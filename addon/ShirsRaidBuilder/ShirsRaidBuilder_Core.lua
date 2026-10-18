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
    -- A -lite label contains no verified full source identity.
    if string.sub(string.lower(name), -5) == "-lite" then return "" end
    return name
end

-- Planning identity and the server's shortened live address are separate. A
-- shared address does not merge sources, but cannot safely drive Execute.
function C.LegacyTargetError(entries)
    local targets={}
    for i=1,40 do
        local e=entries and entries[i]
        if type(e)=="table" and e.kind=="legacy" then
            local full=C.GetLegacyHireName(e)
            if not C.IsSafeCharacterName(full) then return "Legacy slot "..i.." has only an unknown or shortened identity. Choose its actual full source character before Execute." end
            local target=C.GetLegacyWhisperName(e); local key=string.lower(target)
            if targets[key] then return "Legacy sources "..targets[key].." and "..full.." share live name "..target..". Their full hire names differ, but this client cannot safely match or whisper both. Edit the plan before Execute; nothing was sent." end
            targets[key]=full
        end
    end
end

function C.BuildHireCommand(legacy)
    if type(legacy) ~= "table" then return nil end
    if C.NormalizeClassLabel(legacy.class) == "random" then return nil end
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

function C.IsRandomHire(entry)
    return type(entry) == "table" and entry.kind == "normal" and entry.class == "random"
end

function C.BuildNormalHireCommand(slot)
    if type(slot) ~= "table" then return nil end
    local account = C.Trim(slot.account)
    if not C.IsSafeCharacterName(account) then return nil end
    if slot.class == "random" then
        if not C.IsRandomHire(slot) or slot.account ~= account or type(slot.tier) ~= "string"
            or not (slot.tier == "t0d" or string.find(slot.tier, "^t[1-5][dr]$"))
            or not (slot.role == "tank" or slot.role == "healer" or slot.role == "dps")
            or slot.spec ~= nil or slot.race ~= nil or slot.gender ~= nil then return nil end
        -- MCP's quick role buttons leave class, spec, race and gender to the server.
        return ".z addi " .. account .. " " .. slot.tier .. " " .. slot.role
    end
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

function C.RandomHireAllowsRole(entry, class, role)
    local observedRole = C.NormalizeRoleLabel(role)
    return C.IsRandomHire(entry) and C.BuildNormalHireCommand(entry) ~= nil
        and C.RoleAllowedForClass(class, observedRole)
        and (entry.role == observedRole or (entry.role == "dps" and (observedRole == "mdps" or observedRole == "rdps")))
end

function C.NormalHireMatchesInfo(entry, record)
    if type(entry) ~= "table" or entry.kind ~= "normal" or type(record) ~= "table" then return false end
    local wantedName = C.Trim(entry.companionName)
    local recordName = C.Trim(record.name)
    -- Legacy companions are a separate hire type, even when no legacy row is in this batch.
    if string.find(string.lower(recordName), "%-lite$") then return false end
    if C.Trim(entry.account)=="" or string.lower(C.Trim(entry.account))~=string.lower(C.Trim(record.owner)) then return false end
    if C.IsRandomHire(entry) then
        return C.IsSafeCharacterName(recordName) and C.RandomHireAllowsRole(entry, record.class, record.role)
    end
    if wantedName ~= "" and string.lower(wantedName) == string.lower(recordName) then return true end
    if C.Trim(entry.account) == "" or C.Trim(entry.class) == "" or C.Trim(entry.role) == "" then return false end
    return string.lower(C.Trim(entry.account)) == string.lower(C.Trim(record.owner))
        and C.NormalizeClassLabel(entry.class) == C.NormalizeClassLabel(record.class)
        and C.NormalizeRoleLabel(entry.role) == C.NormalizeRoleLabel(record.role)
end

-- Concrete/named rows reserve live records before role-only intent. In both pools,
-- every exact owner is tried before the established hirer fallback.
function C.NormalHirePriority(entry)
    if C.IsRandomHire(entry) then return 3 end
    if C.Trim(entry.companionName) ~= "" then return 1 end
    return 2
end

function C.NormalHireSlots(entries)
    local slots = {}
    for priority = 1, 3 do
        for slot = 1, 40 do
            local entry = type(entries) == "table" and entries[slot]
            if type(entry) == "table" and entry.kind == "normal" and C.NormalHirePriority(entry) == priority then
                table.insert(slots, slot)
            end
        end
    end
    return slots
end

function C.MatchNormalHireEntries(entries, records, hirers)
    local matched, used = {}, {}
    local slots = C.NormalHireSlots(entries)
    for pool = 1, 2 do
        -- Exact names first, then class/role; repeat only for the proven hirer.
        for pass = 1, 4 do
            for _, slot in ipairs(slots) do
                local entry = entries[slot]
                if not matched[slot] and ((pool == 2) == C.IsRandomHire(entry)) then
                    for _, row in ipairs(type(records) == "table" and records or {}) do
                        local key = type(row) == "table" and string.lower(C.Trim(row.name))
                        if key and key ~= "" and not used[key]
                            and (pass == 2 or pass == 4 or key == string.lower(C.Trim(entry.companionName)))
                            and ((pass <= 2 and C.NormalHireMatchesInfo(entry, row))
                            or (pass >= 3 and hirers and C.HandHiredBy(entry, row, hirers[slot]))) then
                            matched[slot] = row; used[key] = true; break
                        end
                    end
                end
            end
        end
    end
    return matched
end

function C.FilterExistingNormalHires(queue, entries, info)
    local result, active, skipped = {}, {}, 0
    if type(queue) ~= "table" then return result, skipped end
    for _, item in ipairs(queue) do
        if item.kind == "normal" and type(entries) == "table" and item.sourceEntryIndex then
            active[item.sourceEntryIndex] = entries[item.sourceEntryIndex]
        end
    end
    local matched = C.MatchNormalHireEntries(active, info)
    for _, item in ipairs(queue) do
        if item.kind == "normal" and matched[item.sourceEntryIndex] then skipped = skipped + 1
        else table.insert(result, item) end
    end
    return result, skipped
end

-- Legacy rows whose companion is already in the group: slot -> true. A row matches only its
-- exact -lite name in present (a roster snapshot, name -> true), and each live member covers
-- one row, in board order.
function C.PresentLegacySlots(entries, present)
    local slots,used,aliases,live={}, {}, {}, {}
    if type(entries) ~= "table" or type(present) ~= "table" then return slots end
    for name,exists in pairs(present) do if type(name)=="string" and exists then live[string.lower(name)]=true end end
    for i=1,40 do
        local e=entries[i]
        if type(e)=="table" and e.kind=="legacy" then
            local key=string.lower(C.GetLegacyWhisperName(e)); aliases[key]=(aliases[key] or 0)+1
        end
    end
    for i=1,40 do
        local e=entries[i]
        if type(e)=="table" and e.kind=="legacy" and C.IsSafeCharacterName(C.GetLegacyHireName(e)) then
            local key=string.lower(C.GetLegacyWhisperName(e))
            if key~="" and aliases[key]==1 and live[key] and not used[key] then used[key]=true; slots[i]=true end
        end
    end
    return slots
end

-- Drops the legacy hires of PresentLegacySlots; their deny and setup whispers stay queued.
function C.FilterPresentLegacyHires(queue, entries, present)
    local slots, result, skipped = C.PresentLegacySlots(entries, present), {}, 0
    if type(queue) ~= "table" then return result, skipped end
    for i = 1, table.getn(queue) do
        local item = queue[i]
        if item and item.kind == "hire" and slots[item.sourceEntryIndex] then skipped = skipped + 1
        else table.insert(result, item) end
    end
    return result, skipped
end

-- The label a linked run carries for a saved profile name. Only the run wire uses it.
function C.HandWireName(name)
    local label = string.gsub(tostring(name or ""), "[^A-Za-z0-9 _'-]", " ")
    label = string.sub(C.Trim(string.gsub(label, "%s+", " ")), 1, 48)
    label = C.Trim(label)
    if label == "" then return "Plan" end
    return label
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
    if C.NormalizeClassLabel(entry.class) == "random" then
        if not C.IsRandomHire(entry) then return {kind="empty"} end
        return entry -- Intent stays unknown until GRINFO; never apply class defaults.
    end
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

function C.EnsurePlayerSlot(entries, name, class, role, preferred)
    if preferred==40 then
        local slot=C.PlannerPlacePlayer(entries,{}, {name=name,class=class,role=C.Trim(role)~="" and role or nil})
        C.PadRaidSlots(entries,40); return slot
    end
    C.PadRaidSlots(entries, 40)
    local playerName = C.Trim(name)
    if playerName == "" then return nil end
    local found = nil
    local i
    for i = 1, 40 do
        if C.IsPlayerEntry(entries[i]) and string.lower(C.Trim(entries[i].charName))==string.lower(playerName) then
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
    -- Tail placement leaves holes before occupied human slots. Lua 5.0 may
    -- report a short length there; appending would overwrite the tail.
    for i = 1, math.max(want, table.getn(entries)) do
        if type(entries[i]) ~= "table" then
            entries[i] = {kind="empty"}
        elseif not C.IsFilledEntry(entries[i]) then
            entries[i].kind = "empty"
        end
    end
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

function C.CountRoles(entries,companionsOnly)
    local counts = {tank=0, healer=0, mdps=0, rdps=0, dps=0}
    if companionsOnly then counts.humans=0 end
    if type(entries) ~= "table" then return counts end
    for i = 1, table.getn(entries) do
        local entry = entries[i]
        if C.IsFilledEntry(entry) then
            -- Hire footer excludes explicit humans, never guesses that an
            -- unresolved guest/companion is a player. Other callers stay unchanged.
            if companionsOnly and C.IsPlayerEntry(entry) then counts.humans=counts.humans+1
            elseif counts[entry.role] then counts[entry.role]=counts[entry.role]+1 end
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
        if save and entries[index] and not C.IsRandomHire(entries[index]) and (entries[index].kind == "normal" or entries[index].kind == "guest") then
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
            elseif not C.IsRandomHire(entry) then
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
            if C.IsFilledEntry(entry) and (not slotName[i]) and entry.kind ~= "player" and entry.kind ~= "legacy" and not C.IsRandomHire(entry) then
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
        if C.IsFilledEntry(entry) and not C.IsRandomHire(entry) and (not slotName[i]) and C.NameInRoster(roster, entry.companionName) then
            assignSlot(i, entry.companionName, C.RaidSlotGroup(i), false)
        end
    end
    if type(roster) == "table" then
        for i = 1, table.getn(entries) do
            local entry = entries[i]
            if C.IsFilledEntry(entry) and not C.IsRandomHire(entry) and (not slotName[i]) then
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
    -- A roster name or detected join alone cannot prove a random hire's class,
    -- role or owner. Only unused, present GRINFO records may fill these slots.
    for _, slot in ipairs(C.NormalHireSlots(entries)) do
        local entry = entries[slot]
        if C.IsRandomHire(entry) then
            for _, row in ipairs(type(info) == "table" and info or {}) do
                if C.NormalHireMatchesInfo(entry, row) and ((not roster) or table.getn(roster) == 0 or C.NameInRoster(roster, row.name)) then
                    if assignSlot(slot, row.name, C.RaidSlotGroup(slot), false) then break end
                end
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
    -- Canonicalize an exact known name only. Seven-letter prefixes are labels,
    -- never evidence that one of several full characters owns this row.
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
    if entry.class=="random" and not C.BuildNormalHireCommand(entry) then return nil end
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
    if out.class=="random" then return out end
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
    s.quoteOut=nil; s.quoteSeen=nil; s.quoteHelloAt=nil
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

-- Whether the plan sends any whisper to these rows (slot -> entry): a legacy row's own
-- commands, or a deny or setup rule naming a row's class and role.
function C.RowsNeedCommands(plan,own)
    local subset={entries={},denyRules=plan.denyRules,setupRules=plan.setupRules}
    local companions={}
    for i=1,40 do
        subset.entries[i]=own[i] or {kind="empty"}
        if own[i] then table.insert(companions,{name="row" .. i,class=C.NormalizeClassLabel(own[i].class),role=C.NormalizeRoleLabel(own[i].role)}) end
    end
    for _,item in ipairs(C.BuildWhisperQueue(subset)) do
        if item.phase=="role-class-final" or item.phase=="class-setup" then
            if table.getn(C.MatchCompanionsScoped(companions,item.class,item.role,item.spec))>0 then return true end
            for _,entry in pairs(own) do
                for _,role in ipairs({"tank","healer","mdps","rdps"}) do
                    if (item.role=="all" or C.NormalizeRoleLabel(item.role)==role)
                        and C.RandomHireAllowsRole(entry,item.class,role) then return true end
                end
            end
        else return true end
    end
    return false
