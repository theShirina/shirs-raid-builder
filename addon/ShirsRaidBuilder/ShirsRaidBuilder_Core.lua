-- Shir's Raid Builder core
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

-- Deny-list editors show five rows. The scrollbar appears at five or more
-- items so a full page never sits under a dead thumb.
C.DENY_LIST_VISIBLE_ROWS = 5

function C.DenyListNeedsScrollbar(count)
    return (tonumber(count) or 0) >= C.DENY_LIST_VISIBLE_ROWS
end

function C.DenyListMaxOffset(count, visible)
    visible = tonumber(visible) or C.DENY_LIST_VISIBLE_ROWS
    local total = tonumber(count) or 0
    if total <= visible then return 0 end
    return total - visible
end

function C.ClampDenyListOffset(offset, count, visible)
    local maxOffset = C.DenyListMaxOffset(count, visible)
    offset = math.floor(tonumber(offset) or 0)
    if offset < 0 then return 0 end
    if offset > maxOffset then return maxOffset end
    return offset
end

function C.DenyListThumb(offset, count, trackHeight, visible)
    trackHeight = tonumber(trackHeight) or 0
    visible = tonumber(visible) or C.DENY_LIST_VISIBLE_ROWS
    local total = tonumber(count) or 0
    if trackHeight <= 0 or total < visible then
        return 0, 0
    end
    local thumb = math.floor(trackHeight * visible / total)
    if thumb < 16 then thumb = 16 end
    if thumb > trackHeight then thumb = trackHeight end
    local maxOffset = C.DenyListMaxOffset(total, visible)
    local travel = trackHeight - thumb
    local y = 0
    if maxOffset > 0 then
        y = -math.floor((C.ClampDenyListOffset(offset, total, visible) / maxOffset) * travel + 0.5)
    end
    return thumb, y
end

function C.DenyListOffsetFromThumb(thumbY, count, trackHeight, visible)
    visible = tonumber(visible) or C.DENY_LIST_VISIBLE_ROWS
    local total = tonumber(count) or 0
    local maxOffset = C.DenyListMaxOffset(total, visible)
    if maxOffset <= 0 then return 0 end
    local thumb, _ = C.DenyListThumb(0, total, trackHeight, visible)
    local travel = (tonumber(trackHeight) or 0) - thumb
    if travel <= 0 then return 0 end
    local y = -(tonumber(thumbY) or 0)
    if y < 0 then y = 0 end
    if y > travel then y = travel end
    return C.ClampDenyListOffset(math.floor((y / travel) * maxOffset + 0.5), total, visible)
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

-- Deny-rule targeting resolves from the editor dropdowns at click time.
-- Matching accepts an all-roles wildcard; lookup is exact so adding to a
-- Tank/Warrior rule never folds into an all-roles Warrior rule.
function C.DenyRuleMatches(rule, role, class)
    local ruleRole = string.lower(C.Trim(rule.role or ""))
    return string.lower(C.Trim(rule.class or "")) == string.lower(class)
        and (ruleRole == string.lower(role) or ruleRole == "all")
end

function C.FindDenyRule(rules, role, class)
    local wantRole = string.lower(C.Trim(role or ""))
    local wantClass = string.lower(C.Trim(class or ""))
    for i = 1, table.getn(rules or {}) do
        local rule = rules[i]
        if type(rule) == "table"
            and string.lower(C.Trim(rule.class or "")) == wantClass
            and string.lower(C.Trim(rule.role or "")) == wantRole then
            return rule
        end
    end
    return nil
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

-- Microbot's deny parser accepts one prefix and comma-separated spell arguments.
-- Only known targets within one deny phase may share a message. Keep uncertain
-- argument syntax verbatim and separate; no escaping contract exists for it.
function C.BatchDenyQueue(items)
    local result, block, targets = {}, {}, {}
    local phase = nil
    local function flush()
        for i = 1, table.getn(block) do table.insert(result, block[i]) end
        block, targets, phase = {}, {}, nil
    end
    for i = 1, table.getn(items or {}) do
        local item = items[i]
        local ability = item.ability
        local safe = item.kind == "deny" and item.chatType == "WHISPER"
            and type(item.target) == "string" and item.target ~= ""
            and type(ability) == "string" and ability ~= ""
            and string.find(ability, "^[A-Za-z0-9 '()%-]+$") ~= nil
            and item.command == "deny add " .. ability
            and string.len(item.command) <= 255
        if not safe then
            flush()
            table.insert(result, item)
        else
            if phase ~= item.phase then flush() end
            phase = item.phase
            local previous = targets[item.target]
            if previous and string.len(previous.command) + 2 + string.len(ability) <= 255 then
                previous.command = previous.command .. ", " .. ability
            else
                local copy = {}
                for key, value in pairs(item) do copy[key] = value end
                table.insert(block, copy)
                targets[item.target] = copy
            end
        end
    end
    flush()
    return result
end

function C.DenyQueueError(items)
    for i = 1, table.getn(items or {}) do
        local item = items[i]
        if item.kind == "deny" and type(item.command) == "string" and string.len(item.command) > 255 then
            return "Deny command for " .. (C.Trim(item.target) ~= "" and item.target or "group") .. " exceeds 255 bytes. Nothing more was sent."
        end
    end
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

function C.ParseGrinfoResponse(text)
    local source = C.Trim(text)
    local _, _, payload = string.find(source, "^%[nexus%]%s+GRINFO:ALL:FULL%s*(.*)$")
    if payload == nil then
        _, _, payload = string.find(source, "^GRINFO:ALL:FULL%s*(.*)$")
    end
    if payload == nil then return nil, false end
    if C.Trim(payload) == "" then return {}, true end
    local companions = C.ParseCompanionInfo(payload)
    if table.getn(companions) == 0 then return nil, false end
    return companions, true
end

function C.HasOtherGroupMembers(snapshot, playerName)
    if type(snapshot) ~= "table" then return false end
    local me = string.lower(C.Trim(playerName))
    local name
    for name in pairs(snapshot) do
        if string.lower(C.Trim(name)) ~= me then return true end
    end
    return false
end

function C.InfoCoversGroup(snapshot, playerName, info)
    if type(snapshot) ~= "table" or type(info) ~= "table" then return false end
    local me = string.lower(C.Trim(playerName))
    local present = {}
    local otherCount = 0
    local name
    for name in pairs(snapshot) do
        local lower = string.lower(C.Trim(name))
        if lower ~= "" and lower ~= me then
            present[lower] = true
            otherCount = otherCount + 1
        end
    end
    if otherCount == 0 then return false end
    local covered = {}
    local coveredCount = 0
    for i = 1, table.getn(info) do
        local lower = string.lower(C.Trim(info[i] and info[i].name))
        if present[lower] and not covered[lower] then
            covered[lower] = true
            coveredCount = coveredCount + 1
        end
    end
    return coveredCount == otherCount
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

function C.BuildGrowlCommand(policy)
    local value = string.lower(C.Trim(policy))
    if value == "" or value == "(none)" or value == "unchanged" then return nil end
    if value == "deny" then return "deny add growl" end
    if value == "allow" then return "deny remove growl" end
    return nil
end

function C.BuildDrinkCommand(percentage)
    if percentage == nil then return nil end
    local value = tostring(percentage)
    if value == "" or value == "(none)" or string.lower(value) == "unchanged" then return nil end
    if not string.find(value, "^%d+$") then return nil end
    local number = tonumber(value)
    if not number or number < 1 or number > 100 then return nil end
    return "set drink " .. value
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

-- How many of the entries' legacy companions (by their whisper name) present does not list.
function C.MissingLegacyNames(entries, present)
    local missing = 0
    for name in pairs(C.LegacyNameSet(entries)) do
        if not (type(present) == "table" and present[name]) then missing = missing + 1 end
    end
    return missing
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

function C.MatchCompanionsScoped(companions, class, role, spec)
    local wantClass = C.NormalizeClassLabel(class)
    local wantRole = C.NormalizeRoleLabel(role)
    local wantSpec = string.lower(C.Trim(spec))
    local result = {}
    if type(companions) ~= "table" or wantClass == "" then return result end
    local anyRole = wantRole == "" or wantRole == "all"
    local anySpec = wantSpec == "" or wantSpec == "all"
    for i = 1, table.getn(companions) do
        local companion = companions[i]
        if companion.class == wantClass and C.Trim(companion.name) ~= "" then
            if (anyRole or companion.role == wantRole)
                and (anySpec or string.lower(C.Trim(companion.spec)) == wantSpec) then
                table.insert(result, companion.name)
            end
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
        -- GRINFO has no specialization field. Do not turn a stored
        -- spec-specific rule into a class/role-wide command.
        if spec ~= "all" then
            spec = nil
        end
        local commands = {}
        if spec == "all" and class == "shaman" then
            table.insert(commands, C.BuildTotemCommand(rule.earth))
            table.insert(commands, C.BuildTotemCommand(rule.fire))
            table.insert(commands, C.BuildTotemCommand(rule.water))
            table.insert(commands, C.BuildTotemCommand(rule.air))
        elseif spec == "all" and class == "paladin" then
            table.insert(commands, C.BuildAuraCommand(rule.aura))
        elseif spec == "all" and class == "hunter" then
            table.insert(commands, C.BuildAspectCommand(rule.aspect))
            table.insert(commands, C.BuildPetCommand(rule.pet))
            table.insert(commands, C.BuildGrowlCommand(rule.growl))
        elseif spec == "all" and class == "warlock" then
            table.insert(commands, C.BuildPetCommand(rule.pet))
        elseif spec == "all" and class == "mage" then
            table.insert(commands, C.BuildMagicCommand(rule.magic))
            table.insert(commands, C.BuildDrinkCommand(rule.drink))
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
        local names = C.MatchCompanionsScoped(companions, item.class or item.role and item.class, item.role, item.spec)
        if item.phase == "role-class-final" or (item.role and item.class and item.ability) then
            names = C.MatchCompanionsScoped(companions, item.class, item.role, item.spec)
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

-- GRINFO lists hired companions only. Legacy board characters never appear in
-- it, so group commands must add them from the preset itself. Only members the
-- live group still shows (their whisper name sits in presentSet) are appended,
-- after every server record, so companions keep their head-start ordering.
function C.AppendLegacyGroupMembers(companions, entries, presentSet)
    local result = {}
    local seen = {}
    local i
    if type(companions) == "table" then
        for i = 1, table.getn(companions) do
            local companion = companions[i]
            if type(companion) == "table" and companion.name and C.Trim(companion.name) ~= "" then
                table.insert(result, companion)
                seen[string.lower(C.Trim(companion.name))] = true
            end
        end
    end
    if type(entries) ~= "table" or type(presentSet) ~= "table" then return result end
    for i = 1, table.getn(entries) do
        local entry = entries[i]
        if type(entry) == "table" and entry.kind == "legacy" then
            local name = C.GetLegacyWhisperName(entry)
            if name ~= "" and presentSet[name] and not seen[string.lower(name)] then
                table.insert(result, {
                    name = name,
                    class = C.NormalizeClassLabel(entry.class or ""),
                    role = C.NormalizeRoleLabel(entry.role or ""),
                })
            end
        end
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
    return C.BatchDenyQueue(result)
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
            local individual = C.BuildClassSetupPlan(entry.setupRules)
            for si = 1, table.getn(individual) do
                local item = individual[si]
                if item.class == C.NormalizeClassLabel(entry.class) and target ~= "" then
                    item.phase = "legacy-setup"
                    item.character = C.Trim(entry.charName)
                    item.sourceEntryIndex = i
                    item.target = target
                    table.insert(queue, item)
                end
            end
        end
    end
    for i = 1, table.getn(lateWhispers) do table.insert(queue, lateWhispers[i]) end
    return C.BatchDenyQueue(queue)
end

function C.NormalHireMatchesInfo(entry, record)
    if type(entry) ~= "table" or entry.kind ~= "normal" or type(record) ~= "table" then return false end
    local wantedName = C.Trim(entry.companionName)
    local recordName = C.Trim(record.name)
    if C.Trim(entry.account)=="" or string.lower(C.Trim(entry.account))~=string.lower(C.Trim(record.owner)) then return false end
    if wantedName ~= "" and string.lower(wantedName) == string.lower(recordName) then return true end
    if C.Trim(entry.account) == "" or C.Trim(entry.class) == "" or C.Trim(entry.role) == "" then return false end
    return string.lower(C.Trim(entry.account)) == string.lower(C.Trim(record.owner))
        and C.NormalizeClassLabel(entry.class) == C.NormalizeClassLabel(record.class)
        and C.NormalizeRoleLabel(entry.role) == C.NormalizeRoleLabel(record.role)
end

function C.FilterExistingNormalHires(queue, entries, info)
    local result = {}
    local used = {}
    local skipped = 0
    if type(queue) ~= "table" then return result, skipped end
    for i = 1, table.getn(queue) do
        local item = queue[i]
        local omit = false
        if item and item.kind == "normal" and type(entries) == "table" and type(info) == "table" then
            local entry = entries[item.sourceEntryIndex]
            for ri = 1, table.getn(info) do
                if not used[ri] and C.NormalHireMatchesInfo(entry, info[ri]) then
                    used[ri] = true
                    omit = true
                    skipped = skipped + 1
                    break
                end
            end
        end
        if not omit then table.insert(result, item) end
    end
    return result, skipped
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

function C.RememberLegacyCharacter(db, name, class, role)
    if type(db) ~= "table" or type(name) ~= "string" or type(class) ~= "string" then return end
    local key = string.lower(C.Trim(name))
    class = C.ClassKeyFromLabel(class)
    if not C.IsSafeCharacterName(key) or string.find(key, "-", 1, true) then return end
    if not C.RoleAllowedForClass(class, C.DefaultRoleForClass(class)) then return end
    if type(db.legacyCharacters) ~= "table" then db.legacyCharacters = {} end
    db.legacyCharacters[key] = class
    if type(role) == "string" and role == C.NormalizeRoleLabel(role) and C.RoleAllowedForClass(class, role) then
        if type(db.legacyCharacterRoles) ~= "table" then db.legacyCharacterRoles = {} end
        db.legacyCharacterRoles[key] = role
    end
end

function C.LegacyCharacterRole(db, name, class)
    if type(db) ~= "table" or type(name) ~= "string" or type(class) ~= "string" then return nil end
    local key = string.lower(C.Trim(name))
    if not C.IsSafeCharacterName(key) then return nil end
    local role
    if type(db.legacyCharacterRoles) == "table" then role = db.legacyCharacterRoles[key] end
    if role ~= nil then
        if type(role) == "string" and role == C.NormalizeRoleLabel(role) and C.RoleAllowedForClass(class, role) then return role end
        return nil
    end
    -- Older saves have the role only in their legacy composition entries.
    local found
    for _, preset in pairs(type(db.presets) == "table" and db.presets or {}) do
        local entries = type(preset) == "table" and preset.entries or nil
        for _, entry in pairs(type(entries) == "table" and entries or {}) do
            if type(entry) == "table" and entry.kind == "legacy" and string.lower(C.GetLegacyHireName(entry)) == key then
                role = entry.role
                if type(entry.class) ~= "string" or C.ClassKeyFromLabel(entry.class) ~= class or type(role) ~= "string" or role ~= C.NormalizeRoleLabel(role) or not C.RoleAllowedForClass(class, role) then return nil end
                if found and found ~= role then return nil end
                found = role
            end
        end
    end
    return found
