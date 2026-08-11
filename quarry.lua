--[[ ------------------------------------------------------------
  quarry.lua  -  3-layer strip quarry for CC: Tweaked mining turtles

  Usage:   quarry <size> [maxDepth]
  Example: quarry 16          -- 16x16 down to bedrock
           quarry 16 40       -- 16x16, stop 40 blocks down

  Setup:   chest BEHIND the turtle, turtle facing into the area.
           The square extends FORWARD and to the RIGHT.

  vs. the built-in excavate:
    * travels on every 3rd layer, digging up + down  -> ~3x fewer moves
    * voids junk stone on the spot                   -> ~10x fewer trips
    * refuels itself from mined coal
    * keeps one fuel stack when it unloads
------------------------------------------------------------ ]]

local args = { ... }
local size = tonumber(args[1])
local maxDepth = tonumber(args[2]) or 4096

if not size or size < 1 then
  print("Usage: quarry <size> [maxDepth]")
  return
end

-- ---------------------------------------------------------------
-- JUNK LIST - dropped on the spot. Edit freely.
-- Deliberately NOT here: tuff, asurine, crimsite, ochrum, veridium
-- (Create crushes all five into metal nuggets) and coal.
-- ---------------------------------------------------------------
local junk = {
  ["minecraft:cobblestone"]      = true,
  ["minecraft:stone"]            = true,
  ["minecraft:cobbled_deepslate"]= true,
  ["minecraft:deepslate"]        = true,
  ["minecraft:granite"]          = true,
  ["minecraft:diorite"]          = true,
  ["minecraft:andesite"]         = true,
  ["minecraft:dirt"]             = true,
  ["minecraft:coarse_dirt"]      = true,
  ["minecraft:rooted_dirt"]      = true,
  ["minecraft:grass_block"]      = true,
  ["minecraft:podzol"]           = true,
  ["minecraft:gravel"]           = true,
  ["minecraft:sand"]             = true,
  ["minecraft:red_sand"]         = true,
  ["minecraft:sandstone"]        = true,
  ["minecraft:calcite"]          = true,
  ["minecraft:basalt"]           = true,
  ["minecraft:smooth_basalt"]    = true,
  ["minecraft:dripstone_block"]  = true,
  ["minecraft:pointed_dripstone"]= true,
  ["minecraft:moss_block"]       = true,
  ["minecraft:mud"]              = true,
  ["minecraft:clay"]             = true,
  ["minecraft:magma_block"]      = true,
  ["minecraft:obsidian"]         = false, -- keep obsidian
}

-- ---------------------------------------------------------------
-- position tracking (relative to start)
--   x = right,  z = forward,  y = up
-- ---------------------------------------------------------------
local pos     = { x = 0, y = 0, z = 0 }
local facing  = 0                     -- 0 fwd, 1 right, 2 back, 3 left
local delta   = { [0]={0,1}, [1]={1,0}, [2]={0,-1}, [3]={-1,0} }
local mined   = 0

local function turnRight() turtle.turnRight(); facing = (facing + 1) % 4 end
local function turnLeft()  turtle.turnLeft();  facing = (facing + 3) % 4 end

local function face(d)
  if (facing + 1) % 4 == d then turnRight()
  else while facing ~= d do turnLeft() end end
end

-- ---------------------------------------------------------------
-- fuel
-- ---------------------------------------------------------------
local function costHome()
  return math.abs(pos.x) + math.abs(pos.z) + math.abs(pos.y) + 10
end

local function ensureFuel(target)
  if turtle.getFuelLevel() == "unlimited" then return true end
  if turtle.getFuelLevel() >= target then return true end
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      if turtle.refuel(0) then
        while turtle.getFuelLevel() < target and turtle.getItemCount(slot) > 0 do
          turtle.refuel(1)
        end
      end
    end
    if turtle.getFuelLevel() >= target then break end
  end
  turtle.select(1)
  return turtle.getFuelLevel() >= target
end

-- ---------------------------------------------------------------
-- movement (digs through obstacles, punches mobs, tracks position)
-- ---------------------------------------------------------------
local function forward()
  local tries = 0
  while not turtle.forward() do
    if turtle.detect() then
      if not turtle.dig() then tries = tries + 1 end
    else
      turtle.attack(); tries = tries + 1
    end
    if tries > 40 then return false end
    sleep(0.2)
  end
  local d = delta[facing]
  pos.x = pos.x + d[1]
  pos.z = pos.z + d[2]
  return true
