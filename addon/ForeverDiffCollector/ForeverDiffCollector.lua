-- ForeverDiff Collector: an opt-in record of what the client shows you, written to SavedVariables.
--
-- The Forever realm ships no database. Quest text, who gives a quest, where a creature stands, what
-- a vendor sells and what a corpse drops exist only on screen, so this addon writes down what the
-- client already told the player and nothing else. It reads no protected information, sends nothing
-- anywhere, and records no account, character or player name: the file it leaves behind holds the
-- realm and the build it was collected on, and game facts.
--
-- Everything here is event-driven and bounded. There is no OnUpdate handler and no scanning loop:
-- sightings are capped per entity, a vendor's stock is capped per merchant, and object names - the
-- one key the client hands over as free text - are capped as a whole. What is left (quests,
-- creatures, vendors, loot and item names) is keyed by ids the game itself only has so many of.
-- The table is meant to stay small enough to upload (well under a megabyte in practice).

local ADDON_NAME = "ForeverDiffCollector"
local SCHEMA = 1
ForeverDiffDebug = { tooltipErrors = 0, slashErrors = 0, eventErrors = 0, lastError = nil }
local function guarded(what, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      ForeverDiffDebug[what] = (ForeverDiffDebug[what] or 0) + 1
      ForeverDiffDebug.lastError = tostring(err)
    end
  end
end
--- Per entity, in the file. Twenty positions describe a patrol; two hundred describe nothing more.
local MAX_SIGHTINGS = 20
--- One merchant's pages. The biggest vendors in the Classic line carry fewer than this.
local MAX_VENDOR_ITEMS = 60
--- Object names come from tooltip text, the only free-text key in the file, so they are capped.
local MAX_OBJECTS = 500
--- Item names kept, first come. More than this is more items than any character meets in a life,
--- and the cap is what stops a stream of links nobody asked about from growing the file.
local MAX_ITEM_NAMES = 5000
--- Corpses remembered this session, so re-opening one loot window is not counted as a second kill.
local MAX_LOOTED = 200

local objectCount = 0
local itemNameCount = 0
local lastQuestID = nil
local looted, lootedOrder = {}, {}
--- The last place the player stood outdoors, spent the moment an instance loads around them: that
--- position is the only thing anywhere that says where a dungeon's door is. `lastOutdoorMap` is the
--- same map id, kept rather than spent. `lastInstance` is the instance they are in until they step
--- back out of it, when the client puts them down at its door. `insideMap` is a map the client
--- showed *only* inside - a "door" still on that map is the client not having caught up, and is
--- refused - and stays nil for an instance drawn on its zone's own map, which Classic Era's all are.
local lastOutdoor = nil
local lastOutdoorMap = nil
local lastInstance = nil
local insideMap = nil

-- -- small readings of what the client says -----------------------------------------------------

--- `Creature-0-0-0-0-1234-0000ABCDEF` -> "Creature", 1234. The id is always the sixth field.
local function guidParts(guid)
  if type(guid) ~= "string" then return nil end
  local fields = {}
  for part in guid:gmatch("[^%-]+") do fields[#fields + 1] = part end
  local id = tonumber(fields[6])
  if not id then return nil end
  return fields[1], id
end

local function itemIdFromLink(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

--- The name inside an item link: `|cff9d9d9d|Hitem:182:...|h[Large Candle]|h|r` -> `Large Candle`.
local function itemNameFromLink(link)
  return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end

--- Which corpse or chest loot came off. Creature 6 and GameObject 6 are different things, so the
--- kind is part of the key: the pipeline files one as a drop and the other as contents.
local function sourceKey(kind, id)
  return kind .. ":" .. id
end

local function round(value)
  return math.floor(value * 10000 + 0.5) / 10000
end

--- Where the player is standing, as the map the client would draw them on. Nil off any map.
local function playerPos()
  if not C_Map or not C_Map.GetBestMapForUnit then return nil end
  local map = C_Map.GetBestMapForUnit("player")
  if not map then return nil end
  local pos = C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return nil end
  local x, y = pos:GetXY()
  if not x or not y or (x == 0 and y == 0) then return nil end
  return map, round(x), round(y)
end

--- Append where the player stands to `list`, unless it is already there or the list is full.
local function addSighting(list)
  local map, x, y = playerPos()
  if not map then return false end
  for i = 1, #list do
    local s = list[i]
    if s.map == map and s.x == x and s.y == y then return false end
  end
  if #list >= MAX_SIGHTINGS then return false end
  list[#list + 1] = { map = map, x = x, y = y }
  return true
end

--- True the first time this session a corpse or chest is looted, so kills are counted once.
local function firstLoot(guid)
  if looted[guid] then return false end
  looted[guid] = true
  lootedOrder[#lootedOrder + 1] = guid
  if #lootedOrder > MAX_LOOTED then
    looted[table.remove(lootedOrder, 1)] = nil
  end
  return true
end

-- -- the database --------------------------------------------------------------------------------

local function db()
  return ForeverDiffCollectorDB
end

local function emptyTables(d)
  d.quests, d.npcs, d.objects, d.vendors, d.loot, d.kills, d.items = {}, {}, {}, {}, {}, {}, {}
  d.entrances = {}
  objectCount, itemNameCount = 0, 0
end

--- The name the client printed for an item, kept once. Blizzard has shipped builds with the item
--- table withheld, and then this is the only name there is for what somebody looted.
local function nameItem(d, id, name)
  if id and type(name) == "string" and name ~= "" and not d.items[id]
     and itemNameCount < MAX_ITEM_NAMES then
    d.items[id] = name
    itemNameCount = itemNameCount + 1
  end
end

local function ensureDB()
  local d = ForeverDiffCollectorDB
  if type(d) ~= "table" or d.version ~= SCHEMA then
    d = { version = SCHEMA }
    emptyTables(d)
  end
  for _, name in ipairs({ "quests", "npcs", "objects", "vendors", "loot", "kills", "items",
                          "entrances" }) do
    if type(d[name]) ~= "table" then d[name] = {} end
  end
  local version, build, _date, interface = GetBuildInfo()
  d.build = { version = version, build = build, interface = interface }
  d.realm = GetRealmName()
  objectCount, itemNameCount = 0, 0
  for _ in pairs(d.objects) do objectCount = objectCount + 1 end
  for _ in pairs(d.items) do itemNameCount = itemNameCount + 1 end
  ForeverDiffCollectorDB = d
end

local function counts(d)
  local out = {}
  for _, name in ipairs({ "quests", "npcs", "objects", "vendors", "loot", "items", "entrances" }) do
    local n = 0
    for _ in pairs(d[name]) do n = n + 1 end
    out[name] = n
  end
  return out
end

-- -- events ---------------------------------------------------------------------------------------

local handlers = {}

function handlers.ADDON_LOADED(name)
  if name ~= ADDON_NAME then return end
  ensureDB()
end

--- The quest the quest frame is showing, or the last one it showed when the client will not say.
local function questID()
  local id = GetQuestID and GetQuestID() or nil
  if id and id > 0 then
    lastQuestID = id
    return id
  end
  return lastQuestID
end

local function questItems(kind, count)
  local d, ids = db(), {}
  for i = 1, (count or 0) do
    local link = GetQuestItemLink(kind, i)
    local id = itemIdFromLink(link)
    if id then
      ids[#ids + 1] = id
      nameItem(d, id, itemNameFromLink(link))
    end
  end
  return ids
end

function handlers.QUEST_DETAIL()
  local d, id = db(), questID()
  if not d or not id then return end
  local q = d.quests[id] or {}
  q.title = GetTitleText()
  q.description = GetQuestText()
  q.objectives = GetObjectiveText()
  -- The Classic client gives no reliable quest level while the quest frame is open, so none is
  -- recorded: a wrong level is worse than an absent one, which the pipeline fills from its base.
  local kind, giver = guidParts(UnitGUID("npc"))
  if kind then
    q.giver = { type = kind, id = giver }
    q.giverName = UnitName("npc")
  end
  local map, x, y = playerPos()
  if map then q.pos = { map = map, x = x, y = y } end
  q.rewards = {
    choices = questItems("choice", GetNumQuestChoices and GetNumQuestChoices() or 0),
    items = questItems("reward", GetNumQuestRewards and GetNumQuestRewards() or 0),
    money = GetRewardMoney and GetRewardMoney() or 0,
    xp = GetRewardXP and GetRewardXP() or 0,
  }
  d.quests[id] = q
end

function handlers.QUEST_PROGRESS()
  local d, id = db(), questID()
  if not d or not id then return end
  local q = d.quests[id] or {}
  q.progress = GetProgressText()
  d.quests[id] = q
end

function handlers.QUEST_COMPLETE()
  local d, id = db(), questID()
  if not d or not id then return end
  local q = d.quests[id] or {}
  q.completion = GetRewardText()
  local kind, ender = guidParts(UnitGUID("npc"))
  if kind then
    q.ender = { type = kind, id = ender }
    q.enderName = UnitName("npc")
  end
  d.quests[id] = q
end

--- One creature, as the client describes it while it is targeted or under the mouse.
local function recordUnit(token)
  local d = db()
  if not d then return end
  local kind, id = guidParts(UnitGUID(token))
  if kind ~= "Creature" or not id then return end
  local n = d.npcs[id] or { sightings = {} }
  local level = UnitLevel(token)
  n.name = UnitName(token) or n.name
  n.level = (type(level) == "number" and level > 0) and level or "??"
  n.classification = UnitClassification(token) or n.classification
  n.type = UnitCreatureType(token) or n.type
  n.reaction = UnitReaction("player", token) or n.reaction
  n.factionGroup = UnitFactionGroup(token) or n.factionGroup
  addSighting(n.sightings)
  d.npcs[id] = n
end

function handlers.PLAYER_TARGET_CHANGED()
  recordUnit("target")
end

function handlers.UPDATE_MOUSEOVER_UNIT()
  recordUnit("mouseover")
end

function handlers.MERCHANT_SHOW()
  local d = db()
  if not d then return end
  local _kind, npcID = guidParts(UnitGUID("npc"))
  if not npcID then return end
  local items = {}
  for i = 1, (GetMerchantNumItems() or 0) do
    if #items >= MAX_VENDOR_ITEMS then break end
    local id = itemIdFromLink(GetMerchantItemLink(i))
    if id then
      local name, _texture, price, quantity, numAvailable = GetMerchantItemInfo(i)
      items[#items + 1] = { id = id, price = price or 0, quantity = quantity or 1,
                            numAvailable = numAvailable or -1 }
      nameItem(d, id, name or itemNameFromLink(GetMerchantItemLink(i)))
    end
  end
  if #items > 0 then d.vendors[npcID] = { items = items } end
end

function handlers.LOOT_OPENED()
  local d = db()
  if not d then return end
  local counted = {}
  for slot = 1, (GetNumLootItems() or 0) do
    local link = GetLootSlotLink(slot)
    local itemID = itemIdFromLink(link)
    local _texture, lootName = GetLootSlotInfo(slot)
    nameItem(d, itemID, lootName or itemNameFromLink(link))
    local sources = { GetLootSourceInfo(slot) }
    -- GetLootSourceInfo returns guid, quantity pairs: one corpse, or several in a pile
    for i = 1, #sources - 1, 2 do
      local kind, id = guidParts(sources[i])
      if (kind == "Creature" or kind == "GameObject") and id then
        local key = sourceKey(kind, id)
        if not counted[sources[i]] then
          counted[sources[i]] = true
          if firstLoot(sources[i]) then d.kills[key] = (d.kills[key] or 0) + 1 end
        end
        if itemID then
          local from = d.loot[key] or {}
          from[itemID] = (from[itemID] or 0) + (tonumber(sources[i + 1]) or 1)
          d.loot[key] = from
        end
      end
    end
  end
end

-- -- dungeon entrances -------------------------------------------------------------------------

--- Which instance the player is standing in, by the `Map` id the pipeline files dungeons under.
--- The eighth return of `GetInstanceInfo` is that id; the client offers it nowhere else.
local function instanceMapID()
  if not GetInstanceInfo then return nil end
  local _name, _kind, _difficulty, _difficultyName, _maxPlayers, _dynamic, _isDynamic, mapID =
    GetInstanceInfo()
  return tonumber(mapID)
end

local function inInstance()
  if not IsInInstance then return false end
  local inside = IsInInstance()
  return inside and true or false
end

--- Keep one reading of one door. A reading taken standing at it - the client putting the player
--- down outside as they leave - outranks one taken walking up to it, and a later reading of the
--- same kind replaces an earlier one, so a door gets better the more it is used. `samples` counts
--- every reading the entry has seen, which is what lets the pipeline weigh one door against
--- another; the entry itself stays one row per instance.
local function writeEntrance(d, id, spot, atDoor)
  local known = d.entrances[id]
  local samples = (known and known.samples or 0) + 1
  if known and known.exit and not atDoor then
    known.samples = samples                 -- an approach never overwrites the door itself
    return
  end
  d.entrances[id] = { map = spot.map, x = spot.x, y = spot.y, samples = samples,
                      exit = atDoor or nil }
end

--- Where a dungeon's door is - the one fact about an instance no client table carries.
---
--- `AreaPOI` marks five doors in the whole of Classic Era, `UiMapLink` is empty on every Classic
--- client and `Map` holds no entrance position, so the only source there will ever be is a player
--- standing at one. Two things are read, on every event that can tell the addon the player moved:
--- the last outdoor position before an instance loads (an approach, which is a step from the door),
--- and the position the client puts them down at when they leave one (the door itself).
---
--- Bounded by the game: one entry per instance map id, one map read per event, no OnUpdate. The
--- outdoor position is spent when it is used, so a portal out of one instance straight into another
--- can never be read as that one's door, and an exit reading still showing the instance's own map -
--- the client has not caught up - is refused and taken on the next event instead.
local function recordEntrance()
  local d = db()
  if not d then return end
  if not inInstance() then
    local map, x, y = playerPos()
    if not map then return end
    if lastInstance and map ~= insideMap then
      writeEntrance(d, lastInstance, { map = map, x = x, y = y }, true)
      lastInstance = nil
    end
    lastOutdoor = { map = map, x = x, y = y }
    lastOutdoorMap = map
    return
  end
  local id = instanceMapID()
  if not id then return end
  if lastOutdoor then
    writeEntrance(d, id, lastOutdoor, false)
    lastOutdoor = nil
  end
  lastInstance = id
  local map = playerPos()
  insideMap = (map and map ~= lastOutdoorMap) and map or nil
end

function handlers.PLAYER_ENTERING_WORLD()
  recordEntrance()
end

function handlers.ZONE_CHANGED_NEW_AREA()
  recordEntrance()
end

--- A Classic portal - Deadmines' mineshaft, Blackrock's chains - fires neither of the two above.
function handlers.ZONE_CHANGED()
  recordEntrance()
end

function handlers.ZONE_CHANGED_INDOORS()
  recordEntrance()
end

-- -- world objects ---------------------------------------------------------------------------------

--- A tooltip the world owns, showing no unit, is a door, a chest, a herb or a mining node. The
--- client never says which object id it is, so the name it prints is the key until one is learned.
local function recordTooltipObject(tooltip)
  local d = db()
  if not d or tooltip:GetUnit() then return end
  if tooltip.GetOwner and tooltip:GetOwner() ~= UIParent then return end
  local line = GameTooltipTextLeft1
  local name = line and line:GetText()
  if type(name) ~= "string" or name == "" then return end
  local known = d.objects[name]
  if not known and objectCount >= MAX_OBJECTS then return end
  local o = known or { sightings = {} }
  if not addSighting(o.sightings) and not known then return end
  if not known then objectCount = objectCount + 1 end
  d.objects[name] = o
end

if GameTooltip and GameTooltip.HookScript then
  GameTooltip:HookScript("OnShow", guarded("tooltipErrors", recordTooltipObject))
end

-- -- wiring ------------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
  frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", guarded("eventErrors", function(_self, event, ...)
  local handler = handlers[event]
  if handler then handler(...) end
end))

--- `/foreverdiff` used to be this command's second word. It is the link box's now (below), because
--- that is the one a player who has never heard of this addon will guess, and `/fdc` - the word the
--- README and the in-game test script have always printed - is unchanged.
SLASH_FOREVERDIFFCOLLECTOR1 = "/fdc"
SlashCmdList["FOREVERDIFFCOLLECTOR"] = guarded("slashErrors", function(msg)
  local d = db()
  if not d then return end
  if (msg or ""):lower():match("^%s*reset%s*$") then
    emptyTables(d)
    print("ForeverDiff Collector: cleared.")
    return
  end
  local c = counts(d)
  print(string.format(
    "ForeverDiff Collector: %d quests, %d creatures, %d objects, %d vendors, %d looted sources, "
    .. "%d item names, %d dungeon entrances.",
    c.quests, c.npcs, c.objects, c.vendors, c.loot, c.items, c.entrances))
  print(string.format("Realm %s, build %s. Upload WTF/Account/<ACCOUNT>/SavedVariables/%s.lua "
                      .. "at foreverdiff /contribute. /fdc reset clears it.",
                      tostring(d.realm), tostring(d.build and d.build.version), ADDON_NAME))
  if ForeverDiffDebug.tooltipErrors > 0 or ForeverDiffDebug.slashErrors > 0 then
    print(string.format("ForeverDiff: %d tooltip error(s), %d command error(s). Last: %s",
                        ForeverDiffDebug.tooltipErrors, ForeverDiffDebug.slashErrors,
                        tostring(ForeverDiffDebug.lastError)))
  end
end)

-- -- what the site still needs, in the item tooltip ------------------------------------------------
--
-- The client's Lua has no HTTP, so the addon cannot ask ForeverDiff anything. The answer ships with
-- it instead: `ForeverDiffData.lua` is written by `wfd build` for the Forever build, uploaded with
-- the rest of the dataset and put into the download zip at request time, so the list of items the
-- site is still missing is refreshed without an addon release and without an app deploy.
--
-- Three rules, and all three are about staying out of the way:
--
--   * an item the site already has adds **nothing** - no line, no blank line, no header. A database
--     addon that writes on every tooltip is one a player turns off in a week;
--   * no data file (the site could not fetch it, or the player unzipped an older build) adds
--     nothing and says nothing. `ForeverDiffData` is simply nil and every read below is guarded;
--   * nothing in here may ever raise. Every hook body runs inside `pcall`, a failure is counted in
--     `ForeverDiffDebug` and printed by `/fdc` if a player is asked for it, and the tooltip the
--     player is actually looking at is untouched. A Lua error thrown from a tooltip hook is a red
--     box on every mouseover until the addon is disabled.

--- Counted rather than printed: an error inside a tooltip hook must not become an error message on
--- top of the tooltip. `/fdc` reports these, which is what a player can be asked for.


--- What each gap code puts in the tooltip's second line. `sources` is the site's own wording for
--- the same absence ("Where this item comes from has not been recorded by a contributor yet"),
--- shortened to fit a tooltip. A code this addon has no wording for still gets a line, because the
--- data file is generated by a newer pipeline than the addon whenever the two are out of step.
local GAP_TEXT = {
  sources = "Where it comes from is not recorded",
}
local GAP_TEXT_DEFAULT = "This item's world data is not recorded"
--- The gold the site's own accent is, and the grey the client writes its own secondary lines in.
local GOLD = { r = 1, g = 0.82, b = 0.09 }
local GREY = { r = 0.7, g = 0.7, b = 0.7 }
--- U+00B7 MIDDLE DOT and U+00D7 MULTIPLICATION SIGN, as the UTF-8 bytes the client's fonts draw.
--- Written as escapes rather than as the characters themselves so that nothing between this file
--- and the player's disk - a zip, an editor, a patch - can re-encode them into mojibake.
local DOT = "\194\183"
local TIMES = "\195\151"

local function data()
  local d = ForeverDiffData
  return type(d) == "table" and type(d.items) == "table" and d or nil
end

--- What the site knows about one item id, or nil when it needs nothing (or there is no data file).
local function entryFor(itemID)
  local d = data()
  if not d or not itemID then return nil end
  local row = d.items[itemID]
  return type(row) == "table" and row or nil
end

--- Where a contributor is sent for one item: the contribute form when the site named a gap, and the
--- item's own page otherwise. `site/lib/placeholders.ts::contributeHref` is the contract this
--- mirrors - `/contribute?type=items&id=<id>&gap=<gap>`, in that order.
local function urlFor(itemID)
  local d = data()
  local site = (d and type(d.site) == "string" and d.site) or "https://foreverdiff.gg"
  local row = entryFor(itemID)
  if row and type(row.gap) == "string" then
    return string.format("%s/contribute?type=items&id=%d&gap=%s", site, itemID, row.gap)
  end
  return string.format("%s/items/%d", site, itemID)
end

--- The second line: what is missing, how much the site already knows, and how to get the link.
---
--- A count the data did not carry is left out of the line rather than printed as a zero. Zero is a
--- real answer here - "nobody has recorded this, you would be the first" - and the pipeline writes
--- it as zero; a *nil* means the build could not measure it at all, and the line says less instead
--- of saying something untrue.
local function detailLine(row)
  local parts = { GAP_TEXT[row.gap] or GAP_TEXT_DEFAULT }
  if type(row.seen) == "number" then
    parts[#parts + 1] = "seen " .. row.seen .. TIMES
  end
  if type(row.contributions) == "number" then
    parts[#parts + 1] = row.contributions .. " contribution" ..
                        (row.contributions == 1 and "" or "s")
  end
  parts[#parts + 1] = "/fd for the link"
  return table.concat(parts, " " .. DOT .. " ")
end

--- `|cff...|Hitem:1234:...|h[Name]|h|r` -> 1234. The same reading the collector does of a link.
local function tooltipItemID(tooltip, payload)
  if not (tooltip and tooltip.GetItem) then return nil end
  local _name, link = tooltip:GetItem()
  return itemIdFromLink(link)
end

--- Add ForeverDiff's two lines to one item tooltip, or add nothing at all.
local function addLines(tooltip, payload)
  if not (tooltip and tooltip.AddLine) then return end
  local itemID = tooltipItemID(tooltip, payload)
  local row = entryFor(itemID)
  if not row then return end
  -- one tooltip, one set of lines, however many times the client processes it before it hides
  if tooltip.foreverDiffFor == itemID then return end
  tooltip.foreverDiffFor = itemID
  tooltip:AddLine("ForeverDiff: needs a contribution", GOLD.r, GOLD.g, GOLD.b)
  tooltip:AddLine(detailLine(row), GREY.r, GREY.g, GREY.b)
  if tooltip.Show then tooltip:Show() end
end

local onTooltipItem = guarded("tooltipErrors", addLines)
--- The mark that stops a re-processed tooltip printing the lines twice is cleared whenever the
--- client clears or hides the tooltip, so the *next* look at the same item is a fresh one.
local forget = guarded("tooltipErrors", function(tooltip)
  if tooltip then tooltip.foreverDiffFor = nil end
end)

--- Both tooltip APIs, chosen by what the client has rather than by which client it is.
---
--- A 10.x-engine client (Classic Era 1.15 and, as far as anyone outside Blizzard knows, Forever)
--- routes every tooltip through `TooltipDataProcessor`, and one post-call covers `GameTooltip`, the
--- clicked-link tooltip, bags, the character sheet and every other frame that shows an item. An
--- older engine has no such thing and the script hook is the only way in, and there it has to be
--- attached to each tooltip frame by hand.
local function install()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
     and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltipItem)
  else
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
      if tooltip and tooltip.HookScript then
        tooltip:HookScript("OnTooltipSetItem", onTooltipItem)
      end
    end
  end
  -- on both paths, and on the tooltips a player actually reads: clearing the mark is what lets the
  -- same item be described again the next time it is hovered
  for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tooltip and tooltip.HookScript then
      pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", forget)
      pcall(tooltip.HookScript, tooltip, "OnHide", forget)
    end
  end
end

guarded("tooltipErrors", install)()

-- -- /foreverdiff, /fd: the link, in a box a player can copy out of ---------------------------------
--
-- Hayden's ask, verbatim: "an easy 0 friction way to do so (maybe the forever diff addon slash
-- command and linking the item to create a link they can copy paste from a copy paste box".
--
-- The client cannot open a browser and cannot put anything on the system clipboard. A read-only
-- edit box with the text already selected is as close as the game gets: Ctrl+C is then one key.

local linkFrame = nil

--- Build the little window once, the first time somebody asks for a link. Nothing is created at
--- load: an addon that builds frames nobody opens costs every player the memory and the taint.
local function buildFrame()
  local win = CreateFrame("Frame", "ForeverDiffLinkFrame", UIParent,
                          BackdropTemplateMixin and "BackdropTemplate" or nil)
  -- SetWidth/SetHeight rather than SetSize: the same call on every client this addon has ever been
  -- loaded on, which is the whole budget for guessing what the Forever client supports
  win:SetWidth(420)
  win:SetHeight(120)
  win:SetPoint("CENTER")
  win:SetFrameStrata("DIALOG")
  win:EnableMouse(true)
  win:SetMovable(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", guarded("slashErrors", win.StartMoving))
  win:SetScript("OnDragStop", guarded("slashErrors", win.StopMovingOrSizing))
  if win.SetBackdrop then
    win:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                      tile = true, tileSize = 32, edgeSize = 32,
                      insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  end

  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -16)
  title:SetText("ForeverDiff")
  win.title = title

  local box = CreateFrame("EditBox", "ForeverDiffLinkBox", win, "InputBoxTemplate")
  box:SetWidth(360)
  box:SetHeight(20)
  box:SetPoint("TOP", 0, -44)
  box:SetAutoFocus(false)
  box:SetScript("OnEscapePressed", guarded("slashErrors", function() win:Hide() end))
  box:SetScript("OnEnterPressed", guarded("slashErrors", function(self) self:HighlightText() end))
  -- read-only by restoration rather than by a flag the older clients do not have: whatever is typed
  -- is put back, so the URL cannot be edited away and then copied wrong
  box:SetScript("OnTextChanged", guarded("slashErrors", function(self)
    if self.settingText then return end
    if self:GetText() ~= (self.url or "") then
      self.settingText = true
      self:SetText(self.url or "")
      self.settingText = nil
    end
    self:HighlightText()
  end))
  win.box = box

  local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOP", box, "BOTTOM", 0, -8)
  hint:SetText("Ctrl+C to copy, Esc to close")

  local close = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  close:SetWidth(80)
  close:SetHeight(22)
  close:SetPoint("BOTTOM", 0, 14)
  close:SetText("Close")
  close:SetScript("OnClick", guarded("slashErrors", function() win:Hide() end))

  -- Esc closes it, the way every other window in the game does
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "ForeverDiffLinkFrame")
  end
  win:Hide()
  return win
end

--- Show one URL, selected and focused, ready for Ctrl+C.
local function showLink(url)
  linkFrame = linkFrame or buildFrame()
  local box = linkFrame.box
  box.url = url
  box.settingText = true
  box:SetText(url)
  box.settingText = nil
  linkFrame:Show()
  box:SetFocus()
  box:HighlightText()
end

--- The item a player put after `/fd`: a shift-clicked link, a `[Name]` hyperlink pasted in, or the
--- bare id somebody read off the site.
local function askedItem(msg)
  local text = msg or ""
  return itemIdFromLink(text) or tonumber(text:match("^%s*(%d+)%s*$"))
end

SLASH_FOREVERDIFF1 = "/foreverdiff"
SLASH_FOREVERDIFF2 = "/fd"
SlashCmdList["FOREVERDIFF"] = guarded("slashErrors", function(msg)
  local itemID = askedItem(msg)
  if not itemID then
    print("ForeverDiff: shift-click an item after /fd to get its link")
    return
  end
  showLink(urlFor(itemID))
end)