end

function C.StoreLegacyCharacterList(db, message)
    if type(message) ~= "string" then return false end
    local _, _, payload = string.find(message, "^%[nexus%] ACINFO:LEGACY:LIST (.*)$")
    if not payload then return false end
    for record in string.gfind(payload, "%S+") do
        local _, _, name, class = string.find(record, "^(%a+):(%a+):[01]$")
        if name then C.RememberLegacyCharacter(db, name, class) end
    end
    return true
end

function C.LegacyCharacterClass(db, name)
    if type(db) ~= "table" or type(name) ~= "string" then return nil end
    local key = string.lower(C.Trim(name))
    if not C.IsSafeCharacterName(key) then return nil end
    local cached = type(db.legacyCharacters) == "table" and db.legacyCharacters[key] or nil
    if type(cached) == "string" and C.RoleAllowedForClass(cached, C.DefaultRoleForClass(cached)) then return cached end
    local records = type(db.inviteCharacters) == "table" and db.inviteCharacters or {}
    for savedName, record in pairs(records) do
        if type(savedName) == "string" and string.lower(savedName) == key and type(record) == "table" then
            local class = type(record.class) == "string" and C.ClassKeyFromLabel(record.class) or ""
            if C.RoleAllowedForClass(class, C.DefaultRoleForClass(class)) then return class end
        end
    end
    local found
    for _, preset in pairs(type(db.presets) == "table" and db.presets or {}) do
        local entries = type(preset) == "table" and preset.entries or nil
        for _, entry in pairs(type(entries) == "table" and entries or {}) do
            if type(entry) == "table" and entry.kind == "legacy" and string.lower(C.GetLegacyHireName(entry)) == key then
                local class = type(entry.class) == "string" and C.ClassKeyFromLabel(entry.class) or ""
                if C.RoleAllowedForClass(class, C.DefaultRoleForClass(class)) then
                    if found and found ~= class then return nil end
                    found = class
                end
            end
        end
    end
    if found then return found end
    return nil
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

-- A licence tier as the sidebar writes it: t5r -> T5R, t1d -> T1D; the base tier reads
-- T0 whether saved as t0 or t0d. Anything else: "".
function C.TierLabel(tier)
    if type(tier) ~= "string" or not string.find(tier, "^t%d[rd]?$") then return "" end
    if tier == "t0d" then return "T0" end
    return string.upper(tier)
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

function C.KnownFaction(faction)
    if faction == "Alliance" or faction == "Horde" then return faction end
end

-- What `read` finds about a hire-from character, or nil: from this account's server list
-- or its own rows, else from the newest trusted linked snapshot where `read` finds it.
function C.HireFromRead(db, you, realm, name, read)
    local key = string.lower(C.Trim(name))
    if type(db) ~= "table" or key == "" then return nil end
    for n, record in pairs(type(db.inviteCharacters) == "table" and db.inviteCharacters or {}) do
        if type(n) == "string" and string.lower(n) == key and type(record) == "table" and read(record) then return read(record) end
    end
    local rows = type(db.localAccountRows) == "table" and db.localAccountRows[realm]
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if type(r) == "table" and string.lower(C.Trim(r.name)) == key and read(r) then return read(r) end
    end
    local best, when
    for k, snapshot in pairs(type(db.peerSnapshots) == "table" and db.peerSnapshots or {}) do
        local copy = C.AccountSavedCopy(snapshot, you, realm, db.peerLinks)
        if copy and k == realm .. ";" .. string.lower(copy.source) and (not when or copy.received > when) then
            for _, r in ipairs(copy.entries) do
                if string.lower(r.name) == key and read(r) then best, when = read(r), copy.received end
            end
        end
    end
    return best
end

-- A hire-from character's licences, or nil while they are unknown.
function C.HireFromLicenses(db, you, realm, name)
    return C.HireFromRead(db, you, realm, name, function(r)
        local raid, dungeon = string.lower(C.Trim(r.raidLicense)), string.lower(C.Trim(r.dungeonLicense))
        if (raid == "none" or string.find(raid, "^t[0-5]r$")) and (dungeon == "none" or string.find(dungeon, "^t[0-5]d$")) then
            return {raidLicense = raid, dungeonLicense = dungeon}
        end
    end)
end

-- A hire-from character's faction, as the server told this account or a linked one; nil
-- while it is unknown.
function C.HireFromFaction(db, you, realm, name)
    return C.HireFromRead(db, you, realm, name, function(r) return C.KnownFaction(r.faction) end)
end

-- The tiers a hire-from character holds, base tier first and its highest last; nil while
-- its licences are unknown.
function C.HireFromTiers(db, you, realm, name)
    local licences = C.HireFromLicenses(db, you, realm, name)
    if licences then return C.BuildLicenseOptions(licences.dungeonLicense, licences.raidLicense) end
end

-- A tier for a character holding these tiers: kept when it holds it (the base tier always
-- counts), else its highest.
function C.FitTier(tier, tiers)
    if type(tiers) ~= "table" or table.getn(tiers) == 0 or tier == "t0" or tier == "t0d" then return tier end
    for _, held in ipairs(tiers) do if held == tier then return tier end end
    return tiers[table.getn(tiers)]
end

-- Read LazyTrix's confirmed snapshot only, never its synthetic Ready/schedule rows.
function C.GetConfirmedSavedRaidLabels(lazyDB, realm, character, now)
    if type(realm) ~= "string" or C.Trim(realm) == "" or type(character) ~= "string" or C.Trim(character) == "" then return "" end
    if type(now) ~= "number" or not (now > 0 and now <= 4102444800) then return "" end
    if type(lazyDB) ~= "table" or type(lazyDB.cooldownsByCharacter) ~= "table" then return "" end
    local state = lazyDB.cooldownsByCharacter[realm .. string.char(31) .. character]
    if type(state) ~= "table" or type(state.raidInfo) ~= "table" then return "" end
    local info = state.raidInfo
    if info.known ~= true or type(info.instances) ~= "table" then return "" end
    return C.SavedRaidLabels(info.instances, now)
end

function C.SavedRaidLabels(entries, now)
    if type(entries) ~= "table" or type(now) ~= "number" or not (now > 0 and now <= 4102444800) then return "" end
    local aliases = {
        ["molten core"] = "MC", ["blackwing lair"] = "BWL",
        ["temple of ahn'qiraj"] = "AQ40", ["ahn'qiraj temple"] = "AQ40",
        ["ahn'qiraj"] = "AQ40", ["aq40"] = "AQ40", ["naxxramas"] = "NAXX",
    }
    local found = {}
    for _, entry in ipairs(entries) do
        if type(entry) == "table" and not entry.ready and not entry.scheduled and type(entry.name) == "string"
            and type(entry.readyAt) == "number" and (entry.readyAt == 1 or entry.readyAt > now) and entry.readyAt <= 4102444800 + 31622400 then
            local label = aliases[string.lower(C.Trim(entry.name))]
            if label then found[label] = true end
        end
    end
    local labels = {}
    for _, label in ipairs({"MC", "BWL", "AQ40", "NAXX"}) do
        if found[label] then table.insert(labels, label) end
    end
    return table.concat(labels, " ")
end

function C.CurrentLicenseTier(record)
    if type(record) ~= "table" then return nil end
    if type(record.raidLicense) ~= "string" or type(record.dungeonLicense) ~= "string" then return nil end
    local raid = string.upper(C.Trim(record.raidLicense))
    local dungeon = string.upper(C.Trim(record.dungeonLicense))
    if dungeon == "NONE" then
        dungeon = "T0D"
    end
    if not string.find(raid, "^T[0-5]R?$") or not string.find(dungeon, "^T[0-5]D?$") then return nil end
    return raid .. " - " .. dungeon
end

function C.SortInviteNamesByRaidLicense(names, records)
    table.sort(names, function(a, b)
        local aRecord = type(records) == "table" and records[a]
        local bRecord = type(records) == "table" and records[b]
        local aTier = aRecord and C.LicenseTier(aRecord.raidLicense) or -1
        local bTier = bRecord and C.LicenseTier(bRecord.raidLicense) or -1
        if aTier ~= bTier then return aTier > bTier end
        return a < b
    end)
    return names
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

