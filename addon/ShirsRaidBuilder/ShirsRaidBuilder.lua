-- Shir's Raid Builder 0.62
-- Independent clean-room implementation.

local C = ShirsRaidBuilderCore
local DB = {}

local function BindAccountDB()
    if type(ShirsRaidBuilderDB) ~= "table" then return false end
    local pending = DB
    DB = ShirsRaidBuilderDB
    if type(DB.presets) ~= "table" then DB.presets = {} end
    if type(DB.knownCharacters) ~= "table" then DB.knownCharacters = {} end
    if type(DB.characterLevels) ~= "table" then DB.characterLevels = {} end
    if type(DB.characterFactions) ~= "table" then DB.characterFactions = {} end
    if type(DB.characterRoles) ~= "table" then DB.characterRoles = {} end
    if type(DB.inviteCharacters) ~= "table" then DB.inviteCharacters = {} end
    if pending ~= DB and type(pending) == "table" then
        if type(pending.presets) == "table" then
            for name, preset in pairs(pending.presets) do
                if type(DB.presets[name]) ~= "table" then DB.presets[name] = preset end
            end
            if pending.currentPreset and not DB.currentPreset then DB.currentPreset = pending.currentPreset end
        end
        if type(pending.knownCharacters) == "table" then
            for name in pairs(pending.knownCharacters) do DB.knownCharacters[name] = true end
        end
        if type(pending.characterLevels) == "table" then
            for name, level in pairs(pending.characterLevels) do DB.characterLevels[name] = level end
        end
        if type(pending.characterRoles) == "table" then
            for name, role in pairs(pending.characterRoles) do DB.characterRoles[name] = role end
        end
    end
    return true
end

local ROLES = { "tank", "healer", "rdps", "mdps" }
local ROLE_LABELS = { all="All Roles", tank="Tank", healer="Healer", rdps="Ranged DPS", mdps="Melee DPS" }
local CLASS_LABELS = {
    warrior="Warrior", mage="Mage", warlock="Warlock", priest="Priest",
    druid="Druid", paladin="Paladin", shaman="Shaman", hunter="Hunter", rogue="Rogue",
}
local RACE_LABELS = {
    human="Human", dwarf="Dwarf", gnome="Gnome", nightelf="Night Elf",
    orc="Orc", undead="Undead", tauren="Tauren", troll="Troll",
}
local SPEC_LABELS = { default="Default", frost="Frost", fire="Fire", arcane="Arcane", might="Might", magic="Magic" }
local CLASS_COLORS = {
    warrior={0.78,0.61,0.43}, paladin={0.96,0.55,0.73}, hunter={0.67,0.83,0.45},
    rogue={1.00,0.96,0.41}, priest={1.00,1.00,1.00}, shaman={0.00,0.44,0.87},
    mage={0.41,0.80,0.94}, warlock={0.58,0.51,0.79}, druid={1.00,0.49,0.04},
}
local ROLE_SHORT = { tank="Tank", healer="Heal", mdps="Melee", rdps="Range" }
local GENDER_LABELS = { male="Male", female="Female" }
local CLASSES = { "warrior", "mage", "warlock", "priest", "druid", "paladin", "shaman", "hunter", "rogue" }
local SPECS = {
    warrior={"default"}, mage={"frost","fire","arcane"}, warlock={"default"}, priest={"default"},
    druid={"default"}, paladin={"default","might","magic"}, shaman={"default"}, hunter={"default"}, rogue={"default"},
}
local CLASS_ROLES = {
    warrior={"tank","mdps"}, mage={"rdps"}, warlock={"rdps"}, priest={"healer","rdps"},
    druid={"tank","healer","mdps","rdps"}, paladin={"tank","healer","mdps"},
    shaman={"tank","healer","mdps","rdps"}, hunter={"rdps"}, rogue={"mdps"},
}
local TIERS = {"t0","t1r","t2r","t3r","t4r","t5r","t1d","t2d","t3d","t4d","t5d"}
local RACES = {"human","dwarf","gnome","nightelf","orc","undead","tauren","troll"}
local GENDERS = {"male","female"}
local RACE_FACTIONS = {
    human="Alliance", dwarf="Alliance", gnome="Alliance", nightelf="Alliance",
    orc="Horde", undead="Horde", tauren="Horde", troll="Horde",
}
local CLASS_RACES = {
    warrior={"orc","undead","tauren","troll","human","gnome","nightelf","dwarf"},
    mage={"undead","troll","human","gnome"},
    warlock={"orc","undead","human","gnome"},
    priest={"undead","troll","human","nightelf","dwarf"},
    druid={"tauren","nightelf"}, paladin={"human","dwarf"},
    shaman={"orc","tauren","troll"},
    hunter={"orc","tauren","troll","nightelf","dwarf"},
    rogue={"orc","undead","troll","human","gnome","nightelf","dwarf"},
}

local mainFrame = nil
local compositionContent = nil
local rows = {}
local statusText = nil
local presetButton = nil
local settingsFrame = nil
local denyFrame = nil
local contextFrame = nil
local addNormalFrame = nil
local addLegacyFrame = nil
local namePrompt = nil
local denyRows = {}
local denyWorking = {}
local denyIndex = nil
local settingsRuleIndex = nil
local settingsAbilityInput = nil
local abilityMenu = nil
local abilitySuggestionRows = {}
local settingsRoleButton = nil
local settingsClassButton = nil
local setupFrame = nil
local legacyNameMenu = nil
local legacyNameRows = {}
local executing = false
local executeFrame = nil
local nodFrame = nil
local executeQueue = nil
local executeIndex = 0
local executeFrames = 0
local executeWaitStarted = 0
local HIRE_DELAY_MIN = 7.5
local HIRE_DELAY_MAX = 8.5
local NOD_TIMEOUT_SECONDS = 3.0
local WHISPER_GAP_SECONDS = 0.7
local executeHireReadyAt = 0
local executeWaitingNod = false
local executeNodReady = false
local executeNodName = ""
local executeNodStarted = 0
local executeWhisperGap = 0
local executeElapsed = 0
local executePartyBefore = nil
local executeCompanions = {}
local executeBaseline = {}
local executeWaitElapsed = 0
local executeCompanionList = {}
local executeGrinfoRequested = false
local executeGrinfoReady = false
local executeGrinfoExpanded = false
local executeRequestFrame = nil
local grinfoFrame = nil
local collapsedGroups = {}
local compositionSlots = {}
local dragSourceIndex = nil
local dragGhost = nil
local dragUpdate = nil
local dragOffsetX = 0
local dragOffsetY = 0
local contextShield = nil
local contextIndex = nil
local inviteFrame = nil

local function RandomHireDelay()
    return HIRE_DELAY_MIN + (HIRE_DELAY_MAX - HIRE_DELAY_MIN) * math.random()
end

