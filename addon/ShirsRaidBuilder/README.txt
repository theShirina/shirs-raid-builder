Shir's Raid Builder 1.3

Built for Microbot WoW 1.12.1.
Download: https://github.com/theShirina/shirs-raid-builder/releases/download/v1.3/ShirsRaidBuilder-1.3.zip

INSTALL
1. Close WoW.
2. Delete any old Interface/AddOns/ShirsRaidBuilder folder.
3. Copy this ShirsRaidBuilder folder into Interface/AddOns.
4. Start WoW and type /srb.

WARNING
Hiring commands can spend gold. Back up your WTF folder and use Preview before
Execute. Import replaces the current profile after its overwrite warning.
Opening /srb is display-only and does not start synchronization.
Synchronization runs on login or when you click Refresh Synchronization.
All accounts in a linked run must use v1.3. Accept links only for accounts you trust.
Other human-player entries can be removed from a plan without changing the live group.
The current-character slot stays protected.
Logging in as another character no longer adds another automatic player row to saved plans. Older player rows have no marker to show whether they were automatic or deliberate; remove any unwanted old rows once. The update keeps them rather than guessing.
Build Proposal also refreshes selected trusted accounts when needed, then
checks hire prices without closing the builder. Keep both accounts online
with the same updated code; a matching version label alone is not enough.

The proposal shows Estimated total in gold, silver and copper for all new
normal hires, plus costs per character. It uses fresh prices, the chosen
race's reputation and the observed four-hire progression. Later costs are
estimates, rounded to the nearest copper, not a price lock. Unknown costs
stay marked unknown. Only Execute hires or spends gold.

Refresh Synchronization checks the visible Hire profile's prices after sync.
Its bottom Estimated total is separate from Composition and Proposed groups.
Repeated clicks share the pending check. Profile, row, source or count changes
cancel it; late replies cannot replace a changed plan. Unknown costs stay
unknown, with a subtotal for priced rows. Stop cancels the check. Quotes expire;
refresh again for current prices. Both endpoints need compatible quote code.
A settled local or linked refusal stays unknown without dropping other sources.
Independent accounts can check prices together; each client still reads one
server quote at a time. Refresh does not interrupt a live price reply. Needed
trusted links renew only between requests. The check has a time limit and at
most one fresh pass after a delay. If replies cannot stay fresh, it shows a
partial result rather than stale prices; it sends no background price checks.

Ultra gold saving is off by default. While selected, it overrides Save gold
without changing that saved choice. It can replace a fourth highest-licence
hire with a cheaper next-lower chosen licence on another selected eligible
character. Each character keeps its chosen licence. Ultra can reassign other normal
hires across selected characters to keep role priority while avoiding a fourth.
Auto uses its six role groups and each source's eligibility; Custom keeps the
numbered class/role order. It compares discounted
estimates in final hire order, each character's current count and the chosen
race; a lower licence is not always cheaper. Without a cheaper adjacent-tier
alternative that fits the exact composition and remaining capacity, the fourth
hire stays. Custom tier priority comes before cost: an earlier role keeps its
stronger licence when no cheaper lower-priority move fits. Missing or stale
prices prevent an Ultra proposal. Turning Ultra
off restores the existing Save gold choice.

Composition shows draft companions and selected legacies apart from saved
counts, carried legacies and human occupancy. Inputs still start with saved
normal counts. Opening or editing the draft does not overwrite the saved plan.
Sources, Composition, Proposed groups and Tier priority keep a selected
highlight distinct from hover. Sources lists fourteen characters down before
starting the next column, with your current account first. Larger rosters
continue below and scroll.

Auto race choices use preferred class/role defaults. Manual choices and
captured races stay; only additional rows use missing defaults. Warrior Tank
has its own race selector. Choices must fit the class and source faction;
these are preferences, not damage rankings.

Execute, Capture and Sort can query the Microbot addon channel, and Sort can
convert a party to a raid when you are the party leader.

All accounts in a linked run must use v1.3. Accepting a link lets that account
hire and spend gold for its plan when the initiating account clicks Execute.
Accept links only for accounts you trust. Linked hires also need a recent sync
and the addon loaded on each account. The first link needs the builder open on
the receiving account. Opening /srb does not sync; sync runs at login or when
you click Refresh Synchronization.

Share Current Plan lets each linked recipient approve a copy or merge, or
reject it. A merge that does not fit leaves the plan unchanged. Sharing never
executes a plan. The main header shows linked-run progress. Hover Stop for
its current actor, group and any pause or recovery reason; /srbhandoff shows
the same read-only status. The initiating plan's rules apply to linked hires.
Later hand-offs are shorter than the first, so linked runs send fewer messages.

Saved raid snapshots come from Microbot Control Panel; enable it on each
character. Other accounts' players use raid slots but are not board cards.
Leave room for them: ten players leave 30 slots for companions. Each hiring
character can have at most four normal hires per plan.

The server may report a companion's owner as the character that sent the
hire. Re-runs match by the hire-from character, so review the board before
running it again. Stop on the main builder ends local hires, whispers,
sorting and unsent handoffs, including paused or waiting work. Repeated Stop
clicks are safe. Already delivered groups need Stop on those accounts too;
the leader cannot recall them. If Stop reports an incomplete handoff, click
Refresh Synchronization on that account before starting a new linked run.
Linked-run handoff messages appear in both accounts' chat frames.
Run profile names allow letters, numbers, spaces, underscores, apostrophes
and hyphens, up to 48 characters.

Normal hiring waits for the companion to join, then one second. If no join is
seen, the 7.5-8.5 second wait remains. Legacy companions are also given time
to join before setup or deny commands are sent. Deny spells for one companion
can be sent together in a single whisper.

The account sidebar shows linked characters and the age of their last good
snapshot. Read peer licenses opens a separate read-only view. Saved raids
from Microbot Control Panel include MC, BWL, AQ40 and NAXX when available.

Add Legacy remembers known class and role choices. Its picker can scroll through
long lists, shows known classes in colour, and hides names already in the current
profile. Individual commands can set deny and setup commands for one legacy
hire. Add Normal can plan with linked characters' remembered tiers and faction
limits; Hire from moves a card to another eligible character, and cards show
their tier.



The addon does not include Microbot, CCP, client files, account data, or saved
profiles.

The composition planner builds a 40-slot plan from selected characters and
licences, normal and legacy hires, and optional player slots. It supports role
counts, synergy and hire priority. Estimated prices can be checked across
selected accounts; estimates may expire and are not a price lock. Save gold and
Ultra guide the proposal, but only Execute hires or spends gold. Quick Hire and
Random ask you to confirm the final choice before sending a hire command.

Stop ends local hiring, whispers, sorting and unsent linked hand-offs. A group
already delivered to another account must be stopped there.

Source: https://github.com/theShirina/shirs-raid-builder
Licence: MIT