-- Import owns its nested data; the existing Save flow keeps its own semantics.
local function CopyImportValue(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do out[key] = CopyImportValue(item, seen) end
    return out
end

function C.ImportPreset(db, mode, source, destination)
    if type(db) ~= "table" or (mode ~= "hire" and mode ~= "sort") then return false end
    local bank = mode == "sort" and db.sortPresets or db.presets
    local current = mode == "sort" and db.currentSortPreset or db.currentPreset
    if type(bank) ~= "table" or current ~= destination or source == destination then return false end
    if type(bank[source]) ~= "table" or type(bank[destination]) ~= "table" then return false end
    bank[destination] = CopyImportValue(C.CopyPreset(bank[source]))
    return true
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
    for i = 1, 40 do
        local entry = entries[i]
        if type(entry) == "table" and entry.kind == "normal" and string.lower(C.Trim(entry.account)) == want then
            count = count + 1
        end
    end
    return count
end

-- Returns the first character (trimmed, first-seen casing) with more than `limit` normal hires, else nil.
function C.OverLimitHireCharacter(entries, limit)
    if type(entries) ~= "table" then return nil end
    local maximum = tonumber(limit) or 4
    local counts, names = {}, {}
    local i
    for i = 1, 40 do
        local name = C.HireCountName(entries[i])
        if name then
            local key = string.lower(name)
            counts[key] = (counts[key] or 0) + 1
            names[key] = names[key] or name
            if counts[key] > maximum then return names[key] end
        end
    end
    return nil
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
    -- Only the explicit marker counts. Heuristics on entry shapes are unsafe:
    -- a legitimate hire board with legacy cards plus another player's companion
    -- (a guest) has the same shape as a captured raid, so guessing here used to
    -- wipe real hire plans on every relog (moved them to the sort bank).
    return type(preset) == "table" and preset.sortLayout == true
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

-- Raid composition wire format: fixed fields only, never Lua or settings.
C.PLAN_FIELDS={"kind","account","charName","sourceName","companionName","class","role","spec","tier","race","gender"}

function C.PlanParts(text,separator)
    local out={}; local first=1
    while true do
        local at=string.find(text,separator,first,true)
        if not at then table.insert(out,string.sub(text,first)); return out end
        table.insert(out,string.sub(text,first,at-1)); first=at+1
    end
end

function C.PlanName(name)
    return type(name)=="string" and string.len(name)>=1 and string.len(name)<=48
        and name==C.Trim(name) and string.find(name,"^[A-Za-z0-9 _'-]+$")~=nil
end

function C.PlanEntry(entry)
    if type(entry)~="table" then return nil end
    local kinds={normal=true,legacy=true,guest=true,player=true,empty=true}
    if not kinds[entry.kind] then return nil end
    local out={}
    for _,key in ipairs(C.PLAN_FIELDS) do
        local value=entry[key]
        if value~=nil and value~="" then
            if type(value)~="string" or string.len(value)>24 or not string.find(value,"^[A-Za-z0-9%-]+$") then return nil end
            out[key]=value
        end
    end
    if out.kind=="empty" then return {kind="empty"} end
    if out.kind=="normal" and not C.IsSafeCharacterName(out.account) then return nil end
    if out.kind=="legacy" and not C.IsSafeCharacterName(out.sourceName or out.charName) then return nil end
    if out.class and not string.find(";warrior;paladin;hunter;rogue;priest;shaman;mage;warlock;druid;",";" .. out.class .. ";",1,true) then return nil end
    if out.role and not string.find(";tank;healer;mdps;rdps;",";" .. out.role .. ";",1,true) then return nil end
    return out
end

function C.PlanEncode(plan,mode,name)
    if type(plan)~="table" or type(plan.entries)~="table" or (mode~="hire" and mode~="sort") or not C.PlanName(name) then return nil end
    local maximum=0
    for key in pairs(plan.entries) do
        if type(key)~="number" or not (key>=1 and key<=40 and key==math.floor(key)) then return nil end
        maximum=math.max(maximum,key)
    end
    local rows={}
    for i=1,maximum do
        local entry=C.PlanEntry(plan.entries[i] or {kind="empty"})
        if not entry then return nil end
        local fields={}
        for _,key in ipairs(C.PLAN_FIELDS) do table.insert(fields,entry[key] or "_") end
        table.insert(rows,table.concat(fields,","))
    end
    local text=mode .. "~" .. name .. "~" .. table.concat(rows,"/")
    if string.len(text)<=6144 then return text end
end

function C.PlanDecode(text)
    if type(text)~="string" or string.len(text)>6144 then return nil end
    local parts=C.PlanParts(text,"~")
    if table.getn(parts)~=3 or not C.PlanName(parts[2]) or (parts[1]~="hire" and parts[1]~="sort") then return nil end
    local entries={}
    if parts[3]~="" then
        local rows=C.PlanParts(parts[3],"/")
        if table.getn(rows)>40 then return nil end
        for _,row in ipairs(rows) do
            local fields=C.PlanParts(row,","); local entry={}
            if table.getn(fields)~=table.getn(C.PLAN_FIELDS) then return nil end
            for i,key in ipairs(C.PLAN_FIELDS) do if fields[i]~="_" then entry[key]=fields[i] end end
            entry=C.PlanEntry(entry)
            if not entry then return nil end
            table.insert(entries,entry)
        end
    end
    local plan={name=parts[2],mode=parts[1],entries=entries}
    -- Require a canonical encoding; reject hidden or ignored fields.
    if C.PlanEncode(plan,plan.mode,plan.name)~=text then return nil end
    return plan
end

function C.PlanParse(text)
    if type(text)~="string" or string.len(text)>240 then return nil end
    local f=C.PlanParts(text,";")
    if table.getn(f)~=11 or f[1]~="SRBPLAN1" or not C.PeerNew(f[3],f[4],f[2])
        or not C.PeerNonce(f[5]) or not C.PeerNonce(f[6]) or not C.PeerNonce(f[7]) then return nil end
    for i=8,10 do
        if string.len(f[i])>10 or not string.find(f[i],"^[1-9][0-9]*$") then return nil end
    end
    local expiry,index,total=tonumber(f[8]),tonumber(f[9]),tonumber(f[10])
    if not (expiry<=2147483647 and total<=128 and index<=total) or string.len(f[11])<1 or string.len(f[11])>48
        or not string.find(f[11],"^[A-Za-z0-9 _',/~%-]+$") then return nil end
    return {realm=f[2],sender=string.lower(f[3]),target=string.lower(f[4]),a=f[5],b=f[6],nonce=f[7],expires=expiry,index=index,total=total,data=f[11]}
end

function C.PlanPackets(s,text,nonce,wall,clock)
    if not s or s.phase~="linked" or not C.PeerAlive(s,wall,clock) or not C.PeerNonce(nonce) or not C.PlanDecode(text) then return nil end
    local total=math.ceil(string.len(text)/48)
    if s.expires-wall<total*0.25+10 then return nil end
    local packets={}
    for i=1,total do
        local p=table.concat({"SRBPLAN1",s.realm,s.youLabel or s.you,s.peerLabel or s.peer,s.a,s.b,nonce,tostring(s.expires),tostring(i),tostring(total),string.sub(text,(i-1)*48+1,i*48)},";")
        if not C.PlanParse(p) then return nil end
        table.insert(packets,p)
    end
    return packets
end

function C.PlanAuthorized(s,links,wall,clock)
    return s and s.phase=="linked" and C.LinkKnown(links,s.you,s.peer,s.realm) and C.PeerAlive(s,wall,clock)
end

function C.PlanReceive(s,text,sender,links,wall,clock,handoff)
    local p=handoff and C.HandParse(text) or C.PlanParse(text)
    if not p or not C.PlanAuthorized(s,links,wall,clock) or type(sender)~="string" or string.lower(sender)~=s.peer
        or p.sender~=s.peer or p.target~=s.you or p.realm~=s.realm or p.a~=s.a or p.b~=s.b or p.expires~=s.expires then return false end
    local seenKey=handoff and "handSeen" or "planSeen"
    local inputKey=handoff and "handInput" or "planInput"
    local proposalKey=handoff and "handProposal" or "planProposal"
    s[seenKey]=s[seenKey] or {}
    local input=s[inputKey]
    if not input then
        if p.index~=1 or s[seenKey][p.nonce] or s[proposalKey] then return false end
        local n=0; for _ in pairs(s[seenKey]) do n=n+1 end
        if n>=4 then return false end
        s[seenKey][p.nonce]=true
        input={nonce=p.nonce,total=p.total,next=1,parts={}}; s[inputKey]=input
    end
    if input.nonce~=p.nonce then return false end
    if p.index~=input.next or p.total~=input.total or (p.index<p.total and string.len(p.data)~=48) then
        s[inputKey]=nil; return false
    end
    table.insert(input.parts,p.data); input.next=input.next+1
    if p.index~=p.total then return false end
    s[inputKey]=nil
    local wire=table.concat(input.parts)
    -- A hand-off is a full message or a short one; HandTick rebuilds a short one.
    local plan
    if handoff then plan=C.HandDecode(wire) or C.HandShortParse(wire) else plan=C.PlanDecode(wire) end
    if not plan then return false end
    s[proposalKey]={wire=wire,plan=plan,nonce=p.nonce}
    return true
end

function C.PlanReject(s)
    if s then s.planInput=nil; s.planProposal=nil end
end

-- Local approval only. Copy never overwrites; merge preserves occupied slots
-- and relocates conflicts into free slots of a staged copy (atomic on failure).
-- No current-profile pointer, live board, settings or execution queue changes.
function C.PlanImport(db,s,links,destination,action,wall,clock)
    if type(db)~="table" then return false,"database" end
    if not C.PlanAuthorized(s,links,wall,clock) then return false,"unauthorized" end
    if not s.planProposal then return false,"proposal" end
    if not C.PlanName(destination) then return false,"destination" end
    if action~="copy" and action~="merge" then return false,"action" end
    local plan=C.PlanDecode(s.planProposal.wire)
    if not plan then return false,"invalid" end
    local bank=plan.mode=="sort" and db.sortPresets or db.presets
    if type(bank)~="table" then return false,"database" end
    local old=bank[destination]
    if action=="copy" and old~=nil then return false,"exists" end
    if action=="merge" and (type(old)~="table" or type(old.entries)~="table") then return false,"missing" end
    local out=action=="merge" and CopyImportValue(old) or C.BlankPreset()
    local function free(i) return not out.entries[i] or out.entries[i].kind=="empty" end
    local added,moved,conflicts=0,0,{}
    for i=1,40 do
        local entry=plan.entries[i]
        if entry and entry.kind~="empty" then
            if free(i) then out.entries[i]=entry; added=added+1
            else table.insert(conflicts,entry) end
        elseif entry and action=="copy" then out.entries[i]=entry end
    end
    local slot=1
    for _,entry in ipairs(conflicts) do
        while slot<=40 and not free(slot) do slot=slot+1 end
        if slot>40 then return false,"capacity" end
        out.entries[slot]=entry; added=added+1; moved=moved+1
    end
    if plan.mode=="sort" then out.sortLayout=true end
    bank[destination]=out
    s.planProposal=nil
    return true,{added=added,moved=moved}
end

-- Character/realm binding is local trust, not account authentication.
function C.PeerNew(you, peer, realm)
    if type(you) ~= "string" or type(peer) ~= "string" or type(realm) ~= "string" then return nil end
    if not C.IsSafeCharacterName(you) or not C.IsSafeCharacterName(peer) then return nil end
    if you ~= C.Trim(you) or peer ~= C.Trim(peer) then return nil end
    if string.len(realm) < 1 or string.len(realm) > 40 or realm ~= C.Trim(realm) then return nil end
    if not string.find(realm, "^[A-Za-z0-9 '-]+$") then return nil end
    if string.lower(you) == string.lower(peer) then return nil end
    return {you=string.lower(you), peer=string.lower(peer), youLabel=you, peerLabel=peer, realm=realm, phase="disabled"}
end

function C.PeerClear(s, reason)
    if not s then return end
    s.phase = "disabled"; s.reason = reason or "Cancelled locally"
    s.a = nil; s.b = nil; s.nonce = nil; s.expires = nil
    s.deadline = nil; s.started = nil; s.proposal = nil
    s.invitation = nil; s.retryAt = nil; s.retries = nil
    s.remoteLicense=nil; s.licenseWait=nil; s.licenseServe=nil; s.licenseOut=nil; s.licenseAfterLink=nil
    s.raidWait=nil; s.raidServe=nil; s.raidOut=nil
    s.planInput=nil; s.planProposal=nil; s.planOut=nil
    s.handInput=nil; s.handProposal=nil; s.handOut=nil
end

function C.PeerNonce(value)
    return type(value) == "string" and string.len(value) >= 6 and string.len(value) <= 32
        and string.find(value, "^[0-9]+$") ~= nil
end

function C.PeerArm(s, nonce, wall, clock)
    if not s or s.phase ~= "disabled" or not C.PeerNonce(nonce) then return false end
    -- Each live session gets its own bounded replay budget; old packets still fail a/b.
    s.planSeen={}; s.handSeen={}
    s.phase = "listening"; s.reason = nil; s.nonce = nonce
    s.expires = wall + 60; s.deadline = clock + 60; s.started = clock
    return true
end

function C.PeerAlive(s, wall, clock)
    if not s or s.phase == "disabled" then return false end
    if clock < s.started or clock >= s.deadline or wall >= s.expires then
        C.PeerClear(s, "Expired; peer availability unknown")
        return false
    end
    return true
end

-- Invitation v2: consent is separate from proof of a fresh addressed reply.
function C.LinkPacket(s, kind)
    local text = table.concat({"SRBLINK2", kind, s.realm, s.youLabel or s.you, s.peerLabel or s.peer, s.a or "-", s.b or "-", tostring(s.expires)}, ";")
    if string.len(text) <= 240 then return text end
end

function C.LinkParse(text)
    if type(text) ~= "string" or string.len(text) > 240 then return nil end
    local _, _, kind, realm, sender, target, a, b, expiry = string.find(text,
        "^SRBLINK2;([A-Z]+);([^;]+);([A-Za-z]+);([A-Za-z]+);([0-9]+);([0-9%-]+);([0-9]+)$")
    if not kind or not C.PeerNew(sender, target, realm) or not C.PeerNonce(a) then return nil end
    if b ~= "-" and not C.PeerNonce(b) then return nil end
    if string.len(expiry) > 10 or string.sub(expiry,1,1) == "0" then return nil end
    expiry = tonumber(expiry)
    if not expiry or not (expiry > 0 and expiry <= 2147483647) then return nil end
    if kind ~= "INVITE" and kind ~= "ACCEPT" and kind ~= "CONFIRM" and kind ~= "READY" and kind ~= "REJECT" then return nil end
    return {kind=kind, realm=realm, sender=string.lower(sender), target=string.lower(target), a=a, b=b, expires=expiry}
end

function C.LinkInvite(s, nonce, wall, clock)
    if not C.PeerArm(s, nonce, wall, clock) then return nil end
    s.a = nonce; s.phase = "waiting"
    return C.LinkPacket(s, "INVITE")
end

function C.LinkIncoming(text, sender, you, realm, nonce, wall, clock)
    local p = C.LinkParse(text)
    if not p or p.kind ~= "INVITE" or p.b ~= "-" or type(sender) ~= "string" or type(you) ~= "string" then return nil end
    if p.sender ~= string.lower(sender) or p.target ~= string.lower(you) or p.realm ~= realm then return nil end
    if p.expires <= wall or p.expires > wall + 60 or not C.PeerNonce(nonce) or nonce == p.a then return nil end
    local s = C.PeerNew(you, sender, realm)
    if not s then return nil end
    s.a=p.a; s.b=nonce; s.expires=p.expires; s.started=clock; s.deadline=clock+(p.expires-wall); s.phase="approval"
    return s
end

function C.LinkAccept(s, wall, clock)
    if not C.PeerAlive(s, wall, clock) or s.phase ~= "approval" then return nil end
    s.phase="confirming"
    return C.LinkPacket(s, "ACCEPT")
end

function C.LinkReject(s, wall, clock)
    if not C.PeerAlive(s, wall, clock) or s.phase ~= "approval" then return nil end
    s.b="-"
    local packet=C.LinkPacket(s, "REJECT")
    C.PeerClear(s, "Rejected locally")
    return packet
end

function C.LinkReceive(s, text, sender, wall, clock)
    if not C.PeerAlive(s, wall, clock) then return false end
    local p=C.LinkParse(text)
    if not p or type(sender) ~= "string" or string.lower(sender) ~= s.peer then return false end
    if p.sender ~= s.peer or p.target ~= s.you or p.realm ~= s.realm or p.a ~= s.a or p.expires ~= s.expires then return false end
    if p.kind == "REJECT" and s.phase == "waiting" and p.b == "-" then C.PeerClear(s, "Invitation rejected"); return true end
    if p.kind == "ACCEPT" and s.phase == "waiting" and p.b ~= "-" and p.b ~= s.a then
        s.b=p.b; s.phase="confirm-sent"; return C.LinkPacket(s, "CONFIRM")
    end
    if p.b ~= s.b then return false end
    if p.kind == "CONFIRM" and s.phase == "confirming" then s.phase="linked"; return C.LinkPacket(s, "READY") end
    if p.kind == "READY" and s.phase == "confirm-sent" then s.phase="linked"; return true end
    return false
end

function C.LinkKey(you, peer, realm, account)
    local s=C.PeerNew(you, peer, realm)
    if s then return s.realm .. ";" .. s.peer .. ";" .. (account and "*" or s.you) end
end

function C.LinkSave(db, s, account)
    if type(db) ~= "table" or not s or s.phase ~= "linked" then return false end
    local key=C.LinkKey(s.you, s.peer, s.realm, account)
    if not key then return false end
    local bindings={}
    if account and type(db[key]) == "table" and type(db[key].bindings) == "table" then
        for name,label in pairs(db[key].bindings) do
            local bound=C.PeerNew(label,s.peer,s.realm)
            if bound and bound.you == name then bindings[name]=label end
        end
    end
    bindings[s.you]=s.youLabel or s.you
    db[key]={version=2, realm=s.realm, peer=s.peer, peerLabel=s.peerLabel or s.peer,
        scope=account and "*" or s.you, bindings=bindings}
    local own=C.LinkKey(s.you,s.peer,s.realm,false)
    if account and type(db[own]) == "table" and db[own].revoked then db[own]=nil end
    return true
end

function C.LinkKnown(db, you, peer, realm)
    if type(db) ~= "table" then return false end
    local own=C.LinkKey(you,peer,realm,false)
    if own and type(db[own]) == "table" and db[own].revoked == true then return false end
    for _, account in ipairs({false,true}) do
        local key=C.LinkKey(you, peer, realm, account)
        local p=key and db[key]
        if type(p) == "table" and p.version == 2 and p.realm == realm and p.peer == string.lower(peer)
            and p.revoked ~= true and p.scope == (account and "*" or string.lower(you)) then return true end
    end
    return false
end

-- Advisory only; these fields never authorize an action.
function C.LicenseTokens(d,r)
    return type(d)=="string" and type(r)=="string"
        and (d=="unknown" or d=="none" or string.find(d,"^t[0-5]d$") ~= nil)
        and (r=="unknown" or r=="none" or string.find(r,"^t[1-5]r$") ~= nil)
end

function C.LicensePacket(s,kind,nonce,index,total,name,d,r,observed)
    if not s or not C.PeerNonce(nonce) then return nil end
    local text=table.concat({"SRBLIC2",kind,s.realm,s.youLabel or s.you,s.peerLabel or s.peer,s.a,s.b,nonce,tostring(index or 0),tostring(total or 0),name or "-",d or "-",r or "-",tostring(observed or 0)},";")
    if string.len(text)<=240 then return text end
end

function C.LicenseParse(text)
    if type(text)~="string" or string.len(text)>240 then return nil end
    local _,_,kind,realm,sender,target,a,b,nonce,index,total,name,d,r,observed=string.find(text,"^SRBLIC2;([A-Z]+);([^;]+);([A-Za-z]+);([A-Za-z]+);([0-9]+);([0-9]+);([0-9]+);(%d+);(%d+);([A-Za-z%-]+);([a-z0-9%-]+);([a-z0-9%-]+);(%d+)$")
    if not kind or not C.PeerNew(sender,target,realm) or not C.PeerNonce(a) or not C.PeerNonce(b) or not C.PeerNonce(nonce) then return nil end
    if string.len(index)>2 or string.len(total)>2 or string.len(observed)>10 then return nil end
    index=tonumber(index); total=tonumber(total); observed=tonumber(observed)
    if kind=="GET" or kind=="GETONCE" then if index~=0 or total~=0 or name~="-" or d~="-" or r~="-" or observed~=0 then return nil end
    elseif kind=="DATA" then
        if index<1 or total<1 or total>64 or index>total or not C.IsSafeCharacterName(name) or not C.LicenseTokens(d,r) or observed<=0 or observed>2147483647 then return nil end
    else return nil end
    return {kind=kind,realm=realm,sender=string.lower(sender),target=string.lower(target),a=a,b=b,nonce=nonce,index=index,total=total,name=name,d=d,r=r,observed=observed}
end

-- All-or-nothing, bounded account claims. Never truncate an oversized set.
function C.LicenseReadPayload(payload)
    if type(payload)~="string" or string.len(payload)>8192 then return nil end
    local records={}
    for token in string.gfind(payload,"%S+") do
        if not string.find(token,"^%a+:%a+:%w+:%w+$")
            and not string.find(token,"^%a+:%a+:%w+:%w+:%a:%w+$")
            and not string.find(token,"^%a+:%a+:%w+:%w+:%a:%w+:%d+:%d+:%d+$")
            and not string.find(token,"^%a+:%a+:%w+:%w+:%a:%w+:%d+:%d+:%d+:[01]$") then return nil end
        local parsed=C.ParseInviteList(token)
        if table.getn(parsed)~=1 then return nil end
        table.insert(records,parsed[1])
        if table.getn(records)>128 then return nil end
    end
    return records
end

function C.LicenseSnapshot(s,nonce,records,observed)
    if type(records)~="table" or table.getn(records)<1 or table.getn(records)>128 then return nil end
    local rows,seen={},{}
    for _,r in ipairs(records) do
        if type(r)~="table" or not C.IsSafeCharacterName(r.name) then return nil end
        r={name=r.name,dungeonLicense=C.LicenseTokens(r.dungeonLicense,"none") and r.dungeonLicense or "unknown",
            raidLicense=C.LicenseTokens("none",r.raidLicense) and r.raidLicense or "unknown"}
        local key=string.lower(r.name)
        if seen[key] then
            if seen[key].dungeonLicense~=r.dungeonLicense or seen[key].raidLicense~=r.raidLicense then return nil end
        else seen[key]=r; table.insert(rows,r) end
    end
    if table.getn(rows)>64 then return nil end
    table.sort(rows,function(a,b) return string.lower(a.name)<string.lower(b.name) end)
    local packets={}
    for i,r in ipairs(rows) do
        local p=C.LicensePacket(s,"DATA",nonce,i,table.getn(rows),r.name,r.dungeonLicense,r.raidLicense,observed)
        if not p or not C.LicenseParse(p) then return nil end
        table.insert(packets,p)
    end
    return packets
end

function C.LicenseFresh(r,clock)
    return r and clock>=r.clock and clock-r.clock<30
end

-- Saved advisory data uses wall time, never the short live-session clock.
function C.LicenseAgeLabel(r,now)
    if not r or type(now)~="number" or type(r.received)~="number" or not (r.received>0 and now>=r.received) then return "Age unavailable" end
    local age=math.floor(now-r.received)
    if age<60 then return "Received " .. age .. "s ago" end
    if age<3600 then return math.floor(age/60) .. "m ago; stale" end
    if age<86400 then return math.floor(age/3600) .. "h ago; stale" end
    return math.floor(age/86400) .. "d ago; stale"
end

function C.LicenseSavedCopy(r,you,realm,links)
    if type(r)~="table" or r.realm~=realm or type(r.source)~="string"
        or not C.LinkKnown(links,you,r.source,realm) or r.authoritative~=false
        or type(r.received)~="number" or r.received<=0 or r.received>2147483647
        or type(r.observed)~="number" or r.observed<=0 or r.observed>r.received
        or type(r.entries)~="table" then return nil end
    local entries,seen={},{}
    for i,e in pairs(r.entries) do
        if type(i)~="number" or i<1 or i>64 or i~=math.floor(i) or type(e)~="table"
            or not C.IsSafeCharacterName(e.name) or not C.LicenseTokens(e.dungeonLicense,e.raidLicense)
            or e.observed~=r.observed or type(e.received)~="number" or e.received<r.observed or e.received>r.received
            or e.authoritative~=false or seen[string.lower(e.name)] then return nil end
        seen[string.lower(e.name)]=true
        entries[i]={name=e.name,dungeonLicense=e.dungeonLicense,raidLicense=e.raidLicense,
            observed=e.observed,received=e.received,authoritative=false}
    end
    local count=0; for _ in pairs(entries) do count=count+1 end
    if count<1 then return nil end
    for i=1,count do if not entries[i] then return nil end end
    return {source=r.source,realm=realm,received=r.received,observed=r.observed,entries=entries,authoritative=false}
end

function C.CharacterLicenseRow(name,record,count,raids,source)
    raids=raids or ""
    local r=type(record)=="table" and record.raidLicense
    if type(r)=="string" then r=string.lower(r) end
    local tier=type(r)=="string" and string.find(r,"^t[0-5]r$") and string.upper(r) or nil
    local model={name=name,tier=tier,source=source,readOnly=source~=nil,
        title=name .. (tier and " - " .. tier or ""),raids=raids,
        height=20+(raids~="" and 14 or 0)}
    if type(count)=="number" then model.count=count; model.countText=count .. "/4" end
    return model
end

function C.LicenseBound(s,p,sender,wall,clock)
    return s and s.phase=="linked" and C.PeerAlive(s,wall,clock) and p and type(sender)=="string"
        and string.lower(sender)==s.peer and p.sender==s.peer and p.target==s.you
        and p.realm==s.realm and p.a==s.a and p.b==s.b
end

function C.LicenseRequest(s,nonce,clock,reply)
    if not s or s.phase~="linked" or not C.PeerNonce(nonce) or s.licenseWait then return nil end
    s.licenseWait={nonce=nonce,started=clock,entries={},names={},count=0}; s.remoteLicense=nil
    s.raidWait={nonce=nonce,started=clock,entries={},count=0}
    return C.LicensePacket(s,reply and "GETONCE" or "GET",nonce)
end

function C.LicenseReceive(s,text,sender,wall,clock)
    local p=C.LicenseParse(text)
    if not C.LicenseBound(s,p,sender,wall,clock) or p.kind~="DATA" then return false end
    local w=s.licenseWait
    if not w or w.nonce~=p.nonce or clock<w.started or clock-w.started>=45 then return false end
    if wall<p.observed or wall-p.observed>=30 then return false end
    if w.total and (w.total~=p.total or w.observed~=p.observed) then s.licenseWait=nil; return false end
    if w.entries[p.index] then
        local old=w.entries[p.index]
        if old.name~=p.name or old.dungeonLicense~=p.d or old.raidLicense~=p.r then s.licenseWait=nil end
        return false
    end
    if w.names[string.lower(p.name)] then s.licenseWait=nil; return false end
    w.total=p.total; w.observed=p.observed; w.names[string.lower(p.name)]=true
    w.entries[p.index]={name=p.name,dungeonLicense=p.d,raidLicense=p.r,observed=p.observed,received=wall,authoritative=false}
    w.count=w.count+1
    if w.count~=w.total then return false end
    s.licenseWait=nil
    s.remoteLicense={source=p.sender,realm=p.realm,entries=w.entries,observed=p.observed,received=wall,clock=clock-(wall-p.observed),authoritative=false}
    return true
end

function C.LicenseCurrent(records,you)
    local found
    for _,r in ipairs(records) do
        if type(r.name)=="string" and string.lower(r.name)==string.lower(you) then
            if found or not C.LicenseTokens(r.dungeonLicense,r.raidLicense) then return nil end
            found=r
        end
    end
    return found
end

function C.LinkForget(db, you, peer, realm, account)
    local key=C.LinkKey(you, peer, realm, account)
    if key and type(db) == "table" then
        db[key]=nil
        if account then
            for other,p in pairs(db) do
                if type(p)=="table" and p.realm==realm and p.peer==string.lower(peer) then db[other]=nil end
            end
        end
        if not account and db[C.LinkKey(you,peer,realm,true)] then
            db[key]={version=2,realm=realm,peer=string.lower(peer),scope=string.lower(you),revoked=true}
        end
    end
end

-- Read-only raid claims. No helper below sends commands or drives hiring.
function C.RaidNumber(n,lo,hi)
    return type(n)=="number" and n==n and n>=lo and n<=hi and n==math.floor(n)
end

function C.RaidName(n)
    return type(n)=="string" and string.len(n)>=1 and string.len(n)<=80
        and n==C.Trim(n) and string.find(n,"^[A-Za-z0-9 ',:%-%(%)]+$")~=nil
end

function C.RaidEntry(e,observed)
    if type(e)~="table" or not C.RaidName(e.name)
        or not C.RaidNumber(e.id,0,2147483647)
        or not (C.RaidNumber(e.readyAt,observed+1,math.min(2147483647,observed+31622400))
            or (C.RaidNumber(e.readyAt,1,1) and e.scheduled==false and C.RaidNumber(e.id,1,2147483647)))
        or type(e.scheduled)~="boolean" then return nil end
    if e.scheduled then
        if e.id~=0 or not C.RaidNumber(e.cycle,1,366) then return nil end
    elseif e.cycle~=nil and e.cycle~=0 then return nil end
    return {name=e.name,id=e.id,readyAt=e.readyAt,scheduled=e.scheduled,cycle=e.scheduled and e.cycle or nil}
end

function C.RaidCopySnapshot(r)
    if type(r)~="table" or type(r.known)~="boolean" or not C.RaidNumber(r.observed,1,2147483647)
        or type(r.entries)~="table" then return nil end
    local entries,seen,count={},{},0
    for i,e in pairs(r.entries) do
        if not C.RaidNumber(i,1,32) then return nil end
        local row=C.RaidEntry(e,r.observed)
        if not row or seen[string.lower(row.name)] then return nil end
        seen[string.lower(row.name)]=true; entries[i]=row; count=count+1
    end
    for i=1,count do if not entries[i] then return nil end end
    if not r.known and count>0 then return nil end
    return {known=r.known,entries=entries,observed=r.observed}
end

function C.RaidSnapshot(native,ccp,wall,clock)
    if not C.RaidNumber(wall,1,2147483647) or type(clock)~="number" or clock~=clock or clock<0 or clock>2147483647 then return nil end
    local out={known=type(native)=="table",entries={},observed=wall}
    if not out.known then return out end
    local seen={}
    local function add(e,scheduled,seconds)
        if type(e)~="table" or not C.RaidName(e.name) then return end
        local key=string.lower(e.name)
        if seen[key] then return end
        -- Even expired native rows prevent a schedule from replacing that raid.
        if not scheduled then seen[key]=true end
        if type(seconds)~="number" or seconds~=seconds or seconds<1 or seconds>31622400 then return end
        local row=C.RaidEntry({name=e.name,id=scheduled and 0 or e.id,readyAt=wall+math.floor(seconds),scheduled=scheduled,cycle=scheduled and e.cycle or nil},wall)
        if row then seen[key]=true; table.insert(out.entries,row) end
    end
    for _,e in pairs(native) do if type(e)=="table" then add(e,false,e.reset) end end
    if type(ccp)=="table" then
        if type(ccp.locks)=="table" then
            for _,e in pairs(ccp.locks) do if type(e)=="table" and type(e.resetAt)=="number" then add(e,false,e.resetAt-clock) end end
        end
        if type(ccp.sched)=="table" then
            for _,e in pairs(ccp.sched) do if type(e)=="table" and type(e.resetAt)=="number" then add(e,true,e.resetAt-clock) end end
        end
    end
    if table.getn(out.entries)>32 then out.known=false; out.entries={} end
    return out
end

function C.RaidSavedCopy(r)
    local out=C.RaidCopySnapshot(r)
    if not out or r.authoritative~=false or not C.IsSafeCharacterName(r.source)
        or not C.IsSafeCharacterName(r.character) or string.lower(r.character)~=string.lower(r.source)
        or type(r.realm)~="string" or string.len(r.realm)<1 or string.len(r.realm)>40
        or not string.find(r.realm,"^[A-Za-z0-9 '-]+$") or r.realm~=C.Trim(r.realm)
        or not C.RaidNumber(r.received,r.observed,2147483647) then return nil end
    out.source=r.source; out.character=r.character; out.realm=r.realm
    out.received=r.received; out.authoritative=false
    return out
end

-- DATA carries one row; EMPTY and UNKNOWN carry no row. All share the nonce.
function C.RaidParse(text)
    if type(text)~="string" or string.len(text)>240 then return nil end
    local fields={}
    for token in string.gfind(text..";","([^;]*);") do table.insert(fields,token) end
    if table.getn(fields)~=16 or fields[1]~="SRBRAID3" then return nil end
    local p={kind=fields[2],realm=fields[3],sender=string.lower(fields[4]),target=string.lower(fields[5]),a=fields[6],b=fields[7],nonce=fields[8]}
    if not C.PeerNew(fields[4],fields[5],p.realm) or not C.PeerNonce(p.a) or not C.PeerNonce(p.b) or not C.PeerNonce(p.nonce) then return nil end
    for _,i in ipairs({9,10,11,13,14,15,16}) do
        if string.len(fields[i])>10 or not string.find(fields[i],"^%d+$") then return nil end
        fields[i]=tonumber(fields[i])
    end
    p.index=fields[9]; p.total=fields[10]; p.observed=fields[11]
    if not C.RaidNumber(p.observed,1,2147483647) then return nil end
    if p.kind=="DATA" then
        if not C.RaidNumber(p.total,1,32) or not C.RaidNumber(p.index,1,p.total) or fields[15]>1 then return nil end
        p.entry=C.RaidEntry({name=fields[12],id=fields[13],readyAt=fields[14],scheduled=fields[15]==1,cycle=fields[16]},p.observed)
        if not p.entry then return nil end
    elseif p.kind=="EMPTY" or p.kind=="UNKNOWN" then
        if p.index~=0 or p.total~=0 or fields[12]~="-" or fields[13]~=0 or fields[14]~=0 or fields[15]~=0 or fields[16]~=0 then return nil end
    else return nil end
    return p
end

function C.RaidPackets(s,nonce,snapshot)
    local r=C.RaidCopySnapshot(snapshot)
    if not r or type(s)~="table" or not C.PeerNonce(nonce) or not C.PeerNonce(s.a) or not C.PeerNonce(s.b)
        or not C.PeerNew(s.youLabel or s.you,s.peerLabel or s.peer,s.realm) then return nil end
    local packets={}
    local total=table.getn(r.entries)
    for i=1,math.max(total,1) do
        local e=r.entries[i]
        local kind=e and "DATA" or (r.known and "EMPTY" or "UNKNOWN")
        local p=table.concat({"SRBRAID3",kind,s.realm,s.youLabel or s.you,s.peerLabel or s.peer,s.a,s.b,nonce,
            tostring(e and i or 0),tostring(total),tostring(r.observed),e and e.name or "-",tostring(e and e.id or 0),
            tostring(e and e.readyAt or 0),e and e.scheduled and "1" or "0",tostring(e and e.cycle or 0)},";")
        if not C.RaidParse(p) then return nil end
        table.insert(packets,p)
    end
    return packets
end

function C.RaidReceive(s,text,sender,wall,clock)
    if not C.RaidNumber(wall,1,2147483647) or type(clock)~="number" or clock~=clock or clock<0 or clock>2147483647 then return false end
    local p=C.RaidParse(text)
    if not p or not C.LicenseBound(s,p,sender,wall,clock) then return false end
    local w=s.raidWait
    if not w or w.nonce~=p.nonce or type(w.started)~="number" or clock<w.started or clock-w.started>=45
        or wall<p.observed or wall-p.observed>=30 then return false end
    if w.total and (w.total~=p.total or w.observed~=p.observed or w.kind~=p.kind) then s.raidWait=nil; return false end
    if p.entry then
        if w.entries[p.index] then
            local old=w.entries[p.index]
            if old.name~=p.entry.name or old.id~=p.entry.id or old.readyAt~=p.entry.readyAt or old.scheduled~=p.entry.scheduled or old.cycle~=p.entry.cycle then s.raidWait=nil end
            return false
        end
        for _,e in pairs(w.entries) do if string.lower(e.name)==string.lower(p.entry.name) then s.raidWait=nil; return false end end
        w.entries[p.index]=p.entry; w.count=w.count+1
    end
    w.total=p.total; w.observed=p.observed; w.kind=p.kind
    if w.count~=p.total then return false end
    local out=C.RaidSavedCopy({source=p.sender,character=s.peerLabel or s.peer,realm=p.realm,entries=w.entries,
        known=p.kind~="UNKNOWN",received=wall,observed=p.observed,authoritative=false})
    s.raidWait=nil
    if not out then return false end
    s.remoteRaids=out
    return true
end

-- Account-wide advisory rows. Unknown levels never imply level 60. A row names its
-- character's faction when the account knows it.
function C.AccountRowCopy(e)
    if type(e)~="table" or not C.IsSafeCharacterName(e.name) or e.level~=60
        or not C.LicenseTokens(e.dungeonLicense,e.raidLicense)
        or not C.RaidNumber(e.observed,1,2147483647) then return nil end
    local out={name=e.name,level=60,dungeonLicense=e.dungeonLicense,raidLicense=e.raidLicense,observed=e.observed,faction=C.KnownFaction(e.faction)}
    if e.raidObserved~=nil then
        if not C.RaidNumber(e.raidObserved,1,2147483647) or type(e.saves)~="table" then return nil end
        out.raidObserved=e.raidObserved; out.saves={}
        for i=1,4 do
            local n=e.saves[i]
            if not C.RaidNumber(n,0,2147483647) or (n~=0 and n~=1 and not (n>e.raidObserved and n<=e.raidObserved+31622400)) then return nil end
            out.saves[i]=n
        end
    end
    return out
end

function C.AccountCollect(records,now)
    local rows={}
    if type(records)~="table" or not C.RaidNumber(now,1,2147483647) then return rows end
    for _,e in pairs(records) do
        if type(e)=="table" and e.level==60 then
            local row=C.AccountRowCopy({name=e.name,level=60,observed=now,faction=e.faction,
                dungeonLicense=C.LicenseTokens(e.dungeonLicense,"none") and e.dungeonLicense or "unknown",
                raidLicense=C.LicenseTokens("none",e.raidLicense) and e.raidLicense or "unknown"})
            if row then table.insert(rows,row) end
        end
    end
    return C.AccountMerge({},rows)
end

function C.AccountMerge(old,new)
    local byName={}
    for _,list in ipairs({old or {},new or {}}) do
        for _,e in pairs(list) do
            local row=C.AccountRowCopy(e)
            if row then
                local key=string.lower(row.name); local previous=byName[key]
                if previous then
                    local raid,older=row,previous
                    if (previous.raidObserved or 0)>(row.raidObserved or 0) then raid=previous end
                    if previous.observed>row.observed then row,older=previous,row end
                    -- "unknown" carries no information, so it never hides a licence another
                    -- observation of the same character knows; a real newer value still wins.
                    if row.dungeonLicense=="unknown" then row.dungeonLicense=older.dungeonLicense end
                    if row.raidLicense=="unknown" then row.raidLicense=older.raidLicense end
                    row.faction=row.faction or older.faction
                    row.raidObserved=raid.raidObserved; row.saves=raid.saves
                end
                byName[key]=row
            end
        end
    end
    local rows={}; for _,e in pairs(byName) do table.insert(rows,e) end
    table.sort(rows,function(a,b) return string.lower(a.name)<string.lower(b.name) end)
    return rows
end

-- MCP's schedule is not a save. Convert only real locks, using receipt clocks.
-- readyAt=1 is an explicit saved/unknown-reset marker, never a reset countdown.
function C.MCPLockSnapshot(locks,wall,up)
    local out={known=false,observed=wall,entries={}}
    if type(locks)~="table" or not C.RaidNumber(wall,1,2147483647)
        or type(up)~="number" or not (up>=0 and up<=2147483647) or table.getn(locks)>32 then return out end
    local names={[409]="Molten Core",[469]="Blackwing Lair",[531]="Ahn'Qiraj Temple",[533]="Naxxramas"}
    local count=0
    for key in pairs(locks) do
        if not C.RaidNumber(key,1,32) then return out end
        count=count+1
    end
    for i=1,count do if not locks[i] then return out end end
    for _,lock in ipairs(locks) do
        if type(lock)~="table" or not C.RaidNumber(lock.map,1,2147483647) then return out end
        local name=names[lock.map]
        if name then
            if not C.RaidNumber(lock.id,1,2147483647) then return out end
            if lock.resetAt==nil then
                table.insert(out.entries,{name=name,id=lock.id,readyAt=1,scheduled=false})
            elseif type(lock.resetAt)~="number" or not (lock.resetAt>=0 and lock.resetAt<=2147483647) then return out
            elseif lock.resetAt>up then
                local delta=lock.resetAt-up
                if not (delta>=1 and delta<=31622400 and wall+delta<=2147483647) then return out end
                table.insert(out.entries,{name=name,id=lock.id,readyAt=math.floor(wall+delta),scheduled=false})
            end
        end
    end
    out.known=true
    return out
end

function C.AccountSetRaids(row,info,now)
    if type(info)~="table" or info.known~=true or type(info.instances)~="table"
        or not C.RaidNumber(info.observedAt,1,now) then return end
    local saves={0,0,0,0}
    local labels={MC=1,BWL=2,AQ40=3,NAXX=4}
    for _,e in ipairs(info.instances) do
        local label=C.SavedRaidLabels({e},now)
        local index=labels[label]
        if index and (C.RaidNumber(e.readyAt,1,1) or C.RaidNumber(e.readyAt,info.observedAt+1,math.min(2147483647,info.observedAt+31622400))) then
            saves[index]=math.max(saves[index],e.readyAt)
        end
    end
    if info.observedAt>=(row.raidObserved or 0) then row.raidObserved=info.observedAt; row.saves=saves end
end

function C.AccountRaidLabels(row,now)
    if not C.RaidNumber(now,1,2147483647) then return "" end
    local labels={}; local names={"MC","BWL","AQ40","NAXX"}
    row=C.AccountRowCopy(row)
    if row and row.saves then
        for i,n in ipairs(row.saves) do if n==1 or n>now then table.insert(labels,names[i]) end end
    end
    return table.concat(labels," ")
end

-- Raid tiers descend; no raid license follows T1R, unknown/missing last.
-- Sort a copy so display order never changes the stored observations.
function C.AccountLicenseOrder(entries)
    local rows={}
    for _,entry in ipairs(entries or {}) do table.insert(rows,entry) end
    table.sort(rows,function(a,b)
        local ranks={t5r=5,t4r=4,t3r=3,t2r=2,t1r=1,none=0}
        local ar=ranks[string.lower(a.raidLicense or "")] or -1
        local br=ranks[string.lower(b.raidLicense or "")] or -1
        if ar~=br then return ar>br end
        local an=string.lower(a.name or ""); local bn=string.lower(b.name or "")
        if an~=bn then return an<bn end
        local ak=string.lower(a.realm or ""); local bk=string.lower(b.realm or "")
        if ak~=bk then return ak<bk end
        return (a.name or "") .. ";" .. (a.realm or "") < (b.name or "") .. ";" .. (b.realm or "")
    end)
    return rows
end

function C.AccountIdentity(id)
    return C.PeerNonce(id) and string.len(id)>=16
end

-- Header, level-60 row, and compact saved-raid row share the fresh link/GET nonce.
-- The opaque ID groups approved peer claims; it is not server account proof.
function C.AccountParse(text)
    if type(text)~="string" or string.len(text)>240 then return nil end
    local f={}; for value in string.gfind(text..";","([^;]*);") do table.insert(f,value) end
    if f[1]~="SRBACC4" or (table.getn(f)~=11 and table.getn(f)~=14 and not (f[2]=="ROW" and table.getn(f)==15))
        or not C.PeerNew(f[4],f[5],f[3]) or not C.PeerNonce(f[6]) or not C.PeerNonce(f[7]) or not C.PeerNonce(f[8]) then return nil end
    local p={kind=f[2],realm=f[3],sender=string.lower(f[4]),target=string.lower(f[5]),a=f[6],b=f[7],nonce=f[8]}
    local function number(i,lo,hi)
        if string.len(f[i])>10 or not string.find(f[i],"^%d+$") then return nil end
        local n=tonumber(f[i]); if C.RaidNumber(n,lo,hi) then return n end
    end
    if p.kind=="HEAD" and table.getn(f)==11 then
        p.accountId=f[9]; p.total=number(10,0,64); p.observed=number(11,1,2147483647)
        if not C.AccountIdentity(p.accountId) or not p.total or not p.observed then return nil end
    elseif p.kind=="ROW" and table.getn(f)>=14 then
        -- A 15th field is the faction, A or H; rows from older builds end at 14.
        local sides={A="Alliance",H="Horde"}
        if f[15] and not sides[f[15]] then return nil end
        p.index=number(9,1,64)
        p.row=C.AccountRowCopy({name=f[10],level=number(11,60,60),dungeonLicense=f[12],raidLicense=f[13],observed=number(14,1,2147483647),faction=f[15] and sides[f[15]]})
        if not p.index or not p.row then return nil end
    elseif p.kind=="SAVE" and table.getn(f)==14 then
        p.index=number(9,1,64); p.observed=number(10,0,2147483647); p.saves={}
        if not p.index or not p.observed then return nil end
        for i=1,4 do
            local n=number(i+10,0,2147483647)
            if not n or (p.observed==0 and n~=0) or (n~=0 and n~=1 and not (n>p.observed and n<=p.observed+31622400)) then return nil end
            p.saves[i]=n
        end
    else return nil end
    return p
end

function C.AccountPackets(s,nonce,id,rows,now)
    if not s or not C.AccountIdentity(id) or type(rows)~="table" or table.getn(rows)>64 then return nil end
    local packets={}; local prefix={"SRBACC4","",s.realm,s.youLabel or s.you,s.peerLabel or s.peer,s.a,s.b,nonce}
    local function add(kind,fields)
        prefix[2]=kind
        local packet=table.concat(prefix,";") .. ";" .. table.concat(fields,";")
        if not C.AccountParse(packet) then return false end
        table.insert(packets,packet); return true
    end
    if not add("HEAD",{id,tostring(table.getn(rows)),tostring(now)}) then return nil end
    local seen={}
    for i,e in ipairs(rows) do
        local row=C.AccountRowCopy(e)
        if not row or row.observed>now or (row.raidObserved and row.raidObserved>now) or seen[string.lower(row.name)] then return nil end
        seen[string.lower(row.name)]=true
        local fields={tostring(i),row.name,"60",row.dungeonLicense,row.raidLicense,tostring(row.observed)}
        if row.faction then table.insert(fields,string.sub(row.faction,1,1)) end
        if not add("ROW",fields) then return nil end
        local v=row.saves or {0,0,0,0}
        if not add("SAVE",{tostring(i),tostring(row.raidObserved or 0),tostring(v[1]),tostring(v[2]),tostring(v[3]),tostring(v[4])}) then return nil end
    end
    return packets
end

function C.AccountSavedCopy(r,you,realm,links)
    if type(r)~="table" or r.realm~=realm or not C.AccountIdentity(r.accountId)
        or not C.LinkKnown(links,you,r.source,realm) or r.authoritative~=false
        or not C.RaidNumber(r.received,1,2147483647) or not C.RaidNumber(r.observed,1,r.received)
        or type(r.entries)~="table" then return nil end
    local entries,seen,count={},{},0
    for i,e in pairs(r.entries) do
        local row=C.AccountRowCopy(e)
        if not C.RaidNumber(i,1,64) or not row or row.observed>r.observed
            or (row.raidObserved and row.raidObserved>r.observed) or seen[string.lower(row.name)] then return nil end
        entries[i]=row; seen[string.lower(row.name)]=true; count=count+1
    end
    for i=1,count do if not entries[i] then return nil end end
    return {accountId=r.accountId,source=r.source,realm=realm,received=r.received,observed=r.observed,entries=entries,authoritative=false}
end

-- Previously approved account names are advisory planning data, not authority.
function C.RememberedHireNames(db,you,realm)
    local found,keys={},{}
    for key in pairs(type(db.peerSnapshots)=="table" and db.peerSnapshots or {}) do
        if type(key)=="string" then table.insert(keys,key) end
    end
    table.sort(keys)
    for _,key in ipairs(keys) do
        local copy=C.AccountSavedCopy(db.peerSnapshots[key],you,realm,db.peerLinks)
        if copy and key==realm .. ";" .. string.lower(copy.source) then
            for _,row in ipairs(copy.entries) do found[string.lower(row.name)]=row.name end
        end
    end
    local names={}; for _,name in pairs(found) do table.insert(names,name) end
    table.sort(names,function(a,b) return string.lower(a)<string.lower(b) end)
    return names
end

-- A process has one frozen composition and ordered steps that cover every occupied
-- board slot exactly once, in increasing slot order. A step is a whole raid group
-- ("group,actor"); a group several accounts hire into is split into exact slot chunks
-- ("group,actor,first,last"): two or more, ascending, alternating actors, bounded by
-- occupied slots. One step per occupied slot at most, so 40 slots bound every run.
-- The wire carries progress claims only; it cannot request execution or settings.
-- Plain H5 keeps its origin as the first actor and whole groups only. Only the base
-- inside an authorized GRANT/REPORT/PAUSE H6 wrapper (wrapped) may start with a linked
-- account's step or carry chunks; earlier versions reject chunk rows outright.
-- An authorized run may end with commands steps ("0,actor"), at most one per actor that
-- has a hire step: that actor whispers the plan's commands to every row it hired, after
-- every hire of the run (see HandStepPlan). Earlier versions reject them. So 40 hire
-- steps and 40 commands steps bound every run, whatever the number of accounts.
local function HandBaseEncode(h,wrapped)
    if type(h)~="table" or not C.PeerNonce(h.id) or not C.IsSafeCharacterName(h.origin)
        or type(h.realm)~="string" or string.len(h.realm)<1 or string.len(h.realm)>40
        or h.realm~=C.Trim(h.realm) or not string.find(h.realm,"^[A-Za-z0-9 '-]+$")
        or not C.RaidNumber(h.expires,1,2147483647) or type(h.steps)~="table"
        or not C.RaidNumber(h.step,1,table.getn(h.steps)+1) then return nil end
    local count=table.getn(h.steps)
    if count<1 or count>80 then return nil end
    local plan=C.PlanEncode(h.plan,"hire",h.name)
    if not plan then return nil end
    local function filled(i) local e=h.plan.entries[i]; return e and e.kind~="empty" end
    local size,hires={},0
    for k=1,count do
        local row=h.steps[k]
        if type(row)~="table" or not C.IsSafeCharacterName(row.actor) then return nil end
        if row.group==0 then
            if not wrapped or row.first~=nil or row.last~=nil then return nil end
        elseif not C.RaidNumber(row.group,1,8) or hires<k-1 then return nil
        else hires=k; size[row.group]=(size[row.group] or 0)+1 end
    end
    if hires<1 or hires>40 or count-hires>40 then return nil end
    if not wrapped and string.lower(h.origin)~=string.lower(h.steps[1].actor) then return nil end
    local steps,cover,last,hired,commands={},{},nil,{},{}
    for k=hires+1,count do
        local key=string.lower(h.steps[k].actor)
        if commands[key] then return nil end
        commands[key]=true
    end
    for k=1,hires do
        local row=h.steps[k]; local lo,hi=(row.group-1)*5+1,row.group*5
        hired[string.lower(row.actor)]=true
        if size[row.group]>1 then
            if not wrapped or not C.RaidNumber(row.first,lo,hi) or not C.RaidNumber(row.last,row.first,hi)
                or not filled(row.first) or not filled(row.last) then return nil end
            lo,hi=row.first,row.last
            table.insert(steps,row.group .. "," .. row.actor .. "," .. lo .. "," .. hi)
        elseif row.first~=nil or row.last~=nil then return nil
        else table.insert(steps,row.group .. "," .. row.actor) end
        if last and (row.group<last.group or (row.group==last.group
            and (lo<=last.hi or string.lower(row.actor)==string.lower(last.actor)))) then return nil end
        for i=lo,hi do if filled(i) then cover[i]=true end end
        last={group=row.group,hi=hi,actor=row.actor}
    end
    for k=hires+1,count do
        local row=h.steps[k]
        if not hired[string.lower(row.actor)] then return nil end
        table.insert(steps,"0," .. row.actor)
    end
    -- Every occupied slot is covered once; every step's group is occupied.
    for group=1,8 do
        local occupied=false
        for i=(group-1)*5+1,group*5 do
            if filled(i) then occupied=true; if not cover[i] then return nil end end
        end
        if occupied~=(size[group]~=nil) then return nil end
    end
    local text=table.concat({"H5",h.id,h.origin,h.realm,tostring(h.expires),tostring(h.step),table.concat(steps,"/")},"~") .. "~" .. plan
    if string.len(text)<=6144 then return text end
end

local function HandBaseDecode(text,wrapped)
    if type(text)~="string" or string.len(text)>6144 then return nil end
    local f=C.PlanParts(text,"~")
    if table.getn(f)~=10 or f[1]~="H5" or not string.find(f[5],"^%d+$") or not string.find(f[6],"^%d+$") then return nil end
    local plan=C.PlanDecode(table.concat({f[8],f[9],f[10]},"~"))
    if not plan or plan.mode~="hire" then return nil end
    local h={id=f[2],origin=f[3],realm=f[4],expires=tonumber(f[5]),step=tonumber(f[6]),steps={},name=plan.name,plan=plan}
    for _,textRow in ipairs(C.PlanParts(f[7],"/")) do
        local row=C.PlanParts(textRow,","); local n=table.getn(row)
        if (n~=2 and n~=4) or not string.find(row[1],"^%d+$") then return nil end
        local step={group=tonumber(row[1]),actor=row[2]}
        if n==4 then
            if not string.find(row[3],"^%d+$") or not string.find(row[4],"^%d+$") then return nil end
            step.first=tonumber(row[3]); step.last=tonumber(row[4])
        end
        table.insert(h.steps,step)
    end
    if HandBaseEncode(h,wrapped)==text then return h end
end

-- Kinds whose wrapper carries an authorized run, which may start with a linked account's
-- group or carry chunks: the leader's GRANT, and a participant's REPORT or PAUSE answer.
-- Only GRANT is ever work; a REPORT or PAUSE is checked against the leader's own run.
local function HandWrapsFirst(kind)
    return kind=="GRANT" or kind=="REPORT" or kind=="PAUSE"
end

-- The plan's own commands (h.extras), frozen at Execute so every step applies this plan
-- and never whatever profile is open: its group deny and setup rules, and each legacy
-- row's custom denies, pet, aspect, magic and individual setups. Only a GRANT carries
-- them, as "X1~D~S~L" before the base: D rows "slot,role,class,ability" (one ability
-- per row; slot 0 is a group rule, consecutive rows with equal role and class form one
-- rule), S rows "slot,<HAND_SETUP_FIELDS>", L rows "slot,pet,aspect,magic". A slot above
-- 0 must hold a legacy row. Values are printable text without "|", at most 64 bytes;
-- on the wire every byte but letters, digits, space, ' and - is _XX (hex), "_" is none.
-- A wire is accepted only in its one canonical form.
C.HAND_SETUP_FIELDS={"class","role","spec","aura","aspect","pet","growl","magic","drink","earth","fire","water","air"}
C.HAND_LEGACY_FIELDS={"pet","aspect","magic"}

-- A command value as BuildQueue reads it (C.Trim): nil when blank, false when unsendable.
local function HandValue(v)
    if v==nil then return nil end
    local kind=type(v)
    if kind~="string" and kind~="number" and kind~="boolean" then return false end
    v=C.Trim(v)
    if v=="" then return nil end
    if string.len(v)>64 or string.find(v,"[^ -~]") or string.find(v,"|",1,true) then return false end
    return v
end

local function HandWire(v)
    if v==nil then return "_" end
    return (string.gsub(v,"[^A-Za-z0-9 '%-]",function(c) return string.format("_%02X",string.byte(c)) end))
end

-- nil,true for "_"; the value,true; or nil,false when it is not a sendable value.
local function HandUnwire(text)
    if text=="_" then return nil,true end
    local v=HandValue((string.gsub(text,"_(%x%x)",function(x) return string.char(tonumber(x,16)) end)))
    return v or nil,v and true or false
end

-- Deny abilities as BuildQueue reads them: trimmed, case-insensitively unique, sendable.
local function HandAbilities(values)
    local out={}
    for _,v in ipairs(C.NormalizeDenyList(values)) do
        local t=HandValue(v)
        if not t then return nil end
        table.insert(out,t)
    end
    return out
end

local function HandSetup(rule)
    if type(rule)~="table" then return nil end
    local out={}
    for _,key in ipairs(C.HAND_SETUP_FIELDS) do
        local v=HandValue(rule[key])
        if v==false then return nil end
        out[key]=v
    end
    return out
end

local function HandExtrasEncode(x,plan)
    if type(x)~="table" or type(x.denyRules)~="table" or type(x.setupRules)~="table" or type(x.legacy)~="table"
        or type(plan)~="table" or type(plan.entries)~="table" then return nil end
    for slot in pairs(x.legacy) do
        local e=plan.entries[slot]
        if not C.RaidNumber(slot,1,40) or type(e)~="table" or e.kind~="legacy" then return nil end
    end
    local d,s,l={},{},{}
    local function value(v)
        local t=HandValue(v)
        if t==false then return nil end
        return HandWire(t)
    end
    local function setupRows(slot,rules)
        if rules==nil then return true end
        if type(rules)~="table" then return false end
        for _,rule in ipairs(rules) do
            local copy=HandSetup(rule)
            if not copy then return false end
            local row={tostring(slot)}
            for _,key in ipairs(C.HAND_SETUP_FIELDS) do table.insert(row,HandWire(copy[key])) end
            table.insert(s,table.concat(row,","))
        end
        return true
    end
    -- Consecutive rules with equal role and class are one rule: their union is what
    -- BuildGroupDenyPlan sends, and it is the only form a decoder can rebuild.
    local groups={}
    for _,rule in ipairs(x.denyRules) do
        if type(rule)~="table" then return nil end
        local role,class=value(rule.role),value(rule.class)
        if not role or not class then return nil end
        local last=groups[table.getn(groups)]
        if not (last and last.role==role and last.class==class) then
            last={role=role,class=class,abilities={}}; table.insert(groups,last)
        end
        for _,a in ipairs(type(rule.abilities)=="table" and rule.abilities or {}) do table.insert(last.abilities,a) end
    end
    for _,group in ipairs(groups) do
        local abilities=HandAbilities(group.abilities)
        if not abilities then return nil end
        for _,a in ipairs(abilities) do table.insert(d,table.concat({"0",group.role,group.class,HandWire(a)},",")) end
    end
    if not setupRows(0,x.setupRules) then return nil end
    for slot=1,40 do
        local e=x.legacy[slot]
        if e~=nil then
            if type(e)~="table" then return nil end
            local abilities=HandAbilities(type(e.denyList)=="table" and e.denyList or {})
            if not abilities then return nil end
            for _,a in ipairs(abilities) do table.insert(d,slot .. ",_,_," .. HandWire(a)) end
            if not setupRows(slot,e.setupRules) then return nil end
            local row,any={tostring(slot)},false
            for _,key in ipairs(C.HAND_LEGACY_FIELDS) do
                local v=value(e[key])
                if not v then return nil end
                if v~="_" then any=true end
                table.insert(row,v)
            end
            if any then table.insert(l,table.concat(row,",")) end
        end
    end
    if table.getn(d)>160 or table.getn(s)>80 or table.getn(l)>40 then return nil end
    return table.concat(d,"/") .. "~" .. table.concat(s,"/") .. "~" .. table.concat(l,"/")
end

local function HandExtrasDecode(dText,sText,lText,plan)
    local x={denyRules={},setupRules={},legacy={}}
    local function rows(text) if text=="" then return {} end return C.PlanParts(text,"/") end
    local function slotOf(text,legacyOnly)
        if not string.find(text,"^%d+$") or string.len(text)>2 then return nil end
        local slot=tonumber(text)
        if slot==0 and not legacyOnly then return 0 end
        local e=plan.entries[slot]
        if C.RaidNumber(slot,1,40) and type(e)=="table" and e.kind=="legacy" then return slot end
    end
    local function legacy(slot) x.legacy[slot]=x.legacy[slot] or {}; return x.legacy[slot] end
    for _,text in ipairs(rows(dText)) do
        local f=C.PlanParts(text,",")
        if table.getn(f)~=4 then return nil end
        local slot=slotOf(f[1]); local role,okRole=HandUnwire(f[2]); local class,okClass=HandUnwire(f[3]); local ability=HandUnwire(f[4])
        if not slot or not okRole or not okClass or not ability then return nil end
        if slot==0 then
            local last=x.denyRules[table.getn(x.denyRules)]
            if last and last.role==role and last.class==class then table.insert(last.abilities,ability)
            else table.insert(x.denyRules,{role=role,class=class,abilities={ability}}) end
        else
            if role~=nil or class~=nil then return nil end
            local e=legacy(slot); e.denyList=e.denyList or {}; table.insert(e.denyList,ability)
        end
    end
    for _,text in ipairs(rows(sText)) do
        local f=C.PlanParts(text,",")
        if table.getn(f)~=table.getn(C.HAND_SETUP_FIELDS)+1 then return nil end
        local slot=slotOf(f[1])
        if not slot then return nil end
        local rule={}
        for i,key in ipairs(C.HAND_SETUP_FIELDS) do
            local v,ok=HandUnwire(f[i+1])
            if not ok then return nil end
            rule[key]=v
        end
        if slot==0 then table.insert(x.setupRules,rule)
        else local e=legacy(slot); e.setupRules=e.setupRules or {}; table.insert(e.setupRules,rule) end
    end
    for _,text in ipairs(rows(lText)) do
        local f=C.PlanParts(text,",")
        if table.getn(f)~=table.getn(C.HAND_LEGACY_FIELDS)+1 then return nil end
        local slot=slotOf(f[1],true)
        if not slot then return nil end
        local e=legacy(slot)
        for i,key in ipairs(C.HAND_LEGACY_FIELDS) do
            local v,ok=HandUnwire(f[i+1])
            if not ok then return nil end
            e[key]=v
        end
    end
    return x
end

-- Freeze a plan's own commands for a run (see HAND_SETUP_FIELDS above). Returns nil when
-- one cannot be sent; the caller refuses Execute and names the reason.
function C.HandExtras(plan)
    if type(plan)~="table" or type(plan.entries)~="table" then return nil end
    local x={denyRules={},setupRules={},legacy={}}
    for _,rule in ipairs(type(plan.denyRules)=="table" and plan.denyRules or {}) do
        if type(rule)~="table" then return nil end
        local role,class,abilities=HandValue(rule.role),HandValue(rule.class),HandAbilities(type(rule.abilities)=="table" and rule.abilities or {})
        if role==false or class==false or not abilities then return nil end
        if table.getn(abilities)>0 then table.insert(x.denyRules,{role=role,class=class,abilities=abilities}) end
    end
    for _,rule in ipairs(type(plan.setupRules)=="table" and plan.setupRules or {}) do
        local copy=HandSetup(rule)
        if not copy then return nil end
        table.insert(x.setupRules,copy)
    end
    for slot=1,40 do
        local e=plan.entries[slot]
        if type(e)=="table" and e.kind=="legacy" then
            local out,any={},false
            local abilities=HandAbilities(type(e.denyList)=="table" and e.denyList or {})
            if not abilities then return nil end
            if table.getn(abilities)>0 then out.denyList=abilities; any=true end
            for _,key in ipairs(C.HAND_LEGACY_FIELDS) do
                local v=HandValue(e[key])
                if v==false then return nil end
                if v then out[key]=v; any=true end
            end
            if type(e.setupRules)=="table" and table.getn(e.setupRules)>0 then
                out.setupRules={}
                for _,rule in ipairs(e.setupRules) do
                    local copy=HandSetup(rule)
                    if not copy then return nil end
                    table.insert(out.setupRules,copy)
                end
                any=true
            end
            if any then x.legacy[slot]=out end
        end
    end
    if not HandExtrasEncode(x,plan) then return nil end
    return x
end

function C.HandEncode(h)
    if type(h)=="table" and h.kind then
        if h.kind~="GRANT" and h.kind~="REPORT" and h.kind~="PAUSE" and h.kind~="END" then return nil end
        if type(h.accounts)~="table" or type(h.steps)~="table" or table.getn(h.accounts)~=table.getn(h.steps) then return nil end
        for _,id in ipairs(h.accounts) do if not C.AccountIdentity(id) then return nil end end
        local copy=CopyImportValue(h); copy.kind=nil; copy.accounts=nil; copy.extras=nil
        local base=HandBaseEncode(copy,HandWrapsFirst(h.kind))
        if base then
            -- Only work carries the plan's commands; answers bind to the run without them.
            local extras=""
            if h.kind=="GRANT" and h.extras~=nil then
                extras=HandExtrasEncode(h.extras,h.plan)
                if not extras then return nil end
                extras="X1~" .. extras .. "~"
            end
            local wire="H6~" .. h.kind .. "~" .. table.concat(h.accounts,",") .. "~" .. extras .. base
            if string.len(wire)<=6144 then return wire end
        end
        return nil
    end
    return HandBaseEncode(h,false)
end

function C.HandDecode(text)
    if type(text)~="string" or string.len(text)>6144 then return nil end
    if string.sub(text,1,3)=="H6~" then
        local _,_,kind,accounts,rest=string.find(text,"^H6~([A-Z]+)~([0-9,]+)~(.+)$")
        local base,d,s,l=rest,nil,nil,nil
        if kind=="GRANT" and rest and string.sub(rest,1,3)=="X1~" then
            _,_,d,s,l,base=string.find(rest,"^X1~([^~]*)~([^~]*)~([^~]*)~(H5~.+)$")
        end
        local h=base and string.sub(base,1,3)=="H5~" and HandBaseDecode(base,HandWrapsFirst(kind))
        if not h then return nil end
        if d then
            h.extras=HandExtrasDecode(d,s,l,h.plan)
            if not h.extras then return nil end
        end
        h.kind=kind; h.accounts=C.PlanParts(accounts,",")
        if C.HandEncode(h)==text then return h end
        return nil
    end
    return HandBaseDecode(text,false)
end

-- Exact frozen revision, endpoint/account claims and expiry; progress is separate. The
-- plan's commands travel only in a GRANT, so they are never part of the scope.
function C.HandRunScope(h)
    if not h or not h.kind then return nil end
    local copy=CopyImportValue(h); copy.step=1; copy.kind="GRANT"; copy.extras=nil
    return C.HandEncode(copy)
end

-- Hire-from characters listed by trusted linked account snapshots on this realm:
-- lower-case name -> {endpoint=linked character, accountId=claim}. Any character of an
-- account can hire from any other, and an account is online on one character at a time,
-- so every name an account lists goes to that account's current endpoint: the one
-- endpoint holding a live trusted session (sessions, at wall/clock) whose account claim,
-- received in that session, matches; with none live, the endpoint whose saved snapshot
-- arrived last. When several endpoints are live, or the newest snapshots tie, a name
-- keeps its own endpoint if it is one of them and is otherwise ambiguous (false). A name
-- claimed by different accounts is always ambiguous. The receiver still checks its own
-- characters. Independent of table iteration order.
function C.HandRemoteSources(licenses,links,you,realm,sessions,wall,clock)
    local live={}
    if type(sessions)=="table" and type(wall)=="number" and type(clock)=="number" then
        for _,session in pairs(sessions) do
            local s=type(session)=="table" and session.state
            local r=type(s)=="table" and s.realm==realm and s.you==string.lower(you) and C.PlanAuthorized(s,links,wall,clock)
                and C.AccountSavedCopy(s.remoteLicense,you,realm,links)
            if r and r.source==s.peer then live[s.peer]=r.accountId end
        end
    end
    local found,accounts={},{}
    for key,r in pairs(type(licenses)=="table" and licenses or {}) do
        local source=type(r)=="table" and r.source
        if type(source)=="string" and type(links)=="table" and r.realm==realm and key==realm .. ";" .. source
            and C.AccountIdentity(r.accountId) and type(r.entries)=="table" and C.LinkKnown(links,you,source,realm) then
            local own,account=C.LinkKey(you,source,realm,false),C.LinkKey(you,source,realm,true)
            local link=(own and links[own]) or (account and links[account])
            local label=type(link)=="table" and link.peerLabel
            if C.IsSafeCharacterName(label) and string.lower(label)==source then
                local a=accounts[r.accountId] or {endpoints={}}
                accounts[r.accountId]=a
                a.endpoints[source]={endpoint=label,accountId=r.accountId,received=type(r.received)=="number" and r.received or 0}
                for _,e in pairs(r.entries) do
                    if type(e)=="table" and C.IsSafeCharacterName(e.name) then
                        local name=string.lower(e.name)
                        found[name]=found[name] or {}
                        found[name][r.accountId]=true
                    end
                end
            end
        end
    end
    -- Each account's candidates: its live endpoints, or else its newest saved snapshots.
    for id,a in pairs(accounts) do
        local online,newest,at,count={},{},nil,0
        for source,claim in pairs(a.endpoints) do
            if live[source]==id then online[source]=claim; count=count+1 end
            if not at or claim.received>at then newest={[source]=claim}; at=claim.received
            elseif claim.received==at then newest[source]=claim end
        end
        a.candidates=count>0 and online or newest
        local n,only=0,nil
        for _,claim in pairs(a.candidates) do n=n+1; only=claim end
        if n==1 then a.current=only end
    end
    local out={}
    for name,ids in pairs(found) do
        local count,id=0,nil
        for k in pairs(ids) do count=count+1; id=k end
        if count>1 then out[name]=false
        else
            local a=accounts[id]
            out[name]=a.current or a.candidates[name] or false
        end
    end
    return out
end

-- Execute actors, derived only from the prepared board. Hire-from characters on this
-- account (own, keyed by lower-case name) are hired by you locally; characters a
-- trusted linked snapshot lists (sources, from HandRemoteSources) are hired by that
-- linked endpoint; other names are their own actor. A group whose normal rows name one
-- actor keeps it (actors[group] is a name; occupied legacy-only groups are yours). A
-- group naming several actors maps each occupied slot to its actor (actors[group] is
-- {[slot]=name}); its other rows go with the preceding owned row's actor, or the
-- group's first one. A legacy row belongs to the account that owns its character, as
-- own or one trusted snapshot shows; with neither it follows the position rule and its
-- name is returned in unknown. Returns actors,remote,nil,nil,unknown; or
-- nil,nil,group,name when one character's owner is ambiguous.
function C.HandActors(plan,you,own,sources)
    local function actorOf(name,legacy)
        name=C.Trim(name)
        if name=="" then return nil end
        local key=string.lower(name)
        local mine=type(own)=="table" and own[key]==true
        local claim=nil
        if type(sources)=="table" then claim=sources[key] end
        if claim==false or (mine and claim~=nil) then return nil,true end
        if mine then return you end
        if claim then return claim.endpoint end
        -- Only another account can hire its own legacy character, so never guess one.
        if legacy then return nil end
        return name
    end
    local actors,remote,unknown={},false,{}
    for group=1,8 do
        local owners,first,actor,occupied,mixed={},nil,nil,false,false
        for i=(group-1)*5+1,group*5 do
            local e=plan.entries[i]
            if e and e.kind~="empty" then occupied=true end
            local owner,unclear
            if e and e.kind=="legacy" then
                owner,unclear=actorOf(C.GetLegacyHireName(e),true)
                if unclear then return nil,nil,group,C.GetLegacyHireName(e) end
                if not owner then table.insert(unknown,C.GetLegacyHireName(e)) end
            end
            if e and e.kind=="normal" then
                owner,unclear=actorOf(e.account)
                if unclear then return nil,nil,group,C.Trim(e.account) end
            end
            if e and (e.kind=="normal" or e.kind=="legacy") then
                if owner then
                    first=first or owner
                    if string.lower(first)~=string.lower(owner) then mixed=true end
                    owners[i]=owner; actor=owner
                end
            end
        end
        if mixed then
            local slots,current={},first
            for i=(group-1)*5+1,group*5 do
                local e=plan.entries[i]
                if e and e.kind~="empty" then
                    current=owners[i] or current; slots[i]=current
                    if string.lower(current)~=string.lower(you) then remote=true end
                end
            end
            actors[group]=slots
        else
            if occupied and not actor then actor=you end
            actors[group]=actor
            if actor and string.lower(actor)~=string.lower(you) then remote=true end
        end
    end
    return actors,remote,nil,nil,unknown
end

-- A normal row runs on its own hire-from character; on you when own (this account's
-- validated character map, lower-case name -> true) lists it; or on a linked endpoint
-- when sources (HandRemoteSources) maps it there and own does not. The account never changes.
function C.HandOwnsSource(account,actor,you,own,sources)
    local key=string.lower(account)
    if key==string.lower(actor) then return true end
    local mine=type(own)=="table" and own[key]==true
    if string.lower(actor)==string.lower(you) then return mine end
    local claim=type(sources)=="table" and sources[key]
    return not mine and type(claim)=="table" and string.lower(claim.endpoint)==string.lower(actor)
end

-- authorized: the caller wraps the result as a GRANT (kind/accounts) before storing or
-- sending it, so the first step may be a linked account's and a group may split into
-- slot chunks. Plain calls keep the origin-first, whole-group guard. actors[group] is a
-- name, or {[slot]=name} for a group several accounts hire into (see HandActors).
function C.HandCreate(plan,name,you,realm,actors,id,wall,own,sources,authorized)
    if not C.RaidNumber(wall,1,2147397247) or type(actors)~="table" then return nil end
    local text=C.PlanEncode(plan,"hire",name); local copy=text and C.PlanDecode(text)
    if not copy then return nil end
    local h={id=id,origin=you,realm=realm,expires=wall+86400,step=1,steps={},name=name,plan=copy,phase="ready"}
    for group=1,8 do
        local slots,chunks=actors[group],{}
        for i=(group-1)*5+1,group*5 do
            local row=copy.entries[i]
            if row and row.kind~="empty" then
                local actor=slots
                if type(slots)=="table" then actor=slots[i] end
                if not C.IsSafeCharacterName(actor) then return nil end
                if row.kind=="normal" and not C.HandOwnsSource(row.account,actor,you,own,sources) then return nil end
                local chunk=chunks[table.getn(chunks)]
                if chunk and string.lower(chunk.actor)==string.lower(actor) then chunk.last=i
                else table.insert(chunks,{group=group,actor=actor,first=i,last=i}) end
            end
        end
        -- One actor keeps the whole group; several actors leave exact slot chunks.
        if table.getn(chunks)==1 then chunks[1].first=nil; chunks[1].last=nil end
        for _,chunk in ipairs(chunks) do table.insert(h.steps,chunk) end
    end
    -- The plan's commands go out after every hire, as a single builder sends them: one
    -- commands step for each actor whose rows get any (see HandCommandActors).
    if authorized==true then
        for _,actor in ipairs(C.HandCommandActors(h.steps,plan)) do table.insert(h.steps,{group=0,actor=actor}) end
    end
    if HandBaseEncode(h,authorized==true) then return h end
end

-- The slots a hire step covers: its whole group, or exactly its chunk. nil when invalid.
function C.HandStepSlots(step)
    local group=type(step)=="table" and step.group
    if not C.RaidNumber(group,1,8) then return nil end
    local first,last=step.first or (group-1)*5+1,step.last or group*5
    if first<(group-1)*5+1 or last>group*5 or last<first then return nil end
    return first,last
end

-- The actors of these hire steps whose rows get a command from the plan: a legacy row's
-- own commands, or a deny or setup rule naming the row's class (and its role, unless the
-- rule takes every role), as group commands expand. Ordered for the end of the run: the
-- last step's actor first, so it goes on without a hand-off, then the rest by first step.
function C.HandCommandActors(steps,plan)
    local order,rows={},{}
    for _,step in ipairs(steps) do
        local key=string.lower(step.actor)
        if not rows[key] then rows[key]={}; table.insert(order,step.actor) end
        local first,last=C.HandStepSlots(step)
        for i=first or 1,last or 0 do
            local e=plan.entries[i]
            if type(e)=="table" and e.kind~="empty" then rows[key][i]=e end
        end
    end
    local function needs(own)
        local subset={entries={},denyRules=plan.denyRules,setupRules=plan.setupRules}
        local companions={}
        for i=1,40 do
            subset.entries[i]=own[i] or {kind="empty"}
            if own[i] then table.insert(companions,{name="row" .. i,class=C.NormalizeClassLabel(own[i].class),role=C.NormalizeRoleLabel(own[i].role)}) end
        end
        for _,item in ipairs(C.BuildWhisperQueue(subset)) do
            if item.phase=="role-class-final" or item.phase=="class-setup" then
                if table.getn(C.MatchCompanionsScoped(companions,item.class,item.role,item.spec))>0 then return true end
            else return true end
        end
        return false
    end
    local out,lastKey={},table.getn(steps)>0 and string.lower(steps[table.getn(steps)].actor)
    for _,actor in ipairs(order) do
        if string.lower(actor)==lastKey and needs(rows[lastKey]) then table.insert(out,actor) end
    end
    for _,actor in ipairs(order) do
        if string.lower(actor)~=lastKey and needs(rows[string.lower(actor)]) then table.insert(out,actor) end
    end
    return out
