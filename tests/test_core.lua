-- Run with the exact target Lua runtime.
-- Example: lua tests/test_core.lua

dofile("../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua")
local C = ShirsRaidBuilderCore

local normalized = C.NormalizeDenyList({" Lightning Bolt ", "lightning bolt", "", "Chain Lightning"})
assert(table.getn(normalized) == 2)
assert(normalized[1] == "Lightning Bolt")
assert(normalized[2] == "Chain Lightning")

local legacy = {
    kind = "legacy",
    charName = "Example",
    role = "mdps",
    spec = "",
    denyList = {"Lightning Bolt", "Chain Lightning"},
}
assert(C.IsSafeCharacterName("Example"))
assert(not C.IsSafeCharacterName("Bad\" name"))
assert(not C.IsSafeCharacterName("Name;command"))
assert(C.BuildHireCommand({charName="Bad\" name", role="mdps"}) == nil)
assert(C.BuildNormalHireCommand({account="Bad name",tier="t2r",class="mage",role="rdps",spec="frost",race="human",gender="male"}) == nil)
assert(C.BuildNormalHireCommand({account="Example",tier="t2r;bad",class="mage",role="rdps",spec="frost",race="human",gender="male"}) == nil)
assert(C.NormalizeLegacyName("Longname") == "Longnam-lite")
assert(C.NormalizeLegacyName("Longnam-lite") == "Longnam-lite")
assert(C.NormalizeLegacyName("Shir") == "Shir-lite")
assert(C.NormalizeLegacyName("SuperLongName") == "SuperLo-lite")
assert(C.BuildHireCommand(legacy) == '.z addlegacy "Example" mdps')
assert(C.BuildDenyCommand(legacy, "Lightning Bolt") == "deny add Lightning Bolt")
assert(C.GetLegacyWhisperName(legacy) == "Example-lite")
legacy.whisperName = "Exampl-lite"
assert(C.GetLegacyWhisperName(legacy) == "Example-lite")
local longLegacy = { charName = "Longname" }
assert(C.GetLegacyHireName(longLegacy) == "Longname")
assert(C.GetLegacyWhisperName(longLegacy) == "Longnam-lite")
assert(C.BuildHireCommand(longLegacy) == '.z addlegacy "Longname" mdps')
assert(C.GetLegacyHireName({charName="Longnam-lite", sourceName="Longname"}) == "Longname")
assert(C.BuildHireCommand({charName="Longnam-lite", sourceName="Longname", role="mdps"}) == '.z addlegacy "Longname" mdps')

