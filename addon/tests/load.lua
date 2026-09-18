-- Load every file the .toc lists, in .toc order, the way the client does.
--
-- Hayden, 2026-09-17: "we really want to be sure the addon works from the get go." The harness
-- beside this file proves what the addon *records*; it cannot prove the addon loads, because it
-- `dofile`s one path it knows about. A file added to the .toc and never loaded, a file renamed, a
-- syntax slip in a file the harness does not touch: every one of those is an addon that greys out
-- in the AddOns list with no explanation, and none of them would fail a single check over there.
--
-- So this reads the .toc itself, compiles each `.lua` it names with `loadfile` (the compile is the
-- syntax gate) and then RUNS it against the stub client API in the order the client would, so that
-- a file reading a global an earlier file was supposed to define fails here rather than in the game.
--
-- The generated data file is included when `--data <path>` names one - `ops/test-addon.sh` has the
-- pipeline write a real one first - and its absence is a pass, loudly, because that is exactly what
-- the client sees when the site could not fetch the table and served the addon without it.

local here = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local root = here .. "/../.."
package.path = here .. "/?.lua;" .. package.path

local dataPath = nil
for i = 1, #arg do
  if arg[i] == "--data" then dataPath = arg[i + 1] end
end

require("stub_api")

local failures, checks = 0, 0

local function ok(cond, what)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    io.write("FAIL ", what, "\n")
  end
end

local addonDir = root .. "/addon/ForeverDiffCollector"
local tocPath = addonDir .. "/ForeverDiffCollector.toc"
local handle = io.open(tocPath, "r")
ok(handle ~= nil, "the .toc is readable at " .. tocPath)
if not handle then
  io.write(string.format("%d files loaded, %d failures\n", 0, failures))
  os.exit(1)
end
local toc = handle:read("*a")
handle:close()

local listed = {}
for line in toc:gmatch("[^\r\n]+") do
  local file = line:match("^%s*([%w_%-]+%.lua)%s*$")
  if file then listed[#listed + 1] = file end
end
ok(#listed > 0, "the .toc lists at least one Lua file")

local loaded, absent = 0, {}
for _, file in ipairs(listed) do
  local path = addonDir .. "/" .. file
  if file == "ForeverDiffData.lua" and dataPath then
    path = dataPath
  end
  local probe = io.open(path, "r")
  if not probe then
    -- A listed file that is not on disk is what the client sees when the zip was served without the
    -- data table. It is not a failure; it is the degraded case, and it is named so a missing file
    -- nobody meant to be missing is still visible in the output.
    absent[#absent + 1] = file
    ok(file == "ForeverDiffData.lua" and not dataPath, "only optional data may be absent")
  else
    probe:close()
    local chunk, err = loadfile(path)
    ok(chunk ~= nil, file .. " compiles: " .. tostring(err))
    if chunk then
      local ran, runErr = pcall(chunk)
      ok(ran, file .. " runs against the stub client: " .. tostring(runErr))
      if ran then loaded = loaded + 1 end
    end
  end
end

-- What loading the addon has to have produced, checked here rather than assumed: the client reads
-- `SlashCmdList` and the global the data file defines, and neither is visible to a compile.
ok(type(SlashCmdList["FOREVERDIFFCOLLECTOR"]) == "function", "/fdc is registered after loading")
ok(type(SlashCmdList["FOREVERDIFF"]) == "function", "/foreverdiff is registered after loading")
ok(type(ForeverDiffDebug) == "table", "the addon's error counters exist after loading")
if dataPath then
  ok(type(ForeverDiffData) == "table" and type(ForeverDiffData.items) == "table",
     "the generated data file defined its table")
  local n = 0
  for _ in pairs((ForeverDiffData or {}).items or {}) do n = n + 1 end
  io.write(string.format("data: %s, %d item(s), site %s, build %s\n", dataPath, n,
                         tostring(ForeverDiffData.site), tostring(ForeverDiffData.build)))
end

io.write(string.format("%d of %d .toc file(s) loaded%s; %d checks, %d failures\n",
                       loaded, #listed,
                       #absent > 0 and (" (not on disk: " .. table.concat(absent, ", ") .. ")") or "",
                       checks, failures))
os.exit(failures == 0 and 0 or 1)
