-- ForeverDiff Collector, run outside the game: the stub client API fires the events the addon
-- registers, and this test reads what the addon wrote into `ForeverDiffCollectorDB`.
--
-- The last two checks are what keep the pipeline honest. The addon's own SavedVariables writer is
-- the game's, which nothing here can run, so the test serialises the table the way the game would
-- and asserts the result is the same *shape* as the file the Python ingest test reads
-- (`addon/tests/fixtures/collector.lua`): same sections, same field names,
-- neither side carrying a field the other has never seen. If the addon starts recording something
-- new, or the fixture drifts, one of those two fails.

local here = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local root = here .. "/../.."
package.path = here .. "/?.lua;" .. package.path

local api = require("stub_api")

local failures, checks = 0, 0

local function ok(cond, what)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    io.write("FAIL ", what, "\n")
  end
end

local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    io.write("FAIL ", what, ": got ", tostring(got), ", wanted ", tostring(want), "\n")
  end
end

-- -- serialising, the way the game writes SavedVariables ---------------------------------------

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return n > 0
end

local function sortedKeys(t)
  local numbers, names = {}, {}
  for k in pairs(t) do
    if type(k) == "number" then numbers[#numbers + 1] = k else names[#names + 1] = k end
  end
  table.sort(numbers)
  table.sort(names)
  for _, name in ipairs(names) do numbers[#numbers + 1] = name end
  return numbers
end

local function quoted(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end

local function serialize(value, depth)
  if type(value) ~= "table" then
    return type(value) == "string" and quoted(value) or tostring(value)
  end
  local pad, inner = string.rep("\t", depth), string.rep("\t", depth + 1)
  local out = { "{\n" }
  if isArray(value) then
    for i, v in ipairs(value) do
      out[#out + 1] = inner .. serialize(v, depth + 1) .. ", -- [" .. i .. "]\n"
    end
  else
    for _, k in ipairs(sortedKeys(value)) do
      local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. quoted(k) .. "]")
      out[#out + 1] = inner .. key .. " = " .. serialize(value[k], depth + 1) .. ",\n"
    end
  end
  out[#out + 1] = pad .. "}"
  return table.concat(out)
end

local function loadDB(text, what)
  local chunk, err = loadstring(text .. "\nreturn ForeverDiffCollectorDB")
  if not chunk then
    failures = failures + 1
    io.write("FAIL ", what, " does not parse: ", tostring(err), "\n")
    return nil
  end
  local env = {}
  setfenv(chunk, env)
  return chunk()
end

-- -- shapes ------------------------------------------------------------------------------------

local function mergeShape(a, b)
  if a == nil then return b end
  if b == nil then return a end
  if type(a) == "string" or type(b) == "string" then
    return a == b and a or "mixed"
  end
  for k, v in pairs(b) do a[k] = mergeShape(a[k], v) end
  return a
end

--- Field names only: every key that names an entity - an id, or a typed loot key like
--- `Creature:6` - is the same `*` entry, and its value shapes are merged.
local function shapeOf(value)
  if type(value) ~= "table" then return "scalar" end
  local out = {}
  for k, v in pairs(value) do
    local name = k
    if type(k) == "number" or (type(k) == "string" and k:match("^%a+:%-?%d+$")) then name = "*" end
    out[name] = mergeShape(out[name], shapeOf(v))
  end
  return out
end

local function renderShape(shape, depth)
  if type(shape) == "string" then return shape end
  local pad, out = string.rep("  ", depth), {}
  for _, k in ipairs(sortedKeys(shape)) do
    out[#out + 1] = pad .. k .. ": " .. renderShape(shape[k], depth + 1)
  end
  return "\n" .. table.concat(out, "\n")
end

-- -- the addon under test -----------------------------------------------------------------------

dofile(root .. "/addon/ForeverDiffCollector/ForeverDiffCollector.lua")
api.FireEvent("ADDON_LOADED", "SomeOtherAddon")
api.FireEvent("ADDON_LOADED", "ForeverDiffCollector")

local db = ForeverDiffCollectorDB
ok(db ~= nil, "the addon created its SavedVariables table")
if not db then os.exit(1) end

eq(db.version, 1, "db.version")
eq(db.realm, "Nostalgia", "db.realm")
eq(db.build.version, "1.60.1", "db.build.version")
eq(db.build.build, "69893", "db.build.build")
eq(db.build.interface, 16001, "db.build.interface")

-- -- a quest, start to finish ---------------------------------------------------------------

api.state.units.npc = { guid = "Creature-0-0-0-0-12696-0000ABCDEF", name = "Senani Thunderheart" }
api.state.player = { map = 1440, x = 0.737, y = 0.616 }
api.state.quest = {
  id = 2,
  title = "Sharptalon's Claw",
  description = "The mighty hippogryph Sharptalon has been slain, and his claw taken as a trophy of the hunt.",
  objectives = "Bring Sharptalon's Claw to Senani Thunderheart at Splintertree Post.",
  progress = "Have you brought me the claw of Sharptalon?",
  completion = "Sharptalon is dead, and the Silverwing Sentinels are one enemy lighter.",
  money = 1200,
  xp = 250,
  choices = { "|cffffffff|Hitem:182::::::::60:::::|h[Large Candle]|h|r" },
  rewards = { "|cffffffff|Hitem:647::::::::60:::::|h[Destiny]|h|r" },
}
api.FireEvent("QUEST_DETAIL")

local q = db.quests[2]
ok(q ~= nil, "QUEST_DETAIL recorded quest 2")
eq(q.title, "Sharptalon's Claw", "quest title")
eq(q.description, api.state.quest.description, "quest description")
eq(q.objectives, api.state.quest.objectives, "quest objectives")
eq(q.giver.type, "Creature", "quest giver type from the GUID")
eq(q.giver.id, 12696, "quest giver id from the GUID")
eq(q.giverName, "Senani Thunderheart", "quest giver name")
eq(q.level, nil, "no quest level is recorded (the Classic API does not give one)")
eq(q.pos.map, 1440, "quest position map")
eq(q.pos.x, 0.737, "quest position x")
eq(q.rewards.choices[1], 182, "reward choice item id parsed from the link")
eq(q.rewards.items[1], 647, "reward item id parsed from the link")
eq(q.rewards.money, 1200, "reward money")
eq(q.rewards.xp, 250, "reward xp")
eq(db.items[182], "Large Candle", "the reward choice's name came off the link")
eq(db.items[647], "Destiny", "the reward item's name came off the link")

api.FireEvent("QUEST_PROGRESS")
eq(db.quests[2].progress, api.state.quest.progress, "QUEST_PROGRESS text")

api.state.units.npc = { guid = "Creature-0-0-0-0-12696-0000ABCDEF", name = "Senani Thunderheart" }
api.FireEvent("QUEST_COMPLETE")
eq(db.quests[2].completion, api.state.quest.completion, "QUEST_COMPLETE text")
eq(db.quests[2].ender.id, 12696, "quest ender id")
eq(db.quests[2].enderName, "Senani Thunderheart", "quest ender name")

-- a second quest, seen once and never handed in: it carries what was on screen and nothing else
api.state.units.npc = { guid = "Creature-0-0-0-0-823-0000ABCD01", name = "Innkeeper Farley" }
api.state.player = { map = 1429, x = 0.437, y = 0.658 }
api.state.quest = { id = 500, title = "The Militia Needs Candles",
                    description = "The militia needs thick leather, and the kobolds of Elwynn have hides to spare.",
                    objectives = "Bring 5 Large Candles to Innkeeper Farley.", money = 300, xp = 80,
                    rewards = { "|cffffffff|Hitem:45::::::::60:::::|h[Rat Tail]|h|r" } }
api.FireEvent("QUEST_DETAIL")
eq(db.quests[500].title, "The Militia Needs Candles", "the second quest's title")
eq(db.quests[500].progress, nil, "a quest never handed in has no progress text")

-- -- creatures -------------------------------------------------------------------------------

api.state.player = { map = 1429, x = 0.421, y = 0.604 }
api.state.units.target = { guid = "Creature-0-0-0-0-6-0000AAAA01", name = "Kobold Vermin", level = 2,
                           classification = "normal", creatureType = "Humanoid", reaction = 2,
                           factionGroup = "Neutral" }
api.FireEvent("PLAYER_TARGET_CHANGED")

local n = db.npcs[6]
ok(n ~= nil, "PLAYER_TARGET_CHANGED recorded NPC 6")
eq(n.name, "Kobold Vermin", "npc name")
eq(n.level, 2, "npc level")
eq(n.classification, "normal", "npc classification")
eq(n.type, "Humanoid", "npc creature type")
eq(n.reaction, 2, "npc reaction")
eq(n.factionGroup, "Neutral", "npc faction group")
eq(#n.sightings, 1, "one sighting so far")
eq(n.sightings[1].map, 1429, "sighting map")
eq(n.sightings[1].x, 0.421, "sighting x")

-- the same creature elsewhere is a second sighting; the same spot again is not
api.state.player = { map = 1429, x = 0.446, y = 0.589 }
api.state.units.mouseover = api.state.units.target
api.FireEvent("UPDATE_MOUSEOVER_UNIT")
eq(#db.npcs[6].sightings, 2, "a mouseover somewhere else is a second sighting")
api.FireEvent("UPDATE_MOUSEOVER_UNIT")
eq(#db.npcs[6].sightings, 2, "the same spot twice is one sighting")

-- a boss has no level the client will name, and the file says so rather than storing -1
api.state.units.target = { guid = "Creature-0-0-0-0-12696-0000ABCDEF", name = "Senani Thunderheart",
                           level = -1, classification = "rare", creatureType = "Humanoid",
                           reaction = 6, factionGroup = "Horde" }
api.state.player = { map = 1440, x = 0.737, y = 0.616 }
api.FireEvent("PLAYER_TARGET_CHANGED")
eq(db.npcs[12696].level, "??", "an unknown level is recorded as ??")

-- a player is not a creature, and nothing about one is ever written down
api.state.units.target = { guid = "Player-4395-0123ABCD", name = "Somebody", level = 60,
                           classification = "normal", creatureType = "Humanoid", reaction = 5,
                           factionGroup = "Alliance" }
api.FireEvent("PLAYER_TARGET_CHANGED")
local players = 0
for id in pairs(db.npcs) do if id ~= 6 and id ~= 12696 then players = players + 1 end end
eq(players, 0, "a player target is not recorded")

-- every write is bounded: 30 sightings of one creature keep the first 20
api.state.units.target = { guid = "Creature-0-0-0-0-6-0000AAAA01", name = "Kobold Vermin", level = 2,
                           classification = "normal", creatureType = "Humanoid", reaction = 2,
                           factionGroup = "Neutral" }
for i = 1, 30 do
  api.state.player = { map = 1429, x = 0.1 + i / 1000, y = 0.2 + i / 1000 }
  api.FireEvent("PLAYER_TARGET_CHANGED")
end
eq(#db.npcs[6].sightings, 20, "sightings per creature are capped at 20")

-- -- vendors ---------------------------------------------------------------------------------

api.state.units.npc = { guid = "Creature-0-0-0-0-823-0000ABCD01", name = "Innkeeper Farley" }
api.state.merchant = { { link = "|cffffffff|Hitem:85::::::::60:::::|h[Tough Jerky]|h|r",
                         name = "Tough Jerky", price = 25, quantity = 1, numAvailable = -1 } }
api.FireEvent("MERCHANT_SHOW")
local v = db.vendors[823]
ok(v ~= nil, "MERCHANT_SHOW recorded vendor 823")
eq(v.items[1].id, 85, "vendor item id")
eq(v.items[1].price, 25, "vendor item price")
eq(v.items[1].quantity, 1, "vendor item quantity")
eq(v.items[1].numAvailable, -1, "vendor item stock (-1 is unlimited)")
eq(db.items[85], "Tough Jerky", "the vendor named the item it sells")

-- -- loot ------------------------------------------------------------------------------------

local function lootWindow(guid, quantity)
  api.state.loot = { { link = "|cffffffff|Hitem:182::::::::60:::::|h[Large Candle]|h|r",
                       name = "Large Candle", quantity = quantity,
                       sources = { guid, quantity } } }
  api.FireEvent("LOOT_OPENED")
end

lootWindow("Creature-0-0-0-0-6-0000AAAA01", 2)
lootWindow("Creature-0-0-0-0-6-0000AAAA02", 1)
eq(db.loot["Creature:6"][182], 3, "loot quantities add up across corpses")
eq(db.kills["Creature:6"], 2, "two corpses are two kills")
lootWindow("Creature-0-0-0-0-6-0000AAAA02", 1)
eq(db.kills["Creature:6"], 2, "re-opening the same corpse is not another kill")
eq(db.items[182], "Large Candle", "the loot window named what dropped")

-- the collision the typed keys exist for: creature 6 and object 6 are different things, and the
-- id spaces overlap, so an untyped key would have folded a chest's contents into a kobold's drops
api.state.loot = { { link = "|cffffffff|Hitem:647::::::::60:::::|h[Destiny]|h|r", name = "Destiny",
                     quantity = 1, sources = { "GameObject-0-0-0-0-6-0000BBBB01", 1 } } }
api.FireEvent("LOOT_OPENED")
eq(db.loot["GameObject:6"][647], 1, "an object's loot is filed under its own kind and id")
eq(db.loot["Creature:6"][647], nil, "a creature of the same id did not gain the object's loot")
eq(db.loot["GameObject:6"][182], nil, "nor the object the creature's")
eq(db.kills["GameObject:6"], 1, "the object was opened once")
eq(db.kills["Creature:6"], 2, "and the creature's kills are untouched")

-- 5,000 item names is the cap; the 5,001st link is read and not kept
local kept = 0
for _ in pairs(db.items) do kept = kept + 1 end
for i = 1, 5100 - kept do
  api.state.loot = { { link = "|cffffffff|Hitem:" .. (900000 + i) .. "::::::::60:::::|h[Filler " .. i .. "]|h|r",
                       name = "Filler " .. i, quantity = 1,
                       sources = { "Creature-0-0-0-0-6-0000AAAA01", 1 } } }
  api.FireEvent("LOOT_OPENED")
end
local names = 0
for _ in pairs(db.items) do names = names + 1 end
eq(names, 5000, "item names are capped at 5,000")

-- -- world objects ----------------------------------------------------------------------------

api.state.player = { map = 1440, x = 0.731, y = 0.609 }
api.state.tooltip = { unit = nil, text = "Splintertree Supply Crate", owner = UIParent }
GameTooltip:Show()
local o = db.objects["Splintertree Supply Crate"]
ok(o ~= nil, "a world tooltip recorded the object by name")
eq(#o.sightings, 1, "the object has one sighting")
eq(o.sightings[1].map, 1440, "object sighting map")

-- a unit tooltip is a creature, not an object; an item tooltip is owned by a button, not the world
api.state.tooltip = { unit = "Kobold Vermin", text = "Kobold Vermin", owner = UIParent }
GameTooltip:Show()
api.state.tooltip = { unit = nil, text = "Tough Jerky", owner = CreateFrame("Frame") }
GameTooltip:Show()
local objects = 0
for _ in pairs(db.objects) do objects = objects + 1 end
eq(objects, 1, "only the world object was recorded")

-- -- dungeon entrances -------------------------------------------------------------------------

-- The client carries no entrance position for a Classic instance, so the door is a player standing
-- at it. Walking up to one is the rough reading; stepping back out of it is the accurate one.
api.state.player = { map = 1436, x = 0.425, y = 0.712 }
api.state.instance = nil
api.FireEvent("ZONE_CHANGED_NEW_AREA")
api.state.player = { map = 291, x = 0.5, y = 0.5 }         -- inside, on the instance's own map
api.state.instance = { kind = "party", mapID = 36, name = "The Deadmines" }
api.FireEvent("PLAYER_ENTERING_WORLD")

local e = db.entrances and db.entrances[36]
ok(e ~= nil, "entering an instance recorded its entrance")
if e then
  eq(e.map, 1436, "the entrance is on the outdoor map, not the instance's own")
  eq(e.x, 0.425, "entrance x is the last outdoor position")
  eq(e.y, 0.712, "entrance y is the last outdoor position")
  eq(e.samples, 1, "one reading so far")
  eq(e.exit, nil, "walking up to a door is not the accurate reading")
end

-- Inside already: nothing moves, and the position inside is never taken for a door
api.state.player = { map = 291, x = 0.8, y = 0.2 }
api.FireEvent("ZONE_CHANGED_NEW_AREA")
eq(db.entrances[36].x, 0.425, "a second event inside the instance does not move the entrance")

-- An instance reached without ever being outdoors first - a summon, a portal from another
-- instance - has no position anybody walked to, and none is invented
api.state.instance = { kind = "raid", mapID = 409, name = "Molten Core" }
api.FireEvent("PLAYER_ENTERING_WORLD")
eq(db.entrances[409], nil, "an instance entered with no outdoor position before it is not guessed")

-- Stepping back out puts the player at the door itself: that reading replaces the approach, and
-- from then on it is the one that is kept. The client can still be showing the instance's own map
-- when the event fires, and a reading taken there would be nonsense, so it is refused.
api.state.instance = nil
api.state.player = { map = 291, x = 0.5, y = 0.5 }
api.FireEvent("PLAYER_ENTERING_WORLD")
eq(db.entrances[409], nil, "a reading still on the instance's own map is not the door")
api.state.player = { map = 1436, x = 0.431, y = 0.706 }
api.FireEvent("ZONE_CHANGED")
local out = db.entrances[409]
ok(out ~= nil, "the exit reading arrived on the next event, once the client named an outdoor map")
if out then
  eq(out.map, 1436, "the exit reading is on the outdoor map")
  eq(out.x, 0.431, "the exit reading is where the player was put down")
  eq(out.exit, true, "and it says it was taken at the door")
end

-- ZONE_CHANGED and ZONE_CHANGED_INDOORS sample too: a Classic portal fires neither of the two
-- events this started with, and an approach recorded from the wrong place is worse than none
api.state.player = { map = 1436, x = 0.440, y = 0.700 }
api.FireEvent("ZONE_CHANGED_INDOORS")
api.state.instance = { kind = "party", mapID = 36, name = "The Deadmines" }
api.FireEvent("PLAYER_ENTERING_WORLD")
eq(db.entrances[36].x, 0.440, "a later approach replaces the earlier one")
eq(db.entrances[36].samples, 2, "and both readings are counted")

-- Out of the Deadmines this time: the door itself, which outranks every approach after it
api.state.instance = nil
api.state.player = { map = 1436, x = 0.428, y = 0.709 }
api.FireEvent("PLAYER_ENTERING_WORLD")
eq(db.entrances[36].x, 0.428, "the exit reading replaces the approach")
eq(db.entrances[36].exit, true, "and is marked as taken at the door")
eq(db.entrances[36].samples, 3, "three readings of this door now")

api.state.player = { map = 1436, x = 0.900, y = 0.900 }
api.FireEvent("ZONE_CHANGED_NEW_AREA")
api.state.instance = { kind = "party", mapID = 36, name = "The Deadmines" }
api.FireEvent("PLAYER_ENTERING_WORLD")
eq(db.entrances[36].x, 0.428, "an approach does not overwrite a reading taken at the door")
eq(db.entrances[36].samples, 4, "but it is still counted")

local doors = 0
for _ in pairs(db.entrances) do doors = doors + 1 end
eq(doors, 2, "one entry per instance map id")
api.state.instance = nil

-- -- slash commands ----------------------------------------------------------------------------

api.printed = {}
ok(api.Slash("/fdc", ""), "/fdc is registered")
local report = table.concat(api.printed, "\n")
ok(report:find("2 quest"), "/fdc prints the quest count: " .. report)
api.Slash("/fdc", "reset")
local emptied = 0
for _ in pairs(db.quests) do emptied = emptied + 1 end
for _ in pairs(db.npcs) do emptied = emptied + 1 end
for _ in pairs(db.loot) do emptied = emptied + 1 end
for _ in pairs(db.items) do emptied = emptied + 1 end
for _ in pairs(db.entrances) do emptied = emptied + 1 end
eq(emptied, 0, "/fdc reset empties what was collected")
eq(db.version, 1, "/fdc reset keeps the schema version")

-- -- edges: what the addon refuses, and where its caps bite -------------------------------------
--
-- The happy paths above are what a player does; these are what the client does to an addon on a bad
-- day. Every one of them is a line in ForeverDiffCollector.lua that decides not to write something,
-- and an untested "decides not to" is how a collector starts inventing facts.

-- A quest handed over by something that is not a unit - a scroll on the ground, an item in the bag -
-- has no giver the client will name, and none is invented.
api.state.units.npc = nil
api.state.player = { map = 1429, x = 0.500, y = 0.500 }
api.state.quest = { id = 900, title = "A Note From The Ground",
                    description = "The note is signed with a hurried scrawl.",
                    objectives = "Take the note to Stormwind." }
api.FireEvent("QUEST_DETAIL")
ok(db.quests[900] ~= nil, "a quest with no NPC in front of it is still recorded")
eq(db.quests[900].giver, nil, "and no giver is invented for it")
eq(db.quests[900].giverName, nil, "nor a giver's name")

-- The client stops naming the quest while its own frame is open more often than it should. The
-- addon keeps writing to the last quest it was told about rather than dropping the text.
api.state.quest = { id = 0, progress = "Have you got it?" }
api.FireEvent("QUEST_PROGRESS")
eq(db.quests[900].progress, "Have you got it?", "a quest the client stops naming keeps its own row")

-- Off any map the client will draw - a loading screen, a cinematic, a taxi - there is no position,
-- and a sighting with no position is not written down.
api.state.player = nil
api.state.units.target = { guid = "Creature-0-0-0-0-77-0000CCCC01", name = "Mangy Wolf", level = 3,
                           classification = "normal", creatureType = "Beast", reaction = 2 }
api.FireEvent("PLAYER_TARGET_CHANGED")
ok(db.npcs[77] ~= nil, "a creature seen off-map is still recorded")
eq(#db.npcs[77].sightings, 0, "but with no position, because the client gave none")

-- (0, 0) is what the client answers before it knows where the player is. It is not a place.
api.state.player = { map = 1429, x = 0, y = 0 }
api.FireEvent("PLAYER_TARGET_CHANGED")
eq(#db.npcs[77].sightings, 0, "the client's (0, 0) is not a position")

-- A GUID with no id in it is not guessed at, and neither is a missing one.
api.state.player = { map = 1429, x = 0.3, y = 0.3 }
api.state.units.target = { guid = "Creature-0-0", name = "Nothing" }
api.FireEvent("PLAYER_TARGET_CHANGED")
api.state.units.target = { guid = nil, name = "Nothing" }
api.FireEvent("PLAYER_TARGET_CHANGED")
local seen = 0
for _ in pairs(db.npcs) do seen = seen + 1 end
eq(seen, 1, "a GUID with no id in it records nothing")

-- A chest under the mouse is a GameObject. `npcs` is creatures, and the two id spaces overlap.
api.state.units.mouseover = { guid = "GameObject-0-0-0-0-31-0000BBBB09", name = "Battered Chest" }
api.FireEvent("UPDATE_MOUSEOVER_UNIT")
eq(db.npcs[31], nil, "a GameObject under the mouse is not filed as a creature")

-- A merchant frame the client opens with nobody named writes no vendor: an unattributed stock list
-- is a row under whichever id came next, which is worse than no row.
api.state.units.npc = nil
api.state.merchant = { { link = "|cffffffff|Hitem:85::::::::60:::::|h[Tough Jerky]|h|r",
                         name = "Tough Jerky", price = 25, quantity = 1, numAvailable = -1 } }
api.FireEvent("MERCHANT_SHOW")
local vendors = 0
for _ in pairs(db.vendors) do vendors = vendors + 1 end
eq(vendors, 0, "a merchant window with no NPC named records no vendor")

-- A merchant's stock stops at sixty: the biggest vendors on the Classic line carry fewer.
api.state.units.npc = { guid = "Creature-0-0-0-0-1234-0000ABCD02", name = "Big Vendor" }
api.state.merchant = {}
for i = 1, 90 do
  api.state.merchant[i] = { link = "|cffffffff|Hitem:" .. (700000 + i) .. "::::::::60:::::|h[Stock " .. i .. "]|h|r",
                            name = "Stock " .. i, price = 10, quantity = 1, numAvailable = -1 }
end
api.FireEvent("MERCHANT_SHOW")
eq(#db.vendors[1234].items, 60, "a vendor's stock is capped at 60 items")
eq(db.vendors[1234].items[1].id, 700001, "and it is the first sixty, in the order the frame listed them")

-- A loot window the client names no source for still names the item, and credits nothing with it.
api.state.loot = { { link = "|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r",
                     name = "Linen Cloth", quantity = 1, sources = nil } }
api.FireEvent("LOOT_OPENED")
eq(db.items[2589], "Linen Cloth", "an item whose source the client withheld is still named")
local sources = 0
for _ in pairs(db.loot) do sources = sources + 1 end
eq(sources, 0, "and nothing is credited with dropping it")

-- Object names are the only free text the file is keyed by, so they stop at five hundred - and an
-- object already known keeps gaining positions afterwards, which is what the cap must not break.
for i = 1, 520 do
  api.state.player = { map = 1440, x = 0.1 + i / 10000, y = 0.2 + i / 10000 }
  api.state.tooltip = { unit = nil, text = "Node " .. i, owner = UIParent }
  GameTooltip:Show()
end
local objects = 0
for _ in pairs(db.objects) do objects = objects + 1 end
eq(objects, 500, "object names are capped at 500")
api.state.player = { map = 1440, x = 0.9, y = 0.9 }
api.state.tooltip = { unit = nil, text = "Node 1", owner = UIParent }
GameTooltip:Show()
eq(#db.objects["Node 1"].sightings, 2, "an object already known still gains positions past the cap")
api.state.tooltip = { unit = nil, text = nil, owner = UIParent }

-- Put the stub client back the way the sections above left it. The last section serialises whatever
-- state is standing, and a merchant frame still holding ninety rows of `Stock 1` would quietly make
-- the file this harness writes - the one the Python end-to-end test ingests - describe a vendor
-- nobody ever opened.
api.state.merchant = { { link = "|cffffffff|Hitem:85::::::::60:::::|h[Tough Jerky]|h|r",
                         name = "Tough Jerky", price = 25, quantity = 1, numAvailable = -1 } }
api.state.units.mouseover = nil

-- Two hundred corpses are remembered so that re-opening one loot window is not a second kill. The
-- two-hundred-and-first forgets the oldest, which is the bound that stops a session growing - and
-- the price of that bound is that a corpse looted again much later is counted twice. Both are here.
api.state.player = { map = 1429, x = 0.4, y = 0.4 }
local function corpse(n)
  api.state.loot = { { link = "|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r",
                       name = "Linen Cloth", quantity = 1,
                       sources = { "Creature-0-0-0-0-4242-" .. string.format("%010d", n), 1 } } }
  api.FireEvent("LOOT_OPENED")
end
for i = 1, 200 do corpse(i) end
eq(db.kills["Creature:4242"], 200, "two hundred corpses are two hundred kills")
corpse(200)
eq(db.kills["Creature:4242"], 200, "and re-opening the newest of them is not another kill")
corpse(201)
eq(db.kills["Creature:4242"], 201, "the two-hundred-and-first corpse is counted")
corpse(1)
eq(db.kills["Creature:4242"], 202, "the oldest has been forgotten, which is what the bound costs")

-- A second session reads the file the first one left behind and adds to it, rather than starting
-- again - and a table a released collector never wrote (`entrances`) is created for it.
ForeverDiffCollectorDB = { version = 1, quests = { [7] = { title = "From last night" } } }
api.FireEvent("ADDON_LOADED", "ForeverDiffCollector")
db = ForeverDiffCollectorDB
eq(db.quests[7].title, "From last night", "a database of this schema is kept and added to")
eq(db.build.interface, 16001, "and its build is refreshed to the client that has just loaded it")
ok(type(db.entrances) == "table", "a table an older collector never wrote is created for it")

-- The .toc names two client families and the addon is the same code on both: a Classic Era client
-- records its own build, and the pipeline files what it collects under that client's own product.
api.state.build = { version = "1.15.9", build = "69722", date = "Sep 16 2026", interface = 11509 }
api.FireEvent("ADDON_LOADED", "ForeverDiffCollector")
db = ForeverDiffCollectorDB
eq(db.build.version, "1.15.9", "a Classic Era client records its own build")
eq(db.build.interface, 11509, "and its own interface number")
api.state.build = { version = "1.60.1", build = "69893", date = "Sep 16 2026", interface = 16001 }
api.FireEvent("ADDON_LOADED", "ForeverDiffCollector")
db = ForeverDiffCollectorDB

-- A file written by a collector of another schema is remade empty. The pipeline reads version 1 and
-- nothing else, so a half-read table of an unknown shape is the one thing that must never be kept.
ForeverDiffCollectorDB = { version = 99, quests = { [1] = { title = "from another schema" } } }
api.FireEvent("ADDON_LOADED", "ForeverDiffCollector")
db = ForeverDiffCollectorDB
eq(db.version, 1, "a database of another schema is remade at this one")
eq(db.quests[1], nil, "and nothing of it is carried over")

-- -- the file the pipeline reads ----------------------------------------------------------------

api.Slash("/fdc", "reset")
api.state.quest = { id = 2, title = "Sharptalon's Claw", description = "d", objectives = "o",
                    progress = "p", completion = "c", money = 1200, xp = 250,
                    choices = { "|Hitem:182:|h" }, rewards = { "|Hitem:647:|h" } }
api.state.units.npc = { guid = "Creature-0-0-0-0-12696-0000ABCDEF", name = "Senani Thunderheart" }
api.state.player = { map = 1440, x = 0.737, y = 0.616 }
api.FireEvent("QUEST_DETAIL")
api.FireEvent("QUEST_PROGRESS")
api.FireEvent("QUEST_COMPLETE")
api.state.units.target = { guid = "Creature-0-0-0-0-6-0000AAAA01", name = "Kobold Vermin", level = 2,
                           classification = "normal", creatureType = "Humanoid", reaction = 2,
                           factionGroup = "Neutral" }
api.state.player = { map = 1429, x = 0.421, y = 0.604 }
api.FireEvent("PLAYER_TARGET_CHANGED")
api.FireEvent("MERCHANT_SHOW")
lootWindow("Creature-0-0-0-0-6-0000AAAA03", 3)
api.state.loot = { { link = "|cffffffff|Hitem:647::::::::60:::::|h[Destiny]|h|r", name = "Destiny",
                     quantity = 1, sources = { "GameObject-0-0-0-0-31-0000BBBB09", 1 } } }
api.FireEvent("LOOT_OPENED")
api.state.player = { map = 1440, x = 0.731, y = 0.609 }
api.state.tooltip = { unit = nil, text = "Splintertree Supply Crate", owner = UIParent }
GameTooltip:Show()
api.state.player = { map = 1436, x = 0.440, y = 0.700 }
api.FireEvent("ZONE_CHANGED_NEW_AREA")
api.state.instance = { kind = "party", mapID = 36, name = "The Deadmines" }
api.FireEvent("PLAYER_ENTERING_WORLD")
api.state.instance = nil
api.state.player = { map = 1436, x = 0.425, y = 0.712 }
api.FireEvent("PLAYER_ENTERING_WORLD")

local text = "ForeverDiffCollectorDB = " .. serialize(db, 0) .. "\n"

--- `run.lua --write <path>` leaves that file on disk, which is what the Python end-to-end test
--- ingests: it proves the pipeline reads what this addon writes rather than what a fixture says it
--- writes. Nothing else about the run changes, so the checks below still run and still decide.
if arg[1] == "--write" and arg[2] then
  local out = assert(io.open(arg[2], "w"))
  out:write(text)
  out:close()
  io.write("wrote ", arg[2], " (", #text, " bytes)\n")
end
ok(text:find('^ForeverDiffCollectorDB = {\n\t%["build"%] = {\n'), "the file starts the way the game writes it")
local round = loadDB(text, "the serialised database")
ok(round ~= nil and round.quests[2].title == "Sharptalon's Claw", "the serialised database reads back")

local fixturePath = root .. "/addon/tests/fixtures/collector.lua"
local handle = io.open(fixturePath, "r")
ok(handle ~= nil, "the pipeline fixture exists at " .. fixturePath)
if handle then
  local fixture = loadDB(handle:read("*a"), "the pipeline fixture")
  handle:close()
  if fixture then
    local mine, theirs = renderShape(shapeOf(db), 1), renderShape(shapeOf(fixture), 1)
    if mine ~= theirs then
      failures = failures + 1
      io.write("FAIL the addon and the pipeline fixture disagree.\n--- addon ---", mine,
               "\n--- fixture ---", theirs, "\n")
    end
    checks = checks + 1
  end
end

-- -- what the site still needs, in the item tooltip ---------------------------------------------
--
-- The rule the tooltip exists to obey is a silence: an item the site already has gets no line, no
-- blank line and no header, and an addon that gets that wrong is one a player turns off. Every
-- check below is about when NOTHING is written as much as about what is written.
--
-- `api.HoverItem` drives whichever tooltip API the stub is offering, which `ops/test-addon.sh`
-- flips with `FDC_TOOLTIP_API=legacy` so that both are proved on every run of the gate.

local GOLD = { 1, 0.82, 0.09 }
local GREY = { 0.7, 0.7, 0.7 }
local DOT = "\194\183"
local TIMES = "\195\151"

--- An item link the way the client writes one, for an id.
local function itemLink(id, name)
  return string.format("|cffffffff|Hitem:%d::::::::60:::::|h[%s]|h|r", id, name or ("Item " .. id))
end

local function lineTexts(lines)
  local out = {}
  for i, line in ipairs(lines) do out[i] = line.text end
  return table.concat(out, " | ")
end

ForeverDiffData = {
  site = "https://foreverdiff.gg",
  build = "wow_classic_beta-1.60.1.69893",
  generated = "2026-09-17T12:00:00Z",
  items = {
    [25] = { gap = "sources", seen = 4, contributions = 2 },
    [35] = { gap = "sources", seen = 0, contributions = 0 },
    [45] = { gap = "sources", seen = 1, contributions = 1 },
    [55] = { gap = "sources" },
    [65] = { gap = "somethingTheAddonHasNoWordingFor", seen = 2, contributions = 0 },
  },
}

api.state.tooltip = { unit = nil, text = nil, owner = nil }

eq(api.TooltipApi(), os.getenv("FDC_TOOLTIP_API") == "legacy" and "legacy" or "modern",
   "the stub offers the tooltip API this run is testing")

-- an item the site still needs: exactly two lines, in the exact words, in the exact colours
local lines = api.HoverItem(itemLink(25, "Worn Shortsword"))
eq(#lines, 2, "a needed item adds exactly two lines (" .. lineTexts(lines) .. ")")
eq(lines[1] and lines[1].text, "ForeverDiff: needs a contribution", "the first line names the site")
eq(lines[1] and lines[1].r, GOLD[1], "the first line is gold (r)")
eq(lines[1] and lines[1].g, GOLD[2], "the first line is gold (g)")
eq(lines[1] and lines[1].b, GOLD[3], "the first line is gold (b)")
eq(lines[2] and lines[2].text,
   "Where it comes from is not recorded " .. DOT .. " seen 4" .. TIMES .. " " .. DOT ..
   " 2 contributions " .. DOT .. " /fd for the link",
   "the second line says what is missing, how much is known, and how to contribute")
eq(lines[2] and lines[2].r, GREY[1], "the second line is grey (r)")
eq(lines[2] and lines[2].g, GREY[2], "the second line is grey (g)")
eq(lines[2] and lines[2].b, GREY[3], "the second line is grey (b)")

-- one contribution is one contribution, not "1 contributions"
lines = api.HoverItem(itemLink(45))
eq(lines[2] and lines[2].text,
   "Where it comes from is not recorded " .. DOT .. " seen 1" .. TIMES .. " " .. DOT ..
   " 1 contribution " .. DOT .. " /fd for the link", "one contribution is singular")

-- nought is a real answer and is printed: nobody has recorded this, you would be the first
lines = api.HoverItem(itemLink(35))
eq(lines[2] and lines[2].text,
   "Where it comes from is not recorded " .. DOT .. " seen 0" .. TIMES .. " " .. DOT ..
   " 0 contributions " .. DOT .. " /fd for the link", "nought is printed, not hidden")

-- a count the build could not measure is left out of the line rather than written as a zero
lines = api.HoverItem(itemLink(55))
eq(lines[2] and lines[2].text,
   "Where it comes from is not recorded " .. DOT .. " /fd for the link",
   "an unmeasured count is left out of the line")

-- a gap code from a newer pipeline than this addon still gets a line a player can act on
lines = api.HoverItem(itemLink(65))
eq(lines[2] and lines[2].text,
   "This item's world data is not recorded " .. DOT .. " seen 2" .. TIMES .. " " .. DOT ..
   " 0 contributions " .. DOT .. " /fd for the link",
   "a gap code this addon has no wording for still reads")

-- THE RULE: an item the site already has adds nothing at all
eq(#api.HoverItem(itemLink(647, "Destiny")), 0, "an item the site already has adds no line")
eq(#api.HoverItem(itemLink(999999)), 0, "an id nothing knows about adds no line")
eq(#api.HoverItem(nil), 0, "a tooltip showing no item at all adds no line")
eq(#api.HoverItem("|cffffffff|Hspell:133:|h[Fireball]|h|r"), 0, "a tooltip of something else adds no line")

-- a clicked chat link is the same answer on the same rules
lines = api.HoverItem(itemLink(25), ItemRefTooltip)
eq(#lines, 2, "a link clicked in chat gets the same two lines")
eq(#api.HoverItem(itemLink(647), ItemRefTooltip), 0, "and the same silence for an item that is fine")

-- the client processing one tooltip twice before it is cleared writes one set of lines
GameTooltip:ClearLines()
api.HoverItem(itemLink(25))
local before = #GameTooltip.lines
api.state.tooltip.item = { name = "Worn Shortsword", link = itemLink(25) }
if TooltipDataProcessor then
  for _, fn in ipairs(api.tooltipPostCalls[Enum.TooltipDataType.Item] or {}) do
    fn(GameTooltip, { type = Enum.TooltipDataType.Item })
  end
else
  GameTooltip:FireHook("OnTooltipSetItem")
end
eq(#GameTooltip.lines, before, "a tooltip processed twice before it is cleared is not written twice")

-- ...and the same item, looked at again after the tooltip cleared, is described again
eq(#api.HoverItem(itemLink(25)), 2, "the same item hovered again is described again")

-- and hiding the tooltip clears the mark just as clearing it does
api.HoverItem(itemLink(25))
GameTooltip:Hide()
eq(#api.HoverItem(itemLink(25)), 2, "hiding the tooltip also lets the next look be described")

-- no data file at all: the addon is silent and nothing errors. This is what a player gets when the
-- site could not read the table, and it is the single most important check in this section.
local savedData = ForeverDiffData
ForeverDiffData = nil
eq(#api.HoverItem(itemLink(25)), 0, "with no data file the tooltip gets nothing")
eq(ForeverDiffDebug.tooltipErrors, 0, "and nothing raised")

-- a data file of the wrong shape is the same silence, not a Lua error into the player's UI
ForeverDiffData = { site = "https://foreverdiff.gg" }
eq(#api.HoverItem(itemLink(25)), 0, "a data file with no items table adds nothing")
ForeverDiffData = { items = "not a table" }
eq(#api.HoverItem(itemLink(25)), 0, "a data file whose items are not a table adds nothing")
ForeverDiffData = { items = { [25] = "not a row" } }
eq(#api.HoverItem(itemLink(25)), 0, "an entry that is not a table adds nothing")
eq(ForeverDiffDebug.tooltipErrors, 0, "and none of those raised either")

-- a tooltip that is not a tooltip cannot reach the player as an error: it is counted and dropped
local errorsBefore = ForeverDiffDebug.tooltipErrors
ForeverDiffData = savedData
if TooltipDataProcessor then
  for _, fn in ipairs(api.tooltipPostCalls[Enum.TooltipDataType.Item] or {}) do
    fn(setmetatable({}, { __index = function() error("a client that answers nonsense") end }), nil)
  end
else
  local broken = CreateFrame("Frame")
  broken.AddLine = function() error("a client that answers nonsense") end
  broken.GetItem = function() return "x", itemLink(25) end
  broken.foreverDiffFor = nil
  for _, fn in ipairs(GameTooltip.hooks.OnTooltipSetItem or {}) do fn(broken) end
end
ok(ForeverDiffDebug.tooltipErrors > errorsBefore, "a hook that raises is counted, not printed")
ok(ForeverDiffDebug.lastError ~= nil, "and the error itself is kept for /fdc to report")
ForeverDiffDebug.tooltipErrors, ForeverDiffDebug.lastError = 0, nil

-- -- /foreverdiff and /fd: the link, in a box -----------------------------------------------------

local CONTRIBUTE = "https://foreverdiff.gg/contribute?type=items&id=25&gap=sources"

ok(api.Slash("/fd", itemLink(25)), "/fd is a command the client knows")
local box = _G.ForeverDiffLinkBox
ok(box ~= nil, "it opened a box to copy out of")
eq(box and box:GetText(), CONTRIBUTE, "holding the item's contribute URL")
eq(box and box.highlighted, true, "already selected, so Ctrl+C is one key")
eq(box and box.focused, true, "and focused")
eq(_G.ForeverDiffLinkFrame and _G.ForeverDiffLinkFrame:IsShown(), true, "the window is up")
ok(_G.UISpecialFrames[#_G.UISpecialFrames] == "ForeverDiffLinkFrame", "Esc closes it")

-- the long word and the short word are the same command
api.Slash("/foreverdiff", itemLink(35))
eq(box:GetText(), "https://foreverdiff.gg/contribute?type=items&id=35&gap=sources",
   "/foreverdiff is the same command as /fd")

-- a bare id is what somebody reads off the site and types back
api.Slash("/fd", "25")
eq(box:GetText(), CONTRIBUTE, "a bare item id works too")
api.Slash("/fd", "  25  ")
eq(box:GetText(), CONTRIBUTE, "and is not upset by the spaces a paste leaves behind")

-- an item the site already has has no gap, so the link is the item's own page
api.Slash("/fd", itemLink(647, "Destiny"))
eq(box:GetText(), "https://foreverdiff.gg/items/647",
   "an item that needs nothing links to its page rather than to the contribute form")

-- the URL cannot be edited away: whatever is typed over it is put back and re-selected
box.highlighted = false
box:SetText("http://not-the-url")
eq(box:GetText(), "https://foreverdiff.gg/items/647", "typing over the URL restores it")
eq(box.highlighted, true, "and re-selects it")

-- the site the link points at is the data file's, so moving the site is a data change
ForeverDiffData = { site = "https://staging.example", items = { [25] = { gap = "sources" } } }
api.Slash("/fd", "25")
eq(box:GetText(), "https://staging.example/contribute?type=items&id=25&gap=sources",
   "the site in the data file is the site in the link")
ForeverDiffData = nil
api.Slash("/fd", "25")
eq(box:GetText(), "https://foreverdiff.gg/items/25",
   "with no data file at all the link is still a page a player can reach")
ForeverDiffData = savedData

-- no argument is a sentence, not a window
local printedBefore = #api.printed
_G.ForeverDiffLinkFrame:Hide()
api.Slash("/fd", "")
eq(api.printed[#api.printed], "ForeverDiff: shift-click an item after /fd to get its link",
   "/fd on its own says how to use it")
eq(#api.printed, printedBefore + 1, "and says it once")
eq(_G.ForeverDiffLinkFrame:IsShown(), false, "and opens nothing")
api.Slash("/fd", "not an item at all")
eq(api.printed[#api.printed], "ForeverDiff: shift-click an item after /fd to get its link",
   "and so is anything that is not an item")
eq(ForeverDiffDebug.slashErrors, 0, "nothing the command did raised")

-- `/fdc` is untouched: it is the word the README and the in-game script have always printed
printedBefore = #api.printed
ok(api.Slash("/fdc", ""), "/fdc still reports what has been collected")
ok(#api.printed > printedBefore, "and still prints")

-- -- the .toc the client reads ------------------------------------------------------------------
--
-- Contract: Classic Era 1.15 and Forever beta 1.60 are the supported client families.

local function slurp(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end

local toc = slurp(root .. "/addon/ForeverDiffCollector/ForeverDiffCollector.toc")
ok(toc ~= nil, "the .toc is where the client looks for it")

-- The client loads the files a .toc lists in the order it lists them, so the data table has to be
-- named before the code that reads it at load. The other way round the addon would read a nil
-- global once, at the one moment it cannot recover from.
if toc then
  local order = {}
  for line in toc:gmatch("[^\r\n]+") do
    local file = line:match("^%s*([%w_%-]+%.lua)%s*$")
    if file then order[#order + 1] = file end
  end
  eq(order[1], "ForeverDiffData.lua", "the .toc loads the data table first")
  eq(order[2], "ForeverDiffCollector.lua", "and the addon second")
  eq(#order, 2, "and lists nothing else (the zip route builds the archive from what is here)")
end
if toc then
  local declared, line = {}, toc:match("##%s*Interface:%s*([^\r\n]*)")
  ok(line ~= nil, "the .toc declares an interface")
  for number in tostring(line):gmatch("%d+") do declared[#declared + 1] = tonumber(number) end
  ok(#declared > 0, "and it is a number")
  local wanted = { 11500, 16000 }
  for _, base in ipairs(wanted) do
    local found = nil
    for _, number in ipairs(declared) do
      if math.floor(number / 100) * 100 == base then found = number end
    end
    ok(found ~= nil, string.format(
      "the .toc names an interface in the %d.%02d client family (declared: %s)",
      math.floor(base / 10000), math.floor(base % 10000 / 100), tostring(line)))
  end
end

io.write(string.format("%d checks, %d failures\n", checks, failures))
os.exit(failures == 0 and 0 or 1)
