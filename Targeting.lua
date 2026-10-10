-- Targeting: adds two bindable commands for Blizzard's native gamepad
-- targeting-cone mode (C_GamepadTargeting), plus a clear-target binding.
-- ConsolePort has no binding for this mode. The closest it offers are
-- Blizzard's TARGETSCANENEMY / TARGETNEARESTENEMY, which use the separate
-- target-priority highlight (TargetPriorityHighlightStart/End), have no
-- friendly equivalent, and aren't what Forever's own gamepad UI uses
-- (Blizzard_GamepadTargeting/TargetLogic.lua, BeginTargeting/EndTargeting).
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

-- ConsolePort's Special bindings take a file path or a function for `texture`
-- (Libs/Local/ActionButton.lua, SkinUtility.SetTexture), not an atlas. The
-- function draws the atlas and returns an unmount that restores the icon's
-- texture coordinates, which SetAtlas changes and a later SetTexture doesn't
-- reset.
local function AtlasTexture(atlas)
	return function(icon)
		local coords = { icon:GetTexCoord() }
		icon:SetAtlas(atlas, false)
		return function()
			icon:SetTexCoord(unpack(coords))
		end
	end
end

local MODES = {
	Hostile = {
		filter = Enum.GamepadTargetingFilters.Hostile;
		icon   = 'gamepad-targeting-hostile';
		macro  = '/targetenemy';
		label  = 'Gamepad Targeting: Hostile';
		desc   = 'Hold to widen the targeting cone and prioritize hostile units toward the camera. Release to target the highlighted unit, or the nearest enemy if none is highlighted.';
	};
	Friendly = {
		filter = Enum.GamepadTargetingFilters.Friendly;
		icon   = 'gamepad-targeting-friendly';
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
		texture = AtlasTexture(mode.icon);
	};
end

---------------------------------------------------------------
-- Clear target
---------------------------------------------------------------
-- No clear-target binding exists in ConsolePort or Blizzard's binding list.
-- Bound to a modifier combo (e.g. LT+RB) in ConsolePort, it matches
-- LyraelForever's modifier-cancel on the targeting buttons.
local CLEAR_BUTTON = 'ConsolePortGamepadClearTarget'
local clearButton = CreateFrame('Button', CLEAR_BUTTON, UIParent, 'SecureActionButtonTemplate')
clearButton:SetAttribute(CPAPI.ActionTypePress, 'macro')
clearButton:SetAttribute('macrotext', '/cleartarget')
clearButton:RegisterForClicks('AnyDown', 'AnyUp')

local clearCommand = ('CLICK %s:LeftButton'):format(CLEAR_BUTTON)
local clearName = 'Clear Target'
_G[('BINDING_NAME_%s'):format(clearCommand)] = clearName

Bindings.Custom.GamepadClearTarget = clearCommand;
Bindings.Special[#Bindings.Special + 1] = {
	binding = clearCommand;
	name    = clearName;
	desc    = 'Clears your current target.';
	texture = [[Interface\Buttons\UI-GroupLoot-Pass-Up]];
};
