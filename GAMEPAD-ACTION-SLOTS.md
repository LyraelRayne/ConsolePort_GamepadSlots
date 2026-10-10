# Gamepad action storage slots (WoW Forever client)

Notes from building gamepad-slot support on top of ConsolePort for the WoW Forever client (interface 16001, UI source from build 1.60.1.70291). Sources are the client's Blizzard UI code (`Blizzard_GamepadActionBars`, `Blizzard_ActionBar`, `Blizzard_APIDocumentationGenerated/GamepadUIDocumentation.lua`) and in-game testing. Things not confirmed in game are marked.

> **Possession is untested.** Everything here about possession or mind control (the possess bar showing, and what fills slots 11–18 while possessing) comes from reading Blizzard's code. It hasn't been tested in game, because no character available for testing had those abilities yet.

## Summary

- Blizzard's gamepad UI keeps its actions in a storage range separate from the 180 keyboard action slots, starting at `C_GamepadUI.GetFirstGamepadActionStorageSlotIndex()` (**181**). In game, `IsValidGamepadActionStorageSlotIndex` returns true fo **181–360** (180 slots) and nothing else. These slots work with `PickupAction`, `PlaceAction`, `GetActionInfo` and secure `type="action"` buttons, the same as keyboard slots.
- **The engine doesn't page these slots.** Stance swapping (and, per the code, possess swapping) happens in the gamepad UI's Lua, which points buttons at different storage slots. An addon using this range has to do its own paging.
- The stance storage base comes from `C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance()`. That function **doesn't seem to be available to secure snippets**, so paging that has to work in combat must work it out from `GetBonusBarOffset()` (formula below).

## API

`C_GamepadUI` has the following functions:

| Function | Returns / notes |
|---|---|
| `C_GamepadUI.GetFirstGamepadActionStorageSlotIndex()` | First gamepad storage slot. **181** on this client. |
| `C_GamepadUI.IsValidGamepadActionStorageSlotIndex(slot)` | Whether `slot` is valid gamepad storage. |
| `C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance()` | First slot of the active stance's 8-slot bar, or nil when no bonus bar is active. |
| `C_GamepadUI.GetFirstGamepadPetActionStorageSlotIndex()` | First **pet action** slot used by the gamepad possess bar. On Forever, that bar doesn't show for normal pets (see below). This is a pet action index, used with `PickupPetAction`, `GetPetActionInfo` and `type="pet"` buttons, not an action slot. In game it returns **11**, and `IsValidGamepadPossessBarStorageSlotIndex` accepts exactly **11–18** (8 slots), straight after the keyboard pet bar's 1–10. |
| `C_GamepadUI.IsValidGamepadPossessBarStorageSlotIndex(index)` | Whether `index` is a valid possess bar pet slot. |

Other useful functions:
| Function | Returns / notes |
| `C_ActionBar.GetBonusBarOffset()` / `GetBonusBarIndex()` | Stance offset k / keyboard bonus page (6 + k). **Both are allowed in secure snippets.** |
| `C_ActionBar.HasBonusActionBar()`, `HasVehicleActionBar()`, `HasOverrideActionBar()`, `HasTempShapeshiftActionBar()`, and `Get*BarIndex()` | Keyboard override state. Also allowed in secure snippets. |
| `C_ActionBar.GetBonusBarIndexForSlot(slot)` | Returns nil for gamepad slots (tested in game), so it can't be used as a reverse lookup. **No API maps an arbitrary stance to its gamepad slots**; only the active stance's base is available. |
| `C_ActionBar.FindSpellActionButtons`, `FindPetActionButtons`, `FindFlyoutActionButtons`, `GetPetActionPetBarIndices` | Take an `Enum.ActionBarSet` (`Mkb`, `Gamepad`, `All`) to search keyboard slots, gamepad slots, or both by contents. |
| Events `GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED`, `GAMEPAD_POSSESS_BAR_OVERRIDE_CHANGED` | The player changed which bar position the stance or possess bar replaces (`Enum.GamepadStanceBarOverride` / `Enum.GamepadPossessBarOverride`). |

