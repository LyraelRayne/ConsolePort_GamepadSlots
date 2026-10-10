# Console Port: Gamepad Slots

A third-party module for the WoW Forever build of [ConsolePort](https://github.com/seblindfors/ConsolePort). It isn't an official ConsolePort module.

It lets ConsolePort use the separate gamepad action slots that Blizzard added for its gamepad UI. Your keyboard bars and your gamepad bars then hold different actions, and changing one doesn't touch the other. It also adds a few gamepad features ConsolePort doesn't have.

- **Requires:** ConsolePort. ConsolePort_Bar (Action Bar) and ConsolePort_Config are supported but optional.
- **Client:** WoW Forever, `## Interface: 16001`.
- **Saved variables:** `ConsolePortGamepadSlotsDB` (AceDB, with profiles).

## Features

### Gamepad slot bindings

Blizzard's gamepad UI stores its actions in slots 181–360, separate from the 180 keyboard slots. This module adds those slots to ConsolePort's **Action Bars** binding page as 15 "Gamepad" bars of 12 slots each. Bind them like any other action bar.

You can put the same slot on more than one button combination. Turn on ConsolePort's **Gameplay → Bindings → Allow Binding Overlap** first; otherwise ConsolePort removes an action's previous binding when you give it a new one.

### Stance, vehicle and possess paging

Gamepad slots can switch to other slots when your stance or form changes, and to vehicle or possess actions. Paging follows ConsolePort's own pager, so it reacts to the same conditions as ConsolePort's bars. If ConsolePort is set not to page, these slots don't page either.

- **Stances 1–12:** each stance has a list of rules of the form "gamepad slots A–B fire slots C–D".
- **Vehicles:** in a vehicle, on an override bar or while possessing, rules map gamepad slots to main-bar positions 1–12. That's the same action `ACTIONBUTTON1`–`12` would fire there. Most vehicles only use positions 1–6.
- A slot with no matching rule keeps its own action. Rules in one list can't overlap.

This works both with ConsolePort_Bar's buttons, whose icons and cooldowns follow the paging, and with the module's own hidden slot buttons when ConsolePort_Bar isn't loaded.

Default rules, from the LyraelForever gamepad layout, for stance offsets k = 1–5:

| Gamepad slots | Fire |
|---|---|
| Right bar 193–200 (form bar) | 257 + 8k |
| Bottom X/Y/B/A 205–208 | 209 + 4(k−1) |
| Top Y/B 329–330 | 349 + 2(k−1) |

Default vehicle rules: top Y/B → positions 1–2, right X/Y/B/A → 3–6, bottom X/Y/B/A → 7–10, top D-pad left/up → 11–12. The left bar has no vehicle rule, so it keeps its own actions.

### Gamepad targeting

Two bindings under ConsolePort's custom bindings:

- **Gamepad Targeting: Hostile**
- **Gamepad Targeting: Friendly**

Hold one to widen Blizzard's gamepad targeting cone toward hostile or friendly units. Release it to target the highlighted unit, or the nearest enemy or friend if nothing is highlighted.

### Interact (Blizzard button)

A binding under ConsolePort's custom bindings, **Interact (Blizzard button)**, that clicks Blizzard's own gamepad interact button. It does whatever Blizzard's interact would: loot, talk, gather, or attack. It skips an out-of-range soft target, and holding it toggles auto-loot.

On ConsolePort_Bar, the button it's bound to shows the same icon as Blizzard's interact button (loot, talk, gather, attack, or the greyed "unable" versions), updated whenever Blizzard redraws it. ConsolePort's config window shows the binding without the live icon.

### Turn With Camera switching

Switches the game's Turn With Camera setting (`GamePadTurnWithCamera`) between two values: one while a modifier is held, another when it's released. The ConsolePort version of LyraelForever's LT camera switch.

- **Modifier:** Shift, Ctrl or Alt, each shown with the button ConsolePort maps it to. "None" means binding only.
- **Hold binding:** **Hold: Turn With Camera**, for holding a button that isn't a modifier. A modifier can't carry a binding, so to use LT, choose its modifier above.
- **Values:** while moving / while moving or in combat / while moving, in combat or casting / always. "While released" also offers **ConsolePort's setting**.
- **Ignore ConsolePort's cast turning** (on by default): ConsolePort normally forces "always" for the whole of every cast. With this on it doesn't, so the held/released values decide while casting too. Vehicles still turn with the camera.

If LyraelForever is enabled on the same character, turn off one of the two camera switches. LyraelForever has its own toggle: **Turn with camera while LT is held**.

## Settings

Open ConsolePort's config window and choose the **Gamepad Slots** tab. Everything there is controller-friendly.

- **Gamepad Slots → General:** the paging toggle.
- **Gamepad Slots → Camera:** the Turn With Camera options above.
- **Gamepad Slots → Profiles:**
  - choose the active profile
  - create a profile for this character or class
  - reset the profile
  - copy from or delete other profiles.
- **Stances → 1–12:** each stance's rules. ConsolePort shows a stance's name once you've been in that form. Each rule has First gamepad slot, Count and First target slot, plus Delete rule. At the bottom are Add rule and Reset to default.
- **Vehicles:** the same editor, with main-bar positions as targets.

ConsolePort's config window closes in combat, so settings can only be changed out of combat. If a change does arrive during combat some other way (for example, another addon switching the profile), it's applied when combat ends. ConsolePort's **Defaults** button resets the current profile.

## Action bar presets (`presets/`)

The addon doesn't load these files. Import them in ConsolePort_Bar's designer: Loadout → Import, then paste.

- `LR-quad-with-paddles.txt`: the main layout. Four crossbars, one per modifier: none, Ctrl, Alt and Ctrl+Alt. Each has the D-pad, face buttons, paddles P1–P4 (laid out like the Steam Deck) and the sticks. The active bar is fully opaque and the others are at 60%, with dividers that brighten with the active bar.
- `GamepadSlotsCrossbars.txt` and `gen_preset.lua`: an older generated layout in LyraelForever's arrangement, and the script that builds it. To regenerate it, run `luajit presets/gen_preset.lua <path to ConsolePort_Config/Model/Legacy.lua> presets/GamepadSlotsCrossbars.txt`. The script checks its output with ConsolePort's own import decoder.

Paddles only respond once ConsolePort recognises them as gamepad buttons. If your controller or Steam Input sends keyboard keys for the paddles, map them under ConsolePort's device settings: **Emulate P1–P4**.

## How it works

| File | Role |
|---|---|
| `Core.lua` | AceAddon and AceDB setup with profiles. Default rules are copied into each new profile once rather than being AceDB defaults, so a deleted default rule stays deleted. |
| `Paging.lua` | A secure header registered with ConsolePort's pager. On each page change it works out each gamepad slot's target and publishes it as `map-<slot>` attributes. It applies these to its own slot buttons and to ConsolePort_Bar's buttons. |
| `GamepadSlots.lua` | Registers the gamepad slot bars with ConsolePort's action bar API, and creates a small secure button for each bound slot. |
| `Targeting.lua` | The two targeting buttons and their bindings. |
| `Interact.lua` | The Blizzard interact click binding, and the live icon that copies Blizzard's interact icon. |
| `Camera.lua` | The modifier state driver, the hold binding, and the hooks that coordinate with ConsolePort's own Turn With Camera handling. |
| `Options.lua` | The ConsolePort config tab. It's built like ConsolePort_Bar's own tab, with a setting row type that reads and writes the AceDB profile. |

### ConsolePort internals this relies on

None of these are documented API, so a ConsolePort update can break them. Check here first if something stops working.

- **Paging:** `db.Pager:RegisterHeader`, and the header's `ActionPageChanged` attribute and `actionpage` attribute.
- **Action bar registration:** `db.Actionbar.Pages`, `Names`, `Action`, `Widget` and `Binding`. This is the same approach as ConsolePort's `Controller/ExtraActions.lua`.
- **ConsolePort_Bar paging:** the module wraps each ConsolePort_Bar button's `UpdateState` snippet. It finds ConsolePort_Bar's buttons in LibActionButton's `buttonRegistry` by the `mainBarActionID` text in that snippet. It relies on the `labaction-<state>` attributes and LibActionButton's `ButtonContentsChanged`.
  - **Safety check:** if a button has that snippet but no `ButtonContentsChanged` method, the module leaves the button alone. It prints this once in chat: *"GamepadSlots: ConsolePort_Bar buttons have changed shape; stance paging on ConsolePort_Bar is disabled."*
  - **When the check fires:** ConsolePort_Bar keeps working, and its gamepad slot buttons fire their own fixed slots, as if paging were off. Paging on the module's own slot buttons isn't affected.
  - **When the check doesn't fire:** if ConsolePort renames the snippet's text so the `mainBarActionID` match fails, nothing is patched and there's no message. ConsolePort_Bar buttons then simply stop paging.
  - This can't be tested until a ConsolePort update triggers it.
- **Custom bindings:** `db.Bindings.Custom` and `db.Bindings.Special`.
- **Interact icon:** a Special binding's `texture` given as a function (ConsolePort's `SkinUtility.SetTexture` calls it and its returned cleanup); Blizzard's `GamepadMainActionBarFrame:UpdateInteractIcons()` and the interact button's name (`GamepadMainActionBarFramePageUnitTopCenteredAnchorTopBarActionButton5`), which is Blizzard's, not ConsolePort's.
- **Camera:** `db.Movement` and its `UpdateTurnWithCamera`, `GetTurnWithCameraValue` and `fmSpellOverride`/`fmVehicleOverride` fields, plus its `UNIT_SPELLCAST_*_START` handlers (replaced by name).
- **Config tab:** `ConsolePort:RegisterConfigCallback`, `configEnv:CreatePanel`, `SettingsPanel`, `SettingsRenderer`, `Elements.Setting`/`Button`/`InitializeSetting` and `env.Setting`. These are the same pieces ConsolePort_Bar uses for its own tab.

Secure-code rules for changes are in `SECURE-EXECUTION-RULES.md` at the workspace root.