local function Chat(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffShir's Raid Builder:|r " .. message)
    end
end

local function EnsureDB()
    BindAccountDB()
    if type(DB.presets) ~= "table" then DB.presets = {} end
    if DB.uiMode ~= "sort" then DB.uiMode = "hire" end
    C.EnsureProfileBanks(DB)
    if type(DB.knownCharacters) ~= "table" then DB.knownCharacters = {} end
    if type(DB.characterLevels) ~= "table" then DB.characterLevels = {} end
    if type(DB.characterFactions) ~= "table" then DB.characterFactions = {} end
    if type(DB.characterRoles) ~= "table" then DB.characterRoles = {} end
    if type(DB.inviteCharacters) ~= "table" then DB.inviteCharacters = {} end
    if type(DB.captureWarningHidden) ~= "table" then DB.captureWarningHidden = {} end
    local known = {}
    local name
    for name in pairs(DB.inviteCharacters) do table.insert(known, name) end
    for name in pairs(DB.knownCharacters) do table.insert(known, name) end
    C.knownCharacterNames = known
    if DB.uiMode == "hire" then
        local moved = C.RescueHirePreset(DB)
        if moved then C.rescueNote = moved end
    end
    C.MigrateCharacterRoles(DB.characterRoles, DB.presets, DB.currentPreset)
    local preset = C.ActivePreset(DB, DB.uiMode)
    if type(preset.entries) ~= "table" then preset.entries = {} end
    if type(preset.denyRules) ~= "table" then preset.denyRules = {} end
    if type(preset.setupRules) ~= "table" then preset.setupRules = {} end
    C.PadRaidSlots(preset.entries, 40)
    C.RepairRaidEntries(preset.entries)
    DB.inviteRequested = nil
    for i = table.getn(preset.denyRules), 1, -1 do
        local rule = preset.denyRules[i]
        if type(rule) ~= "table" then
            table.remove(preset.denyRules, i)
        else
            rule.role = C.Trim(rule.role) ~= "" and string.lower(rule.role) or "mdps"
            rule.class = C.Trim(rule.class) ~= "" and string.lower(rule.class) or "shaman"
            rule.abilities = C.NormalizeDenyList(rule.abilities)
            if table.getn(rule.abilities) == 0 then table.remove(preset.denyRules, i) end
        end
    end
    return preset
end

local function SetStatus(text)
    if statusText then statusText:SetText(text or "") end
end

local BUTTON_H = 22
local DROP_H = 22
local DROP_BG = {bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=8, insets={left=2,right=2,top=2,bottom=2}}
local PANEL_BG = {bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=16, edgeSize=32, insets={left=11,right=12,top=12,bottom=11}}

local function StyleMenuFrame(frame)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetToplevel(true)
    frame:SetFrameLevel(200)
    frame:EnableMouse(true)
    frame:SetBackdrop(DROP_BG)
    frame:SetBackdropColor(0.02, 0.03, 0.06, 1.0)
    frame:SetBackdropBorderColor(0.55, 0.68, 0.88, 1.0)
end

local function StylePanelFrame(frame)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetFrameLevel(80)
    frame:EnableMouse(true)
    frame:SetBackdrop(PANEL_BG)
    frame:SetBackdropColor(0.03, 0.04, 0.07, 1.0)
    frame:SetBackdropBorderColor(0.70, 0.70, 0.70, 1.0)
end

local function RegisterEscapeFrame(frame)
end

local function MakeCaption(parent, text, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(text)
    label:SetTextColor(0.78, 0.82, 0.90)
    return label
end

local function MakeButton(parent, text, width, x, y, onClick, fromBottom)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(width); button:SetHeight(BUTTON_H)
    if fromBottom then
        button:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
    else
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    button:SetBackdrop(DROP_BG)
    button:SetBackdropColor(0.08, 0.12, 0.20, 1.0)
    button:SetBackdropBorderColor(0.45, 0.58, 0.78, 1.0)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(0.90, 0.93, 1.0)
    button.label = label
    button:SetScript("OnEnter", function()
        button:SetBackdropColor(0.16, 0.24, 0.36, 1.0)
        button:SetBackdropBorderColor(0.80, 0.88, 1.0, 1.0)
        label:SetTextColor(1.0, 0.90, 0.45)
        if button.tip and GameTooltip then
            GameTooltip:SetOwner(this or button, "ANCHOR_RIGHT")
            GameTooltip:SetText(button.tipTitle or text)
            GameTooltip:AddLine(button.tip, 1, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        button:SetBackdropColor(0.08, 0.12, 0.20, 1.0)
        button:SetBackdropBorderColor(0.45, 0.58, 0.78, 1.0)
        label:SetTextColor(0.90, 0.93, 1.0)
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", onClick)
    return button
end

local function MakeInput(parent, width, x, y, value)
    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    input:SetWidth(width); input:SetHeight(20)
    input:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    input:SetAutoFocus(false); input:SetMaxLetters(60)
    input:SetFontObject(GameFontNormalSmall); input:SetText(value or "")
    input:SetTextColor(0.95, 0.97, 1.0)
    return input
end

local choiceMenu = nil
local choiceButtons = {}
local choiceOwner = nil

local function CloseChoiceMenu()
    if choiceMenu then choiceMenu:Hide() end
    choiceOwner = nil
end

local function SelectButton(parent, options, current, width, x, y, onChange)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(width); button:SetHeight(DROP_H); button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetBackdrop(DROP_BG)
    button:SetBackdropColor(0.07, 0.10, 0.16, 0.98)
    button:SetBackdropBorderColor(0.55, 0.68, 0.88, 1.0)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.label:SetPoint("LEFT", button, "LEFT", 7, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -16, 0)
    button.label:SetJustifyH("LEFT")
    button.label:SetTextColor(0.95, 0.97, 1.0)
    button.arrow = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.arrow:SetPoint("RIGHT", button, "RIGHT", -5, 0)
    button.arrow:SetText("v")
    button.arrow:SetTextColor(0.78, 0.86, 1.0)
    button.options = options or {}
    button.label:SetText(current or button.options[1] or "(none)")
    button:SetScript("OnEnter", function()
        button:SetBackdropColor(0.14, 0.20, 0.30, 0.98)
        button:SetBackdropBorderColor(0.80, 0.88, 1.0, 1.0)
        if button.tip and GameTooltip then
            GameTooltip:SetOwner(this or button, "ANCHOR_RIGHT")
            GameTooltip:SetText(button.tipTitle or "Profile")
            GameTooltip:AddLine(button.tip, 1, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        button:SetBackdropColor(0.07, 0.10, 0.16, 0.98)
        button:SetBackdropBorderColor(0.55, 0.68, 0.88, 1.0)
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", function()
        if choiceMenu and choiceMenu:IsShown() and choiceOwner == button then
            CloseChoiceMenu()
            return
        end
        if not choiceMenu then
            choiceMenu = CreateFrame("Frame", "ShirsRaidBuilderChoiceMenu", UIParent)
        end
        StyleMenuFrame(choiceMenu)
        for i = 1, table.getn(choiceButtons) do choiceButtons[i]:Hide(); choiceButtons[i]:SetParent(nil) end
        choiceButtons = {}
        local values = button.options; local count = table.getn(values)
        if count == 0 then return end
        choiceMenu:SetWidth(button:GetWidth())
        choiceMenu:SetHeight(count * 20 + 8)
        choiceMenu:ClearAllPoints(); choiceMenu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
        for i = 1, count do
            local value = values[i]
            local option = CreateFrame("Button", nil, choiceMenu)
            option:SetWidth(button:GetWidth() - 8); option:SetHeight(18)
            option:SetPoint("TOPLEFT", choiceMenu, "TOPLEFT", 4, -4 - ((i - 1) * 20))
            local text = option:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", option, "LEFT", 4, 0)
            text:SetText(value)
            text:SetTextColor(0.92, 0.95, 1.0)
            option:SetScript("OnEnter", function() text:SetTextColor(1.0, 0.86, 0.35) end)
            option:SetScript("OnLeave", function() text:SetTextColor(0.92, 0.95, 1.0) end)
            local captured = value
            option:SetScript("OnClick", function()
                button.label:SetText(captured)
                CloseChoiceMenu()
                if onChange then onChange(captured) end
            end)
            table.insert(choiceButtons, option)
        end
        choiceOwner = button
        RegisterEscapeFrame(choiceMenu)
        choiceMenu:Show()
    end)
    return button
end

local function RoleOptions(class)
    local result = {}
    local source = CLASS_ROLES[class] or ROLES
    for i = 1, table.getn(source) do table.insert(result, ROLE_LABELS[source[i]] or source[i]) end
    return result
end

local function ClassesForRole(role, faction)
    local result = {}
    for i = 1, table.getn(CLASSES) do
        local class = CLASSES[i]
        if C.ClassAllowedForFaction(class, faction) then
            if role == "all" then
                table.insert(result, CLASS_LABELS[class] or class)
            else
                local allowed = CLASS_ROLES[class] or ROLES
                for ri = 1, table.getn(allowed) do
                    if allowed[ri] == role then table.insert(result, CLASS_LABELS[class] or class); break end
                end
            end
        end
    end
    return result
end

local function TiersForCharacter(name)
    local record = type(DB.inviteCharacters) == "table" and DB.inviteCharacters[C.Trim(name)]
    if record then return C.BuildLicenseOptions(record.dungeonLicense, record.raidLicense) end
    return TIERS
end

local function SpecsForClassRole(class, role)
    return C.SpecsForClassRole(class, role) or SPECS[class] or {"default"}
end

local function RoleValue(display)
    if display == "All Roles" then return "all" end
    if display == "Melee DPS" then return "mdps" end
    if display == "Ranged DPS" then return "rdps" end
    return string.lower(display or "mdps")
end

local function KeyOf(display, labels)
    local want = C.Trim(display)
    if want == "" then return "" end
    for key, label in pairs(labels) do
        if label == want or key == string.lower(want) then return key end
    end
    return string.lower(want)
end

local function ClassValue(display)
    return KeyOf(display, CLASS_LABELS)
end

local function RaceValue(display)
    return KeyOf(display, RACE_LABELS)
end

local function SpecValue(display)
    return KeyOf(display, SPEC_LABELS)
end

local function GenderValue(display)
    return KeyOf(display, GENDER_LABELS)
end

local function LabeledKeys(keys, labels)
    local result = {}
    if type(keys) ~= "table" then return result end
    for i = 1, table.getn(keys) do table.insert(result, labels[keys[i]] or keys[i]) end
    return result
end

local function RacesForClass(class)
    return CLASS_RACES[class] or RACES
end

local function RememberFaction(name, faction)
    local character = C.Trim(name)
    if character == "" then return end
    if faction ~= "Alliance" and faction ~= "Horde" then return end
    if type(DB.characterFactions) ~= "table" then DB.characterFactions = {} end
    DB.characterFactions[character] = faction
end

local function HarvestKnownFactions()
    if type(DB.presets) ~= "table" then return end
    for _, preset in pairs(DB.presets) do
        if type(preset) == "table" and type(preset.entries) == "table" then
            for i = 1, table.getn(preset.entries) do
                local entry = preset.entries[i]
                if entry and entry.kind == "normal" and entry.account then
                    RememberFaction(entry.account, RACE_FACTIONS[entry.race])
                end
            end
        end
    end
end

local function FactionForCharacter(name)
    local character = C.Trim(name)
    if character == "" then return nil end
    HarvestKnownFactions()
    if type(DB.characterFactions) == "table" and DB.characterFactions[character] then return DB.characterFactions[character] end
    if type(DB.inviteCharacters) == "table" and DB.inviteCharacters[character] and DB.inviteCharacters[character].faction then
        return DB.inviteCharacters[character].faction
    end
    if type(UnitName) == "function" and type(UnitFactionGroup) == "function" and UnitName("player") == character then
        local live = UnitFactionGroup("player")
        RememberFaction(character, live)
        return live
    end
    local preset = DB.presets and DB.presets[DB.currentPreset]
    if preset and type(preset.entries) == "table" then
        for i = 1, table.getn(preset.entries) do
            local entry = preset.entries[i]
            if entry and (entry.account or entry.charName) == character and RACE_FACTIONS[entry.race] then
                RememberFaction(character, RACE_FACTIONS[entry.race])
                return RACE_FACTIONS[entry.race]
            end
        end
    end
    return nil
end

local function RacesForClassAndFaction(class, faction)
    local source = RacesForClass(class)
    if faction ~= "Alliance" and faction ~= "Horde" then return source end
    local result = {}
    for i = 1, table.getn(source) do
        if RACE_FACTIONS[source[i]] == faction then table.insert(result, source[i]) end
    end
    return table.getn(result) > 0 and result or source
end

local function GetPresetNames()
    local names = {}
    local bank = C.PresetBank(DB, DB.uiMode)
    for name in pairs(bank) do table.insert(names, name) end
    table.sort(names)
    return names
end

local function RefreshPresetButton()
    if presetButton then
        local _, name = C.PresetBank(DB, DB.uiMode)
        presetButton.options = GetPresetNames(); presetButton.label:SetText(name or "Default")
    end
end

local function SwitchPreset(name)
    local bank = C.PresetBank(DB, DB.uiMode)
    if bank[name] then
        if DB.uiMode == "sort" then DB.currentSortPreset = name else DB.currentPreset = name end
        EnsureDB(); RefreshPresetButton()
        if mainFrame then RefreshComposition() end
    end
end

local function CyclePreset(delta)
    local names = GetPresetNames()
    if table.getn(names) == 0 then return end
    local index = 1
    for i = 1, table.getn(names) do if names[i] == DB.currentPreset then index = i end end
    index = index + delta
    if index < 1 then index = table.getn(names) end
    if index > table.getn(names) then index = 1 end
    SwitchPreset(names[index])
end

local function MoveEntry(fromIndex, dest)
    local preset = EnsureDB()
    C.PadRaidSlots(preset.entries, 40)
    if not fromIndex or not dest then RefreshComposition(); return end
    local toIndex = dest.index
    if dest.kind == "header" then
        local first = dest.index
        toIndex = nil
        for i = first, first + 4 do
            if preset.entries[i] and preset.entries[i].kind == "empty" then toIndex = i; break end
        end
        if not toIndex then toIndex = first end
    end
    if not C.SwapRaidSlots(preset.entries, fromIndex, toIndex) then RefreshComposition(); return end
    local held = preset.entries[toIndex]
    local other = preset.entries[fromIndex]
    RefreshComposition()
    if C.IsFilledEntry(other) then
        SetStatus("Swapped " .. (held.account or held.charName or "entry") .. " with " .. (other.account or other.charName or "entry") .. ".")
    else
        SetStatus("Moved " .. (held.account or held.charName or "entry") .. " to spawn " .. toIndex .. ".")
    end
end

local function CursorOverFrame(frame)
    if not frame or not frame.IsVisible or not frame:IsVisible() then return false end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not x or not scale or scale == 0 then return false end
    x = x / scale
    y = y / scale
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not left or not right or not top or not bottom then return false end
    return x >= left and x <= right and y >= bottom and y <= top
end

local function FindDropSlot(ignoreFrame)
    local best = nil
    for i = 1, table.getn(compositionSlots) do
        local slot = compositionSlots[i]
        if slot.frame ~= ignoreFrame and CursorOverFrame(slot.frame) then best = slot end
    end
    return best
end

local function RemoveEntry(index)
    local preset = EnsureDB()
    local entry = preset.entries[index]
    if C.IsFilledEntry(entry) then
        preset.entries[index] = {kind="empty"}
        RefreshComposition()
        SetStatus("Removed " .. (entry.account or entry.charName or "entry") .. ".")
    end
end

local OpenContextMenu
local OpenDenyEditor
local CloseContext

local function AddRowActionButtons(row, index)
    if C.IsPlayerEntry(EnsureDB().entries[index]) then return end
    MakeButton(row, "X", 16, 82, -3, function() RemoveEntry(index) end)
end

local function PaintEntryRow(row, entry)
    if entry.kind == "player" then
        row:SetBackdropColor(0.18,0.14,0.04,1.0); row:SetBackdropBorderColor(0.95,0.78,0.28,1.0)
    elseif entry.kind == "legacy" then
        row:SetBackdropColor(0.16,0.06,0.22,1.0); row:SetBackdropBorderColor(0.68,0.32,0.86,1.0)
    elseif entry.kind == "guest" then
        row:SetBackdropColor(0.04,0.12,0.12,1.0); row:SetBackdropBorderColor(0.30,0.72,0.68,1.0)
    else
        row:SetBackdropColor(0.06,0.10,0.16,1.0); row:SetBackdropBorderColor(0.28,0.46,0.68,1.0)
    end
end

local function RenderEntry(index, entry, y, spawnNumber, x)
    local row = CreateFrame("Button", nil, compositionContent)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetWidth(100); row:SetHeight(28)
    row:SetPoint("TOPLEFT", compositionContent, "TOPLEFT", x, y)
    row:SetBackdrop(DROP_BG)
    PaintEntryRow(row, entry)
    local denyList = C.GetEffectiveDenyList(entry, EnsureDB().denyRules)
    local denyCount = table.getn(denyList)
    local name = C.LayoutLabel(entry)
    if name == "" then name = "?" end
    local classKey = entry.class or "warrior"
    local color = CLASS_COLORS[classKey] or {0.85,0.88,0.95}
    local line1 = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line1:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -3)
    line1:SetPoint("TOPRIGHT", row, "TOPRIGHT", -18, -3)
    line1:SetHeight(10)
    line1:SetJustifyH("LEFT")
    if line1.SetNonSpaceWrap then line1:SetNonSpaceWrap(false) end
    line1:SetText(tostring(spawnNumber) .. " " .. name)
    line1:SetTextColor(0.95, 0.96, 1.0)
    local line2 = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line2:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -15); line2:SetWidth(78); line2:SetHeight(10); line2:SetJustifyH("LEFT")
    if line2.SetNonSpaceWrap then line2:SetNonSpaceWrap(false) end
    line2:SetText((CLASS_LABELS[classKey] or classKey) .. " " .. (ROLE_SHORT[entry.role] or entry.role or ""))
    line2:SetTextColor(color[1], color[2], color[3])
    row:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" then
            OpenContextMenu(index, row)
        else
            CloseContext()
        end
    end)
    row:SetScript("OnEnter", function()
        if entry.kind == "player" then row:SetBackdropColor(0.28,0.22,0.08,1.0) elseif entry.kind == "legacy" then row:SetBackdropColor(0.28,0.10,0.38,1.0) else row:SetBackdropColor(0.12,0.20,0.32,1.0) end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(name, 1,1,1)
        GameTooltip:AddLine((CLASS_LABELS[classKey] or classKey) .. "  " .. (ROLE_LABELS[entry.role] or entry.role or ""), color[1], color[2], color[3])
        if entry.kind == "player" then
            GameTooltip:AddLine("You. Stays in this raid group.", 0.95, 0.84, 0.40)
            GameTooltip:AddLine("Drag to choose your group. Right-click to set role.", 0.8,0.8,0.8)
        end
        if entry.kind == "normal" then
            GameTooltip:AddLine((entry.tier or "") .. "  " .. (SPEC_LABELS[entry.spec] or entry.spec or "") .. "  " .. (RACE_LABELS[entry.race] or "") .. "  " .. (GENDER_LABELS[entry.gender] or ""), 0.8,0.8,0.8)
            GameTooltip:AddLine("Right-click: change hire settings", 0.8,0.8,0.8)
        end
        if entry.kind == "legacy" then
            GameTooltip:AddLine("Hires: " .. (C.GetLegacyHireName(entry) or "?"), 0.8,0.8,0.8)
            if entry.pet and entry.pet ~= "" then GameTooltip:AddLine("Pet: " .. entry.pet, 0.8,0.8,0.8) end
            GameTooltip:AddLine("Right-click: extra denies or hire settings", 0.8,0.8,0.8)
        end
        GameTooltip:AddLine("Matching rules: " .. denyCount .. " ability(s)", 0.8,0.8,0.8)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        if dragSourceIndex ~= index then PaintEntryRow(row, entry) end
        GameTooltip:Hide()
    end)
    row:SetMovable(true)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function()
        dragSourceIndex = index
        GameTooltip:Hide()
        CloseContext()
        if mainFrame then mainFrame:StopMovingOrSizing() end
        row:StopMovingOrSizing()
        if not dragGhost then
            dragGhost = CreateFrame("Frame", nil, UIParent)
            dragGhost:SetWidth(100); dragGhost:SetHeight(28)
            dragGhost:SetFrameStrata("TOOLTIP")
            dragGhost:SetToplevel(true)
            dragGhost:EnableMouse(false)
            dragGhost:SetBackdrop(DROP_BG)
            dragGhost.line1 = dragGhost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dragGhost.line1:SetPoint("TOPLEFT", dragGhost, "TOPLEFT", 3, -3)
            dragGhost.line1:SetPoint("TOPRIGHT", dragGhost, "TOPRIGHT", -4, -3)
            dragGhost.line1:SetHeight(10)
            dragGhost.line1:SetJustifyH("LEFT")
            if dragGhost.line1.SetNonSpaceWrap then dragGhost.line1:SetNonSpaceWrap(false) end
            dragGhost.line2 = dragGhost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dragGhost.line2:SetPoint("TOPLEFT", dragGhost, "TOPLEFT", 3, -15)
            dragGhost.line2:SetWidth(92); dragGhost.line2:SetHeight(10); dragGhost.line2:SetJustifyH("LEFT")
            if dragGhost.line2.SetNonSpaceWrap then dragGhost.line2:SetNonSpaceWrap(false) end
        end
        PaintEntryRow(dragGhost, entry)
        dragGhost.line1:SetText(tostring(index) .. " " .. name)
        dragGhost.line1:SetTextColor(0.95, 0.96, 1.0)
        dragGhost.line2:SetText((CLASS_LABELS[classKey] or classKey) .. " " .. (ROLE_SHORT[entry.role] or entry.role or ""))
        dragGhost.line2:SetTextColor(color[1], color[2], color[3])
        local function PlaceGhost()
            local s = UIParent:GetEffectiveScale()
            if not s or s == 0 then s = 1 end
            local x, y = GetCursorPosition()
            dragGhost:ClearAllPoints()
            dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
        end
        PlaceGhost()
        dragGhost:Show()
        row:SetAlpha(0.35)
        if not dragUpdate then dragUpdate = CreateFrame("Frame") end
        dragUpdate:SetScript("OnUpdate", function()
            if not dragGhost or not dragGhost:IsShown() then return end
            PlaceGhost()
        end)
        SetStatus("Drop this hire on another slot to move it.")
    end)
    row:SetScript("OnDragStop", function()
        if dragUpdate then dragUpdate:SetScript("OnUpdate", nil) end
        if dragGhost then dragGhost:Hide() end
        row:SetAlpha(1)
        local dest = FindDropSlot(row)
        local source = dragSourceIndex
        dragSourceIndex = nil
        MoveEntry(source, dest)
    end)
    AddRowActionButtons(row, index)
    table.insert(rows, row)
    table.insert(compositionSlots, {frame=row, index=index, kind="entry"})
end

local function RenderEmptySlot(destIndex, y, x)
    local row = CreateFrame("Button", nil, compositionContent)
    row:SetWidth(100); row:SetHeight(28)
    row:SetPoint("TOPLEFT", compositionContent, "TOPLEFT", x, y)
    row:EnableMouse(true)
    row:SetBackdrop(DROP_BG)
    row:SetBackdropColor(0.04, 0.05, 0.08, 1.0)
    row:SetBackdropBorderColor(0.22, 0.28, 0.36, 1.0)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", row, "CENTER", 0, 0)
    text:SetText("empty")
    text:SetTextColor(0.40, 0.45, 0.52)
    table.insert(rows, row)
    table.insert(compositionSlots, {frame=row, index=destIndex, kind="empty"})
end

local function GroupDenyCount(preset, firstIndex, lastIndex)
    local total = 0
    for i = firstIndex, lastIndex do
        if C.IsFilledEntry(preset.entries[i]) then total = total + table.getn(C.GetEffectiveDenyList(preset.entries[i], preset.denyRules)) end
    end
    return total
end

function RefreshComposition()
    if not compositionContent then return end
    for i = 1, table.getn(rows) do rows[i]:Hide(); rows[i]:SetParent(nil) end
    rows = {}
    compositionSlots = {}
    local preset = EnsureDB()
    C.PadRaidSlots(preset.entries, 40)
    if type(UnitName) == "function" then
        local you = UnitName("player")
        if you and you ~= "" then
            local class = ""
            if type(UnitClass) == "function" then class = C.ClassKeyFromLabel(UnitClass("player")) end
            local role = C.RememberedCharacterRole(DB.characterRoles, you, class)
            C.EnsurePlayerSlot(preset.entries, you, class, role)
        end
    end
    local y = -2
    for group = 1, 8 do
        local firstIndex = (group - 1) * 5 + 1
        local lastIndex = firstIndex + 4
        local header = CreateFrame("Button", nil, compositionContent)
        header:SetWidth(510); header:SetHeight(18); header:SetPoint("TOPLEFT", compositionContent, "TOPLEFT", 2, y)
        local headerText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("LEFT", header, "LEFT", 6, 0)
        headerText:SetText((collapsedGroups[group] and "[+] " or "[-] ") .. "Group " .. group .. "  |  Spawn " .. firstIndex .. "-" .. lastIndex .. "  |  denies " .. GroupDenyCount(preset, firstIndex, lastIndex))
        headerText:SetTextColor(1.0,0.84,0.28)
        local capturedGroup = group
        local capturedFirst = firstIndex
        header:SetScript("OnClick", function() collapsedGroups[capturedGroup] = not collapsedGroups[capturedGroup]; RefreshComposition() end)
        table.insert(rows, header)
        table.insert(compositionSlots, {frame=header, index=capturedFirst, kind="header"})
        y = y - 19
        if not collapsedGroups[group] then
            for slot = 0, 4 do
                local index = firstIndex + slot
                local x = 2 + (slot * 102)
                if C.IsFilledEntry(preset.entries[index]) then
                    RenderEntry(index, preset.entries[index], y, index, x)
                else
                    RenderEmptySlot(index, y, x)
                end
            end
            y = y - 32
        end
    end
    compositionContent:SetHeight(math.max(420, -y + 8))
    if mainFrame and mainFrame.countText then mainFrame.countText:SetText(tostring(C.HireSlotCount(preset.entries)) .. "/40") end
    if mainFrame and mainFrame.roleText then
        local roles = C.CountRoles(preset.entries)
        mainFrame.roleText:SetText("Tank "..roles.tank.."   Healer "..roles.healer.."   Melee "..roles.mdps.."   Range "..roles.rdps)
    end
    RefreshAccountPanel()
    if C.rescueNote then
        local moved = C.rescueNote
        C.rescueNote = nil
        RefreshPresetButton()
        SetStatus("Default was a captured raid, not a hire profile. Moved it to sort layout \"" .. moved .. "\" and opened ZG.")
    end
end

local function RememberPlayer()
    if type(UnitName) ~= "function" then return end
    local name = UnitName("player")
    if not name or name == "" then return end
    EnsureDB()
    if type(UnitLevel) == "function" then DB.characterLevels[name] = UnitLevel("player") end
    if type(UnitFactionGroup) == "function" then RememberFaction(name, UnitFactionGroup("player")) end
    local class = ""
    if type(UnitClass) == "function" then class = C.ClassKeyFromLabel(UnitClass("player")) end
    C.EnsurePlayerSlot(EnsureDB().entries, name, class)
end

local function IsLevelSixty(name)
    local value = C.Trim(name)
    if value == "" then return false end
    if type(DB.characterLevels) == "table" and DB.characterLevels[value] == 60 then return true end
    if type(UnitName) == "function" and type(UnitLevel) == "function" and UnitName("player") == value then
        return UnitLevel("player") == 60
    end
    return false
end

local function DiscoverCharacterNames()
    local found = {}
    local function AddName(name)
        local value = C.Trim(name)
        if value ~= "" and IsLevelSixty(value) then
            local reals = {}
            if type(DB.inviteCharacters) == "table" then
                local n
                for n in pairs(DB.inviteCharacters) do table.insert(reals, n) end
            end
            if not C.IsLegacyHireStub(value, reals) then found[value] = true end
        end
    end
    if type(DB.inviteCharacters) == "table" then
        local licensed = {}
        for name, record in pairs(DB.inviteCharacters) do
            if C.CharacterCanHire(record) then table.insert(licensed, name) end
        end
        if table.getn(licensed) > 0 then
            table.sort(licensed)
            return licensed
        end
    end
    if type(UnitName) == "function" then AddName(UnitName("player")) end
    if type(DB.knownCharacters) == "table" then
        for name in pairs(DB.knownCharacters) do AddName(name) end
    end
    if type(DB.characterLevels) == "table" then
        for name in pairs(DB.characterLevels) do AddName(name) end
    end
    if type(ShirsInventoryAccountDB) == "table" and type(ShirsInventoryAccountDB.items) == "table" then
        for _, realmCharacters in pairs(ShirsInventoryAccountDB.items) do
            if type(realmCharacters) == "table" then for name in pairs(realmCharacters) do AddName(name) end end
        end
    end
    if type(ShirsLazyTrixDB) == "table" and type(ShirsLazyTrixDB.cooldownsByCharacter) == "table" then
        local separator = string.char(31)
        for key in pairs(ShirsLazyTrixDB.cooldownsByCharacter) do
            local _, position = string.find(key, separator, 1, true)
            if position then AddName(string.sub(key, position + 1)) end
        end
    end
    if type(DB.presets) == "table" then
        for _, preset in pairs(DB.presets) do
            if type(preset) == "table" and type(preset.entries) == "table" then
                for i = 1, table.getn(preset.entries) do
                    local entry = preset.entries[i]
                    if entry then
                        AddName(entry.account)
                    end
                end
            end
        end
    end
    local result = {}
    for name in pairs(found) do table.insert(result, name) end
    table.sort(result)
    return result
end

local function StoreInviteCharacters(records)
    EnsureDB()
    DB.inviteCharacters = {}
    local realNames = {}
    local i
    for i = 1, table.getn(records) do
        if records[i] and records[i].name then table.insert(realNames, records[i].name) end
    end
    for i = 1, table.getn(records) do
        local record = records[i]
        DB.inviteCharacters[record.name] = record
        if record.level then DB.characterLevels[record.name] = record.level end
        RememberFaction(record.name, record.faction)
        if not C.IsLegacyHireStub(record.name, realNames) then DB.knownCharacters[record.name] = true end
    end
    if type(DB.knownCharacters) == "table" then
        local name
        for name in pairs(DB.knownCharacters) do
            if C.IsLegacyHireStub(name, realNames) then DB.knownCharacters[name] = nil end
        end
    end
end

local function HandleInviteListMessage()
    local raw = tostring(arg1 or "")
    if arg2 and arg2 ~= "" then raw = raw .. " " .. tostring(arg2) end
    local payload = C.ExtractInviteListPayload(raw)
    if not payload then return end
    local records = C.ParseInviteList(payload)
    StoreInviteCharacters(records)
    if mainFrame and mainFrame:IsShown() then RefreshAccountPanel() end
    SetStatus("CCP licenses: " .. table.getn(records) .. " character(s). Only those who can hire are listed.")
end

local function RequestInviteList()
    if type(SendChatMessage) ~= "function" then return end
    if type(DB) == "table" then DB.inviteRequested = nil end
    if not inviteFrame then return end
    local started = GetTime and GetTime() or 0
    inviteFrame:SetScript("OnUpdate", function()
        if GetTime and (GetTime() - started) < 0.05 then return end
        inviteFrame:SetScript("OnUpdate", nil)
        SendChatMessage(".z addinvite list", "SAY")
    end)
end

local function EnsureInviteListener()
    if inviteFrame then return end
    inviteFrame = CreateFrame("Frame")
    inviteFrame:RegisterEvent("CHAT_MSG_ADDON")
    inviteFrame:RegisterEvent("CHAT_MSG_MONSTER_WHISPER")
    inviteFrame:SetScript("OnEvent", HandleInviteListMessage)
end

function RefreshAccountPanel()
    if not mainFrame or not mainFrame.accountContent then return end
    if DB.uiMode == "sort" then
        mainFrame.accountContent:Hide()
        return
    end
    mainFrame.accountContent:Show()
    for i = 1, table.getn(mainFrame.accountRows or {}) do mainFrame.accountRows[i]:Hide(); mainFrame.accountRows[i]:SetParent(nil) end
    mainFrame.accountRows = {}
    local counts = {}
    local preset = EnsureDB()
    for i = 1, table.getn(preset.entries) do
        local name = C.HireCountName(preset.entries[i])
        if name then counts[name] = (counts[name] or 0) + 1 end
    end
    local names = DiscoverCharacterNames()
    local reals = {}
    if type(DB.inviteCharacters) == "table" then
        local n
        for n in pairs(DB.inviteCharacters) do table.insert(reals, n) end
    end
    for i = 1, table.getn(names) do table.insert(reals, names[i]) end
    for name in pairs(counts) do
        if not C.IsLegacyHireStub(name, reals) then
            local exists = false
            for i = 1, table.getn(names) do if names[i] == name then exists = true end end
            if not exists then table.insert(names, name) end
        end
    end
    table.sort(names)
    local y = -8
    for i = 1, table.getn(names) do
        local name = names[i]
        local row = CreateFrame("Button", nil, mainFrame.accountContent)
        row:SetWidth(165); row:SetHeight(22); row:SetPoint("TOPLEFT", mainFrame.accountContent, "TOPLEFT", 2, y)
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", row, "LEFT", 4, 0)
        text:SetText(name .. "  [" .. (counts[name] or 0) .. "]")
        text:SetTextColor(0.75, 0.88, 1.0)
        local captured = name
        row:SetScript("OnClick", function()
            SetStatus(captured .. " has " .. (counts[captured] or 0) .. " hire(s) in this preset.")
        end)
        table.insert(mainFrame.accountRows, row)
        y = y - 24
    end
    mainFrame.accountContent:SetHeight(math.max(100, -y + 10))
end

CloseContext = function()
    contextIndex = nil
    if contextShield then contextShield:Hide() end
    if contextFrame then contextFrame:Hide() end
end

local function HideFloatingPanels()
    CloseContext()
    CloseChoiceMenu()
    if abilityMenu then abilityMenu:Hide() end
    if legacyNameMenu then legacyNameMenu:Hide() end
    if denyFrame then denyFrame:Hide() end
    if settingsFrame then settingsFrame:Hide() end
    if setupFrame then setupFrame:Hide() end
    if addNormalFrame then addNormalFrame:Hide() end
    if addLegacyFrame then addLegacyFrame:Hide() end
    if namePrompt then namePrompt:Hide() end
    if C.capturePrompt then C.capturePrompt:Hide() end
    if dragGhost then dragGhost:Hide() end
    if dragUpdate then dragUpdate:SetScript("OnUpdate", nil) end
    if contextShield then contextShield:Hide() end
    if GameTooltip then GameTooltip:Hide() end
end

OpenContextMenu = function(index, anchor, page)
    local entry = EnsureDB().entries[index]
    if not C.IsFilledEntry(entry) then return end
    if not page and contextIndex == index and contextFrame and contextFrame:IsShown() then
        CloseContext()
        return
    end
    contextIndex = index
    if not contextShield then
        contextShield = CreateFrame("Button", "ShirsRaidBuilderContextShield", UIParent)
        contextShield:SetAllPoints(UIParent)
        contextShield:SetFrameStrata("FULLSCREEN_DIALOG")
        contextShield:SetFrameLevel(90)
        contextShield:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        contextShield:SetScript("OnClick", CloseContext)
    end
    if not contextFrame then
        contextFrame = CreateFrame("Frame", "ShirsRaidBuilderContextFrame", UIParent)
        StyleMenuFrame(contextFrame)
        RegisterEscapeFrame(contextFrame)
        contextFrame:SetScript("OnHide", function()
            contextIndex = nil
            if contextShield then contextShield:Hide() end
        end)
    end
    contextShield:Show()
    contextFrame:SetFrameStrata("TOOLTIP")
    for i = 1, table.getn(contextFrame.buttons or {}) do contextFrame.buttons[i]:Hide(); contextFrame.buttons[i]:SetParent(nil) end
    contextFrame.buttons = {}
    local function AddContext(text, action)
        local b = MakeButton(contextFrame, text, 176, 12, -10 - (table.getn(contextFrame.buttons) * 24), action)
        local previous = contextFrame.buttons[table.getn(contextFrame.buttons)]
        if previous then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
        end
        table.insert(contextFrame.buttons, b)
    end
    local function ApplyField(field, value)
        local live = EnsureDB().entries[index]
        if field == "role" then value = C.NormalizeRoleForClass(live.class, value) end
        live[field] = value
        if live.kind == "player" and field == "role" then
            C.RememberCharacterRole(DB.characterRoles, live.charName, live.class, value)
        end
        if live.class == "paladin" and live.role == "healer" then live.spec = "default" end
        CloseContext()
        RefreshComposition()
        SetStatus("Updated " .. (live.charName or live.account or C.GetLegacyWhisperName(live) or "hire") .. ".")
    end
    if not page then
        if entry.kind == "player" then
            AddContext("Role: " .. (ROLE_LABELS[entry.role] or entry.role or "?"), function() OpenContextMenu(index, anchor, "role") end)
            AddContext("Close", CloseContext)
        else
        if entry.kind == "legacy" then
            AddContext("Edit extra denies", function() CloseContext(); OpenDenyEditor(index) end)
        end
        if entry.kind == "normal" then
            AddContext("Tier: " .. (entry.tier or "t2r"), function() OpenContextMenu(index, anchor, "tier") end)
            AddContext("Gender: " .. (GENDER_LABELS[entry.gender] or entry.gender or "Male"), function() OpenContextMenu(index, anchor, "gender") end)
        end
        AddContext("Role: " .. (ROLE_LABELS[entry.role] or entry.role or "?"), function() OpenContextMenu(index, anchor, "role") end)
        AddContext("Spec: " .. (SPEC_LABELS[entry.spec] or entry.spec or "Default"), function() OpenContextMenu(index, anchor, "spec") end)
        if entry.kind == "normal" then
            AddContext("Race: " .. (RACE_LABELS[entry.race] or entry.race or "?"), function() OpenContextMenu(index, anchor, "race") end)
        end
        if entry.kind == "legacy" and string.lower(entry.class or "") == "warlock" then
            AddContext("Pet: " .. (entry.pet or "none"), function() OpenContextMenu(index, anchor, "pet") end)
        end
        AddContext("Close", CloseContext)
        end
    elseif page == "tier" then
        AddContext("Back", function() OpenContextMenu(index, anchor) end)
        local tiers = TiersForCharacter(entry.account)
        for i = 1, table.getn(tiers) do
            local tier = tiers[i]
            AddContext(tier, function() ApplyField("tier", tier) end)
        end
    elseif page == "gender" then
        AddContext("Back", function() OpenContextMenu(index, anchor) end)
        AddContext("Male", function() ApplyField("gender", "male") end)
        AddContext("Female", function() ApplyField("gender", "female") end)
    elseif page == "role" then
        AddContext("Back", function() OpenContextMenu(index, anchor) end)
        local roles = CLASS_ROLES[entry.class] or ROLES
        for i = 1, table.getn(roles) do
            local role = roles[i]
            AddContext(ROLE_LABELS[role] or role, function() ApplyField("role", role) end)
        end
    elseif page == "spec" then
        AddContext("Back", function() OpenContextMenu(index, anchor) end)
        local specs = SpecsForClassRole(entry.class, entry.role)
        for i = 1, table.getn(specs) do
            local spec = specs[i]
            AddContext(SPEC_LABELS[spec] or spec, function() ApplyField("spec", spec) end)
        end
    elseif page == "race" then
        AddContext("Back", function() OpenContextMenu(index, anchor) end)
        local races = CLASS_RACES[entry.class] or RACES
        for i = 1, table.getn(races) do
            local race = races[i]
            AddContext(RACE_LABELS[race] or race, function() ApplyField("race", race) end)
        end
    elseif page == "pet" then
        AddContext("Back", function() OpenContextMenu(index, anchor) end)
        local pets = {"On","Off","Imp","Voidwalker","Succubus","Felhunter"}
        for i = 1, table.getn(pets) do
            local pet = pets[i]
            AddContext(pet, function() ApplyField("pet", pet) end)
        end
    end
    contextFrame:SetWidth(200)
    contextFrame:SetHeight(12 + (table.getn(contextFrame.buttons) * 24))
    contextFrame:ClearAllPoints(); contextFrame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0); contextFrame:Show()