Constants (`Constants.GamepadActionBarConstants`):

| Constant | Value |
|---|---|
| `NUM_SLOTS_PER_GAMEPAD_ACTION_BAR_GROUP` | 4 |
| `NUM_GROUPS_PER_GAMEPAD_ACTION_BAR` | 2 |
| `NUM_SLOTS_PER_GAMEPAD_ACTION_BAR` | 8 |
| `NUM_PAGEABLE_BARS_IN_GAMEPAD_ACTION_BAR_PAGE_UNIT` | 4 |
| `NUM_PAGEABLE_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT_STANDARD_PAGE` | 32 |
| `NUM_RESERVED_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT` | 4 |
| `NUM_PAGES_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT` | 4 |
| `NUM_STANDARD_PAGES_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT` | 3 |
| `GAMEPAD_ACTION_BAR_PAGE_UNIT_SPECIAL_PAGE_INDEX` | 4 |
| `NUM_PAGEABLE_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT` | 96 |
| `NUM_GAMEPAD_STANCE_ACTION_BARS` | 5 |

## Standard pages (181–264)

The gamepad UI has 4 bars (top, left, right, bottom) of 8 buttons. Each bar is two groups of 4: D-pad, then face buttons, each in the order left, up, right, down (face buttons: X, Y, B, A). There are 3 standard pages, plus a 4th "special" page for the possess bar (per the code; possession untested).

Positions on a page (`ActionBindingUtil.lua`):

```
                 TopBar
              02        06
           01    03  05    07
              04        08
     LeftBar                       RightBar
   10        14              18        22
09    11  13    15        17    19  21    23
   12        16              20        24
                BottomBar
              26        30
           25    27  29    31
              28        32
```

Positions 5–8 (the top bar's face buttons) are **reserved for UI actions** such as interact and jump, and get no storage. Each standard page therefore uses 28 storage slots.

`GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID(page, id)`, for page 1–3 and a non-reserved id:

```
slot = first + 32*(page-1) + (id-1) - 4*(page-1) - (id >= 5 and 4 or 0)
     = 181 + 28*(page-1) + (id-1) - (id >= 5 and 4 or 0)
```

| Page | Top (D-pad only) | Left | Right | Bottom |
|---|---|---|---|---|
| 1 | 181–184 | 185–192 | 193–200 | 201–208 |
| 2 | 209–212 | 213–220 | 221–228 | 229–236 |
| 3 | 237–240 | 241–248 | 249–256 | 257–264 |

## Stance bars (265–304)

- When a bonus bar is active (`HasBonusActionBar()`), the gamepad stance bar replaces one bar position with that stance's 8 slots. The player chooses which position (`Enum.GamepadStanceBarOverride`).
- Five stance bars of 8 slots each (`NUM_GAMEPAD_STANCE_ACTION_BARS = 5`). The first slot for stance offset k is:

```
GetFirstGamepadActionBarStorageSlotIndexForActiveStance() == 257 + 8 * GetBonusBarOffset()
```

The formula matches in game for offset 1 (Cat Form and Battle Stance → 265), offset 2 (Defensive Stance → 273) and offset 3 (Bear Form → 281).

| Slots | Offset | Seen in game |
|---|---|---|
| 265–272 | 1 | Druid Cat Form, Warrior Battle Stance (confirmed) |
| 273–280 | 2 | Warrior Defensive Stance (confirmed) |
| 281–288 | 3 | Druid Bear Form (confirmed) |
| 289–296 | 4 | unconfirmed |
| 297–304 | 5 | unconfirmed |

- **The offset belongs to the form, not its stance-bar position.** Druid Bear Form is stance-bar button 1 but offset 3; Cat Form is button 3 but offset 1. (For warriors the two happen to match.)
- **Gamepad stance slots are independent of the keyboard bonus pages.** In game, each form's gamepad bar held different actions from its keyboard page (for example, Cat Form's keyboard page 7 vs. gamepad 265–272). Nothing copies one to the other. Action storage belongs to each character, so a druid's Cat Form and a warrior's Battle Stance both using 265–272 don't conflict.
- Not every stance-bar ability has a bonus bar. On this client, Druid Prowl stays on Cat Form's offset 1, Paladin auras don't page, and Rogue Stealth reports no bonus bar and no shapeshift form (`HasBonusActionBar()` false, offset 0, `GetShapeshiftForm()` 0). These never use the gamepad stance slots.
- If a bonus bar is active with no gamepad stance bar, Blizzard's code asserts: *"A MKB bonus action bar is active which doesn't have a gamepad equivalent. Extend the gamepad action bar storage (ActionBarConstants.tag) to add additional slots for this bar."*
- Unverified: whether bonus offsets above 5 have gamepad storage. The keyboard totem bar is on page 12; if that's offset 6, the formula would put it at 305.

