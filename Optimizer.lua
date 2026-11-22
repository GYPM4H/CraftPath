-- CraftPath optimizer: finds the cheapest / fastest sequence of recipes to
-- level a profession from the current skill to a target skill.
--
-- Pure Lua (no WoW API) so it can be tested outside the game.
local _, ns = ...
ns = ns or {}

local Opt = {}
ns.Optimizer = Opt

local floor, ceil, sqrt, min, max = math.floor, math.ceil, math.sqrt, math.min, math.max
local INF = math.huge
local Z90 = 1.2816 -- 90th percentile of a normal distribution

-- Skill-up model (Blizzard never published one):
--   orange: always, gray: never,
--   yellow: 100% at the start of yellow, falling to 50% where green starts,
--   green: 50% falling to 0% at gray.
-- For the usual recipe (green halfway between yellow and gray) this is
-- exactly the community formula (gray - skill) / (gray - yellow); for the
-- rest it keeps the chance in line with the colour the game shows, so a
-- green recipe never reads as a likely skill-up.
function Opt.Chance(recipe, skill)
  local c = recipe.c
  if skill < recipe.learn then return nil end
  local yellow, green, gray = c[2], c[3], c[4]
  if skill >= gray then return 0 end
  if skill < yellow then return 1 end
  if gray <= yellow then return 0 end
  if not green or green <= yellow or green >= gray then green = (yellow + gray) / 2 end
  if skill < green then return 1 - 0.5 * (skill - yellow) / (green - yellow) end
  return 0.5 * (gray - skill) / (gray - green)
end

-- Average number of items one craft makes (at least 1).
function Opt.Yield(r)
  if not r.make then return 1 end
  return max(1, ((r.make[2] or 1) + (r.make[3] or 1)) / 2)
end