end

local function RefreshDenyRows()
    if not denyFrame then return end
    for i = 1, table.getn(denyRows) do denyRows[i]:Hide(); denyRows[i]:SetParent(nil) end
    denyRows = {}
    local y = -72
    for i = 1, table.getn(denyWorking) do
        local row = CreateFrame("Frame", nil, denyFrame); row:SetWidth(310); row:SetHeight(22); row:SetPoint("TOPLEFT", denyFrame, "TOPLEFT", 18, y)
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); text:SetPoint("LEFT", row, "LEFT", 2, 0); text:SetWidth(220); text:SetJustifyH("LEFT"); text:SetText(denyWorking[i]); text:SetTextColor(0.90,0.95,0.75)
        local captured = i
        MakeButton(row, "X", 24, 246, 0, function() table.remove(denyWorking, captured); RefreshDenyRows() end)
        table.insert(denyRows, row); y = y - 24
    end
end

local function HideAbilitySuggestions()
    if abilityMenu then abilityMenu:Hide() end
    for i = 1, table.getn(abilitySuggestionRows) do
        abilitySuggestionRows[i]:Hide()
        abilitySuggestionRows[i]:SetParent(nil)
    end
    abilitySuggestionRows = {}
end

local function ListedDenyNames(input)
    if denyFrame and input == denyFrame.input then return denyWorking end
    if settingsAbilityInput and input == settingsAbilityInput then
        local rules = EnsureDB().denyRules
        if settingsRuleIndex and rules[settingsRuleIndex] then return rules[settingsRuleIndex].abilities end
    end
    return nil
end

local function AbilityAlreadyListed(input, ability)
    local list = ListedDenyNames(input)
    if type(list) ~= "table" then return false end
    local lower = string.lower(ability)
    for i = 1, table.getn(list) do
        if string.lower(list[i]) == lower then return true end
    end
    return false
end

