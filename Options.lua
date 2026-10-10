-- Options: a "Gamepad Slots" tab in ConsolePort's own config window, built
-- the same way ConsolePort_Bar builds its tab (View/Config/Panel.lua): a
-- panel mixing ConsolePort_Config's SettingsPanel and SettingsRenderer, fed
-- by a provider, registered with configEnv:CreatePanel.
--
-- ConsolePort's setting rows normally read and write ConsolePort's own
-- database. Values here live in the AceDB profile instead, so rows use
-- ProfileSetting: a subclass of Elements.Setting that swaps the storage,
-- the same way ConsolePort's Cvar element does for CVars. Each row gets a
-- get/set pair; a write goes through set, which validates it, stores it and
-- fires Registry so the row redraws (with the stored value, so a rejected
-- edit snaps back).
--
-- Rows are rebuilt from the profile on every reindex (Refresh), so adding,
-- deleting and resetting rules, and switching profiles, always redraw from
-- current data.
local _, _, env, db = CPAPI.LinkEnv(...)

if not C_GamepadUI then return end

local PANEL_NAME = 'Gamepad Slots'
local MAX_COUNT  = 24
local Data       = db.Data

local Registry = CreateFromMixins(CallbackRegistryMixin)
Registry:OnLoad()
Registry:SetUndefinedEventsAllowed(true)

local panel; -- the config panel, once ConsolePort_Config has loaded

local function Refresh()
	if panel and panel.index then
		panel:OnIndexChanged()
	end
end

local function Confirm(text, onAccept)
	CPAPI.Popup('ConsolePort_GamepadSlots_Confirm', {
		text     = text;
		button1  = YES;
		button2  = NO;
		timeout  = 0;
		OnAccept = onAccept;
		hideOnEscape = true;
	})
end

---------------------------------------------------------------
-- Rule validation
---------------------------------------------------------------
local function FormatRange(first, count)
	if count == 1 then return tostring(first) end
	return ('%d-%d'):format(first, first + count - 1)
end

-- Returns an error message, or nil if the rule is valid. skipIndex is the
-- rule being edited, so it isn't reported as overlapping itself.
local function CheckRule(rules, skipIndex, kind, from, count, to)
	if count < 1 or count > MAX_COUNT then
		return ('Count must be 1-%d.'):format(MAX_COUNT)
	end
	if from < env.FIRST_SLOT or from + count - 1 > env.LAST_SLOT then
		return ('Gamepad slots must be within %d-%d.'):format(env.FIRST_SLOT, env.LAST_SLOT)
	end
	if kind == 'vehicle' then
		if to < 1 or to + count - 1 > env.NUM_POSITIONS then
			return ('Main-bar positions must be within 1-%d.'):format(env.NUM_POSITIONS)
		end
	elseif to < 1 or to + count - 1 > env.LAST_SLOT then
		return ('Target slots must be within 1-%d.'):format(env.LAST_SLOT)
	end
	for i, rule in ipairs(rules) do
		if i ~= skipIndex and from <= rule.from + rule.count - 1 and rule.from <= from + count - 1 then
			return ('Overlaps the rule for gamepad slots %s.'):format(FormatRange(rule.from, rule.count))
		end
	end
end

-- First single slot no rule covers, for a new rule to start on.
local function FindFreeSlot(rules)
	for slot = env.FIRST_SLOT, env.LAST_SLOT do
		if not CheckRule(rules, nil, 'stance', slot, 1, slot) then
			return slot
		end
	end
end

local function SortRules(rules)
	table.sort(rules, function(a, b) return a.from < b.from end)
end

---------------------------------------------------------------
-- Panel
---------------------------------------------------------------
local GROUP = { GENERAL = PANEL_NAME, STANCES = 'Stances', VEHICLES = 'Vehicles' };
local GROUP_ORDER = { [GROUP.GENERAL] = 1, [GROUP.STANCES] = 2, [GROUP.VEHICLES] = 3 };

local Panel = { name = PANEL_NAME };

function Panel:OnLoad()
	CPAPI.Start(self)
	self:Reindex()
	self:SetActiveCategory(GENERAL, self.index[GROUP.GENERAL][GENERAL])
end

function Panel:OnDefaults()
	Confirm('Reset the current profile to the default rules?', function()
		env.Addon.db:ResetProfile()
		Refresh()
	end)
end

function Panel.GroupSort(_, a, b)
	return (GROUP_ORDER[a] or 99) < (GROUP_ORDER[b] or 99)
end

-- ConsolePort caches each stance's name by its page once you've been in it
-- (Model/Game/Actionbar.lua, Lookup.Stances); stance offset k is page 6 + k.
local function StanceName(offset)
	local info = db.Actionbar.Lookup.Stances[NUM_ACTIONBAR_PAGES + offset]
	if info and info.name then
		return ('%d: %s'):format(offset, info.name)
	end
	return ('Stance %d'):format(offset)