local rules = {
    { role = "mdps", class = "shaman", abilities = {"Lightning Bolt", "Chain Lightning"} },
}
local matching = { kind="legacy", role = "mdps", class = "shaman", denyList = {"Windfury Totem"} }
local effective = C.GetEffectiveDenyList(matching, rules)
assert(table.getn(effective) == 3)
assert(effective[1] == "Lightning Bolt")
assert(effective[2] == "Chain Lightning")
assert(effective[3] == "Windfury Totem")
local normalWithRule = {kind="normal", account="Healowner", role="healer", class="priest"}
local normalQueue = C.BuildQueue({entries={normalWithRule}, denyRules={{role="healer", class="priest", abilities={"Holy Nova"}}}})
assert(table.getn(normalQueue) == 2)
assert(normalQueue[2].phase == "role-class-final" and normalQueue[2].ability == "Holy Nova")
assert(normalQueue[2].command == "deny add Holy Nova")
assert(normalQueue[2].role == "healer" and normalQueue[2].class == "priest")
local lateNormal = {kind="normal", account="Example", role="healer", class="priest"}
local lateQueue = C.BuildQueue({entries={normalWithRule, lateNormal}, denyRules={{role="healer", class="priest", abilities={"Holy Nova"}}}})
assert(table.getn(lateQueue) == 3)
assert(lateQueue[1].kind == "normal" and lateQueue[2].kind == "normal")
assert(lateQueue[3].phase == "role-class-final" and lateQueue[3].ability == "Holy Nova")
assert(C.BuildDenyCommand({kind="normal", account="Healowner"}, "Holy Nova") == "deny add Holy Nova")
local parsedFive = C.ParseCompanionInfo("Unitone:Human:Priest:Healer:Example Other:Orc:Shaman:MDPS:Example")
assert(table.getn(parsedFive) == 2)
assert(parsedFive[1].name == "Unitone" and parsedFive[1].class == "priest" and parsedFive[1].role == "healer")
local parsedSix = C.ParseCompanionInfo("Unittwo:Human:Priest:Healer:Uncommon:Example")
assert(table.getn(parsedSix) == 1)
assert(parsedSix[1].name == "Unittwo" and parsedSix[1].class == "priest" and parsedSix[1].role == "healer")
local matchedSix = C.MatchCompanions(parsedSix, "healer", "priest")
assert(table.getn(matchedSix) == 1 and matchedSix[1] == "Unittwo")
local expanded = C.ExpandRoleDenies({lateQueue[3]}, parsedSix)
assert(table.getn(expanded) == 1)
assert(expanded[1].target == "Unittwo" and expanded[1].command == "deny add Holy Nova")
local gone = C.KeepPresentCompanions(parsedSix, { Unitone = true })
assert(table.getn(gone) == 0)
local stillHere = C.KeepPresentCompanions(parsedSix, { Unittwo = true })
assert(table.getn(stillHere) == 1 and stillHere[1].name == "Unittwo")
local skippedOld = C.ExpandRoleDenies({lateQueue[3]}, gone)
assert(table.getn(skippedOld) == 0)
local normalCustom = {kind="normal", account="Healowner", role="healer", class="priest", denyList={"Should Not Apply"}}
assert(table.getn(C.GetEffectiveDenyList(normalCustom, {})) == 0)
local legacyCustom = {kind="legacy", charName="OldCompanion", role="mdps", class="shaman", denyList={"Lightning Bolt"}, whisperName="OldCompanion"}
assert(table.getn(C.GetEffectiveDenyList(legacyCustom, {})) == 1)
assert(C.BuildTotemCommand("Windfury Totem") == "set totem Windfury Totem")
assert(C.BuildTotemCommand("cancel") == "set totem cancel")
assert(C.BuildAuraCommand("Devotion Aura") == "set aura Devotion Aura")
assert(C.BuildAspectCommand("Aspect of the Hawk") == "set aspect Aspect of the Hawk")
assert(C.BuildAspectCommand("AI Default (Clear Setting)") == "set aspect cancel")
assert(C.BuildPetCommand("on") == "set pet on")
assert(C.BuildPetCommand("Wolf") == "set pet wolf")
assert(C.BuildPetCommand("felhunter") == "set pet felhunter")
assert(C.BuildMagicCommand("None") == "set magic none")
assert(C.BuildMagicCommand("Amplify") == "set magic amplify")
assert(C.BuildMagicCommand("Dampen Magic") == "set magic dampen")
local magePlan = C.BuildClassSetupPlan({{class="mage", role="all", magic="Amplify"}})
assert(table.getn(magePlan) == 1 and magePlan[1].command == "set magic amplify")
local hunterPlan = C.BuildClassSetupPlan({{class="hunter", role="all", aspect="Aspect of the Hawk", pet="wolf"}})
assert(table.getn(hunterPlan) == 2)
assert(hunterPlan[1].command == "set aspect Aspect of the Hawk")
assert(hunterPlan[2].command == "set pet wolf")
local warlockPlan = C.BuildClassSetupPlan({{class="warlock", role="rdps", pet="off"}})
assert(table.getn(warlockPlan) == 1 and warlockPlan[1].command == "set pet off")
local orderedFirst, orderedSecond = C.OrderCompanionThenLegacy({"Bolt", "Longnam-lite", "Storm"}, {["Longnam-lite"]=true})
assert(table.getn(orderedFirst) == 2 and orderedFirst[1] == "Bolt" and orderedFirst[2] == "Storm")
assert(table.getn(orderedSecond) == 1 and orderedSecond[1] == "Longnam-lite")
local setupRule = {class="shaman", role="all", earth="Strength of Earth Totem", fire="Flametongue Totem", water="Mana Spring Totem", air="Windfury Totem"}
local setupPlan = C.BuildClassSetupPlan({setupRule})
assert(table.getn(setupPlan) == 4)
assert(setupPlan[1].command == "set totem Strength of Earth Totem")
assert(setupPlan[4].command == "set totem Windfury Totem")
local paladinPlan = C.BuildClassSetupPlan({{class="paladin", role="healer", aura="Concentration Aura"}})
assert(table.getn(paladinPlan) == 1 and paladinPlan[1].command == "set aura Concentration Aura")
local setupPeople = C.ParseCompanionInfo("Unittwo:Human:Priest:Healer:Uncommon:Example Storm:Orc:Shaman:Healer:Uncommon:Example Bolt:Orc:Shaman:MDPS:Uncommon:Example")
local allShaman = C.MatchCompanionsScoped(setupPeople, "shaman", "all")
assert(table.getn(allShaman) == 2)
local healerShaman = C.MatchCompanionsScoped(setupPeople, "shaman", "healer")
assert(table.getn(healerShaman) == 1 and healerShaman[1] == "Storm")
local expandedSetup = C.ExpandClassSetup(setupPlan, C.KeepPresentCompanions(setupPeople, {Storm=true, Bolt=true}))
assert(table.getn(expandedSetup) == 8)
local setupQueue = C.BuildQueue({entries={{kind="normal", account="Longname", tier="t2r", class="shaman", role="healer", spec="default", race="orc", gender="female"}}, setupRules={setupRule}})
assert(setupQueue[1].kind == "normal")
assert(setupQueue[2].phase == "class-setup" and setupQueue[2].command == "set totem Strength of Earth Totem")

local normal = {
    kind = "normal",
    account = "Longname",
    tier = "t2r",
    class = "shaman",
    role = "healer",
    spec = "default",
    race = "orc",
    gender = "female",
}
assert(C.BuildNormalHireCommand(normal) == ".z addinvite Longname t2r shaman healer default orc female")