-- opts:
--   prof          profession table (ns.Professions[...])
--   from, to      skill range
--   mode          "cheap" | "fast" | "balanced"
--   craftValue    copper one craft is "worth" in balanced mode
--   switchCost    extra cost (copper, or crafts in fast mode) per recipe change
--   price(item)   -> unitPrice|nil, sourceTag      (market price incl. vendor)
--   planPrice(r)  -> price|nil, howText            (cost to obtain an unknown plan)
--   known         set of recipe ids already known
--   knownComplete true when `known` was read from the profession window, so
--                 starter recipes missing from it really are unknown
--   specs         set of specialization spell ids the character has
--   faction       1 Alliance, 2 Horde (filters vendor plans)
--   sellBack      subtract vendor sell value of the product
--   sellPrice(id) -> vendor sell price (from the game); falls back to the data
--   allowQuest    treat quest-only plans as obtainable (free)
function Opt.Run(opts)
  local prof, from, to = opts.prof, opts.from, opts.to
  local mode = opts.mode or "cheap"
  local items = opts.items or ns.Items or {}
  local known = opts.known or {}
  local specs = opts.specs or {}
  local function sellPrice(id)
    local p = opts.sellPrice and opts.sellPrice(id)
    if p then return p end
    local it = items[id]
    return it and it[3] or 0
  end

  ---------------------------------------------------------------- item cost
  -- unit cost of an item: min(market, crafting it with this profession)
  local makers = {}
  for _, r in ipairs(prof.recipes) do
    if r.make then
      local id = r.make[1]
      makers[id] = makers[id] or {}
      table.insert(makers[id], r)
    end
  end

  local function isKnown(r)
    return known[r.id] or (r.src:find("s") and not opts.knownComplete)
  end

  local memo, visiting = {}, {}
  local itemCost -- forward

  local function recipeMatCost(r, maxLearn)
    local total, flags = 0, {}
    for _, rg in ipairs(r.reag) do
      local unit, how = itemCost(rg[1], maxLearn)
      if not unit then return nil, rg[1] end
      total = total + unit * rg[2]
      if how == "estimate" then flags.estimate = true end
    end
    return total, nil, flags
  end

  -- returns unitCost, how ("ah","vendor","auctionator","estimate","craft"), craftRecipe
  function itemCost(id, maxLearn)
    local key = id .. ":" .. (maxLearn or 0)
    local m = memo[key]
    if m then return m[1], m[2], m[3] end
    local best, how, via = opts.price(id)
    if not visiting[id] and makers[id] then
      visiting[id] = true
      for _, r in ipairs(makers[id]) do
        -- only intermediates you can make by the time you need them
        local usable = (isKnown(r) or r.src:find("[st]")) and (not maxLearn or r.learn <= maxLearn)
        if usable then
          local mat = recipeMatCost(r, r.learn)
          if mat then
            local unit = mat / Opt.Yield(r)
            if not best or unit < best then best, how, via = unit, "craft", r end
          end
        end
      end
      visiting[id] = nil
    end
    memo[key] = { best, how, via }
    return best, how, via
  end

  ------------------------------------------------------- recipe availability
  local cands, skipped = {}, {}
  for _, r in ipairs(prof.recipes) do
    local ok, why, learnCost, learnHow = true, nil, 0, nil
    if r.c[4] <= from or r.learn >= to then
      ok, why = false, "range"
    elseif r.spec and not specs[r.spec] then
      ok, why = false, "spec"
    elseif known[r.id] then
      learnHow = "known"
    elseif r.src:find("s") and not opts.knownComplete then
      learnHow = "starter"
    else
      local opts_ = {}
      if r.src:find("[ts]") then table.insert(opts_, { r.cost or 0, "Trainer" }) end
      local pp, phow
      if opts.planPrice then pp, phow = opts.planPrice(r) end
      if pp then table.insert(opts_, { pp, phow }) end
      if r.src:find("q") and opts.allowQuest then table.insert(opts_, { 0, "Quest" }) end
      if #opts_ == 0 then
        ok, why = false, "plan"
      else
        table.sort(opts_, function(a, b) return a[1] < b[1] end)
        learnCost, learnHow = opts_[1][1], opts_[1][2]
      end
    end
    local mat, missing, flags
    if ok then
      mat, missing, flags = recipeMatCost(r, r.learn)
      if not mat then ok, why = false, "price:" .. tostring(missing) end
    end
    if ok then
      local back = 0
      if opts.sellBack and r.make then
        back = sellPrice(r.make[1]) * Opt.Yield(r)
      end
      table.insert(cands, {
        r = r, mat = mat, net = max(0, mat - back), back = back,
        learnCost = learnCost, learnHow = learnHow, estimate = flags and flags.estimate,
      })
    else
      skipped[r.id] = why
    end
  end

  ---------------------------------------------------------------- the DP
  -- f[s][i]: best score to reach skill s with the last point made by cand i.
  local craftValue = opts.craftValue or 0
  local switchCost = opts.switchCost or 0
  local function stepScore(c, crafts)
    if mode == "fast" then return crafts + crafts * c.net * 1e-9 end
    if mode == "balanced" then return crafts * (c.net + craftValue) end
    return crafts * c.net
  end
  local function learnScore(c)
    if mode == "fast" then return switchCost + c.learnCost * 1e-9 end
    return c.learnCost + switchCost
  end

  local n = #cands
  local f, back = {}, {}
  f[from] = {}
  local bestAt, bestIdx = { [from] = 0 }, {}
  for s = from + 1, to do
    local prev, cur, bk = f[s - 1], {}, {}
    local pBest = bestAt[s - 1]
    local bv, bi = INF, nil
    for i = 1, n do
      local c = cands[i]
      local p = Opt.Chance(c.r, s - 1)
      if p and p > 0 then
        local stay = prev[i] or INF
        local switch = pBest + learnScore(c)
        local base, from_ = stay, true
        if switch < stay then base, from_ = switch, false end
        if base < INF then
          local v = base + stepScore(c, 1 / p)
          cur[i], bk[i] = v, from_
          if v < bv then bv, bi = v, i end
        end
      end
    end
    if not bi then
      return { ok = false, stuckAt = s - 1, skipped = skipped, cands = cands }
    end
    f[s], back[s], bestAt[s], bestIdx[s] = cur, bk, bv, bi
  end

  -------------------------------------------------------- reconstruct path
  local seq = {} -- seq[s] = cand index for the point s-1 -> s
  local i = bestIdx[to]
  for s = to, from + 1, -1 do
    seq[s] = i
    if not back[s][i] then i = bestIdx[s - 1] end
  end

  local steps, learned = {}, {}
  local s = from + 1
  while s <= to do
    local ci, e = seq[s], s
    while e + 1 <= to and seq[e + 1] == ci do e = e + 1 end
    local c = cands[ci]
    local mean, var = 0, 0
    for k = s - 1, e - 1 do
      local p = Opt.Chance(c.r, k)
      mean = mean + 1 / p
      var = var + (1 - p) / (p * p)
    end
    local crafts = ceil(mean - 1e-9)
    local safe = max(crafts, ceil(mean + Z90 * sqrt(var) - 1e-9))
    local learnCost, mustLearn = 0, false
    if not learned[c.r.id] then
      learnCost, learned[c.r.id] = c.learnCost, true
      mustLearn = c.learnHow ~= "known" and c.learnHow ~= "starter"
    end
    table.insert(steps, {
      recipe = c.r, from = s - 1, to = e, mean = mean, crafts = crafts, safe = safe,
      matPerCraft = c.mat, backPerCraft = c.back, cost = crafts * c.mat,
      learnCost = learnCost, learnHow = c.learnHow, estimate = c.estimate,
      mustLearn = mustLearn, -- first use of a recipe you still have to learn
    })
    s = e + 1
  end

  ------------------------------------------------------------ shopping list
  -- Items made by earlier steps are used first when a later step needs them
  -- (instead of selling them and buying the same thing again).
  local shop, crafted, pool, reused = {}, {}, {}, {}
  local function need(id, qty, maxLearn, safeQty)
    local have = pool[id] or 0
    if have > 0 then
      local take = min(have, qty)
      pool[id] = have - take
      reused[id] = (reused[id] or 0) + take
      qty, safeQty = qty - take, max(0, safeQty - take)
      if qty <= 0 and safeQty <= 0 then return end
    end
    local unit, how, via = itemCost(id, maxLearn)
    if how == "craft" and via then
      local yield = Opt.Yield(via)
      local n_, ns_ = ceil(qty / yield - 1e-9), ceil(safeQty / yield - 1e-9)
      local cr = crafted[via.id] or { recipe = via, crafts = 0, safe = 0 }
      cr.crafts, cr.safe = cr.crafts + n_, cr.safe + ns_
      crafted[via.id] = cr
      for _, rg in ipairs(via.reag) do need(rg[1], rg[2] * n_, via.learn, rg[2] * ns_) end
    else
      local e = shop[id] or { id = id, qty = 0, safe = 0, unit = unit, how = how }
      e.qty, e.safe = e.qty + qty, e.safe + safeQty
      shop[id] = e
    end
  end
  for _, st in ipairs(steps) do
    for _, rg in ipairs(st.recipe.reag) do
      need(rg[1], rg[2] * st.crafts, st.recipe.learn, rg[2] * st.safe)
    end
    if st.recipe.make then
      local id = st.recipe.make[1]
      pool[id] = (pool[id] or 0) + st.crafts * Opt.Yield(st.recipe)
    end
  end
  local reusedList, reusedBack = {}, 0
  for id, qty in pairs(reused) do
    local q = floor(qty + 1e-9)
    if q > 0 then table.insert(reusedList, { id = id, qty = q }) end
    reusedBack = reusedBack + qty * sellPrice(id) -- not sold after all
  end
  table.sort(reusedList, function(a, b) return a.qty > b.qty end)
  local shopList, craftList = {}, {}
  local totalMat, totalSafe, totalLearn, totalCrafts, totalBack = 0, 0, 0, 0, 0
  for _, e in pairs(shop) do
    e.total = e.qty * (e.unit or 0)
    totalMat, totalSafe = totalMat + e.total, totalSafe + e.safe * (e.unit or 0)
    table.insert(shopList, e)
  end
  table.sort(shopList, function(a, b) return a.total > b.total end)
  for _, cr in pairs(crafted) do
    cr.mustLearn = not isKnown(cr.recipe)
    table.insert(craftList, cr)
  end
  table.sort(craftList, function(a, b) return a.recipe.learn < b.recipe.learn end)
  for _, st in ipairs(steps) do
    totalLearn = totalLearn + st.learnCost
    totalCrafts = totalCrafts + st.crafts
    totalBack = totalBack + st.crafts * st.backPerCraft
  end
  if opts.sellBack then totalBack = max(0, totalBack - reusedBack) end

  return {
    ok = true, from = from, to = to, mode = mode, steps = steps,
    shopping = shopList, intermediates = craftList, reused = reusedList,
    totals = {
      materials = totalMat, materialsSafe = totalSafe, learn = totalLearn,
      crafts = totalCrafts, sellBack = totalBack,
      total = totalMat + totalLearn - (opts.sellBack and totalBack or 0),
    },
    skipped = skipped, cands = cands,
    itemCost = itemCost, -- (id, maxLearn) -> unit, how, craftRecipe
  }
end

return Opt
