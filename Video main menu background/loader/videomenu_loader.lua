-- ============================================================
--  Video Menu Loader  (tiny loader that has to be installed locally)
--
--  Put this file at:   garrysmod/lua/includes/videomenu_loader.lua
--  then add this line at the END of garrysmod/lua/includes/init_menu.lua :
--      include("videomenu_loader.lua")
--
--  It waits until addon 1 (videomenu_core) is mounted, reads
--  lua/videomenu/videomenu_main.lua from it and runs it in the menu state.
--  Works for addons in garrysmod/addons/ and for Workshop addons.
-- ============================================================
if not MENU_DLL then return end

if not (timer and timer.Create and hook and hook.Add) then
	print("[VideoMenu] timer/hook are not ready - loader disabled")
	return
end

VideoMenuLoader = VideoMenuLoader or {}
local L = VideoMenuLoader
if L.Started then return end
L.Started = true

local CORE = "lua/videomenu/videomenu_main.lua"

local function Log(msg)
	print("[VideoMenu] " .. tostring(msg))
end

-- Find which path ID holds a file:
--   "GAME"       = the game folder, addons in garrysmod/addons/ and mounted Workshop addons
--   addon title  = a mounted Workshop addon (same approach as Aperture Theme Engine)
-- Returns nil when the file is not found (yet).
function L.FindFile(path)
	if file.Exists(path, "GAME") then return "GAME" end

	local addons = engine and engine.GetAddons and engine.GetAddons()
	if addons then
		for _, a in ipairs(addons) do
			local title = a.title
			if a.mounted and type(title) == "string" and title ~= "" then
				local ok, found = pcall(file.Exists, path, title)
				if ok and found then return title end
			end
		end
	end

	return nil
end

local function LoadCore()
	local id = L.FindFile(CORE)
	if not id then return false end

	local code = file.Read(CORE, id)
	if not code or code == "" then
		Log("core found but could not be read (path ID: " .. tostring(id) .. ")")
		return false
	end

	L.CoreId = id

	-- The menu state has no CompileString, so use RunString (Shared and Menu).
	-- handleError = false: errors are returned as a string instead of being thrown.
	local err = RunString(code, "videomenu_main.lua", false)
	if type(err) == "string" and err ~= "" then
		return true, err -- do not retry; the code itself has to be fixed
	end
	return true
end

local tries = 0
local errShown = false

local function Try()
	if L.Loaded then return end
	tries = tries + 1

	local ok, res, coreErr = pcall(LoadCore)
	if not ok then
		if not errShown then
			errShown = true
			Log("loader error: " .. tostring(res))
		end
		return
	end

	if res then
		L.Loaded = true
		timer.Remove("VideoMenuLoader_Wait")
		hook.Remove("GameContentChanged", "VideoMenuLoader_Watch")
		if coreErr then
			Log("core ran from path ID " .. tostring(L.CoreId) .. " but reported an error: " .. coreErr)
		else
			Log("core loaded from path ID: " .. tostring(L.CoreId))
		end
	elseif tries == 20 then
		Log("addon 1 not found (" .. CORE .. ") - check that it is installed and enabled")
	end
end

-- Workshop addons are mounted after the menu starts, so keep retrying
timer.Create("VideoMenuLoader_Wait", 1, 600, Try)
hook.Add("GameContentChanged", "VideoMenuLoader_Watch", Try)