local function RefreshAbilitySuggestions(input, class, role)
    if not input then return end
    HideAbilitySuggestions()
    local query = string.lower(C.Trim(input:GetText()))
    if query == "" then return end
    class = ClassValue(class or (settingsClassButton and settingsClassButton.label:GetText()) or "shaman")
    role = RoleValue(role or (settingsRoleButton and settingsRoleButton.label:GetText()) or "Melee DPS")
    if role ~= "all" and not C.RoleAllowedForClass(class, role) then return end
    local catalog = C.AbilitiesForClassRole(ShirsRaidBuilderAbilities, class, role)
    local denied = nil
    if role ~= "all" then
        denied = {}
        local preset = (type(DB) == "table" and type(C.ActivePreset) == "function") and C.ActivePreset(DB, DB.uiMode) or nil
        local rules = type(preset) == "table" and preset.denyRules or nil
        for i = 1, table.getn(rules or {}) do
            local rule = rules[i]
            local ruleRole = string.lower(C.Trim(rule.role or ""))
            if string.lower(C.Trim(rule.class or "")) == string.lower(class)
                and (ruleRole == role or ruleRole == "all") then
                for ai = 1, table.getn(rule.abilities or {}) do
                    denied[string.lower(C.Trim(rule.abilities[ai]))] = true
                end
            end
        end
    end
    local matches = {}
    for i = 1, table.getn(catalog) do
        local ability = catalog[i]
        local lower = string.lower(ability)
        if lower ~= query and not AbilityAlreadyListed(input, ability)
            and (not denied or not denied[lower]) and string.find(lower, query, 1, true) then
            table.insert(matches, ability)
            if table.getn(matches) >= 8 then break end
        end
    end
    if table.getn(matches) == 0 then return end
    if not abilityMenu then
        abilityMenu = CreateFrame("Frame", "ShirsRaidBuilderAbilityMenu", UIParent)
        RegisterEscapeFrame(abilityMenu)
    end
    StyleMenuFrame(abilityMenu)
    abilityMenu:ClearAllPoints()
    abilityMenu:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -4, -2)
    abilityMenu:SetWidth(198)
    abilityMenu:SetHeight(table.getn(matches) * 20 + 8)
    for i = 1, table.getn(matches) do
        local option = CreateFrame("Button", nil, abilityMenu)
        option:SetWidth(190); option:SetHeight(18)
        option:SetPoint("TOPLEFT", abilityMenu, "TOPLEFT", 4, -4 - ((i - 1) * 20))
        local text = option:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", option, "LEFT", 4, 0)
        text:SetText(matches[i])
        text:SetTextColor(0.92, 0.95, 1.0)
        option:SetScript("OnEnter", function() text:SetTextColor(1.0, 0.86, 0.35) end)
        option:SetScript("OnLeave", function() text:SetTextColor(0.92, 0.95, 1.0) end)
        local selected = matches[i]
        option:SetScript("OnClick", function()
            input:SetText(selected)
            HideAbilitySuggestions()
        end)
        table.insert(abilitySuggestionRows, option)
    end
    abilityMenu:Show()
end

local function AddWorkingDeny()
    HideAbilitySuggestions()
    local value = C.Trim(denyFrame.input:GetText())
    if value ~= "" then table.insert(denyWorking, value); denyWorking = C.NormalizeDenyList(denyWorking); denyFrame.input:SetText(""); RefreshDenyRows() end
end

OpenDenyEditor = function(index)
    local entry = EnsureDB().entries[index]; if not entry or entry.kind ~= "legacy" then SetStatus("Only legacy hires can have custom deny lists."); return end
    denyIndex = index; denyWorking = C.CopyDenyList(entry.denyList)
    if not denyFrame then
        denyFrame = CreateFrame("Frame", "ShirsRaidBuilderDenyFrame", UIParent); denyFrame:SetWidth(350); denyFrame:SetHeight(280); StylePanelFrame(denyFrame)
        denyFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
        RegisterEscapeFrame(denyFrame)
        denyFrame:SetScript("OnHide", HideAbilitySuggestions)
        denyFrame.title = denyFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight"); denyFrame.title:SetPoint("TOP",denyFrame,"TOP",0,-14)
        denyFrame.note = denyFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); denyFrame.note:SetPoint("TOPLEFT",denyFrame,"TOPLEFT",18,-34); denyFrame.note:SetText("Character-specific additions; group rules are in Settings."); denyFrame.note:SetTextColor(0.75,0.80,0.90)
        denyFrame.input = MakeInput(denyFrame, 240, 18, -54, "")
        denyFrame.input:SetScript("OnEnterPressed", AddWorkingDeny)
        denyFrame.input:SetScript("OnTextChanged", function()
            local current = EnsureDB().entries[denyIndex]
            RefreshAbilitySuggestions(denyFrame.input, current and current.class or "shaman", current and current.role or "mdps")
        end)
        MakeButton(denyFrame,"Add",64,264,-54,AddWorkingDeny)
        MakeButton(denyFrame,"Save",64,18,14,function() HideAbilitySuggestions(); EnsureDB().entries[denyIndex].denyList=C.NormalizeDenyList(denyWorking); denyFrame:Hide(); RefreshComposition() end, true)
        MakeButton(denyFrame,"Cancel",64,86,14,function() HideAbilitySuggestions(); denyFrame:Hide() end, true)
    end
    denyFrame.title:SetText("Extra denies: " .. (C.GetLegacyWhisperName(entry) ~= "" and C.GetLegacyWhisperName(entry) or (entry.charName or "entry"))); denyFrame.input:SetText(""); HideAbilitySuggestions(); RefreshDenyRows(); denyFrame:Show()
end
ShirsRaidBuilder_OpenDenyEditor = OpenDenyEditor

function C.ResetDenyRuleEditor()
    settingsRuleIndex = nil
    settingsRoleButton.label:SetText("Melee DPS")
    settingsClassButton.options = ClassesForRole("mdps")
    settingsClassButton.label:SetText("Shaman")
    settingsAbilityInput:SetText("")
    HideAbilitySuggestions()
end

local function RefreshRuleList()
    if not settingsFrame then return end
    for i = 1, table.getn(settingsFrame.ruleRows or {}) do settingsFrame.ruleRows[i]:Hide(); settingsFrame.ruleRows[i]:SetParent(nil) end
    settingsFrame.ruleRows = {}; local y = -180
    local rules = EnsureDB().denyRules
    for i = 1, table.getn(rules) do
        local rule = rules[i]; local row = CreateFrame("Button",nil,settingsFrame); row:SetWidth(360); row:SetHeight(30); row:SetPoint("TOPLEFT",settingsFrame,"TOPLEFT",18,y)
        local text = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); text:SetPoint("LEFT",row,"LEFT",4,0); text:SetWidth(278)
        text:SetText((ROLE_LABELS[rule.role] or rule.role) .. " / " .. (CLASS_LABELS[rule.class] or rule.class) .. ": " .. table.concat(rule.abilities, ", ")); text:SetTextColor(0.85,0.90,1.0)
        local captured=i; row:SetScript("OnClick",function()
            settingsRuleIndex=captured
            settingsRoleButton.label:SetText(ROLE_LABELS[rule.role] or rule.role)
            settingsClassButton.options=ClassesForRole(rule.role)
            settingsClassButton.label:SetText(CLASS_LABELS[rule.class] or rule.class)
            settingsAbilityInput:SetText("")
            RefreshAbilitySuggestions(settingsAbilityInput)
            SetStatus("Selected deny rule. Add abilities to update it.")
        end)
        MakeButton(row,"Remove",64,296,0,function()
            table.remove(EnsureDB().denyRules, captured)
            C.ResetDenyRuleEditor()
            RefreshRuleList(); RefreshComposition(); SetStatus("Removed deny rule. Ready to add another.")
        end)
        table.insert(settingsFrame.ruleRows,row); y=y-32
    end
end

local function OpenSettings()
    if not settingsFrame then
        settingsFrame=CreateFrame("Frame","ShirsRaidBuilderSettingsFrame",UIParent); settingsFrame:SetWidth(410); settingsFrame:SetHeight(390); StylePanelFrame(settingsFrame); settingsFrame:SetPoint("CENTER",UIParent,"CENTER",0,0)
        settingsFrame.title=settingsFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight"); settingsFrame.title:SetPoint("TOP",settingsFrame,"TOP",0,-14)
        RegisterEscapeFrame(settingsFrame)
        settingsFrame:SetScript("OnHide", function() HideAbilitySuggestions(); CloseChoiceMenu() end)
        local note=settingsFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); note:SetPoint("TOPLEFT",settingsFrame,"TOPLEFT",18,-34); note:SetText("Rules match role + class, or all roles of one class, in this preset."); note:SetTextColor(0.75,0.80,0.90)
        MakeCaption(settingsFrame, "Role", 18, -52)
        MakeCaption(settingsFrame, "Class", 148, -52)
        MakeCaption(settingsFrame, "Ability", 18, -92)
        settingsRoleButton=SelectButton(settingsFrame, {"All Roles","Tank","Healer","Ranged DPS","Melee DPS"}, "Melee DPS", 122,18,-68,function(v)
            local classes=ClassesForRole(RoleValue(v))
            settingsClassButton.options=classes
            settingsClassButton.label:SetText(classes[1] or "(none)")
            RefreshAbilitySuggestions(settingsAbilityInput, nil, RoleValue(v))
        end)
        settingsClassButton=SelectButton(settingsFrame, ClassesForRole("mdps"), "Shaman", 110,148,-68,function() RefreshAbilitySuggestions(settingsAbilityInput) end)
        settingsAbilityInput=MakeInput(settingsFrame,190,18,-108,"")
        settingsAbilityInput:SetScript("OnTextChanged", function() RefreshAbilitySuggestions(settingsAbilityInput) end)
        local addAbility=MakeButton(settingsFrame,"Add Ability",86,214,-106,function()
            local v=C.Trim(settingsAbilityInput:GetText())
            if v~="" then
                local p=EnsureDB(); local role=RoleValue(settingsRoleButton.label:GetText()); local class=ClassValue(settingsClassButton.label:GetText())
                local idx=settingsRuleIndex or table.getn(p.denyRules)+1
                local lowerV=string.lower(v)
                for ri = 1, table.getn(p.denyRules) do
                    local rule = p.denyRules[ri]
                    local ruleRole = string.lower(C.Trim(rule.role or ""))
                    if string.lower(C.Trim(rule.class or "")) == string.lower(class)
                        and (ruleRole == role or ruleRole == "all") then
                        local abilities = C.NormalizeDenyList(rule.abilities or {})
                        for ai = 1, table.getn(abilities) do
                            if string.lower(abilities[ai]) == lowerV then
                                local label = ROLE_LABELS[rule.role] .. " / " .. (CLASS_LABELS[rule.class] or rule.class)
                                SetStatus(v .. " is already denied by " .. label .. ".")
                                return
                            end
                        end
                    end
                end
                if not p.denyRules[idx] then p.denyRules[idx]={role=role,class=class,abilities={}} end
                p.denyRules[idx].role=role; p.denyRules[idx].class=class
                table.insert(p.denyRules[idx].abilities,v); p.denyRules[idx].abilities=C.NormalizeDenyList(p.denyRules[idx].abilities)
                settingsRuleIndex=idx; settingsAbilityInput:SetText(""); HideAbilitySuggestions(); RefreshRuleList(); RefreshComposition()
            end
        end)
        addAbility:SetFrameLevel(settingsFrame:GetFrameLevel()+6)
        MakeButton(settingsFrame,"New",64,18,14,C.ResetDenyRuleEditor,true)
        MakeButton(settingsFrame,"Close",64,86,14,function() HideAbilitySuggestions(); settingsFrame:Hide() end,true)
        settingsFrame.ruleRows={}
    end
    settingsFrame.title:SetText("Deny rules: " .. (DB.currentPreset or "Default")); RefreshRuleList(); settingsFrame:Show()
end

local EARTH_TOTEMS = {"(none)","Strength of Earth Totem","Stoneskin Totem","Tremor Totem","Earthbind Totem","Stoneclaw Totem","cancel"}
local FIRE_TOTEMS = {"(none)","Flametongue Totem","Searing Totem","Magma Totem","Fire Nova Totem","Frost Resistance Totem","cancel"}
local WATER_TOTEMS = {"(none)","Mana Spring Totem","Healing Stream Totem","Fire Resistance Totem","Poison Cleansing Totem","Disease Cleansing Totem","Mana Tide Totem","cancel"}
local AIR_TOTEMS = {"(none)","Windfury Totem","Grace of Air Totem","Grounding Totem","Tranquil Air Totem","Nature Resistance Totem","Windwall Totem","cancel"}
local PALADIN_AURAS = {"(none)","Devotion Aura","Retribution Aura","Sanctity Aura","Concentration Aura","Fire Resistance Aura","Frost Resistance Aura","Shadow Resistance Aura","cancel"}
local HUNTER_ASPECTS = {"(none)","AI Default (Clear Setting)","Aspect of the Hawk","Aspect of the Cheetah","Aspect of the Pack","Aspect of the Wild"}
local HUNTER_PETS = {"(none)","On","Off","Wolf","Cat","Bear","Crab","Gorilla","Bird","Boar","Bat","Croc","Spider","Owl","Strider","Scorpid","Serpent","Raptor","Turtle","Hyena"}
local WARLOCK_PETS = {"(none)","On","Off","Imp","Voidwalker","Succubus","Felhunter"}
local MAGE_MAGIC = {"(none)","None","Amplify","Dampen"}

local function ApplyValue(display)
    if display == "All" then return "all" end
    return RoleValue(display)
end

local function ApplyLabel(value)
    if value == "all" or value == "" or not value then return "All" end
    return ROLE_LABELS[value] or value
end

local function PickListed(options, current)
    if type(options) ~= "table" then return current end
    for i = 1, table.getn(options) do if options[i] == current then return current end end
    return options[1] or current
end

local function SetupApplyOptions(class)
    local result = {"All"}
    local roles = RoleOptions(class)
    for i = 1, table.getn(roles) do table.insert(result, roles[i]) end
    return result
end

local function SetupSpecOptions(class)
    local result = {"All"}
    local specs = SPECS[class] or {"default"}
    for i = 1, table.getn(specs) do table.insert(result, SPEC_LABELS[specs[i]] or specs[i]) end
    return result
end

local function SetupSummary(rule)
    local who = ApplyLabel(rule.role) .. " " .. (CLASS_LABELS[rule.class] or rule.class)
    if rule.spec and rule.spec ~= "" and rule.spec ~= "all" then who = who .. " / " .. (SPEC_LABELS[rule.spec] or rule.spec) end
    if rule.class == "paladin" then return who .. ": " .. (rule.aura or "(none)") end
    if rule.class == "hunter" then
        local parts = {}
        if rule.aspect and rule.aspect ~= "" then table.insert(parts, rule.aspect) end
        if rule.pet and rule.pet ~= "" then table.insert(parts, "Pet " .. rule.pet) end
        if table.getn(parts) == 0 then return who end
        return who .. ": " .. table.concat(parts, ", ")
    end
    if rule.class == "warlock" then
        if rule.pet and rule.pet ~= "" then return who .. ": Pet " .. rule.pet end
        return who
    end
    if rule.class == "mage" then
        if rule.magic and rule.magic ~= "" then return who .. ": Magic " .. rule.magic end
        return who
    end
    local parts = {}
    if rule.earth and rule.earth ~= "" then table.insert(parts, "Earth " .. rule.earth) end
    if rule.fire and rule.fire ~= "" then table.insert(parts, "Fire " .. rule.fire) end
    if rule.water and rule.water ~= "" then table.insert(parts, "Water " .. rule.water) end
    if rule.air and rule.air ~= "" then table.insert(parts, "Air " .. rule.air) end
    if table.getn(parts) == 0 then return who end
    return who .. ": " .. table.concat(parts, ", ")
end

local function ChosenOrEmpty(text)
    local value = C.Trim(text)
    if value == "" or value == "(none)" then return "" end
    return value
end

local function RefreshSetupList()
    if not setupFrame then return end
    for i = 1, table.getn(setupFrame.ruleRows or {}) do setupFrame.ruleRows[i]:Hide(); setupFrame.ruleRows[i]:SetParent(nil) end
    setupFrame.ruleRows = {}; local y = -236
    local rules = EnsureDB().setupRules
    for i = 1, table.getn(rules) do
        local rule = rules[i]; local row = CreateFrame("Button",nil,setupFrame); row:SetWidth(484); row:SetHeight(28); row:SetPoint("TOPLEFT",setupFrame,"TOPLEFT",18,y)
        local text = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); text:SetPoint("LEFT",row,"LEFT",4,0); text:SetWidth(380); text:SetJustifyH("LEFT")
        text:SetText(SetupSummary(rule)); text:SetTextColor(0.85,0.90,1.0)
        local captured=i
        MakeButton(row,"Remove",64,414,2,function()
            table.remove(EnsureDB().setupRules, captured)
            RefreshSetupList(); SetStatus("Removed totem/aura rule.")
        end)
        table.insert(setupFrame.ruleRows,row); y=y-30
    end
end