local preset = { entries = { normal, legacy, { kind = "legacy", charName = "Warlocka", role = "healer", denyList = {} } } }
local queue = C.BuildQueue(preset)
assert(table.getn(queue) == 5)
assert(queue[1].kind == "normal" and queue[1].character == "Longname")
assert(queue[2].kind == "hire" and queue[2].character == "Example")
assert(queue[3].kind == "hire" and queue[3].character == "Warlocka")
assert(queue[4].kind == "deny" and queue[4].phase == "legacy-custom" and queue[4].ability == "Lightning Bolt" and queue[4].chatType == "WHISPER" and queue[4].target == "Example-lite")
assert(queue[5].kind == "deny" and queue[5].ability == "Chain Lightning")

local previewQueue = C.BuildQueue(preset)
assert(previewQueue[1].kind == "normal")
assert(previewQueue[2].kind == "hire")
assert(previewQueue[3].kind == "hire")
assert(previewQueue[4].command == "deny add Lightning Bolt")

local overwriteQueue = C.BuildQueue({
    entries = {legacy},
    setupRules = {setupRule},
})
assert(overwriteQueue[1].kind == "hire")
assert(overwriteQueue[2].phase == "class-setup")
assert(overwriteQueue[5].phase == "class-setup")
assert(overwriteQueue[6].phase == "legacy-custom" and overwriteQueue[6].command == "deny add Lightning Bolt")
assert(overwriteQueue[7].phase == "legacy-custom" and overwriteQueue[7].ability == "Chain Lightning")
assert(table.getn(overwriteQueue) == 7)

local petLegacy = {kind="legacy", sourceName="Warlocka", charName="Warlocka", class="warlock", role="rdps", pet="Voidwalker", denyList={}}
local petQueue = C.BuildQueue({entries={petLegacy}})
assert(petQueue[1].kind == "hire")
assert(petQueue[2].phase == "legacy-setup" and petQueue[2].command == "set pet voidwalker" and petQueue[2].target == "Warlock-lite")

local mixed = {
    {name="Bolt", class="shaman", role="healer"},
    {name="Longnam-lite", class="shaman", role="healer"},
}
local mixedPlan = C.BuildClassSetupPlan({
    {class="shaman", role="healer", earth="Strength of Earth Totem"},
    {class="shaman", role="healer", fire="Flametongue Totem"},
})
local mixedExpand = C.ExpandClassSetup(mixedPlan, mixed, {["Longnam-lite"]=true})
assert(table.getn(mixedExpand) == 4)
assert(mixedExpand[1].target == "Bolt" and mixedExpand[1].command == "set totem Strength of Earth Totem")
assert(mixedExpand[2].target == "Bolt" and mixedExpand[2].command == "set totem Flametongue Totem")
assert(mixedExpand[3].target == "Longnam-lite" and mixedExpand[3].command == "set totem Strength of Earth Totem")
assert(mixedExpand[4].target == "Longnam-lite" and mixedExpand[4].command == "set totem Flametongue Totem")
local leftoverSet = {["Longnam-lite"]=true}
local live = {
    {name="Bolt", class="shaman", role="healer"},
    {name="Storm", class="shaman", role="mdps"},
    {name="Longnam-lite", class="shaman", role="healer"},
}
local setupPending = C.BuildClassSetupPlan({{class="shaman", role="healer", earth="Strength of Earth Totem"}})
local denyPending = C.BuildGroupDenyPlan({{role="healer", class="shaman", abilities={"Lightning Bolt"}}})
local leftoverCard = {{kind="setup", phase="legacy-setup", target="Longnam-lite", command="set pet voidwalker"}}
local leftoverCustom = {{kind="deny", phase="legacy-custom", target="Longnam-lite", command="deny add Windfury Totem"}}
local assembled = C.AssembleLiveGroupCommands(setupPending, denyPending, leftoverCard, leftoverCustom, live, leftoverSet)
assert(assembled[1].target == "Bolt" and assembled[1].phase == "class-setup")
assert(assembled[2].target == "Bolt" and assembled[2].phase == "role-class-final")
assert(assembled[3].target == "Longnam-lite" and assembled[3].phase == "class-setup")
assert(assembled[4].target == "Longnam-lite" and assembled[4].phase == "role-class-final")
assert(assembled[5].phase == "legacy-setup" and assembled[5].target == "Longnam-lite")
assert(assembled[6].phase == "legacy-custom" and assembled[6].target == "Longnam-lite")
assert(table.getn(assembled) == 6)