end

function C.HandRestore(h,you,realm,wall)
    local text=C.HandEncode(h); local copy=text and C.HandDecode(text)
    local phases={ready=true,running=true,interrupted=true,submitted=true,waiting=true,done=true,cancelled=true}
    if not copy or h.realm~=realm or not C.RaidNumber(wall,1,h.expires-1) or not phases[h.phase]
        or not C.IsSafeCharacterName(you) then return nil end
    copy.phase=h.phase=="running" and "interrupted" or h.phase
    copy.source=h.source; copy.updated=h.updated
    return copy
end

-- An authorized run hands an actor all its steps in a row at once: step k through the
-- last step after it with the same actor. Both sides read the batch from the frozen
-- steps, so the wire is unchanged; one grant starts it and one report ends it.
function C.HandBatchEnd(h,k)
    local step=h and h.steps and h.steps[k]
    if not step then return k end
    local last=k
    if h.kind=="GRANT" then
        while h.steps[last+1] and string.lower(h.steps[last+1].actor)==string.lower(step.actor) do last=last+1 end
    end
    return last
end

-- The current batch's slots (see HandBatchEnd): each step's whole group, or exactly its
-- chunk, in board order. A run carries its plan's commands (h.extras) and builds from
-- them; a run saved before they existed keeps the open profile's rules (settings).
-- out.hires names the slots to hire. A run with commands steps hires only in its hire
-- steps; its commands step adds every row its actor hired (out.allRows) and the commands
-- for them (out.commands). A run without one sends each step's commands with its hires.
function C.HandStepPlan(h,settings,you,own)
    if not h or h.phase~="ready" or not h.steps[h.step] or string.lower(h.steps[h.step].actor)~=string.lower(you) then return nil end
    local x=type(h.extras)=="table" and h.extras
    local out
    if x then out={entries={},denyRules=CopyImportValue(x.denyRules or {}),setupRules=CopyImportValue(x.setupRules or {})}
    else out=CopyImportValue(settings or C.BlankPreset()); out.entries={} end
    out.hires={}; out.commands=true
    for _,step in ipairs(h.steps) do if step.group==0 then out.commands=false end end
    local function add(i,hire)
        local row=h.plan.entries[i]
        if row and row.kind~="empty" then
            if row.kind=="normal" and not C.HandOwnsSource(row.account,you,you,own) then return false end
            if not out.entries[i] then
                out.entries[i]=CopyImportValue(row)
                local commands=x and row.kind=="legacy" and type(x.legacy)=="table" and x.legacy[i]
                if type(commands)=="table" then
                    for key,value in pairs(commands) do out.entries[i][key]=CopyImportValue(value) end
                end
            end
            if hire then out.hires[i]=true end
        end
        return true
    end
    for k=h.step,C.HandBatchEnd(h,h.step) do
        local step=h.steps[k]
        if step.group==0 then
            out.commands=true; out.allRows=true
            for _,row in ipairs(h.steps) do
                if row.group~=0 and string.lower(row.actor)==string.lower(step.actor) then
                    local first,last=C.HandStepSlots(row)
                    if not first then return nil end
                    for i=first,last do if not add(i,false) then return nil end end
                end
            end
        else
            local first,last=C.HandStepSlots(step)
            if not first then return nil end
            for i=first,last do if not add(i,true) then return nil end end
        end
    end
    return out
