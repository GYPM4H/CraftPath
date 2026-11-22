"""List vendor recipe items that appear on routes but have no named vendor in
the data, so their vendor/zone/price can be fetched from Wowhead.

Usage (needs `pip install lupa`):  python route_vendor_plans.py > missing_vendor_plans.json
"""
import glob
import json
import os

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..")

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute("ns = {}")
for f in sorted(os.path.basename(x) for x in glob.glob(os.path.join(ADDON, "Data_*.lua"))) + ["Optimizer.lua"]:
    src = open(os.path.join(ADDON, f), encoding="utf-8").read()
    lua.execute("local chunk = ...; chunk('CraftPath', ns)", lua.eval("loadstring")(src))

found = lua.execute("""
local out = {}
local function price(id)
  local v = ns.VendorSeed[id]
  if v then return v, "vendor" end
  local it = ns.Items[id]
  if it and it[2] and it[2] > 0 then return it[2], "ah" end
end
local function planPrice(r)
  if not r.vendors then return nil end
  for _, v in ipairs(r.vendors) do if v[2] > 0 then return v[2], "Vendor" end end
end
for key, prof in pairs(ns.Professions) do
  for _, mode in ipairs({ "cheap", "balanced", "fast" }) do
    for _, from in ipairs({ 1, 50, 100, 150, 200, 250 }) do
      for _, faction in ipairs({ 1, 2 }) do
        local res = ns.Optimizer.Run({ prof = prof, from = from, to = 300, mode = mode, craftValue = 2000,
          price = price, planPrice = planPrice, known = {}, specs = {}, faction = faction, sellBack = true })
        if res.ok then
          for _, st in ipairs(res.steps) do
            local r = st.recipe
            if r.plan and r.vendors and st.learnHow == "Vendor" then
              local named = false
              for _, v in ipairs(r.vendors) do if v[1] ~= "vendor" and v[6] ~= "" then named = true end end
              if not named then out[r.plan] = key .. ": " .. r.name end
            end
          end
        end
      end
    end
  end
end
return out
""")
result = {int(k): v for k, v in found.items()}
print(json.dumps(result, indent=1, sort_keys=True))
