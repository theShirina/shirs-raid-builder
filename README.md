# Shir's Raid Builder

Shir's Raid Builder creates, saves, and runs Microbot raid hiring plans for WoW 1.12.1. It also saves live raid layouts, sends companion setup commands, and arranges raid subgroups at a safe pace.

> **Safety:** this addon can send commands that spend gold. Back up `WTF`, use **Preview** before **Execute**, and start with a small plan. Import replaces the current profile after its overwrite warning.

## Download

Download [ShirsRaidBuilder-1.0.zip](https://github.com/theShirina/shirs-raid-builder/releases/download/v1.0/ShirsRaidBuilder-1.0.zip) from the [v1.0 release page](https://github.com/theShirina/shirs-raid-builder/releases/tag/v1.0).

## What's new in 1.0

### Added

- Link accounts on the same realm, remember account-wide or character-only approvals, and synchronize characters, licences, factions, and saved raid snapshots. The sidebar shows linked characters and snapshot age; licence details have a separate read-only view. Saved links can be renewed, unlinked or forgotten.
- Share the current plan with linked accounts. Each recipient can approve a separate copy, merge, or reject it; sharing never runs a plan or sends deny and setup rules. An expired link is renewed and a pending approval is awaited automatically.
- Use one **Execute** on the initiating account to hire normal and legacy characters across approved linked accounts, in board order. Linked accounts hire on their own, later hand-offs are shorter, and **Hire status** shows progress and stop controls.
- Plan with remembered linked characters, their hire counts, tiers and faction/class/race choices. **Hire from** moves a card to another eligible character, and cards show their tier.
- Send several deny spells to one companion in a single whisper.

### Changed

- Normal hire pacing follows a companion joining, then waits one second. If no join is seen, the existing 7.5–8.5 second wait remains. Legacy companions are also given time to join before setup or deny commands are sent.
- Saved raid snapshots now come from Microbot Control Panel. Enable it on each character whose saved raids you want to see. The Naxxramas label now reads **NAXX**.
- The main window now puts account linking, synchronization, hire status, plan sharing, and import controls in the top bar. Execute uses the initiating plan's rules for linked hires; commands are sent after hiring. Escape closes the link prompt, link panel and licence view.
- Re-runs distinguish companions by their hire-from character, and hire counts include all 40 board slots.

### Fixed

- A single remaining hire on a re-run could be sent twice and spend gold twice; it now runs once.
- Group setup or deny commands could be sent before a newly hired companion appeared in the group; the addon now waits for it.
- A held legacy setup command could be whispered twice when Sort mode started; it is sent once.
- Legacy deny commands could arrive before the legacy companion joined, and a missing companion could go unreported; the addon now waits and reports the outcome.
- Opening `/srb` could send an invite-list request; it now only opens the window. Synchronization runs at login or when requested.

## Before installing

- Built for Microbot WoW 1.12.1 and Interface `11200`
- Uses Microbot companion, legacy hire, deny, setup, and raid roster commands
- All accounts in a linked run must use v1.0. Accepting a link lets that account hire and spend gold for its plan when the initiating account clicks **Execute**; accept links only for accounts you trust
- Linked hires need an approved link and recent synchronization. Old sidebar snapshots are display-only and do not authorize a run
- The first link requires the builder to be open on the receiving account. Synchronization runs on login or when you click **Refresh Synchronization**. Opening `/srb` is display-only and does not start synchronization.
- Accounts that log in close together can now synchronize without waiting for a long timeout.
- Saved raid snapshots come from Microbot Control Panel; enable it on each character whose saves you want to see
- Does not include Microbot, CCP, client files, account data, or saved profiles
- Hiring can cost gold; the addon cannot refund a command that the server accepts
- Execute, Capture, and Sort can query Microbot's `nexus` addon channel for live companion owner, class, and role data
- Starting Sort while leading a party can convert that party into a raid before moving members
- Other linked accounts' players also use raid slots but are not counted as board cards; ten players leave room for 30 companions
- Run profile names allow letters, numbers, spaces, `_`, apostrophes, and hyphens, up to 48 characters
- The server may report a companion's owner as the character that sent the hire. Re-runs match by the hire-from character, so check the board before running a plan again
- Stop requested on a receiving account is not reported to the leader immediately; use **Cancel process** on the leader if a linked run stalls
- Linked-run handoff messages appear in both accounts' chat frames; the first handoff can take several seconds

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
- Use **Link Account**, **Refresh Synchronization**, **Share Current Plan**, and **Hire status** to work with linked accounts. The recipient must approve a copied or merged plan; sharing never executes it
- Use `/srbhandoff` to open Hire status. The initiating account's plan rules apply across linked hires
- Deny and setup rules are not copied by Share Current Plan; set the rules on the initiating plan before Execute

After a normal hire, the addon waits until its companion joins, then waits one second. If no join is seen, it uses the 7.5–8.5 second fallback. Legacy companions also get time to join before setup or deny commands are sent.

## Companion setup

- Add class-and-role deny rules with class-filtered ability suggestions
- Open **Individual commands** on a legacy hire to search its class abilities and set commands for that hire alone
- Keep custom deny lists on legacy characters
- Configure shaman totems, paladin auras, hunter aspects, pets, and Growl policy; warlock pets; and mage magic and drink thresholds
- Send normal companion setup after hiring finishes
- Send legacy-specific setup last so it can override broader class rules
- Wait for companion replies before moving through whisper-heavy queues

The account panel sorts hiring characters by raid licence and can show licence tiers and saved raid snapshots when available. The v1.0 snapshot source is Microbot Control Panel; enable it on each character.

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