## Possess bar

> Possession itself is **untested** (see the note at the top). In game, only the slot range, editing the slots, and the bar *not* showing with a normal pet were checked.

- The code treats this as a general gamepad pet bar, but **on Forever it doesn't show for normal pets.** In game, with a hunter's pet out, the gamepad UI shows no pet bar, only the two class-action flyouts (below). Per the code, its slots, 11–18, would then be used only when possessing or mind controlling. This is inferred, not tested.
  - Its visibility is meant to follow the keyboard pet bar (`PetActionBar.lua` triggers `"PetActionBar.GamepadVisibilityHandler"`), and it listens to the pet events (`UNIT_PET`, `PET_BAR_UPDATE`, ...).
  - Binding to it needs an active pet (`GAMEPAD_BIND_FAILURE_NO_ACTIVE_PET`), and is blocked while the pet is charmed (`GAMEPAD_POSSESS_BAR_MODIFICATION_NOT_POSSIBLE`).
- It uses **pet action** storage from `GetFirstGamepadPetActionStorageSlotIndex()`, with 8 `type="pet"` buttons.
- **The game fills it.** For a hunter's pet that was never set up on the gamepad, pet actions 11–18 held:

  | Keyboard pet bar | 1 Attack | 2 Follow | 3 Move To | 4 Cower | 5 (empty) | 6 (empty) | 7 (empty) | 8 Assist | 9 Defensive | 10 Passive |
  |---|---|---|---|---|---|---|---|---|---|---|
  | Gamepad pet bar | 11 Attack | 12 Follow | 13 Move To | 14 Cower | 15 (empty) | | | 16 Assist | 17 Defensive | 18 Passive |

  That looks like keyboard pet slots 1–5 followed by the three stance buttons (8–10), with 6–7 dropped. A pet with more abilities would confirm whether 15 maps to 5. After that, the two bars are independent: confirmed in game, rearranging the keyboard pet bar leaves 11–18 unchanged.
- **It's editable.** In game, `PickupPetAction` on 11–18 picks up and places pet actions, and the slots can be emptied entirely. Only pet actions can be placed there, matching Blizzard's own check (`GAMEPAD_BIND_FAILURE_NON_PET_ACTION`).
- **Only the possess bar reads 11–18** (per the code). The two Forever-only (`Camelot`) hunter/warlock flyouts on the class-action buttons read the **keyboard** pet bar (1–10) instead, so editing 11–18 doesn't affect them. Confirmed in game: rearranging the keyboard pet bar changes what the flyouts show.
  - Left class action, pet command flyout (`Camelot/PetActionFlyout.lua`): built-in commands only (Attack, Follow, Move To, Passive, Defensive, ...). Its button only shows if one of those is on the keyboard pet bar.
  - Right class action, pet spell flyout (`Camelot/PetSpellFlyout.lua`): entries with a spell ID only. With exactly one pet spell, it doesn't open; pressing it casts that spell (`SingleSpellMixin` → `CastPetAction`). It only opens with two or more.
