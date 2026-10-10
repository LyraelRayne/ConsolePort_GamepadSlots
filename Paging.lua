-- Paging: re-targets gamepad slot bindings by stance and vehicle, following
-- ConsolePort's own pager instead of a driver of our own.
--
-- This frame is registered as a header with db.Pager:RegisterHeader
-- (ConsolePort/Controller/Pager.lua), the same way ConsolePort_Bar's bars are.
-- Whenever ConsolePort's page driver changes page, it writes the new page to
-- our 'actionpage' attribute and runs our 'ActionPageChanged' snippet. So if
-- ConsolePort is configured not to page (Settings/actionPageCondition), these
-- slots don't page either. The page decides what each gamepad slot fires:
--   vehicle/override/temp-shapeshift page, or possess -> vehicle rules: the
--       slot fires main-bar position N of that page, i.e. the same slot
--       ACTIONBUTTON<N> fires there.
--   page 7+ (stance, offset = page - 6) -> that offset's stance rules.
--   anything else, or no matching rule -> the slot fires itself.
-- The result is published as 'map-<slot>' attributes on this frame (unset =
-- the slot fires itself), and applied to two kinds of button:
--
-- 1. Our own slot buttons (GamepadSlots.lua), which the CLICK bindings press
--    when ConsolePort_Bar isn't loaded.
-- 2. ConsolePort_Bar's buttons. When it's loaded, it overrides every key whose
--    binding resolves to an action slot (db.Actionbar.Binding, where
--    GamepadSlots.lua registers these) to press its own button instead, with
--    a fixed 'action' -- and it only pages slots 1-12. So its UpdateState
--    snippet is wrapped (PatchBarButton): after the original runs, a gamepad
--    slot's 'action' is replaced with this frame's 'map-<slot>', and
--    ButtonContentsChanged is called the way ConsolePort_Bar does for its own
--    bar 1 paging, so the icon and cooldown follow. LibActionButton reads the
--    'UpdateState' attribute fresh on every run (RunAttribute/RunFor), so the
--    wrapper takes effect without touching ConsolePort_Bar's files.
--
-- The rules live in the secure environment as STANCES[offset][slot] = action,
-- VEHICLE[slot] = position and SOURCES = every slot that has any rule, rebuilt
-- by Push() out of combat. Anything that can't be done in combat (Push,
-- patching) is retried on PLAYER_REGEN_ENABLED.
local _, _, env, db = CPAPI.LinkEnv(...)
local LAB = LibStub('LibActionButton-1.0', true)

if not C_GamepadUI then return end

local Paging = CreateFrame('Frame', 'ConsolePortGamepadSlotsPaging', UIParent, 'SecureHandlerBaseTemplate')
env.Paging = Paging

local APPLY = ([[
	local page = self:GetAttribute('actionpage') or 1;
	local vehicle, map = false, nil;
	if ENABLED then
		if ( HasVehicleActionBar() and page == GetVehicleBarIndex() )
		or ( HasOverrideActionBar() and page == GetOverrideBarIndex() )
		or ( HasTempShapeshiftActionBar() and page == GetTempShapeshiftBarIndex() )
		or ( page > %d and SecureCmdOptionParse('[possessbar] 1; 0') == '1' ) then
			vehicle = true;
		elseif page > %d then
			map = STANCES[page - %d];
		end
	end
	for i = 1, #SOURCES do
		local slot, action = SOURCES[i], nil;
		if vehicle then
			local position = VEHICLE[slot];
			if position then
				action = (page - 1) * %d + position;
			end
		elseif map then
			action = map[slot];
		end
		self:SetAttribute('map-' .. slot, action);
	end
	for i = 1, #BUTTONS do
		local button = BUTTONS[i];
		local slot = button:GetAttribute('gamepadslot');
		local action = self:GetAttribute('map-' .. slot) or slot;
		if button:GetAttribute('action') ~= action then
			button:SetAttribute('action', action);
		end
	end
	for i = 1, #BARBUTTONS do
		local button = BARBUTTONS[i];
		self:RunFor(button, button:GetAttribute('UpdateState'), button:GetAttribute('state'));
	end
]]):format(NUM_ACTIONBAR_PAGES, NUM_ACTIONBAR_PAGES, NUM_ACTIONBAR_PAGES, NUM_ACTIONBAR_BUTTONS)

Paging:Execute([[
	BUTTONS    = newtable();
	BARBUTTONS = newtable();
	STANCES    = newtable();
	VEHICLE    = newtable();
	SOURCES    = newtable();
	ENABLED    = false;
]])
Paging:SetAttribute('ActionPageChanged', APPLY)
db.Pager:RegisterHeader(Paging)

---------------------------------------------------------------
-- Combat deferral
---------------------------------------------------------------
local pendingPush, pendingScan;

local combatWatcher = CreateFrame('Frame')
combatWatcher:SetScript('OnEvent', function(self)
	self:UnregisterEvent('PLAYER_REGEN_ENABLED')
	if pendingScan then Paging:ScanBarButtons() end
	if pendingPush then Paging:Push() end
end)

local function DeferUntilCombatEnds()
	combatWatcher:RegisterEvent('PLAYER_REGEN_ENABLED')
end

