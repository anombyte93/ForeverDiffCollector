package.path = "addon/tests/?.lua;" .. package.path
local api = require("stub_api")
dofile("addon/ForeverDiffCollector/ForeverDiffCollector.lua")
api.FireEvent("ADDON_LOADED", "ForeverDiffCollector")
local getUnit = GameTooltip.GetUnit
GameTooltip.GetUnit = function() error("bad client tooltip") end
assert(pcall(function() GameTooltip:Show() end), "world tooltip errors must not escape")
GameTooltip.GetUnit = getUnit
assert(ForeverDiffDebug.tooltipErrors > 0)
api.Slash("/fd", "25")
local box = ForeverDiffLinkBox
box.HighlightText = function() error("bad editbox") end
assert(pcall(function() box:FireScript("OnTextChanged") end), "editbox hooks must not escape")
assert(ForeverDiffDebug.slashErrors > 0)
assert(pcall(function() api.Slash("/fdc", {}) end), "collector slash errors must not escape")
io.write("3 adversarial hook safety checks passed\n")