- It replaces the special page's top bar, or a bar position on pages 1–3 that the player chooses (`Enum.GamepadPossessBarOverride`). From the code; untested.
- Pet abilities can also go in ordinary gamepad **action** slots: `ActionButtonUtil.GetActionBarStatusForPetActionFromGamepadBars` looks for them there with `FindPetActionButtons(id, Enum.ActionBarSet.Gamepad)`. From the code; untested.
- The vehicle and override bars have no separate gamepad storage in the source. An addon can send gamepad buttons to the keyboard vehicle/override page instead, slot `(page - 1) * 12 + position` where `page` is `GetVehicleBarIndex()` or `GetOverrideBarIndex()`, which is the slot `ACTIONBUTTON<position>` fires (361–372 for the vehicle bar, see below). Untested: no vehicles were found on the beta.

## 305–360

These are valid gamepad storage (the range ends at 360), but no Blizzard code we found assigns them. My addon has used parts of the range (305–310 and 329–358) as extra gamepad slots, with no conflicts seen so far. Treat "unused by Blizzard" as observed rather than guaranteed.

## Slots above 360

On this client, the action slots continue past gamepad storage:

| Range | Used for | Source |
|---|---|---|
| 361–372 | Vehicle bar, page 31 | `GetVehicleBarIndex()` = 31 |
| 373–384 | Temporary shapeshift bar, page 32 | `GetTempShapeshiftBarIndex()` = 32 |
| 385–396 | Override bar, page 33 | `GetOverrideBarIndex()` = 33 |
| 397 | Extra Action Button | `ExtraActionButton1.action` (not the 217 or 169 ConsolePort falls back to if the button doesn't exist) |

So the full sequence is keyboard 1–180, gamepad 181–360, vehicle, temporary shapeshift and override pages, then the Extra Action Button. Nothing overlaps.

## Paging these slots from an addon (what we found)

1. **Engine paging covers only keyboard slots.** The keyboard main bar pages through `actionpage`, with bonus page = 6 + offset. Nothing pages gamepad storage, so addon buttons bound to gamepad slots fire a fixed slot unless the addon changes their `action` attribute.
2. **Combat:** use a secure state driver or snippet. Stance → slot has to be computed from `GetBonusBarOffset()` in the snippet (`257 + 8 * offset + i`), because `C_GamepadUI` isn't in the restricted environment.
3. **ConsolePort specifics:**
   - ConsolePort's pager only remaps action IDs 1–12 (`(page-1)*12 + id`). ConsolePort_Bar buttons holding slots above 12 never page.
   - ConsolePort_Bar takes over any key whose binding resolves to an action slot through `db.Actionbar.Binding`, and fires it from its own button with a fixed action.
   - What works (tested in game) uses both:
     - A header registered with `db.Pager:RegisterHeader` gets ConsolePort's page changes in `ActionPageChanged`, so the paging follows ConsolePort's own page settings. It remaps the addon's own slot buttons, which is enough on its own when ConsolePort_Bar isn't loaded.
     - ConsolePort_Bar's buttons also need their `UpdateState` snippet wrapped, so a gamepad slot's `action` is replaced after ConsolePort_Bar sets it, and `ButtonContentsChanged` keeps the icon in step. They also need rerunning on each page change, because ConsolePort_Bar only re-evaluates its slot 1–12 buttons then.
4. Registering gamepad slots as ConsolePort action bars works with the same `ActionBarAPI.Action`/`Widget`/`Binding` and `Pages` tables that ConsolePort's `Controller/ExtraActions.lua` uses for bars 13–15. The first gamepad page is page 16, since `(181 - 1) / 12 + 1 = 16`.
