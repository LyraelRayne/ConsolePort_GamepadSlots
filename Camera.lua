-- Camera: switches GamePadTurnWithCamera between two values while a modifier
-- (or the "Hold: Turn With Camera" binding) is held and when it's released --
-- the ConsolePort version of LyraelForever's LT camera switch.
--
-- ConsolePort manages the same CVar itself (Controller/Movement.lua): it
-- applies its own "Turn Character With Camera" setting, re-applies it on
-- combat changes, and forces Always while casting or in a vehicle, restoring
-- its setting afterwards. To stay out of each other's way:
--   * while ConsolePort's cast/vehicle override is active, this leaves the
--     CVar alone (its fmSpellOverride/fmVehicleOverride are set);
--   * after every ConsolePort update (Movement:UpdateTurnWithCamera, or its
--     setting changing) the held/released value is re-applied on the next
--     frame, once ConsolePort has finished clearing its override state.
-- The released value can also be "ConsolePort's setting", which applies
-- ConsolePort's own resolved value instead of a fixed one. The cast override
-- can be switched off entirely (ignoreCastOverride, below).
--
-- The modifier is read by a secure state driver ([modifier:ctrl] etc.), the
-- same way LyraelForever does it; setting the CVar itself is unprotected.
local _, _, env, db = CPAPI.LinkEnv(...)

if not C_GamepadUI then return end

local CVAR = 'GamePadTurnWithCamera'
local Movement = db.Movement

env.CAMERA_FOLLOW_CONSOLEPORT = -1
-- Blizzard_SettingsDefinitions_Shared/Gamepad.lua's labels for each value.
env.TURN_WITH_CAMERA_VALUES = {
	[0] = 'While moving';
	[1] = 'While moving or in combat';
	[3] = 'While moving, in combat or casting';
	[2] = 'Always';
};

local Camera = CreateFrame('Frame', 'ConsolePortGamepadSlotsCamera', UIParent, 'SecureHandlerStateTemplate')
env.Camera = Camera

local modifierHeld, bindingHeld = false, false

local function GetSettings()
	local profile = env.GetProfile()
	return profile and profile.camera
end

local function IsConsolePortOverriding()
	return Movement and ( Movement.fmSpellOverride ~= nil or Movement.fmVehicleOverride ~= nil )
end

local function Apply()
	local settings = GetSettings()
	if not settings or not settings.enabled or IsConsolePortOverriding() then return end
	local value = ( modifierHeld or bindingHeld ) and settings.held or settings.released
	if value == env.CAMERA_FOLLOW_CONSOLEPORT then
		if not Movement then return end
		value = Movement:GetTurnWithCameraValue()
	end
	C_CVar.SetCVar(CVAR, value)
end

local applyQueued = false;
local function QueueApply()
	if applyQueued then return end
	applyQueued = true
	RunNextFrame(function()
		applyQueued = false
		Apply()
	end)
end

