-- GamepadSlots: makes ConsolePort's own bind-config UI list the native
-- gamepad action storage slots (181-360) as bindable "bars", alongside the
-- standard 180 it already lists. ConsolePort's own action system (Pager.lua,
-- Model/Game/Actionbar.lua) never touches this range at all -- confirmed by
-- reading its source, it only computes ordinary slot IDs via
-- ((page-1)*12)+id, tied to the classic 6-bar/bonus-bar model.
--
-- The mechanism is a direct port of ConsolePort's own Controller/
-- ExtraActions.lua, which does the exact same thing for ITS non-native bars
-- 13-15 (Classic only, since modern/retail already has native
-- MULTIACTIONBAR5/6/7BUTTON%d global binding commands for those -- but there
-- is no native global binding command for the gamepad storage range on any
-- version, so this file's approach is needed unconditionally, not just on
-- Classic): one small persistent SecureActionButtonTemplate per bound slot,
-- created lazily on OnNewBindings (not all 180 up front), with a fixed
-- "action" attribute and a CLICK binding on its own name. Each button is
-- also handed to Paging.lua, which re-targets its "action" by stance and
-- vehicle following ConsolePort's pager; with paging off it stays on its own
-- slot.
--
-- Registering with ActionBarAPI.Pages/.Names/.Action/.Widget/.Binding below
-- is what makes ConsolePort_Config's "Action bars" settings page draw these
-- as selectable rows automatically (confirmed from DataProvider.lua: it
-- iterates db:For('Actionbar/Pages'), and ActionbarMapper's own bind/unbind
-- logic resolves generically via db('Actionbar/Action/'..actionID), which
-- works on any slot number through the same (page-1)*12+id arithmetic --
-- nothing UI-side needs to know these aren't the standard 180.
local _, _, env, db = CPAPI.LinkEnv(...)

if not C_GamepadUI then return end
local ActionBarAPI = db.Actionbar

---------------------------------------------------------------
-- Range
---------------------------------------------------------------
local GAMEPAD_BASE = C_GamepadUI.GetFirstGamepadActionStorageSlotIndex()
-- ActionBarAPI:GetFormattedIDs (Model/Game/Actionbar.lua) computes
-- barID = ceil(actionID / 12) for ANY actionID, gamepad range included --
-- that's fixed by ConsolePort's own code, not something this file gets to
-- choose. Bar N's first slot is therefore (N-1)*12 + 1, so GAMEPAD_BASE
-- lines up with a whole bar only if (GAMEPAD_BASE - 1) is a multiple of 12
-- -- NOT GAMEPAD_BASE itself. (181-1)/12 = 15 exactly, confirming 181 is
-- real. Checked here, not assumed, since the asserted-but-wrong version of
-- this check (GAMEPAD_BASE % 12 == 0) is exactly what silently killed this
-- whole file on first load -- 181 % 12 == 1, so it threw before a single
-- line below it ran.
assert((GAMEPAD_BASE - 1) % NUM_ACTIONBAR_BUTTONS == 0,
	'Gamepad storage base does not land on a bar boundary; the page/slot arithmetic below assumes it does.')

local FIRST_PAGE = ((GAMEPAD_BASE - 1) / NUM_ACTIONBAR_BUTTONS) + 1
-- 180 slots (181-360), confirmed against LyraelForever's own documented map
-- of this range (GAMEPAD-LAYOUT.md). Checked per-slot against
-- IsValidGamepadActionStorageSlotIndex below too, in case this client's
-- real upper bound differs.
local NUM_GAMEPAD_BARS = 15
local LAST_PAGE = FIRST_PAGE + NUM_GAMEPAD_BARS - 1

---------------------------------------------------------------
-- Action slot handler (one per bound slot, created lazily)
---------------------------------------------------------------
local WIDGET_FORMAT  = 'ConsolePortGamepadSlotPage%sSlot%s';
local BINDING_FORMAT = ('CLICK %s:LeftButton'):format(WIDGET_FORMAT:format('%s', '%s'));
local BINDING_MATCH  = BINDING_FORMAT:format('(%d+)', '(%d+)');

local function CalculateActionID(pageID, slotID)
	return ((pageID - 1) * NUM_ACTIONBAR_BUTTONS) + slotID;
end

local function CreateActionSlotHandler(pageID, slotID, actionID)
	local widgetName = WIDGET_FORMAT:format(pageID, slotID)
	local button = CreateFrame('Button', widgetName, UIParent, 'SecureActionButtonTemplate')
	button:SetAttribute(CPAPI.ActionTypePress, 'action')
	button:SetAttribute('action', actionID)
	button:RegisterForClicks('AnyDown')
	env.Paging:AddButton(button, actionID)
	_G[('BINDING_NAME_CLICK %s:LeftButton'):format(widgetName)] =
		('Gamepad Slot %d-%d'):format(pageID - FIRST_PAGE + 1, slotID);
	return button;
end

local created = {};
db:RegisterSafeCallback('OnNewBindings', function(self, bindings)
	for _, set in pairs(bindings) do
		for _, binding in pairs(set) do
			local pageID, slotID = binding:match(BINDING_MATCH)
			if pageID and slotID then
				pageID, slotID = tonumber(pageID), tonumber(slotID);
				local actionID = CalculateActionID(pageID, slotID);
				if not created[actionID] then
					if C_GamepadUI.IsValidGamepadActionStorageSlotIndex(actionID) then
						created[actionID] = CreateActionSlotHandler(pageID, slotID, actionID);
					else
						-- Pre-formatted, not passed as format args to CPAPI.Log --
						-- it routes through db.Locale(...), which treats its first
						-- argument as a translation key lookup, not a printf format.
						CPAPI.Log(('GamepadSlots: action %d (page %d slot %d) is bound but not a valid gamepad storage slot on this client -- skipped.'):format(
							actionID, pageID, slotID))
					end
				end
			end
		end
	end
end, {})

---------------------------------------------------------------
-- Register the range with ConsolePort's own action bar API
---------------------------------------------------------------
local gamepadPages = {};
for pageID = FIRST_PAGE, LAST_PAGE do
	gamepadPages[#gamepadPages + 1] = pageID;
	local pageFormat = BINDING_FORMAT:format(pageID, '%d');
	ActionBarAPI.Action[tostring(pageID)] = pageFormat;
	ActionBarAPI.Widget[tostring(pageID)] = WIDGET_FORMAT:format(pageID, '%d');
	for slotID = 1, NUM_ACTIONBAR_BUTTONS do
		ActionBarAPI.Binding[pageFormat:format(slotID)] = CalculateActionID(pageID, slotID);
	end
end

-- A new page group, same shape as ActionBarAPI.Pages' existing entries
-- (Model/Game/Actionbar.lua) -- always shown (CPAPI.Static(true)), since
-- this range exists whenever C_GamepadUI does (already checked above).
local gamepadGroup = CPAPI.Callable(gamepadPages, CPAPI.Static(true));
ActionBarAPI.Pages[#ActionBarAPI.Pages + 1] = gamepadGroup;
ActionBarAPI.Names[gamepadGroup] = 'Gamepad';