local function ShowSetupClassFields()
    if not setupFrame then return end
    local class = ClassValue(setupFrame.classButton.label:GetText())
    setupFrame.applyButton.options = SetupApplyOptions(class)
    setupFrame.applyButton.label:SetText(PickListed(setupFrame.applyButton.options, setupFrame.applyButton.label:GetText()))
    setupFrame.specButton.options = SetupSpecOptions(class)
    setupFrame.specButton.label:SetText(PickListed(setupFrame.specButton.options, "All"))
    setupFrame.earthButton:Hide(); setupFrame.fireButton:Hide(); setupFrame.waterButton:Hide(); setupFrame.airButton:Hide(); setupFrame.auraButton:Hide(); setupFrame.aspectButton:Hide(); setupFrame.petButton:Hide(); setupFrame.magicButton:Hide()
    setupFrame.earthCaption:Hide(); setupFrame.fireCaption:Hide(); setupFrame.waterCaption:Hide(); setupFrame.airCaption:Hide(); setupFrame.auraCaption:Hide(); setupFrame.aspectCaption:Hide(); setupFrame.petCaption:Hide(); setupFrame.magicCaption:Hide()
    if class == "paladin" then
        setupFrame.auraButton:Show(); setupFrame.auraCaption:Show()
    elseif class == "hunter" then
        setupFrame.aspectButton:Show(); setupFrame.aspectCaption:Show()
        setupFrame.petButton.options = HUNTER_PETS
        setupFrame.petButton.label:SetText("(none)")
        setupFrame.petCaption:ClearAllPoints(); setupFrame.petCaption:SetPoint("TOPLEFT", setupFrame, "TOPLEFT", 278, -96)
        setupFrame.petButton:ClearAllPoints(); setupFrame.petButton:SetPoint("TOPLEFT", setupFrame, "TOPLEFT", 278, -112)
        setupFrame.petButton:SetWidth(210)
        setupFrame.petButton:Show(); setupFrame.petCaption:Show()
    elseif class == "warlock" then
        setupFrame.petButton.options = WARLOCK_PETS
        setupFrame.petButton.label:SetText("(none)")
        setupFrame.petCaption:ClearAllPoints(); setupFrame.petCaption:SetPoint("TOPLEFT", setupFrame, "TOPLEFT", 18, -96)
        setupFrame.petButton:ClearAllPoints(); setupFrame.petButton:SetPoint("TOPLEFT", setupFrame, "TOPLEFT", 18, -112)
        setupFrame.petButton:SetWidth(210)
        setupFrame.petButton:Show(); setupFrame.petCaption:Show()
    elseif class == "mage" then
        setupFrame.magicButton:Show(); setupFrame.magicCaption:Show()
    else
        setupFrame.earthButton:Show(); setupFrame.fireButton:Show(); setupFrame.waterButton:Show(); setupFrame.airButton:Show()
        setupFrame.earthCaption:Show(); setupFrame.fireCaption:Show(); setupFrame.waterCaption:Show(); setupFrame.airCaption:Show()
    end
end

local function OpenSetup()
    if not setupFrame then
        setupFrame=CreateFrame("Frame","ShirsRaidBuilderSetupFrame",UIParent); setupFrame:SetWidth(520); setupFrame:SetHeight(430); StylePanelFrame(setupFrame); setupFrame:SetPoint("CENTER",UIParent,"CENTER",0,0)
        setupFrame.title=setupFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight"); setupFrame.title:SetPoint("TOP",setupFrame,"TOP",0,-14)
        MakeButton(setupFrame,"X",22,480,-8,function() CloseChoiceMenu(); setupFrame:Hide() end)
        local note=setupFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); note:SetPoint("TOPLEFT",setupFrame,"TOPLEFT",18,-34); note:SetWidth(480); note:SetJustifyH("LEFT"); note:SetText("After hiring, whisper companions first, then overwrite matching legacy hires."); note:SetTextColor(0.75,0.80,0.90)
        MakeCaption(setupFrame, "Class", 18, -52)
        MakeCaption(setupFrame, "Apply to", 176, -52)
        MakeCaption(setupFrame, "Spec", 334, -52)
        setupFrame.classButton=SelectButton(setupFrame, {"Shaman","Paladin","Hunter","Warlock","Mage"}, "Shaman", 148,18,-68,function() ShowSetupClassFields() end)
        setupFrame.applyButton=SelectButton(setupFrame, SetupApplyOptions("shaman"), "All", 148,176,-68,function() end)
        setupFrame.specButton=SelectButton(setupFrame, SetupSpecOptions("shaman"), "All", 148,334,-68,function() end)
        setupFrame.earthCaption=MakeCaption(setupFrame, "Earth", 18, -96)
        setupFrame.fireCaption=MakeCaption(setupFrame, "Fire", 268, -96)
        setupFrame.waterCaption=MakeCaption(setupFrame, "Water", 18, -140)
        setupFrame.airCaption=MakeCaption(setupFrame, "Air", 268, -140)
        setupFrame.auraCaption=MakeCaption(setupFrame, "Aura", 18, -96)
        setupFrame.aspectCaption=MakeCaption(setupFrame, "Aspect", 18, -96)
        setupFrame.petCaption=MakeCaption(setupFrame, "Pet", 18, -96)
        setupFrame.magicCaption=MakeCaption(setupFrame, "Magic", 18, -96)
        setupFrame.earthButton=SelectButton(setupFrame, EARTH_TOTEMS, "(none)", 240,18,-112,function() end)
        setupFrame.fireButton=SelectButton(setupFrame, FIRE_TOTEMS, "(none)", 240,268,-112,function() end)
        setupFrame.waterButton=SelectButton(setupFrame, WATER_TOTEMS, "(none)", 240,18,-156,function() end)
        setupFrame.airButton=SelectButton(setupFrame, AIR_TOTEMS, "(none)", 240,268,-156,function() end)
        setupFrame.auraButton=SelectButton(setupFrame, PALADIN_AURAS, "(none)", 240,18,-112,function() end)
        setupFrame.aspectButton=SelectButton(setupFrame, HUNTER_ASPECTS, "(none)", 240,18,-112,function() end)
        setupFrame.petButton=SelectButton(setupFrame, HUNTER_PETS, "(none)", 240,18,-112,function() end)
        setupFrame.magicButton=SelectButton(setupFrame, MAGE_MAGIC, "(none)", 240,18,-112,function() end)
        MakeButton(setupFrame,"Add Rule",86,18,-196,function()
            local class=ClassValue(setupFrame.classButton.label:GetText())
            local rule={class=class, role=ApplyValue(setupFrame.applyButton.label:GetText()), spec=SpecValue(setupFrame.specButton.label:GetText())}
            if rule.spec == "" then rule.spec = "all" end
            if class == "paladin" then
                rule.aura=ChosenOrEmpty(setupFrame.auraButton.label:GetText())
                if rule.aura == "" then SetStatus("Choose a Paladin aura first."); return end
            elseif class == "hunter" then
                rule.aspect=ChosenOrEmpty(setupFrame.aspectButton.label:GetText())
                rule.pet=ChosenOrEmpty(setupFrame.petButton.label:GetText())
                if rule.aspect == "" and rule.pet == "" then SetStatus("Choose an aspect or a pet first."); return end
            elseif class == "warlock" then
                rule.pet=ChosenOrEmpty(setupFrame.petButton.label:GetText())
                if rule.pet == "" then SetStatus("Choose a Warlock pet first."); return end
            elseif class == "mage" then
                rule.magic=ChosenOrEmpty(setupFrame.magicButton.label:GetText())
                if rule.magic == "" then SetStatus("Choose None, Amplify, or Dampen first."); return end
            else
                rule.earth=ChosenOrEmpty(setupFrame.earthButton.label:GetText())
                rule.fire=ChosenOrEmpty(setupFrame.fireButton.label:GetText())
                rule.water=ChosenOrEmpty(setupFrame.waterButton.label:GetText())
                rule.air=ChosenOrEmpty(setupFrame.airButton.label:GetText())
                if rule.earth=="" and rule.fire=="" and rule.water=="" and rule.air=="" then SetStatus("Choose at least one totem slot."); return end
            end
            table.insert(EnsureDB().setupRules, rule)
            RefreshSetupList(); SetStatus("Saved " .. SetupSummary(rule) .. ".")
        end)
        MakeButton(setupFrame,"Close",64,18,14,function() CloseChoiceMenu(); setupFrame:Hide() end,true)
        setupFrame.ruleRows={}
        setupFrame:SetScript("OnHide", CloseChoiceMenu)
        RegisterEscapeFrame(setupFrame)
        ShowSetupClassFields()
    end
    setupFrame.title:SetText("Other commands: " .. (DB.currentPreset or "Default")); RefreshSetupList(); setupFrame:Show()
end

local function HideLegacyNameSuggestions()
    if legacyNameMenu then legacyNameMenu:Hide() end
    for i = 1, table.getn(legacyNameRows) do
        legacyNameRows[i]:Hide()
        legacyNameRows[i]:SetParent(nil)
    end
    legacyNameRows = {}
end

local function RefreshLegacyNameSuggestions(input)
    if not input then return end
    HideLegacyNameSuggestions()
    local query = string.lower(C.Trim(input:GetText()))
    local names = DiscoverCharacterNames()
    local matches = {}
    for i = 1, table.getn(names) do
        local name = names[i]
        local lower = string.lower(name)
        if query == "" or string.find(lower, query, 1, true) then
            if lower ~= query then
                table.insert(matches, name)
                if table.getn(matches) >= 5 then break end
            end
        end
    end
    if table.getn(matches) == 0 then return end
    local host = input:GetParent() or UIParent
    if not legacyNameMenu then
        legacyNameMenu = CreateFrame("Frame", "ShirsRaidBuilderLegacyNameMenu", host)
    else
        legacyNameMenu:SetParent(host)
    end
    legacyNameMenu:SetBackdrop(DROP_BG)
    legacyNameMenu:SetBackdropColor(0.02, 0.03, 0.06, 1.0)
    legacyNameMenu:SetBackdropBorderColor(0.55, 0.68, 0.88, 1.0)
    legacyNameMenu:SetFrameStrata(host.GetFrameStrata and host:GetFrameStrata() or "FULLSCREEN_DIALOG")
    legacyNameMenu:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 80) + 4)
    legacyNameMenu:ClearAllPoints()
    legacyNameMenu:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -4, -2)
    legacyNameMenu:SetWidth(158)
    legacyNameMenu:SetHeight(table.getn(matches) * 20 + 8)
    if host.addButton then host.addButton:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 80) + 20) end
    if host.cancelButton then host.cancelButton:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 80) + 20) end
    for i = 1, table.getn(matches) do
        local option = CreateFrame("Button", nil, legacyNameMenu)
        option:SetWidth(150); option:SetHeight(18)
        option:SetPoint("TOPLEFT", legacyNameMenu, "TOPLEFT", 4, -4 - ((i - 1) * 20))
        local text = option:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", option, "LEFT", 4, 0)
        text:SetText(matches[i])
        text:SetTextColor(0.92, 0.95, 1.0)
        option:SetScript("OnEnter", function() text:SetTextColor(1.0, 0.86, 0.35) end)
        option:SetScript("OnLeave", function() text:SetTextColor(0.92, 0.95, 1.0) end)
        local selected = matches[i]
        option:SetScript("OnClick", function()
            input:SetText(selected)
            HideLegacyNameSuggestions()
        end)
        table.insert(legacyNameRows, option)
    end
    legacyNameMenu:Show()
end

local function RefreshNormalHireOptions(frame)
    if not frame or not frame.roleButton or not frame.classButton then return end
    local role = RoleValue(frame.roleButton.label:GetText())
    local classes = ClassesForRole(role, frame.selectedFaction)
    frame.classButton.options = classes
    frame.classButton.label:SetText(PickListed(classes, frame.classButton.label:GetText()))
    local classKey = ClassValue(frame.classButton.label:GetText())
    if frame.specButton then
        local specs = LabeledKeys(SpecsForClassRole(classKey, role), SPEC_LABELS)
        frame.specButton.options = specs
        frame.specButton.label:SetText(PickListed(specs, frame.specButton.label:GetText()))
    end
    if frame.tierButton then
        local tiers = TiersForCharacter(frame.characterButton and frame.characterButton.label:GetText())
        frame.tierButton.options = tiers
        frame.tierButton.label:SetText(PickListed(tiers, frame.tierButton.label:GetText()))
    end
    if frame.raceButton then
        local races = LabeledKeys(RacesForClassAndFaction(classKey, frame.selectedFaction), RACE_LABELS)
        frame.raceButton.options = races
        frame.raceButton.label:SetText(PickListed(races, frame.raceButton.label:GetText()))
    end
end

local function AddEntryEditor(kind)
    local frame = kind == "normal" and addNormalFrame or addLegacyFrame
    if not frame then
        frame=CreateFrame("Frame",kind=="normal" and "ShirsRaidBuilderAddNormal" or "ShirsRaidBuilderAddLegacy",UIParent); frame:SetWidth(kind=="normal" and 568 or 440); frame:SetHeight(kind=="normal" and 176 or 210); StylePanelFrame(frame); frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
        local title=frame:CreateFontString(nil,"OVERLAY","GameFontHighlight"); title:SetPoint("TOP",frame,"TOP",0,-12); title:SetText(kind=="normal" and "Add normal hire" or "Add legacy hire")
        MakeButton(frame,"X",22,kind=="normal" and 528 or 400,-8,function() if kind=="legacy" then HideLegacyNameSuggestions() end; frame:Hide() end)
        if kind == "normal" then
            frame.selectedFaction=nil
            MakeCaption(frame, "Character", 18, -30)
            frame.characterButton=SelectButton(frame,{"(none)"},"(none)",128,18,-46,function(v)
                frame.selectedFaction=FactionForCharacter(v)
                RefreshNormalHireOptions(frame)
                SetStatus(frame.selectedFaction and (v .. " is " .. frame.selectedFaction .. ".") or (v .. " faction is unknown; log that character once, or pick a race."))
            end)
        else
            MakeCaption(frame, "Character name", 18, -30)
            frame.nameInput=MakeInput(frame,150,18,-46,"")
            frame.nameInput:SetMaxLetters(12)
            frame.nameInput:SetScript("OnTextChanged", function() RefreshLegacyNameSuggestions(frame.nameInput) end)
            frame.nameInput:SetScript("OnEditFocusGained", function() RefreshLegacyNameSuggestions(frame.nameInput) end)
            frame.nameInput:SetScript("OnEditFocusLost", function() end)
            frame.nameInput:SetScript("OnEnterPressed", function() HideLegacyNameSuggestions() end)
        end
        MakeCaption(frame, "Role", 156, -30)
        frame.roleButton=SelectButton(frame, {"Tank","Healer","Ranged DPS","Melee DPS"}, "Melee DPS",128,156,-46,function()
            if kind == "normal" then RefreshNormalHireOptions(frame) else
                local classes=ClassesForRole(RoleValue(frame.roleButton.label:GetText()))
                frame.classButton.options=classes
                frame.classButton.label:SetText(classes[1] or "(none)")
            end
        end)
        MakeCaption(frame, "Class", 294, -30)
        frame.classButton=SelectButton(frame,ClassesForRole("mdps"),"Warrior",128,294,-46,function()
            if kind == "normal" then RefreshNormalHireOptions(frame) end
        end)
        if kind=="normal" then
            MakeCaption(frame, "Tier", 432, -30)
            frame.tierButton=SelectButton(frame,TIERS,"t2r",118,432,-46,function() end)
            MakeCaption(frame, "Spec", 18, -76)
            frame.specButton=SelectButton(frame,LabeledKeys(SPECS.warrior, SPEC_LABELS),"Default",128,18,-92,function() end)
            MakeCaption(frame, "Race", 156, -76)
            frame.raceButton=SelectButton(frame,LabeledKeys(RacesForClassAndFaction("warrior", frame.selectedFaction), RACE_LABELS),"Human",128,156,-92,function() end)
            MakeCaption(frame, "Gender", 294, -76)
            frame.genderButton=SelectButton(frame,LabeledKeys(GENDERS, GENDER_LABELS),"Male",128,294,-92,function() end)
            MakeButton(frame,"Add",64,86,14,function()
                local f=frame; local p=EnsureDB(); local account=C.Trim(f.characterButton.label:GetText())
                if account == "" or account == "(none)" then SetStatus("Select a saved character first."); return end
                local race=RaceValue(f.raceButton.label:GetText())
                local entry={kind="normal",account=account,tier=f.tierButton.label:GetText(),class=ClassValue(f.classButton.label:GetText()),role=RoleValue(f.roleButton.label:GetText()),spec=SpecValue(f.specButton.label:GetText()),race=race,gender=GenderValue(f.genderButton.label:GetText())}
                local slot, reason=C.TryAddNormalHire(p.entries, entry, 4, 40)
                if not slot then
                    if reason == "character-limit" then SetStatus(account .. " already has the maximum four companions in this hiring plan.")
                    elseif reason == "raid-full" then SetStatus("All 40 raid slots are full.")
                    else SetStatus("Could not add that normal hire.") end
                    return
                end
                RememberFaction(account, RACE_FACTIONS[race] or f.selectedFaction)
                RefreshComposition(); SetStatus("Added normal hire from " .. account .. " in spawn " .. slot .. ".")
            end,true)
            MakeButton(frame,"Cancel",64,18,14,function() frame:Hide() end,true); addNormalFrame=frame
        else
            frame.addButton=MakeButton(frame,"Add",64,86,14,function()
                local f=frame; local p=EnsureDB(); local typed=C.Trim(f.nameInput:GetText())
                if typed == "" then SetStatus("Enter the real character name first."); return end
                if not C.IsSafeCharacterName(typed) then SetStatus("Character names must use 2-12 letters only."); return end
                if string.sub(string.lower(typed), -5) == "-lite" then SetStatus("Type the real name (Longname). The card still shows Longnam-lite."); return end
                local hireName=typed
                local whisperName=C.NormalizeLegacyName(hireName)
                f.nameInput:SetText(hireName)
                HideLegacyNameSuggestions()
                local slot=C.FirstEmptySlot(p.entries, 40)
                if not slot then SetStatus("All 40 raid slots are full."); return end
                p.entries[slot]={kind="legacy",sourceName=hireName,charName=hireName,role=RoleValue(f.roleButton.label:GetText()),class=ClassValue(f.classButton.label:GetText()),spec="",denyList={},whisperName=whisperName}
                RefreshComposition(); SetStatus("Added " .. whisperName .. " (hires " .. hireName .. ") in spawn " .. slot .. ".")
            end,true)
            frame.cancelButton=MakeButton(frame,"Cancel",64,18,14,function() HideLegacyNameSuggestions(); frame:Hide() end,true); addLegacyFrame=frame
        end
    end
    if kind == "normal" then
        local savedNames=DiscoverCharacterNames(); if table.getn(savedNames)==0 then savedNames={"(none)"} end
        frame.characterButton.options=savedNames
        local selected=frame.characterButton.label:GetText(); local valid=false
        for i=1,table.getn(savedNames) do if savedNames[i]==selected then valid=true end end
        if not valid then frame.characterButton.label:SetText(savedNames[1]) end
        frame.selectedFaction=FactionForCharacter(frame.characterButton.label:GetText())
        RefreshNormalHireOptions(frame)
    end
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:Show()
    if frame.characterButton and frame.characterButton.SetFrameLevel then frame.characterButton:SetFrameLevel((frame:GetFrameLevel() or 10) + 5) end