end

-- A run batch's queue (HandStepPlan): BuildQueue's order, with hires for out.hires only
-- and the commands only when the batch sends them. Any other plan: BuildQueue.
function C.HandQueue(plan)
    local queue=C.BuildQueue(plan)
    if type(plan)~="table" or type(plan.hires)~="table" then return queue end
    local out={}
    for _,item in ipairs(queue) do
        if C.IsHireCommand(item) then
            if plan.hires[item.sourceEntryIndex] then table.insert(out,item) end
        elseif plan.commands then table.insert(out,item) end
    end
    return out
end

function C.HandComplete(h,you)
    if not h or h.phase~="submitted" or not h.steps[h.step] or string.lower(h.steps[h.step].actor)~=string.lower(you) then return false end
    h.step=C.HandBatchEnd(h,h.step)+1; h.phase=h.step>table.getn(h.steps) and "done" or "waiting"
    return true
end

function C.HandApprove(store,h,sender,you,realm,wall)
    -- A GRANT comes from the run's leader and may authorize step 1; a chained process
    -- comes from the previous actor and never starts at step 1.
    if type(store)~="table" or not C.HandEncode(h) or (h.kind and h.kind~="GRANT") or h.realm~=realm or not C.RaidNumber(wall,1,h.expires-1)
        or (h.step<2 and h.kind~="GRANT") or not h.steps[h.step] or not C.IsSafeCharacterName(sender) or not C.IsSafeCharacterName(you)
        or string.lower(h.steps[h.step].actor)~=string.lower(you)
        or string.lower(h.kind and h.origin or h.steps[h.step-1].actor)~=string.lower(sender) then return false end
    local old,replaced=store.active
    if store.seen~=nil and type(store.seen)~="table" then return false end
    if old and not C.HandEncode(old) then return false end
    if old and old.id==h.id then
        if (old.phase~="waiting" and not (h.kind and old.phase=="done")) or old.step>h.step or old.name~=h.name or old.realm~=h.realm or old.origin~=h.origin
            or old.expires~=h.expires or C.PlanEncode(old.plan,"hire",old.name)~=C.PlanEncode(h.plan,"hire",h.name)
            or table.getn(old.steps)~=table.getn(h.steps) or (h.kind and C.HandRunScope(old)~=C.HandRunScope(h))
            -- A later grant of the same run carries the same frozen plan commands.
            or (h.kind and (old.extras and HandExtrasEncode(old.extras,old.plan) or "")~=(h.extras and HandExtrasEncode(h.extras,h.plan) or "")) then return false end
        for i,row in ipairs(old.steps) do
            local now=h.steps[i]
            if row.group~=now.group or row.actor~=now.actor or row.first~=now.first or row.last~=now.last then return false end
        end
        for i=old.step,h.step-1 do if string.lower(h.steps[i].actor)==string.lower(you) then return false end end
    elseif old and old.phase~="done" and old.phase~="cancelled" and wall<old.expires then
        -- A leader holds one run at a time, and a run's expiry is fixed when it starts, so a
        -- later-expiring grant from the same leader means that leader ended the old run. A
        -- stopped, waiting or unstarted copy of it gives way; a running one, or another
        -- leader's run, still refuses.
        if not (h.kind=="GRANT" and old.kind=="GRANT" and string.lower(old.origin)==string.lower(h.origin) and old.realm==h.realm
            and h.expires>old.expires and old.phase~="running" and old.phase~="submitted") then return false end
        replaced=old
    end
    store.seen=store.seen or {}; local count=0
    for id,row in pairs(store.seen) do
        if not C.PeerNonce(id) or type(row)~="table" or not C.RaidNumber(row.step,1,49) then return false end
        if type(row)~="table" or not C.RaidNumber(row.expires,wall+1,2147483647) then store.seen[id]=nil else count=count+1 end
    end
    local seen=store.seen[h.id]
    if seen and (seen.cancelled or h.step<=seen.step) then return false end
    if not seen and count>=64 then return false end
    local copy=C.HandDecode(C.HandEncode(h)); copy.phase="ready"; copy.source=string.lower(sender); copy.updated=wall
    if replaced then store.seen[replaced.id]={step=replaced.step,expires=replaced.expires,cancelled=true} end
    store.active=copy; store.seen[h.id]={step=h.step,expires=h.expires}
    return true
