-- The slice of the Classic-line client API the collector calls, and nothing else.
--
-- Every function reads `api.state`, which a test sets before firing an event, so a test says what the
-- client would have said and then checks what the addon wrote. `api.FireEvent(name, ...)` is the
-- client's event dispatcher: it calls the OnEvent script of every frame that registered `name`.
--
-- Two entries are not in the brief's list and are here because an object has no other name: the
-- default UI anchors a world tooltip to `UIParent` and writes the name into `GameTooltipTextLeft1`.

local api = {}

api.state = {
  --- The Forever beta as it really reports itself: `wow_classic_beta` 1.60.1.69893, build-name
  --- WOW-69893patch1.60.1_ForeverBeta (data/raw/wow_classic_beta/1.60.1.69893/build.json), whose
  --- interface number is major * 10000 + minor * 100 + patch. This was "1.27.0" with an interface of
  --- 11509 - two different clients in one table, and a version prefix `wfd.world.observed` refuses
  --- outright - so nothing that ingested the harness's own output could ever have worked.
  build = { version = "1.60.1", build = "69893", date = "Sep 16 2026", interface = 16001 },
  realm = "Nostalgia",
  player = { map = 1429, x = 0.421, y = 0.604 },
  quest = nil,      -- { id, title, description, objectives, progress, completion, money, xp,
                    --   choices = { "|Hitem:182:..." }, rewards = { ... } }
  units = {},       -- unit token -> { guid, name, level, classification, type, reaction, faction }
  merchant = {},    -- { { link, price, quantity, numAvailable } }
  loot = {},        -- { { link, quantity, sources = { guid, quantity, ... } } }
  tooltip = { unit = nil, text = nil, owner = nil, item = nil },
                    --   `item` = { name, link } while an item tooltip is up (api.HoverItem)
  instance = nil,   -- nil outdoors, else { kind = "party", mapID = 36, name = "The Deadmines" }
}
api.printed = {}
api.frames = {}

-- -- frames and events ------------------------------------------------------------------------

local frameMethods = {}
frameMethods.__index = frameMethods
--- Declared before the methods that call it: a method body compiled before this line would read a
--- *global* `newFrame`, which is nil, and every `CreateFontString` would fail at the first `/fd`.
local newFrame

function frameMethods:RegisterEvent(event)
  self.events[event] = true
end

function frameMethods:UnregisterEvent(event)
  self.events[event] = nil
end

function frameMethods:SetScript(name, fn)
  self.scripts[name] = fn
end

function frameMethods:GetScript(name)
  return self.scripts[name]
end

