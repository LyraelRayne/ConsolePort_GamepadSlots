-- Targeting: adds two bindable commands for Blizzard's native gamepad
-- targeting-cone mode (C_GamepadTargeting) -- confirmed by reading
-- ConsolePort's source that it has no equivalent of its own anywhere.
-- Controller/Targeting.lua only manages tooltips/nameplate highlighting
-- around the older native soft-target system (softenemy/softfriend,
-- PLAYER_SOFT_*_CHANGED); there's no cone-widen/cycle/filter feature at all.
--
-- Same shape as LyraelForever/modules/GamepadActionLayout.lua's
-- CreateTargetingButton, and Blizzard's own GamepadTargetLogicMixin
-- (Blizzard_GamepadTargeting/TargetLogic.lua):
--   press   -> SetFilter + Enable (unprotected, plain Lua via HookScript)
--   release -> /targetenemy or /targetfriend, then Disable(), which selects
--              whatever the cone is hovering. Disable() alone selects nothing
--              when the cone has no hover target -- Blizzard falls back to
--              TargetNearestEnemy/Friend there, which is protected, so the
--              fallback goes through the button's native macro dispatch.
-- The macro runs before the hook (HookScript appends), so a hovered unit
-- from Disable() wins over the cycled one.
local _, _, _, db = CPAPI.LinkEnv(...)

if not C_GamepadTargeting then return end
local Bindings = db.Bindings

local MODES = {
	Hostile = {
		filter = Enum.GamepadTargetingFilters.Hostile;
		macro  = '/targetenemy';
		label  = 'Gamepad Targeting: Hostile';
		desc   = 'Hold to widen the targeting cone and prioritize hostile units toward the camera. Release to target the highlighted unit, or the nearest enemy if none is highlighted.';
	};
	Friendly = {
		filter = Enum.GamepadTargetingFilters.Friendly;
		macro  = '/targetfriend';
		label  = 'Gamepad Targeting: Friendly';
		desc   = 'Hold to widen the targeting cone and prioritize friendly units toward the camera. Release to target the highlighted unit, or the nearest friend if none is highlighted.';
	};
};

for key, mode in pairs(MODES) do
	local widgetName = ('ConsolePortGamepadTarget%s'):format(key)
	local button = CreateFrame('Button', widgetName, UIParent, 'SecureActionButtonTemplate')
	button:SetAttribute(CPAPI.ActionTypePress, 'macro')
	button:SetAttribute('macrotext', mode.macro)
	-- Release-only regardless of the ActionButtonUseKeyDown CVar, since the
	-- press is the hold-to-aim half (SecureTemplates.lua: clickAction).
	button:SetAttribute('useOnKeyDown', false)
	button:RegisterForClicks('AnyDown', 'AnyUp')
	button:HookScript('OnClick', function(_, _, down)
		if down then
			C_GamepadTargeting.SetFilter(mode.filter)
			C_GamepadTargeting.Enable()
		else
			C_GamepadTargeting.Disable()
		end
	end)

	local bindingCommand = ('CLICK %s:LeftButton'):format(widgetName)
	_G[('BINDING_NAME_%s'):format(bindingCommand)] = mode.label

	-- Same registration shape as ConsolePort's own custom (non-native)
	-- bindings in Model/Game/Bindings.lua (Bindings.Custom / .Special) --
	-- this is what makes it a selectable row in ConsolePort's own bind
	-- config UI, not just Blizzard's generic Key Bindings panel.
	Bindings.Custom['GamepadTarget' .. key] = bindingCommand;
	Bindings.Special[#Bindings.Special + 1] = {
		binding = bindingCommand;
		name    = mode.label;
		desc    = mode.desc;
	};
end