assert(C.IsHireCommand({kind="normal"}))
assert(C.IsHireCommand({kind="hire"}))
assert(not C.IsHireCommand({kind="deny", chatType="WHISPER", target="Bolt"}))
assert(C.IsWhisperCommand({chatType="WHISPER", target="Bolt"}))
assert(not C.IsWhisperCommand({kind="hire", command=".z addlegacy"}))
assert(C.IsNodAck("Longnam-lite", "Longnam-lite nods at you.", "Longnam-lite"))
assert(C.IsNodAck("Bolt", "Bolt nods at you.", "Bolt"))
assert(C.IsNodAck("bolt", "Bolt nods at you.", "BOLT"))
assert(C.IsNodAck("", "Longnam-lite nods at you.", "Longnam-lite"))
assert(not C.IsNodAck("Storm", "Bolt nods at you.", "Bolt"))
assert(not C.IsNodAck("Bolt", "Bolt waves at you.", "Bolt"))
assert(C.IsBlacklistAck("Longnam-lite", "I have blacklisted Chain Lightning.", "Longnam-lite"))
assert(not C.IsBlacklistAck("Storm", "I have blacklisted Chain Lightning.", "Longnam-lite"))

local padded = C.PadRaidSlots({{kind="normal", account="Shir"}}, 8)
assert(table.getn(padded) == 8)
assert(C.FilledCount(padded) == 1)
assert(C.FirstEmptySlot(padded, 8) == 2)
assert(not C.IsFilledEntry({kind="empty"}))
local swapBoard = C.PadRaidSlots({
    {kind="normal", account="Shir", role="tank"},
    {kind="empty"},
    {kind="legacy", charName="Bolt", role="mdps"},
}, 8)
assert(C.SwapRaidSlots(swapBoard, 1, 3))
assert(swapBoard[1].charName == "Bolt" and swapBoard[3].account == "Shir")
assert(C.SwapRaidSlots(swapBoard, 3, 2))
assert(swapBoard[2].account == "Shir" and swapBoard[3].kind == "empty")
assert(not C.SwapRaidSlots(swapBoard, 3, 1))
local emptyQueue = C.BuildQueue({entries={{kind="empty"}, {kind="normal", account="Longname", tier="t2r", class="shaman", role="healer", spec="default", race="orc", gender="female"}}})
assert(emptyQueue[1].kind == "normal" and emptyQueue[1].character == "Longname")
assert(C.ClassAllowedForFaction("shaman", "Horde"))
assert(not C.ClassAllowedForFaction("shaman", "Alliance"))
assert(C.ClassAllowedForFaction("paladin", "Alliance"))
assert(not C.ClassAllowedForFaction("paladin", "Horde"))
assert(C.ClassAllowedForFaction("priest", "Alliance"))
local healerSpecs = C.SpecsForClassRole("paladin", "healer")
assert(table.getn(healerSpecs) == 1 and healerSpecs[1] == "default")
local tankSpecs = C.SpecsForClassRole("paladin", "tank")
assert(table.getn(tankSpecs) == 2 and tankSpecs[1] == "might" and tankSpecs[2] == "magic")
local invitePayload = C.ExtractInviteListPayload("[nexus] ACINFO:INVITE:LIST Shir:Warrior:T2D:T4R:A:0:60:1:4:0 Longname:Shaman:None:T1R:H:0:60:4:4:0")
local invites = C.ParseInviteList(invitePayload)
assert(table.getn(invites) == 2)
assert(invites[1].name == "Shir" and invites[1].faction == "Alliance" and invites[1].dungeonLicense == "t2d")
assert(C.CharacterCanHire(invites[1]))
assert(not C.CharacterCanHire(invites[2]))
local shirTiers = C.BuildLicenseOptions(invites[1].dungeonLicense, invites[1].raidLicense)
assert(shirTiers[1] == "t0d" and shirTiers[3] == "t2d" and shirTiers[table.getn(shirTiers)] == "t4r")
local roles = C.CountRoles({
    {kind="legacy", role="mdps"},
    {kind="empty"},
    {kind="normal", role="tank"},
    {kind="normal", role="healer"},
    {kind="normal", role="rdps"},
    {kind="normal", role="healer"},
})
assert(roles.tank == 1 and roles.healer == 2 and roles.mdps == 1 and roles.rdps == 1)
assert(C.RaidSlotGroup(1) == 1 and C.RaidSlotGroup(5) == 1)
assert(C.RaidSlotGroup(6) == 2 and C.RaidSlotGroup(40) == 8)
local raidAssign = C.BuildRaidAssignments({
    {kind="legacy", charName="Longname", sourceName="Longname"},
    {kind="empty"},
    {kind="empty"},
    {kind="empty"},
    {kind="empty"},
    {kind="normal", account="Shir"},
}, {[6]="Bolt"})
assert(C.AssignmentForName(raidAssign, "Longname") == 1)
assert(C.AssignmentForName(raidAssign, "Longnam-lite") == 1)
assert(C.AssignmentForName(raidAssign, "bolt") == 2)
local raidMoves = C.PlanRaidMoves({
    {index=1, name="Longname", group=3},
    {index=2, name="Bolt", group=1},
}, raidAssign)
assert(table.getn(raidMoves) == 2)
assert(raidMoves[1].name == "Longname" and raidMoves[1].group == 1)
assert(raidMoves[2].name == "Bolt" and raidMoves[2].group == 2)
local swapAssign = {A=2, B=2, C=2, D=2, E=2, F=1, G=1, H=1, I=1, J=1}
local swapRoster = {
    {index=1, name="A", group=1}, {index=2, name="B", group=1}, {index=3, name="C", group=1},
    {index=4, name="D", group=1}, {index=5, name="E", group=1},
    {index=6, name="F", group=2}, {index=7, name="G", group=2}, {index=8, name="H", group=2},
    {index=9, name="I", group=2}, {index=10, name="J", group=2},
}
local swapMoves = C.PlanRaidMoves(swapRoster, swapAssign)
assert(table.getn(swapMoves) == 10)
assert(swapMoves[1].name == "A" and swapMoves[1].group == 2)
assert(swapMoves[6].name == "F" and swapMoves[6].group == 1)
assert(C.IsPlayerEntry({kind="player", charName="Shir"}))
assert(C.IsFilledEntry({kind="player", charName="Shir"}))
local youBoard = C.PadRaidSlots({{kind="normal", account="Alt"}}, 8)
assert(C.EnsurePlayerSlot(youBoard, "Shir", "warrior", "tank") == 2)
assert(youBoard[2].kind == "player" and youBoard[2].charName == "Shir")
assert(C.EnsurePlayerSlot(youBoard, "Longname", "shaman") == 2)
assert(youBoard[2].charName == "Longname" and youBoard[2].class == "shaman" and youBoard[2].role == "tank")
assert(C.EnsurePlayerSlot(youBoard, "Longname", "shaman") == 2)
local youQueue = C.BuildQueue({entries=youBoard})
assert(table.getn(youQueue) == 1 and youQueue[1].kind == "normal")
local youAssign = C.BuildRaidAssignments(youBoard, {})
assert(C.AssignmentForName(youAssign, "Longname") == 1)
assert(C.AssignmentForName(youAssign, "Longnam-lite") == nil)
local hireQueue = {
    {kind="normal", sourceEntryIndex=2, character="Shir"},
    {kind="normal", sourceEntryIndex=6, character="Longname"},
    {kind="hire", sourceEntryIndex=3, character="Warlocka"},
}
local detected = {}
assert(C.AssignDetectedCompanions(hireQueue, detected, {"Bolt", "Storm"}) == 2)
assert(detected[2] == "Bolt" and detected[6] == "Storm")
assert(detected[3] == nil)
assert(C.AssignDetectedCompanions(hireQueue, detected, {"Extra"}) == 0)
local namedAssign = C.BuildRaidAssignments({
    {kind="player", charName="Shir"},
    {kind="normal", account="Shir"},
    {kind="empty"}, {kind="empty"}, {kind="empty"},
    {kind="normal", account="Longname"},
}, detected)
assert(C.AssignmentForName(namedAssign, "Bolt") == 1)
assert(C.AssignmentForName(namedAssign, "Storm") == 2)