end

local function OpenNamePrompt(titleText, initial, onSave)
    if not namePrompt then
        namePrompt = CreateFrame("Frame", "ShirsRaidBuilderNamePrompt", UIParent)
        namePrompt:SetWidth(310); namePrompt:SetHeight(120); StylePanelFrame(namePrompt)
        RegisterEscapeFrame(namePrompt)
        namePrompt:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        namePrompt.title = namePrompt:CreateFontString(nil,"OVERLAY","GameFontHighlight"); namePrompt.title:SetPoint("TOP",namePrompt,"TOP",0,-14)
        namePrompt.input = MakeInput(namePrompt,250,20,-44,"")
        MakeButton(namePrompt,"Save",64,20,14,function() local name=C.Trim(namePrompt.input:GetText()); if name~="" then namePrompt:Hide(); if namePrompt.save then namePrompt.save(name) end end end, true)
        MakeButton(namePrompt,"Cancel",64,88,14,function() namePrompt:Hide() end, true)
    end
    namePrompt.title:SetText(titleText); namePrompt.input:SetText(initial or ""); namePrompt.save=onSave; namePrompt:Show(); namePrompt.input:SetFocus()
end

function C.SaveSortLayout()
    EnsureDB()
    local _, current = C.PresetBank(DB, "sort")
    OpenNamePrompt("Save sort layout", current or "Default", function(name)
        DB.sortPresets[name] = C.CopyPreset(C.ActivePreset(DB, "sort"))
        DB.sortPresets[name].sortLayout = true
        DB.currentSortPreset = name
        EnsureDB(); RefreshPresetButton(); RefreshComposition()
        SetStatus("Saved sort layout "..name.." in the addon.")
    end)
end

local function NewPreset()
    local title = DB.uiMode == "sort" and "New sort layout" or "New composition profile"
    OpenNamePrompt(title, "", function(name)
        local bank = C.PresetBank(DB, DB.uiMode)
        if bank[name] then SetStatus("A profile with that name already exists."); return end
        bank[name] = C.BlankPreset()
        if DB.uiMode == "sort" then DB.currentSortPreset = name else DB.currentPreset = name end
        EnsureDB(); RefreshPresetButton(); RefreshComposition()
    end)
end

local function RenamePreset()
    local _, current = C.PresetBank(DB, DB.uiMode)
    local title = DB.uiMode == "sort" and "Rename sort layout" or "Rename composition profile"
    OpenNamePrompt(title, current, function(name)
        if name == current then return end
        local bank = C.PresetBank(DB, DB.uiMode)
        if bank[name] then SetStatus("A profile with that name already exists."); return end
        bank[name] = bank[current]; bank[current] = nil
        if DB.uiMode == "sort" then DB.currentSortPreset = name else DB.currentPreset = name end
        EnsureDB(); RefreshPresetButton(); RefreshComposition()
    end)
end

local function DeletePreset()
    local names=GetPresetNames(); if table.getn(names)<=1 then return end
    local bank, current = C.PresetBank(DB, DB.uiMode)
    bank[current]=nil
    if DB.uiMode == "sort" then DB.currentSortPreset=names[1] else DB.currentPreset=names[1] end
    if names[1]==current then DB.currentSortPreset=names[2] or names[1]; if DB.uiMode ~= "sort" then DB.currentPreset=names[2] or names[1] end end
    EnsureDB(); RefreshPresetButton(); RefreshComposition()
end

local function IsRealCharacterName(name)
    local value = C.Trim(name)
    if value == "" then return false end
    local lower = string.lower(value)
    if lower == "unknown" or lower == "unknow" then return false end
    return true
end

local function SnapshotGroup()
    local snapshot = {}
    local function AddUnit(unit)
        if type(UnitName) ~= "function" then return end
        local name = UnitName(unit)
        if IsRealCharacterName(name) then snapshot[name] = true end
    end
    AddUnit("player")
    if type(GetNumPartyMembers) == "function" then
        local party = GetNumPartyMembers() or 0
        for i = 1, party do AddUnit("party" .. i) end
    end
    if type(GetNumRaidMembers) == "function" then
        local raid = GetNumRaidMembers() or 0
        for i = 1, raid do AddUnit("raid" .. i) end
    end
    return snapshot
end

local function CompanionAlreadyUsed(name)
    if not IsRealCharacterName(name) then return false end
    for _, assigned in pairs(executeCompanions) do
        if assigned == name then return true end
    end
    return false
end

local function ApplyDetectedCompanionName(hireIndex, name)
    if not name or name == "" or not executeQueue then return false end
    if not IsRealCharacterName(name) then return false end
    local hire = executeQueue[hireIndex]
    local sourceIndex = hire and hire.sourceEntryIndex
    if not sourceIndex then return false end
    if executeCompanions[sourceIndex] and IsRealCharacterName(executeCompanions[sourceIndex]) then return false end
    executeCompanions[sourceIndex] = name
    local changed = false
    for i = 1, table.getn(executeQueue) do
        local queued = executeQueue[i]
        if queued.kind == "deny" and queued.phase == "role-class-final" and queued.sourceEntryIndex == sourceIndex then
            queued.target = name
            changed = true
        end
    end
    if changed then Chat("Detected companion: " .. name .. ". Final role/class denies will whisper this character.") end
    return changed
end

local function AssignNewCompanions()
    if not executeQueue then return end
    local now = SnapshotGroup()
    local newNames = {}
    for name in pairs(now) do
        if (not executeBaseline or not executeBaseline[name]) and not CompanionAlreadyUsed(name) then
            if type(UnitName) ~= "function" or name ~= UnitName("player") then
                table.insert(newNames, name)
            end
        end
    end
    if table.getn(newNames) == 0 then return end
    table.sort(newNames)
    local assigned = C.AssignDetectedCompanions(executeQueue, executeCompanions, newNames)
    if assigned > 0 then
        Chat("Matched " .. assigned .. " hired companion(s) to board slots.")
    end
end

local function ResolveRoleDenyTarget(entry)
    if not entry or entry.phase ~= "role-class-final" then return true end
    return entry.target and entry.target ~= ""
end

local function RequestCompanionInfo()
    if type(SendAddonMessage) ~= "function" then
        Chat("This client cannot query companion role/class names.")
        return false
    end
    local now = GetTime and GetTime() or 0
    if C.grinfoAskedAt and now > 0 and (now - C.grinfoAskedAt) < 3 then return true end
    C.grinfoAskedAt = now
    if not executeRequestFrame then executeRequestFrame = CreateFrame("Frame") end
    executeRequestFrame:SetScript("OnUpdate", function()
        SendAddonMessage("nexus", "GRINFO:ALL:FULL", "BATTLEGROUND")
        executeRequestFrame:SetScript("OnUpdate", nil)
    end)
    Chat("Asking the server for companion names by role and class.")
    return true
end

local function HandleCompanionInfoMessage()
    if (not executing) and (not C.sortWaiting) then return end
    local raw = tostring(arg1 or "")
    if arg2 and arg2 ~= "" then raw = raw .. " " .. tostring(arg2) end
    local startPos, endPos = string.find(raw, "%[nexus%]")
    if not startPos then
        if string.find(raw, "GRINFO:") then
            startPos = 0
            endPos = 0
        else
            return
        end
    end
    if arg3 and arg3 ~= "" and arg3 ~= "UNKNOWN" and arg3 ~= "BATTLEGROUND" then return end
    local response = raw
    if endPos and endPos > 0 then response = string.sub(raw, endPos + 2) end
    response = C.Trim(response)
    if not string.find(response, "GRINFO:") then return end
    if not string.find(response, ":FULL") then return end
    if executeGrinfoReady then return end
    local _, prefEnd = string.find(string.lower(response), "^nexus%s+")
    if prefEnd then response = C.Trim(string.sub(response, prefEnd + 1)) end
    local space = string.find(response, " ")
    if not space then return end
    local payload = C.Trim(string.sub(response, space + 1))
    if payload == "" then
        executeCompanionList = {}
        executeGrinfoReady = true
        Chat("The server returned no companions.")
        return
    end
    executeCompanionList = C.ParseCompanionInfo(payload)
    executeGrinfoReady = true
    Chat("Received " .. table.getn(executeCompanionList) .. " companion record(s) from the server.")
end

local function IsHeldPhase(phase)
    return phase == "role-class-final" or phase == "class-setup" or phase == "legacy-setup"
end

local function ExpandPendingGroupDenies()
    if not executeQueue then return end
    local kept = {}
    local pending = {}
    local legacySetup = {}
    for i = 1, table.getn(executeQueue) do
        if i < executeIndex then
            table.insert(kept, executeQueue[i])
        elseif executeQueue[i].phase == "legacy-setup" then
            table.insert(legacySetup, executeQueue[i])
        elseif executeQueue[i].phase == "role-class-final" or executeQueue[i].phase == "class-setup" then
            table.insert(pending, executeQueue[i])
        else
            table.insert(kept, executeQueue[i])
        end
    end
    local present = SnapshotGroup()
    if type(UnitName) == "function" then
        local me = UnitName("player")
        if me then present[me] = nil end
    end
    local live = C.KeepPresentCompanions(executeCompanionList, present)
    local leftoverSet = C.LegacyNameSet(EnsureDB().entries)
    local denyPending = {}
    local setupPending = {}
    for i = 1, table.getn(pending) do
        if pending[i].phase == "class-setup" then table.insert(setupPending, pending[i]) else table.insert(denyPending, pending[i]) end
    end
    local leftoverCard = {}
    for i = 1, table.getn(legacySetup) do
        if present[legacySetup[i].target] then table.insert(leftoverCard, legacySetup[i]) end
    end
    local leftoverCustom = {}
    for i = 1, table.getn(executeQueue) do
        if i >= executeIndex and executeQueue[i].phase == "legacy-custom" then
            if present[executeQueue[i].target] then table.insert(leftoverCustom, executeQueue[i]) end
        end
    end
    local trimmed = {}
    for i = 1, table.getn(kept) do
        if kept[i].phase ~= "legacy-custom" then table.insert(trimmed, kept[i]) end
    end
    local expanded = C.AssembleLiveGroupCommands(setupPending, denyPending, leftoverCard, leftoverCustom, live, leftoverSet)
    for i = 1, table.getn(expanded) do table.insert(trimmed, expanded[i]) end
    executeQueue = trimmed
    local total = table.getn(expanded)
    if total == 0 then
        Chat("No current party or raid companions matched the saved group commands.")
    else
        Chat("Group commands will whisper companions first, then leftover overwrite last: " .. total .. " live command(s).")
    end
end

if not grinfoFrame then
    grinfoFrame = CreateFrame("Frame")
    grinfoFrame:RegisterEvent("CHAT_MSG_ADDON")
    grinfoFrame:SetScript("OnEvent", function()
        if event ~= "CHAT_MSG_ADDON" then return end
        HandleCompanionInfoMessage()
    end)
end

local function SendQueueEntry(entry)
    if not entry or not entry.command then return end
    if entry.chatType == "WHISPER" then
        if not entry.target or entry.target == "" then return end
        SendChatMessage(entry.command, "WHISPER", nil, entry.target)
        Chat("whisper " .. entry.target .. " -> " .. entry.command)
    else
        SendChatMessage(entry.command, "SAY")
        Chat("say -> " .. entry.command)
    end
end