end

local function down()
  local tries = 0
  while not turtle.down() do
    if turtle.detectDown() then
      if not turtle.digDown() then return false end   -- bedrock
    else
      turtle.attackDown(); tries = tries + 1
    end
    if tries > 40 then return false end
    sleep(0.2)
  end
  pos.y = pos.y - 1
  return true
end

local function up()
  local tries = 0
  while not turtle.up() do
    if turtle.detectUp() then
      if not turtle.digUp() then tries = tries + 1 end
    else
      turtle.attackUp(); tries = tries + 1
    end
    if tries > 40 then return false end
    sleep(0.2)
  end
  pos.y = pos.y + 1
  return true
end

-- ---------------------------------------------------------------
-- inventory
-- ---------------------------------------------------------------
local function freeSlots()
  local n = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) == 0 then n = n + 1 end
  end
  return n
end

local function dumpJunk()
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and junk[item.name] then
      turtle.select(slot)
      turtle.dropDown()
    end
  end
  turtle.select(1)
end

-- go to a point. rises first, moves flat, then descends - the whole
-- cleared column is open, so this never needs to dig.
local function goTo(tx, ty, tz)
  while pos.y < ty do if not up() then return false end end
  if pos.x ~= tx then
    face(pos.x < tx and 1 or 3)
    while pos.x ~= tx do if not forward() then return false end end
  end
  if pos.z ~= tz then
    face(pos.z < tz and 0 or 2)
    while pos.z ~= tz do if not forward() then return false end end
  end
  while pos.y > ty do if not down() then return false end end
  return true
end

local function unload()
  local wx, wy, wz, wf = pos.x, pos.y, pos.z, facing
  print("Full - returning to unload (" .. mined .. " blocks so far)")
  if not goTo(0, 0, 0) then error("lost on the way home", 0) end
  face(2)                                   -- chest sits behind the start
  local keptFuel = false
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      if not keptFuel and turtle.refuel(0) then
        keptFuel = true                     -- keep one fuel stack aboard
      else
        turtle.drop()
      end
    end
  end
  turtle.select(1)
  goTo(wx, wy, wz)
  face(wf)
end

-- ---------------------------------------------------------------
-- digging
-- ---------------------------------------------------------------
local function clearUp()
  local guard = 0
  while turtle.detectUp() and guard < 16 do
    if not turtle.digUp() then return end
    mined = mined + 1
    guard = guard + 1
  end
end

local function clearDown()
  if turtle.detectDown() then
    if turtle.digDown() then mined = mined + 1 end
  end
end

local function cell()
  clearUp()
  clearDown()
  if freeSlots() < 3 then dumpJunk() end
  if freeSlots() == 0 then unload() end
  if not ensureFuel(costHome() + 100) then
    print("Out of fuel - heading home.")
    goTo(0, 0, 0); face(2)
    error("no fuel", 0)
  end
end

-- sweep the size x size square at the current level
local function sweep()
  local shiftRight = true
  for row = 1, size do
    for col = 1, size do
      cell()
      if col < size then
        if not forward() then break end
      end
    end
    if row < size then
      if shiftRight then
        turnRight(); forward(); turnRight()
      else
        turnLeft();  forward(); turnLeft()
      end
      shiftRight = not shiftRight
    end
  end
end

-- ---------------------------------------------------------------
-- main
-- ---------------------------------------------------------------
print("Quarry " .. size .. "x" .. size .. " starting.")
ensureFuel(1000)

if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < 100 then
  print("Put some coal in me first, then run again.")
  return
end

if not down() then
  print("Can't dig down here.")
  return
end

while true do
  sweep()
  goTo(0, pos.y, 0)
  face(0)

  if -pos.y >= maxDepth then
    print("Reached max depth.")
    break
  end

  local dropped = 0
  for _ = 1, 3 do
    if down() then dropped = dropped + 1 else break end
  end
  if dropped == 0 then
    print("Bedrock reached.")
    break
  end
end

goTo(0, 0, 0)
face(2)
local keptFuel = false
for slot = 1, 16 do
  if turtle.getItemCount(slot) > 0 then
    turtle.select(slot)
    if not keptFuel and turtle.refuel(0) then keptFuel = true else turtle.drop() end
  end
end
turtle.select(1)
face(0)
print("Done. Blocks broken: " .. mined)
