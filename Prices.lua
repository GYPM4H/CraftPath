-- CraftPath prices: own AH scans, Auctionator, vendor prices. No estimates:
-- until you scan (or Auctionator has data) the planner waits for a first scan.
-- Works with the modern client (C_AuctionHouse, used by WoW Forever) and
-- falls back to the classic AH API if that is what the client has.
local ADDON, ns = ...

local Prices = {}
ns.Prices = Prices

local FRESH = 48 * 3600 -- own scans younger than this beat Auctionator
local TIMEOUT = 6       -- seconds to wait for one search result

local function realmKey()
  return (GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?")
end

function Prices:Realm()
  local db = ns.db
  local key = realmKey()
  db.realms[key] = db.realms[key] or { ah = {} }
  return db.realms[key]
end

-- Price from the Auctionator addon, if installed.
local function auctionatorPrice(id)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.GetAuctionPriceByItemID) then return nil end
  local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, id)
  if ok and type(price) == "number" and price > 0 then return price end
end

-- Days since Auctionator last saw the item (0 = today), or nil if unknown.
local function auctionatorAge(id)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.GetAuctionAgeByItemID) then return nil end
  local ok, days = pcall(api.GetAuctionAgeByItemID, ADDON, id)
  if ok and type(days) == "number" and days >= 0 then return days end
end

local DAY = 86400