local function StartRaidSort(verbose, onDone)
    local pump = C.sortFrame
    if pump and pump.busy then return "busy" end
    if type(GetNumRaidMembers) ~= "function" then return "no-raid" end
    local count = GetNumRaidMembers() or 0
    if count == 0 and type(ConvertToRaid) == "function" and type(GetNumPartyMembers) == "function" then
        if (GetNumPartyMembers() or 0) > 0 and type(IsPartyLeader) == "function" and IsPartyLeader() then
            ConvertToRaid()
            count = GetNumRaidMembers() or 0
        end
    end
    if count == 0 then return "no-raid" end
    local lead = type(IsRaidLeader) == "function" and IsRaidLeader()
    local assist = type(IsRaidOfficer) == "function" and IsRaidOfficer()
    if not lead and not assist then return "need-assist" end
    if type(GetRaidRosterInfo) ~= "function" or type(SetRaidSubgroup) ~= "function" then return "no-raid" end
    local function oneMove()
        local n = GetNumRaidMembers() or 0
        if n == 0 then return "no-raid" end
        local roster = {}
        local i
        for i = 1, n do
            local name, _, group, _, class = GetRaidRosterInfo(i)
            if name and group then table.insert(roster, {index = i, name = name, group = group, class = class}) end
        end
        local assignments = C.BuildLiveRaidAssignments(EnsureDB().entries, executeCompanions, roster, executeCompanionList, (UnitName and UnitName("player")) or "")
        if C.sortFrame and C.sortFrame.orderQueue then
            while C.sortFrame.orderIndex <= table.getn(C.sortFrame.orderQueue) do
                local action = C.sortFrame.orderQueue[C.sortFrame.orderIndex]
                local row = nil
                for i = 1, table.getn(roster) do
                    if string.lower(C.Trim(roster[i].name)) == string.lower(C.Trim(action.name)) then row = roster[i]; break end
                end
                if not row then
                    C.sortFrame.orderProcessed[C.sortFrame.orderGroup] = true
                    C.sortFrame.orderFailed[C.sortFrame.orderGroup] = true
                    C.sortFrame.orderQueue = nil
                    if verbose then Chat("Sort: could not find "..action.name.."; continuing to the next group.") end
                    return "order-next"
                end
                if row.group ~= action.group then
                    C.sortFrame.orderActionAttempts = (C.sortFrame.orderActionAttempts or 0) + 1
                    if C.sortFrame.orderActionAttempts > 3 then
                        C.sortFrame.orderProcessed[C.sortFrame.orderGroup] = true
                        C.sortFrame.orderFailed[C.sortFrame.orderGroup] = true
                        C.sortFrame.orderQueue = nil
                        if verbose then Chat("Sort: move did not land for group "..C.sortFrame.orderGroup.."; continuing.") end
                        return "order-next"
                    end
                    if verbose then Chat("Sort: "..action.phase.." "..action.name.." -> group "..action.group) end
                    SetRaidSubgroup(row.index, action.group)
                    return "ordered"
                end
                C.sortFrame.orderActionAttempts = 0
                C.sortFrame.orderIndex = C.sortFrame.orderIndex + 1
            end
            C.sortFrame.orderProcessed[C.sortFrame.orderGroup] = true
            if verbose then Chat("Sort: completed the slot-order pass for group "..C.sortFrame.orderGroup.."; continuing.") end
            C.sortFrame.orderQueue = nil
            C.sortFrame.orderIndex = nil
            C.sortFrame.orderGroup = nil
            C.sortFrame.orderBefore = nil
        end
        local moves = C.PlanRaidMoves(roster, assignments)
        if table.getn(moves) == 0 then
            local allOrderSwaps = C.PlanRaidOrderSwaps(roster, assignments)
            local orderSwaps = C.PlanRaidOrderSwaps(roster, assignments, C.sortFrame.orderProcessed)
            if table.getn(orderSwaps) == 0 then
                local hasFailure = false
                local failedGroup
                for failedGroup in pairs(C.sortFrame.orderFailed) do hasFailure = true; break end
                if hasFailure then
                    if verbose then Chat("Sort: checked every group; some exact slot passes were unavailable.") end
                    return "order-partial"
                end
                if verbose then
                    if table.getn(allOrderSwaps) == 0 then Chat("Sort: board groups and slot order matched.")
                    else Chat("Sort: every required group received one completed slot-order pass.") end
                end
                return "done"
            end
            C.sortFrame.orderPasses = (C.sortFrame.orderPasses or 0) + 1
            if C.sortFrame.orderPasses > 8 then return "order-partial" end
            local targetGroup = orderSwaps[1].group
            local orderQueue, reason = C.PlanRaidOrderRebuild(roster, assignments, C.sortFrame.orderProcessed)
            if reason or table.getn(orderQueue) == 0 then
                C.sortFrame.orderProcessed[targetGroup] = true
                C.sortFrame.orderFailed[targetGroup] = true
                if verbose then Chat("Sort: group "..targetGroup.." needs an empty temporary subgroup; continuing.") end
                return "order-next"
            end
            C.sortFrame.orderQueue = orderQueue
            C.sortFrame.orderIndex = 1
            C.sortFrame.orderActionAttempts = 1
            C.sortFrame.orderGroup = targetGroup
            C.sortFrame.orderBefore = C.RaidOrderSignature(roster)
            local action = orderQueue[1]
            local row = nil
            for i = 1, table.getn(roster) do
                if string.lower(C.Trim(roster[i].name)) == string.lower(C.Trim(action.name)) then row = roster[i]; break end
            end
            if not row then
                C.sortFrame.orderProcessed[targetGroup] = true
                C.sortFrame.orderFailed[targetGroup] = true
                C.sortFrame.orderQueue = nil
                return "order-next"
            end
            if verbose then Chat("Sort: rebuilding group "..targetGroup.." slot by slot through group "..action.group..".") end
            SetRaidSubgroup(row.index, action.group)
            return "ordered"
        end
        local m
        for m = 1, table.getn(moves) do
            local target = moves[m]
            local dest = target.group
            local idx = nil
            local destCount = 0
            for i = 1, table.getn(roster) do
                if roster[i].name == target.name then idx = roster[i].index end
                if roster[i].group == dest then destCount = destCount + 1 end
            end
            if idx then
                if destCount < 5 then
                    if verbose then Chat("Sort: "..target.name.." -> group "..dest) end
                    SetRaidSubgroup(idx, dest)
                    return "moved"
                elseif type(SwapRaidSubgroup) == "function" then
                    for i = 1, table.getn(roster) do
                        local other = roster[i]
                        if other.group == dest and other.name ~= target.name then
                            local otherWant = C.AssignmentForName(assignments, other.name)
                            if (not otherWant) or otherWant ~= dest then
                                if verbose then Chat("Sort: swap "..target.name.." <-> "..other.name) end
                                SwapRaidSubgroup(idx, other.index)
                                return "moved"
                            end
                        end
                    end
                end
            end
        end
        if verbose then
            Chat("Sort stuck. Still wrong:")
            for m = 1, table.getn(moves) do
                Chat("  "..moves[m].name.." wants group "..moves[m].group)
            end
        end
        return "stuck"
    end
    if not C.sortFrame then C.sortFrame = CreateFrame("Frame") end
    pump = C.sortFrame
    pump.busy = true
    pump.moved = 0
    pump.orderQueue = nil
    pump.orderIndex = nil
    pump.orderActionAttempts = 0
    pump.orderGroup = nil
    pump.orderProcessed = {}
    pump.orderFailed = {}
    pump.orderBefore = nil
    pump.orderPasses = 0
    pump.onDone = onDone
    C.sortWaiting = true
    if not executeGrinfoReady then
        executeGrinfoReady = false
        RequestCompanionInfo()
    end
    pump.waitInfoUntil = (GetTime and GetTime() or 0) + 8
    pump.readyAt = (GetTime and GetTime() or 0) + 0.5
    if verbose then Chat("Sort: one move every 0.5s so the client can keep up.") end
    pump:SetScript("OnUpdate", function()
        local now = GetTime and GetTime() or 0
        if C.sortWaiting and (not executeGrinfoReady) and now < (C.sortFrame.waitInfoUntil or 0) then
            SetStatus("Sort: waiting for companion names.")
            return
        end
        if C.sortWaiting then
            C.sortWaiting = nil
            if (not executeGrinfoReady) and verbose then Chat("Sort: no companion list; matching names we already know.") end
            C.sortFrame.readyAt = now + 0.5
            return
        end
        if now < (C.sortFrame.readyAt or 0) then return end
        local step = oneMove()
        if step == "moved" or step == "ordered" then
            C.sortFrame.moved = (C.sortFrame.moved or 0) + 1
            C.sortFrame.readyAt = now + 0.5
            if step == "ordered" then SetStatus("Sort: ordered slot, waiting 0.5s.")
            else SetStatus("Sort: moved "..C.sortFrame.moved..", waiting 0.5s.") end
            return
        end
        if step == "order-next" then
            C.sortFrame.readyAt = now + 0.5
            SetStatus("Sort: continuing to the next group.")
            return
        end
        C.sortFrame:SetScript("OnUpdate", nil)
        C.sortFrame.busy = nil
        local cb = C.sortFrame.onDone
        C.sortFrame.onDone = nil
        local result = step
        if step == "done" then result = C.sortFrame.moved or 0 end
        if cb then cb(result) end
    end)
    return "started"
end

local function FinishExecute(status)
    executing = false
    executeQueue = nil
    executeIndex = 0
    executeElapsed = 0
    executePartyBefore = nil
    executeCompanions = {}
    executeBaseline = {}
    executeCompanionList = {}
    executeGrinfoRequested = false
    executeGrinfoReady = false
    executeGrinfoExpanded = false
    executeWaitElapsed = 0
    executeWaitStarted = 0
    executeFrames = 0
    executeHireReadyAt = 0
    executeWaitingNod = false
    executeNodReady = false
    executeNodName = ""
    executeNodStarted = 0
    executeWhisperGap = 0
    if executeFrame then executeFrame:SetScript("OnUpdate", nil) end
    if C.sortFrame then C.sortFrame:SetScript("OnUpdate", nil); C.sortFrame.busy = nil; C.sortFrame.onDone = nil end
    C.sortWaiting = nil
    C.whisperRun = nil
    SetStatus(status)
end

local function StopQueue()
    FinishExecute("Execution stopped.")
end

local function NoteCommandSent(entry)
    if C.IsWhisperCommand(entry) then
        executeWaitingNod = true
        executeNodReady = false
        executeNodName = entry.target
        executeNodStarted = 0
        executeWhisperGap = 0
    else
        executeWaitingNod = false
        executeNodReady = false
        executeNodName = ""
        executeNodStarted = 0
        executeWhisperGap = 0
        if C.IsHireCommand(entry) then executeHireReadyAt = (GetTime and GetTime() or 0) + RandomHireDelay() end
    end
end

local function ReadyForNext(nextEntry)
    AssignNewCompanions()
    if executeWaitingNod and not executeNodReady then
        if (executeNodStarted or 0) == 0 then executeNodStarted = GetTime and GetTime() or 0 end
    end
    local nodElapsed = 0
    if executeWaitingNod and not executeNodReady and GetTime then
        nodElapsed = GetTime() - (executeNodStarted or 0)
    end
    if executeWaitingNod then
        if executeNodReady or nodElapsed >= NOD_TIMEOUT_SECONDS then
            if (not executeNodReady) and nodElapsed >= NOD_TIMEOUT_SECONDS and executeWhisperGap == 0 then
                if executeNodName ~= "" then Chat("No nod from " .. executeNodName .. "; continuing.") end
            end
            local gapStarted = executeWhisperGap == 0
            if gapStarted and GetTime then executeWhisperGap = GetTime() end
            if not GetTime or (GetTime() - executeWhisperGap) < WHISPER_GAP_SECONDS then
                SetStatus("Pacing whispers.")
                return false
            end
            executeWaitingNod = false
            executeNodReady = false
            return true
        end
        SetStatus("Waiting for nod from " .. (executeNodName ~= "" and executeNodName or "companion") .. ".")
        return false
    end
    if (executeHireReadyAt or 0) > 0 then
        local now = GetTime and GetTime() or 0
        if now < executeHireReadyAt then
            SetStatus("Pacing hires.")
            return false
        end
    end
    return true
end

local function HandleCommandAck()
    if not executing or not executeWaitingNod or executeNodReady then return end
    if event == "CHAT_MSG_TEXT_EMOTE" or event == "CHAT_MSG_EMOTE" then
        if C.IsNodAck(arg2, arg1, executeNodName) then executeNodReady = true end
    elseif event == "CHAT_MSG_WHISPER" then
        if C.IsBlacklistAck(arg2, arg1, executeNodName) then executeNodReady = true end
    end
end

if not nodFrame then
    nodFrame = CreateFrame("Frame")
    nodFrame:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
    nodFrame:RegisterEvent("CHAT_MSG_EMOTE")
    nodFrame:RegisterEvent("CHAT_MSG_WHISPER")
    nodFrame:SetScript("OnEvent", function()
        HandleCommandAck()
    end)
end

local function SendCurrentQueueEntry()
    local entry = executeQueue and executeQueue[executeIndex]
    if not entry then return false end
    if not ResolveRoleDenyTarget(entry) then return false end
    if entry.kind == "normal" then executePartyBefore = SnapshotGroup() end
    SendQueueEntry(entry)
    NoteCommandSent(entry)
    return true
end

local function ExecuteQueue()
    if executing then SetStatus("Queue is already running."); return end
    if C.whisperRun then executeQueue = C.BuildWhisperQueue(EnsureDB()) else executeQueue = C.BuildQueue(EnsureDB()) end
    if table.getn(executeQueue) == 0 then SetStatus("Queue is empty."); C.whisperRun = nil; return end
    executing = true; executeIndex = 1; executeElapsed = 0; executeFrames = 0; executeHireReadyAt = 0; executeWaitingNod = false; executeNodReady = false; executeNodName = ""; executeNodStarted = 0; executeWhisperGap = 0; executeWaitElapsed = 0; executeWaitStarted = 0; executePartyBefore = nil; executeCompanions = {}; executeBaseline = SnapshotGroup(); executeCompanionList = {}; executeGrinfoRequested = false; executeGrinfoReady = false; executeGrinfoExpanded = false
    if math.randomseed then math.randomseed((GetTime and GetTime() or 0) * 1000) end
    SendCurrentQueueEntry()
    if C.whisperRun then SetStatus("Whispering 1/" .. table.getn(executeQueue) .. ".")
    else SetStatus("Executing 1/" .. table.getn(executeQueue) .. ". Pacing hires at 7.5-8.5s.") end
    if not executeFrame then executeFrame = CreateFrame("Frame") end
    executeFrame:SetScript("OnUpdate", function()
        if not executing then return end
        local nextIndex = executeIndex + 1
        local nextEntry = executeQueue[nextIndex]
        if nextEntry and IsHeldPhase(nextEntry.phase) then
            if not executeGrinfoReady then
                if not executeGrinfoRequested then
                    executeGrinfoRequested = true
                    executeWaitStarted = GetTime and GetTime() or 0
                    RequestCompanionInfo()
                end
                local waited = 0
                if GetTime then waited = GetTime() - (executeWaitStarted or 0) end
                if waited < 8 then
                    SetStatus("Waiting for companion role/class names from the server.")
                    return
                end
                Chat("No companion list from the server; group denies were skipped.")
                executeIndex = nextIndex
                while executeIndex <= table.getn(executeQueue) and IsHeldPhase(executeQueue[executeIndex].phase) do
                    executeIndex = executeIndex + 1
                end
                executeWaitingNod = false
                if executeIndex > table.getn(executeQueue) then
                    FinishExecute("Execution complete. Group denies were skipped."); return
                end
                SendCurrentQueueEntry()
                SetStatus("Executing " .. executeIndex .. "/" .. table.getn(executeQueue) .. ".")
                return
            end
            if not executeGrinfoExpanded then
                if not ReadyForNext(nextEntry) then return end
                executeIndex = nextIndex
                ExpandPendingGroupDenies()
                executeGrinfoExpanded = true
                executeWaitingNod = false
                if executeIndex > table.getn(executeQueue) then
                    FinishExecute("Execution complete. All queued commands were sent."); return
                end
                SendCurrentQueueEntry()
                SetStatus("Executing " .. executeIndex .. "/" .. table.getn(executeQueue) .. ".")
                return
            end
        end
        if not ReadyForNext(nextEntry) then return end
        executeWaitingNod = false
        executeNodReady = false
        executeIndex = nextIndex
        if executeIndex > table.getn(executeQueue) then
            FinishExecute("Execution complete. All queued commands were sent."); return
        end
        SendCurrentQueueEntry()
        SetStatus("Executing " .. executeIndex .. "/" .. table.getn(executeQueue) .. ".")
    end)
end

local escapeFrame = nil

local function AddonWindowStillOpen()
    if choiceMenu and choiceMenu:IsShown() then return true end
    if abilityMenu and abilityMenu:IsShown() then return true end
    if legacyNameMenu and legacyNameMenu:IsShown() then return true end
    if contextFrame and contextFrame:IsShown() then return true end
    if namePrompt and namePrompt:IsShown() then return true end
    if C.capturePrompt and C.capturePrompt:IsShown() then return true end
    if denyFrame and denyFrame:IsShown() then return true end
    if addNormalFrame and addNormalFrame:IsShown() then return true end
    if addLegacyFrame and addLegacyFrame:IsShown() then return true end
    if settingsFrame and settingsFrame:IsShown() then return true end
    if setupFrame and setupFrame:IsShown() then return true end
    if mainFrame and mainFrame:IsShown() then return true end
    return false
end

local function HideTopOverlay()
    if choiceMenu and choiceMenu:IsShown() then CloseChoiceMenu(); return true end
    if abilityMenu and abilityMenu:IsShown() then abilityMenu:Hide(); return true end
    if legacyNameMenu and legacyNameMenu:IsShown() then HideLegacyNameSuggestions(); return true end
    if contextFrame and contextFrame:IsShown() then CloseContext(); return true end
    if namePrompt and namePrompt:IsShown() then namePrompt:Hide(); return true end
    if C.capturePrompt and C.capturePrompt:IsShown() then C.capturePrompt:Hide(); return true end
    if denyFrame and denyFrame:IsShown() then denyFrame:Hide(); return true end
    if addNormalFrame and addNormalFrame:IsShown() then addNormalFrame:Hide(); return true end
    if addLegacyFrame and addLegacyFrame:IsShown() then HideLegacyNameSuggestions(); addLegacyFrame:Hide(); return true end
    if settingsFrame and settingsFrame:IsShown() then settingsFrame:Hide(); return true end
    if setupFrame and setupFrame:IsShown() then CloseChoiceMenu(); setupFrame:Hide(); return true end
    if mainFrame and mainFrame:IsShown() then mainFrame:Hide(); return true end
    return false
end

local function EnsureEscapeWatcher()
    if escapeFrame then return end
    escapeFrame = CreateFrame("Frame", "ShirsRaidBuilderEscaper", UIParent)
    escapeFrame:Hide()
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "ShirsRaidBuilderEscaper") end
    escapeFrame:SetScript("OnHide", function()
        HideTopOverlay()
        if AddonWindowStillOpen() then escapeFrame:Show() end
    end)
end

function C.SetTip(btn, title, body)
    if btn then btn.tipTitle = title; btn.tip = body end
    return btn
end

function C.ApplyRaidMode()
    if not mainFrame then return end
    local sort = DB.uiMode == "sort"
    local function showBtn(btn, on)
        if not btn then return end
        if on then
            if btn.homeX then
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", btn.homeX, btn.homeY)
            end
            if btn.SetFrameLevel then btn:SetFrameLevel(80) end
            if btn.EnableMouse then btn:EnableMouse(true) end
            btn:Show()
        else
            if btn.EnableMouse then btn:EnableMouse(false) end
            btn:Hide()
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", -4000, 4000)
            if btn.SetFrameLevel then btn:SetFrameLevel(1) end
        end
    end
    showBtn(mainFrame.addNormalBtn, not sort)
    showBtn(mainFrame.addLegacyBtn, not sort)
    showBtn(mainFrame.captureBtn, sort)
    showBtn(mainFrame.saveBtn, sort)
    showBtn(mainFrame.executeBtn, not sort)
    showBtn(mainFrame.sortBtn, sort)
    showBtn(mainFrame.whisperBtn, sort)
    if mainFrame.modeBtn and mainFrame.modeBtn.label then
        if sort then mainFrame.modeBtn.label:SetText("Hire Mode") else mainFrame.modeBtn.label:SetText("Sort Mode") end
    end
    if mainFrame.titleText then
        if sort then mainFrame.titleText:SetText("Shir's Raid Builder 0.62 - Sort")
        else mainFrame.titleText:SetText("Shir's Raid Builder 0.62") end
    end
    if mainFrame.accountContent then
        if sort then mainFrame.accountContent:Hide() else mainFrame.accountContent:Show() end
    end
    if mainFrame.countText then
        if sort then mainFrame.countText:Hide() else mainFrame.countText:Show() end
    end
    if sort then SetStatus("Sort mode: Capture the raid, Sort groups, then Whispers. No hiring.") end