end

-- A participant runs only a step its leader granted to this account's claim;
-- every leader step must carry the leader's saved account claim.
function C.HandGrantBound(h,sender,you,ownId,leaderId)
    if not h or h.kind~="GRANT" or not C.HandEncode(h) or not C.IsSafeCharacterName(sender) or not C.IsSafeCharacterName(you)
        or string.lower(h.origin)~=string.lower(sender) or string.lower(sender)==string.lower(you) or not h.steps[h.step]
        or string.lower(h.steps[h.step].actor)~=string.lower(you) or not C.AccountIdentity(ownId) or not C.AccountIdentity(leaderId)
        or h.accounts[h.step]~=ownId then return false end
    for i,row in ipairs(h.steps) do
        if string.lower(row.actor)==string.lower(sender) and h.accounts[i]~=leaderId then return false end
    end
    return true
end

-- Only the leader advances, once, on a REPORT for the exact granted revision and a step of
-- the granted batch: its last step, or (from an older participant) any earlier one.
function C.HandReport(h,r,sender,you,realm,wall)
    if not h or h.kind~="GRANT" or h.phase~="waiting" or not r or r.kind~="REPORT" or h.realm~=realm
        or not C.RaidNumber(wall,1,h.expires-1) or not C.IsSafeCharacterName(sender) or not C.IsSafeCharacterName(you)
        or string.lower(h.origin)~=string.lower(you) or not h.steps[h.step] or type(r.step)~="number"
        or r.step<h.step or r.step>C.HandBatchEnd(h,h.step)
        or string.lower(h.steps[h.step].actor)~=string.lower(sender) or C.HandRunScope(h)~=C.HandRunScope(r) then return false end
    h.step=r.step+1; h.updated=wall
    if h.step>table.getn(h.steps) then h.phase="done"
    elseif string.lower(h.steps[h.step].actor)==string.lower(you) then h.phase="ready"
    else h.phase="waiting" end
    return true
