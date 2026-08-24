# Changelog

## 0.62

### Fixed

- Hire pacing no longer breaks at high frame rates: nod timeouts, whisper gaps, and the invite-list request now measure real time instead of frames
- Group denies and setups no longer fire while the server is still processing the last hire; the 7.5–8.5 second wait after each hire now applies to whatever command comes next, not only to another hire

### Added

- Ability suggestions in the deny-rules editor hide spells that a matching rule already denies for the selected role and class (or an all-roles rule of that class)
- Adding an ability that the selected role + class combination already denies is rejected with a message naming the rule that holds it, so duplicate rules can no longer be created

## 0.61

### Added

- Two separate workspaces: Hire mode for building and running plans, and Sort mode for saved raid layouts
- A compact 40-slot board with eight groups, drag-to-swap cards, collapsible groups, role totals, and a gold card for the current player
- Account-wide named profiles with New, Rename, Delete, Save, and Preview controls
- Normal companion hires by hiring character, tier, class, role, spec, race, and gender
- Validation that rejects malformed names and command fields before a hire command can be sent
- A four-companion limit for each hiring character in one plan
- Named legacy hires with real-name commands and automatic `-lite` display names
- Saved-character discovery from available account data, with level, licence, faction, and class-aware choices
- Class-and-role deny rules with ability suggestions and case-insensitive duplicate removal
- Legacy-specific deny lists and setup commands
- Shaman totem, paladin aura, hunter aspect and pet, warlock pet, and mage magic setup
- A paced execution queue with 7.5–8.5 second hire waits, reply-aware whispers, Preview, Execute, and Stop
- Companion setup after hiring, with legacy-specific overrides sent last
- Live companion discovery for final deny and setup targets
- Sort-mode raid capture, including other players' companions and legacy characters
- A profile overwrite warning with a per-character “do not show again” choice
- Raid matching by live name or by hiring owner, class, and role
- Paced subgroup moves and swaps at one operation every 0.5 seconds
- Best-effort within-group slot ordering through an empty temporary subgroup
- Safe continuation when one group cannot be ordered, including full-raid no-buffer handling
- Sort-mode Whispers for setup and deny commands without hiring
- Symmetrical mode controls, tooltips, Escape handling, and submenu click blocking

### Known limits

- Exact order inside Blizzard raid subgroups depends on the client and may remain partial
- Full 40-member sorting has not had broad live testing
- Full hiring plans with many whisper commands have not had broad live testing
- Very large profile collections have not had broad live testing
- Hiring commands can spend gold; Preview and a SavedVariables backup are strongly recommended