local keptYou = C.NormalizeBoardEntry({kind="player", charName="Shir", class="warrior"})
assert(keptYou.kind == "player")
assert(keptYou.charName == "Shir")
assert(keptYou.class == "warrior")
assert(keptYou.role == "tank")
local keptPriest = C.NormalizeBoardEntry({kind="player", charName="Healowner", class="priest", role="rdps"})
assert(keptPriest.kind == "player" and keptPriest.role == "rdps")
local keptLegacy = C.NormalizeBoardEntry({kind="legacy", charName="Longname", class="shaman"})
assert(keptLegacy.kind == "legacy")
assert(keptLegacy.whisperName == "Longnam-lite")
local board = {
    {kind="player", charName="Shir", class="warrior"},
    {kind="normal", account="Alt", class="mage", role="rdps"},
}
C.RepairRaidEntries(board)
assert(board[1].kind == "player" and board[1].role == "tank")
assert(board[2].kind == "normal")
local youAgain = C.PadRaidSlots(board, 8)
assert(C.EnsurePlayerSlot(youAgain, "Shir", "warrior") == 1)
assert(youAgain[1].kind == "player")
assert(C.FilledCount(youAgain) == 2)

assert(C.ClassKeyFromLabel("Mage") == "mage")
assert(C.ClassKeyFromLabel("  Priest ") == "priest")
assert(parsedSix[1].owner == "Example")
assert(parsedFive[1].owner == "Example")