function frameMethods:HookScript(name, fn)
  local hooks = self.hooks[name] or {}
  hooks[#hooks + 1] = fn
  self.hooks[name] = hooks
end

function frameMethods:Show()
  self.shown = true
  for _, fn in ipairs(self.hooks.OnShow or {}) do fn(self) end
end

function frameMethods:Hide()
  self.shown = false
  for _, fn in ipairs(self.hooks.OnHide or {}) do fn(self) end
end

function frameMethods:IsShown()
  return self.shown == true
end

--- Fire one hooked script by hand, the way the client does when it clears or hides a tooltip.
function frameMethods:FireHook(name, ...)
  for _, fn in ipairs(self.hooks[name] or {}) do fn(self, ...) end
end

-- Geometry, dragging, strata and mouse: the client answers all of these and the addon calls them
-- while building its link window. They record nothing a test reads - what matters is that they
-- exist, because a missing one is a Lua error in the player's face the first time they type /fd.
local function noop() end
for _, name in ipairs({ "SetWidth", "SetHeight", "SetSize", "SetPoint", "SetAllPoints",
                        "SetFrameStrata", "EnableMouse", "SetMovable", "RegisterForDrag",
                        "StartMoving", "StopMovingOrSizing", "SetBackdrop", "SetAutoFocus",
                        "SetJustifyH", "SetTextColor", "SetFontObject", "SetMultiLine",
                        "SetMaxLetters" }) do
  frameMethods[name] = noop
end

--- What an `EditBox` is, for this addon's purposes: text, a selection and the focus.
function frameMethods:SetText(text)
  self.text = text
  self.highlighted = false
  self:FireScript("OnTextChanged")
end

function frameMethods:GetText()
  return self.text or ""
end

function frameMethods:HighlightText()
  self.highlighted = true
end

function frameMethods:SetFocus()
  self.focused = true
  api.focus = self
end

function frameMethods:ClearFocus()
  self.focused = false
  if api.focus == self then api.focus = nil end
end

--- Run a `SetScript` handler the way the client would, if one is set.
function frameMethods:FireScript(name, ...)
  local fn = self.scripts[name]
  if fn then return fn(self, ...) end
end

function frameMethods:CreateFontString(_name, _layer, _template)
  return newFrame()
end

function newFrame(kind, name)
  local f = setmetatable({ events = {}, scripts = {}, hooks = {}, kind = kind, frameName = name },
                         frameMethods)
  api.frames[#api.frames + 1] = f
  if name then _G[name] = f end
  return f
end

function CreateFrame(kind, name, _parent, _template)
  return newFrame(kind, name)
end

--- The list the client's Esc key reads. An addon that wants Esc to close its window puts the
--- window's global name in here.
UISpecialFrames = {}

--- Dispatch one event exactly as the client does: every frame that registered it, in creation order.
function api.FireEvent(event, ...)
  for _, f in ipairs(api.frames) do
    if f.events[event] and f.scripts.OnEvent then
      f.scripts.OnEvent(f, event, ...)
    end
  end
end

-- -- the world -------------------------------------------------------------------------------

function GetBuildInfo()
  local b = api.state.build
  return b.version, b.build, b.date, b.interface
end

function GetRealmName()
  return api.state.realm
end

C_Map = {
  GetBestMapForUnit = function(_unit)
    return api.state.player and api.state.player.map
  end,
  GetPlayerMapPosition = function(_map, _unit)
    local p = api.state.player
    if not p or not p.x then return nil end
    return { GetXY = function() return p.x, p.y end }
  end,
}

-- -- instances -------------------------------------------------------------------------------

--- `inInstance, instanceType`, exactly as the client answers it: false and "none" outdoors.
function IsInInstance()
  local i = api.state.instance
  if not i then return false, "none" end
  return true, i.kind or "party"
end

--- name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic,
--- instanceMapID, instanceGroupSize - the eighth return is the `Map` id the addon files an
--- entrance under.
function GetInstanceInfo()
  local i = api.state.instance or {}
  return i.name or "", i.kind or "none", 1, "Normal", 5, 0, false, i.mapID, 5
end

-- -- units -----------------------------------------------------------------------------------

local function unit(token)
  return api.state.units[token]
end

function UnitGUID(token)
  return unit(token) and unit(token).guid
end

function UnitName(token)
  return unit(token) and unit(token).name
end

function UnitLevel(token)
  return unit(token) and unit(token).level
end

function UnitClassification(token)
  return unit(token) and unit(token).classification
end

function UnitCreatureType(token)
  return unit(token) and unit(token).creatureType
end

function UnitReaction(_a, token)
  return unit(token) and unit(token).reaction
end

function UnitFactionGroup(token)
  return unit(token) and unit(token).factionGroup
end

-- -- quests ----------------------------------------------------------------------------------

local function quest()
  return api.state.quest or {}
end

function GetQuestID()
  return quest().id or 0
end

function GetTitleText()
  return quest().title
end

function GetQuestText()
  return quest().description
end

function GetObjectiveText()
  return quest().objectives
end

function GetProgressText()
  return quest().progress
end

function GetRewardText()
  return quest().completion
end

function GetRewardMoney()
  return quest().money or 0
end

function GetRewardXP()
  return quest().xp or 0
end

function GetNumQuestChoices()
  return #(quest().choices or {})
end

function GetNumQuestRewards()
  return #(quest().rewards or {})
end

function GetQuestItemLink(kind, index)
  local list = kind == "choice" and quest().choices or quest().rewards
  return list and list[index]
end

-- -- vendors ---------------------------------------------------------------------------------

function GetMerchantNumItems()
  return #api.state.merchant
end

function GetMerchantItemLink(index)
  local row = api.state.merchant[index]
  return row and row.link
end

function GetMerchantItemInfo(index)
  local row = api.state.merchant[index]
  if not row then return nil end
  -- name, texture, price, quantity, numAvailable, isPurchasable, isUsable, extendedCost
  return row.name or "Item", nil, row.price, row.quantity, row.numAvailable, true, true, false
end

-- -- loot ------------------------------------------------------------------------------------

function GetNumLootItems()
  return #api.state.loot
end

function GetLootSourceInfo(slot)
  local row = api.state.loot[slot]
  if not row or not row.sources then return nil end
  return unpack(row.sources)
end

function GetLootSlotInfo(slot)
  local row = api.state.loot[slot]
  if not row then return nil end
  -- texture, name, quantity, currencyID, quality, locked, isQuestItem, questID, isActive
  return nil, row.name or "Item", row.quantity or 1, nil, 1, false, false, nil, false
end

function GetLootSlotLink(slot)
  local row = api.state.loot[slot]
  return row and row.link
end

-- -- tooltip ---------------------------------------------------------------------------------
--
-- Two tooltip APIs exist in the Classic line and the addon has to work on both, so the stub offers
-- both and `FDC_TOOLTIP_API=legacy` takes the newer one away. `ops/test-addon.sh` runs the whole
-- harness once each way: a client that routes tooltips through `TooltipDataProcessor` (the 10.x
-- engine Classic Era 1.15 is built on) and one that has only `OnTooltipSetItem`.

UIParent = newFrame("Frame", "UIParent")

--- What a tooltip frame answers while it is showing something, and what an addon wrote onto it.
local function newTooltip(name)
  local tt = newFrame("GameTooltip", name)
  tt.lines = {}
  function tt:GetUnit()
    return api.state.tooltip.unit, api.state.tooltip.unit and "mouseover"
  end
  function tt:GetOwner()
    return api.state.tooltip.owner
  end
  --- `name, link` - the client answers both, and the addon reads the id out of the link.
  function tt:GetItem()
    local item = api.state.tooltip.item
    if not item then return nil end
    return item.name, item.link
  end
  function tt:AddLine(text, r, g, b)
    self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b }
  end
  function tt:AddDoubleLine(left, right)
    self.lines[#self.lines + 1] = { text = tostring(left) .. " " .. tostring(right) }
  end
  function tt:NumLines()
    return #self.lines
  end
  --- The client clearing the tooltip before it fills it with the next thing.
  function tt:ClearLines()
    self.lines = {}
    self:FireHook("OnTooltipCleared")
  end
  return tt
end

GameTooltip = newTooltip("GameTooltip")
ItemRefTooltip = newTooltip("ItemRefTooltip")

GameTooltipTextLeft1 = { GetText = function() return api.state.tooltip.text end }

--- The 10.x tooltip pipeline, absent on `FDC_TOOLTIP_API=legacy`. `AddTooltipPostCall` registers
--- one function per data type, called after the client has filled any tooltip of that type.
api.tooltipPostCalls = {}
if os.getenv("FDC_TOOLTIP_API") ~= "legacy" then
  Enum = { TooltipDataType = { Item = 0, Unit = 2, Spell = 5 } }
  TooltipDataProcessor = {
    AddTooltipPostCall = function(dataType, fn)
      local list = api.tooltipPostCalls[dataType] or {}
      list[#list + 1] = fn
      api.tooltipPostCalls[dataType] = list
    end,
  }
end

--- Which API the addon actually installed itself into, as the harness reads it back.
function api.TooltipApi()
  if TooltipDataProcessor then return "modern" end
  return "legacy"
end

--- Hover an item: the client clears the tooltip, fills it, and tells whichever API exists.
---
--- `link` is an item link or nil for a tooltip that is showing no item at all. `tooltip` defaults
--- to `GameTooltip`; pass `ItemRefTooltip` for a link clicked in chat.
function api.HoverItem(link, tooltip)
  tooltip = tooltip or GameTooltip
  tooltip:ClearLines()
  api.state.tooltip = { unit = nil, text = nil, owner = nil,
                        item = link and { name = link:match("%[(.-)%]") or "Item", link = link } }
  if TooltipDataProcessor then
    for _, fn in ipairs(api.tooltipPostCalls[Enum.TooltipDataType.Item] or {}) do
      fn(tooltip, { type = Enum.TooltipDataType.Item })
    end
  else
    tooltip:FireHook("OnTooltipSetItem")
  end
  return tooltip.lines
end

-- -- chat ------------------------------------------------------------------------------------

SlashCmdList = {}

local realPrint = print
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  api.printed[#api.printed + 1] = table.concat(parts, " ")
  if os.getenv("FDC_TEST_VERBOSE") then realPrint(...) end
end

--- Run a slash command the way the chat frame does: the handler under ANY of its `SLASH_<NAME><n>`
--- words. Every word counts, because `/fd` is the second word of the command a player will type and
--- a harness that only ever read the first would have proved nothing about the alias.
function api.Slash(command, rest)
  for name, fn in pairs(SlashCmdList) do
    local n = 1
    while _G["SLASH_" .. name .. n] do
      if _G["SLASH_" .. name .. n] == command then
        fn(rest or "")
        return true
      end
      n = n + 1
    end
  end
  return false
end

return api