end

local function BuildPanel(configEnv)
	local Elements = configEnv.Elements;

	-----------------------------------------------------------
	-- ProfileSetting element
	-----------------------------------------------------------
	local ProfileSetting = CreateFromMixins(Elements.Setting);

	function ProfileSetting:Init(elementData)
		local data = elementData:GetData()
		self.getValue = data.get;
		xpcall(self.Mount, geterrorhandler(), self, {
			name       = data.field.name;
			varID      = data.varID;
			field      = data.field;
			owner      = ConsolePortConfig;
			registry   = Registry;
			newObj     = true;
			callbackID = data.varID;
			callbackFn = data.set;
		})
	end

	function ProfileSetting:Get()
		if self.getValue then
			return self.getValue()
		end
	end

	function ProfileSetting:OnAcquire(new)
		if new then
			Elements.InitializeSetting(self, configEnv.Setting, ProfileSetting)
		end
	end

	-- Own pool key, so these frames are never shared with ConsolePort's
	-- regular setting rows (the tree pools setting frames by this type).
	function ProfileSetting:Data(dp)
		return {
			varID = dp.varID;
			field = dp.field;
			type  = 'GamepadSlots' .. dp.field[1]:GetType();
			get   = dp.get;
			set   = dp.set;
		};
	end

	-----------------------------------------------------------
	-- Row builders
	-----------------------------------------------------------
	-- get() returns the stored value; apply(value) stores it and returns
	-- nil, or returns an error message and stores nothing.
	local function Row(varID, dataObj, name, desc, list, sort, get, apply)
		return {
			type  = ProfileSetting;
			varID = varID;
			sort  = sort;
			field = { dataObj, name = name, desc = desc, list = list };
			get   = get;
			set   = function(value)
				local err = apply(value)
				if err then
					CPAPI.Log(err)
				else
					env.Paging:Push()
				end
				Registry:TriggerEvent(varID, get())
			end;
		};
	end

	local function ActionButton(name, list, sort, atlas, callback, placement)
		local field = { name = name, list = list };
		if placement then field[placement] = true end
		return {
			type     = Elements.Button;
			sort     = sort;
			field    = field;
			text     = name;
			atlas    = atlas;
			callback = callback;
		};
	end

	local TARGET = {
		stance  = { name = 'First target slot', desc = 'The slot the first gamepad slot fires. The rest follow in order.' };
		vehicle = { name = 'First main-bar position', desc = 'The main-bar position (1-12) the first gamepad slot fires. The rest follow in order.' };
	};

	local function AddRuleEditor(AddSetting, main, head, key, kind, getRules, setDefaults)
		local rules = getRules()
		local sort = 0;
		local function Next() sort = sort + 1; return sort end

		for index, rule in ipairs(rules) do
			local list = ('Rule %d'):format(index)
			local prefix = ('gamepadslots/%s/%d/'):format(key, index)

			local function Apply(field)
				return function(value)
					value = tonumber(value)
					if not value then return 'Enter a whole number.' end
					local candidate = { from = rule.from, count = rule.count, to = rule.to };
					candidate[field] = value;
					local err = CheckRule(rules, index, kind, candidate.from, candidate.count, candidate.to)
					if err then return err end
					rule[field] = value;
				end
			end

			AddSetting(main, head, Row(prefix .. 'from', Data.Number(rule.from, 1),
				'First gamepad slot', 'The first gamepad slot this rule changes.',
				list, Next(), function() return rule.from end, Apply('from')))
			AddSetting(main, head, Row(prefix .. 'count', Data.Range(rule.count, 1, 1, MAX_COUNT),
				'Count', 'How many gamepad slots in a row this rule changes.',
				list, Next(), function() return rule.count end, Apply('count')))
			local targetData = kind == 'vehicle'
				and Data.Range(rule.to, 1, 1, env.NUM_POSITIONS)
				or  Data.Number(rule.to, 1);
			AddSetting(main, head, Row(prefix .. 'to', targetData,
				TARGET[kind].name, TARGET[kind].desc,
				list, Next(), function() return rule.to end, Apply('to')))
			AddSetting(main, head, ActionButton('Delete rule', list, Next(), 'common-icon-redx', function()
				table.remove(rules, index)
				env.Paging:Push()
				Refresh()
			end))
		end

		AddSetting(main, head, ActionButton('Add rule', nil, Next(), 'common-icon-plus', function()
			local slot = FindFreeSlot(rules)
			if not slot then
				return CPAPI.Log('Every gamepad slot already has a rule here.')
			end
			rules[#rules + 1] = { from = slot, count = 1, to = kind == 'vehicle' and 1 or slot };
			SortRules(rules)
			env.Paging:Push()
			Refresh()
		end, 'after'))
		return AddSetting(main, head, ActionButton('Reset to default', nil, Next(), 'common-icon-undo', function()
			Confirm(('Replace the rules in %s with the defaults?'):format(head), function()
				setDefaults()
				env.Paging:Push()
				Refresh()
			end)
		end, 'after'))
	end

	-----------------------------------------------------------
	-- Profiles
	-----------------------------------------------------------
	local function AddProfileSettings(AddSetting, main, head)
		local aceDB = env.Addon.db;
		local current = aceDB:GetCurrentProfile()
		local profiles = aceDB:GetProfiles()
		table.sort(profiles)
		local sort = 0;
		local function Next() sort = sort + 1; return sort end

		local function SwitchTo(name)
			aceDB:SetProfile(name)
			Refresh()
		end

		AddSetting(main, head, Row('gamepadslots/profile', Data.Select(current, unpack(profiles)),
			'Active profile', 'The profile this character uses. Profiles hold the toggle and every rule.',
			'Profile', Next(), function() return aceDB:GetCurrentProfile() end,
			function(value) SwitchTo(value) end))

		local exists = {};
		for _, name in ipairs(profiles) do exists[name] = true end
		local quick = {
			{ key = aceDB.keys.char,  label = 'New profile for this character' };
			{ key = aceDB.keys.class, label = 'New profile for this class' };
		};
		for _, entry in ipairs(quick) do
			if not exists[entry.key] then
				AddSetting(main, head, ActionButton(('%s (%s)'):format(entry.label, entry.key), 'Profile', Next(),
					'common-icon-plus', function() SwitchTo(entry.key) end))
			end
		end

		local store = AddSetting(main, head, ActionButton('Reset this profile', 'Profile', Next(), 'common-icon-undo', function()
			Confirm(('Reset profile "%s" to the default rules?'):format(current), function()
				aceDB:ResetProfile()
				Refresh()
			end)
		end))

		for _, name in ipairs(profiles) do
			if name ~= current then
				AddSetting(main, head, ActionButton(('Copy from "%s"'):format(name), 'Copy from', Next(),
					'common-icon-checkmark', function()
						Confirm(('Replace profile "%s" with a copy of "%s"?'):format(current, name), function()
							aceDB:CopyProfile(name)
							Refresh()
						end)
					end))
			end
		end
		for _, name in ipairs(profiles) do
			if name ~= current then
				AddSetting(main, head, ActionButton(('Delete "%s"'):format(name), 'Delete', Next(),
					'common-icon-redx', function()
						Confirm(('Delete profile "%s"?'):format(name), function()
							aceDB:DeleteProfile(name)
							Refresh()
						end)
					end))
			end
		end
		return store;
	end

	-----------------------------------------------------------
	-- Camera
	-----------------------------------------------------------
	local function ModifierLabel(name, cvar)
		local button = GetCVar(cvar)
		if button and button ~= '' and button ~= 'none' then
			return ('%s (%s)'):format(name, GetBindingText(button))
		end
		return name
	end

	local function AddCameraSettings(AddSetting, main, head)
		local camera = env.GetProfile().camera;
		local list = 'Turn With Camera';
		local function Setter(field)
			return function(value)
				camera[field] = value
				env.Camera:Refresh()
			end
		end
		local released = CopyTable(env.TURN_WITH_CAMERA_VALUES)
		released[env.CAMERA_FOLLOW_CONSOLEPORT] = 'ConsolePort\'s setting'

		local store = AddSetting(main, head, Row('gamepadslots/camera/enabled', Data.Bool(camera.enabled),
			'Switch while held',
			'Holding the modifier (or the "Hold: Turn With Camera" binding) switches Turn With Camera to the held value; releasing it switches to the released value. While ConsolePort is overriding it for a cast or a vehicle, ConsolePort\'s value wins. Off: ConsolePort\'s own setting applies.',
			list, 1, function() return camera.enabled end,
			function(value) Setter('enabled')(not not value) end))
		AddSetting(main, head, Row('gamepadslots/camera/modifier', Data.Map(camera.modifier, {
				shift = ModifierLabel('Shift', 'GamePadEmulateShift');
				ctrl  = ModifierLabel('Ctrl', 'GamePadEmulateCtrl');
				alt   = ModifierLabel('Alt', 'GamePadEmulateAlt');
				none  = 'None (binding only)';
			}),
			'Modifier', 'The modifier to hold. Each one shows the button ConsolePort maps it to.',
			list, 2, function() return camera.modifier end, Setter('modifier')))
		AddSetting(main, head, Row('gamepadslots/camera/held', Data.Map(camera.held, env.TURN_WITH_CAMERA_VALUES),
			'While held', 'When your character turns with the camera while the modifier is held.',
			list, 3, function() return camera.held end, Setter('held')))
		AddSetting(main, head, Row('gamepadslots/camera/released', Data.Map(camera.released, released),
			'While released', 'When your character turns with the camera while the modifier is released. "ConsolePort\'s setting" uses ConsolePort\'s own Turn Character With Camera setting.',
			list, 4, function() return camera.released end, Setter('released')))
		AddSetting(main, head, Row('gamepadslots/camera/ignorecast', Data.Bool(camera.ignoreCastOverride),
			'Ignore ConsolePort\'s cast turning',
			'ConsolePort normally turns your character with the camera for the whole of every cast. On: it doesn\'t, so the held/released values (or ConsolePort\'s own setting, if switching is off) decide while casting too. Vehicles still turn with the camera.',
			list, 5, function() return camera.ignoreCastOverride end,
			function(value) Setter('ignoreCastOverride')(not not value) end))
		return store;
	end

	-----------------------------------------------------------
	-- Soft targeting
	-----------------------------------------------------------
	-- Plain CVar rows using ConsolePort's own Cvar element, the same one its
	-- Interact section uses for SoftTargetInteractRange/Arc. Values live in
	-- the CVars (character-scoped), not the profile. ConsolePort only exposes
	-- range and arc for interact; these cover the enemy and friend soft
	-- targets. Range defaults to 45. The game limits it to tab-targeting
	-- range (warcraft.wiki.gg CVar list), whose value isn't documented.
	local ARC_VALUES = { [0] = 'Front', [1] = 'Cone', [2] = 'Around' };
	local SOFT_TARGETS = {
		{ key = 'Enemy',  label = 'Enemy'  };
		{ key = 'Friend', label = 'Friend' };
	};

	local function AddSoftTargetSettings(AddSetting, main, head)
		local store;
		local sort = 0;
		local function AddCvar(cvar, dataObj, name, desc, list)
			local value = GetCVar(cvar)
			if value == nil then return end -- not in this client
			sort = sort + 1;
			local row = AddSetting(main, head, {
				type  = Elements.Cvar;
				varID = cvar;
				sort  = sort;
				field = { dataObj:Set(value), cvar = cvar, name = name, desc = desc, list = list };
			})
			store = store or row;
		end

		for _, target in ipairs(SOFT_TARGETS) do
			local list = ('%s Soft Target'):format(target.label)
			AddCvar(('SoftTarget%sRange'):format(target.key), Data.Range(45, 1, 1, 90),
				'Target Range', ('Distance in yards within which a soft %s target can be found.'):format(target.label:lower()),
				list)
			AddCvar(('SoftTarget%sArc'):format(target.key), Data.Map(1, ARC_VALUES),
				'Arc Allowance', ('Area around you where a soft %s target can be found: only in front, a cone in front, or all around.'):format(target.label:lower()),
				list)
		end
		return store;
	end

	-----------------------------------------------------------
	-- Provider
	-----------------------------------------------------------
	local Settings = CreateFromMixins(configEnv.SettingsPanel, configEnv.SettingsRenderer, Panel);
	Settings:Init()

	Settings:AddProvider(function(AddSetting)
		local profile = env.GetProfile()

		local general = AddSetting(GROUP.GENERAL, GENERAL, Row('gamepadslots/enabled', Data.Bool(profile.enabled),
			'Stance and vehicle paging',
			'Pages the gamepad slots by stance, vehicle and possess, following ConsolePort\'s own action page settings. If ConsolePort is set not to page, these slots don\'t page either.',
			nil, 1, function() return env.GetProfile().enabled end,
			function(value) env.GetProfile().enabled = not not value end))
		general.sort = 1;

		AddCameraSettings(AddSetting, GROUP.GENERAL, 'Camera').sort = 2;
		local softTarget = AddSoftTargetSettings(AddSetting, GROUP.GENERAL, 'Soft Targeting')
		if softTarget then softTarget.sort = 3 end
		AddProfileSettings(AddSetting, GROUP.GENERAL, 'Profiles').sort = 4;

		for offset = 1, env.NUM_STANCES do
			AddRuleEditor(AddSetting, GROUP.STANCES, StanceName(offset), 'stance' .. offset, 'stance',
				function() return profile.stances[offset] end,
				function() profile.stances[offset] = env.GetDefaultStanceRules(offset) end).sort = offset;
		end

		AddRuleEditor(AddSetting, GROUP.VEHICLES, GROUP.VEHICLES, 'vehicle', 'vehicle',
			function() return profile.vehicle end,
			function() profile.vehicle = env.GetDefaultVehicleRules() end)
	end)

	-- CreatePanel mixes Settings into a new frame; that frame is the live panel.
	panel = configEnv:CreatePanel(Settings)
end

function env.SetupOptions()
	ConsolePort:RegisterConfigCallback(function(_, configEnv)
		BuildPanel(configEnv)
	end)
end