end

-- A refusal only pauses: the leader waiting on the exact granted revision, account claims
-- and current step (chunk) stops once, on that step's actor's PAUSE. Nothing advances.
function C.HandRefusal(h,r,sender,you,realm,wall)
    local scope=C.HandRunScope(h)
    if not scope or h.kind~="GRANT" or h.phase~="waiting" or not r or r.kind~="PAUSE" or h.realm~=realm
        or not C.RaidNumber(wall,1,h.expires-1) or not C.IsSafeCharacterName(sender) or not C.IsSafeCharacterName(you)
        or string.lower(h.origin)~=string.lower(you) or not h.steps[h.step] or r.step~=h.step
        or string.lower(h.steps[h.step].actor)~=string.lower(sender) or scope~=C.HandRunScope(r) then return false end
    h.phase="interrupted"; h.updated=wall
    return true
end

-- One outgoing message per state: a leader GRANTs the current step, a participant
-- REPORTs its completed granted step to the leader, a chained process moves on. Only
-- when asked (refused), a participant PAUSEs its own granted step it paused unrun.
function C.HandOutgoing(h,you,refused)
    local text=C.HandEncode(h); local copy=text and C.HandDecode(text)
    if not copy or not C.IsSafeCharacterName(you) then return nil end
    local me=string.lower(you); local current=h.steps[h.step]; local previous=h.steps[h.step-1]
    if refused then
        if h.kind~="GRANT" or string.lower(h.origin)==me or h.phase~="interrupted" or not current or string.lower(current.actor)~=me then return nil end
        copy.kind="PAUSE"
        return C.HandEncode(copy),h.origin
    elseif h.kind=="GRANT" and string.lower(h.origin)==me then
        if h.phase~="waiting" or not current or string.lower(current.actor)==me then return nil end
        return text,current.actor
    elseif h.kind=="GRANT" then
        if (h.phase~="waiting" and h.phase~="done") or not previous or string.lower(previous.actor)~=me then return nil end
        copy.kind="REPORT"; copy.step=h.step-1
        return C.HandEncode(copy),h.origin
    elseif not h.kind and h.phase=="waiting" and current and previous and string.lower(previous.actor)==me then
        return text,current.actor
    end
