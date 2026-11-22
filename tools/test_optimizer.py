"""Run the CraftPath optimizer outside WoW using Wowhead's average prices.

Usage (needs `pip install lupa`):  python test_optimizer.py [from] [to] [mode] [Profession]
"""
import os
import sys

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..")

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute("ns = {}")
import glob
for f in sorted(os.path.basename(x) for x in glob.glob(os.path.join(ADDON, "Data_*.lua"))) + ["Optimizer.lua"]:
    src = open(os.path.join(ADDON, f), encoding="utf-8").read()
    lua.execute("local chunk = ...; chunk('CraftPath', ns)", lua.eval("loadstring")(src))

frm = int(sys.argv[1]) if len(sys.argv) > 1 else 1
to = int(sys.argv[2]) if len(sys.argv) > 2 else 300
mode = sys.argv[3] if len(sys.argv) > 3 else "cheap"
prof = sys.argv[4] if len(sys.argv) > 4 else "Blacksmithing"

result = lua.execute(f"""
local function price(id)
  local v = ns.VendorSeed[id]
  if v then return v, "vendor" end
  local it = ns.Items[id]
  if it and it[2] and it[2] > 0 then return it[2], "estimate" end
end
local function planPrice(r)
  if not r.vendors then return nil end
  local best
  for _, v in ipairs(r.vendors) do
    if v[2] > 0 and (v[4] == 3 or v[4] == 1) and (not best or v[2] < best) then best = v[2] end
  end
  if best then return best, "Vendor" end
end
local t = os.clock()
local res = ns.Optimizer.Run({{
  prof = ns.Professions["{prof}"], from = {frm}, to = {to}, mode = "{mode}",
  craftValue = 2000, switchCost = 0, price = price, planPrice = planPrice,
  known = {{}}, specs = {{}}, faction = 1, sellBack = true,
}})
res.elapsed = os.clock() - t
return res
""")


def money(c):
    c = int(round(c))
    g, s, cp = c // 10000, (c // 100) % 100, c % 100
    return (f"{g}g " if g else "") + (f"{s}s " if g or s else "") + f"{cp}c"


if not result.ok:
    print("STUCK at", result.stuckAt)
    sys.exit(1)
print(f"{len(list(result.cands.values()))} candidate recipes, solved in {result.elapsed*1000:.0f} ms")
for st in result.steps.values():
    print(f"{st['from']:>3} -> {st['to']:<3} {st.recipe.name:<32} x{st.crafts:<3} (safe {st.safe:<3}) "
          f"mats {money(st.cost):>14}  learn {st.learnHow} {money(st.learnCost)}{'  *est' if st.estimate else ''}")
t = result.totals
print("crafts", t.crafts, "| materials", money(t.materials), "| learn", money(t.learn),
      "| sell back", money(t.sellBack), "| total", money(t.total))
print("\nShopping:")
for e in list(result.shopping.values())[:15]:
    name = lua.eval(f"(ns.Items[{e.id}] or {{'?'}})[1]")
    print(f"  {name:<28} {e.qty:>5} (safe {e.safe:>5}) @ {money(e.unit or 0):>10} [{e.how}] = {money(e.total)}")
print("Reused from earlier steps (item ids):", ", ".join(f"{u.qty} x {u.id}" for u in result.reused.values()) or "none")
print("Intermediates:")
for cr in result.intermediates.values():
    print(f"  craft {cr.crafts} x {cr.recipe.name}")
