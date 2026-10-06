# Shir's Raid Builder

Shir's Raid Builder creates, saves, and runs Microbot raid hiring plans for WoW 1.12.1. It also saves live raid layouts, sends companion setup commands, and arranges raid subgroups at a safe pace.

> **Safety:** this addon can send commands that spend gold. Back up `WTF`, use **Preview** before **Execute**, and start with a small plan. Import replaces the current profile after its overwrite warning.

## Download

Download [ShirsRaidBuilder-0.76.zip](https://github.com/theShirina/shirs-raid-builder/releases/download/v0.76/ShirsRaidBuilder-0.76.zip).

## What's new in 0.76

- Unrelated Microbot addon messages no longer repeat full profile initialization, reducing avoidable work during combat

The previous release also added legacy-character refreshes, page-correct import selection, and blank licence tiers for incomplete or unknown source data.

## Before installing

- Built for Microbot WoW 1.12.1 and Interface `11200`
- Uses Microbot companion, legacy hire, deny, setup, and raid roster commands
- Does not include Microbot, CCP, client files, account data, or saved profiles
- Hiring can cost gold; the addon cannot refund a command that the server accepts
- Opening `/srb` is display-only and does not start synchronization. Synchronization runs on login or when you click **Refresh Synchronization**.
- Execute, Capture, and Sort can query Microbot's `nexus` addon channel for live companion owner, class, and role data
- Starting Sort while leading a party can convert that party into a raid before moving members

## Installation

1. Close WoW
2. Delete any old `Interface/AddOns/ShirsRaidBuilder` folder
3. Extract the ZIP into `Interface/AddOns`
4. Start WoW and check that **Shir's Raid Builder** is enabled
5. Type `/srb`

Profiles are stored in the account-wide `ShirsRaidBuilderDB` SavedVariable.

## Hire mode

- Build a 40-slot raid board across eight groups
- Add normal companions by hiring character, tier, class, role, spec, race, and gender
- Limit each hiring character to four normal companions per plan
- Add named legacy characters with their real hire name and derived `-lite` name
- Reuse saved class and role choices for known legacy characters
- Browse all matching legacy names with a five-row scrollbar and class colours
- Keep names already in the current hiring profile out of the Add Legacy suggestions
- Include the current player as a gold board card without treating that card as a hire
- Drag cards to swap raid slots and collapse groups while editing
- Move the main window and each subpanel independently
- Keep separate named profiles, with New, Rename, Delete, Import, and Preview controls
- Import a saved Hire or Sort profile with a paged picker and overwrite confirmation
- Use **Share Current Plan**, beside **Import**, to send the open plan to a linked account; the recipient does not need any panels open
- The recipient must explicitly approve a copy or a merge; a merge keeps occupied destination slots, reserves the incoming plan's original positions where they are free, and moves conflicting incoming cards to the lowest remaining free slots
- If a merge does not fit, the recipient's plan is left unchanged; a shared plan is never executed automatically
- Preview the complete command queue without sending anything
- Stop a running hire or whisper queue

Normal hires wait between 7.5 and 8.5 seconds so the old client and server command path are not flooded.

## Companion setup

- Add class-and-role deny rules with class-filtered ability suggestions
- Open **Individual commands** on a legacy hire to search its class abilities and set commands for that hire alone
- Keep custom deny lists on legacy characters
- Configure shaman totems, paladin auras, hunter aspects, pets, and Growl policy; warlock pets; and mage magic and drink thresholds
- Send normal companion setup after hiring finishes
- Send legacy-specific setup last so it can override broader class rules
- Wait for companion replies before moving through whisper-heavy queues

The account panel sorts hiring characters by raid licence and can show licence tiers and confirmed saved raid lockouts when that information is available.

## Sort mode

Sort mode has its own profiles and never sends hiring commands.

- Capture the current raid into a saved layout
- Confirm before overwriting the current layout
- Hide the overwrite warning per realm and character
- Match companions by live name or by hiring owner, class, and role
- Include companions hired by other players, legacy characters, and the current player
- Move one raid member every 0.5 seconds
- Use swaps when a destination group is full
- Attempt within-group slot ordering through a temporary empty subgroup
- Continue through later groups when one exact-order pass is unavailable
- Send deny and setup whispers without hiring

## Build and test

The repository includes Lua 5.0.3 tests, a public-boundary validator, and a deterministic ZIP builder.

```text
python tests/validate.py --lua <lua-5.0.3> --luac <luac-5.0.3>
python scripts/build_release.py
```

## Acknowledgements

The companion information query flow was informed by [WhisperComps](https://github.com/Desorda/WhisperComps) and is used with permission. Shir's Raid Builder is otherwise an independent clean-room implementation.

The ability suggestions are a project-maintained list of public Vanilla 1.12 spell names compiled from trainer spells and talent-granted action-bar abilities. No upstream addon catalogue is included.

## Licence

Shir's Raid Builder is released under the MIT License.