end

function C.ToggleRaidMode()
    EnsureDB()
    if DB.uiMode == "sort" then DB.uiMode = "hire" else DB.uiMode = "sort" end
    C.ApplyRaidMode()
    RefreshPresetButton()
    RefreshComposition()
end

function C.RequestCaptureLayout()
    EnsureDB()
    if DB.uiMode ~= "sort" then SetStatus("Capture is only for sort mode."); return end
    if type(GetNumRaidMembers) ~= "function" or (GetNumRaidMembers() or 0) == 0 then SetStatus("Capture needs a raid."); return end
    if C.sortFrame and C.sortFrame.busy then SetStatus("Wait for the current sort to finish."); return end
    local character = ""
    local realm = ""
    if type(UnitName) == "function" then character = UnitName("player") or "" end
    if type(GetRealmName) == "function" then realm = GetRealmName() or "" end
    if not C.ShouldShowCaptureWarning(DB, character, realm) then C.StartCaptureLayout(); return end
    if not C.capturePrompt then
        local frame = CreateFrame("Frame", "ShirsRaidBuilderCaptureWarning", UIParent)
        C.capturePrompt = frame
        frame:SetWidth(430); frame:SetHeight(180); StylePanelFrame(frame); frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        RegisterEscapeFrame(frame)
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.title:SetPoint("TOP", frame, "TOP", 0, -14)
        frame.title:SetText("Overwrite sort profile?")
        frame.message = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.message:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, -42)
        frame.message:SetWidth(374); frame.message:SetJustifyH("LEFT")
        frame.checkbox = CreateFrame("CheckButton", "ShirsRaidBuilderCaptureWarningCheck", frame, "UICheckButtonTemplate")
        frame.checkbox:SetWidth(20); frame.checkbox:SetHeight(20)
        frame.checkbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -103)
        frame.checkboxLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.checkboxLabel:SetPoint("LEFT", frame.checkbox, "RIGHT", 4, 0)
        frame.checkboxLabel:SetText("Don't show this warning again for this character")
        MakeButton(frame, "Overwrite", 100, 90, 16, function()
            local prompt = C.capturePrompt
            if prompt.checkbox:GetChecked() then C.SetCaptureWarningHidden(DB, prompt.character, prompt.realm, true) end
            prompt:Hide()
            C.StartCaptureLayout()
        end, true)
        MakeButton(frame, "Cancel", 100, 240, 16, function() C.capturePrompt:Hide() end, true)
    end
    local _, profile = C.PresetBank(DB, "sort")
    C.capturePrompt.character = character
    C.capturePrompt.realm = realm
    C.capturePrompt.checkbox:SetChecked(nil)
    C.capturePrompt.message:SetText("This will overwrite the current sort profile \"" .. (profile or "Default") .. "\" with the current raid.\n\nThe existing layout in this profile will be replaced.")
    C.capturePrompt:Show()
end

function C.StartCaptureLayout()
    if DB.uiMode ~= "sort" then SetStatus("Capture is only for sort mode."); return end
    if type(GetNumRaidMembers) ~= "function" or (GetNumRaidMembers() or 0) == 0 then SetStatus("Capture needs a raid."); return end
    if C.sortFrame and C.sortFrame.busy then SetStatus("Wait for the current sort to finish."); return end
    C.sortWaiting = true
    executeGrinfoReady = false
    RequestCompanionInfo()
    if not C.sortFrame then C.sortFrame = CreateFrame("Frame") end
    C.sortFrame.busy = true
    C.sortFrame.waitInfoUntil = (GetTime and GetTime() or 0) + 8
    C.sortFrame:SetScript("OnUpdate", function()
        local now = GetTime and GetTime() or 0
        if (not executeGrinfoReady) and now < (C.sortFrame.waitInfoUntil or 0) then
            SetStatus("Capture: waiting for companion names.")
            return
        end
        C.sortFrame:SetScript("OnUpdate", nil)
        C.sortFrame.busy = nil
        C.sortWaiting = nil
        local roster = {}
        local n = GetNumRaidMembers() or 0
        local i
        for i = 1, n do
            local name, _, group, _, class = GetRaidRosterInfo(i)
            if name and group then table.insert(roster, {name=name, group=group, class=class}) end
        end
        local you = ""
        if type(UnitName) == "function" then you = UnitName("player") or "" end
        local preset = EnsureDB()
        preset.entries = C.CaptureRaidLayout(roster, executeCompanionList, you)
        preset.sortLayout = true
        RefreshComposition()
        SetStatus("Saved the live raid into this profile.")
    end)
end

function C.StartWhispers()
    C.whisperRun = true
    ExecuteQueue()
end

local function CreateMain()
    EnsureDB()
    mainFrame=CreateFrame("Frame","ShirsRaidBuilderMainFrame",UIParent); mainFrame:SetWidth(780); mainFrame:SetHeight(640); mainFrame:SetPoint("CENTER",UIParent,"CENTER",0,0); mainFrame:SetFrameStrata("FULLSCREEN"); mainFrame:SetToplevel(true); mainFrame:SetMovable(true); mainFrame:EnableMouse(true)
    mainFrame:SetBackdrop(PANEL_BG); mainFrame:SetBackdropColor(0.03, 0.04, 0.07, 1.0); mainFrame:SetBackdropBorderColor(0.70, 0.70, 0.70, 1.0)
    local title=mainFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight"); title:SetPoint("TOP",mainFrame,"TOP",0,-12); title:SetText("Shir's Raid Builder 0.62")
    mainFrame.titleText = title
    MakeButton(mainFrame,"X",22,736,-8,function() mainFrame:Hide() end)
    local drag=CreateFrame("Frame",nil,mainFrame); drag:SetWidth(500); drag:SetHeight(24); drag:SetPoint("TOP",mainFrame,"TOP",0,-4); drag:EnableMouse(true); drag:SetScript("OnMouseDown",function() mainFrame:StartMoving() end); drag:SetScript("OnMouseUp",function() mainFrame:StopMovingOrSizing() end)
    MakeCaption(mainFrame, "Profile", 22, -32)
    presetButton=SelectButton(mainFrame,GetPresetNames(),DB.currentPreset,140,22,-48,function(v) SwitchPreset(v) end)
    C.SetTip(presetButton,"Profile","Hire mode and sort mode each have their own saved profiles.")
    C.SetTip(MakeButton(mainFrame,"New",88,168,-48,NewPreset),"New","Create an empty profile in the current mode.")
    C.SetTip(MakeButton(mainFrame,"Rename",88,260,-48,RenamePreset),"Rename","Rename the open profile. Does not copy it.")
    C.SetTip(MakeButton(mainFrame,"Delete",88,352,-48,DeletePreset),"Delete","Delete the open profile. Needs at least one left.")
    mainFrame.addNormalBtn=C.SetTip(MakeButton(mainFrame,"Add Normal",88,444,-48,function() AddEntryEditor("normal") end),"Add Normal","Hire a companion from a licensed character. Pick the character that does the hiring, not the companion name.")
    mainFrame.addNormalBtn.homeX=444; mainFrame.addNormalBtn.homeY=-48
    mainFrame.addLegacyBtn=C.SetTip(MakeButton(mainFrame,"Add Legacy",88,536,-48,function() AddEntryEditor("legacy") end),"Add Legacy","Add a legacy character by its real name. The card shows the -lite name. This is not a hire-from account.")
    mainFrame.addLegacyBtn.homeX=536; mainFrame.addLegacyBtn.homeY=-48
    mainFrame.captureBtn=C.SetTip(MakeButton(mainFrame,"Capture",88,444,-48,C.RequestCaptureLayout),"Capture","Overwrites this sort layout with the current raid after confirmation. Stores who hired each companion (account + class + role), not the random companion name.")
    mainFrame.captureBtn.homeX=444; mainFrame.captureBtn.homeY=-48
    mainFrame.saveBtn=C.SetTip(MakeButton(mainFrame,"Save",88,536,-48,C.SaveSortLayout),"Save","Save this sort layout in the addon under a name. Does not move anyone in the raid.")
    mainFrame.saveBtn.homeX=536; mainFrame.saveBtn.homeY=-48
    mainFrame.modeBtn=C.SetTip(MakeButton(mainFrame,"Sort Mode",88,628,-48,C.ToggleRaidMode),"Mode","Switch between hiring and raid sorting. Sort mode cannot hire.")
    C.SetTip(MakeButton(mainFrame,"Deny Rules",118,22,-76,OpenSettings),"Deny Rules","Class and role denies sent after everyone is in the group.")
    C.SetTip(MakeButton(mainFrame,"Other Commands",118,144,-76,OpenSetup),"Other Commands","Class setup whispers. Legacy overwrite still happens last.")
    C.SetTip(MakeButton(mainFrame,"Preview",118,266,-76,function()
        local q
        if DB.uiMode == "sort" then q=C.BuildWhisperQueue(EnsureDB()) else q=C.BuildQueue(EnsureDB()) end
        Chat("Preview "..table.getn(q).." queue entries.")
        for i=1,table.getn(q) do
            if q[i].phase=="role-class-final" then
                Chat(i..": group "..(ROLE_LABELS[q[i].role] or q[i].role or "?").." / "..(CLASS_LABELS[q[i].class] or q[i].class or "?").." -> "..(q[i].command or ""))
            elseif q[i].phase=="class-setup" then
                Chat(i..": setup "..(q[i].role or "all").." / "..(CLASS_LABELS[q[i].class] or q[i].class or "?").." -> "..(q[i].command or ""))
            elseif q[i].phase=="legacy-setup" then
                Chat(i..": overwrite "..(q[i].target or "?").." -> "..(q[i].command or ""))
            elseif q[i].chatType=="WHISPER" then
                Chat(i..": whisper "..(q[i].target or "?").." -> "..q[i].command)
            else
                Chat(i..": "..q[i].command)
            end
        end
    end), "Preview", "Print the queue only. Hire mode shows hires plus whispers. Sort mode shows whispers only.")
    mainFrame.executeBtn=C.SetTip(MakeButton(mainFrame,"Execute",118,388,-76,function() C.whisperRun = nil; ExecuteQueue() end),"Execute","Hire the board, then class setup, then legacy overwrite. Slow on purpose.")
    mainFrame.executeBtn.homeX=388; mainFrame.executeBtn.homeY=-76
    C.SetTip(MakeButton(mainFrame,"Stop",118,510,-76,StopQueue),"Stop","Cancel hire, sort, or whispers.")
    mainFrame.sortBtn=C.SetTip(MakeButton(mainFrame,"Sort",118,632,-76,function()
        Chat("Sort: board-to-raid pass.")
        local function report(arranged)
            if arranged == "need-assist" then SetStatus("Sort needs raid lead or assist.")
            elseif arranged == "no-raid" then SetStatus("Sort: not in a raid.")
            elseif arranged == "order-partial" then SetStatus("Groups match. Every group was checked; some exact slot passes were unavailable.")
            elseif arranged == "order-stuck" then SetStatus("Groups match, but this client did not change the within-group slot order.")
            elseif arranged == "stuck" then SetStatus("Sort stuck. Check chat for leftover names.")
            elseif type(arranged) == "number" and arranged > 0 then SetStatus("Sort moved "..arranged.." raid slot(s).")
            elseif type(arranged) == "number" then SetStatus("Sort: raid already matches the board.")
            else SetStatus("Sort finished.") end
        end
        local started = StartRaidSort(true, report)
        if started == "busy" then SetStatus("Sort already running.")
        elseif started ~= "started" then report(started) end
    end),"Sort","Move people in the Blizzard raid to match this layout. Matches by hiring account + class + role, and by legacy names. One move every 0.5s.")
    mainFrame.sortBtn.homeX=632; mainFrame.sortBtn.homeY=-76
    mainFrame.whisperBtn=C.SetTip(MakeButton(mainFrame,"Whispers",118,388,-76,C.StartWhispers),"Whispers","Send deny and other commands only. Does not hire.")
    mainFrame.whisperBtn.homeX=388; mainFrame.whisperBtn.homeY=-76
    mainFrame.countText=mainFrame:CreateFontString(nil,"OVERLAY","GameFontNormal"); mainFrame.countText:SetPoint("TOPRIGHT",mainFrame,"TOPRIGHT",-24,-78); mainFrame.countText:SetTextColor(1,0.85,0.25)
    mainFrame.accountContent=CreateFrame("Frame",nil,mainFrame); mainFrame.accountContent:SetWidth(170); mainFrame.accountContent:SetHeight(490); mainFrame.accountContent:SetPoint("TOPLEFT",mainFrame,"TOPLEFT",22,-108); mainFrame.accountRows={}
    compositionContent=CreateFrame("Frame",nil,mainFrame); compositionContent:SetWidth(550); compositionContent:SetHeight(490); compositionContent:SetPoint("TOPLEFT",mainFrame,"TOPLEFT",204,-108)
    statusText=mainFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); statusText:SetPoint("BOTTOMLEFT",mainFrame,"BOTTOMLEFT",22,16); statusText:SetWidth(430); statusText:SetJustifyH("LEFT"); statusText:SetTextColor(0.75,0.90,0.70)
    mainFrame.roleText=mainFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); mainFrame.roleText:SetPoint("BOTTOMRIGHT",mainFrame,"BOTTOMRIGHT",-24,16); mainFrame.roleText:SetWidth(300); mainFrame.roleText:SetJustifyH("RIGHT"); mainFrame.roleText:SetTextColor(0.85,0.88,0.70)
    mainFrame.roleText:SetText("Tank 0   Healer 0   Melee 0   Range 0")
    RefreshPresetButton(); RefreshComposition(); C.ApplyRaidMode(); EnsureEscapeWatcher(); mainFrame:SetScript("OnShow", function() if escapeFrame then escapeFrame:Show() end; C.ApplyRaidMode() end); mainFrame:SetScript("OnHide", HideFloatingPanels); mainFrame:Hide()
end

local function ShowDemo()
    EnsureDB(); local p=DB.presets[DB.currentPreset]
    if table.getn(p.entries)==0 then
        table.insert(p.entries,{kind="legacy",charName="Longname",role="mdps",class="shaman",denyList={"Windfury Totem"}})
        table.insert(p.entries,{kind="normal",account="Shir",tier="t4r",class="warrior",role="tank",spec="default",race="human",gender="male"})
        table.insert(p.entries,{kind="normal",account="Longname",tier="t2r",class="shaman",role="healer",spec="default",race="orc",gender="female"})
        table.insert(p.entries,{kind="normal",account="Mageowner",tier="t2r",class="mage",role="rdps",spec="frost",race="human",gender="male"})
        table.insert(p.entries,{kind="normal",account="Palowner",tier="t2r",class="paladin",role="healer",spec="might",race="dwarf",gender="female"})
        table.insert(p.denyRules,{role="mdps",class="shaman",abilities={"Lightning Bolt","Chain Lightning"}})
    end
    if not mainFrame then CreateMain() end; RefreshComposition(); mainFrame:Show(); SetStatus("Demo loaded. Use Deny rules for MDPS/Shaman, or right-click any row for character-specific denies.")
end

SLASH_SHIRSRAIDBUILDER1="/srb"
SlashCmdList["SHIRSRAIDBUILDER"]=function(message)
    local command=C.Trim(string.lower(message or ""))
    if command=="demo" then ShowDemo() elseif not mainFrame then CreateMain(); EnsureInviteListener(); RequestInviteList(); mainFrame:Show() elseif mainFrame:IsShown() then mainFrame:Hide() else RefreshComposition(); EnsureInviteListener(); RequestInviteList(); mainFrame:Show() end
end

local init=CreateFrame("Frame"); init:RegisterEvent("ADDON_LOADED"); init:RegisterEvent("VARIABLES_LOADED"); init:RegisterEvent("PLAYER_ENTERING_WORLD"); init:SetScript("OnEvent",function()
    if event == "ADDON_LOADED" and arg1 and arg1 ~= "ShirsRaidBuilder" then return end
    if event == "PLAYER_ENTERING_WORLD" then RememberPlayer(); if mainFrame then RefreshAccountPanel(); RefreshComposition() end; return end
    BindAccountDB(); EnsureDB()
    if event == "VARIABLES_LOADED" then RememberPlayer(); HarvestKnownFactions(); EnsureInviteListener(); DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffShir's Raid Builder:|r v0.61 loaded. Type /srb demo.") end
end)