local liveBoard = C.PadRaidSlots({
    {kind="legacy", charName="Mageowner", class="mage", role="rdps"},
    {kind="legacy", charName="Shir", class="warrior", role="mdps"},
    {kind="normal", account="Shir", class="druid", role="mdps"},
    {kind="normal", account="Shir", class="warrior", role="mdps"},
    {kind="normal", account="Shir", class="paladin", role="mdps"},
    {kind="normal", account="Shir", class="rogue", role="mdps"},
    {kind="normal", account="Mageowner", class="hunter", role="rdps"},
    {kind="normal", account="Mageowner", class="druid", role="healer"},
    {kind="normal", account="Mageowner", class="paladin", role="healer"},
    {kind="normal", account="Mageowner", class="druid", role="tank"},
}, 40)
liveBoard[26] = {kind="player", charName="Mageowner", class="mage", role="rdps"}
C.RepairRaidEntries(liveBoard)
local liveInfo = C.ParseCompanionInfo("Guardone:Human:Warrior:MDPS:Uncommon:Shir Lightone:Human:Paladin:MDPS:Uncommon:Shir Bladeone:Human:Rogue:MDPS:Uncommon:Shir Clawone:NightElf:Druid:MDPS:Uncommon:Shir Lighttwo:Human:Paladin:Healer:Uncommon:Mageowner Arrowone:NightElf:Hunter:RDPS:Uncommon:Mageowner Healone:NightElf:Druid:Healer:Uncommon:Mageowner Tankone:NightElf:Druid:Tank:Uncommon:Mageowner")
local liveRoster = {
    {name="Shir-lite", group=1, class="Warrior"},
    {name="Mageown-lite", group=1, class="Mage"},
    {name="Guardone", group=1, class="Warrior"},
    {name="Lightone", group=1, class="Paladin"},
    {name="Clawone", group=2, class="Druid"},
    {name="Lighttwo", group=2, class="Paladin"},
    {name="Bladeone", group=2, class="Rogue"},
    {name="Healone", group=3, class="Druid"},
    {name="Tankone", group=3, class="Druid"},
    {name="Arrowone", group=6, class="Hunter"},
    {name="Mageowner", group=6, class="Mage"},
}
local liveAssign = C.BuildLiveRaidAssignments(liveBoard, {}, liveRoster, liveInfo)
assert(C.AssignmentForName(liveAssign, "Mageown-lite") == 1)
assert(C.AssignmentForName(liveAssign, "Shir-lite") == 1)
assert(C.AssignmentForName(liveAssign, "Clawone") == 1)
assert(C.AssignmentForName(liveAssign, "Guardone") == 1)
assert(C.AssignmentForName(liveAssign, "Lightone") == 1)
assert(C.AssignmentForName(liveAssign, "Bladeone") == 2)
assert(C.AssignmentForName(liveAssign, "Arrowone") == 2)
assert(C.AssignmentForName(liveAssign, "Healone") == 2)
assert(C.AssignmentForName(liveAssign, "Lighttwo") == 2)
assert(C.AssignmentForName(liveAssign, "Tankone") == 2)
assert(C.AssignmentForName(liveAssign, "Mageowner") == 6)
assert(C.SlotAssignmentForName(liveAssign, "Mageown-lite") == 1)
assert(C.SlotAssignmentForName(liveAssign, "Guardone") == 4)
local liveMoves = C.PlanRaidMoves(liveRoster, liveAssign)
assert(table.getn(liveMoves) >= 4)
assert(liveBoard[4].companionName == "Guardone")
local blankHunter = C.PadRaidSlots({{kind="normal", account="Mageowner", class="hunter", role="rdps"}}, 5)
assert(C.AssignmentForName(C.BuildLiveRaidAssignments(blankHunter, {}, {}, {}), "Arrowone") == nil)

local keptGuest = C.NormalizeBoardEntry({kind="guest", companionName="Guardone", charName="Guardone", account="Shir", class="Warrior", role="MDPS"})
assert(keptGuest.kind == "guest" and keptGuest.class == "warrior" and keptGuest.role == "mdps")
assert(C.IsFilledEntry(keptGuest))
local captured = C.CaptureRaidLayout({
    {name="Mageown-lite", group=1, class="Mage"},
    {name="Guardone", group=1, class="Warrior"},
    {name="Arrowone", group=2, class="Hunter"},
    {name="Mageowner", group=6, class="Mage"},
}, C.ParseCompanionInfo("Guardone:Human:Warrior:MDPS:Uncommon:Shir Arrowone:NightElf:Hunter:RDPS:Uncommon:Otherpal"), "Mageowner")
assert(captured[1].kind == "legacy" and captured[1].whisperName == "Mageown-lite")
assert(captured[2].kind == "guest" and captured[2].companionName == "Guardone" and captured[2].account == "Shir")
assert(captured[6].kind == "guest" and captured[6].companionName == "Arrowone" and captured[6].account == "Otherpal")
assert(captured[26].kind == "player" and captured[26].charName == "Mageowner")
local whisperOnly = C.BuildWhisperQueue({
    entries = captured,
    denyRules = {{role="mdps", class="warrior", abilities={"Hamstring"}}},
    setupRules = {{class="mage", role="all", magic="Amplify"}},
})
local hi = 1
for hi = 1, table.getn(whisperOnly) do
    assert(not C.IsHireCommand(whisperOnly[hi]))
end
assert(table.getn(whisperOnly) >= 1)
local guestAssign = C.BuildLiveRaidAssignments(captured, {}, {
    {name="Mageown-lite", group=3, class="Mage"},
    {name="Guardone", group=3, class="Warrior"},
    {name="Arrowone", group=3, class="Hunter"},
    {name="Mageowner", group=6, class="Mage"},
}, {})
assert(C.AssignmentForName(guestAssign, "Guardone") == 1)
assert(C.AssignmentForName(guestAssign, "Arrowone") == 2)

