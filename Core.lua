-- Core: the AceAddon object, its AceDB profiles, and the default paging
-- rules. Each profile holds:
--   enabled  -- master toggle for stance/vehicle paging
--   stances  -- [offset 1-12] = { {from, count, to}, ... }, gamepad slot
--               from..from+count-1 fires slot to..to+count-1 on that stance
--   vehicle  -- { {from, count, to}, ... }, gamepad slot fires main-bar
--               position to..to+count-1 of the vehicle/override/possess page
--   camera   -- Turn With Camera while held: enabled, modifier, held and
--               released values (Camera.lua)
-- Rules within one list never overlap (Options.lua enforces it), so their
-- order doesn't matter.
--
-- The rule lists are seeded into each profile once (seeded = true) instead of
-- being AceDB defaults: AceDB fills a missing key back in from its defaults,
-- so a default rule the user deleted would reappear.
local _, _, env = CPAPI.LinkEnv(...)
local AceDB = LibStub('AceDB-3.0')

if not C_GamepadUI then return end

local Addon = LibStub('AceAddon-3.0'):NewAddon('ConsolePort_GamepadSlots')
env.Addon = Addon

env.FIRST_SLOT    = C_GamepadUI.GetFirstGamepadActionStorageSlotIndex()
env.LAST_SLOT     = env.FIRST_SLOT + 179
env.NUM_STANCES   = 12
env.NUM_POSITIONS = NUM_ACTIONBAR_BUTTONS

---------------------------------------------------------------
-- Default rules (LyraelForever's layout, GAMEPAD-LAYOUT.md)
---------------------------------------------------------------
-- Blizzard's gamepad UI has five stance storage bars
-- (NUM_GAMEPAD_STANCE_ACTION_BARS), so only offsets 1-5 get defaults.
local NUM_DEFAULT_STANCES = 5

function env.GetDefaultStanceRules(offset)
	if offset > NUM_DEFAULT_STANCES then return {} end
	return {
		{ from = 193, count = 8, to = 257 + 8 * offset };       -- right bar as the form bar
		{ from = 205, count = 4, to = 209 + 4 * (offset - 1) }; -- bottom X, Y, B, A
		{ from = 329, count = 2, to = 349 + 2 * (offset - 1) }; -- top Y, B
	};
end

-- Most-used buttons first, so they land on the vehicle bar's six real
-- buttons (positions 1-6). The left bar is left out on purpose: it holds
-- actions that stay the same everywhere, so it keeps its own slots.
function env.GetDefaultVehicleRules()
	return {
		{ from = 181, count = 2, to = 11 }; -- top D-pad left, up
		{ from = 197, count = 4, to = 3 };  -- right X, Y, B, A
		{ from = 205, count = 4, to = 7 };  -- bottom X, Y, B, A
		{ from = 329, count = 2, to = 1 };  -- top Y, B
	};
end

local function SeedProfile(profile)
	if profile.seeded then return end
	profile.stances = {};
	for offset = 1, env.NUM_STANCES do
		profile.stances[offset] = env.GetDefaultStanceRules(offset);
	end
	profile.vehicle = env.GetDefaultVehicleRules();
	profile.seeded = true;
end

function env.GetProfile()
	return Addon.db and Addon.db.profile;
end

---------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------
function Addon:OnInitialize()
	self.db = AceDB:New('ConsolePortGamepadSlotsDB', { profile = {
		enabled = true;
		camera  = { enabled = true, modifier = 'ctrl', held = 1, released = 0, ignoreCastOverride = true };
	} }, true)
	SeedProfile(self.db.profile)

	local function OnProfileChanged()
		SeedProfile(self.db.profile)
		env.Paging:Push()
		env.Camera:Refresh()
	end
	self.db.RegisterCallback(self, 'OnProfileChanged', OnProfileChanged)
	self.db.RegisterCallback(self, 'OnProfileCopied', OnProfileChanged)
	self.db.RegisterCallback(self, 'OnProfileReset', OnProfileChanged)

	env.SetupOptions()
	env.Paging:Push()
	env.Camera:Refresh()
end