end

-- The plan as Execute must act on it: a legacy row already in the group (present) that gets
-- no whisper needs nothing from any account, so it is left out. Only for choosing actors.
function C.PlanWithoutSettled(plan,present)
    local out={entries={},denyRules=plan.denyRules,setupRules=plan.setupRules}
    local slots=C.PresentLegacySlots(plan.entries,present)
    for i=1,40 do
        local e=plan.entries[i]
        if slots[i] and not C.RowsNeedCommands(plan,{[i]=e}) then e={kind="empty"} end
        out.entries[i]=e
    end
    return out
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
    local function needs(own) return C.RowsNeedCommands(plan,own) end
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

-- Presentation only. Recognize a whole bounded packet, its direction and a saved
-- peer approval; never touch live protocol state or use display as authorization.
-- Saved approval also keeps late/duplicate packets quiet after a run has ended.
function C.IsHandoffChatMessage(chatEvent,text,other,you,realm,links)
    if (chatEvent~="CHAT_MSG_WHISPER" and chatEvent~="CHAT_MSG_WHISPER_INFORM")
        or type(text)~="string" or string.len(text)>240 or string.sub(text,1,3)~="SRB"
        or type(other)~="string" or type(you)~="string" or type(realm)~="string" then return false end
    if C.QuoteParse(text) then
        -- Quote envelopes use the whisper's own direction/realm, not redundant
        -- labels. This is display-only; QuoteBound still validates the live link.
        return C.IsSafeCharacterName(other) and C.IsSafeCharacterName(you) and C.LinkKnown(links,you,other,realm)
    end
    local p=C.HandParse(text)
    if p then
        -- Chunk parsers also accept incomplete transfers. A non-final chunk is
        -- exactly 48 bytes; a single packet must hold a complete known message.
        if (p.index<p.total and string.len(p.data)~=48)
            or (p.total==1 and not C.HandDecode(p.data) and not C.HandShortParse(p.data)) then return false end
    else
        p=C.LinkParse(text)
        if p then
            if p.kind=="INVITE" or p.kind=="REJECT" then
                if p.b~="-" then return false end
            elseif p.b=="-" or p.b==p.a then return false end
        else p=C.LicenseParse(text) or C.RaidParse(text) or C.AccountParse(text) end
    end
    if not p or p.realm~=realm then return false end
    you=string.lower(you); other=string.lower(other)
    if chatEvent=="CHAT_MSG_WHISPER" then
        if p.sender~=other or p.target~=you then return false end
    elseif p.sender~=you or p.target~=other then return false end
    return C.LinkKnown(links,you,other,realm)
end

-- When one character hires from another on its account, the server may give either as the
-- companion's owner: the hire-from character, or the character that sent the hire (hirer).
-- This is the second case: NormalHireMatchesInfo with the hirer in the owner's place.
-- Callers reserve concrete rows first, exact owners before hirers in both pools.
function C.HandHiredBy(entry,record,hirer)
    if type(entry)~="table" or entry.kind~="normal" or not C.IsSafeCharacterName(hirer) then return false end
    if C.IsRandomHire(entry) and not C.BuildNormalHireCommand(entry) then return false end
    local hired={}; for key,value in pairs(entry) do hired[key]=value end
    hired.account=hirer
    return C.NormalHireMatchesInfo(hired,record)
end

-- Companions the run's earlier steps hired are not "already present" for a later step:
-- earlier concrete rows keep their reservations; earlier random rows take only records
-- the remaining concrete rows do not need. Commands steps hire nothing.
function C.HandUnclaimed(h,info)
    local used,out,concrete,pending,hirers,earlier={},{},{},{},{},{}
    for k,step in ipairs(h and h.steps or {}) do
        local first,last=C.HandStepSlots(step)
        for slot=first or 1,last or 0 do
            local entry=h.plan.entries[slot]
            hirers[slot]=step.actor
            if k<(h.step or 1) then
                earlier[slot]=true
                if not C.IsRandomHire(entry) then concrete[slot]=entry else pending[slot]=entry end
            else pending[slot]=entry end
        end
    end
    for _,row in pairs(C.MatchNormalHireEntries(concrete,info,hirers)) do used[string.lower(C.Trim(row.name))]=true end
    local free={}
    for _,row in ipairs(type(info)=="table" and info or {}) do
        if type(row)=="table" and not used[string.lower(C.Trim(row.name))] then table.insert(free,row) end
    end
    for slot,row in pairs(C.MatchNormalHireEntries(pending,free,hirers)) do
        if earlier[slot] then used[string.lower(C.Trim(row.name))]=true end
    end
    for _,row in ipairs(type(info)=="table" and info or {}) do
        if type(row)~="table" or not used[string.lower(C.Trim(row.name))] then table.insert(out,row) end
    end
    return out
end

-- The batch's own live companions, and the slots it could not place. A normal row's
-- companion is owned by its hire-from character: you, or one of this account's own
-- characters (own, lower-case name -> true, as HandOwnsSource); failing that, by you as
-- its hirer (HandHiredBy). A legacy row's companion is its -lite name: one you own in the
-- records, or, when the records do not list it, a present group member.
function C.HandScopeFound(entries,records,you,present,own)
    local chosen,missing,available,hirers,taken={},{},{},{},{}
    for _,row in ipairs(type(records)=="table" and records or {}) do
        if type(row)=="table" and C.HandOwnsSource(C.Trim(row.owner),you,you,own) then table.insert(available,row) end
    end
    for _,slot in ipairs(C.NormalHireSlots(entries)) do
        local entry=entries[slot]
        if not C.IsRandomHire(entry) or C.HandOwnsSource(entry.account,you,you,own) then hirers[slot]=you end
    end
    local matched=C.MatchNormalHireEntries(entries,available,hirers)
    for _,slot in ipairs(C.NormalHireSlots(entries)) do
        if matched[slot] then table.insert(chosen,matched[slot]) else table.insert(missing,slot) end
    end
    for slot,entry in pairs(entries) do
        if entry.kind=="legacy" then
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

-- Full planner: staged data only. No chat, live raid changes, trust or persistence here.
C.PLANNER_CLASSES={"warrior","hunter","rogue","priest","shaman","mage","warlock","druid","paladin"}
C.PLANNER_ROLES={"tank","healer","mdps","rdps"}
C.PLANNER_RACES={
    warrior={"orc","undead","tauren","troll","human","gnome","nightelf","dwarf"},
    hunter={"orc","tauren","troll","nightelf","dwarf"},rogue={"orc","undead","troll","human","gnome","nightelf","dwarf"},
    priest={"undead","troll","human","nightelf","dwarf"},shaman={"orc","tauren","troll"},mage={"undead","troll","human","gnome"},
    warlock={"orc","undead","human","gnome"},druid={"tauren","nightelf"},paladin={"human","dwarf"},
}

function C.PlannerCopy(value)
    if type(value)~="table" then return value end
    local out={}; for k,v in pairs(value) do out[k]=C.PlannerCopy(v) end; return out
end