if Movement then
	hooksecurefunc(Movement, 'UpdateTurnWithCamera', QueueApply)
	db:RegisterCallback('Settings/mvmtTurnWithCamera', QueueApply, Camera)

	-- ConsolePort forces Always for the length of every cast. With
	-- ignoreCastOverride on, its cast-start handlers do nothing, so it never
	-- records fmSpellOverride and its cast-stop handlers have nothing to
	-- restore -- the held/released value (or ConsolePort's own setting) stays
	-- in charge while casting. CPAPI.EventMixin looks handlers up by name on
	-- every event, so replacing the fields is enough. Vehicles are untouched.
	for _, event in ipairs({
		'UNIT_SPELLCAST_START';
		'UNIT_SPELLCAST_CHANNEL_START';
		'UNIT_SPELLCAST_EMPOWER_START';
	}) do
		local handler = Movement[event]
		if handler then
			Movement[event] = function(...)
				local settings = GetSettings()
				if settings and settings.ignoreCastOverride then return end
				return handler(...)
			end
		end
	end
end

---------------------------------------------------------------
-- Modifier driver
---------------------------------------------------------------
Camera:SetAttribute('_onstate-turnhold', [[ self:SetAttribute('held', newstate) ]])
Camera:HookScript('OnAttributeChanged', function(_, name, value)
	if name ~= 'held' then return end
	modifierHeld = tonumber(value) == 1
	Apply()
end)

local combatWatcher = CreateFrame('Frame')
combatWatcher:SetScript('OnEvent', function(self)
	self:UnregisterEvent('PLAYER_REGEN_ENABLED')
	Camera:Refresh()
end)

-- Rebuilds the driver from the profile and re-applies the CVar. Turning the
-- feature off hands the CVar back to ConsolePort's own setting.
function Camera:Refresh()
	if InCombatLockdown() then
		return combatWatcher:RegisterEvent('PLAYER_REGEN_ENABLED')
	end
	local settings = GetSettings()
	if not settings then return end
	local modifier = settings.enabled and settings.modifier
	if modifier and modifier ~= 'none' then
		RegisterStateDriver(self, 'turnhold', ('[modifier:%s] 1; 0'):format(modifier))
	else
		UnregisterStateDriver(self, 'turnhold')
		self:SetAttribute('held', 0)
	end
	if settings.enabled then
		Apply()
	elseif Movement and not IsConsolePortOverriding() then
		Movement:UpdateTurnWithCamera()
	end
end

---------------------------------------------------------------
-- Hold binding
---------------------------------------------------------------
-- For holding on a button that isn't a modifier. Modifiers themselves can't
-- carry a binding, so a modifier-only trigger needs the driver above.
local HOLD_BUTTON = 'ConsolePortGamepadTurnHold'
local holdButton = CreateFrame('Button', HOLD_BUTTON, UIParent, 'SecureActionButtonTemplate')
holdButton:RegisterForClicks('AnyDown', 'AnyUp')
holdButton:HookScript('OnClick', function(_, _, down)
	bindingHeld = not not down
	Apply()
end)

local bindingCommand = ('CLICK %s:LeftButton'):format(HOLD_BUTTON)
local bindingName = 'Hold: Turn With Camera'
_G[('BINDING_NAME_%s'):format(bindingCommand)] = bindingName

db.Bindings.Custom.GamepadTurnHold = bindingCommand;
db.Bindings.Special[#db.Bindings.Special + 1] = {
	binding = bindingCommand;
	name    = bindingName;
	desc    = 'Hold to use the "held" Turn With Camera value from the Gamepad Slots tab; release to go back to the "released" value. Only works while that feature is enabled.';
};

---------------------------------------------------------------
-- Look behind
---------------------------------------------------------------
-- A hold version of Blizzard's Flip Camera binding (FLIPCAMERAYAW), which
-- flips once per press: press turns the camera 180 degrees, release turns it
-- back. A release only undoes a flip this button made, so an up without a
-- matching down (e.g. held across a /reload) doesn't turn the camera.
local LOOK_BEHIND_BUTTON = 'ConsolePortGamepadLookBehind'
local lookBehindButton = CreateFrame('Button', LOOK_BEHIND_BUTTON, UIParent, 'SecureActionButtonTemplate')
lookBehindButton:RegisterForClicks('AnyDown', 'AnyUp')

local flipped = false
lookBehindButton:HookScript('OnClick', function(_, _, down)
	down = not not down
	if down ~= flipped then
		FlipCameraYaw(180)
		flipped = down
	end
end)

local lookBehindCommand = ('CLICK %s:LeftButton'):format(LOOK_BEHIND_BUTTON)
local lookBehindName = 'Flip Camera (Hold)'
_G[('BINDING_NAME_%s'):format(lookBehindCommand)] = lookBehindName

db.Bindings.Custom.GamepadLookBehind = lookBehindCommand;
db.Bindings.Special[#db.Bindings.Special + 1] = {
	binding = lookBehindCommand;
	name    = lookBehindName;
	desc    = 'Hold to look behind you: turns the camera 180 degrees, and turns it back when released.';
};
