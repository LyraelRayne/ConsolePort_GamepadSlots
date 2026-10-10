-- Interact: a ConsolePort binding that clicks Blizzard's own gamepad interact
-- button, with a live icon wherever ConsolePort shows the binding.
--
-- The button is Blizzard_GamepadActionBars' top-bar interact button (found
-- with LyraelForever's /lyrael hoverid). Clicking it runs Blizzard's whole
-- interact logic: loot, talk, gather, attack, skipping an out-of-range soft
-- target, and hold to toggle auto-loot (it's registered for AnyDown/AnyUp).
--
-- The icon uses ConsolePort's dynamic-icon support: a Special binding's
-- `texture` may be a function, which ConsolePort calls with the icon texture
-- when a button starts showing the binding, and whose return value it calls
-- when the button stops (Libs/Local/ActionButton.lua, SkinUtility.SetTexture;
-- ConsolePort's own unit-menu bindings use this for live portraits). Every
-- icon showing this binding copies Blizzard's interact icon, which Blizzard
-- redraws in GamepadMainActionBarFrame:UpdateInteractIcons() a frame after
-- target, soft-interact, soft-enemy and equipment changes.
local _, _, _, db = CPAPI.LinkEnv(...)

local BUTTON       = 'GamepadMainActionBarFramePageUnitTopCenteredAnchorTopBarActionButton5'
local BINDING      = ('CLICK %s:LeftButton'):format(BUTTON)
local NAME         = 'Interact (Blizzard button)'
local DEFAULT_ICON = [[Interface\Cursor\Interact]]

local mounted = {}; -- icon textures currently showing this binding

local function GetBlizzardIcon()
	local button = _G[BUTTON]
	return button and button.SpecialActionIcon
end

-- ConsolePort replaces SetTexture on its icons to handle function textures;
-- the original method draws a plain texture.
local function CopyIcon(icon)
	local source = GetBlizzardIcon()
	local texture = source and source:GetTexture() or DEFAULT_ICON
	CPAPI.Index(icon).SetTexture(icon, texture)
end

local function UpdateAll()
	for icon in pairs(mounted) do
		CopyIcon(icon)
	end
end

local function MountIcon(icon)
	mounted[icon] = true
	CopyIcon(icon)
	return function()
		mounted[icon] = nil
	end
end

EventUtil.ContinueOnAddOnLoaded('Blizzard_GamepadActionBars', function()
	if GamepadMainActionBarFrame and GamepadMainActionBarFrame.UpdateInteractIcons then
		hooksecurefunc(GamepadMainActionBarFrame, 'UpdateInteractIcons', UpdateAll)
	end
	UpdateAll()
end)

_G[('BINDING_NAME_%s'):format(BINDING)] = NAME

db.Bindings.Custom.GamepadBlizzardInteract = BINDING;
db.Bindings.Special[#db.Bindings.Special + 1] = {
	binding = BINDING;
	name    = NAME;
	desc    = 'Clicks Blizzard\'s own gamepad interact button: loot, talk, gather or attack, whichever Blizzard\'s interact would choose. Hold to toggle auto-loot. The icon shows what it will do.';
	texture = MountIcon;
};