---------------------------------------------------------------
-- Our slot buttons
---------------------------------------------------------------
-- Called from OnNewBindings, which ConsolePort only runs out of combat.
function Paging:AddButton(button, slot)
	button:SetAttribute('gamepadslot', slot)
	self:SetFrameRef('button', button)
	self:Execute([[ BUTTONS[#BUTTONS + 1] = self:GetFrameRef('button'); ]] .. APPLY)
end

---------------------------------------------------------------
-- ConsolePort_Bar buttons
---------------------------------------------------------------
-- ConsolePort_Bar's UpdateState (Widget/Button/Button.lua) is the only one
-- that declares mainBarActionID; plain LibActionButton buttons from other
-- addons don't, so they're left alone.
local BAR_SIGNATURE  = 'mainBarActionID'
local PATCH_MARKER   = '-- ConsolePort_GamepadSlots'
local ORIGINAL_ATTR  = 'gamepadslots-UpdateState'

local PATCHED_UPDATE_STATE = ([[
	%s
	self:RunAttribute('%s', ...)
	local state = self:GetAttribute('state')
	if not state or self:GetAttribute('type') ~= 'action' then return end
	local slot = self:GetAttribute(format('labaction-%%s', state))
	if type(slot) ~= 'number' or slot < %d or slot > %d then return end
	local paging = self:GetFrameRef('gamepadslots')
	local action = paging and paging:GetAttribute('map-' .. slot) or slot
	self:SetAttribute('action', action)
	self:CallMethod('ButtonContentsChanged', state, 'action', action)
]]):format(PATCH_MARKER, ORIGINAL_ATTR, env.FIRST_SLOT, env.LAST_SLOT)

local registered = {};
local warned = false;

local function IsBarButton(body)
	return type(body) == 'string' and body:find(BAR_SIGNATURE, 1, true) ~= nil
end

-- Returns true if the button is (now) patched. ConsolePort_Bar can reinstall
-- its own UpdateState when it rebuilds a button, which drops the marker, so
-- an already registered button is simply patched again.
local function PatchBarButton(button)
	local body = button:GetAttribute('UpdateState')
	if type(body) == 'string' and body:find(PATCH_MARKER, 1, true) then
		return true
	end
	if not IsBarButton(body) then return false end
	if not button.ButtonContentsChanged then
		if not warned then
			warned = true
			CPAPI.Log('GamepadSlots: ConsolePort_Bar buttons have changed shape; stance paging on ConsolePort_Bar is disabled.')
		end
		return false
	end
	button:SetAttribute(ORIGINAL_ATTR, body)
	button:SetAttribute('UpdateState', PATCHED_UPDATE_STATE)
	SecureHandlerSetFrameRef(button, 'gamepadslots', Paging)
	return true
end

function Paging:ScanBarButtons()
	pendingScan = nil
	if not LAB then return end
	if InCombatLockdown() then
		pendingScan = true
		return DeferUntilCombatEnds()
	end
	local added = false;
	for button in pairs(LAB.buttonRegistry) do
		if PatchBarButton(button) and not registered[button] then
			registered[button] = true
			added = true
			self:SetFrameRef('button', button)
			self:Execute([[ BARBUTTONS[#BARBUTTONS + 1] = self:GetFrameRef('button'); ]])
		end
	end
	-- Rerun every bar button's UpdateState, so new and re-patched buttons
	-- pick up the current page right away.
	self:Execute(APPLY)
	return added
end

-- ConsolePort_Bar creates and rebuilds its buttons at load, on layout
-- changes and on new bindings, and installs UpdateState after
-- LibActionButton's OnButtonCreated fires -- so scan on the next frame.
local scanQueued = false;
local function QueueScan()
	if scanQueued then return end
	scanQueued = true
	RunNextFrame(function()
		scanQueued = false
		Paging:ScanBarButtons()
	end)
end

if LAB then
	LAB.RegisterCallback(Paging, 'OnButtonCreated', QueueScan)
end
db:RegisterSafeCallback('OnNewBindings', QueueScan, Paging)
EventUtil.ContinueOnAddOnLoaded('ConsolePort_Bar', QueueScan)

---------------------------------------------------------------
-- Rules
---------------------------------------------------------------
local function AppendMap(lines, target, rules, sources)
	for _, rule in ipairs(rules or {}) do
		for i = 0, rule.count - 1 do
			local slot = rule.from + i;
			lines[#lines + 1] = ('%s[%d] = %d;'):format(target, slot, rule.to + i)
			sources[slot] = true;
		end
	end
end

function Paging:Push()
	pendingPush = nil
	local profile = env.GetProfile()
	if not profile then return end
	if InCombatLockdown() then
		pendingPush = true
		return DeferUntilCombatEnds()
	end

	local sources = {};
	local lines = {
		('ENABLED = %s;'):format(profile.enabled and 'true' or 'false');
		'STANCES = newtable();';
		'VEHICLE = newtable();';
	};
	for offset = 1, env.NUM_STANCES do
		lines[#lines + 1] = 'do local map = newtable();'
		AppendMap(lines, 'map', profile.stances[offset], sources)
		lines[#lines + 1] = ('STANCES[%d] = map; end'):format(offset)
	end
	AppendMap(lines, 'VEHICLE', profile.vehicle, sources)

	-- SOURCES is replaced, not cleared: map attributes for slots that just
	-- lost their last rule are cleared here first, since APPLY only visits
	-- the new SOURCES.
	lines[#lines + 1] = [[
		for i = 1, #SOURCES do
			self:SetAttribute('map-' .. SOURCES[i], nil);
		end
		SOURCES = newtable();
	]]
	for slot in pairs(sources) do
		lines[#lines + 1] = ('SOURCES[#SOURCES + 1] = %d;'):format(slot)
	end

	self:Execute(table.concat(lines, '\n') .. '\n' .. APPLY)
end