-- Market price for an auction item (no vendor): the newest of our own scan
-- and Auctionator. Auctionator only knows ages in whole days, so we compare
-- days; on the same day our scan wins (it accounts for listed quantity).
-- Returns price, tag ("ah" | "auctionator"), age in seconds (nil if unknown).
function Prices:AuctionPrice(id)
  local own = self:Realm().ah[id]
  local now = time()
  local a = ns.settings.useAuctionator and auctionatorPrice(id)
  local aDays = a and auctionatorAge(id)

  if own then
    local ownAge = now - own.t
    local ownDays = math.floor(ownAge / DAY)
    -- Auctionator has a strictly newer day (or we can't date it and ours is stale)
    local aNewer = a and ((aDays and aDays < ownDays) or (not aDays and ownAge >= FRESH))
    if aNewer then return a, "auctionator", aDays and aDays * DAY end
    -- our scan found nothing listed, and nothing newer says otherwise
    if own.none then return nil end
    return own.p, "ah", ownAge
  end
  if a then return a, "auctionator", aDays and aDays * DAY end
end

-- "CraftPath scan, 3 h ago" / "Auctionator, today" / "Vendor"
local function ageText(sec, days)
  if not sec then return "date unknown" end
  if days then
    local d = math.floor(sec / DAY)
    return d == 0 and "today" or d == 1 and "yesterday" or (d .. " days ago")
  end
  if sec < 3600 then return ("%d min ago"):format(math.max(1, math.floor(sec / 60))) end
  if sec < DAY then return ("%d h ago"):format(math.floor(sec / 3600)) end
  local d = math.floor(sec / DAY)
  return d == 1 and "1 day ago" or (d .. " days ago")
end

function Prices:SourceText(id, how)
  if how == "vendor" then return "Vendor" end
  if how == "craft" then return "Craft it yourself" end
  if how == "ah" or how == "auctionator" then
    local _, tag, age = self:AuctionPrice(id)
    if tag == "auctionator" then return "Auctionator, " .. ageText(age, true) end
    local own = self:Realm().ah[id]
    if tag == "ah" and own then
      return ("CraftPath scan, %s  ·  %d listed"):format(ageText(age), own.n or 0)
    end
  end
  return how or "?"
end

-- How much real price data is there for the current profession's materials?
-- Returns: items with our own scan, items with an Auctionator price, items
-- with either (seen or listed-as-none), total items.
function Prices:Coverage()
  local own, auc, either, n = 0, 0, 0, 0
  local ah = self:Realm().ah
  local useAuc = ns.settings.useAuctionator
  for id in pairs(ns.FullScanList()) do
    if not ns.IsPlan(id) then -- recipe items are rarely on the AH; count materials
    n = n + 1
    local o = ah[id]
    local a = useAuc and auctionatorPrice(id)
    if o and not o.none then own = own + 1 end
    if a then auc = auc + 1 end
    if o or a then either = either + 1 end -- "none listed" also counts as known
    end
  end
  return own, auc, either, n
end

-- What a vendor pays you for an item, straight from the game (cached).
-- nil when the client hasn't loaded the item yet: the planner then uses the
-- data file, and asks the client to load it for next time.
function Prices:SellPrice(id)
  local cached = ns.db.sell[id]
  if cached then return cached end
  local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not getItemInfo then return nil end
  local sell = select(11, getItemInfo(id))
  if type(sell) == "number" then
    ns.db.sell[id] = sell
    return sell
  end
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

function Prices:VendorPrice(id)
  local v = ns.db.vendor[id]
  if v then return v.p, "vendor" end
  local seed = ns.VendorSeed[id]
  if seed then return seed, "vendor" end
end

-- Cheapest way to buy one unit of a reagent.
function Prices:Get(id)
  local vp, vtag = self:VendorPrice(id)
  local ap, atag = self:AuctionPrice(id)
  if vp and (not ap or vp <= ap) then return vp, vtag end
  return ap, atag
end

-- Cheapest way to obtain an unknown plan (vendor or AH). Trainer cost is
-- handled by the optimizer from the data file.
function Prices:Plan(r)
  local best, how
  local faction = ns.FactionMask()
  local seen = r.plan and ns.db.vendor[r.plan]
  if seen then best, how = seen.p, "Vendor" end
  if not best and r.vendors then
    for _, v in ipairs(r.vendors) do
      local name, price, side = v[1], v[2], v[4]
      if price > 0 and bit.band(side, faction) ~= 0 and (not best or price < best) then
        best, how = price, "Vendor (" .. name .. ")" .. (v[5] == 1 and " (approx.)" or "")
      end
    end
  end
  if r.plan then
    -- plans on the AH: newest of our scan and Auctionator, like materials
    local ap = self:AuctionPrice(r.plan)
    if ap and (not best or ap < best) then best, how = ap, "Auction House" end
  end
  return best, how
end

------------------------------------------------------------------ vendors
local function merchantInfo(i)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local info = C_MerchantFrame.GetItemInfo(i)
    if info then return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
  end
  if GetMerchantItemInfo then
    local _, _, price, quantity, numAvailable, _, _, extendedCost = GetMerchantItemInfo(i)
    return price, quantity, numAvailable, extendedCost
  end
end

-- Remember what vendors sell for (only items we care about).
function Prices:ScanMerchant()
  local wanted = ns.WantedItems()
  local n = GetMerchantNumItems and GetMerchantNumItems() or 0
  local found = 0
  for i = 1, n do
    local link = GetMerchantItemLink(i)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id and (wanted[id] or ns.Items[id] or ns.IsPlan(id)) then
      local price, quantity, numAvailable, extendedCost = merchantInfo(i)
      if price and price > 0 and not extendedCost then
        ns.db.vendor[id] = { p = price / math.max(1, quantity or 1), limited = numAvailable and numAvailable >= 0 or nil }
        if ns.IsPlan(id) then
          ns.db.planVendor[id] = { name = UnitName and UnitName("npc") or "vendor",
            zone = GetRealZoneText and GetRealZoneText() or "" }
        end
        found = found + 1
      end
    end
  end
  if found > 0 then ns.Refresh() end
end

---------------------------------------------------------------- AH scan
-- Stores a market price for an item: the average unit price of the
-- cheapest 30% of what's listed (so one cheap single listing doesn't
-- fool the planner), plus the minimum.
local function storeListings(id, list)
  if #list == 0 then
    Prices:Realm().ah[id] = { none = true, t = time() }
    return
  end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  local total = 0
  for _, l in ipairs(list) do total = total + l[2] end
  local want = math.max(1, math.ceil(total * 0.3))
  local got, spent = 0, 0
  for _, l in ipairs(list) do
    local take = math.min(l[2], want - got)
    spent, got = spent + take * l[1], got + take
    if got >= want then break end
  end
  Prices:Realm().ah[id] = { p = math.floor(spent / got + 0.5), m = list[1][1], n = total, t = time() }
end
Prices.StoreListings = storeListings -- for tests

local MODERN = C_AuctionHouse and C_AuctionHouse.SendSearchQuery and true or false

local scanner = CreateFrame("Frame")
local queue, current, listings, sentAt, page, onDone
local MAX_ROUNDS = 6
local run -- { mode = "smart"|"full", done = {itemId=true}, round = n, count = n }

local function finish(msg)
  scanner:SetScript("OnUpdate", nil)
  scanner:UnregisterAllEvents()
  queue, current, sentAt, run = nil, nil, nil, nil
  Prices.scanning = false
  ns.SetStatus(msg)
  ns.Refresh()
  if onDone then onDone() end
end

