-- Shir's Raid Builder 0.61
-- Clean-room core helpers. Server deny syntax is intentionally configurable.

ShirsRaidBuilderCore = ShirsRaidBuilderCore or {}
local C = ShirsRaidBuilderCore

function C.Trim(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

function C.IsSafeCharacterName(value)
    local name = C.Trim(value)
    local length = string.len(name)
    if length < 2 or length > 12 then return false end
    return string.find(name, "^[A-Za-z]+$") ~= nil
end

function C.IsSafeCommandToken(value)
    local token = C.Trim(value)
    if token == "" then return false end
    return string.find(token, "^[A-Za-z0-9]+$") ~= nil
end

function C.NormalizeDenyList(values)
    local result = {}
    local seen = {}
    if type(values) ~= "table" then return result end
    for i = 1, table.getn(values) do
        local value = C.Trim(values[i])
        local key = string.lower(value)
        if value ~= "" and not seen[key] then
            table.insert(result, value)
            seen[key] = true
        end
    end
    return result
end

function C.CopyDenyList(values)
    local result = {}
    local source = C.NormalizeDenyList(values)
    for i = 1, table.getn(source) do result[i] = source[i] end
    return result
end

function C.GetLegacyHireName(legacy)
    if type(legacy) ~= "table" then return C.Trim(legacy) end
    local source = C.Trim(legacy.sourceName)
    if source ~= "" then return source end
    local name = C.Trim(legacy.charName)
    if name == "" then return "" end
    if string.sub(string.lower(name), -5) == "-lite" then
        return string.sub(name, 1, string.len(name) - 5)
    end
    return name
end

function C.BuildHireCommand(legacy)
    if type(legacy) ~= "table" then return nil end
    local name = C.ResolveLegacyHireName(legacy, C.knownCharacterNames)
    if not C.IsSafeCharacterName(name) then return nil end
    local role = C.Trim(legacy.role)
    if role == "" then role = "mdps" end
    local spec = C.Trim(legacy.spec)
    if not C.IsSafeCommandToken(role) then return nil end
    if spec ~= "" and not C.IsSafeCommandToken(spec) then return nil end
    local command = ".z addlegacy \"" .. name .. "\" " .. role
    if spec ~= "" and string.lower(spec) ~= "default" then
        command = command .. " " .. spec
    end
    return command
end

function C.BuildNormalHireCommand(slot)
    if type(slot) ~= "table" then return nil end
    local account = C.Trim(slot.account)
    if not C.IsSafeCharacterName(account) then return nil end
    local fields = {
        account,
        C.Trim(slot.tier) ~= "" and C.Trim(slot.tier) or "t2r",
        C.Trim(slot.class) ~= "" and C.Trim(slot.class) or "warrior",
        C.Trim(slot.role) ~= "" and C.Trim(slot.role) or "mdps",
        C.Trim(slot.spec) ~= "" and C.Trim(slot.spec) or "default",
        C.Trim(slot.race) ~= "" and C.Trim(slot.race) or "human",
        C.Trim(slot.gender) ~= "" and C.Trim(slot.gender) or "male",
    }
    for i = 2, table.getn(fields) do if not C.IsSafeCommandToken(fields[i]) then return nil end end
    if not C.RoleAllowedForClass(fields[3], fields[4]) then return nil end
    return ".z addinvite " .. fields[1] .. " " .. fields[2] .. " " .. fields[3]
        .. " " .. fields[4] .. " " .. fields[5] .. " " .. fields[6] .. " " .. fields[7]
end

function C.NormalizeLegacyName(value)
    local name = C.Trim(value)
    if name == "" then return "" end
    if string.sub(string.lower(name), -5) == "-lite" then
        name = string.sub(name, 1, string.len(name) - 5)
        name = C.Trim(name)
    end
    if name == "" then return "" end
    if string.len(name) > 7 then name = string.sub(name, 1, 7) end
    return name .. "-lite"
end

function C.GetLegacyWhisperName(legacy)
    if type(legacy) ~= "table" then return C.NormalizeLegacyName(legacy) end
    local fromSource = C.NormalizeLegacyName(legacy.sourceName)
    if fromSource ~= "" then return fromSource end
    return C.NormalizeLegacyName(legacy.charName)
end

function C.GetEffectiveDenyList(entry, rules)
    local result = {}
    local seen = {}
    local function addValues(values)
        local normalized = C.NormalizeDenyList(values)
        for i = 1, table.getn(normalized) do
            local value = normalized[i]
            local key = string.lower(value)
            if not seen[key] then
                table.insert(result, value)
                seen[key] = true
            end
        end
    end
    if type(entry) == "table" and type(rules) == "table" then
        local entryRole = string.lower(C.Trim(entry.role))
        local entryClass = string.lower(C.Trim(entry.class))
        for i = 1, table.getn(rules) do
            local rule = rules[i]
            local ruleRole = string.lower(C.Trim(rule.role))
            local ruleClass = string.lower(C.Trim(rule.class))
            if (ruleRole == entryRole or ruleRole == "all") and ruleClass == entryClass then
                addValues(rule.abilities)
            end
        end
    end
    if type(entry) == "table" and entry.kind == "legacy" then addValues(entry.denyList) end
    return result
end

function C.GetRoleDenyList(entry, rules)
    local result = {}
    local seen = {}
    if type(entry) ~= "table" or type(rules) ~= "table" then return result end
    local entryRole = string.lower(C.Trim(entry.role))
    local entryClass = string.lower(C.Trim(entry.class))
    for i = 1, table.getn(rules) do
        local rule = rules[i]
        local ruleRole = string.lower(C.Trim(rule.role))
        if (ruleRole == entryRole or ruleRole == "all") and string.lower(C.Trim(rule.class)) == entryClass then
            local abilities = C.NormalizeDenyList(rule.abilities)
            for ai = 1, table.getn(abilities) do
                local key = string.lower(abilities[ai])
                if not seen[key] then table.insert(result, abilities[ai]); seen[key] = true end
            end
        end
    end
    return result
end

function C.BuildDenyCommand(legacy, ability)
    local spell = C.Trim(ability)
    if spell == "" then return nil end
    return "deny add " .. spell
end

function C.GetWhisperTarget(entry)
    if type(entry) ~= "table" then return "" end
    local explicit = C.Trim(entry.companionName or entry.denyWhisperName)
    if explicit ~= "" then return explicit end
    if entry.kind == "legacy" then return C.GetLegacyWhisperName(entry) end
    return C.Trim(entry.account)
end

function C.NormalizeRoleLabel(value)
    local role = string.lower(C.Trim(value))
    if role == "melee dps" then return "mdps" end
    if role == "ranged dps" then return "rdps" end
    return role
end

function C.NormalizeClassLabel(value)
    return string.lower(C.Trim(value))
end

function C.ParseCompanionInfo(text)
    local result = {}
    local source = C.Trim(text)
    if source == "" then return result end
    local start = 1
    local space = string.find(source, " ", start)
    while space do
        local block = string.sub(source, start, space - 1)
        if block ~= "" then table.insert(result, block) end
        start = space + 1
        space = string.find(source, " ", start)
    end
    if start <= string.len(source) then table.insert(result, string.sub(source, start)) end
    local companions = {}
    for i = 1, table.getn(result) do
        local parts = {}
        local block = result[i]
        local partStart = 1
        local colon = string.find(block, ":", partStart)
        while colon do
            table.insert(parts, string.sub(block, partStart, colon - 1))
            partStart = colon + 1
            colon = string.find(block, ":", partStart)
        end
        if partStart <= string.len(block) then table.insert(parts, string.sub(block, partStart)) end
        if table.getn(parts) >= 4 and C.Trim(parts[1]) ~= "" then
            table.insert(companions, {
                name = C.Trim(parts[1]),
                race = C.NormalizeClassLabel(parts[2]),
                class = C.NormalizeClassLabel(parts[3]),
                role = C.NormalizeRoleLabel(parts[4]),
                owner = C.Trim(parts[table.getn(parts)]),
            })
        end
    end
    return companions
end

function C.MatchCompanions(companions, role, class)
    local result = {}
    local wantRole = C.NormalizeRoleLabel(role)
    local wantClass = C.NormalizeClassLabel(class)
    if type(companions) ~= "table" or wantRole == "" or wantClass == "" then return result end
    for i = 1, table.getn(companions) do
        local companion = companions[i]
        if companion.role == wantRole and companion.class == wantClass and C.Trim(companion.name) ~= "" then
            table.insert(result, companion.name)
        end
    end
    return result
end

function C.BuildGroupDenyPlan(rules)
    local result = {}
    local seen = {}
    if type(rules) ~= "table" then return result end
    for i = 1, table.getn(rules) do
        local rule = rules[i]
        local role = C.NormalizeRoleLabel(rule.role)
        local class = C.NormalizeClassLabel(rule.class)
        local abilities = C.NormalizeDenyList(rule.abilities)
        for ai = 1, table.getn(abilities) do
            local key = role .. "|" .. class .. "|" .. string.lower(abilities[ai])
            if not seen[key] then
                seen[key] = true
                table.insert(result, {
                    kind = "deny",
                    phase = "role-class-final",
                    role = role,
                    class = class,
                    ability = abilities[ai],
                    chatType = "WHISPER",
                    target = "",
                    command = C.BuildDenyCommand(nil, abilities[ai]),
                })
            end
        end
    end
    return result
end

function C.BuildTotemCommand(name)
    local spell = C.Trim(name)
    if spell == "" or string.lower(spell) == "none" then return nil end
    if string.lower(spell) == "cancel" then return "set totem cancel" end
    return "set totem " .. spell
end

function C.BuildAuraCommand(name)
    local spell = C.Trim(name)
    if spell == "" or string.lower(spell) == "none" then return nil end
    if string.lower(spell) == "cancel" then return "set aura cancel" end
    return "set aura " .. spell
end

function C.BuildAspectCommand(name)
    local spell = C.Trim(name)
    if spell == "" or string.lower(spell) == "none" then return nil end
    local lower = string.lower(spell)
    if lower == "cancel" or string.find(lower, "ai default", 1, true) then return "set aspect cancel" end
    return "set aspect " .. spell
end

function C.BuildPetCommand(name)
    local spell = C.Trim(name)
    if spell == "" or string.lower(spell) == "none" then return nil end
    local lower = string.lower(spell)
    if lower == "on" then return "set pet on" end
    if lower == "off" then return "set pet off" end
    return "set pet " .. lower
end

function C.BuildMagicCommand(name)
    local spell = C.Trim(name)
    if spell == "" or string.lower(spell) == "(none)" then return nil end
    local lower = string.lower(spell)
    if lower == "none" or lower == "cancel" then return "set magic none" end
    if lower == "amplify" or lower == "amplify magic" then return "set magic amplify" end
    if lower == "dampen" or lower == "dampen magic" then return "set magic dampen" end
    return nil
end

function C.LegacyNameSet(entries)
    local set = {}
    if type(entries) ~= "table" then return set end
    for i = 1, table.getn(entries) do
        local entry = entries[i]
        if type(entry) == "table" and entry.kind == "legacy" then
            local name = C.GetLegacyWhisperName(entry)
            if name ~= "" then set[name] = true end
        end
    end
    return set
end

function C.OrderCompanionThenLegacy(names, legacySet)
    local companions = {}
    local legacy = {}
    if type(names) ~= "table" then return companions, legacy end
    for i = 1, table.getn(names) do
        local name = names[i]
        if legacySet and legacySet[name] then table.insert(legacy, name) else table.insert(companions, name) end
    end
    return companions, legacy
end

function C.MatchCompanionsScoped(companions, class, role)
    local wantClass = C.NormalizeClassLabel(class)
    local wantRole = C.NormalizeRoleLabel(role)
    local result = {}
    if type(companions) ~= "table" or wantClass == "" then return result end
    local anyRole = wantRole == "" or wantRole == "all"
    for i = 1, table.getn(companions) do
        local companion = companions[i]
        if companion.class == wantClass and C.Trim(companion.name) ~= "" then
            if anyRole or companion.role == wantRole then table.insert(result, companion.name) end
        end
    end
    return result
end

function C.BuildClassSetupPlan(rules)
    local result = {}
    if type(rules) ~= "table" then return result end
    for i = 1, table.getn(rules) do
        local rule = rules[i]
        local class = C.NormalizeClassLabel(rule.class)
        local role = C.NormalizeRoleLabel(rule.role)
        if role == "" then role = "all" end
        local spec = string.lower(C.Trim(rule.spec))
        if spec == "" then spec = "all" end
        local commands = {}
        if class == "shaman" then
            table.insert(commands, C.BuildTotemCommand(rule.earth))
            table.insert(commands, C.BuildTotemCommand(rule.fire))
            table.insert(commands, C.BuildTotemCommand(rule.water))
            table.insert(commands, C.BuildTotemCommand(rule.air))
        elseif class == "paladin" then
            table.insert(commands, C.BuildAuraCommand(rule.aura))
        elseif class == "hunter" then
            table.insert(commands, C.BuildAspectCommand(rule.aspect))
            table.insert(commands, C.BuildPetCommand(rule.pet))
        elseif class == "warlock" then
            table.insert(commands, C.BuildPetCommand(rule.pet))
        elseif class == "mage" then
            table.insert(commands, C.BuildMagicCommand(rule.magic))
        end
        for ci = 1, table.getn(commands) do
            if commands[ci] then
                table.insert(result, {
                    kind = "setup",
                    phase = "class-setup",
                    class = class,
                    role = role,
                    spec = spec,
                    chatType = "WHISPER",
                    target = "",
                    command = commands[ci],
                })
            end
        end
    end
    return result
end

function C.ExpandNamedWhispers(items, companions, leftoverSet, phase)
    local result = {}
    local leftover = {}
    if type(items) ~= "table" then return result end
    for i = 1, table.getn(items) do
        local item = items[i]
        local names = C.MatchCompanionsScoped(companions, item.class or item.role and item.class, item.role)
        if item.phase == "role-class-final" or (item.role and item.class and item.ability) then
            names = C.MatchCompanionsScoped(companions, item.class, item.role)
        end
        local first, second = C.OrderCompanionThenLegacy(names, leftoverSet)
        local function Emit(name, dest)
            local copy = {
                kind = item.kind or "setup",
                phase = phase or item.phase,
                class = item.class,
                role = item.role,
                spec = item.spec,
                ability = item.ability,
                chatType = "WHISPER",
                target = name,
                command = item.command,
            }
            table.insert(dest, copy)
        end
        for ni = 1, table.getn(first) do Emit(first[ni], result) end
        for ni = 1, table.getn(second) do Emit(second[ni], leftover) end
    end
    for i = 1, table.getn(leftover) do table.insert(result, leftover[i]) end
    return result
end

function C.ExpandClassSetup(items, companions, leftoverSet)
    return C.ExpandNamedWhispers(items, companions, leftoverSet, "class-setup")
end

function C.KeepPresentCompanions(companions, present)
    local result = {}
    if type(companions) ~= "table" or type(present) ~= "table" then return result end
    for i = 1, table.getn(companions) do
        local companion = companions[i]
        local name = companion and companion.name
        if name and name ~= "" and present[name] then table.insert(result, companion) end
    end
    return result
end

function C.ExpandRoleDenies(denies, companions, leftoverSet)
    local result = {}
    local leftover = {}
    local seen = {}
    if type(denies) ~= "table" then return result end
    for i = 1, table.getn(denies) do
        local deny = denies[i]
        local names = C.MatchCompanionsScoped(companions, deny.class, deny.role)
        local first, second = C.OrderCompanionThenLegacy(names, leftoverSet)
        local function Emit(name, dest)
            local key = string.lower(C.Trim(name)) .. "|" .. string.lower(C.Trim(deny.ability))
            if seen[key] then return end
            seen[key] = true
            table.insert(dest, {
                kind = "deny",
                phase = "role-class-final",
                role = deny.role,
                class = deny.class,
                ability = deny.ability,
                chatType = "WHISPER",
                target = name,
                command = deny.command or C.BuildDenyCommand(nil, deny.ability),
            })
        end
        for ni = 1, table.getn(first) do Emit(first[ni], result) end
        for ni = 1, table.getn(second) do Emit(second[ni], leftover) end
    end
    for i = 1, table.getn(leftover) do table.insert(result, leftover[i]) end
    return result
end

function C.SplitCompanionAndLegacy(items, leftoverSet)
    local first = {}
    local second = {}
    if type(items) ~= "table" then return first, second end
    leftoverSet = leftoverSet or {}
    local i
    for i = 1, table.getn(items) do
        local item = items[i]
        if leftoverSet[item.target] then table.insert(second, item) else table.insert(first, item) end
    end
    return first, second
end

function C.AssembleLiveGroupCommands(setupPending, denyPending, leftoverCard, leftoverCustom, companions, leftoverSet)
    local result = {}
    local setups = C.ExpandClassSetup(setupPending, companions, leftoverSet)
    local denies = C.ExpandRoleDenies(denyPending, companions, leftoverSet)
    local setupFirst, setupLast = C.SplitCompanionAndLegacy(setups, leftoverSet)
    local denyFirst, denyLast = C.SplitCompanionAndLegacy(denies, leftoverSet)
    local i
    for i = 1, table.getn(setupFirst) do table.insert(result, setupFirst[i]) end
    for i = 1, table.getn(denyFirst) do table.insert(result, denyFirst[i]) end
    for i = 1, table.getn(setupLast) do table.insert(result, setupLast[i]) end
    for i = 1, table.getn(denyLast) do table.insert(result, denyLast[i]) end
    leftoverCard = leftoverCard or {}
    leftoverCustom = leftoverCustom or {}
    for i = 1, table.getn(leftoverCard) do table.insert(result, leftoverCard[i]) end
    for i = 1, table.getn(leftoverCustom) do table.insert(result, leftoverCustom[i]) end
    return result
end

function C.BuildQueue(preset)
    local queue = {}
    local lateWhispers = {}
    if type(preset) ~= "table" or type(preset.entries) ~= "table" then return queue end
    for i = 1, table.getn(preset.entries) do
        local entry = preset.entries[i]
        local hire = nil
        local character = ""
        local isLegacy = false
        if C.IsFilledEntry(entry) and entry.kind == "normal" then
            hire = C.BuildNormalHireCommand(entry)
            character = C.Trim(entry.account)
        elseif C.IsFilledEntry(entry) and entry.kind == "legacy" then
            hire = C.BuildHireCommand(entry)
            character = C.Trim(entry.charName)
            isLegacy = true
        end
        if hire then
            table.insert(queue, {kind = isLegacy and "hire" or "normal", character = character, sourceEntryIndex = i, command = hire})
            if isLegacy then
                local customDenies = C.NormalizeDenyList(entry.denyList)
                for di = 1, table.getn(customDenies) do
                    table.insert(lateWhispers, {
                        kind = "deny",
                        phase = "legacy-custom",
                        character = character,
                        sourceEntryIndex = i,
                        ability = customDenies[di],
                        chatType = "WHISPER",
                        target = C.GetWhisperTarget(entry),
                        command = C.BuildDenyCommand(entry, customDenies[di]),
                    })
                end
            end
        end
    end
    local groupDenies = C.BuildGroupDenyPlan(preset.denyRules)
    for i = 1, table.getn(groupDenies) do table.insert(queue, groupDenies[i]) end
    local setups = C.BuildClassSetupPlan(preset.setupRules)
    for i = 1, table.getn(setups) do table.insert(queue, setups[i]) end
    for i = 1, table.getn(preset.entries) do
        local entry = preset.entries[i]
        if C.IsFilledEntry(entry) and entry.kind == "legacy" then
            local target = C.GetWhisperTarget(entry)
            local pet = C.BuildPetCommand(entry.pet)
            if pet and target ~= "" then
                table.insert(queue, {kind="setup", phase="legacy-setup", character=C.Trim(entry.charName), sourceEntryIndex=i, chatType="WHISPER", target=target, command=pet})
            end
            local aspect = C.BuildAspectCommand(entry.aspect)
            if aspect and target ~= "" then
                table.insert(queue, {kind="setup", phase="legacy-setup", character=C.Trim(entry.charName), sourceEntryIndex=i, chatType="WHISPER", target=target, command=aspect})
            end
            local magic = C.BuildMagicCommand(entry.magic)
            if magic and target ~= "" then
                table.insert(queue, {kind="setup", phase="legacy-setup", character=C.Trim(entry.charName), sourceEntryIndex=i, chatType="WHISPER", target=target, command=magic})
            end
        end
    end
    for i = 1, table.getn(lateWhispers) do table.insert(queue, lateWhispers[i]) end
    return queue
end

function C.IsFilledEntry(entry)
    if type(entry) ~= "table" then return false end
    if entry.kind == "empty" then return false end
    return entry.kind == "normal" or entry.kind == "legacy" or entry.kind == "player" or entry.kind == "guest" or C.Trim(entry.account) ~= "" or C.Trim(entry.charName) ~= "" or C.Trim(entry.companionName) ~= ""
end

function C.IsPlayerEntry(entry)
    return type(entry) == "table" and entry.kind == "player"
end

function C.DefaultRoleForClass(class)
    local key = string.lower(C.Trim(class))
    if key == "priest" or key == "mage" or key == "warlock" or key == "hunter" then return "rdps" end
    if key == "rogue" then return "mdps" end
    return "tank"
end

function C.RoleAllowedForClass(class, role)
    local key = string.lower(C.Trim(class))
    local want = C.NormalizeRoleLabel(role)
    local roles = {
        warrior={tank=true,mdps=true}, mage={rdps=true}, warlock={rdps=true},
        priest={healer=true,rdps=true}, druid={tank=true,healer=true,mdps=true,rdps=true},
        paladin={tank=true,healer=true,mdps=true}, shaman={tank=true,healer=true,mdps=true,rdps=true},
        hunter={rdps=true}, rogue={mdps=true},
    }
    return roles[key] and roles[key][want] == true or false
end

function C.AbilitiesForClassRole(catalog, class, role)
    local key = C.NormalizeClassLabel(class)
    local want = C.NormalizeRoleLabel(role)
    if type(catalog) ~= "table" then return {} end
    if want ~= "all" and not C.RoleAllowedForClass(key, want) then return {} end
    return type(catalog[key]) == "table" and catalog[key] or {}
end

function C.NormalizeRoleForClass(class, role)
    local want = C.NormalizeRoleLabel(role)
    if C.RoleAllowedForClass(class, want) then return want end
    return C.DefaultRoleForClass(class)
end

function C.RememberCharacterRole(roles, name, class, role)
    local value = C.NormalizeRoleForClass(class, role)
    if type(roles) == "table" then
        local key = string.lower(C.Trim(name))
        if key ~= "" then roles[key] = value end
    end
    return value
end

function C.RememberedCharacterRole(roles, name, class)
    local key = string.lower(C.Trim(name))
    local role = type(roles) == "table" and roles[key] or nil
    return C.NormalizeRoleForClass(class, role)
end

function C.MigrateCharacterRoles(roles, presets, currentPreset)
    if type(roles) ~= "table" or type(presets) ~= "table" then return roles end
    local names = {}
    local name
    for name in pairs(presets) do
        if name ~= currentPreset then table.insert(names, name) end
    end
    table.sort(names)
    if currentPreset and type(presets[currentPreset]) == "table" then table.insert(names, 1, currentPreset) end
    local ni
    for ni = 1, table.getn(names) do
        local preset = presets[names[ni]]
        local entries = type(preset) == "table" and preset.entries or nil
        if type(entries) == "table" then
            local i
            for i = 1, table.getn(entries) do
                local entry = entries[i]
                if C.IsPlayerEntry(entry) and C.Trim(entry.charName) ~= "" then
                    local key = string.lower(C.Trim(entry.charName))
                    if not roles[key] then C.RememberCharacterRole(roles, entry.charName, entry.class, entry.role) end
                end
            end
        end
    end
    return roles
end

function C.ClassKeyFromLabel(class)
    return string.lower(C.Trim(class))
end

function C.NormalizeBoardEntry(entry)
    if type(entry) ~= "table" then return {kind="empty"} end
    if entry.kind == "empty" then return entry end
    if entry.kind == "player" then
        local class = C.Trim(entry.class)
        local role = C.NormalizeRoleForClass(class, entry.role)
        if class == "paladin" and role == "healer" then entry.spec = "default" end
        entry.kind = "player"
        entry.class = class
        entry.role = role
        return entry
    end
    if entry.kind == "guest" then
        local class = C.NormalizeClassLabel(entry.class)
        local role = C.NormalizeRoleForClass(class, entry.role)
        entry.kind = "guest"
        entry.class = class
        entry.role = role
        if C.Trim(entry.companionName) == "" then entry.companionName = C.Trim(entry.charName) end
        return entry
    end
    if entry.kind == "legacy" or (C.Trim(entry.charName) ~= "" and C.Trim(entry.account) == "" and entry.kind ~= "normal" and entry.kind ~= "guest") then
        entry.kind = "legacy"
        entry.denyList = C.NormalizeDenyList(entry.denyList)
        entry.class = C.Trim(entry.class) ~= "" and string.lower(entry.class) or "warrior"
        entry.role = C.NormalizeRoleForClass(entry.class, entry.role)
        if entry.class == "paladin" and entry.role == "healer" then entry.spec = "default" end
        local hireName = C.GetLegacyHireName(entry)
        if hireName ~= "" then
            entry.sourceName = hireName
            entry.charName = hireName
        end
        entry.whisperName = C.GetLegacyWhisperName(entry)
        return entry
    end
    entry.kind = "normal"
    entry.class = C.Trim(entry.class) ~= "" and string.lower(entry.class) or "warrior"
    entry.role = C.NormalizeRoleForClass(entry.class, entry.role)
    if entry.class == "paladin" and entry.role == "healer" then entry.spec = "default" end
    return entry
end

function C.RepairRaidEntries(entries)
    if type(entries) ~= "table" then return entries end
    local i
    for i = 1, table.getn(entries) do
        entries[i] = C.NormalizeBoardEntry(entries[i])
    end
    return entries
end

function C.EnsurePlayerSlot(entries, name, class, role)
    C.PadRaidSlots(entries, 40)
    local playerName = C.Trim(name)
    if playerName == "" then return nil end
    local found = nil
    local i
    for i = 1, 40 do
        if C.IsPlayerEntry(entries[i]) then
            if found then
                entries[i] = {kind="empty"}
            else
                found = i
            end
        end
    end
    if not found then found = C.FirstEmptySlot(entries, 40) end
    if not found then return nil end
    local previous = entries[found]
    local keepRole = C.Trim(role)
    if keepRole == "" and previous and previous.kind == "player" then keepRole = C.Trim(previous.role) end
    keepRole = C.NormalizeRoleForClass(class, keepRole)
    entries[found] = {
        kind = "player",
        charName = playerName,
        class = C.Trim(class),
        role = keepRole,
    }
    return found
end

function C.PadRaidSlots(entries, size)
    local want = size or 40
    if type(entries) ~= "table" then entries = {} end
    for i = 1, table.getn(entries) do
        if type(entries[i]) ~= "table" then
            entries[i] = {kind="empty"}
        elseif not C.IsFilledEntry(entries[i]) then
            entries[i].kind = "empty"
        end
    end
    while table.getn(entries) < want do table.insert(entries, {kind="empty"}) end
    return entries
end

function C.FirstEmptySlot(entries, size)
    local want = size or 40
    if type(entries) ~= "table" then return 1 end
    for i = 1, want do
        if not C.IsFilledEntry(entries[i]) then return i end
    end
    return nil
end

function C.SwapRaidSlots(entries, fromIndex, toIndex)
    if type(entries) ~= "table" then return false end
    C.PadRaidSlots(entries, 40)
    if not fromIndex or not toIndex then return false end
    if fromIndex == toIndex then return false end
    if fromIndex < 1 or toIndex < 1 or fromIndex > 40 or toIndex > 40 then return false end
    if not C.IsFilledEntry(entries[fromIndex]) then return false end
    local held = entries[fromIndex]
    entries[fromIndex] = entries[toIndex] or {kind="empty"}
    entries[toIndex] = held
    return true
end

function C.FilledCount(entries)
    local total = 0
    if type(entries) ~= "table" then return 0 end
    for i = 1, table.getn(entries) do
        if C.IsFilledEntry(entries[i]) then total = total + 1 end
    end
    return total
end

function C.CountRoles(entries)
    local counts = {tank=0, healer=0, mdps=0, rdps=0}
    if type(entries) ~= "table" then return counts end
    for i = 1, table.getn(entries) do
        local entry = entries[i]
        if C.IsFilledEntry(entry) and counts[entry.role] then
            counts[entry.role] = counts[entry.role] + 1
        end
    end
    return counts
end

function C.ClassAllowedForFaction(class, faction)
    if faction == "Alliance" then return class ~= "shaman" end
    if faction == "Horde" then return class ~= "paladin" end
    return true
end

function C.SpecsForClassRole(class, role)
    if class == "paladin" and role == "healer" then return {"default"} end
    if class == "paladin" then return {"might", "magic"} end
    return nil
end

function C.LicenseTier(token)
    local _, _, n = string.find(string.upper(C.Trim(token)), "^T(%d)")
    return tonumber(n) or 0
end

function C.BuildLicenseOptions(dungeonLicense, raidLicense)
    local result = {"t0d"}
    local dungeon = {"t1d", "t2d", "t3d", "t4d", "t5d"}
    local raid = {"t1r", "t2r", "t3r", "t4r", "t5r"}
    local d = C.LicenseTier(dungeonLicense)
    local r = C.LicenseTier(raidLicense)
    if d > 5 then d = 5 end
    if r > 5 then r = 5 end
    for i = 1, d do table.insert(result, dungeon[i]) end
    for i = 1, r do table.insert(result, raid[i]) end
    return result
end

function C.CharacterCanHire(record)
    if type(record) ~= "table" then return false end
    if C.Trim(record.name) == "" then return false end
    if record.level and record.level > 0 and record.level < 60 then return false end
    if record.maxCount and record.count and record.count >= record.maxCount then return false end
    return true
end

function C.ParseInviteList(payload)
    local result = {}
    local seen = {}
    local function add(name, class, dlic, rlic, team, mask, level, count, maxCount)
        if seen[name] then return end
        seen[name] = true
        local faction = nil
        if team == "A" then faction = "Alliance" elseif team == "H" then faction = "Horde" end
        table.insert(result, {
            name = name,
            class = string.lower(class or ""),
            dungeonLicense = string.lower(dlic or "none"),
            raidLicense = string.lower(rlic or "none"),
            faction = faction,
            level = tonumber(level),
            count = tonumber(count),
            maxCount = tonumber(maxCount),
        })
    end
    local text = payload or ""
    for name, class, dlic, rlic, team, mask, level, count, maxCount, legacyHired in string.gfind(text, "(%a+):(%a+):(%w+):(%w+):(%a):(%w+):(%d+):(%d+):(%d+):(%d)") do
        add(name, class, dlic, rlic, team, mask, level, count, maxCount)
    end
    if table.getn(result) == 0 then
        for name, class, dlic, rlic, team, mask, level, count, maxCount in string.gfind(text, "(%a+):(%a+):(%w+):(%w+):(%a):(%w+):(%d+):(%d+):(%d+)") do
            add(name, class, dlic, rlic, team, mask, level, count, maxCount)
        end
    end
    if table.getn(result) == 0 then
        for name, class, dlic, rlic, team, mask in string.gfind(text, "(%a+):(%a+):(%w+):(%w+):(%a):(%w+)") do
            add(name, class, dlic, rlic, team, mask)
        end
    end
    if table.getn(result) == 0 then
        for name, class, dlic, rlic in string.gfind(text, "(%a+):(%a+):(%w+):(%w+)") do
            add(name, class, dlic, rlic)
        end
    end
    return result
end

function C.ExtractInviteListPayload(raw)
    local text = C.Trim(raw)
    local _, stop, payload = string.find(text, "ACINFO:INVITE:LIST%s+(.+)$")
    if payload then return C.Trim(payload) end
    return nil
end

function C.IsHireCommand(entry)
    if type(entry) ~= "table" then return false end
    return entry.kind == "normal" or entry.kind == "hire"
end

function C.IsWhisperCommand(entry)
    if type(entry) ~= "table" then return false end
    return entry.chatType == "WHISPER" and C.Trim(entry.target) ~= ""
end

function C.IsNodAck(emoteName, emoteText, expectedName)
    local want = string.lower(C.Trim(expectedName))
    if want == "" then return false end
    local who = string.lower(C.Trim(emoteName))
    local text = string.lower(C.Trim(emoteText))
    if not string.find(text, "nods at you", 1, true) then return false end
    if who ~= "" then return who == want end
    return string.sub(text, 1, string.len(want)) == want
end

function C.IsBlacklistAck(sender, message, expectedName)
    local want = string.lower(C.Trim(expectedName))
    if want == "" then return false end
    if string.lower(C.Trim(sender)) ~= want then return false end
    return string.find(string.lower(C.Trim(message)), "i have blacklisted", 1, true) ~= nil
end

function C.RaidSlotGroup(index)
    if not index or index < 1 then return nil end
    return math.floor((index - 1) / 5) + 1
end

function C.RememberRaidAssignment(map, name, group, slot)
    local value = C.Trim(name)
    if value == "" or not group then return end
    if slot then map[value] = {group=group, slot=slot} else map[value] = group end
end

function C.BuildRaidAssignments(entries, companions)
    local map = {}
    if type(entries) ~= "table" then return map end
    for i = 1, table.getn(entries) do
        local entry = entries[i]
        if C.IsFilledEntry(entry) then
            local group = C.RaidSlotGroup(i)
            if entry.kind == "player" then
                C.RememberRaidAssignment(map, entry.charName, group, i)
            else
                if type(companions) == "table" then C.RememberRaidAssignment(map, companions[i], group, i) end
                C.RememberRaidAssignment(map, entry.account, group, i)
                C.RememberRaidAssignment(map, entry.charName, group, i)
                C.RememberRaidAssignment(map, entry.sourceName, group, i)
                C.RememberRaidAssignment(map, C.GetLegacyHireName(entry), group, i)
                C.RememberRaidAssignment(map, C.GetLegacyWhisperName(entry), group, i)
            end
        end
    end
    return map
end

function C.AssignmentForName(map, name)
    local value = C.Trim(name)
    if value == "" or type(map) ~= "table" then return nil end
    if map[value] then
        if type(map[value]) == "table" then return map[value].group end
        return map[value]
    end
    local lower = string.lower(value)
    local key, assigned
    for key, assigned in pairs(map) do
        if type(key) == "string" and string.lower(key) == lower then
            if type(assigned) == "table" then return assigned.group end
            return assigned
        end
    end
    return nil
end

function C.SlotAssignmentForName(map, name)
    local value = C.Trim(name)
    if value == "" or type(map) ~= "table" then return nil end
    local assigned = map[value]
    if type(assigned) == "table" then return assigned.slot end
    local lower = string.lower(value)
    local key
    for key, assigned in pairs(map) do
        if type(key) == "string" and string.lower(key) == lower and type(assigned) == "table" then return assigned.slot end
    end
    return nil
end

function C.AssignDetectedCompanions(queue, detected, names)
    local assigned = 0
    if type(queue) ~= "table" or type(detected) ~= "table" or type(names) ~= "table" then return 0 end
    local used = {}
    local key, value
    for key, value in pairs(detected) do
        if value and value ~= "" then used[value] = true end
    end
    local nameIndex = 1
    local i
    for i = 1, table.getn(queue) do
        local hire = queue[i]
        if hire and hire.kind == "normal" and hire.sourceEntryIndex then
            local existing = detected[hire.sourceEntryIndex]
            if not existing or existing == "" then
                while nameIndex <= table.getn(names) and (not names[nameIndex] or names[nameIndex] == "" or used[names[nameIndex]]) do
                    nameIndex = nameIndex + 1
                end
                if nameIndex > table.getn(names) then return assigned end
                detected[hire.sourceEntryIndex] = names[nameIndex]
                used[names[nameIndex]] = true
                assigned = assigned + 1
                nameIndex = nameIndex + 1
            end
        end
    end
    return assigned
end

function C.PlanRaidMoves(roster, assignments)
    local moves = {}
    if type(roster) ~= "table" or type(assignments) ~= "table" then return moves end
    for i = 1, table.getn(roster) do
        local row = roster[i]
        if row and row.name then
            local want = C.AssignmentForName(assignments, row.name)
            if want and want ~= row.group then
                table.insert(moves, {name = row.name, group = want})
            end
        end
    end
    return moves
end

function C.PlanRaidOrderSwaps(roster, assignments, ignoredGroups)
    local swaps = {}
    if type(roster) ~= "table" or type(assignments) ~= "table" then return swaps end
    local desired = {}
    local current = {}
    local name, assigned
    for name, assigned in pairs(assignments) do
        if type(name) == "string" and type(assigned) == "table" and assigned.group and assigned.slot then
            if type(desired[assigned.group]) ~= "table" then desired[assigned.group] = {} end
            table.insert(desired[assigned.group], {name=name, slot=assigned.slot})
        end
    end
    local group
    for group = 1, 8 do
        if type(desired[group]) == "table" then table.sort(desired[group], function(a, b) return a.slot < b.slot end) end
        current[group] = {}
    end
    local i
    for i = 1, table.getn(roster) do
        local row = roster[i]
        if row and row.name and row.group and current[row.group] then table.insert(current[row.group], row) end
    end
    for group = 1, 8 do
        if not (type(ignoredGroups) == "table" and ignoredGroups[group]) then
            local want = desired[group] or {}
            local have = current[group] or {}
            local ordinal
            for ordinal = 1, table.getn(want) do
                local occupant = have[ordinal]
                if occupant and string.lower(C.Trim(occupant.name)) ~= string.lower(C.Trim(want[ordinal].name)) then
                    local other = nil
                    for i = ordinal + 1, table.getn(have) do
                        if string.lower(C.Trim(have[i].name)) == string.lower(C.Trim(want[ordinal].name)) then other = have[i]; break end
                    end
                    if other then
                        table.insert(swaps, {name=want[ordinal].name, other=occupant.name, index=other.index, otherIndex=occupant.index, group=group, slot=want[ordinal].slot, ordinal=ordinal})
                        return swaps
                    end
                end
            end
        end
    end
    return swaps
end

function C.RaidOrderSignature(roster)
    if type(roster) ~= "table" then return "" end
    local parts = {}
    local i
    for i = 1, table.getn(roster) do
        local row = roster[i]
        if row and row.name and row.group then table.insert(parts, tostring(row.group) .. ":" .. string.lower(C.Trim(row.name))) end
    end
    return table.concat(parts, "|")
end

function C.PlanRaidOrderRebuild(roster, assignments, ignoredGroups)
    local operations = {}
    local swaps = C.PlanRaidOrderSwaps(roster, assignments, ignoredGroups)
    if table.getn(swaps) == 0 then return operations, nil end
    local targetGroup = swaps[1].group
    local current = {}
    local currentCounts = {0,0,0,0,0,0,0,0}
    local desiredCounts = {0,0,0,0,0,0,0,0}
    local desired = {}
    local desiredSet = {}
    local i
    for i = 1, table.getn(roster) do
        local row = roster[i]
        if row and row.name and row.group and currentCounts[row.group] then
            currentCounts[row.group] = currentCounts[row.group] + 1
            if row.group == targetGroup then table.insert(current, row.name) end
        end
    end
    local name, assigned
    for name, assigned in pairs(assignments) do
        if type(name) == "string" and type(assigned) == "table" and assigned.group and assigned.slot then
            desiredCounts[assigned.group] = (desiredCounts[assigned.group] or 0) + 1
            if assigned.group == targetGroup then table.insert(desired, {name=name, slot=assigned.slot}) end
        end
    end
    table.sort(desired, function(a, b) return a.slot < b.slot end)
    local buffer = nil
    local group
    for group = 8, 1, -1 do
        if group ~= targetGroup and (currentCounts[group] or 0) == 0 and (desiredCounts[group] or 0) == 0 then buffer = group; break end
    end
    if not buffer then return operations, "no-buffer" end
    for i = 1, table.getn(current) do table.insert(operations, {name=current[i], group=buffer, phase="stage"}) end
    for i = 1, table.getn(desired) do
        desiredSet[string.lower(C.Trim(desired[i].name))] = true
        table.insert(operations, {name=desired[i].name, group=targetGroup, phase="restore", slot=desired[i].slot})
    end
    for i = 1, table.getn(current) do
        if not desiredSet[string.lower(C.Trim(current[i]))] then table.insert(operations, {name=current[i], group=targetGroup, phase="restore-extra"}) end
    end
    return operations, nil
end

function C.BuildLiveRaidAssignments(entries, companions, roster, info, playerName)
    local map = {}
    if type(entries) ~= "table" then return map end
    local used = {}
    local slotName = {}
    local function take(name)
        local key = string.lower(C.Trim(name))
        if key == "" or used[key] then return false end
        used[key] = true
        return true
    end
    local function assignSlot(index, name, group, save)
        if not take(name) then return false end
        slotName[index] = name
        C.RememberRaidAssignment(map, name, group, index)
        if save and entries[index] and (entries[index].kind == "normal" or entries[index].kind == "guest") then
            entries[index].companionName = C.Trim(name)
        end
        return true
    end
    local i
    for i = 1, table.getn(entries) do
        local entry = entries[i]
        if C.IsFilledEntry(entry) then
            local group = C.RaidSlotGroup(i)
            if entry.kind == "player" then
                local you = C.Trim(playerName)
                if you ~= "" then assignSlot(i, you, group, false)
                else assignSlot(i, entry.charName, group, false) end
            else
                local done = false
                if type(companions) == "table" and C.Trim(companions[i]) ~= "" then
                    if (not roster) or table.getn(roster) == 0 or C.NameInRoster(roster, companions[i]) then
                        done = assignSlot(i, companions[i], group, true)
                    end
                end
                if (not done) and entry.kind == "legacy" then
                    if (not roster) or table.getn(roster) == 0 or C.NameInRoster(roster, C.GetLegacyWhisperName(entry)) then
                        done = assignSlot(i, C.GetLegacyWhisperName(entry), group, false)
                    end
                    if (not done) and ((not roster) or table.getn(roster) == 0 or C.NameInRoster(roster, C.GetLegacyHireName(entry))) then
                        done = assignSlot(i, C.GetLegacyHireName(entry), group, false)
                    end
                    if (not done) and ((not roster) or table.getn(roster) == 0 or C.NameInRoster(roster, entry.charName)) then
                        assignSlot(i, entry.charName, group, false)
                    end
                end
            end
        end
    end
    if type(info) == "table" then
        for i = 1, table.getn(entries) do
            local entry = entries[i]
            if C.IsFilledEntry(entry) and (not slotName[i]) and entry.kind ~= "player" and entry.kind ~= "legacy" then
                local group = C.RaidSlotGroup(i)
                local j
                for j = 1, table.getn(info) do
                    local rec = info[j]
                    if rec and C.Trim(rec.name) ~= "" and (not used[string.lower(C.Trim(rec.name))]) then
                        local classOk = C.NormalizeClassLabel(rec.class) == C.NormalizeClassLabel(entry.class)
                        local roleOk = C.NormalizeRoleLabel(rec.role) == C.NormalizeRoleLabel(entry.role)
                        local wantOwner = string.lower(C.Trim(entry.account))
                        local owner = string.lower(C.Trim(rec.owner))
                        local ownerOk = wantOwner == "" or owner == wantOwner
                        if classOk and roleOk and ownerOk then
                            if assignSlot(i, rec.name, group, true) then break end
                        end
                    end
                end
            end
        end
    end
    for i = 1, table.getn(entries) do
        local entry = entries[i]
        if C.IsFilledEntry(entry) and (not slotName[i]) and C.NameInRoster(roster, entry.companionName) then
            assignSlot(i, entry.companionName, C.RaidSlotGroup(i), false)
        end
    end
    if type(roster) == "table" then
        for i = 1, table.getn(entries) do
            local entry = entries[i]
            if C.IsFilledEntry(entry) and (not slotName[i]) then
                local wantClass = C.NormalizeClassLabel(entry.class)
                local hits = {}
                local r
                for r = 1, table.getn(roster) do
                    local row = roster[r]
                    if row and C.Trim(row.name) ~= "" and (not used[string.lower(C.Trim(row.name))]) then
                        if C.NormalizeClassLabel(row.class) == wantClass then table.insert(hits, row.name) end
                    end
                end
                if table.getn(hits) == 1 then assignSlot(i, hits[1], C.RaidSlotGroup(i), true) end
            end
        end
    end
    return map
end

function C.NameInRoster(roster, name)
    local want = string.lower(C.Trim(name))
    if want == "" or type(roster) ~= "table" then return false end
    local i
    for i = 1, table.getn(roster) do
        if roster[i] and string.lower(C.Trim(roster[i].name)) == want then return true end
    end
    return false
end

function C.BlankPreset()
    return {entries={}, denyRules={}, setupRules={}}
end

function C.EnsureProfileBanks(db)
    if type(db) ~= "table" then return db end
    if type(db.presets) ~= "table" then db.presets = {} end
    if C.Trim(db.currentPreset) == "" then db.currentPreset = "Default" end
    if type(db.presets[db.currentPreset]) ~= "table" then db.presets[db.currentPreset] = C.BlankPreset() end
    if type(db.sortPresets) ~= "table" then db.sortPresets = {} end
    if C.Trim(db.currentSortPreset) == "" then db.currentSortPreset = "Default" end
    if type(db.sortPresets[db.currentSortPreset]) ~= "table" then db.sortPresets[db.currentSortPreset] = C.BlankPreset() end
    return db
end

function C.CaptureWarningKey(character, realm)
    local name = string.lower(C.Trim(character))
    if name == "" then return "" end
    local realmName = string.lower(C.Trim(realm))
    if realmName == "" then return name end
    return realmName .. ":" .. name
end

function C.ShouldShowCaptureWarning(db, character, realm)
    if type(db) ~= "table" then return true end
    local key = C.CaptureWarningKey(character, realm)
    if key == "" then return true end
    if type(db.captureWarningHidden) ~= "table" then return true end
    return db.captureWarningHidden[key] ~= true
end

function C.SetCaptureWarningHidden(db, character, realm, hidden)
    if type(db) ~= "table" then return false end
    local key = C.CaptureWarningKey(character, realm)
    if key == "" then return false end
    if type(db.captureWarningHidden) ~= "table" then db.captureWarningHidden = {} end
    if hidden == true then db.captureWarningHidden[key] = true else db.captureWarningHidden[key] = nil end
    return true
end

function C.PresetBank(db, mode)
    C.EnsureProfileBanks(db)
    if mode == "sort" then return db.sortPresets, db.currentSortPreset end
    return db.presets, db.currentPreset
end

function C.ActivePreset(db, mode)
    local bank, name = C.PresetBank(db, mode)
    return bank[name]
end

function C.CopyPreset(src)
    local out = C.BlankPreset()
    if type(src) ~= "table" then return out end
    local i
    if type(src.entries) == "table" then
        for i = 1, table.getn(src.entries) do out.entries[i] = src.entries[i] end
    end
    if type(src.denyRules) == "table" then
        for i = 1, table.getn(src.denyRules) do out.denyRules[i] = src.denyRules[i] end
    end
    if type(src.setupRules) == "table" then
        for i = 1, table.getn(src.setupRules) do out.setupRules[i] = src.setupRules[i] end
    end
    out.sortLayout = src.sortLayout
    return out
end

function C.LegacyHireStub(realName)
    local name = C.Trim(realName)
    if name == "" then return "" end
    if string.len(name) > 7 then return string.sub(name, 1, 7) end
    return name
end

function C.IsLegacyHireStub(name, realNames)
    local stub = string.lower(C.Trim(name))
    if stub == "" or type(realNames) ~= "table" then return false end
    local i
    for i = 1, table.getn(realNames) do
        if string.lower(C.Trim(realNames[i])) == stub then return false end
    end
    for i = 1, table.getn(realNames) do
        local real = C.Trim(realNames[i])
        if string.lower(C.LegacyHireStub(real)) == stub and string.lower(real) ~= stub then return true end
    end
    return false
end

function C.LayoutLabel(entry)
    if type(entry) ~= "table" or entry.kind == "empty" then return "" end
    if entry.kind == "player" then
        if C.Trim(entry.charName) ~= "" then return entry.charName end
        return "You"
    end
    if entry.kind == "legacy" then
        local whisper = C.GetLegacyWhisperName(entry)
        if whisper ~= "" then return whisper end
        return C.Trim(entry.charName)
    end
    if C.Trim(entry.account) ~= "" then return C.Trim(entry.account) end
    if C.Trim(entry.companionName) ~= "" then return C.Trim(entry.companionName) end
    return C.Trim(entry.charName)
end

function C.HireCountName(entry)
    if type(entry) ~= "table" then return nil end
    if entry.kind ~= "normal" then return nil end
    local name = C.Trim(entry.account)
    if name == "" then return nil end
    return name
end

function C.NormalHireCountForCharacter(entries, character)
    if type(entries) ~= "table" then return 0 end
    local want = string.lower(C.Trim(character))
    if want == "" then return 0 end
    local count = 0
    local i
    for i = 1, table.getn(entries) do
        local entry = entries[i]
        if entry and entry.kind == "normal" and string.lower(C.Trim(entry.account)) == want then
            count = count + 1
        end
    end
    return count
end

function C.CanAddNormalHire(entries, character, limit)
    local name = C.Trim(character)
    if name == "" then return false end
    local maximum = tonumber(limit) or 4
    if maximum < 1 then return false end
    return C.NormalHireCountForCharacter(entries, name) < maximum
end

function C.TryAddNormalHire(entries, entry, limit, size)
    if type(entries) ~= "table" or type(entry) ~= "table" then return nil, "invalid-entry" end
    local account = C.Trim(entry.account)
    if account == "" then return nil, "invalid-character" end
    if not C.CanAddNormalHire(entries, account, limit) then return nil, "character-limit" end
    local slot = C.FirstEmptySlot(entries, size or 40)
    if not slot then return nil, "raid-full" end
    entry.kind = "normal"
    entry.account = account
    entries[slot] = entry
    return slot, nil
end

function C.ResolveLegacyHireName(entry, realNames)
    local raw = C.GetLegacyHireName(entry)
    if raw == "" then return "" end
    if type(realNames) ~= "table" then realNames = C.knownCharacterNames end
    if type(realNames) ~= "table" then return raw end
    local i
    for i = 1, table.getn(realNames) do
        if string.lower(C.Trim(realNames[i])) == string.lower(raw) then return C.Trim(realNames[i]) end
    end
    for i = 1, table.getn(realNames) do
        local real = C.Trim(realNames[i])
        if string.lower(C.LegacyHireStub(real)) == string.lower(raw) then return real end
    end
    return raw
end

function C.HireSlotCount(entries)
    if type(entries) ~= "table" then return 0 end
    local n = 0
    local i
    for i = 1, table.getn(entries) do
        local entry = entries[i]
        if entry and (entry.kind == "normal" or entry.kind == "legacy") then n = n + 1 end
    end
    return n
end

function C.IsCapturedHirePreset(preset)
    if type(preset) ~= "table" then return false end
    if preset.sortLayout then return true end
    if type(preset.entries) ~= "table" then return false end
    local guests = 0
    local normals = 0
    local i
    for i = 1, table.getn(preset.entries) do
        local entry = preset.entries[i]
        if entry and entry.kind == "guest" then guests = guests + 1 end
        if entry and entry.kind == "normal" then normals = normals + 1 end
    end
    return guests > 0 and normals == 0
end

function C.RescueHirePreset(db)
    C.EnsureProfileBanks(db)
    local hire = C.ActivePreset(db, "hire")
    if not C.IsCapturedHirePreset(hire) then return nil end
    local name = "Captured Raid"
    local n = 2
    while db.sortPresets[name] do
        name = "Captured Raid " .. n
        n = n + 1
        if n > 20 then break end
    end
    db.sortPresets[name] = hire
    db.sortPresets[name].sortLayout = true
    db.presets[db.currentPreset] = C.BlankPreset()
    if type(db.presets.ZG) == "table" then db.currentPreset = "ZG" end
    return name
end

function C.FindCompanionByName(info, name)
    if type(info) ~= "table" then return nil end
    local want = string.lower(C.Trim(name))
    if want == "" then return nil end
    local i
    for i = 1, table.getn(info) do
        local rec = info[i]
        if rec and string.lower(C.Trim(rec.name)) == want then return rec end
    end
    return nil
end

function C.LiveMemberEntry(row, info, playerName)
    if type(row) ~= "table" then return {kind="empty"} end
    local name = C.Trim(row.name)
    if name == "" then return {kind="empty"} end
    local class = C.NormalizeClassLabel(row.class)
    local rec = C.FindCompanionByName(info, name)
    local role = rec and rec.role or C.DefaultRoleForClass(class)
    local owner = rec and C.Trim(rec.owner) or ""
    if string.lower(name) == string.lower(C.Trim(playerName)) then
        return {kind="player", charName=name, class=class, role=role}
    end
    if string.sub(string.lower(name), -5) == "-lite" then
        return {
            kind="legacy",
            charName=name,
            sourceName=C.GetLegacyHireName({charName=name}),
            class=class,
            role=role,
            whisperName=name,
        }
    end
    return {kind="guest", companionName=name, charName=name, account=owner, class=class, role=role}
end

function C.CaptureRaidLayout(roster, info, playerName)
    local entries = C.PadRaidSlots({}, 40)
    local counts = {0,0,0,0,0,0,0,0}
    if type(roster) ~= "table" then return entries end
    local i
    for i = 1, table.getn(roster) do
        local row = roster[i]
        local group = row and tonumber(row.group) or 0
        if group >= 1 and group <= 8 and C.Trim(row.name) ~= "" then
            counts[group] = counts[group] + 1
            if counts[group] <= 5 then
                local index = (group - 1) * 5 + counts[group]
                entries[index] = C.LiveMemberEntry(row, info, playerName)
            end
        end
    end
    return C.RepairRaidEntries(entries)
end

function C.BuildWhisperQueue(preset)
    local full = C.BuildQueue(preset)
    local out = {}
    local i
    for i = 1, table.getn(full) do
        if not C.IsHireCommand(full[i]) then table.insert(out, full[i]) end
    end
    return out
end