function C.PlannerEqual(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not C.PlannerEqual(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end

function C.PlannerHas(values,value)
    for _,v in ipairs(values or {}) do if v==value then return true end end
    return false
end

-- Builder licence order follows BuildLicenseOptions: all dungeon tiers, then raid
-- tiers. Never sort token text or treat unknown licences as the base licence.
function C.PlannerTierRank(tier)
    for i,v in ipairs({"t0d","t1d","t2d","t3d","t4d","t5d","t1r","t2r","t3r","t4r","t5r"}) do
        if tier==v then return i-1 end
    end
end

function C.PlannerHighestTier(source)
    if not source or not source.eligible then return nil end
    local best,rank=nil,-1
    for _,tier in ipairs(source.tiers or {}) do
        local r=C.PlannerTierRank(tier)
        if r and r>rank then best=tier; rank=r end
    end
    return best
end

C.PLANNER_PRIORITY={"tank","mdps","mage","warlock","rdps","healer"}
C.PLANNER_PRIORITY_LABELS={tank="Tanks",mdps="Melee DPS",mage="Mage",warlock="Warlock",rdps="RDPS",healer="Healers"}

function C.PlannerAutoOrder()
    local out={}
    for _,bucket in ipairs(C.PLANNER_PRIORITY) do
        for _,class in ipairs(C.PLANNER_CLASSES) do
            for _,role in ipairs(C.PLANNER_ROLES) do
                if C.RoleAllowedForClass(class,role) and C.PlannerBucket({class=class,role=role})==bucket then table.insert(out,class..":"..role) end
            end
        end
    end
    return out
end

function C.PlannerValidPriority(order)
    if type(order)~="table" or table.getn(order)==0 then return nil end
    local seen,out,allowed={}, {}, {}
    local defaults=C.PlannerAutoOrder(); for _,id in ipairs(defaults) do allowed[id]=true end
    local bucketOrder=C.PLANNER_PRIORITY_LABELS[order[1]]~=nil
    local n=table.getn(order)
    for k,v in pairs(order) do
        if type(k)~="number" or k~=math.floor(k) or k<1 or k>n or type(v)~="string" or seen[v] then return nil end
        if not (bucketOrder and C.PLANNER_PRIORITY_LABELS[v] or not bucketOrder and allowed[v]) then return nil end
        seen[v]=true
    end
    for i=1,n do if type(order[i])~="string" then return nil end end
    if bucketOrder then
        -- Migrate the interim four/six-bucket order, expanding at its old position.
        if n~=4 and n~=6 then return nil end
        if not seen.tank or not seen.mdps or not seen.rdps or not seen.healer or (n==6 and (not seen.mage or not seen.warlock)) or (n==4 and (seen.mage or seen.warlock)) then return nil end
        for _,bucket in ipairs(order) do
            for _,id in ipairs(defaults) do
                local _,_,class,role=string.find(id,"^(%a+):(%a+)$")
                local b=C.PlannerBucket({class=class,role=role})
                if b==bucket or (n==4 and bucket=="rdps" and (b=="mage" or b=="warlock")) then table.insert(out,id) end
            end
        end
    else
        for _,id in ipairs(order) do table.insert(out,id) end
        -- New supported combinations append in stable Auto order; stale/duplicate IDs
        -- reject the whole order rather than silently dropping a priority.
        for _,id in ipairs(defaults) do if not seen[id] then table.insert(out,id) end end
    end
    return out
end

function C.PlannerLoadPriority(state)
    local order=type(state)=="table" and C.PlannerValidPriority(state.customOrder)
    local mode=order and state.priorityMode=="custom" and "custom" or "auto"
    return mode,order or C.PlannerAutoOrder()
end

function C.PlannerPriorityOrder(request)
    local mode,order=C.PlannerLoadPriority(request)
    return mode=="custom" and order or C.PlannerAutoOrder()
end

function C.PlannerPriorityLabel(id)
    if C.PLANNER_PRIORITY_LABELS[id] then return C.PLANNER_PRIORITY_LABELS[id] end
    local _,_,class,role=string.find(tostring(id),"^(%a+):(%a+)$")
    local label={tank="Tank",mdps="Melee DPS",rdps="Ranged DPS",healer="Healer"}
    if class and label[role] then return string.upper(string.sub(class,1,1))..string.sub(class,2).." "..label[role] end
    return "Unknown priority"
end

function C.PlannerBucket(entry)
    if not entry then return nil end
    if entry.role=="rdps" then
        if entry.class=="mage" or entry.class=="warlock" then return entry.class end
        return "rdps"
    end
    if entry.role=="tank" or entry.role=="mdps" or entry.role=="healer" then return entry.role end
end

-- Preferences are inert choices, never ownership or spending authority. Realm and
-- both account identities stay separate from display labels and live endpoints.
function C.PlannerPreferenceState(db,realm,create)
    if type(db)~="table" or not C.AccountIdentity(db.syncAccountId) or type(realm)~="string" or realm=="" then return nil end
    if type(db.plannerPreferences)~="table" or db.plannerPreferences.version~=1 then
        if not create then return nil end
        db.plannerPreferences={version=1,accounts={}}
    end
    local root=db.plannerPreferences
    if type(root.accounts)~="table" then if not create then return nil end; root.accounts={} end
    if type(root.accounts[db.syncAccountId])~="table" then if not create then return nil end; root.accounts[db.syncAccountId]={} end
    local account=root.accounts[db.syncAccountId]
    if type(account[realm])~="table" then if not create then return nil end; account[realm]={} end
    return account[realm]
end

function C.PlannerPreferenceIdentity(source)
    if type(source)~="table" or not C.AccountIdentity(source.accountId) or not C.IsSafeCharacterName(source.name) then return nil end
    return (source.localSource and "own:" or "linked:")..source.accountId..":"..string.lower(source.name)
end

function C.PlannerRestoreSources(db,realm,sources)
    local state=C.PlannerPreferenceState(db,realm,false)
    local saved=state and type(state.sources)=="table" and state.sources or {}
    local out,present,stale={}, {},0
    for _,source in ipairs(sources or {}) do
        local identity=C.PlannerPreferenceIdentity(source); if identity then present[identity]=true end
        local old=identity and type(saved[identity])=="table" and saved[identity] or {}
        local tier=C.PlannerTierRank(old.tier) and old.tier or C.PlannerHighestTier(source)
        local role=source.legacyClass and C.RoleAllowedForClass(source.legacyClass,old.legacyRole) and old.legacyRole or nil
        out[source.key]={selected=old.selected==true,includeLegacy=old.includeLegacy==true,tier=tier,legacyRole=role}
    end
    for identity,old in pairs(saved) do
        if not present[identity] and type(old)=="table" and (old.selected==true or old.includeLegacy==true) then stale=stale+1 end
    end
    return out,stale
end

function C.PlannerSaveSource(db,realm,source,selection)
    local identity=C.PlannerPreferenceIdentity(source)
    if not identity or type(selection)~="table" then return false end
    local state=C.PlannerPreferenceState(db,realm,true); if not state then return false end
    if type(state.sources)~="table" then state.sources={} end
    state.sources[identity]={selected=selection.selected==true,includeLegacy=selection.includeLegacy==true,
        tier=C.PlannerTierRank(selection.tier) and selection.tier or nil,
        legacyRole=source.legacyClass and C.RoleAllowedForClass(source.legacyClass,selection.legacyRole) and selection.legacyRole or nil}
    return true
end

function C.PlannerSavePriority(db,realm,request)
    local state=C.PlannerPreferenceState(db,realm,true); if not state then return false end
    state.priorityMode,state.customOrder=C.PlannerLoadPriority(request)
    return true
end

-- Uses only this account's established rows and validated trusted snapshots. Snapshot
-- licences describe planning choices, never authority to spend on an offline peer.
function C.PlannerSources(db,you,realm,ownRows,licenses,sessions,wall,clock)
    -- A partially restored live table must not hide remembered linked accounts.
    -- Validate before resolving identity; malformed or noncanonical claims add no authority.
    local trusted={}
    for _,pool in ipairs({type(db.peerSnapshots)=="table" and db.peerSnapshots or {},type(licenses)=="table" and licenses or {}}) do
        for key,raw in pairs(pool) do
            local copy=C.AccountSavedCopy(raw,you,realm,db.peerLinks)
            if copy and key==realm..";"..copy.source then
                local previous=trusted[key]
                if not previous or copy.received>previous.received or (copy.received==previous.received and copy.observed>=previous.observed) then trusted[key]=copy end
            end
        end
    end
    licenses=trusted
    local out,own,remote={}, {}, C.HandRemoteSources(licenses,db.peerLinks,you,realm,sessions,wall,clock)
    local byIdentity={}
    for _,e in ipairs(ownRows or {}) do
        local row=C.AccountRowCopy(e)
        if row then
            local key=string.lower(row.name); own[key]=true
            byIdentity["own:"..key]={key="own:"..key,name=row.name,accountId=db.syncAccountId,endpoint=you,localSource=true,record=row}
        end
    end
    for _,raw in pairs(licenses or {}) do
        local r=C.AccountSavedCopy(raw,you,realm,db.peerLinks)
        if r then
            for _,e in ipairs(r.entries) do
                local key=string.lower(e.name); local claim=remote[key]
                local identity=r.accountId..":"..key
                local current=byIdentity[identity]
                if not current or e.observed>current.record.observed or (e.observed==current.record.observed and r.source<(current.snapshotSource or "~")) then
                    local resolved=type(claim)=="table" and claim.accountId==r.accountId
                    byIdentity[identity]={key=identity,name=e.name,accountId=r.accountId,endpoint=resolved and claim.endpoint or nil,
                        record=C.PlannerCopy(e),received=r.received,snapshotSource=r.source,conflict=not resolved or own[key]==true}
                end
            end
        end
    end
    for _,s in pairs(byIdentity) do
        local key=string.lower(s.name)
        s.faction=C.KnownFaction(s.record.faction); s.capacity=4
        s.legacyClass=C.LegacyCharacterClass(db,s.name)
        s.legacyRole=s.legacyClass and C.LegacyCharacterRole(db,s.name,s.legacyClass)
        local d,r=s.record.dungeonLicense,s.record.raidLicense
        if d~="unknown" and r~="unknown" and C.LicenseTokens(d,r) then s.tiers=C.BuildLicenseOptions(d,r) end
        s.freshness="remembered"
        -- AccountReadLocal may seed an observation timestamp from a remembered list.
        -- Age describes the stored record, not fresh server eligibility or spend consent.
        if type(wall)=="number" and s.record.observed<=wall and wall-s.record.observed<=300 then s.freshness="recent record; eligibility not live-checked" end
        s.live=false
        if not s.localSource then
            for _,session in pairs(sessions or {}) do
                local state=session.state
                if state and string.lower(state.peer or "")==string.lower(s.endpoint or "")
                    and C.PlanAuthorized(state,db.peerLinks,wall,clock) and state.remoteLicense
                    and state.remoteLicense.accountId==s.accountId then s.live=true end
            end
        end
        -- The local server list may know a stricter remaining normal-hire budget.
        if s.localSource then
            for _,record in pairs(db.inviteCharacters or {}) do
                if type(record)=="table" and string.lower(C.Trim(record.name))==key then
                    if C.RaidNumber(record.count,0,40) and C.RaidNumber(record.maxCount,0,40) then
                        s.capacity=math.max(0,math.min(4,record.maxCount-record.count)); s.availabilityKnown=true
                    end
                end
            end
        end
        s.eligible=true
        if s.conflict or remote[key]==false or (own[key] and remote[key]~=nil) then s.conflict=true; s.eligible=false; s.reason="account identity is ambiguous"
        elseif not s.tiers then s.eligible=false; s.reason="licences unknown; refresh account data"
        elseif not s.faction then s.eligible=false; s.reason="faction unknown; refresh account data"
        elseif s.capacity<1 then s.eligible=false; s.reason="no known normal-hire capacity" end
        table.insert(out,s)
    end
    table.sort(out,function(a,b)
        if (a.localSource==true)~=(b.localSource==true) then return a.localSource==true end
        if a.accountId~=b.accountId then return tostring(a.accountId or "")<tostring(b.accountId or "") end
        if string.lower(a.name)~=string.lower(b.name) then return string.lower(a.name)<string.lower(b.name) end
        return a.key<b.key
    end)
    return out
end

-- User preferences, not claims about racial damage or server abilities. MCP's
-- normal-race selector explicitly supports Dwarf Paladins on this target.
function C.PlannerPreferredRace(faction,class,role)
    local choices
    if faction=="Alliance" then
        choices={warrior="human",mage="gnome",warlock="gnome",hunter="nightelf",druid="nightelf",rogue="human"}
        if role=="healer" then choices.priest="dwarf";choices.paladin="dwarf" end
    elseif faction=="Horde" then
        choices={warlock="orc",mage="troll",hunter="troll",rogue="troll"}
        if class=="warrior" then choices.warrior=role=="tank" and "undead" or "orc" end
        if role=="healer" then choices.shaman="troll" end
    end
    local race=choices and choices[class]
    if C.PlannerHas(C.PLANNER_RACES[class],race) then return race end
end

function C.PlannerRaceDefaults(base,preferences)
    local out={}
    for _,class in ipairs(C.PLANNER_CLASSES) do out[class]={race="auto",spec="auto",roles={},captured={}} end
    -- Preserve each captured concrete choice for its full source/class/role,
    -- including mixed races. Only additional rows use the missing preferred default.
    for _,e in ipairs(base.entries or {}) do
        if e.kind=="normal" and out[e.class] and C.RoleAllowedForClass(e.class,e.role) and C.PlannerHas(C.PLANNER_RACES[e.class],e.race) then
            local d=out[e.class];local key=string.lower(e.account or "")..":"..e.role
            d.captured[key]=d.captured[key] or {};table.insert(d.captured[key],e.race)
        end
    end
    local saved=type(preferences)=="table" and preferences.raceDefaults
    if type(saved)~="table" then saved={} end
    for class,d in pairs(saved) do
        if out[class] and type(d)=="table" then
            if d.race=="auto" or C.PlannerHas(C.PLANNER_RACES[class],d.race) then out[class].race=d.race end
            for role,race in pairs(type(d.roles)=="table" and d.roles or {}) do
                if C.RoleAllowedForClass(class,role) and (race=="auto" or C.PlannerHas(C.PLANNER_RACES[class],race)) then out[class].roles[role]=race end
            end
        end
    end
    return out
end

function C.PlannerNormal(source,class,role,request,index)
    local defaults=type(request.defaults)=="table" and request.defaults[class] or {}
    defaults=type(defaults)=="table" and defaults or {}
    local chosen
    if type(defaults.roles)=="table" then chosen=defaults.roles[role] end
    if chosen==nil or chosen=="auto" then chosen=defaults.race or request.race end
    if chosen==nil or chosen=="auto" then
        local captured=type(defaults.captured)=="table" and defaults.captured[string.lower(source.name or "")..":"..role]
        if type(captured)=="table" then chosen=captured[index or 1] else chosen=nil end
    end
    if chosen==nil or chosen=="auto" then chosen=C.PlannerPreferredRace(source.faction,class,role) end
    request={race=chosen,spec=defaults.spec or request.spec,gender=defaults.gender or request.gender}
    if not C.RoleAllowedForClass(class,role) or not C.KnownFaction(source.faction) or not C.ClassAllowedForFaction(class,source.faction) then return nil end
    local race
    for _,r in ipairs(C.PLANNER_RACES[class] or {}) do
        local alliance=r=="human" or r=="dwarf" or r=="gnome" or r=="nightelf"
        if (alliance and source.faction=="Alliance") or (not alliance and source.faction=="Horde") then
            if request.race==nil or request.race=="auto" or request.race==r then race=r; break end
        end
    end
    if not race then return nil end
    local specs=C.SpecsForClassRole(class,role) or (class=="mage" and {"frost","fire","arcane"}) or {"default"}
    local spec=request.spec
    -- Only Mage/Paladin have a class profile choice. Hidden stale preferences must
    -- not force other classes (or a healing Paladin) away from their sole default.
    if (class~="mage" and class~="paladin") or (class=="paladin" and role=="healer") then spec="default" end
    if spec==nil or spec=="auto" then spec=specs[1] end
    if not C.PlannerHas(specs,spec) then return nil end
    local gender=request.gender or "male"
    if gender~="male" and gender~="female" then return nil end
    return {kind="normal",account=source.name,tier=source.chosenTier,class=class,role=role,spec=spec,race=race,gender=gender}
end

-- Lexicographic costs keep bucket/atomic priorities exact without huge numeric
-- weights: fewest fourth hires, each tier priority, then same-tier source balance.
-- Residual paths still repair faction/race bottlenecks; chosen tiers never change.
function C.PlannerCostAdd(a,b)
    local out={}; for i=1,table.getn(a) do out[i]=a[i]+b[i] end; return out
end

function C.PlannerCostLess(a,b)
    if not b then return true end
    for i=1,table.getn(a) do if a[i]~=b[i] then return a[i]<b[i] end end
    return false
end

-- Read-only quote protocol v1. The real whisper sender, current player/realm,
-- saved approval and BOTH live link nonces bind the envelope. Account IDs are
-- opaque approved peer claims, never server account authentication. No commands
-- or executable payloads travel here. Split prices/metadata to stay <=240 bytes.
function C.QuoteParse(text)
    if type(text)~="string" or string.len(text)>240 then return nil end
    local f={}; for v in string.gfind(text..";","([^;]*);") do table.insert(f,v) end
    if table.getn(f)~=10 or f[1]~="SRBQUOTE1" or not C.PeerNonce(f[3]) or not C.PeerNonce(f[4]) or f[3]==f[4]
        or not C.PeerNonce(f[5]) or not C.AccountIdentity(f[6]) or not C.AccountIdentity(f[7]) or f[6]==f[7]
        or not C.IsSafeCharacterName(f[8]) or not C.PlannerTierRank(f[9]) then return nil end
    local p={kind=f[2],a=f[3],b=f[4],nonce=f[5],requester=f[6],owner=f[7],name=f[8],tier=f[9],data=f[10]}
    if p.kind=="H" or p.kind=="G" or p.kind=="C" then if p.data~="-" then return nil end
    elseif p.kind=="A" then if p.data~="1" then return nil end
    elseif p.kind=="E" then
        if not ({BUSY=true,MCP=true,TIMEOUT=true,ACCOUNT=true,SOURCE=true,STALE=true,RATE=true,SIZE=true,INVALID=true})[p.data] then return nil end
    elseif p.kind=="P" then
        local _,_,base,ex,qbase,qex=string.find(p.data,"^(%d+):(%d+):(%d+):(%d+)$")
        if not base then return nil end
        p.price={base=tonumber(base),ex=tonumber(ex),qbase=tonumber(qbase),qex=tonumber(qex)}
        for _,v in pairs(p.price) do if not C.RaidNumber(v,0,2147483647) then return nil end end
    elseif p.kind=="M" then
        local _,_,mask,friendly,count,maximum,observed=string.find(p.data,"^(%w+):(%w+):(%d+):(%d+):(%d+)$")
        if not mask or string.len(mask)>12 or string.len(friendly)>12 then return nil end
        p.meta={mask=mask,friendly=friendly,count=tonumber(count),max=tonumber(maximum),observed=tonumber(observed)}
        if not C.RaidNumber(p.meta.count,0,40) or not C.RaidNumber(p.meta.max,0,40) or p.meta.count>p.meta.max
            or not C.RaidNumber(p.meta.observed,1,2147483647) then return nil end
    else return nil end
    return p
end

function C.QuotePacket(s,kind,w,data)
    if not s or not w then return nil end
    local text=table.concat({"SRBQUOTE1",kind,s.a or "-",s.b or "-",w.nonce or "-",w.requester or "-",w.owner or "-",w.name or "-",w.tier or "-",data or "-"},";")
    if C.QuoteParse(text) then return text end
end

function C.QuoteSame(a,b)
    return a and b and a.nonce==b.nonce and a.requester==b.requester and a.owner==b.owner
        and string.lower(a.name or "")==string.lower(b.name or "") and a.tier==b.tier
end

-- Exact installed MCP COST:INVITE schema. It quotes the NEXT hire only; no
-- subsequent count curve, per-account multiplier or total-price formula is known.
function C.PlannerQuoteParse(message)
    if type(message)~="string" or string.len(message)>240 then return nil end
    local _,_,name,base,extra,mask,friendly,qbase,qextra,count,maximum=string.find(message,"^%[nexus%] ACINFO:COST:INVITE ([^:%s]+):(%d+):(%d+):(%w+):(%w+):(%d+):(%d+):(%d+):(%d+)$")
    if not C.IsSafeCharacterName(name) or not mask or string.len(mask)>12 or string.len(friendly)>12 then return nil end
    local q={name=name,base=tonumber(base),ex=tonumber(extra),mask=mask,friendly=friendly,qbase=tonumber(qbase),qex=tonumber(qextra),count=tonumber(count),max=tonumber(maximum)}
    for _,field in ipairs({"base","ex","qbase","qex"}) do if not C.RaidNumber(q[field],0,2147483647) then return nil end end
    if not C.RaidNumber(q.count,0,40) or not C.RaidNumber(q.max,0,40) or q.count>q.max then return nil end
    return q
end

-- Actual discounted next quotes do not establish later effective discounts.
-- Reputation depends on source character and chosen race. Keep every future
-- discounted amount unknown rather than carrying a current discount forward.
function C.PlannerQuoteMarginal(q,price,offset)
    if type(q)~="table" or offset~=0 or not C.RaidNumber(price,0,2147483647)
        or not C.RaidNumber(q.count,0,40) or not C.RaidNumber(q.max,1,40) or q.count>=q.max then return nil end
    return price
end

-- Match MCP_CostPick/MCP_QuickCost without reading or changing MCP globals.
function C.PlannerPricePick(q,row)
    if type(q)~="table" or type(row)~="table" or type(q.mask)~="string" then return nil end
    local exalted=false
    -- Saved role-only Quick rows leave race unset; the selector's random token
    -- is also accepted as a query context, never persisted as a concrete race.
    local quick=row.class=="random"
    if quick and row.race~=nil and row.race~="random" then return nil end
    if quick then
        if type(q.friendly)~="string" or q.friendly=="" then return nil end
        exalted=q.friendly~="0"
        for i=1,string.len(q.friendly) do
            if not string.find(q.mask,string.sub(q.friendly,i,i),1,true) then exalted=false end
        end
    else
        local digits={human="1",orc="2",dwarf="3",nightelf="4",undead="5",tauren="6",gnome="7",troll="8"}
        local digit=digits[row.race];if not digit then return nil end
        exalted=string.find(q.mask,digit,1,true)~=nil
    end
    local price
    if quick then if exalted then price=q.qex else price=q.qbase end
    else if exalted then price=q.ex else price=q.base end end
    if C.RaidNumber(price,0,2147483647) then return price end
end

function C.PlannerMoney(copper)
    if not C.RaidNumber(copper,0,85899345880) then return "unknown" end
    local gold=math.floor(copper/10000);local silver=math.floor(math.mod(copper,10000)/100);local small=math.mod(copper,100)
    local text={}
    if gold>0 then table.insert(text,gold.."g") end
    if silver>0 then table.insert(text,silver.."s") end
    if small>0 or table.getn(text)==0 then table.insert(text,small.."c") end
    return table.concat(text," ")
end

-- Empirical remaining marginal curve, calibrated to THIS source/selected race
-- and licence's fresh next quote. This is an estimate, not a future server quote.
-- Count belongs to the named character (MCP Invite row), never its whole account.
-- Only the observed four-normal scope is supported; no fifth-hire extrapolation.
function C.PlannerEstimateMarginal(q,price,offset)
    local curve={2,3,5,10} -- exactly 1 / 1.5 / 2.5 / 5 without float constants
    if type(q)~="table" or q.max~=4 or not C.RaidNumber(q.count,0,3)
        or not C.RaidNumber(offset,0,3) or q.count+offset>3 or not C.RaidNumber(price,0,2147483647) then return nil end
    local estimate=math.floor(price*curve[q.count+offset+1]/curve[q.count+1]+0.5)
    if C.RaidNumber(estimate,0,2147483647) then return estimate end
end

-- One metadata read per full source/licence used by the visible saved plan.
-- Row order is never rewritten; a licence change does not reset its hire ordinal.
function C.VisiblePriceRows(plan,sources)
    local names,rows,seen={}, {},{}
    for _,s in ipairs(sources or {}) do
        local name=string.lower(s.name or "")
        if names[name]~=nil then names[name]=false else names[name]=s end
    end
    for i=1,40 do
        local e=plan.entries[i]
        if e and e.kind=="normal" then
            local s=names[string.lower(e.account or "")]
            if s and s.eligible and not s.conflict and C.AccountIdentity(s.accountId)
                and C.IsSafeCharacterName(s.name) and C.PlannerHas(s.tiers,e.tier) and C.BuildNormalHireCommand(e) then
                local key=s.key..":"..e.tier
                if not seen[key] then
                    seen[key]=true;table.insert(rows,{source=C.PlannerCopy(s),tier=e.tier,key=key})
                end
            end
        end
    end
    return rows
end

function C.PlannerEstimate(result,sources,request)
    local byName,byKey,offsets,counts,bad={}, {},{}, {},{}
    local total={totalCopper=0,known=0,unknown=0,complete=true}
    for _,s in ipairs(sources or {}) do
        local key=string.lower(s.name or "")
        if byName[key]~=nil then byName[key]=false else byName[key]=s end
    end
    if request.planQuotes then
        for i=1,40 do
            local e=result.plan.entries[i]
            local s=e and e.kind=="normal" and byName[string.lower(e.account or "")]
            local q=s and request.planQuotes[s.key..":"..tostring(e.tier)]
            if type(q)=="table" then
                local old=counts[s.key]
                if old and (old.count~=q.count or old.max~=q.max) then bad[s.key]=true end
                counts[s.key]=q
            end
        end
    end
    for _,a in ipairs(result.allocation or {}) do a.estimatedCopper=0;a.priced=0;a.unpriced=0;byKey[a.key]=a end
    -- Final saved slot order is the order Execute sees. Offsets are per CHARACTER,
    -- including earlier unpriced rows, and continue across that character's tiers.
    for i=1,40 do
        local row=result.plan.entries[i]
        if row and row.kind=="normal" then
            local s=byName[string.lower(row.account or "")];local value
            local q=s and request.quotes and request.quotes[s.key]
            if s and request.planQuotes then q=request.planQuotes[s.key..":"..tostring(row.tier)] end
            local a=s and byKey[s.key]
            local offset=s and (offsets[s.key] or 0)
            if s then offsets[s.key]=offset+1 end
            if type(q)~="table" then q=nil end
            if q and not bad[s.key] then
                local tier=request.planQuotes and row.tier or s.chosenTier or (request.sources[s.key] and request.sources[s.key].tier)
                if q.accountId==s.accountId and string.lower(q.name or "")==string.lower(s.name) and q.tier==tier and row.tier==tier
                    and (not request.planQuotes or (not s.conflict and s.eligible and C.PlannerHas(s.tiers,tier) and C.BuildNormalHireCommand(row)))
                    and type(request.quoteNow)=="number" and type(q.received)=="number" and request.quoteNow>=q.received and request.quoteNow-q.received<=30 then
                    value=C.PlannerEstimateMarginal(q,C.PlannerPricePick(q,row),offset)
                end
            end
            if value~=nil then
                total.totalCopper=total.totalCopper+value;total.known=total.known+1
                if a then a.estimatedCopper=a.estimatedCopper+value;a.priced=a.priced+1 end
            else
                total.unknown=total.unknown+1;total.complete=false
                if a then a.unpriced=a.unpriced+1 end
            end
        end
    end
    result.estimate=total;return total
end

function C.PlannerQuotedPrice(source,jobs,request)
    if not request.quotes or table.getn(jobs)==0 then return nil end
    local q=request.quotes[source.key]
    if type(q)~="table" or string.lower(q.name or "")~=string.lower(source.name) or q.tier~=source.chosenTier or q.accountId~=source.accountId
        or type(request.quoteNow)~="number" or type(q.received)~="number" or request.quoteNow<q.received or request.quoteNow-q.received>30
        or not C.RaidNumber(q.count,0,40) or not C.RaidNumber(q.max,0,40) or q.count>=q.max then return nil,"A selected character's price/count is missing, stale or changed. Build again to check prices." end
    local price,prices=nil,{}
    for _,job in ipairs(jobs) do
        local row=C.PlannerNormal(source,job.class,job.role,request)
        if row then
            local cost=C.PlannerPricePick(q,row)
            if cost==nil then return nil,"The server quote does not describe this race/price safely." end
            prices[job.class..":"..job.role]=cost
            price=price and math.min(price,cost) or cost
        end
    end
    return price,nil,math.max(0,math.min(4,q.max-q.count)),prices
end

function C.PlannerAllocate(jobs,sources,request)
    local graph={}
    local order=C.PlannerPriorityOrder(request)
    local priority={}; for i,id in ipairs(order) do priority[id]=i+12 end
    local zero={}; for i=1,table.getn(order)+16 do zero[i]=0 end
    for _,source in ipairs(sources) do
        local price,why,capacity,prices=C.PlannerQuotedPrice(source,jobs,request)
        if why then return nil,why end
        source.nextPrice=price;source.nextPrices=prices;source.quoteCount=0
        local q=request.quotes and request.quotes[source.key]
        if q and q.max==4 then source.quoteCount=q.count end
        if capacity then source.capacity=math.min(source.capacity or 4,capacity) end
    end
    local bestRank=0; for _,s in ipairs(sources) do bestRank=math.max(bestRank,C.PlannerTierRank(s.chosenTier) or 0) end
    local sink=2+table.getn(jobs)+table.getn(sources)
    for i=1,sink do graph[i]={} end
    local function edge(a,b,capacity,cost)
        local reverse={}; for i=1,table.getn(cost) do reverse[i]=-cost[i] end
        local x={to=b,cap=capacity,cost=cost,rev=table.getn(graph[b])+1}
        local y={to=a,cap=0,cost=reverse,rev=table.getn(graph[a])+1}
        table.insert(graph[a],x); table.insert(graph[b],y); return x
    end
    local links,total={},0
    for i,job in ipairs(jobs) do
        edge(1,1+i,job.count,zero); links[i]={}; total=total+job.count
        for j,source in ipairs(sources) do
            if C.PlannerNormal(source,job.class,job.role,request) then
                local cost=C.PlannerCopy(zero)
                local rank=C.PlannerTierRank(source.chosenTier) or 0
                cost[12-rank]=-1 -- strongest chosen licences first, then the next
                cost[priority[job.class..":"..job.role]]=bestRank-rank
                -- Source/race-specific NEXT-price benchmark, never a later-hire
                -- estimate or promised total. Quality priorities remain first.
                cost[table.getn(cost)-2]=source.nextPrices and source.nextPrices[job.class..":"..job.role] or 0
                links[i][j]=edge(1+i,1+table.getn(jobs)+j,job.count,cost)
            end
        end
    end
    for j,s in ipairs(sources) do
        for n=1,math.min(4,s.capacity or 4) do
            local cost=C.PlannerCopy(zero)
            local fourth=s.quoteCount+n==4
            cost[1]=request.saveGold~=false and fourth and 1 or 0
            -- Prefer covering actual next-quote ordinals before unknown later
            -- ordinals; next-price benchmarks on job edges break remaining ties.
            cost[table.getn(cost)-3]=s.nextPrice~=nil and n>1 and 1 or 0
            cost[table.getn(cost)-1]=fourth and 1 or 0
            cost[table.getn(cost)]=n-1
            edge(1+table.getn(jobs)+j,sink,1,cost)
        end
    end
    for sent=1,total do
        local dist,from,which={[1]=zero},{},{}
        for pass=1,sink-1 do
            local changed=false
            for a=1,sink do
                if dist[a] then
                    for k,e in ipairs(graph[a]) do
                        if e.cap>0 then
                            local candidate=C.PlannerCostAdd(dist[a],e.cost)
                            if C.PlannerCostLess(candidate,dist[e.to]) then
                                dist[e.to]=candidate; from[e.to]=a; which[e.to]=k; changed=true
                            end
                        end
                    end
                end
            end
            if not changed then break end
        end
        if not dist[sink] then return nil,"Selected sources cannot supply the requested counts at those tiers/factions/race/spec settings (maximum four normals per source). Select more eligible sources or reduce counts." end
        local at=sink
        while at~=1 do
            local a=from[at]; local e=graph[a][which[at]]
            e.cap=e.cap-1; graph[at][e.rev].cap=graph[at][e.rev].cap+1; at=a
        end
    end
    local rows,allocation={},{}
    for j,s in ipairs(sources) do allocation[j]={key=s.key,name=s.name,tier=s.chosenTier,count=0} end
    for i,job in ipairs(jobs) do
        for j,s in ipairs(sources) do
            local e=links[i][j]
            local count=e and graph[e.to][e.rev].cap or 0
            allocation[j].count=allocation[j].count+count
            local price=s.nextPrices and s.nextPrices[job.class..":"..job.role]
            if count>0 and price~=nil then
                local a=allocation[j]
                a.nextMin=a.nextMin and math.min(a.nextMin,price) or price
                a.nextMax=a.nextMax and math.max(a.nextMax,price) or price
            end
            for n=1,count do
                local row=C.PlannerNormal(s,job.class,job.role,request,n)
                if not row then return nil,"A captured race is no longer valid for its source/class/role. Choose a valid race before Build." end
                table.insert(rows,row)
            end
        end
    end
    for j,s in ipairs(sources) do
        local a=allocation[j];a.fourth=a.count>0 and s.quoteCount+a.count==4
        a.nextPrice=a.nextMin==a.nextMax and a.nextMin or nil;a.existingCount=s.quoteCount

    end
    return rows,allocation
end

-- Price the actual grouped slot order. Ultra changes only a normal row's
-- selected source/licence and its valid defaults; class/role and every slot stay.
function C.PlannerUltraMetrics(entries,sources,request)
    local result={plan={entries=entries},allocation={}};local names={}
    for _,s in ipairs(sources) do
        local q=request.quotes[s.key]
        local a={key=s.key,name=s.name,tier=s.chosenTier,count=0,existingCount=q.count}
        names[string.lower(s.name)]={source=s,allocation=a};table.insert(result.allocation,a)
    end
    for i=1,40 do
        local e=entries[i];local item=e and e.kind=="normal" and names[string.lower(e.account or "")]
        if item then
            local a=item.allocation;a.count=a.count+1
            local price=C.PlannerPricePick(request.quotes[item.source.key],e)
            if price~=nil then a.nextMin=a.nextMin and math.min(a.nextMin,price) or price;a.nextMax=a.nextMax and math.max(a.nextMax,price) or price end
        end
    end
    for _,a in ipairs(result.allocation) do
        a.fourth=a.count>0 and a.existingCount+a.count==4
        a.nextPrice=a.nextMin==a.nextMax and a.nextMin or nil
    end
    C.PlannerEstimate(result,sources,request)
    return result,names
end

-- Reassign the whole normal composition for one exact source-count transfer.
-- Reuse the eligibility/priority flow, including its residual-path repair. The
-- class/role slots and all non-normal rows stay fixed, so grouping survives.
function C.PlannerUltraReassign(entries,sources,request,names,high,low,jobs)
    local limited={};local affected={}
    for _,source in ipairs(sources) do
        if source.chosenTier==high.chosenTier or source.chosenTier==low.chosenTier then
            local s=C.PlannerCopy(source);table.insert(limited,s);affected[string.lower(s.name)]=true
            s.capacity=names[string.lower(s.name)].allocation.count
            if s.key==high.key then s.capacity=s.capacity-1 end
            if s.key==low.key then s.capacity=s.capacity+1 end
        end
    end
    local rows=C.PlannerAllocate(jobs,limited,request)
    if not rows then return nil end
    local trial=C.PlannerCopy(entries);local used,pending={},{}
    -- Retain byte-equivalent generated rows in their original slots first,
    -- including different captured races for repeated source/class/role rows.
    for slot=1,40 do
        local e=entries[slot]
        if e and e.kind=="normal" and affected[string.lower(e.account or "")] then
            local matched=false
            for i,row in ipairs(rows) do
                if not used[i] and C.PlannerEqual(e,row) then used[i]=true;matched=true;break end
            end
            if not matched then table.insert(pending,slot) end
        end
    end
    for _,slot in ipairs(pending) do
        local old=entries[slot];local matched=false
        for i,row in ipairs(rows) do
            if not used[i] and row.class==old.class and row.role==old.role then
                trial[slot]=row;used[i]=true;matched=true;break
            end
        end
        if not matched then return nil end
    end
    return trial
end

function C.PlannerUltraApply(entries,sources,request)
    local bestRank=0
    for _,s in ipairs(sources) do
        local q=request.quotes and request.quotes[s.key]
        if type(q)~="table" or q.accountId~=s.accountId or string.lower(q.name or "")~=string.lower(s.name)
            or q.tier~=s.chosenTier or q.max~=4 or not C.RaidNumber(q.count,0,3)
            or type(q.received)~="number" or type(request.quoteNow)~="number"
            or request.quoteNow<q.received or request.quoteNow-q.received>30 then
            return nil,"Ultra gold saving needs fresh discounted prices and the current four-hire count for every selected character. Build again; no licence was changed."
        end
        bestRank=math.max(bestRank,C.PlannerTierRank(s.chosenTier) or 0)
    end
    local current,names=C.PlannerUltraMetrics(entries,sources,request)
    if not current.estimate.complete then return nil,"Ultra gold saving cannot compare every selected race and remaining hire order safely. Build again to check prices." end
    local stats={replacements=0,savedCopper=0,reassignedRows=0,candidates=0,priorityBlocked=0,notCheaper=0};local before=current.estimate.totalCopper
    local priority,jobs,counts={}, {},{}
    local custom=C.PlannerLoadPriority(request)=="custom"
    for i,id in ipairs(C.PlannerPriorityOrder(request)) do
        local _,_,class,role=string.find(id,"^(%a+):(%a+)$")
        local rank=i
        if not custom then
            local bucket=C.PlannerBucket({class=class,role=role})
            for j,value in ipairs(C.PLANNER_PRIORITY) do if value==bucket then rank=j end end
        end
        priority[id]=rank
    end
    for _,e in ipairs(entries) do
        if e.kind=="normal" and C.PlannerTierRank(e.tier)>=bestRank-1 then local id=e.class..":"..e.role;counts[id]=(counts[id] or 0)+1 end
    end
    for _,class in ipairs(C.PLANNER_CLASSES) do
        for _,role in ipairs(C.PLANNER_ROLES) do
            local count=counts[class..":"..role]
            if count then table.insert(jobs,{class=class,role=role,count=count}) end
        end
    end
    local allocationRequest=C.PlannerCopy(request);allocationRequest.saveGold=false
    -- Each accepted transfer removes one highest-licence fourth without creating
    -- another at that licence. Normal slots bound the number of accepted steps.
    for step=1,40 do
        local best,weakestPriority,highCounts,frontier=nil,0,{},nil
        for _,row in ipairs(entries) do
            if row.kind=="normal" and C.PlannerTierRank(row.tier)==bestRank then
                local rank=priority[row.class..":"..row.role]
                weakestPriority=math.max(weakestPriority,rank);highCounts[rank]=(highCounts[rank] or 0)+1
            end
        end
        local function consider(trial)
            if not trial then return end
            stats.candidates=stats.candidates+1
            local after={}
            for _,row in ipairs(trial) do
                if row.kind=="normal" and C.PlannerTierRank(row.tier)==bestRank then
                    local rank=priority[row.class..":"..row.role];after[rank]=(after[rank] or 0)+1
                end
            end
            if custom then
                -- Explicit class/role priority stays hard, including R4's case
                -- where only an earlier Tank move would save money.
                for rank,count in pairs(highCounts) do
                    if rank<weakestPriority and (after[rank] or 0)<count then stats.priorityBlocked=stats.priorityBlocked+1;return end
                end
            else
                -- Auto uses its six advertised groups. Find the strongest
                -- feasible distribution BEFORE comparing prices. A mandatory
                -- faction-locked healer can stay high without blocking others.
                local quality={};for rank=1,table.getn(C.PLANNER_PRIORITY) do quality[rank]=-(after[rank] or 0) end
                if not frontier or C.PlannerCostLess(quality,frontier) then frontier=quality;best=nil
                elseif C.PlannerCostLess(frontier,quality) then stats.priorityBlocked=stats.priorityBlocked+1;return end
            end
            local candidate=C.PlannerUltraMetrics(trial,sources,request)
            if candidate.estimate.complete and candidate.estimate.totalCopper<current.estimate.totalCopper then
                if not best or candidate.estimate.totalCopper<best.result.estimate.totalCopper then best={entries=trial,result=candidate} end
            else stats.notCheaper=stats.notCheaper+1 end
        end
        for _,high in ipairs(sources) do
            local highItem=names[string.lower(high.name)]
            if C.PlannerTierRank(high.chosenTier)==bestRank and highItem.allocation.fourth then
                for _,low in ipairs(sources) do
                    local item=names[string.lower(low.name)];local count=item.allocation.count
                    if low.key~=high.key and string.lower(low.name)~=string.lower(high.name) and low.eligible and not low.conflict
                        and C.PlannerTierRank(low.chosenTier)==bestRank-1
                        and count<math.min(low.capacity or 4,4-item.allocation.existingCount) then
                        -- Retain the cheap direct trials, including their actual
                        -- slot/race ordinals, then try a full residual reassignment.
                        for slot=40,1,-1 do
                            local e=entries[slot]
                            if e and e.kind=="normal" and string.lower(e.account or "")==string.lower(high.name)
                                and (not custom or priority[e.class..":"..e.role]==weakestPriority) then
                                local index=1
                                for _,old in ipairs(entries) do if old.kind=="normal" and old.account==low.name and old.class==e.class and old.role==e.role then index=index+1 end end
                                local row=C.PlannerNormal(low,e.class,e.role,request,index)
                                if row then local trial=C.PlannerCopy(entries);trial[slot]=row;consider(trial) end
                            end
                        end
                        consider(C.PlannerUltraReassign(entries,sources,allocationRequest,names,high,low,jobs))
                    end
                end
            end
        end
        if not best then break end
        for slot=1,40 do
            if not C.PlannerEqual(entries[slot],best.entries[slot]) then stats.reassignedRows=stats.reassignedRows+1 end
            entries[slot]=best.entries[slot]
        end
        current,names=C.PlannerUltraMetrics(entries,sources,request);stats.replacements=stats.replacements+1
    end
    stats.savedCopper=before-current.estimate.totalCopper
    return current.allocation,stats
end

function C.PlannerMelee(e)
    return C.IsFilledEntry(e) and (e.role=="tank" or e.role=="mdps")
end

function C.PlannerPhysical(e)
    return C.PlannerMelee(e) or (C.IsFilledEntry(e) and e.class=="hunter" and e.role=="rdps")
end

function C.PlannerCasterPreference(e)
    if not C.IsFilledEntry(e) or e.role~="rdps" or (e.class~="mage" and e.class~="warlock") then return 0 end
    if e.kind=="legacy" then return 1200 end
    if e.class=="mage" and e.spec=="fire" then return 240 end
    if e.class=="warlock" then return 50 end
    return 0 -- Unknown/default/frost Mage is never inferred to be Fire.
end

function C.PlannerPair(a,b)
    if not C.IsFilledEntry(a) or not C.IsFilledEntry(b) then return 0 end
    local score=0
    if (a.class=="shaman" and C.PlannerPhysical(b)) or (b.class=="shaman" and C.PlannerPhysical(a)) then score=score+30 end
    if a.class=="shaman" and b.class=="shaman" then score=score-70 end
    if (a.class=="warrior" and C.PlannerMelee(a) and b.role=="mdps") or (b.class=="warrior" and C.PlannerMelee(b) and a.role=="mdps") then score=score+22 end
    if a.role=="mdps" and b.role=="mdps" then score=score+6 end
    if a.class=="druid" and a.role=="rdps" then score=score+C.PlannerCasterPreference(b) end
    if b.class=="druid" and b.role=="rdps" then score=score+C.PlannerCasterPreference(a) end
    local ar=a.role=="rdps" and not C.PlannerPhysical(a)
    local br=b.role=="rdps" and not C.PlannerPhysical(b)
    local ah=a.role=="healer" and (a.class=="priest" or a.class=="paladin")
    local bh=b.role=="healer" and (b.class=="priest" or b.class=="paladin")
    if (ah and br) or (bh and ar) then score=score+20 end
    if ah and bh then score=score+(a.class==b.class and -90 or 8) end
    if (a.role=="tank" and b.role=="healer") or (b.role=="tank" and a.role=="healer") then score=score+6 end
    if a.role=="tank" and b.role=="tank" then score=score+((a.class=="warrior" and b.class=="warrior") and 80 or -8) end
    return score
end

function C.PlannerGroupScore(entries,group)
    local score,paladins,constrained=0,0,false
    for a=(group-1)*5+1,group*5 do
        local e=entries[a]
        if C.IsFilledEntry(e) then
            if C.PlannerMelee(e) and group<=4 then score=score+10000 end
            if not C.PlannerMelee(e) then score=score+group end
            if e.class=="paladin" and e.role=="healer" then paladins=paladins+1 end
            if C.PlannerPhysical(e) or e.role=="rdps" then constrained=true end
        end
        for b=a+1,group*5 do score=score+C.PlannerPair(e,entries[b]) end
    end
    -- Last fallback only: one healer Paladin in an otherwise unconstrained group.
    -- Specific physical/caster and Priest/Paladin ranged preferences score first.
    if not constrained and paladins>0 then score=score+3 end
    return score
end

-- Reserve support and occupied capacity before physical groups, caster bundles
-- and healer cover. No later score-based swap may undo an earlier constraint.
function C.PlannerReserveGroups(entries,pinned,groups)
    local out,locked,pool,empty,notes={}, {}, {}, {}, {}
    local limit,total=groups*5,0
    local function key(e)
        local parts={}
        for _,field in ipairs({"kind","class","role","sourceName","charName","account","tier","spec","race","gender","whisperName"}) do table.insert(parts,tostring(e[field] or "")) end
        return table.concat(parts,";")
    end
    for i=1,limit do
        local e=entries[i] or {kind="empty"}
        if C.IsFilledEntry(e) then total=total+1 end
        if pinned[i] then out[i]=e; locked[i]=true
        elseif C.IsFilledEntry(e) then table.insert(pool,{entry=e,index=i,key=key(e)})
        else table.insert(empty,e) end
    end
    table.sort(pool,function(a,b) if a.key~=b.key then return a.key<b.key end; return a.index<b.index end)
    local function count(g,match)
        local n=0; for i=(g-1)*5+1,g*5 do if C.IsFilledEntry(out[i]) and match(out[i]) then n=n+1 end end; return n
    end
    local function available(match)
        local n=0; for _,item in ipairs(pool) do if match(item.entry) then n=n+1 end end; return n
    end
    local function take(match)
        for i,item in ipairs(pool) do if match(item.entry) then table.remove(pool,i); return item.entry end end
    end
    local allowed=nil
    local function free(g)
        local n=0; for i=(g-1)*5+1,g*5 do if not out[i] and (not allowed or allowed[i]) then n=n+1 end end; return n
    end
    local function put(e,g,right)
        if not e then return nil end
        local first,last,step=(g-1)*5+1,g*5,1
        if right then first,last,step=last,first,-1 end
        for i=first,last,step do if not out[i] and (not allowed or allowed[i]) then out[i]=e; locked[i]=true; return i end end
        error("Staged grouping lost capacity")
    end
    local function shaman(e) return e.class=="shaman" end
    local shamans=available(shaman)
    for i,e in pairs(out) do
        if C.IsFilledEntry(e) and shaman(e) then
            shamans=shamans+1
            if math.mod(i,5)~=0 then table.insert(notes,"Fixed Shaman at slot "..i.." cannot move to the rightmost slot of group "..(math.floor((i-1)/5)+1)..".") end
        end
    end
    local function reserveShaman(g,required,normalFirst)
        if count(g,shaman)>0 then return end
        if free(g)==0 then
            if required then table.insert(notes,"Group "..g.." is full of fixed rows; its Shaman reservation is impossible.") end
            return
        end
        local e=normalFirst and take(function(v) return shaman(v) and v.kind=="normal" end) or nil
        e=e or take(shaman)
        if not e then
            if required then table.insert(notes,"Group "..g.." cannot receive a Shaman: remaining identities occupy fixed anchors elsewhere.") end
            return
        end
        local slot=put(e,g,true)
        if slot~=g*5 then table.insert(notes,"Fixed row at slot "..(g*5).." blocks the rightmost Shaman position in group "..g.."; used slot "..slot.." instead.") end
    end
    -- Reserve Group2's normal Shaman before Group1 can consume the sole one.
    if shamans>=2 and groups>=2 then reserveShaman(2,true,true) end
    for g=1,math.min(5,groups,shamans) do reserveShaman(g,true,false) end
    for g=1,groups do reserveShaman(g,false,g==2) end
    while available(shaman)>0 do
        local best,bestCount=nil,nil
        for g=1,groups do local n=count(g,shaman); if free(g)>0 and (not bestCount or n<bestCount) then best=g; bestCount=n end end
        assert(best,"Shaman reservation lost capacity"); put(take(shaman),best,true)
    end
    -- Fixed caster groups may extend the prefix; movable bundles may not.
    local function rebuildMask()
        allowed={};local reserved=0
        for i=1,limit do if C.IsFilledEntry(out[i]) then allowed[i]=true;reserved=reserved+1 end end
        for i=1,limit do if reserved<total and not out[i] then allowed[i]=true;reserved=reserved+1 end end
        assert(reserved==total,"Occupied prefix lost capacity")
    end
    rebuildMask()
    local function firstGroup(avoidTwo)
        for g=1,groups do if free(g)>0 and not (avoidTwo and g==2) then return g end end
        for g=1,groups do if free(g)>0 then return g end end
    end
    local function warriorTank(e) return e.class=="warrior" and e.role=="tank" end
    while free(1)>0 and available(warriorTank)>0 do put(take(warriorTank),1,false) end
    local function hunter(e) return e.class=="hunter" and e.role=="rdps" end
    local hunterGroup=groups>=2 and (available(hunter)>0 or count(2,hunter)>0)
    if hunterGroup then
        local function member(match,label)
            if count(2,match)>0 then return end
            if free(2)>0 and available(match)>0 then put(take(match),2,false)
            else table.insert(notes,"Group 2 Hunter preference lacks "..label.." or free capacity; no substitute hire was added.") end
        end
        member(hunter,"a Hunter")
        member(function(e) return e.class=="rogue" and e.role=="mdps" end,"a Rogue")
        local function feral(e) return e.class=="druid" and e.role=="mdps" end
        local function bear(e) return e.class=="druid" and e.role=="tank" end
        if count(2,feral)+count(2,bear)==0 then
            if available(feral)>0 then member(feral,"a feral Druid") else member(bear,"a feral/bear Druid") end
        end
        member(function(e) return e.kind=="normal" and e.class=="warrior" and e.role=="mdps" end,"a normal Warrior MDPS for Battle Shout")
    end
    local function balance(e) return e.class=="druid" and e.role=="rdps" end
    local function shadow(e) return e.class=="priest" and e.role=="rdps" end
    local function warlock(e) return e.class=="warlock" and e.role=="rdps" end
    local function fire(e) return e.class=="mage" and e.role=="rdps" and e.spec=="fire" end
    local function primaryRank(e)
        if not C.IsFilledEntry(e) or e.role~="rdps" then return 0 end
        if e.kind=="legacy" and e.class=="mage" then return 4 end
        if e.kind=="legacy" and warlock(e) then return 3 end
        if fire(e) then return 2 end
        if warlock(e) then return 1 end
        return 0
    end
    local function bundle(g,movable)
        local room=free(g)-(movable and 1 or 0)
        if room<0 then return nil end
        local primary,rank,fromPool=nil,0,false
        for i=(g-1)*5+1,g*5 do local r=primaryRank(out[i]);if r>rank then primary=out[i];rank=r end end
        if room>0 then
            for _,item in ipairs(pool) do local r=primaryRank(item.entry);if r>rank then primary=item.entry;rank=r;fromPool=true end end
        end
        local plan={rows={},rank=rank,extra=0,fire=0,primary=primary}
        if fromPool then table.insert(plan.rows,primary);room=room-1 end
        for i=(g-1)*5+1,g*5 do
            local e=out[i]
            if e and e~=primary and (fire(e) or warlock(e)) then plan.extra=plan.extra+1;if fire(e) then plan.fire=plan.fire+1 end end
        end
        for _,match in ipairs({fire,warlock}) do
            for _,item in ipairs(pool) do
                local e=item.entry
                if plan.extra<2 and room>0 and e~=primary and match(e) then
                    table.insert(plan.rows,e);plan.extra=plan.extra+1;room=room-1
                    if fire(e) then plan.fire=plan.fire+1 end
                end
            end
        end
        return plan
    end
    local function placeBalance(e,fixedGroup)
        -- Predict residual physical space without consuming those identities.
        local projected,left={},available(C.PlannerPhysical)
        for g=1,groups do projected[g]=math.min(free(g),left);left=left-projected[g] end
        local best,chosen,score=nil,nil,nil
        for g=1,groups do
            if not fixedGroup or fixedGroup==g then
                local plan=bundle(g,e~=nil)
                if plan then
                    local physical=count(g,function(v)return v.class~="shaman" and C.PlannerPhysical(v) end)
                    local s=plan.rank*100000000+math.min(2,plan.extra)*1000000+math.min(2,plan.fire)*100000
                        -physical*1000000-projected[g]*1000-(e and count(g,balance)*1000000000 or 0)
                        +(projected[g]>0 and g or -g)
                    if not score or s>score then best=g;chosen=plan;score=s end
                end
            end
        end
        if not best then table.insert(notes,"A fixed Balance Druid has no free caster capacity in its five-person group.");return end
        if e then put(e,best,false) end
        for _,row in ipairs(chosen.rows) do assert(take(function(v)return v==row end),"Caster identity already consumed");put(row,best,false) end
        if chosen.rank==0 or chosen.extra<2 then
            local name=e and (e.sourceName or e.charName or e.account) or "fixed Balance"
            table.insert(notes,"Balance caster group "..best.." ("..tostring(name)..") has "..(chosen.rank>0 and "a primary caster" or "no eligible primary caster").." and "..math.min(2,chosen.extra).." of two additional Fire Mage/Warlock positions. Supplied identities, stronger reservations and five-person capacity limit this block; no extra hire was added.")
        end
    end
    allowed=nil
    for g=1,groups do if count(g,balance)>0 then placeBalance(nil,g) end end
    rebuildMask()
    while available(balance)>0 do placeBalance(take(balance)) end
    -- Non-Warrior tanks gain no co-location bonus. Remaining physical rows use
    -- the earliest slots, including sensible spare positions in Group1.
    for _,match in ipairs({warriorTank,function(e) return e.role=="tank" end,C.PlannerPhysical}) do
        while available(match)>0 do
            local e=take(match)
            local avoid=hunterGroup and e.kind=="legacy" and e.class=="warrior" and e.role=="mdps"
            put(e,assert(firstGroup(avoid)),false)
        end
    end
    local lastPhysical=nil
    for g=1,groups do
        if count(g,function(e) return e.class~="shaman" and (e.role=="mdps" or hunter(e)) end)>0 then lastPhysical=g end
    end
    local function healer(class) return function(e) return e.class==class and e.role=="healer" end end
    if lastPhysical then
        for _,class in ipairs({"paladin","priest"}) do if free(lastPhysical)>0 and available(healer(class))>0 then put(take(healer(class)),lastPhysical,false) end end
    end
    -- Shadow receives only Warlocks left after complete Balance reservations.
    local function placeShadow(e,fixedGroup)
        local best,score=nil,nil
        for g=1,groups do if (not fixedGroup or fixedGroup==g) and free(g)>=(e and 1 or 0) then
            local room=free(g)-(e and 1 or 0)
            local n=count(g,warlock)+math.min(room,available(warlock))
            local physical=count(g,function(v) return v.class~="shaman" and C.PlannerPhysical(v) end)
            local s=n*1000000-physical*10000-count(g,shadow)*1000+free(g)*10-g
            if not score or s>score then best=g; score=s end
        end end
        if not best then return end
        if e then put(e,best,false) end
        while free(best)>0 and available(warlock)>0 do put(take(warlock),best,false) end
        if count(best,warlock)<4 then table.insert(notes,"Shadow Priest group "..best.." has "..count(best,warlock).." Warlock(s); available locks, earlier Balance partners and five-person capacity limit this deterministic allocation.") end
    end
    for g=1,groups do if count(g,shadow)>0 then placeShadow(nil,g) end end
    while available(shadow)>0 do placeShadow(take(shadow)) end
    local function ranged(e) return e.role=="rdps" and not C.PlannerPhysical(e) end
    for g=1,groups do if count(g,ranged)>0 then
        for _,class in ipairs({"priest","paladin"}) do if free(g)>0 and count(g,healer(class))==0 and available(healer(class))>0 then put(take(healer(class)),g,false) end end
    end end
    while available(ranged)>0 do
        local e=take(ranged); local best,score=nil,nil
        for g=1,groups do if free(g)>0 then
            local physical=count(g,function(v) return v.class~="shaman" and C.PlannerPhysical(v) end)
            local s=-physical*100000+count(g,balance)*C.PlannerCasterPreference(e)+count(g,healer("priest"))*20+count(g,healer("paladin"))*20-g
            if not score or s>score then best=g; score=s end
        end end
        put(e,assert(best),false)
        if count(best,ranged)==1 then
            for _,class in ipairs({"priest","paladin"}) do if free(best)>0 and count(best,healer(class))==0 and available(healer(class))>0 then put(take(healer(class)),best,false) end end
        end
    end
    for g=1,groups do
        if free(g)>0 and count(g,C.PlannerPhysical)==0 and count(g,healer("paladin"))==0 and available(healer("paladin"))>0 then put(take(healer("paladin")),g,false) end
    end
    while table.getn(pool)>0 do put(table.remove(pool,1).entry,assert(firstGroup()),false) end
    local at,lastMovable=1,0
    for i=1,limit do if C.IsFilledEntry(out[i]) and out[i].kind~="player" then lastMovable=i end end
    local gaps=0; for i=1,lastMovable do if not out[i] then gaps=gaps+1 end end
    if gaps>0 then table.insert(notes,gaps.." earlier empty slot(s) remain because fixed anchors or rightmost Shaman reservations require later occupied slots; compaction cannot fill them without breaking those constraints.") end
    for i=1,limit do
        if not out[i] then out[i]=assert(empty[at],"Grouping lost an empty slot"); at=at+1 end
        entries[i]=out[i]
    end
    assert(at-1==table.getn(empty),"Grouping duplicated an empty slot")
    return locked,notes
end

function C.PlannerGroup(entries,pinned,groups)
    local locked,notes=C.PlannerReserveGroups(entries,pinned,groups)
    local score=0; for g=1,groups do score=score+C.PlannerGroupScore(entries,g) end
    return {moves=0,score=score,notes=notes,staged=true}
end

-- Only explicit player rows identify humans. Captured guests may be unresolved
-- companions, so they keep their distinct type and are never guessed to be humans.
function C.PlannerPlaceHumans(entries,pinned,player,notes)
    local humans,seen={},{}
    for i=1,40 do
        local e=entries[i]
        if type(e)=="table" and e.kind=="player" then
            if not C.IsSafeCharacterName(e.charName) or not C.RoleAllowedForClass(e.class,e.role) then return nil,"A human row needs its full identity and verified class/role before planning." end
            local identity=string.lower(e.charName)
            if seen[identity] then return nil,"Duplicate human identity: "..e.charName..". Edit the plan before planning." end
            seen[identity]=true
            if identity~=string.lower(player.name) then table.insert(humans,{entry=e,index=i}) end
        end
    end
    table.sort(humans,function(a,b) return string.lower(a.entry.charName)<string.lower(b.entry.charName) end)
    for _,h in ipairs(humans) do entries[h.index]=nil; pinned[h.index]=nil end
    local displaced={}
    for n,h in ipairs(humans) do
        local dest=40-n
        if C.IsFilledEntry(entries[dest]) then table.insert(displaced,{entry=entries[dest],fixed=pinned[dest]}) end
        entries[dest]=h.entry; pinned[dest]=true
    end
    for _,v in ipairs(displaced) do
        local dest=C.FirstEmptySlot(entries,39-table.getn(humans))
        if not dest then return nil,"Human tail has no safe space for its displaced companion/anchor; the limit is 40." end
        entries[dest]=v.entry; pinned[dest]=v.fixed
        table.insert(notes,"Reserved human tail; moved its previous non-human occupant to slot "..dest.." in this proposal.")
    end
    return 40,notes
end

function C.PlannerPlacePlayer(entries,pinned,player)
    if type(player)~="table" or not C.IsSafeCharacterName(player.name) then return nil,"Current player identity is unavailable." end
    local role=C.NormalizeRoleForClass(player.class,player.role)
    if not C.RoleAllowedForClass(player.class,role) then return nil,"Current player class/role is unavailable." end
    local previous,oldSlot=nil,nil
    for i=1,40 do
        local e=entries[i]
        if C.IsFilledEntry(e) and (e.kind=="player" or e.kind=="guest") and string.lower(e.charName or e.companionName or "")==string.lower(player.name) then
            if not previous then previous=C.PlannerCopy(e); oldSlot=i end
            entries[i]=nil; pinned[i]=nil
        end
    end
    local notes={}
    if C.IsFilledEntry(entries[40]) then
        local dest=oldSlot and oldSlot<40 and oldSlot or C.FirstEmptySlot(entries,39)
        if not dest then return nil,"Slot 40 holds a fixed row and no slot is free for the current player; the limit is 40." end
        local e=entries[40]; entries[dest]=e; pinned[dest]=true
        table.insert(notes,"Reserved slot 40 for the current player; moved its fixed occupant to slot "..dest.." in this proposal. Review before saving.")
    end
    previous=previous or {}
    previous.kind="player"; previous.charName=player.name; previous.class=player.class
    previous.role=C.NormalizeRoleForClass(player.class,player.role or previous.role)
    entries[40]=previous; pinned[40]=true
    return C.PlannerPlaceHumans(entries,pinned,player,notes)
end

-- Count desired normals plus actual fixed/included identities without allocating
-- sources or guessing unknown legacy metadata. Used by the composition footer.
function C.PlannerCompositionTotals(base,sources,request)
    local out={total=0,normal=0,legacy=0,player=0,guest=0,unresolved=0,roles={tank=0,mdps=0,rdps=0,healer=0,dps=0}}
    local entries,seen={},{}
    for i,e in pairs(base.entries or {}) do
        if C.IsFilledEntry(e) and e.kind~="normal" then entries[i]=C.PlannerCopy(e) end
    end
    if request.player then local slot=C.PlannerPlacePlayer(entries,{},request.player); if not slot then out.unresolved=out.unresolved+1 end end
    for _,e in pairs(entries) do
        if C.IsFilledEntry(e) then
            out[e.kind]=(out[e.kind] or 0)+1; out.total=out.total+1
            if (e.kind=="normal" or e.kind=="legacy") and out.roles[e.role] then out.roles[e.role]=out.roles[e.role]+1 end
            if e.kind=="legacy" then seen[string.lower(C.GetLegacyHireName(e))]=true end
        end
    end
    for _,s in ipairs(sources or {}) do
        local sel=request.sources[s.key]
        if sel and sel.includeLegacy and not seen[string.lower(s.name)] then
            seen[string.lower(s.name)]=true; out.legacy=out.legacy+1; out.total=out.total+1
            local role=sel.legacyRole or s.legacyRole
            if not s.conflict and s.legacyClass and C.RoleAllowedForClass(s.legacyClass,role) and out.roles[role] then out.roles[role]=out.roles[role]+1 else out.unresolved=out.unresolved+1 end
        end
    end
    for _,class in ipairs(C.PLANNER_CLASSES) do
        for _,role in ipairs(C.PLANNER_ROLES) do
            local n=request.counts[class..":"..role] or 0
            if C.RoleAllowedForClass(class,role) and type(n)=="number" and n>=0 and n<=40 and n==math.floor(n) then
                out.normal=out.normal+n; out.total=out.total+n; out.roles[role]=out.roles[role]+n
            end
        end
    end
    return out
end

-- Draft companions come only from entered normals and selected legacies. Carried
-- saved rows still occupy slots, but do not silently become draft role totals.
function C.PlannerDraftTotals(base,sources,request)
    local draft=C.PlannerCompositionTotals({entries={}},sources,request)
    local occupied=C.PlannerCompositionTotals(base,sources,request)
    draft.saved={normal=0,legacy=0,humans=0}
    for _,e in pairs(base.entries or {}) do
        if C.IsFilledEntry(e) then
            if e.kind=="normal" or e.kind=="legacy" then draft.saved[e.kind]=draft.saved[e.kind]+1
            elseif e.kind=="player" or e.kind=="guest" then draft.saved.humans=draft.saved.humans+1 end
        end
    end
    draft.humans=occupied.player+occupied.guest
    draft.carriedLegacy=math.max(0,occupied.legacy-draft.legacy)
    draft.occupied=occupied.total
    draft.unresolved=draft.unresolved+occupied.unresolved
    return draft
end

function C.PlannerBuild(base,sources,request)
    if type(base)~="table" or type(base.entries)~="table" or type(request)~="table" or type(request.counts)~="table" or type(request.sources)~="table" then return nil,"Planner input is missing." end
    local result={plan=C.PlannerCopy(base),notes={},normal=0,legacy=0,player=0,guest=0,total=0,fourths=0,replaced=0}
    local entries,pinned,legacyNames,targets={}, {}, {}, {}
    local maxAnchor=0
    for key,e in pairs(base.entries) do
        if not C.RaidNumber(key,1,40) then return nil,"The existing profile exceeds the 40-slot board." end
        if C.IsFilledEntry(e) then
            if e.kind=="normal" then result.replaced=result.replaced+1
            elseif e.kind=="player" or e.kind=="guest" or e.kind=="legacy" then
                if not C.PlanEntry(e) then return nil,"An existing fixed row needs valid identity fields before planning." end
                entries[key]=C.PlannerCopy(e); pinned[key]=true; maxAnchor=math.max(maxAnchor,key)
                result[e.kind]=result[e.kind]+1; result.total=result.total+1
                if e.kind=="legacy" then
                    local name=string.lower(C.GetLegacyHireName(e)); local target=string.lower(C.GetLegacyWhisperName(e))
                    if not C.IsSafeCharacterName(name) or not C.BuildHireCommand(e) then return nil,"An existing legacy has only a shortened or unknown source identity; choose its actual full character first." end
                    if legacyNames[name] then return nil,"Existing legacy rows duplicate the same full source identity; edit them first." end
                    legacyNames[name]=e; targets[target]=name
                end
            else return nil,"Unsupported existing row; nothing can be replaced safely." end
        end
    end
    if request.player then
        local slot,notes=C.PlannerPlacePlayer(entries,pinned,request.player)
        if not slot then return nil,notes end
        result.plan.plannerPlayerSlot=40
        result.player=0; result.guest=0; result.legacy=0; result.total=0; maxAnchor=0
        for i,e in pairs(entries) do
            if C.IsFilledEntry(e) then result[e.kind]=result[e.kind]+1; result.total=result.total+1; maxAnchor=math.max(maxAnchor,i) end
        end
        for _,note in ipairs(notes) do table.insert(result.notes,note) end
    end
    local available={}; for _,s in ipairs(sources or {}) do available[s.key]=s end
    local chosen,newLegacy={},{}
    local keys={}; for key in pairs(request.sources) do table.insert(keys,key) end; table.sort(keys)
    for _,key in ipairs(keys) do
        local selection=request.sources[key]; local s=available[key]
        if selection.selected or selection.includeLegacy then
            if not s then return nil,"A selected source is no longer listed. Reopen the planner and refresh account data." end
            if s.conflict then return nil,s.name..": account identity is ambiguous." end
        end
        if selection.selected then
            if not s.eligible or not C.KnownFaction(s.faction) then return nil,s.name..": "..(s.reason or "eligibility is unknown").."." end
            if not C.PlannerHas(s.tiers,selection.tier) then return nil,s.name..": choose an available licence tier; no tier was upgraded." end
            local copy=C.PlannerCopy(s); copy.chosenTier=selection.tier; table.insert(chosen,copy)
        end
        if selection.includeLegacy then
            local class,role=s.legacyClass,selection.legacyRole or s.legacyRole
            if not class or not role or not C.RoleAllowedForClass(class,role) then return nil,s.name..": legacy class/role is missing or invalid. Choose a known legacy role or remember its class first." end
            local name=string.lower(s.name); local target=string.lower(C.NormalizeLegacyName(s.name))
            local anchor=legacyNames[name]
            if anchor then
                if anchor.class~=class or anchor.role~=role then return nil,s.name..": fixed legacy anchor has a different class/role. Edit that anchor first." end
            else
                if not C.IsSafeCharacterName(s.name) then return nil,"A selected legacy has no verified full source identity." end
                if targets[target] then table.insert(result.notes,"Distinct full sources "..s.name.." and "..targets[target].." share live alias "..C.NormalizeLegacyName(s.name)..". Planning keeps both identities; Execute must stop until their live targets can be distinguished safely.") end
                targets[target]=name
                local e={kind="legacy",sourceName=s.name,charName=s.name,class=class,role=role,spec="default",whisperName=C.NormalizeLegacyName(s.name),denyList={}}
                if not C.BuildHireCommand(e) then return nil,s.name..": legacy identity cannot be resolved safely." end
                table.insert(newLegacy,e); legacyNames[name]=e; result.legacy=result.legacy+1; result.total=result.total+1
            end
        end
    end
    table.sort(chosen,function(a,b) return a.key<b.key end)
    if table.getn(chosen)>256 then return nil,"Too many selected sources; select at most 256." end
    local jobs,valid={},{}
    for _,class in ipairs(C.PLANNER_CLASSES) do
        for _,role in ipairs(C.PLANNER_ROLES) do
            local key=class..":"..role
            if C.RoleAllowedForClass(class,role) then
                valid[key]=true; local count=request.counts[key] or 0
                if type(count)~="number" or count~=math.floor(count) or not (count>=0 and count<=40) then return nil,"Counts must be whole numbers from 0 to 40." end
                if count>0 then table.insert(jobs,{class=class,role=role,count=count}); result.normal=result.normal+count end
            end
        end
    end
    for key in pairs(request.counts) do if not valid[key] then return nil,"Unsupported class/role count: "..tostring(key) end end
    result.total=result.total+result.normal
    if result.total>40 then return nil,"The plan needs "..result.total.." slots including fixed players/guests/legacies; the limit is 40." end
    if result.normal>0 and table.getn(chosen)==0 then return nil,"Select eligible hire-from characters and a licence tier for each." end
    local allocationRequest=request
    if request.ultraGold==true then allocationRequest=C.PlannerCopy(request);allocationRequest.saveGold=false end
    local normal,allocation=C.PlannerAllocate(jobs,chosen,allocationRequest)
    if not normal then return nil,allocation end
    result.allocation=allocation
    for _,a in ipairs(allocation) do
        if a.fourth then result.fourths=result.fourths+1 end
        local s=available[a.key]
        if a.count>0 and not s.localSource and not s.live then table.insert(result.notes,a.name..": remembered linked data only; refresh its live link before Execute.") end
    end
    if request.ultraGold~=true then
        if result.fourths>0 then table.insert(result.notes,result.fourths..(request.saveGold~=false and " source(s) need a fourth normal hire to satisfy the exact counts." or " source(s) use a fourth normal hire under the highest-licence preference.").." No exact gold-price claim is made.") end
        table.insert(result.notes,request.saveGold~=false and "Save gold is on: avoid fourth hires when other selected, eligible licence capacity can satisfy the exact counts; then favor stronger chosen licences and class/role priority." or "Save gold is off: maximize the strongest selected licences, then each next licence, including fourth hires; class/role priority assigns their strongest tiers.")
    end
    if request.quotes and result.normal>0 then table.insert(result.notes,"Estimated costs use fresh character/licence next-hire prices, the selected race's reputation and the observed 1 / 1.5 / 2.5 / 5 hire progression. Later amounts assume that context stays unchanged and round to the nearest copper; final charges remain unknown until the server applies them. This is not a price lock or an exact cheapest-plan claim.") end
    local mode=C.PlannerLoadPriority(request)
    local priority={}; for _,id in ipairs(mode=="custom" and C.PlannerPriorityOrder(request) or C.PLANNER_PRIORITY) do table.insert(priority,C.PlannerPriorityLabel(id)) end
    table.insert(result.notes,"Tier priority: "..table.concat(priority," > ")..". "..(request.ultraGold==true and "Ultra keeps earlier roles at the stronger licence where eligible alternatives allow; " or request.saveGold~=false and "Preferred three normals per source comes first; " or "Highest chosen licences come first, including fourth hires; ").."eligibility, capacity and each chosen source tier can limit this order. No tier is upgraded.")
    for i=1,40 do if not entries[i] then entries[i]={kind="empty"} end end
    for _,list in ipairs({newLegacy,normal}) do
        for _,e in ipairs(list) do local slot=C.FirstEmptySlot(entries,40); entries[slot]=e end
    end
    maxAnchor=0
    for i,e in ipairs(entries) do
        if e.kind=="legacy" then pinned[i]=nil end
        if pinned[i] then maxAnchor=math.max(maxAnchor,i) end
    end
    local groups=math.max(math.ceil(result.total/5),math.ceil(maxAnchor/5))
    -- Old companion slots no longer set group bounds. Bring any such row into
    -- the proposed range before reservations so a sparse legacy cannot be missed.
    for i=groups*5+1,40 do
        if C.IsFilledEntry(entries[i]) then
            local dest=assert(C.FirstEmptySlot(entries,groups*5),"Proposed groups lost capacity")
            entries[dest],entries[i]=entries[i],entries[dest]
        end
    end
    result.grouping=C.PlannerGroup(entries,pinned,groups); result.score=result.grouping.score; result.groups=groups
    if request.ultraGold==true and result.normal>0 then
        local selected,stats=C.PlannerUltraApply(entries,chosen,request)
        if not selected then return nil,stats end
        result.allocation=selected;result.ultra=stats;result.fourths=0
        for _,a in ipairs(selected) do if a.fourth then result.fourths=result.fourths+1 end end
        if stats.replacements>0 then
            table.insert(result.notes,"Ultra gold saving: moved "..stats.replacements.." highest-licence fourth hire(s) to another selected character at the next lower chosen licence. Estimated saving versus the strongest-licence plan: "..C.PlannerMoney(stats.savedCopper)..".")
        else table.insert(result.notes,"Ultra gold saving: no cheaper eligible next-lower-licence alternative fits this composition. Highest-licence fourth hires stay when needed.") end
        table.insert(result.notes,"Ultra overrides Save gold only while selected. It compares fresh discounted estimates in final hire order; a lower licence is not always cheaper. Each character keeps its chosen licence. Unselected characters, missing prices, unavailable capacity and skipped licence tiers are not alternatives. Server charges may differ; this is not an exact cheapest-plan claim.")
    end
    for _,note in ipairs(result.grouping.notes) do table.insert(result.notes,note) end
    -- Report unmet soft preferences, including forced anchor compromises.
    local physicalWithout,rangedWithout,priestWithout,paladinWithout=0,0,0,0
    for g=1,groups do
        local physical,ranged,shaman,priest,paladin=false,false,false,false,false
        for i=(g-1)*5+1,g*5 do
            local e=entries[i]
            if C.IsFilledEntry(e) then
                physical=physical or C.PlannerPhysical(e); ranged=ranged or (e.role=="rdps" and not C.PlannerPhysical(e))
                shaman=shaman or e.class=="shaman"; priest=priest or (e.class=="priest" and e.role=="healer"); paladin=paladin or (e.class=="paladin" and e.role=="healer")
            end
        end
        if physical and not shaman then physicalWithout=physicalWithout+1 end
        if ranged then
            if not priest then priestWithout=priestWithout+1 end
            if not paladin then paladinWithout=paladinWithout+1 end
            if not priest and not paladin then rangedWithout=rangedWithout+1 end
        end
    end
    if physicalWithout>0 then table.insert(result.notes,physicalWithout.." physical group(s) without Shaman support; counts, available slots and fixed anchors take priority.") end
    if priestWithout>0 or paladinWithout>0 then table.insert(result.notes,"Ranged groups without a Priest healer: "..priestWithout.."; without a Paladin healer: "..paladinWithout..". Supplies/anchors limit coverage.") end
    local overflow,unmatched,bestCaster=0,0,0
    for i,e in ipairs(entries) do
        if i>20 and C.PlannerMelee(e) then overflow=overflow+1 end
        bestCaster=math.max(bestCaster,C.PlannerCasterPreference(e))
    end
    for i,e in ipairs(entries) do
        if C.IsFilledEntry(e) and e.class=="druid" and e.role=="rdps" then
            local best=0; local g=math.floor((i-1)/5)+1
            for j=(g-1)*5+1,g*5 do best=math.max(best,C.PlannerCasterPreference(entries[j])) end
            if best<bestCaster then unmatched=unmatched+1 end
        end
    end
    if overflow>0 then table.insert(result.notes,overflow.." tank/melee row(s) remain outside groups 1-4; fixed anchors and available front slots limit placement.") end
    if unmatched>0 then table.insert(result.notes,unmatched.." Balance Druid(s) could not share their preferred caster group; fixed anchors, five-person groups and other preferences compete.") end
    table.insert(result.notes,"Groups prefer tanks/melee in groups 1-4, including melee Paladins/Druids with Warriors/Shamans. Balance prefers included legacy Mage/Warlock, then known Fire Mage, otherwise Warlock. Healer Paladins spread across remaining unconstrained groups after these choices.")
    table.insert(result.notes,"Shaman reservations cover groups 1-5 first, one per group in slots 5/10/15/20/25 when supplied; Group2 prefers a normal Shaman. Extra Shamans cover other groups before stacking. Tanks prefer Group1; Group2 prefers Hunter/Rogue/feral-or-bear/normal Warrior MDPS. Physical groups fill early, with Paladin then Priest healing in their last partial group. Balance receives its preferred included caster before Shadow Priests take remaining Warlocks in full-identity order. These staged preferences are deterministic, not a universal optimum or proof of live buffs. Normal and legacy companions regroup without changing identity, source, tier or commands. "..(request.player and "Verified humans reserve the tail from40, self40; unresolved guest anchors remain distinct and capacity conflicts are noted. Unused ordinary slots precede the human tail." or "Existing explicit anchors stay fixed."))
    result.plan.entries=entries
    C.PlannerEstimate(result,chosen,request)
    return result
end