end

function C.HandParse(text)
    if type(text)~="string" or string.sub(text,1,9)~="SRBHAND5;" then return nil end
    return C.PlanParse("SRBPLAN1;" .. string.sub(text,10))
end

-- A mark of a text: two 24-bit polynomial sums as 12 hex digits.
function C.HandMark(text)
    local a,b=0,0
    for i=1,string.len(text) do
        local c=string.byte(text,i)
        a=math.mod(a*31+c,16777213); b=math.mod(b*37+c,16777199)
    end
    return string.format("%06x%06x",a,b)
end

-- Once an account holds a run, every hand-off message to it is short, "H7~K~id~step~mark":
-- K is G, R or P for GRANT, REPORT or PAUSE, and mark is HandMark of the run's frozen scope
-- (HandRunScope). It fits one packet. The receiver rebuilds the full message from its own
-- copy of the run (HandExpand), so a mark that differs from that copy is refused.
C.HAND_SHORT={GRANT="G",REPORT="R",PAUSE="P"}
C.HAND_LONG={G="GRANT",R="REPORT",P="PAUSE"}
function C.HandShort(h)
    local letter=type(h)=="table" and C.HAND_SHORT[h.kind]
    local scope=letter and C.RaidNumber(h.step,1,49) and C.HandRunScope(h)
    if not scope then return nil end
    return "H7~" .. letter .. "~" .. h.id .. "~" .. h.step .. "~" .. C.HandMark(scope)
end

function C.HandShortParse(text)
    if type(text)~="string" or string.len(text)>48 then return nil end
    local _,_,letter,id,step,mark=string.find(text,"^H7~(%u)~(%d+)~(%d+)~(%x+)$")
    local kind=letter and C.HAND_LONG[letter]
    local n=kind and tonumber(step)
    if not n or not C.PeerNonce(id) or not C.RaidNumber(n,1,49) or tostring(n)~=step
        or string.len(mark)~=12 or string.lower(mark)~=mark then return nil end
    return {kind=kind,id=id,step=n,mark=mark}
end

-- The full message a short one stands for, rebuilt from held (this side's stored run), or
-- nil when it names another run, revision or scope. A GRANT keeps the run's commands.
function C.HandExpand(text,held)
    local p=C.HandShortParse(text)
    if not p or type(held)~="table" or held.kind~="GRANT" or held.id~=p.id then return nil end
    local scope=C.HandRunScope(held)
    local h=scope and C.HandMark(scope)==p.mark and C.HandDecode(C.HandEncode(held))
    if not h then return nil end
    h.kind=p.kind; h.step=p.step
    if p.kind~="GRANT" then h.extras=nil end
    if C.HandEncode(h) then return h end
end

function C.HandPackets(s,text,nonce,wall,clock)
    if not (C.HandDecode(text) or C.HandShortParse(text)) or not C.PeerNonce(nonce) or not s or s.phase~="linked" or not C.PeerAlive(s,wall,clock) then return nil end
    local total=math.ceil(string.len(text)/48); if s.expires-wall<total*0.25+10 then return nil end
    local packets={}
    for i=1,total do
        local packet=table.concat({"SRBHAND5",s.realm,s.youLabel or s.you,s.peerLabel or s.peer,s.a,s.b,nonce,tostring(s.expires),tostring(i),tostring(total),string.sub(text,(i-1)*48+1,i*48)},";")
        if not C.HandParse(packet) then return nil end
        table.insert(packets,packet)
    end
    return packets
end

function C.HandReceive(s,text,sender,links,wall,clock)
    return C.PlanReceive(s,text,sender,links,wall,clock,true)
end

-- When one character hires from another on its account, the server may give either as the
-- companion's owner: the hire-from character, or the character that sent the hire (hirer).
-- This is the second case: NormalHireMatchesInfo with the hirer in the owner's place.
-- Callers try exact owners for every row first, so this never takes another row's match.
function C.HandHiredBy(entry,record,hirer)
    if type(entry)~="table" or entry.kind~="normal" or not C.IsSafeCharacterName(hirer) then return false end
    return C.NormalHireMatchesInfo({kind="normal",account=hirer,companionName=entry.companionName,class=entry.class,role=entry.role},record)
end

-- Companions the run's earlier steps hired are not "already present" for a later step:
-- in step order, each earlier normal row takes its own one-to-one GRINFO match, exact
-- owners first, then one its step's actor owns (HandHiredBy). Commands steps hire nothing.
function C.HandUnclaimed(h,info)
    local used,out,open={},{},{}
    for k=1,(h and h.step or 1)-1 do
        local step=h.steps[k]
        local first,last=C.HandStepSlots(step)
        for i=first or 1,last or 0 do
            local found
            for ri,r in ipairs(info) do
                if not used[ri] and C.NormalHireMatchesInfo(h.plan.entries[i],r) then used[ri]=true; found=true; break end
            end
            if not found then table.insert(open,{slot=i,actor=step.actor}) end
        end
    end
    for _,row in ipairs(open) do
        for ri,r in ipairs(info) do
            if not used[ri] and C.HandHiredBy(h.plan.entries[row.slot],r,row.actor) then used[ri]=true; break end
        end
    end
    for ri,r in ipairs(info) do if not used[ri] then table.insert(out,r) end end
    return out
end

-- The batch's own live companions, and the slots it could not place. A normal row's
-- companion is owned by its hire-from character: you, or one of this account's own
-- characters (own, lower-case name -> true, as HandOwnsSource); failing that, by you as
-- its hirer (HandHiredBy). A legacy row's companion is its -lite name: one you own in the
-- records, or, when the records do not list it, a present group member.
function C.HandScopeFound(entries,records,you,present,own)
    local chosen,used,missing,open,lite,taken={},{},{},{},{},{}
    for _,entry in pairs(entries) do
        if entry.kind=="legacy" then lite[string.lower(C.GetLegacyWhisperName(entry))]=true end
    end
    -- A record with a legacy row's -lite name is never taken for a normal row.
    for i,row in ipairs(records) do if lite[string.lower(row.name or "")] then used[i]=true end end
    for slot,entry in pairs(entries) do
        if entry.kind=="normal" then
            local found
            for i,row in ipairs(records) do
                if not used[i] and C.HandOwnsSource(C.Trim(row.owner),you,you,own) and C.NormalHireMatchesInfo(entry,row) then
                    table.insert(chosen,row); used[i]=true; found=true; break
                end
            end
            if not found then table.insert(open,slot) end
        elseif entry.kind=="legacy" then
            local target=C.GetLegacyWhisperName(entry)
            local found,observed
            for i,row in ipairs(records) do
                if string.lower(row.name or "")==string.lower(target or "") then
                    observed=true
                    if not taken[i] and string.lower(C.Trim(row.owner))==string.lower(you) then
                        table.insert(chosen,row); taken[i]=true; found=true; break
                    end
                end
            end
            if not observed and type(present)=="table" and present[target] then
                table.insert(chosen,{name=target,class=C.NormalizeClassLabel(entry.class),role=C.NormalizeRoleLabel(entry.role)}); found=true
            end
            if not found then table.insert(missing,slot) end
        end
    end
    for _,slot in ipairs(open) do
        local found
        for i,row in ipairs(records) do
            if not used[i] and C.HandHiredBy(entries[slot],row,you) then table.insert(chosen,row); used[i]=true; found=true; break end
        end
        if not found then table.insert(missing,slot) end
    end
    table.sort(missing)
    return chosen,missing
end

-- Every batch row placed, or nil.
function C.HandScope(entries,records,you,present,own)
    local chosen,missing=C.HandScopeFound(entries,records,you,present,own)
    if table.getn(missing)>0 then return nil end
    return chosen
end

function C.AccountReceive(s,text,sender,wall,clock)
    local p=C.AccountParse(text)
    if not C.LicenseBound(s,p,sender,wall,clock) then return false end
    local w=s.licenseWait
    if not w or w.nonce~=p.nonce or clock<w.started or clock-w.started>=45 then return false end
    if p.kind=="HEAD" then
        if p.observed>wall or wall-p.observed>=30 then return false end
        if w.header and w.header~=text then s.licenseWait=nil; return false end
        w.header=text; w.accountId=p.accountId; w.total=p.total; w.observed=p.observed
        w.rows=w.rows or {}; w.saves=w.saves or {}; w.packets=w.packets or {}
    else
        if not w.header or p.index>w.total then return false end
        local key=p.kind .. p.index
        if w.packets[key] then
            if w.packets[key]~=text then s.licenseWait=nil end
            return false
        end
        w.packets[key]=text
        if p.kind=="ROW" then
            if p.row.observed>w.observed then s.licenseWait=nil; return false end
            w.rows[p.index]=p.row
        else
            if p.observed>w.observed then s.licenseWait=nil; return false end
            w.saves[p.index]=p
        end
    end
    local rows,seen={},{}
    for i=1,w.total do
        local row=w.rows[i]; local save=w.saves[i]
        if not row or not save then return false end
        if seen[string.lower(row.name)] then s.licenseWait=nil; return false end
        seen[string.lower(row.name)]=true
        if save.observed>0 then row.raidObserved=save.observed; row.saves=save.saves end
        table.insert(rows,row)
    end
    s.remoteLicense={source=p.sender,realm=p.realm,accountId=w.accountId,entries=rows,received=wall,observed=w.observed,authoritative=false}
    s.licenseWait=nil
    return true
end