local exactEntries = C.PadRaidSlots({
    {kind="guest", companionName="Alpha", account="Shir", class="warrior", role="tank"},
    {kind="guest", companionName="Bravo", account="Shir", class="priest", role="healer"},
    {kind="guest", companionName="Charlie", account="Shir", class="mage", role="rdps"},
}, 40)
local exactWrongRoster = {
    {index=1, name="Bravo", group=1, class="Priest"},
    {index=2, name="Alpha", group=1, class="Warrior"},
    {index=3, name="Charlie", group=1, class="Mage"},
}
local exactAssign = C.BuildLiveRaidAssignments(exactEntries, {}, exactWrongRoster, {})
assert(table.getn(C.PlanRaidMoves(exactWrongRoster, exactAssign)) == 0)
local exactSwaps = C.PlanRaidOrderSwaps(exactWrongRoster, exactAssign)
assert(table.getn(exactSwaps) == 1)
assert(exactSwaps[1].name == "Alpha" and exactSwaps[1].other == "Bravo")
assert(exactSwaps[1].group == 1 and exactSwaps[1].slot == 1 and exactSwaps[1].ordinal == 1)
local exactRightRoster = {
    {index=1, name="Alpha", group=1, class="Warrior"},
    {index=2, name="Bravo", group=1, class="Priest"},
    {index=3, name="Charlie", group=1, class="Mage"},
}
assert(table.getn(C.PlanRaidOrderSwaps(exactRightRoster, exactAssign)) == 0)
local rebuild, rebuildReason = C.PlanRaidOrderRebuild(exactWrongRoster, exactAssign)
assert(rebuildReason == nil and table.getn(rebuild) == 6)
assert(rebuild[1].name == "Bravo" and rebuild[1].group == 8 and rebuild[1].phase == "stage")
assert(rebuild[2].name == "Alpha" and rebuild[2].group == 8 and rebuild[2].phase == "stage")
assert(rebuild[3].name == "Charlie" and rebuild[3].group == 8 and rebuild[3].phase == "stage")
assert(rebuild[4].name == "Alpha" and rebuild[4].group == 1 and rebuild[4].phase == "restore")
assert(rebuild[5].name == "Bravo" and rebuild[5].group == 1 and rebuild[5].phase == "restore")
assert(rebuild[6].name == "Charlie" and rebuild[6].group == 1 and rebuild[6].phase == "restore")
assert(C.RaidOrderSignature(exactWrongRoster) ~= C.RaidOrderSignature(exactRightRoster))
assert(table.getn(C.PlanRaidOrderSwaps(exactWrongRoster, exactAssign, {[1]=true})) == 0)
local twoGroupRoster = {
    {index=1, name="Bravo", group=1}, {index=2, name="Alpha", group=1},
    {index=3, name="Echo", group=2}, {index=4, name="Delta", group=2},
}
local twoGroupAssign = {
    Alpha={group=1,slot=1}, Bravo={group=1,slot=2},
    Delta={group=2,slot=6}, Echo={group=2,slot=7},
}
local secondGroupSwaps = C.PlanRaidOrderSwaps(twoGroupRoster, twoGroupAssign, {[1]=true})
assert(table.getn(secondGroupSwaps) == 1 and secondGroupSwaps[1].group == 2)

local fullRoster = {}
local fullAssign = {}
local fullIndex
for fullIndex = 1, 40 do
    local fullGroup = C.RaidSlotGroup(fullIndex)
    local fullName = "Member" .. fullIndex
    table.insert(fullRoster, {index=fullIndex, name=fullName, group=fullGroup})
    fullAssign[fullName] = {group=fullGroup, slot=fullIndex}
end
fullRoster[1].name = "Member2"; fullRoster[2].name = "Member1"
local fullRebuild, fullReason = C.PlanRaidOrderRebuild(fullRoster, fullAssign)
assert(table.getn(fullRebuild) == 0 and fullReason == "no-buffer")

local sharedBoard = C.PadRaidSlots({
    {kind="guest", companionName="Guardone", account="Shir", class="warrior", role="mdps"},
    {kind="legacy", charName="Mageowner", class="mage", role="rdps"},
}, 40)
sharedBoard[26] = {kind="player", charName="Mageowner", class="mage", role="rdps"}
C.RepairRaidEntries(sharedBoard)
local sharedInfo = C.ParseCompanionInfo("Guildwar:Human:Warrior:MDPS:Uncommon:Shir")
local sharedRoster = {
    {name="Guildwar", group=3, class="Warrior"},
    {name="Mageown-lite", group=3, class="Mage"},
    {name="Guildlead", group=6, class="Mage"},
}
local sharedAssign = C.BuildLiveRaidAssignments(sharedBoard, {}, sharedRoster, sharedInfo, "Guildlead")
assert(C.AssignmentForName(sharedAssign, "Guildwar") == 1)
assert(C.AssignmentForName(sharedAssign, "Mageown-lite") == 1)
assert(C.AssignmentForName(sharedAssign, "Guildlead") == 6)
assert(C.AssignmentForName(sharedAssign, "Guardone") == nil)