local function nextItem()
  current = queue and table.remove(queue, 1)
  listings, page = {}, 0
  if current then
    run.done[current] = true
    run.count = run.count + 1
    ns.SetStatus(("%s round %d: %s (%d left)"):format(run.mode == "full" and "Full scan" or "Scan",
      run.round, ns.ItemName(current), #queue))
  end
  return current
end

-- Items to scan in the next round: what the (re-planned) routes now use
-- that this run hasn't looked at yet.
local function nextRound()
  local list = ns.ScanListAll(run.mode == "full" and "full" or "smart")
  queue = {}
  for id in pairs(list) do
    if not run.done[id] then table.insert(queue, id) end
  end
  table.sort(queue)
  return #queue
end

local function doneWithItem(timedOut)
  if not timedOut then storeListings(current, listings) end -- keep old price on timeout
  sentAt = nil
  if nextItem() then return end
  -- round finished: new prices may change the route; scan anything new it uses
  if run.round < MAX_ROUNDS and nextRound() > 0 then
    run.round = run.round + 1
    nextItem()
    return
  end
  finish(("Scan complete: %d items, %d round%s - route is up to date."):format(
    run.count, run.round, run.round == 1 and "" or "s"))
end

-- modern client --------------------------------------------------------
local SORT = { { sortOrder = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }

local function modernSend()
  if not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
  C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(current), SORT, false)
  sentAt = GetTime()
end

local function readCommodity(id)
  for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(id) do
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
    if info and info.unitPrice and info.quantity and info.quantity > 0 then
      table.insert(listings, { info.unitPrice, info.quantity })
    end
  end
end

local function readItems(key)
  for i = 1, C_AuctionHouse.GetNumItemSearchResults(key) do
    local info = C_AuctionHouse.GetItemSearchResultInfo(key, i)
    local q = info and (info.quantity or 1) or 0
    if info and info.buyoutAmount and q > 0 then
      table.insert(listings, { info.buyoutAmount / q, q })
    end
  end
end

-- classic client --------------------------------------------------------
local function classicSend()
  if not CanSendAuctionQuery() then return end
  pcall(QueryAuctionItems, (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(current)) or ns.ItemName(current),
    nil, nil, page, false, nil, false, true)
  sentAt = GetTime()
end

local function readClassic()
  local batch, total = GetNumAuctionItems("list")
  for i = 1, batch do
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemId = GetAuctionItemInfo("list", i)
    if itemId == current and buyout and buyout > 0 and count and count > 0 then
      table.insert(listings, { buyout / count, count })
    end
  end
  return batch, total
end

-- driver ----------------------------------------------------------------
local function itemEvents(_, event, arg)
  if not current or not sentAt then return end
  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" and arg == current then
    readCommodity(current)
    doneWithItem()
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" and type(arg) == "table" and arg.itemID == current then
    readItems(arg)
    doneWithItem()
  elseif event == "AUCTION_ITEM_LIST_UPDATE" then
    local batch, total = readClassic()
    sentAt = nil
    if batch == (NUM_AUCTION_ITEMS_PER_PAGE or 50) and (page + 1) * batch < total and page < 9 then
      page = page + 1
    else
      doneWithItem()
    end
  end
end

local function onUpdate()
  if not ns.atAH then return finish("Scan stopped: Auction House closed.") end
  if sentAt then
    if GetTime() - sentAt > TIMEOUT then doneWithItem(true) end -- no answer: skip
    return
  end
  if MODERN then modernSend() else classicSend() end
end

------------------------------------------------------------ fast scan
-- C_AuctionHouse.ReplicateItems() downloads every auction in one request
-- (what Auctionator's full scan uses). The server allows it once every 15
-- minutes; in between we fall back to item-by-item searches.
local REPLICATE_COOLDOWN = 15 * 60
local REPLICATE_WAIT = 60     -- seconds to wait for the download
local READ_PER_FRAME = 2000   -- auctions read per frame (keeps the game smooth)

local function canReplicate()
  return C_AuctionHouse and C_AuctionHouse.ReplicateItems and C_AuctionHouse.GetNumReplicateItems
    and C_AuctionHouse.GetReplicateItemInfo and true or false
end

-- Seconds until the fast scan can run again (0 = now), or nil if the client
-- doesn't have it.
function Prices:FastScanIn()
  if not canReplicate() then return nil end
  local last = ns.db.replicateAt or 0
  return math.max(0, REPLICATE_COOLDOWN - (time() - last))
end

local fast -- { wanted, lists, i, n, unknown, sentAt }

local function replicateItemId(i)
  local id = select(17, C_AuctionHouse.GetReplicateItemInfo(i))
  if id then return id end
  local link = C_AuctionHouse.GetReplicateItemLink and C_AuctionHouse.GetReplicateItemLink(i)
  return link and tonumber(link:match("item:(%d+)"))
end

local function fastFinish()
  local stored, none = 0, 0
  -- if many auctions couldn't be identified, "not found" isn't trustworthy
  local trustNone = fast.unknown <= fast.n * 0.02
  for id in pairs(fast.wanted) do
    local list = fast.lists[id]
    if list then
      storeListings(id, list)
      stored = stored + 1
    elseif trustNone then
      storeListings(id, {})
      none = none + 1
    end
  end
  local profs, n = table.concat(fast.profs, ", "), fast.n
  fast = nil
  finish(("Fast scan complete: %d auctions read. Prices for %d items (%d not listed) - %s. Next fast scan in 15 min."):format(
    n, stored, none, profs))
end

local function fastOnUpdate()
  if not ns.atAH then fast = nil; return finish("Scan stopped: Auction House closed.") end
  if not fast.n then
    if GetTime() - fast.sentAt > REPLICATE_WAIT then
      -- no answer (server still on cooldown?): scan item by item instead
      local mode = fast.mode
      fast = nil
      scanner:SetScript("OnUpdate", nil)
      scanner:UnregisterAllEvents()
      Prices.scanning = false
      ns.SetStatus("Fast scan didn't answer - scanning item by item instead.")
      Prices:StartScan(onDone, mode, true)
    end
    return
  end
  local stop = math.min(fast.n - 1, fast.i + READ_PER_FRAME - 1)
  for i = fast.i, stop do
    local _, _, count, _, _, _, _, _, _, buyout = C_AuctionHouse.GetReplicateItemInfo(i)
    local id = replicateItemId(i)
    if not id then
      fast.unknown = fast.unknown + 1
    elseif fast.wanted[id] and buyout and buyout > 0 and count and count > 0 then
      local list = fast.lists[id] or {}
      table.insert(list, { buyout / count, count })
      fast.lists[id] = list
    end
  end
  fast.i = stop + 1
  ns.SetStatus(("Fast scan: reading auctions %d / %d"):format(fast.i, fast.n))
  if fast.i >= fast.n then fastFinish() end
end

local function startFast(mode)
  local wanted = ns.ScanListAll("full")
  fast = { wanted = wanted, lists = {}, i = 0, unknown = 0, sentAt = GetTime(), mode = mode,
    profs = ns.ScanProfessions() }
  for i, key in ipairs(fast.profs) do fast.profs[i] = ns.ProfName(ns.Professions[key]) end
  Prices.scanning = true
  Prices.mode = "fast"
  scanner:UnregisterAllEvents()
  scanner:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  scanner:SetScript("OnEvent", function(_, event)
    if event == "REPLICATE_ITEM_LIST_UPDATE" and fast and not fast.n then
      fast.n = C_AuctionHouse.GetNumReplicateItems() or 0
      scanner:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    end
  end)
  scanner:SetScript("OnUpdate", fastOnUpdate)
  ns.db.replicateAt = time()
  ns.SetStatus("Fast scan: downloading the whole Auction House...")
  C_AuctionHouse.ReplicateItems()
end

-- mode "smart" (default): items the best routes use, re-planning after each
-- round until nothing new comes up. "full": every reagent of every recipe you
-- can get between your skill and the target (a few minutes). Both cover all
-- your professions, and both use the fast whole-AH scan when it's available.
function Prices:StartScan(done, mode, noFast)
  if self.scanning then return end
  if not ns.atAH then
    ns.SetStatus("Open the Auction House first.")
    return
  end
  if ns.neutralAH then
    ns.SetStatus(ns.NEUTRAL_MSG)
    return
  end
  onDone = done
  if not noFast and self:FastScanIn() == 0 then return startFast(mode) end
  scanner:SetScript("OnEvent", itemEvents)
  if mode ~= "full" and ns.AnyNeedsFirstScan() then mode = "full" end
  run = { mode = mode == "full" and "full" or "smart", done = {}, round = 1, count = 0 }
  self.mode = run.mode
  if nextRound() == 0 or not nextItem() then
    run = nil
    return ns.SetStatus("Nothing to scan.")
  end
  self.scanning = true
  if MODERN then
    scanner:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
    scanner:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
  else
    scanner:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
  end
  scanner:SetScript("OnUpdate", onUpdate)
end

function Prices:StopScan()
  if self.scanning then fast = nil; finish("Scan stopped.") end
end