local banks = {presets={ZG={entries={{kind="normal",account="Shir"}}, denyRules={}}}, currentPreset="ZG"}
C.EnsureProfileBanks(banks)
assert(type(banks.sortPresets.Default) == "table")
local hireBank, hireName = C.PresetBank(banks, "hire")
local sortBank, sortName = C.PresetBank(banks, "sort")
assert(hireName == "ZG" and hireBank.ZG.entries[1].account == "Shir")
assert(sortName == "Default" and sortBank ~= hireBank)
assert(C.ActivePreset(banks, "hire") == hireBank.ZG)
assert(C.ActivePreset(banks, "sort") == sortBank.Default)

assert(C.IsLegacyHireStub("Mageown", {"Shir", "Mageowner", "Longname"}) == true)
assert(C.IsLegacyHireStub("Shir", {"Shir", "Mageowner", "Longname"}) == false)
assert(C.IsLegacyHireStub("Mageowner", {"Shir", "Mageowner", "Longname"}) == false)
assert(C.LayoutLabel({kind="guest", companionName="Bladeone", account="Mageowner", class="rogue"}) == "Mageowner")
assert(C.LayoutLabel({kind="legacy", charName="Mageowner", whisperName="Mageown-lite"}) == "Mageown-lite")
assert(C.LayoutLabel({kind="player", charName="Mageowner"}) == "Mageowner")
assert(C.HireCountName({kind="normal", account="Mageowner", companionName="Bladeone"}) == "Mageowner")
assert(C.HireCountName({kind="guest", account="Mageowner", companionName="Bladeone"}) == nil)
assert(C.HireCountName({kind="legacy", charName="Mageown", sourceName="Mageowner"}) == nil)
assert(C.ResolveLegacyHireName({charName="Mageown-lite", sourceName="Mageown"}, {"Shir", "Mageowner", "Longname"}) == "Mageowner")
assert(C.IsCapturedHirePreset({sortLayout=true, entries={{kind="guest"}}}) == true)
assert(C.IsCapturedHirePreset({entries={{kind="normal", account="Shir"}}}) == false)
local rescued = {presets={Default={sortLayout=true, entries={{kind="guest", account="Mageowner"}}}, ZG={entries={{kind="normal", account="Shir"}}}}, currentPreset="Default"}
local moved = C.RescueHirePreset(rescued)
assert(moved ~= nil and rescued.currentPreset == "ZG")
assert(rescued.sortPresets[moved].entries[1].kind == "guest")
assert(C.HireSlotCount({{kind="normal"},{kind="legacy"},{kind="guest"},{kind="player"}}) == 2)

local cappedHires = {
    {kind="normal", account="Shir"},
    {kind="normal", account="shir"},
    {kind="normal", account="SHIR"},
    {kind="normal", account="Shir"},
    {kind="legacy", charName="Shir"},
    {kind="guest", account="Shir"},
    {kind="player", charName="Shir"},
}
assert(C.NormalHireCountForCharacter(cappedHires, "Shir") == 4)
assert(C.NormalHireCountForCharacter(cappedHires, "Other") == 0)
assert(not C.CanAddNormalHire(cappedHires, "Shir", 4))
assert(C.CanAddNormalHire(cappedHires, "Other", 4))
assert(C.CanAddNormalHire({cappedHires[1], cappedHires[2], cappedHires[3]}, "Shir", 4))
assert(not C.CanAddNormalHire(cappedHires, "", 4))
local rejectedBoard = C.PadRaidSlots(cappedHires, 10)
local rejectedSlot, rejectedReason = C.TryAddNormalHire(rejectedBoard, {kind="normal", account="Shir"}, 4, 10)
assert(rejectedSlot == nil and rejectedReason == "character-limit")
assert(C.NormalHireCountForCharacter(rejectedBoard, "Shir") == 4)
local acceptedBoard = C.PadRaidSlots({cappedHires[1], cappedHires[2], cappedHires[3]}, 10)
local acceptedSlot, acceptedReason = C.TryAddNormalHire(acceptedBoard, {kind="normal", account="Shir"}, 4, 10)
assert(acceptedSlot == 4 and acceptedReason == nil)
assert(C.NormalHireCountForCharacter(acceptedBoard, "Shir") == 4)

local warningDB = {}
assert(C.CaptureWarningKey("Mageowner", "Microbot") == "microbot:mageowner")
assert(C.ShouldShowCaptureWarning(warningDB, "Mageowner", "Microbot"))
assert(C.SetCaptureWarningHidden(warningDB, "Mageowner", "Microbot", true))
assert(not C.ShouldShowCaptureWarning(warningDB, "Mageowner", "Microbot"))
assert(C.ShouldShowCaptureWarning(warningDB, "Shir", "Microbot"))
assert(C.ShouldShowCaptureWarning(warningDB, "Mageowner", "Other Realm"))
assert(not C.SetCaptureWarningHidden(warningDB, "", "Microbot", true))
warningDB.captureWarningHidden["microbot:mageowner"] = "yes"
assert(C.ShouldShowCaptureWarning(warningDB, "Mageowner", "Microbot"))

print("Shir's Raid Builder core tests: PASS")
