-- Shir's Raid Builder
-- Independent clean-room implementation.

local C = ShirsRaidBuilderCore
C.VERSION = type(GetAddOnMetadata) == "function" and GetAddOnMetadata("ShirsRaidBuilder", "Version") or "?"
local DB = {}

local function BindAccountDB()
    -- The SavedVariable global must exist for the client to save anything.
    -- A missing table used to return early, so every edit landed in the
    -- file-local DB and logout wrote "ShirsRaidBuilderDB = nil".
    if type(ShirsRaidBuilderDB) ~= "table" then ShirsRaidBuilderDB = {} end
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
        if type(pending.legacyCharacters) == "table" then
            for name, class in pairs(pending.legacyCharacters) do
                if not C.LegacyCharacterClass(DB, name) then C.RememberLegacyCharacter(DB, name, class) end
            end
        end
        if type(pending.legacyCharacterRoles) == "table" then
            if type(DB.legacyCharacterRoles) ~= "table" then DB.legacyCharacterRoles = {} end
            for name, role in pairs(pending.legacyCharacterRoles) do
                if type(name) == "string" and DB.legacyCharacterRoles[name] == nil and C.LegacyCharacterRole(pending, name, C.LegacyCharacterClass(DB, name)) == role then
                    DB.legacyCharacterRoles[name] = role
                end
            end
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
local ROLE_SHORT = { tank="Tank", healer="Heal", mdps="MDPS", rdps="RDPS" }
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
local denyWorking = {}
local denyIndex = nil
local settingsAbilityInput = nil
local abilityMenu = nil
local abilitySuggestionRows = {}
local settingsRoleButton = nil
local settingsClassButton = nil
local setupFrame = nil
local legacyNameMenu = nil
local executing = false
local executeFrame = nil
local nodFrame = nil
local executeQueue = nil
local executeIndex = 0
local executeFrames = 0
local executeWaitStarted = 0
local HIRE_DELAY_MIN = 7.5
local HIRE_DELAY_MAX = 8.5
-- A hire may follow a hire once the last hired companion has joined the group (the server
-- has finished that hire) and this many seconds more. With no join, and before any other
-- command or the end of a queue, the 7.5-8.5 s settle time still applies.
C.HIRE_JOIN_MARGIN = 1.0
-- A legacy companion can take longer to arrive than the settle time. Its deny list waits for
-- it to be in the group, at most this many seconds, then goes anyway.
C.LEGACY_JOIN_WAIT = 20
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

-- Deny-rule targeting always resolves from the editor dropdowns at click
-- time, so changing Role or Class can never leave the next Add writing
-- into a rule the user can no longer see selected.
-- Matching and lookup live in Core (ShirsRaidBuilder_Core.lua).

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
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame.dragBar = CreateFrame("Frame", nil, frame)
    frame.dragBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -4)
    frame.dragBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -4)
    frame.dragBar:SetHeight(24)
    frame.dragBar:EnableMouse(true)
    frame.dragBar:RegisterForDrag("LeftButton")
    frame.dragBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame.dragBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
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

-- One five-row viewport plus a thumb that only appears at five or more items.
-- Hung on C. so this file stays under Lua 5.0's 200-local cap.
function C.CreateScrollTrack(host, viewport)
    local track = CreateFrame("Button", nil, host)
    track:SetWidth(12)
    track:SetHeight(viewport:GetHeight())
    track:SetPoint("TOPLEFT", viewport, "TOPRIGHT", 4, 0)
    track:SetBackdrop(DROP_BG)
    track:SetBackdropColor(0.04, 0.06, 0.10, 1.0)
    track:SetBackdropBorderColor(0.35, 0.45, 0.60, 1.0)
    track:EnableMouseWheel(true)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(10)
    thumb:SetHeight(16)
    thumb:SetPoint("TOPLEFT", track, "TOPLEFT", 1, 0)
    thumb:SetBackdrop(DROP_BG)
    thumb:SetBackdropColor(0.45, 0.58, 0.78, 1.0)
    thumb:SetBackdropBorderColor(0.80, 0.88, 1.0, 1.0)
    thumb:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    track.thumb=thumb
    return track,thumb
end

function C.EnsureDenyListScroll(host, spec)
    if host.listScroll then return host.listScroll end
    local viewport = CreateFrame("Frame", nil, host)
    viewport:SetWidth(spec.width)
    viewport:SetHeight(spec.rowHeight * C.DENY_LIST_VISIBLE_ROWS)
    viewport:SetPoint("TOPLEFT", host, "TOPLEFT", spec.x, spec.y)
    viewport:EnableMouse(true)
    viewport:EnableMouseWheel(true)
    local track,thumb=C.CreateScrollTrack(host,viewport)
    local state = { offset = 0, items = {}, rows = {}, viewport = viewport, track = track, thumb = thumb, dragging = false }
    local function Paint()
        local items = state.items or {}
        local count = table.getn(items)
        state.offset = C.ClampDenyListOffset(state.offset, count)
        if C.DenyListNeedsScrollbar(count) and (not spec.minScrollCount or count >= spec.minScrollCount) then
            local height, y = C.DenyListThumb(state.offset, count, track:GetHeight())
            thumb:SetHeight(height)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPLEFT", track, "TOPLEFT", 1, y)
            track:Show()
            thumb:Show()
        else
            track:Hide()
            thumb:Hide()
        end
        local i
        for i = 1, C.DENY_LIST_VISIBLE_ROWS do
            local row = state.rows[i]
            local index = state.offset + i
            local item = items[index]
            if item ~= nil then
                row:Show()
                spec.bindRow(row, item, index)
            else
                row:Hide()
            end
        end
    end
    state.Paint = Paint
    local function OnWheel()
        local count = table.getn(state.items or {})
        if not C.DenyListNeedsScrollbar(count) then return end
        state.offset = C.ClampDenyListOffset(state.offset - (arg1 or 0), count)
        Paint()
    end
    viewport:SetScript("OnMouseWheel", OnWheel)
    track:SetScript("OnMouseWheel", OnWheel)
    host:EnableMouseWheel(true)
    host:SetScript("OnMouseWheel", OnWheel)
    track:SetScript("OnClick", function()
        local count = table.getn(state.items or {})
        if not C.DenyListNeedsScrollbar(count) then return end
        local _, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        if scale == 0 then scale = 1 end
        local page = C.DENY_LIST_VISIBLE_ROWS
        if (cursorY / scale) > (thumb:GetTop() or 0) then
            state.offset = C.ClampDenyListOffset(state.offset - page, count)
        else
            state.offset = C.ClampDenyListOffset(state.offset + page, count)
        end
        Paint()
    end)
    local function StopDrag() state.dragging = false end
    thumb:SetScript("OnMouseDown", function() state.dragging = true end)
    thumb:SetScript("OnMouseUp", StopDrag)
    viewport:SetScript("OnMouseUp", StopDrag)
    host:SetScript("OnMouseUp", StopDrag)
    thumb:SetScript("OnUpdate", function()
        if not state.dragging then return end
        local count = table.getn(state.items or {})
        if not C.DenyListNeedsScrollbar(count) then state.dragging = false; return end
        local _, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        if scale == 0 then scale = 1 end
        local y = (cursorY / scale) - (track:GetTop() or 0)
        if y > 0 then y = 0 end
        state.offset = C.DenyListOffsetFromThumb(y, count, track:GetHeight())
        Paint()
    end)
    local i
    for i = 1, C.DENY_LIST_VISIBLE_ROWS do
        local row = spec.createRow(viewport)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, -((i - 1) * spec.rowHeight))
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", OnWheel)
        table.insert(state.rows, row)
    end
    host.listScroll = state
    return state
end

local choiceMenu = nil
local choiceButtons = {}
local choiceOwner = nil

local function CloseChoiceMenu()
    if choiceMenu then choiceMenu:Hide() end
    if C.characterChoices then C.characterChoices:Hide() end
    choiceOwner = nil
end
C.CloseChoiceMenu = CloseChoiceMenu

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
        if button.scrollCharacters then C.OpenCharacterChoices(button,onChange); return end
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

function C.OpenCharacterChoices(button,onChange)
    CloseChoiceMenu()
    if not C.characterChoices then
        C.characterChoices=CreateFrame("Frame","ShirsRaidBuilderCharacterChoices",UIParent)
        RegisterEscapeFrame(C.characterChoices)
    end
    local menu=C.characterChoices
    local count=table.getn(button.options)
    if count==0 then return end
    StyleMenuFrame(menu)
    menu:SetWidth(math.max(174,button:GetWidth())); menu:SetHeight(math.min(count,5)*20+8)
    menu:ClearAllPoints(); menu:SetPoint("TOPLEFT",button,"BOTTOMLEFT",0,-2)
    menu.owner=button; menu.changed=onChange
    local scroll=C.EnsureDenyListScroll(menu,{
        width=150,rowHeight=20,x=4,y=-4,minScrollCount=6,
        createRow=function(parent)
            local row=CreateFrame("Button",nil,parent); row:SetWidth(150); row:SetHeight(18)
            row.label=row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            row.label:SetPoint("LEFT",row,"LEFT",4,0); row.label:SetWidth(142); row.label:SetJustifyH("LEFT")
            row:SetScript("OnClick",function()
                local name=row.value; local owner=menu.owner; local changed=menu.changed
                menu:Hide(); owner.label:SetText(name)
                if changed then changed(name) end
            end)
            return row
        end,
        bindRow=function(row,name) row.value=name; row.label:SetText(name) end,
    })
    scroll.viewport:SetHeight(math.min(count,5)*20)
    scroll.thumb:EnableMouseWheel(true); scroll.thumb:SetScript("OnMouseWheel",scroll.track:GetScript("OnMouseWheel"))
    scroll.items=button.options; scroll.offset=0; scroll.dragging=false; scroll.Paint(); menu:Show()
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

-- The tiers a hire-from character holds, from this account's list or a linked account's
-- snapshot; only the base tier while its licences are unknown.
local function TiersForCharacter(name)
    return C.HireFromTiers(DB, UnitName("player"), GetRealmName(), name) or {"t0d"}
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

-- The live game and the server's lists (this account's, or a linked account's synced rows)
-- come first; a remembered faction may be a guess from an old hire's race.
local function FactionForCharacter(name)
    local character = C.Trim(name)
    if character == "" then return nil end
    if type(UnitName) == "function" and type(UnitFactionGroup) == "function" and UnitName("player") == character then
        local live = UnitFactionGroup("player")
        RememberFaction(character, live)
        return live
    end
    local synced = C.HireFromFaction(DB, UnitName("player"), GetRealmName(), character)
    if synced then return synced end
    HarvestKnownFactions()
    if type(DB.characterFactions) == "table" and DB.characterFactions[character] then return DB.characterFactions[character] end
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
    -- Compact, beside the name line, so the card's bottom right can show the hire's tier.
    MakeButton(row, "X", 16, 82, -3, function() RemoveEntry(index) end):SetHeight(12)
end

-- A normal hire's licence tier as the sidebar writes it (T5R): raid tiers in the header
-- gold, dungeon tiers in the panel's light blue. Returns the label ("" when none).
function C.PaintTier(text, entry)
    local label = entry and entry.kind == "normal" and C.TierLabel(entry.tier) or ""
    text:SetText(label)
    if string.find(label, "R$") then text:SetTextColor(1.0, 0.84, 0.28) else text:SetTextColor(0.75, 0.88, 1.0) end
    return label
end

-- The tier sits bottom right under the remove button, a size below the card text. Its box
-- is sized to its text by FitCardLine.
function C.TierText(parent)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -15); text:SetWidth(24); text:SetHeight(10); text:SetJustifyH("RIGHT")
    if text.GetFont then
        local file, _, flags = text:GetFont()
        if file and flags then text:SetFont(file, 9, flags) elseif file then text:SetFont(file, 9) end
    end
    return text
end

-- A card's second line: class and role at the left, and the painted tier (or nil) whole at
-- the right. A measured width runs past the drawn letters, so the class line may reach 2
-- units into the tier's measured width and the drawn text still keeps clear (in the game
-- font a strict fit cut the "r" from "Warrior MDPS" beside T0D with 7 units free). Only when
-- the line still does not fit does the class name lose letters from its end, never the role.
function C.FitCardLine(line, tier, class, role)
    local room = 94
    if tier then
        local width = tier:GetStringWidth() or 0
        if width < 8 then width = 20 end -- no font metrics yet: room for three letters
        tier:SetWidth(width + 1)
        room = 96 - width
    end
    line:SetWidth(room + 1)
    local cut = class
    line:SetText(cut .. " " .. role)
    while string.len(cut) > 3 and (line:GetStringWidth() or 0) > room do
        cut = string.sub(cut, 1, string.len(cut) - 1)
        line:SetText(cut .. " " .. role)
    end
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
    line2:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -15); line2:SetHeight(10); line2:SetJustifyH("LEFT")
    if line2.SetNonSpaceWrap then line2:SetNonSpaceWrap(false) end
    line2:SetTextColor(color[1], color[2], color[3])
    if entry.kind == "normal" and C.TierLabel(entry.tier) ~= "" then
        row.tierText = C.TierText(row); C.PaintTier(row.tierText, entry)
    end
    C.FitCardLine(line2, row.tierText, CLASS_LABELS[classKey] or classKey, ROLE_SHORT[entry.role] or entry.role or "")
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
            GameTooltip:AddLine(C.TierLabel(entry.tier) .. "  " .. (SPEC_LABELS[entry.spec] or entry.spec or "") .. "  " .. (RACE_LABELS[entry.race] or "") .. "  " .. (GENDER_LABELS[entry.gender] or ""), 0.8,0.8,0.8)
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
            dragGhost.line2:SetHeight(10); dragGhost.line2:SetJustifyH("LEFT")
            if dragGhost.line2.SetNonSpaceWrap then dragGhost.line2:SetNonSpaceWrap(false) end
            dragGhost.tier = C.TierText(dragGhost)
        end
        PaintEntryRow(dragGhost, entry)
        dragGhost.line1:SetText(tostring(index) .. " " .. name)
        dragGhost.line1:SetTextColor(0.95, 0.96, 1.0)
        dragGhost.line2:SetTextColor(color[1], color[2], color[3])
        C.FitCardLine(dragGhost.line2, C.PaintTier(dragGhost.tier, entry) ~= "" and dragGhost.tier or nil,
            CLASS_LABELS[classKey] or classKey, ROLE_SHORT[entry.role] or entry.role or "")
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
    C.RefreshNormalCount(addNormalFrame)
    if addLegacyFrame and addLegacyFrame:IsShown() and C.RefreshLegacyNameSuggestions then
        C.RefreshLegacyNameSuggestions(addLegacyFrame.nameInput)
    end
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
            local seen={}; for _,name in ipairs(licensed) do seen[string.lower(name)]=true end
            for _,name in ipairs(C.RememberedHireNames(DB,UnitName("player"),GetRealmName())) do
                if not seen[string.lower(name)] then table.insert(licensed,name); seen[string.lower(name)]=true end
            end
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
    for _,name in ipairs(C.RememberedHireNames(DB,UnitName("player"),GetRealmName())) do found[name]=true end
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
        C.RememberLegacyCharacter(DB, record.name, record.class)
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
    -- Startup initializes DB; unrelated chat must not rescan every preset.
    -- Keep first-use and SavedVariable rebinding safe without a per-message migration.
    if DB ~= ShirsRaidBuilderDB or type(DB.presets) ~= "table" then EnsureDB() end
    if C.StoreLegacyCharacterList(DB, arg1) or (event == "CHAT_MSG_ADDON" and C.StoreLegacyCharacterList(DB, arg2)) then
        if addLegacyFrame and addLegacyFrame:IsShown() then C.RefreshLegacyCharacter(addLegacyFrame) end
        return
    end
    local raw = tostring(arg1 or "")
    if arg2 and arg2 ~= "" then raw = raw .. " " .. tostring(arg2) end
    local payload = C.ExtractInviteListPayload(raw)
    if not payload then return end
    local records = C.ParseInviteList(payload)
    if C.LicenseObserve then
        C.LicenseObserve(C.LicenseReadPayload(C.ExtractInviteListPayload(tostring(arg1 or "")) or C.ExtractInviteListPayload(tostring(arg2 or ""))))
    end
    StoreInviteCharacters(records)
    if addLegacyFrame and addLegacyFrame:IsShown() then C.RefreshLegacyCharacter(addLegacyFrame) end
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

function C.AccountScroll(value)
    if not mainFrame or not mainFrame.accountScroll then return end
    local maximum=math.max(0,mainFrame.accountContent:GetHeight()-mainFrame.accountScroll:GetHeight())
    value=math.max(0,math.min(maximum,value or 0))
    mainFrame.accountScroll:SetVerticalScroll(value)
    if mainFrame.accountBar then
        local track=mainFrame.accountBar
        track.maximum=maximum
        local height=track:GetHeight()
        local thumbHeight=math.min(height,math.max(16,height*mainFrame.accountScroll:GetHeight()/mainFrame.accountContent:GetHeight()))
        track.thumb:SetHeight(thumbHeight)
        track.thumb:ClearAllPoints()
        track.thumb:SetPoint("TOPLEFT",track,"TOPLEFT",1,maximum>0 and -(height-thumbHeight)*value/maximum or 0)
        if maximum>0 and DB.uiMode~="sort" then track:Show() else track:Hide(); track.dragging=false end
    end
end

function C.AccountWheel()
    C.AccountScroll(mainFrame.accountScroll:GetVerticalScroll()-(arg1 or 0)*60)
end

function C.CreateAccountScrollTrack()
    local track,thumb=C.CreateScrollTrack(mainFrame,mainFrame.accountScroll)
    mainFrame.accountBar=track
    track:SetScript("OnMouseWheel",C.AccountWheel)
    thumb:EnableMouseWheel(true); thumb:SetScript("OnMouseWheel",C.AccountWheel)
    track:SetScript("OnClick",function()
        local _,y=GetCursorPosition()
        local direction=y/track:GetEffectiveScale()>(thumb:GetTop() or 0) and -1 or 1
        C.AccountScroll(mainFrame.accountScroll:GetVerticalScroll()+direction*mainFrame.accountScroll:GetHeight())
    end)
    thumb:SetScript("OnMouseDown",function()
        if arg1~="LeftButton" then return end
        local _,y=GetCursorPosition()
        track.dragging=true; track.dragY=y/track:GetEffectiveScale()
        track.dragValue=mainFrame.accountScroll:GetVerticalScroll()
    end)
    local function StopDrag() track.dragging=false end
    thumb:SetScript("OnMouseUp",StopDrag); track:SetScript("OnMouseUp",StopDrag)
    track:SetScript("OnHide",StopDrag); mainFrame.accountScroll:SetScript("OnHide",StopDrag)
    thumb:SetScript("OnUpdate",function()
        if not track.dragging then return end
        if type(IsMouseButtonDown)=="function" and not IsMouseButtonDown("LeftButton") then StopDrag(); return end
        local travel=track:GetHeight()-thumb:GetHeight()
        if travel<=0 or not track.maximum or track.maximum<=0 then StopDrag(); return end
        local _,y=GetCursorPosition()
        C.AccountScroll(track.dragValue+(track.dragY-y/track:GetEffectiveScale())*track.maximum/travel)
    end)
end

function C.AccountRow(y,height)
    mainFrame.accountPool=mainFrame.accountPool or {}
    local index=table.getn(mainFrame.accountRows)+1
    local row=mainFrame.accountPool[index]
    if not row then
        row=CreateFrame("Button",nil,mainFrame.accountContent)
        row.lines={}
        for i=1,2 do
            local text=row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            text:SetPoint("TOPLEFT",row,"TOPLEFT",4,-3-(i-1)*14)
            text:SetWidth(153); text:SetHeight(14); text:SetJustifyH("LEFT")
            row.lines[i]=text
        end
        row.countText=row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        row.countText:SetPoint("TOPRIGHT",row,"TOPRIGHT",-4,-3)
        row.countText:SetHeight(14); row.countText:SetJustifyH("RIGHT"); row.countText:SetTextColor(1,0.85,0.25)
        row:EnableMouseWheel(true); row:SetScript("OnMouseWheel",C.AccountWheel)
        mainFrame.accountPool[index]=row
    end
    row.model=nil
    row:ClearAllPoints(); row:SetPoint("TOPLEFT",mainFrame.accountContent,"TOPLEFT",2,y)
    row:SetWidth(161); row:SetHeight(height); row:SetScript("OnClick",nil); row:SetScript("OnEnter",nil); row:SetScript("OnLeave",nil)
    for _,text in ipairs(row.lines) do text:SetText(""); text:Hide() end
    row.lines[1]:SetWidth(153); row.countText:SetText(""); row.countText:Hide()
    row:Show(); table.insert(mainFrame.accountRows,row)
    return row
end

function C.DrawCharacterLicenseRow(model,y)
    local row=C.AccountRow(y,model.height)
    row.model=model
    local values={model.title,model.raids}
    for i,text in ipairs(row.lines) do
        text:SetText(values[i] or "")
        if i==2 then text:SetTextColor(1,0.35,0.1) else text:SetTextColor(0.75,0.88,1.0) end
        if values[i] and values[i]~="" then text:Show() end
    end
    if model.countText then
        row.countText:SetText(model.countText); row.countText:Show()
        row.lines[1]:SetWidth(153-row.countText:GetStringWidth()-6)
    end
    return row
end

function RefreshAccountPanel()
    if not mainFrame or not mainFrame.accountContent then return end
    if DB.uiMode == "sort" then
        mainFrame.accountContent:Hide()
        if mainFrame.accountBar then mainFrame.accountBar:Hide() end
        return
    end
    mainFrame.accountContent:Show()
    for i = 1, table.getn(mainFrame.accountRows or {}) do mainFrame.accountRows[i]:Hide() end
    mainFrame.accountRows = {}
    local preset = EnsureDB()
    local counts = {}
    local names,records = {},{}
    for _,record in ipairs(C.AccountReadLocal()) do records[record.name]=record; table.insert(names,record.name) end
    C.SortInviteNamesByRaidLicense(names, records)
    local realm = type(GetRealmName) == "function" and GetRealmName()
    local now = type(time) == "function" and time()
    local y = -8
    for i = 1, table.getn(names) do
        local name = names[i]
        local record = records[name]
        local savedRaids = C.AccountRaidLabels(record,now)
        counts[name]=C.NormalHireCountForCharacter(preset.entries,name)
        local model=C.CharacterLicenseRow(name,record,counts[name],savedRaids)
        local row=C.DrawCharacterLicenseRow(model,y)
        local captured = name
        row:SetScript("OnClick", function()
            SetStatus(captured .. " has " .. (counts[captured] or 0) .. " hire(s) in this preset.")
        end)
        y = y - model.height - 2
    end
    if C.LicenseSidebar then y=C.LicenseSidebar(y) end
    mainFrame.accountContent:SetHeight(math.max(100, -y + 10))
    C.AccountScroll(mainFrame.accountScroll:GetVerticalScroll())
end

CloseContext = function()
    contextIndex = nil
    if contextShield then contextShield:Hide() end
    if contextFrame then contextFrame:Hide() end
end

local function HideFloatingPanels()
    if C.planShareFrame then C.planShareFrame:Hide() end
    if C.planReceiveFrame then C.planReceiveFrame:Hide() end
    if C.licenseView then C.licenseView:Hide() end
    if C.peerPanel then C.peerPanel:Hide() end
    if C.PeerBuilderClosed then C.PeerBuilderClosed("Builder closed; peer will time out") end
    CloseContext()
    CloseChoiceMenu()
    if abilityMenu then abilityMenu:Hide() end
    if legacyNameMenu then legacyNameMenu:Hide() end
    if setupFrame then setupFrame:Hide() end
    if denyFrame then denyFrame:Hide() end
    if settingsFrame then settingsFrame:Hide() end
    if addNormalFrame then addNormalFrame:Hide() end
    if addLegacyFrame then addLegacyFrame:Hide() end
    if namePrompt then namePrompt:Hide() end
    if C.capturePrompt then C.capturePrompt:Hide() end
    if C.importFrame then C.importFrame:Hide() end
    if dragGhost then dragGhost:Hide() end
    if dragUpdate then dragUpdate:SetScript("OnUpdate", nil) end
    if contextShield then contextShield:Hide() end
    if GameTooltip then GameTooltip:Hide() end
end

-- Move a normal hire to another hire-from character. Refused when that character already
-- has four hires on the board, or its faction cannot have the class. A tier it lacks drops
-- to its highest (T0 while its licences are unknown); the base tier and tiers it holds
-- stay. A race of the other faction becomes the first of its own for the class.
function C.MoveHireFrom(index, account)
    local entries = EnsureDB().entries
    local entry = entries[index]
    if not entry or entry.kind ~= "normal" or not C.IsSafeCharacterName(account) then return end
    if C.NormalHireCountForCharacter(entries, account) >= 4 then
        SetStatus(account .. " already has the maximum four companions in this hiring plan.")
        return
    end
    local faction = FactionForCharacter(account)
    if faction and not C.ClassAllowedForFaction(entry.class, faction) then
        SetStatus(account .. " is " .. faction .. " and cannot hire a " .. (CLASS_LABELS[entry.class] or tostring(entry.class)) .. ".")
        return
    end
    local before = C.TierLabel(entry.tier)
    local known = C.HireFromTiers(DB, UnitName("player"), GetRealmName(), account)
    entry.account = account
    entry.tier = C.FitTier(entry.tier, TiersForCharacter(account))
    if faction and RACE_FACTIONS[entry.race] and RACE_FACTIONS[entry.race] ~= faction then
        local races = RacesForClassAndFaction(entry.class, faction)
        if races[1] then entry.race = races[1] end
    end
    RefreshComposition()
    local after = C.TierLabel(entry.tier)
    if after ~= before and not known then SetStatus("Spawn " .. index .. " now hires from " .. account .. " at " .. after .. " (was " .. before .. "): its licences are unknown on this account.")
    elseif after ~= before then SetStatus("Spawn " .. index .. " now hires from " .. account .. " at " .. after .. ", its highest tier (was " .. before .. ").")
    else SetStatus("Spawn " .. index .. " now hires from " .. account .. ".") end
end

OpenContextMenu = function(index, anchor, page)
    local entry = EnsureDB().entries[index]
    if not C.IsFilledEntry(entry) then return end
    -- A second right-click closes the menu; Back asks for the "main" page instead.
    if not page and contextIndex == index and contextFrame and contextFrame:IsShown() then
        CloseContext()
        return
    end
    if page == "main" then page = nil end
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
            AddContext("Individual commands", function() CloseContext(); OpenDenyEditor(index) end)
        end
        if entry.kind == "normal" then
            AddContext("Hire from: " .. (entry.account or "?"), function() OpenContextMenu(index, anchor, "account") end)
            AddContext("Tier: " .. C.TierLabel(entry.tier or "t2r"), function() OpenContextMenu(index, anchor, "tier") end)
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
        AddContext("Back", function() OpenContextMenu(index, anchor, "main") end)
        local tiers = TiersForCharacter(entry.account)
        for i = 1, table.getn(tiers) do
            local tier = tiers[i]
            AddContext(tier, function() ApplyField("tier", tier) end)
        end
    elseif page == "account" then
        AddContext("Back", function() OpenContextMenu(index, anchor, "main") end)
        for _, name in ipairs(DiscoverCharacterNames()) do
            local who = name
            if who ~= "(none)" and string.lower(who) ~= string.lower(entry.account or "") then
                AddContext(who, function() CloseContext(); C.MoveHireFrom(index, who) end)
            end
        end
    elseif page == "gender" then
        AddContext("Back", function() OpenContextMenu(index, anchor, "main") end)
        AddContext("Male", function() ApplyField("gender", "male") end)
        AddContext("Female", function() ApplyField("gender", "female") end)
    elseif page == "role" then
        AddContext("Back", function() OpenContextMenu(index, anchor, "main") end)
        local roles = CLASS_ROLES[entry.class] or ROLES
        for i = 1, table.getn(roles) do
            local role = roles[i]
            AddContext(ROLE_LABELS[role] or role, function() ApplyField("role", role) end)
        end
    elseif page == "spec" then
        AddContext("Back", function() OpenContextMenu(index, anchor, "main") end)
        local specs = SpecsForClassRole(entry.class, entry.role)
        for i = 1, table.getn(specs) do
            local spec = specs[i]
            AddContext(SPEC_LABELS[spec] or spec, function() ApplyField("spec", spec) end)
        end
    elseif page == "race" then
        AddContext("Back", function() OpenContextMenu(index, anchor, "main") end)
        local races = RacesForClassAndFaction(entry.class, FactionForCharacter(entry.account or ""))
        for i = 1, table.getn(races) do
            local race = races[i]
            AddContext(RACE_LABELS[race] or race, function() ApplyField("race", race) end)
        end
    elseif page == "pet" then
        AddContext("Back", function() OpenContextMenu(index, anchor, "main") end)
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
    local scroll = C.EnsureDenyListScroll(denyFrame, {
        width = 310,
        rowHeight = 24,
        x = 18,
        y = -72,
        createRow = function(parent)
            local row = CreateFrame("Frame", nil, parent)
            row:SetWidth(310)
            row:SetHeight(22)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.text:SetWidth(220)
            row.text:SetJustifyH("LEFT")
            row.text:SetTextColor(0.90,0.95,0.75)
            MakeButton(row, "X", 24, 246, 0, function()
                if row.denyIndex then table.remove(denyWorking, row.denyIndex); RefreshDenyRows() end
            end)
            return row
        end,
        bindRow = function(row, item, index)
            row.denyIndex = index
            row.text:SetText(item)
        end,
    })
    scroll.items = denyWorking
    scroll.Paint()
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
        local role = RoleValue(settingsRoleButton.label:GetText())
        local class = ClassValue(settingsClassButton.label:GetText())
        local rule = C.FindDenyRule(EnsureDB().denyRules, role, class)
        if rule then return rule.abilities end
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
    if not C.EditorEntryIsCurrent(denyFrame) then SetStatus("The selected individual changed. Reopen its commands."); return end
    local query = string.lower(C.Trim(denyFrame.input:GetText()))
    local catalog = C.AbilitiesForClassRole(ShirsRaidBuilderAbilities, denyFrame.entry.class, "all")
    for i=1,table.getn(catalog) do
        if string.lower(catalog[i]) == query then
            table.insert(denyWorking, catalog[i]); denyWorking = C.NormalizeDenyList(denyWorking)
            denyFrame.input:SetText(""); HideAbilitySuggestions(); RefreshDenyRows(); return
        end
    end
    SetStatus("Choose an ability from this individual's class deny list.")
end

OpenDenyEditor = function(index)
    local entry = EnsureDB().entries[index]; if not entry or entry.kind ~= "legacy" then SetStatus("Only legacy hires can have custom deny lists."); return end
    CloseChoiceMenu()
    if setupFrame then setupFrame:Hide() end
    denyIndex = index; denyWorking = C.CopyDenyList(entry.denyList)
    if not denyFrame then
        denyFrame = CreateFrame("Frame", "ShirsRaidBuilderDenyFrame", UIParent); denyFrame:SetWidth(370); denyFrame:SetHeight(280); StylePanelFrame(denyFrame)
        denyFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
        RegisterEscapeFrame(denyFrame)
        denyFrame:SetScript("OnHide", HideAbilitySuggestions)
        denyFrame.title = denyFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight"); denyFrame.title:SetPoint("TOP",denyFrame,"TOP",0,-14)
        denyFrame.note = denyFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); denyFrame.note:SetPoint("TOPLEFT",denyFrame,"TOPLEFT",18,-34); denyFrame.note:SetText("Search this class's abilities, or open Other Commands."); denyFrame.note:SetTextColor(0.75,0.80,0.90)
        denyFrame.input = MakeInput(denyFrame, 240, 18, -54, "")
        denyFrame.input:SetScript("OnEnterPressed", AddWorkingDeny)
        denyFrame.input:SetScript("OnTextChanged", function()
            local current = denyFrame.entry
            RefreshAbilitySuggestions(denyFrame.input, current and current.class or "shaman", "all")
        end)
        denyFrame.input:SetScript("OnEditFocusGained", function() RefreshAbilitySuggestions(denyFrame.input, denyFrame.entry.class, "all") end)
        MakeButton(denyFrame,"Add",64,264,-54,AddWorkingDeny)
        MakeButton(denyFrame,"Other Commands",142,18,-210,function()
            if not C.EditorEntryIsCurrent(denyFrame) then SetStatus("The selected individual changed. Reopen its commands."); return end
            HideAbilitySuggestions(); C.OpenIndividualSetup(denyFrame.entry)
        end)
        MakeButton(denyFrame,"Save",64,18,14,function()
            HideAbilitySuggestions()
            if not C.EditorEntryIsCurrent(denyFrame) then SetStatus("The selected individual changed. Reopen its commands."); return end
            denyFrame.entry.denyList=C.NormalizeDenyList(denyWorking); denyFrame:Hide(); RefreshComposition()
        end, true)
        MakeButton(denyFrame,"Cancel",64,86,14,function() HideAbilitySuggestions(); denyFrame:Hide() end, true)
    end
    denyFrame.entry=entry; denyFrame.preset=EnsureDB(); denyFrame.entryClass=entry.class
    denyFrame.title:SetText("Individual commands: " .. C.GetWhisperTarget(entry)); denyFrame.input:SetText(""); HideAbilitySuggestions(); RefreshDenyRows(); denyFrame:Show()
end
ShirsRaidBuilder_OpenDenyEditor = OpenDenyEditor

function C.ResetDenyRuleEditor()
    settingsRoleButton.label:SetText("Melee DPS")
    settingsClassButton.options = ClassesForRole("mdps")
    settingsClassButton.label:SetText("Shaman")
    settingsAbilityInput:SetText("")
    HideAbilitySuggestions()
end

local function RefreshRuleList()
    if not settingsFrame then return end
    local scroll = C.EnsureDenyListScroll(settingsFrame, {
        width = 360,
        rowHeight = 32,
        x = 18,
        y = -180,
        createRow = function(parent)
            local row = CreateFrame("Button",nil,parent); row:SetWidth(360); row:SetHeight(30)
            row.text = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); row.text:SetPoint("LEFT",row,"LEFT",4,0); row.text:SetWidth(278)
            row.text:SetTextColor(0.85,0.90,1.0)
            -- Clicking a row loads it into the dropdowns; Add then targets by
            -- those values, never by a remembered index.
            row:SetScript("OnClick",function()
                local rule=row.rule
                if not rule then return end
                settingsRoleButton.label:SetText(ROLE_LABELS[rule.role] or rule.role)
                settingsClassButton.options=ClassesForRole(rule.role)
                settingsClassButton.label:SetText(CLASS_LABELS[rule.class] or rule.class)
                settingsAbilityInput:SetText("")
                RefreshAbilitySuggestions(settingsAbilityInput)
                SetStatus("Selected deny rule. Changing Role or Class adds elsewhere.")
            end)
            -- Remove captures the rule table itself; deleting by position let
            -- one stale click take out the wrong rule after the list shifted.
            MakeButton(row,"Remove",64,296,0,function()
                local rule=row.rule
                if not rule then return end
                local all=EnsureDB().denyRules
                for ri=1,table.getn(all) do
                    if all[ri]==rule then table.remove(all,ri) break end
                end
                C.ResetDenyRuleEditor()
                RefreshRuleList(); RefreshComposition(); SetStatus("Removed deny rule. Ready to add another.")
            end)
            return row
        end,
        bindRow = function(row, item)
            row.rule = item
            row.text:SetText((ROLE_LABELS[item.role] or item.role) .. " / " .. (CLASS_LABELS[item.class] or item.class) .. ": " .. table.concat(item.abilities, ", "))
        end,
    })
    scroll.items = EnsureDB().denyRules
    scroll.Paint()
end

local function OpenSettings()
    if not settingsFrame then
        settingsFrame=CreateFrame("Frame","ShirsRaidBuilderSettingsFrame",UIParent); settingsFrame:SetWidth(430); settingsFrame:SetHeight(390); StylePanelFrame(settingsFrame); settingsFrame:SetPoint("CENTER",UIParent,"CENTER",0,0)
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
                local p=EnsureDB()
                -- Target strictly by what the dropdowns show right now.
                local role=RoleValue(settingsRoleButton.label:GetText())
                local class=ClassValue(settingsClassButton.label:GetText())
                if role~="all" and not C.RoleAllowedForClass(class,role) then
                    SetStatus(class .. " cannot take the " .. (ROLE_LABELS[role] or role) .. " role.")
                    return
                end
                local lowerV=string.lower(v)
                for ri = 1, table.getn(p.denyRules) do
                    local rule = p.denyRules[ri]
                    if C.DenyRuleMatches(rule, role, class) then
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
                local rule = C.FindDenyRule(p.denyRules, role, class)
                if not rule then rule={role=role,class=class,abilities={}}; table.insert(p.denyRules,rule) end
                table.insert(rule.abilities,v)
                rule.abilities=C.NormalizeDenyList(rule.abilities)
                settingsAbilityInput:SetText(""); HideAbilitySuggestions(); RefreshRuleList(); RefreshComposition()
            end
        end)
        addAbility:SetFrameLevel(settingsFrame:GetFrameLevel()+6)
        MakeButton(settingsFrame,"New",64,18,14,C.ResetDenyRuleEditor,true)
        MakeButton(settingsFrame,"Close",64,86,14,function() HideAbilitySuggestions(); settingsFrame:Hide() end,true)
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
C.HUNTER_GROWL = {"(none)","Deny","Allow"}
local WARLOCK_PETS = {"(none)","On","Off","Imp","Voidwalker","Succubus","Felhunter"}
local MAGE_MAGIC = {"(none)","None","Amplify","Dampen"}
C.MAGE_DRINK = {"(none)","10%","20%","30%","40%","50%","60%","70%","80%","90%","100%"}

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

local function SetupSummary(rule, entry)
    local who = ApplyLabel(rule.role) .. " " .. (CLASS_LABELS[rule.class] or rule.class)
    if entry then who = C.GetWhisperTarget(entry) end
    if rule.class == "paladin" then return who .. ": " .. (rule.aura or "(none)") end
    if rule.class == "hunter" then
        local parts = {}
        if rule.aspect and rule.aspect ~= "" then table.insert(parts, rule.aspect) end
        if rule.pet and rule.pet ~= "" then table.insert(parts, "Pet " .. rule.pet) end
        if rule.growl and rule.growl ~= "" then table.insert(parts, "Growl " .. rule.growl) end
        if table.getn(parts) == 0 then return who end
        return who .. ": " .. table.concat(parts, ", ")
    end
    if rule.class == "warlock" then
        if rule.pet and rule.pet ~= "" then return who .. ": Pet " .. rule.pet end
        return who
    end
    if rule.class == "mage" then
        local parts = {}
        if rule.magic and rule.magic ~= "" then table.insert(parts, "Magic " .. rule.magic) end
        if rule.drink and rule.drink ~= "" then table.insert(parts, "Drink " .. rule.drink .. "%") end
        if table.getn(parts) > 0 then return who .. ": " .. table.concat(parts, ", ") end
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
    local scroll = C.EnsureDenyListScroll(setupFrame, {
        width = 484,
        rowHeight = 30,
        x = 18,
        y = -236,
        createRow = function(parent)
            local row = CreateFrame("Button",nil,parent); row:SetWidth(484); row:SetHeight(28)
            row.text = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); row.text:SetPoint("LEFT",row,"LEFT",4,0); row.text:SetWidth(380); row.text:SetJustifyH("LEFT")
            row.text:SetTextColor(0.85,0.90,1.0)
            MakeButton(row,"Remove",64,414,2,function()
                if not row.setupIndex then return end
                local rules = C.SetupRulesForEditor()
                if not rules then return end
                table.remove(rules, row.setupIndex)
                RefreshSetupList(); SetStatus("Removed totem/aura rule.")
            end)
            return row
        end,
        bindRow = function(row, item, index)
            row.setupIndex = index
            row.text:SetText(SetupSummary(item, setupFrame.entry))
        end,
    })
    scroll.items = C.SetupRulesForEditor() or {}
    scroll.Paint()
end

local function ShowSetupClassFields()
    if not setupFrame then return end
    local class = ClassValue(setupFrame.classButton.label:GetText())
    if setupFrame.entry then
        setupFrame.applyButton.options = {C.GetWhisperTarget(setupFrame.entry)}
        setupFrame.applyButton.label:SetText(setupFrame.applyButton.options[1])
    else
        setupFrame.applyButton.options = SetupApplyOptions(class)
        setupFrame.applyButton.label:SetText(PickListed(setupFrame.applyButton.options, setupFrame.applyButton.label:GetText()))
    end
    setupFrame.earthButton:Hide(); setupFrame.fireButton:Hide(); setupFrame.waterButton:Hide(); setupFrame.airButton:Hide(); setupFrame.auraButton:Hide(); setupFrame.aspectButton:Hide(); setupFrame.petButton:Hide(); setupFrame.growlButton:Hide(); setupFrame.magicButton:Hide(); setupFrame.drinkButton:Hide()
    setupFrame.earthCaption:Hide(); setupFrame.fireCaption:Hide(); setupFrame.waterCaption:Hide(); setupFrame.airCaption:Hide(); setupFrame.auraCaption:Hide(); setupFrame.aspectCaption:Hide(); setupFrame.petCaption:Hide(); setupFrame.growlCaption:Hide(); setupFrame.magicCaption:Hide(); setupFrame.drinkCaption:Hide()
    if class == "paladin" then
        setupFrame.auraButton:Show(); setupFrame.auraCaption:Show()
    elseif class == "hunter" then
        setupFrame.aspectButton:Show(); setupFrame.aspectCaption:Show()
        setupFrame.petButton.options = HUNTER_PETS
        setupFrame.petButton.label:SetText("(none)")
        setupFrame.growlButton.label:SetText("(none)")
        setupFrame.petCaption:ClearAllPoints(); setupFrame.petCaption:SetPoint("TOPLEFT", setupFrame, "TOPLEFT", 278, -96)
        setupFrame.petButton:ClearAllPoints(); setupFrame.petButton:SetPoint("TOPLEFT", setupFrame, "TOPLEFT", 278, -112)
        setupFrame.petButton:SetWidth(210)
        setupFrame.petButton:Show(); setupFrame.petCaption:Show()
        setupFrame.growlButton:Show(); setupFrame.growlCaption:Show()
    elseif class == "warlock" then
        setupFrame.petButton.options = WARLOCK_PETS
        setupFrame.petButton.label:SetText("(none)")
        setupFrame.petCaption:ClearAllPoints(); setupFrame.petCaption:SetPoint("TOPLEFT", setupFrame, "TOPLEFT", 18, -96)
        setupFrame.petButton:ClearAllPoints(); setupFrame.petButton:SetPoint("TOPLEFT", setupFrame, "TOPLEFT", 18, -112)
        setupFrame.petButton:SetWidth(210)
        setupFrame.petButton:Show(); setupFrame.petCaption:Show()
    elseif class == "mage" then
        setupFrame.drinkButton.label:SetText("(none)")
        setupFrame.magicButton:Show(); setupFrame.magicCaption:Show()
        setupFrame.drinkButton:Show(); setupFrame.drinkCaption:Show()
    elseif class == "shaman" then
        setupFrame.earthButton:Show(); setupFrame.fireButton:Show(); setupFrame.waterButton:Show(); setupFrame.airButton:Show()
        setupFrame.earthCaption:Show(); setupFrame.fireCaption:Show(); setupFrame.waterCaption:Show(); setupFrame.airCaption:Show()
    end
end

function C.EditorEntryIsCurrent(host)
    local preset = EnsureDB()
    if host.preset ~= preset or not host.entry or host.entry.class ~= host.entryClass then return false end
    for i = 1, table.getn(preset.entries) do
        if preset.entries[i] == host.entry then return host.entry.kind == "legacy" end
    end
    return false
end

function C.SetupRulesForEditor()
    if not setupFrame.entry then return EnsureDB().setupRules end
    if not C.EditorEntryIsCurrent(setupFrame) then
        SetStatus("The selected individual changed. Reopen its commands.")
        return nil
    end
    if type(setupFrame.entry.setupRules) ~= "table" then setupFrame.entry.setupRules = {} end
    return setupFrame.entry.setupRules
end

local function OpenSetup(entry)
    CloseChoiceMenu()
    HideAbilitySuggestions()
    if denyFrame then denyFrame:Hide() end
    if not setupFrame then
        setupFrame=CreateFrame("Frame","ShirsRaidBuilderSetupFrame",UIParent); setupFrame:SetWidth(520); setupFrame:SetHeight(430); StylePanelFrame(setupFrame); setupFrame:SetPoint("CENTER",UIParent,"CENTER",0,0)
        setupFrame.title=setupFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight"); setupFrame.title:SetPoint("TOP",setupFrame,"TOP",0,-14)
        MakeButton(setupFrame,"X",22,480,-8,function() CloseChoiceMenu(); setupFrame:Hide() end)
        local note=setupFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); note:SetPoint("TOPLEFT",setupFrame,"TOPLEFT",18,-34); note:SetWidth(480); note:SetJustifyH("LEFT"); note:SetTextColor(0.75,0.80,0.90); setupFrame.note=note
        MakeCaption(setupFrame, "Class", 18, -52)
        MakeCaption(setupFrame, "Apply to", 176, -52)
        setupFrame.classButton=SelectButton(setupFrame, {"Shaman","Paladin","Hunter","Warlock","Mage"}, "Shaman", 148,18,-68,function() ShowSetupClassFields() end)
        setupFrame.applyButton=SelectButton(setupFrame, SetupApplyOptions("shaman"), "All", 148,176,-68,function() end)
        setupFrame.earthCaption=MakeCaption(setupFrame, "Earth", 18, -96)
        setupFrame.fireCaption=MakeCaption(setupFrame, "Fire", 268, -96)
        setupFrame.waterCaption=MakeCaption(setupFrame, "Water", 18, -140)
        setupFrame.airCaption=MakeCaption(setupFrame, "Air", 268, -140)
        setupFrame.auraCaption=MakeCaption(setupFrame, "Aura", 18, -96)
        setupFrame.aspectCaption=MakeCaption(setupFrame, "Aspect", 18, -96)
        setupFrame.petCaption=MakeCaption(setupFrame, "Pet", 18, -96)
        setupFrame.growlCaption=MakeCaption(setupFrame, "Growl policy", 18, -140)
        setupFrame.magicCaption=MakeCaption(setupFrame, "Magic", 18, -96)
        setupFrame.drinkCaption=MakeCaption(setupFrame, "Drink below", 268, -96)
        setupFrame.earthButton=SelectButton(setupFrame, EARTH_TOTEMS, "(none)", 240,18,-112,function() end)
        setupFrame.fireButton=SelectButton(setupFrame, FIRE_TOTEMS, "(none)", 240,268,-112,function() end)
        setupFrame.waterButton=SelectButton(setupFrame, WATER_TOTEMS, "(none)", 240,18,-156,function() end)
        setupFrame.airButton=SelectButton(setupFrame, AIR_TOTEMS, "(none)", 240,268,-156,function() end)
        setupFrame.auraButton=SelectButton(setupFrame, PALADIN_AURAS, "(none)", 240,18,-112,function() end)
        setupFrame.aspectButton=SelectButton(setupFrame, HUNTER_ASPECTS, "(none)", 240,18,-112,function() end)
        setupFrame.petButton=SelectButton(setupFrame, HUNTER_PETS, "(none)", 240,18,-112,function() end)
        setupFrame.growlButton=SelectButton(setupFrame, C.HUNTER_GROWL, "(none)", 240,18,-156,function() end)
        setupFrame.magicButton=SelectButton(setupFrame, MAGE_MAGIC, "(none)", 240,18,-112,function() end)
        setupFrame.drinkButton=SelectButton(setupFrame, C.MAGE_DRINK, "(none)", 210,268,-112,function() end)
        MakeButton(setupFrame,"Add Rule",86,18,-196,function()
            local rules=C.SetupRulesForEditor()
            if not rules then return end
            local class=ClassValue(setupFrame.classButton.label:GetText())
            local rule={class=class, role=setupFrame.entry and "all" or ApplyValue(setupFrame.applyButton.label:GetText()), spec="all"}
            if class == "paladin" then
                rule.aura=ChosenOrEmpty(setupFrame.auraButton.label:GetText())
                if rule.aura == "" then SetStatus("Choose a Paladin aura first."); return end
            elseif class == "hunter" then
                rule.aspect=ChosenOrEmpty(setupFrame.aspectButton.label:GetText())
                rule.pet=ChosenOrEmpty(setupFrame.petButton.label:GetText())
                rule.growl=ChosenOrEmpty(setupFrame.growlButton.label:GetText())
                if rule.aspect == "" and rule.pet == "" and rule.growl == "" then SetStatus("Choose an aspect, pet, or Growl policy first."); return end
            elseif class == "warlock" then
                rule.pet=ChosenOrEmpty(setupFrame.petButton.label:GetText())
                if rule.pet == "" then SetStatus("Choose a Warlock pet first."); return end
            elseif class == "mage" then
                rule.magic=ChosenOrEmpty(setupFrame.magicButton.label:GetText())
                rule.drink=string.gsub(ChosenOrEmpty(setupFrame.drinkButton.label:GetText()), "%%$", "")
                if rule.magic == "" and rule.drink == "" then SetStatus("Choose magic or a drink threshold first."); return end
            elseif class == "shaman" then
                rule.earth=ChosenOrEmpty(setupFrame.earthButton.label:GetText())
                rule.fire=ChosenOrEmpty(setupFrame.fireButton.label:GetText())
                rule.water=ChosenOrEmpty(setupFrame.waterButton.label:GetText())
                rule.air=ChosenOrEmpty(setupFrame.airButton.label:GetText())
                if rule.earth=="" and rule.fire=="" and rule.water=="" and rule.air=="" then SetStatus("Choose at least one totem slot."); return end
            else
                SetStatus("This class has no Other Commands. Use its deny list."); return
            end
            table.insert(rules, rule)
            RefreshSetupList(); SetStatus("Saved " .. SetupSummary(rule, setupFrame.entry) .. ".")
        end)
        MakeButton(setupFrame,"Close",64,18,14,function() CloseChoiceMenu(); setupFrame:Hide() end,true)
        setupFrame:SetScript("OnHide", function()
            CloseChoiceMenu()
            if setupFrame.entry and denyFrame and denyFrame.entry == setupFrame.entry
                and C.EditorEntryIsCurrent(denyFrame) then denyFrame:Show() end
        end)
        RegisterEscapeFrame(setupFrame)
        ShowSetupClassFields()
    end
    setupFrame.entry=entry
    setupFrame.preset=EnsureDB()
    setupFrame.entryClass=entry and entry.class
    if entry then
        setupFrame.classButton.label:SetText(CLASS_LABELS[entry.class] or entry.class)
        setupFrame.classButton:Disable(); setupFrame.applyButton:Disable()
        setupFrame.title:SetText("Other commands: " .. C.GetWhisperTarget(entry))
        setupFrame.note:SetText("Only this individual receives these commands, after general assignments.")
    else
        setupFrame.classButton:Enable(); setupFrame.applyButton:Enable()
        setupFrame.classButton.label:SetText("Shaman")
        setupFrame.title:SetText("Other commands: " .. (DB.currentPreset or "Default"))
        setupFrame.note:SetText("After hiring, whisper companions first, then overwrite matching legacy hires.")
    end
    local fields={"earth","fire","water","air","aura","aspect","pet","growl","magic","drink"}
    for i=1,table.getn(fields) do setupFrame[fields[i] .. "Button"].label:SetText("(none)") end
    ShowSetupClassFields(); RefreshSetupList(); setupFrame:Show()
end
C.OpenIndividualSetup = OpenSetup

local function HideLegacyNameSuggestions()
    C.HideLegacyNameSuggestions = HideLegacyNameSuggestions
    if legacyNameMenu then legacyNameMenu:Hide() end
end

local function RefreshLegacyNameSuggestions(input)
    if not input then return end
    HideLegacyNameSuggestions()
    local query = string.lower(C.Trim(input:GetText()))
    local names = DiscoverCharacterNames()
    local matches = {}
    local added = {}
    local preset = DB.presets and DB.presets[DB.currentPreset]
    for _, entry in pairs(preset and preset.entries or {}) do
        if entry.kind == "legacy" then added[string.lower(C.GetLegacyHireName(entry))] = true end
    end
    for i = 1, table.getn(names) do
        local name = names[i]
        local lower = string.lower(name)
        if query == "" or string.find(lower, query, 1, true) then
            if lower ~= query and not added[lower] then
                table.insert(matches, name)
            end
        end
    end
    if table.getn(matches) == 0 then return end
    local host = input:GetParent() or UIParent
    if not legacyNameMenu then
        legacyNameMenu = CreateFrame("Frame", "ShirsRaidBuilderLegacyNameMenu", host)
        legacyNameMenu:SetScript("OnHide", function()
            if legacyNameMenu.listScroll then legacyNameMenu.listScroll.dragging = false end
        end)
    else
        legacyNameMenu:SetParent(host)
    end
    legacyNameMenu:SetBackdrop(DROP_BG)
    legacyNameMenu:SetBackdropColor(0.02, 0.03, 0.06, 1.0)
    legacyNameMenu:SetBackdropBorderColor(0.55, 0.68, 0.88, 1.0)
    legacyNameMenu:SetFrameStrata(host.GetFrameStrata and host:GetFrameStrata() or "FULLSCREEN_DIALOG")
    -- Above the panel's raised dropdowns (+5), below its Add and Cancel buttons (+20).
    legacyNameMenu:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 80) + 10)
    legacyNameMenu:ClearAllPoints()
    legacyNameMenu:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -4, -2)
    local count = table.getn(matches)
    legacyNameMenu:SetWidth(count > 5 and 174 or 158)
    legacyNameMenu:SetHeight(math.min(count, 5) * 20 + 8)
    if host.addButton then host.addButton:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 80) + 20) end
    if host.cancelButton then host.cancelButton:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 80) + 20) end
    legacyNameMenu.input = input
    local scroll = C.EnsureDenyListScroll(legacyNameMenu, {
        width = 150, rowHeight = 20, x = 4, y = -4, minScrollCount = 6,
        createRow = function(parent)
            local row = CreateFrame("Button", nil, parent)
            row:SetWidth(150); row:SetHeight(18)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.text:SetWidth(142); row.text:SetJustifyH("LEFT")
            row.highlight = row:CreateTexture(nil, "BACKGROUND")
            row.highlight:SetAllPoints(row)
            row.highlight:SetTexture(1, 1, 1, 0.12)
            row.highlight:Hide()
            row:SetScript("OnEnter", function() row.highlight:Show() end)
            row:SetScript("OnLeave", function() row.highlight:Hide() end)
            row:SetScript("OnClick", function()
                legacyNameMenu.input:SetText(row.nameValue)
                HideLegacyNameSuggestions()
            end)
            return row
        end,
        bindRow = function(row, name)
            row.nameValue = name
            row.text:SetText(name)
            local color = CLASS_COLORS[C.LegacyCharacterClass(DB, name)]
            if color then row.text:SetTextColor(color[1], color[2], color[3])
            else row.text:SetTextColor(0.92, 0.95, 1.0) end
            row.highlight:Hide()
        end,
    })
    scroll.viewport:SetHeight(math.min(count, 5) * 20)
    scroll.thumb:EnableMouseWheel(true)
    scroll.thumb:SetScript("OnMouseWheel", scroll.track:GetScript("OnMouseWheel"))
    scroll.items = matches
    scroll.offset = 0
    scroll.dragging = false
    scroll.Paint()
    legacyNameMenu:Show()
end
C.RefreshLegacyNameSuggestions = RefreshLegacyNameSuggestions

function C.RefreshNormalCount(frame)
    if not frame or not frame.countText or not frame.characterButton then return end
    local name = C.Trim(frame.characterButton.label:GetText())
    if name == "" or name == "(none)" then frame.countText:SetText(""); return end
    frame.countText:SetText(C.NormalHireCountForCharacter(EnsureDB().entries, name) .. "/4")
end

local function RefreshNormalHireOptions(frame)
    if not frame or not frame.roleButton or not frame.classButton then return end
    C.RefreshNormalCount(frame)
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

function C.RefreshLegacyCharacter(frame)
    if not frame or not frame.classButton or not frame.roleButton then return end
    if frame.legacyEditedName == string.lower(C.Trim(frame.nameInput:GetText())) then return end
    local class = C.LegacyCharacterClass(DB, frame.nameInput:GetText())
    if not class then return end
    local role
    if frame.legacyRoleEditedName ~= string.lower(C.Trim(frame.nameInput:GetText())) then
        role = C.LegacyCharacterRole(DB, frame.nameInput:GetText(), class)
    end
    role = role or C.NormalizeRoleForClass(class, RoleValue(frame.roleButton.label:GetText()))
    frame.roleButton.label:SetText(ROLE_LABELS[role])
    frame.classButton.options = ClassesForRole(role)
    frame.classButton.label:SetText(CLASS_LABELS[class])
end

function C.RefreshLegacyRole(frame)
    frame.legacyRoleEditedName = string.lower(C.Trim(frame.nameInput:GetText()))
    local classes = ClassesForRole(RoleValue(frame.roleButton.label:GetText()))
    frame.classButton.options = classes
    frame.classButton.label:SetText(PickListed(classes, frame.classButton.label:GetText()))
    C.RefreshLegacyCharacter(frame)
end

function C.RequestLegacyCharacters(frame)
    EnsureInviteListener()
    if type(GetTime) ~= "function" or type(SendChatMessage) ~= "function" then return end
    local now = GetTime()
    if C.legacyRequestedAt and now - C.legacyRequestedAt < 2 then return end
    if not C.legacyQueryFrame then C.legacyQueryFrame = CreateFrame("Frame") end
    C.legacyRequestedAt = now
    C.legacyQueryFrame:SetScript("OnUpdate", function()
        if GetTime() - now < 0.5 then return end
        C.legacyQueryFrame:SetScript("OnUpdate", nil)
        if frame:IsShown() then SendChatMessage(".z addlegacy list", "SAY") end
    end)
end

-- Add Normal's tier starts on the selected character's highest, when its licences are known.
function C.TopTier(frame)
    local tiers = C.HireFromTiers(DB, UnitName("player"), GetRealmName(), frame.characterButton.label:GetText())
    if tiers and table.getn(tiers) > 0 then frame.tierButton.label:SetText(tiers[table.getn(tiers)]) end
end

-- The status line for a picked character: its faction, or what this account does not know
-- about it yet and what the lists offer meanwhile. The second value is true when both are known.
function C.CharacterNote(name, faction)
    local tiers = C.HireFromTiers(DB, UnitName("player"), GetRealmName(), name)
    if faction and tiers then return name .. " is " .. faction .. ".", true end
    local missing = not faction and not tiers and "faction and licences" or not faction and "faction" or "licences"
    local offer = not faction and not tiers and "every race and only T0 show" or not faction and "every race shows" or "only T0 shows"
    return name .. ": " .. missing .. " unknown on this account, so " .. offer .. ". Use Refresh Synchronization.", false
end

local function AddEntryEditor(kind)
    -- A dropdown left open on another hire panel is mouse-enabled at TOOLTIP
    -- strata; if it survives, it swallows every click on this panel.
    if C.CloseChoiceMenu then C.CloseChoiceMenu() end
    if C.HideAbilitySuggestions then C.HideAbilitySuggestions() end
    if C.HideLegacyNameSuggestions then C.HideLegacyNameSuggestions() end
    -- Pick the panel for this kind directly; `x and a or b` hands back the
    -- legacy frame whenever the normal panel has not been created yet.
    local frame
    if kind == "normal" then frame = addNormalFrame else frame = addLegacyFrame end
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
                C.TopTier(frame)
                SetStatus((C.CharacterNote(v, frame.selectedFaction)))
            end)
            frame.characterButton.scrollCharacters=true
            frame.countText=frame:CreateFontString(nil,"OVERLAY","GameFontNormal"); frame.countText:SetPoint("TOPLEFT",frame,"TOPLEFT",100,-28); frame.countText:SetTextColor(1,0.85,0.25)
        else
            MakeCaption(frame, "Character name", 18, -30)
            frame.nameInput=MakeInput(frame,150,18,-46,"")
            frame.nameInput:SetMaxLetters(12)
            -- Right-hand column: the name list opens below the name field and must not cover it.
            MakeCaption(frame,"Remembered characters",294,-78)
            frame.characterButton=SelectButton(frame,{"(none)"},"(none)",128,294,-94,function(v)
                if v~="(none)" then frame.nameInput:SetText(v); HideLegacyNameSuggestions() end
            end)
            frame.characterButton.scrollCharacters=true
            frame.nameInput:SetScript("OnTextChanged", function() frame.legacyEditedName=nil; frame.legacyRoleEditedName=nil; C.RefreshLegacyCharacter(frame); RefreshLegacyNameSuggestions(frame.nameInput) end)
            frame.nameInput:SetScript("OnEditFocusGained", function() RefreshLegacyNameSuggestions(frame.nameInput) end)
            frame.nameInput:SetScript("OnEditFocusLost", function() end)
            frame.nameInput:SetScript("OnEnterPressed", function() HideLegacyNameSuggestions() end)
        end
        MakeCaption(frame, "Role", 156, -30)
        frame.roleButton=SelectButton(frame, {"Tank","Healer","Ranged DPS","Melee DPS"}, "Melee DPS",128,156,-46,function()
            if kind == "normal" then RefreshNormalHireOptions(frame) else
                C.RefreshLegacyRole(frame)
            end
        end)
        MakeCaption(frame, "Class", 294, -30)
        frame.classButton=SelectButton(frame,ClassesForRole("mdps"),"Warrior",128,294,-46,function()
            if kind == "normal" then RefreshNormalHireOptions(frame)
            else frame.legacyEditedName=string.lower(C.Trim(frame.nameInput:GetText())) end
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
                for _, entry in pairs(p.entries) do
                    if entry.kind == "legacy" and string.lower(C.GetLegacyHireName(entry)) == string.lower(hireName) then
                        SetStatus(hireName .. " is already in this hiring plan.")
                        return
                    end
                end
                local whisperName=C.NormalizeLegacyName(hireName)
                HideLegacyNameSuggestions()
                local slot=C.FirstEmptySlot(p.entries, 40)
                if not slot then SetStatus("All 40 raid slots are full."); return end
                p.entries[slot]={kind="legacy",sourceName=hireName,charName=hireName,role=RoleValue(f.roleButton.label:GetText()),class=ClassValue(f.classButton.label:GetText()),spec="",denyList={},whisperName=whisperName}
                C.RememberLegacyCharacter(DB, hireName, p.entries[slot].class, p.entries[slot].role)
                RefreshComposition()
                f.nameInput:SetText(""); HideLegacyNameSuggestions()
                SetStatus("Added " .. whisperName .. " (hires " .. hireName .. ") in spawn " .. slot .. ".")
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
        C.TopTier(frame)
        local note, known = C.CharacterNote(frame.characterButton.label:GetText(), frame.selectedFaction)
        if not known and C.IsSafeCharacterName(frame.characterButton.label:GetText()) then SetStatus(note) end
    else
        frame.characterButton.options=DiscoverCharacterNames()
        if table.getn(frame.characterButton.options)==0 then frame.characterButton.options={"(none)"} end
    end
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:Show()
    if kind == "legacy" then
        C.RefreshLegacyCharacter(frame)
        RefreshLegacyNameSuggestions(frame.nameInput)
        C.RequestLegacyCharacters(frame)
    end
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

function C.RefreshImportPage(delta)
    local frame = C.importFrame
    CloseChoiceMenu()
    frame.page = math.max(1, math.min(math.max(1, math.ceil(table.getn(frame.names) / 8)), (frame.page or 1) + (delta or 0)))
    local options = {}
    for index = (frame.page - 1) * 8 + 1, math.min(frame.page * 8, table.getn(frame.names)) do table.insert(options, frame.names[index]) end
    frame.sourceButton.options = options
    frame.sourceButton.label:SetText(options[1] or "(no saved profiles)")
    if frame.page > 1 then frame.previousButton:Enable() else frame.previousButton:Disable() end
    if frame.page * 8 < table.getn(frame.names) then frame.nextButton:Enable() else frame.nextButton:Disable() end
    frame.pageLabel:SetText("Page " .. frame.page .. " / " .. math.max(1, math.ceil(table.getn(frame.names) / 8)))
end

function C.OpenPresetImport()
    EnsureDB()
    if executing or (C.sortFrame and C.sortFrame.busy) then SetStatus("Stop the current run before importing a profile."); return end
    HideFloatingPanels()
    if not C.importFrame then
        local frame = CreateFrame("Frame", "ShirsRaidBuilderImport", UIParent)
        C.importFrame = frame
        frame:SetWidth(430); frame:SetHeight(280); StylePanelFrame(frame)
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        MakeCaption(frame, "Import saved profile", 28, -16)
        MakeCaption(frame, "Copy from", 28, -42)
        frame.sourceButton = SelectButton(frame, {}, "", 374, 28, -60)
        frame.previousButton = MakeButton(frame, "Previous", 72, 28, -90, function() C.RefreshImportPage(-1) end)
        frame.nextButton = MakeButton(frame, "Next", 72, 106, -90, function() C.RefreshImportPage(1) end)
        frame.pageLabel = MakeCaption(frame, "", 194, -94)
        frame.warningCheck = CreateFrame("CheckButton", "ShirsRaidBuilderImportWarningCheck", frame, "UICheckButtonTemplate")
        frame.warningCheck:SetWidth(20); frame.warningCheck:SetHeight(20)
        frame.warningCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -122)
        frame.warningCheck:SetScript("OnClick", function()
            if frame.characterKey == "" then frame.warningCheck:SetChecked(1); return end
            if type(DB.importWarningHidden) ~= "table" then DB.importWarningHidden = {} end
            DB.importWarningHidden[frame.characterKey] = not frame.warningCheck:GetChecked() and true or nil
        end)
        MakeCaption(frame, "Show overwrite warning for this character", 50, -126)
        frame.message = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.message:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, -154)
        frame.message:SetWidth(374); frame.message:SetJustifyH("LEFT")
        frame.importButton = MakeButton(frame, "Import", 100, 90, 16, function()
            local bank, current = C.PresetBank(DB, DB.uiMode)
            local source = frame.sourceButton.label:GetText()
            if DB.uiMode ~= frame.mode or current ~= frame.destination or bank[current] ~= frame.destinationPreset or
                type(bank[source]) ~= "table" or source == current or executing or (C.sortFrame and C.sortFrame.busy) then
                frame:Hide(); SetStatus("The profile changed or a run started. Open Import again."); return
            end
            if not frame.confirmed and frame.warningCheck:GetChecked() then
                frame.confirmed = bank[source]
                frame.sourceButton:Disable(); frame.warningCheck:Disable()
                frame.previousButton:Disable(); frame.nextButton:Disable()
                frame.importButton.label:SetText("Overwrite")
                frame.message:SetText("Overwrite \"" .. current .. "\" with \"" .. source .. "\"?\n\nThis replaces its entries, deny rules and setup rules. The source profile stays unchanged.")
                return
            end
            if frame.confirmed and frame.confirmed ~= bank[source] then frame:Hide(); SetStatus("The source profile changed. Open Import again."); return end
            if C.ImportPreset(DB, frame.mode, source, current) then
                frame:Hide(); EnsureDB(); RefreshPresetButton(); RefreshComposition()
                SetStatus("Imported " .. source .. " into " .. current .. ".")
            end
        end, true)
        MakeButton(frame, "Cancel", 100, 240, 16, function() frame:Hide() end, true)
        frame:SetScript("OnHide", function() CloseChoiceMenu(); frame.confirmed = nil end)
    end
    local frame = C.importFrame
    local bank, current = C.PresetBank(DB, DB.uiMode)
    local names = {}
    for name, preset in pairs(bank) do
        if type(name) == "string" and name ~= current and type(preset) == "table" then table.insert(names, name) end
    end
    table.sort(names)
    frame.mode = DB.uiMode; frame.destination = current; frame.destinationPreset = bank[current]
    frame.confirmed = nil
    frame.names = names; frame.page = 1; C.RefreshImportPage(0)

    frame.sourceButton:Enable(); frame.warningCheck:Enable()
    frame.characterKey = C.CaptureWarningKey(type(UnitName) == "function" and UnitName("player") or "", type(GetRealmName) == "function" and GetRealmName() or "")
    frame.warningCheck:SetChecked(not (frame.characterKey ~= "" and type(DB.importWarningHidden) == "table" and DB.importWarningHidden[frame.characterKey] == true))
    frame.importButton.label:SetText("Import")
    if table.getn(names) == 0 then frame.importButton:Disable(); frame.sourceButton:Disable() else frame.importButton:Enable() end
    frame.message:SetText("Copy a saved " .. frame.mode .. " profile into \"" .. current .. "\". Its current contents will be replaced.")
    frame:Show()
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
    local raw = tostring(arg1 or "")
    if arg3 and arg3 ~= "" and arg3 ~= "UNKNOWN" and arg3 ~= "BATTLEGROUND" then return end
    local companions, valid = C.ParseGrinfoResponse(raw)
    if not valid and arg2 and arg2 ~= "" and arg2 ~= raw then
        companions, valid = C.ParseGrinfoResponse(arg2)
    end
    if not valid then return end
    C.latestCompanionList = companions
    C.latestCompanionInfoAt = GetTime and GetTime() or 0
    if (not executing) and (not C.sortWaiting) then return end
    -- A list answering another addon while a hire settles can predate that hire's
    -- companion. The queue asks for its own list once the hire has settled.
    if executing and GetTime and (executeHireReadyAt or 0) > GetTime() then return end
    if executeGrinfoReady and not C.grinfoRefresh then return end
    C.grinfoRefresh = nil
    executeCompanionList = companions
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
    local plan=C.handRunPlan or EnsureDB()
    local leftoverSet = C.LegacyNameSet(plan.entries)
    local live = C.AppendLegacyGroupMembers(C.KeepPresentCompanions(executeCompanionList, present), plan.entries, present)
    C.scopeAsks = nil; C.scopeCheckedAt = nil; C.scopeShort = nil; C.grinfoRefresh = nil
    if C.handRunPlan then
        -- Companions the run's earlier steps account for stay with those steps. A batch row
        -- with no companion here (its hire failed, or it never came) loses only its own
        -- group commands, and the chat names it; the run goes on.
        local unclaimed=plan.allRows and executeCompanionList or C.HandUnclaimed(C.HandStore().active,executeCompanionList)
        local missing
        live,missing=C.HandScopeFound(plan.entries,C.KeepPresentCompanions(unclaimed,present),UnitName("player"),present,C.HandOwn())
        for _,slot in ipairs(missing) do Chat(C.HandMissingNote(plan.entries[slot], slot)) end
    end
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

-- In a run, how many of the batch's own rows the current companion list cannot place yet
-- (HandScopeFound), checked twice a second. While any is missing the name wait goes on,
-- and the server is asked again, twice at most and 3 s apart: a list can answer before the
-- last hire's companion registered.
function C.HandScopeShort()
    if not C.handRunPlan then return 0 end
    local now = GetTime and GetTime() or 0
    if C.scopeCheckedAt and now - C.scopeCheckedAt < 0.5 then return C.scopeShort or 0 end
    C.scopeCheckedAt = now
    local present = SnapshotGroup()
    present[UnitName("player")] = nil
    local unclaimed = C.handRunPlan.allRows and executeCompanionList or C.HandUnclaimed(C.HandStore().active, executeCompanionList)
    local _, missing = C.HandScopeFound(C.handRunPlan.entries, C.KeepPresentCompanions(unclaimed, present), UnitName("player"), present, C.HandOwn())
    C.scopeShort = table.getn(missing)
    if C.scopeShort > 0 and not C.grinfoRefresh and (C.scopeAsks or 0) < 2 and now - (C.grinfoAskedAt or 0) >= 3 then
        C.scopeAsks = (C.scopeAsks or 0) + 1
        C.grinfoRefresh = true
        RequestCompanionInfo()
    end
    return C.scopeShort
end

-- The chat line for a batch row whose group commands found no companion.
function C.HandMissingNote(entry, slot)
    if entry and entry.kind == "legacy" then
        return C.GetLegacyWhisperName(entry) .. " (slot " .. slot .. ") is not in the group; its group commands were not sent."
    end
    local class = entry and (CLASS_LABELS[entry.class] or entry.class) or "?"
    local role = entry and (ROLE_SHORT[entry.role] or entry.role) or "?"
    return tostring(entry and entry.account) .. "'s " .. tostring(class) .. " " .. tostring(role) .. " (slot " .. slot
        .. ") is not in the server's companion list; its group commands were not sent."
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
    local handSubmitted=false
    if C.handRunPlan then
        local h=DB.handoff and DB.handoff.active
        if h and h.phase=="running" then
            local complete=status=="Execution complete. All queued commands were sent." or status=="Execution complete. All saved hires were already present."
                or status=="Execution complete. No hire commands in this group."
            h.phase=complete and "submitted" or "interrupted"
            handSubmitted=complete
            h.updated=time()
        end
        C.handRunPlan=nil
    end
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
    C.scopeAsks = nil; C.scopeCheckedAt = nil; C.scopeShort = nil; C.grinfoRefresh = nil
    SetStatus(status)
    if handSubmitted then
        local h=C.HandStore().active
        if h and h.phase=="submitted" and C.HandComplete(h,UnitName("player")) then
            h.updated=time()
            if h.kind=="GRANT" and string.lower(h.origin)~=string.lower(UnitName("player")) then
                -- A participant never advances the run; it reports its granted group to the leader.
                h.phase="done"; C.HandStatus("Granted group submitted; reporting to " .. h.origin .. ". Server results are unverified."); C.HandSendLocal()
            else
                if h.phase=="waiting" and string.lower(h.steps[h.step].actor)==string.lower(UnitName("player")) then h.phase="ready" end
                if h.phase=="waiting" then C.HandSendLocal()
                elseif h.phase=="ready" and h.kind=="GRANT" then C.HandRunStep()
                else
                    if h.phase=="done" then C.handAuthority=nil; C.handReportDeadline=nil end
                    C.HandStatus("Local commands submitted. " .. (h.phase=="done" and "Process finished; check server results." or "Next local group is ready. Click Execute."))
                end
            end
        end
    elseif C.handAuthority or C.handNotify then
        local h=C.HandStore().active
        local text=status .. " Process paused; check submitted hires before recovery."
        -- A participant's granted batch that stops on its own tells the leader, which would
        -- otherwise wait out its report deadline. Stop sends nothing more, and also discards
        -- an unsent refusal notice; it was never execution authority.
        if C.handAuthority and status~="Execution stopped." and h and h.kind=="GRANT" and h.phase=="interrupted"
            and string.lower(h.origin)~=string.lower(UnitName("player")) then C.HandRefuse(text)
        else C.HandPause(text) end
    end
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
        if C.IsHireCommand(entry) then
            executeGrinfoReady = false
            executeCompanionList = {}
            executeGrinfoRequested = false
            C.grinfoAskedAt = nil
            executeHireReadyAt = (GetTime and GetTime() or 0) + RandomHireDelay()
        end
    end
end

-- A legacy deny list goes straight to its companion, so it waits for that companion to be in
-- the group. Legacy setups need no wait here: group commands wait for every legacy companion
-- before they expand, and expansion keeps only those present.
function C.LegacyWhisperReady(entry)
    if not entry or entry.chatType ~= "WHISPER" or entry.phase ~= "legacy-custom"
        or not entry.target or entry.target == "" or SnapshotGroup()[entry.target] then C.legacyWait = nil; return true end
    local now = GetTime and GetTime() or 0
    if not C.legacyWait or C.legacyWait.entry ~= entry then C.legacyWait = {entry = entry, started = now} end
    if now - C.legacyWait.started < C.LEGACY_JOIN_WAIT then
        SetStatus("Waiting for " .. entry.target .. " to join.")
        return false
    end
    Chat(entry.target .. " is not in the group; whispering anyway.")
    C.legacyWait = nil
    return true
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
            return C.LegacyWhisperReady(nextEntry)
        end
        SetStatus("Waiting for nod from " .. (executeNodName ~= "" and executeNodName or "companion") .. ".")
        return false
    end
    if (executeHireReadyAt or 0) > 0 then
        local now = GetTime and GetTime() or 0
        local readyAt = executeHireReadyAt
        if C.IsHireCommand(nextEntry) and C.hireBefore then
            if not C.hireJoinedAt then
                for name in pairs(SnapshotGroup()) do
                    if not C.hireBefore[name] then C.hireJoinedAt = now; break end
                end
            end
            if C.hireJoinedAt then readyAt = math.min(readyAt, C.hireJoinedAt + C.HIRE_JOIN_MARGIN) end
        end
        if now < readyAt then
            SetStatus((C.IsHireCommand(nextEntry) and not C.hireJoinedAt) and "Waiting for the last companion to join." or "Pacing hires.")
            return false
        end
    end
    return C.LegacyWhisperReady(nextEntry)
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
    -- A held command waits for the companion list. A queue that starts on one (a commands
    -- step, or every hire already present) sends it once, after the list expands.
    if IsHeldPhase(entry.phase) and not executeGrinfoExpanded then return false end
    if not ResolveRoleDenyTarget(entry) then return false end
    if entry.kind == "normal" then executePartyBefore = SnapshotGroup() end
    -- Who is in the group before a hire goes out, so its companion's join is seen even
    -- when the roster updates at once.
    if C.IsHireCommand(entry) then C.hireBefore = SnapshotGroup(); C.hireJoinedAt = nil end
    SendQueueEntry(entry)
    NoteCommandSent(entry)
    return true
end

local function ExecuteQueue()
    if executing then SetStatus("Queue is already running."); return end
    local plan=C.handRunPlan or EnsureDB()
    local overLimit = C.OverLimitHireCharacter(plan.entries, 4)
    if overLimit then
        C.whisperRun = nil
        SetStatus(overLimit .. " has more than four companions in this hiring plan. Remove extras before executing.")
        return
    end
    if C.whisperRun then executeQueue = C.BuildWhisperQueue(plan) else executeQueue = C.HandQueue(plan) end
    local denyError = C.DenyQueueError(executeQueue)
    if denyError then C.whisperRun = nil; SetStatus(denyError); Chat(denyError); return end
    if table.getn(executeQueue) == 0 then
        C.whisperRun = nil
        -- A frozen run group of board-only rows (e.g. the current player) needs no command;
        -- it completes and advances the run without claiming any server result.
        if C.handRunPlan then FinishExecute("Execution complete. No hire commands in this group."); return end
        SetStatus("Queue is empty."); return
    end
    executing = true; executeIndex = 1; executeElapsed = 0; executeFrames = 0; executeHireReadyAt = 0; executeWaitingNod = false; executeNodReady = false; executeNodName = ""; executeNodStarted = 0; executeWhisperGap = 0; executeWaitElapsed = 0; executeWaitStarted = 0; executePartyBefore = nil; executeCompanions = {}; executeBaseline = SnapshotGroup(); executeCompanionList = {}; executeGrinfoRequested = false; executeGrinfoReady = false; executeGrinfoExpanded = false; C.executePreflightStarted = 0; C.executePreflightComplete = false
    if math.randomseed then math.randomseed((GetTime and GetTime() or 0) * 1000) end
    local needsPreflight = false
    local hasHire = false
    local hasNormalHire = false
    for qi = 1, table.getn(executeQueue) do
        if executeQueue[qi].kind == "normal" or executeQueue[qi].kind == "hire" then hasHire = true end
        if executeQueue[qi].kind == "normal" then hasNormalHire = true end
    end
    if hasNormalHire and C.HasOtherGroupMembers(executeBaseline, UnitName and UnitName("player") or "") then
        needsPreflight = true
    end
    if (needsPreflight or not hasHire) and C.InfoCoversGroup(executeBaseline, UnitName and UnitName("player") or "", C.latestCompanionList) then
        executeCompanionList = C.latestCompanionList
        executeGrinfoReady = true
    end
    if needsPreflight then
        if not executeGrinfoReady then
            C.executePreflightStarted = GetTime and GetTime() or 0
            C.grinfoAskedAt = nil
            RequestCompanionInfo()
            SetStatus("Reading the current companion list before hiring.")
        else
            SetStatus("Checking the current companion list before hiring.")
        end
    else
        C.executePreflightComplete = true
        SendCurrentQueueEntry()
        if C.whisperRun then SetStatus("Whispering 1/" .. table.getn(executeQueue) .. ".")
        else SetStatus("Executing 1/" .. table.getn(executeQueue) .. ". Each hire waits for the last companion to join.") end
    end
    if not executeFrame then executeFrame = CreateFrame("Frame") end
    executeFrame:SetScript("OnUpdate", function()
        if not executing then return end
        if not C.executePreflightComplete then
            if executeGrinfoReady then
                -- In a run, companions hired by its earlier steps are not already present here.
                local info = executeCompanionList
                if C.handRunPlan then info = C.HandUnclaimed(C.HandStore().active, info) end
                local filtered, skipped = C.FilterExistingNormalHires(executeQueue, (C.handRunPlan or EnsureDB()).entries, info)
                executeQueue = filtered
                C.executePreflightComplete = true
                executeGrinfoRequested = false
                executeGrinfoReady = false
                executeCompanionList = {}
                C.grinfoAskedAt = nil
                if skipped > 0 then Chat("Skipped " .. skipped .. " normal hire(s) already present in the group.") end
                if table.getn(executeQueue) == 0 then
                    FinishExecute("Execution complete. All saved hires were already present.")
                    return
                end
                SendCurrentQueueEntry()
                if C.whisperRun then SetStatus("Whispering 1/" .. table.getn(executeQueue) .. ".")
                else SetStatus("Executing 1/" .. table.getn(executeQueue) .. ". Each hire waits for the last companion to join.") end
                return
            end
            local preflightWaited = 0
            if GetTime then preflightWaited = GetTime() - (C.executePreflightStarted or 0) end
            if preflightWaited >= 8 then
                FinishExecute("Could not read the current companion list. No hires were sent.")
                return
            end
            SetStatus("Waiting for the current companion list before hiring.")
            return
        end
        local nextIndex = executeIndex + 1
        local nextEntry = executeQueue[nextIndex]
        local currentEntry = executeQueue[executeIndex]
        if (nextEntry and IsHeldPhase(nextEntry.phase)) or (currentEntry and IsHeldPhase(currentEntry.phase) and not executeGrinfoExpanded) then
            if not executeGrinfoReady then
                if not executeGrinfoRequested then
                    -- Wait out the post-hire window first: a GRINFO answer that
                    -- lands while the last .z addinvite is still processing lists
                    -- companions as of before that hire, so the newest companion
                    -- would be missing from every expanded target list.
                    -- Evaluate BEFORE committing executeGrinfoRequested so a pending
                    -- hire cannot leave the flag set with executeWaitStarted stale.
                    local hirePending = (executeHireReadyAt or 0) > 0 and GetTime and (GetTime() < executeHireReadyAt)
                    if hirePending then
                        SetStatus("Finishing the current hire before asking for names.")
                        return
                    end
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
                if C.handRunPlan then FinishExecute("Handoff stopped: companion discovery timed out. Check sent hires before retrying."); return end
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
                -- The newest hire can still be missing from the party roster when
                -- the GRINFO reply lands; expanding then drops exactly that
                -- companion (the N-1 skip). Wait until every name the server sent
                -- is visible in the group, or until a bounded grace period ends.
                -- Waiting ticks never move the queue: the advance below happens once.
                local pendingNames = 0
                local present = SnapshotGroup()
                for ci = 1, table.getn(executeCompanionList) do
                    local cname = executeCompanionList[ci] and executeCompanionList[ci].name
                    if cname and cname ~= "" and not present[cname] then pendingNames = pendingNames + 1 end
                end
                -- Legacy companions are not in the server's list; wait for them by name too.
                pendingNames = pendingNames + C.MissingLegacyNames((C.handRunPlan or EnsureDB()).entries, present)
                -- In a run, also wait while the list cannot place one of the batch's own companions.
                pendingNames = math.max(pendingNames, C.HandScopeShort())
                if pendingNames > 0 and GetTime and (GetTime() - (executeWaitStarted or 0)) < 12 then
                    SetStatus("Waiting for " .. pendingNames .. " companion(s) to appear in the group.")
                    return
                end
                if executeIndex > 1 or not IsHeldPhase(currentEntry.phase) then
                    -- The current entry was already sent (normal flow: we are
                    -- parked on the last sent index, expansion replaces what is ahead).
                    -- A lone first hire was sent too; only a held first entry was not.
                    if not ReadyForNext(nextEntry) then return end
                    executeIndex = nextIndex
                end
                ExpandPendingGroupDenies()
                local denyError = C.DenyQueueError(executeQueue)
                if denyError then Chat(denyError); FinishExecute(denyError); return end
                executeGrinfoExpanded = true
                executeWaitingNod = false
                if currentEntry and IsHeldPhase(currentEntry.phase) then
                    -- Entry 1 was never sent (queue starts on a held phase);
                    -- after expansion it stays at executeIndex and goes out now.
                    SendCurrentQueueEntry()
                    SetStatus("Executing " .. executeIndex .. "/" .. table.getn(executeQueue) .. ".")
                    return
                end
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
    if C.peerPrompt and C.peerPrompt:IsShown() then return true end
    if C.peerPanel and C.peerPanel:IsShown() then return true end
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
    if C.peerPrompt and C.peerPrompt:IsShown() then C.peerPrompt:Hide(); return true end
    if C.licenseView and C.licenseView:IsShown() then C.licenseView:Hide(); return true end
    if C.peerPanel and C.peerPanel:IsShown() then C.peerPanel:Hide(); return true end
    if choiceMenu and choiceMenu:IsShown() then CloseChoiceMenu(); return true end
    if abilityMenu and abilityMenu:IsShown() then abilityMenu:Hide(); return true end
    if legacyNameMenu and legacyNameMenu:IsShown() then HideLegacyNameSuggestions(); return true end
    if contextFrame and contextFrame:IsShown() then CloseContext(); return true end
    if namePrompt and namePrompt:IsShown() then namePrompt:Hide(); return true end
    if C.capturePrompt and C.capturePrompt:IsShown() then C.capturePrompt:Hide(); return true end
    if C.importFrame and C.importFrame:IsShown() then C.importFrame:Hide(); return true end
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
        if sort then mainFrame.titleText:SetText("Shir's Raid Builder " .. C.VERSION .. " - Sort")
        else mainFrame.titleText:SetText("Shir's Raid Builder " .. C.VERSION) end
    end
    if mainFrame.accountContent then
        if sort then mainFrame.accountContent:Hide() else mainFrame.accountContent:Show() end
        C.AccountScroll(mainFrame.accountScroll:GetVerticalScroll())
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

-- Account link adapter. Remote traffic cannot reach local action queues.
function C.PeerRestoreConfig()
    if C.peerConfigLoaded then return end
    EnsureDB(); C.peerConfigLoaded = true
    -- The first link panel stored only a local endpoint, not mutual consent.
    -- Keep that exact version-1 endpoint as a draft; never promote it to approval.
    local old=DB.peerConfig
    if type(old)=="table" and old.version==1 and old.confirmed==true
        and old.you==string.lower(UnitName("player") or "") and old.realm==GetRealmName() then
        local draft=C.PeerNew(UnitName("player"),old.peer,old.realm)
        if draft then C.peerDraft=draft.peerLabel end
    end
    DB.peerConfig=nil
    local clean, count = {}, 0
    if type(DB.peerLinks) == "table" then
        for key, p in pairs(DB.peerLinks) do
            if count < 128 and type(p) == "table" and p.version == 2 and type(p.scope) == "string" then
                local you = p.scope == "*" and UnitName("player") or p.scope
                local expected = C.LinkKey(you, p.peer, p.realm, p.scope == "*")
                if expected and expected == key then
                    local labels={}
                    if type(p.bindings) == "table" then
                        local n=0
                        for name,label in pairs(p.bindings) do
                            local bound=C.PeerNew(label,p.peer,p.realm)
                            if n < 128 and bound and bound.you == name and (p.scope == "*" or p.scope == name) then
                                labels[name]=label; n=n+1
                            end
                        end
                    end
                    local label=C.PeerNew(you,p.peerLabel,p.realm)
                    clean[key] = {version=2, realm=p.realm, peer=p.peer, peerLabel=label and label.peer == p.peer and p.peerLabel or p.peer,
                        scope=p.scope, bindings=labels, revoked=p.revoked == true or nil}; count=count+1
                end
            end
        end
    end
    DB.peerLinks = clean
    C.LicenseRestoreSaved()
    C.RaidRestoreSaved()
    RefreshAccountPanel()
end

function C.LicenseRestoreSaved()
    C.remoteLicenses={}
    if type(DB.peerSnapshots)~="table" then DB.peerSnapshots={} end
    local saved=DB.peerSnapshots
    local count=0
    for key,r in pairs(saved) do
        local copy=C.AccountSavedCopy(r,UnitName("player"),GetRealmName(),DB.peerLinks)
            or C.LicenseSavedCopy(r,UnitName("player"),GetRealmName(),DB.peerLinks)
        if copy and key==copy.realm .. ";" .. copy.source and count<128 then
            C.remoteLicenses[key]=copy; count=count+1
        end
    end
end

function C.PeerVisibleEndpoint()
    local f=C.peerPanel
    if f and type(GetRealmName) == "function" and type(UnitName) == "function" then
        return C.PeerNew(UnitName("player"), f.nameInput:GetText(), GetRealmName())
    end
    return C.peerState
end

function C.PeerAbort(reason)
    if C.peerState then C.peerState.remoteLicense=nil; C.peerState.licenseWait=nil; C.peerState.licenseServe=nil end
    C.PeerClear(C.peerState, reason)
    C.peerPending=nil
    C.licenseNotice="Unavailable: " .. (reason or "exchange cancelled")
    if C.peerState then C.peerState.licenseAfterLink=nil end
    if C.peerPrompt and C.promptSession==C.activeSession then C.promptSession=nil; C.peerPrompt:Hide() end
    RefreshAccountPanel()
    C.PeerRefresh()
end

function C.PeerRefresh()
    C.SyncStore()
    local f=C.peerPanel
    if not f then return end
    local endpoint=C.PeerVisibleEndpoint()
    local session=endpoint and C.peerSessions and C.peerSessions[endpoint.realm .. ";" .. endpoint.peer]
    local s=session and session.state
    local text="Enter a known character on this realm, then Pair."
    if endpoint then
        text="Local: " .. endpoint.youLabel .. " | Remote: " .. endpoint.peerLabel .. " / " .. endpoint.realm .. " | Protocol 2"
        local own=DB.peerLinks[C.LinkKey(endpoint.you,endpoint.peer,endpoint.realm,false)]
        local all=DB.peerLinks[C.LinkKey(endpoint.you,endpoint.peer,endpoint.realm,true)]
        text=text .. "\nSaved approval: " .. (own and own.revoked and "unlinked for this character" or (all and "all local characters" or (own and "this local character" or "none")))
    end
    if s then
        local labels={waiting="Waiting for approval",approval="Approval needed",confirming="Confirming link",["confirm-sent"]="Confirming link",linked="Linked (data not synchronized)",disabled="Not connected"}
        if s.remoteLicense then labels.linked="Linked (advisory account licenses received)" end
        text=text .. "\n" .. s.peer .. ": " .. (labels[s.phase] or "Not connected")
        if s.reason then text=text .. "\n" .. s.reason end
    end
    text=text .. "\nAccount details are peer claims, not ownership proof."
    local r=endpoint and C.remoteLicenses and C.remoteLicenses[endpoint.realm .. ";" .. endpoint.peer]
    if r then
        text=text .. "\nPeer-claimed (read-only): " .. r.source .. " / " .. r.realm
        text=text .. "\n" .. table.getn(r.entries) .. " character(s); see the sidebar."
        text=text .. "\nSaved snapshot: " .. C.LicenseAgeLabel(r,time()) .. ". Not live."
    else text=text .. "\nFreshness: unavailable. No saved peer license reply." end
    text=text .. "\nSidebar rows are view-only. Linked hires can spend gold after Execute\non the initiating account, only for that plan."
    if s and s.licenseWait then text=text .. "\nWaiting for a fresh advisory license reply."
    elseif s and s.licenseAfterLink then text=text .. "\nWaiting for a fresh link before reading licenses."
    elseif session and session.notice then text=text .. "\n" .. session.notice end
    f.status:SetText(text)
    if C.licenseView then C.licenseView.status:SetText(text) end
    local busy=s and s.phase ~= "disabled" and s.phase ~= "linked"
    if endpoint and not busy and not (session and session.pending) then f.pairButton:Enable() else f.pairButton:Disable() end
    if f.licenseButton then
        f.licenseButton:Enable() -- Always allow opening the result/unavailable view.
    end
end

function C.PeerContextOK()
    if (executing and not (C.handAuthority and C.handRunPlan)) or (C.sortFrame and C.sortFrame.busy) then return false end
    if type(time) ~= "function" or type(GetTime) ~= "function" or type(GetRealmName) ~= "function" or type(UnitName) ~= "function" then return false end
    local s=C.peerState
    return not s or (s.you == string.lower(UnitName("player") or "") and s.realm == GetRealmName())
end

function C.LinkNonce()
    C.peerSequence=(C.peerSequence or 0)+1
    return string.format("%.0f%.0f%04d%d",time(),GetTime()*1000,math.random(1000,9999),C.peerSequence)
end

function C.PeerQueuePacket(packet)
    if type(packet) ~= "string" or string.len(packet)>240 then return end
    if C.peerPending then C.PeerAbort("Exchange interrupted; Pair again"); return end
    C.peerPending=packet; C.peerSendAt=math.max(GetTime()+1,C.peerNextSend or 0)
end

function C.LinkPair()
    local s=C.PeerVisibleEndpoint()
    if not s then return end
    if not C.SyncSelect(s,true) or not C.PeerContextOK() or C.peerPending then return end
    if C.peerState and C.peerState.phase ~= "disabled" and C.peerState.phase ~= "linked" then return end
    C.PeerAbort("New invitation")
    C.licenseNotice=nil
    C.peerState=s; s.remember=C.peerPanel.rememberCheck:GetChecked() and true or false
    s.invitation=C.LinkInvite(s,C.LinkNonce(),time(),GetTime())
    C.PeerQueuePacket(s.invitation)
    C.peerPanel.nameInput:ClearFocus(); C.PeerRefresh()
end

function C.LinkForgetVisible(account)
    local s=C.PeerVisibleEndpoint()
    if not s then return end
    C.SyncSelect(s,false)
    C.LinkForget(DB.peerLinks,s.you,s.peer,s.realm,account)
    if account and DB.peerSnapshots then DB.peerSnapshots[s.realm .. ";" .. s.peer]=nil end
    if account and DB.peerRaidSnapshots then DB.peerRaidSnapshots[s.realm .. ";" .. s.peer]=nil end
    C.LicenseRestoreSaved()
    C.RaidRestoreSaved()
    C.PeerAbort("Approval removed locally. The other account manages its own approval.")
end

function C.LinkApprove()
    C.SyncActivate(C.promptSession)
    local s=C.peerState
    if not s or not C.PeerContextOK() or not C.peerPrompt or not C.peerPrompt:IsShown() or s.phase ~= "approval" then C.PeerAbort("Approval cancelled"); return end
    s.remember=C.peerPrompt.rememberCheck:GetChecked() and true or false
    C.PeerQueuePacket(C.LinkAccept(s,time(),GetTime()))
    C.peerPrompt:Hide(); C.PeerRefresh()
end

function C.LinkDecline()
    C.SyncActivate(C.promptSession)
    local s=C.peerState
    if not s or not C.PeerContextOK() then C.PeerAbort("Approval cancelled"); return end
    local packet=C.LinkReject(s,time(),GetTime())
    C.peerPrompt:Hide(); C.PeerQueuePacket(packet); C.PeerRefresh()
end

function C.LinkRaisePrompt()
    local f=C.peerPrompt
    local level=100
    if type(EnumerateFrames)=="function" then
        local other=EnumerateFrames()
        while other do
            local parent=other
            while parent and parent~=f do parent=parent:GetParent() end
            if not parent and other:IsShown() and other:GetFrameStrata()=="FULLSCREEN_DIALOG" then level=math.max(level,other:GetFrameLevel()+10) end
            other=EnumerateFrames(other)
        end
    end
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(level); f:SetToplevel(true); f:EnableMouse(true); f:Raise()
    -- Keep existing controls above the raised opaque parent on the legacy client.
    for _,control in ipairs({f.dragBar,f.rememberCheck,f.acceptButton,f.rejectButton}) do
        control:SetFrameStrata("FULLSCREEN_DIALOG"); control:SetFrameLevel(f:GetFrameLevel()+1)
        control:EnableMouse(true); control:Show()
    end
end

function C.LinkShowPrompt()
    if not C.peerPrompt then
        local f=CreateFrame("Frame","ShirsRaidBuilderLinkApproval",UIParent); C.peerPrompt=f
        f:SetWidth(550); f:SetHeight(220); f:SetPoint("CENTER",UIParent,"CENTER",0,80); StylePanelFrame(f)
        f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
        f:SetScript("OnShow",C.LinkRaisePrompt)
        f.title=MakeCaption(f,"",22,-20); f.title:SetWidth(506); f.title:SetHeight(52); f.title:SetJustifyH("LEFT")
        f.rememberCheck=CreateFrame("CheckButton",nil,f,"UICheckButtonTemplate")
        f.rememberCheck:SetWidth(20); f.rememberCheck:SetHeight(20); f.rememberCheck:SetPoint("TOPLEFT",f,"TOPLEFT",22,-78)
        MakeCaption(f,"Remember this link for all characters on this account",48,-82)
        local help=MakeCaption(f,"Unchecked: approval covers only this local character.\nAccept lets the peer hire and spend gold for its plan after Execute\non the initiating account. Licenses are peer claims, not proof.",22,-110)
        help:SetWidth(506); help:SetHeight(42); help:SetJustifyH("LEFT")
        f.acceptButton=MakeButton(f,"Accept",110,22,18,C.LinkApprove,true)
        f.rejectButton=MakeButton(f,"Reject",110,144,18,C.LinkDecline,true)
        f:SetScript("OnHide",function()
            local session=C.promptSession; C.promptSession=nil
            if session and session.state and session.state.phase=="approval" then
                C.SyncActivate(session); C.PeerAbort("Approval cancelled locally")
            end
        end)
    end
    C.peerPrompt.title:SetText(C.peerState.peerLabel .. " wants to synchronize with this character.\nRealm: " .. C.peerState.realm)
    C.peerPrompt.rememberCheck:SetChecked(nil); C.peerPrompt:Show(); C.LinkRaisePrompt()
end

function C.LicenseRefreshRemote(background)
    local selected=C.PeerVisibleEndpoint()
    if selected then C.SyncSelect(selected,true) end
    if not C.licenseView then
        local f=CreateFrame("Frame","ShirsRaidBuilderLicenseView",UIParent); C.licenseView=f
        f:SetWidth(570); f:SetHeight(350); f:SetPoint("CENTER",UIParent,"CENTER",0,0); StylePanelFrame(f)
        f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
        MakeCaption(f,"Advisory peer licenses (read-only)",22,-14)
        f.status=MakeCaption(f,"",22,-44); f.status:SetWidth(526); f.status:SetHeight(248)
        f.status:SetJustifyH("LEFT"); f.status:SetJustifyV("TOP")
        f.closeButton=MakeButton(f,"Close",100,22,18,function() f:Hide() end,true)
    end
    local view=C.licenseView
    if not background then
        view:SetFrameLevel(C.peerPanel:GetFrameLevel()+10); view:Show(); view:Raise()
    end
    for _,control in ipairs({view.closeButton,view.dragBar}) do
        control:SetFrameStrata("FULLSCREEN_DIALOG"); control:SetFrameLevel(view:GetFrameLevel()+1)
    end
    C.licenseNotice="Saved data only. Use Refresh Synchronization to update."
    C.PeerRefresh()
end

function C.LicenseObserveOne(records)
    local s=C.peerState
    local w=s and s.licenseServe
    if not w or not w.sent or not C.PeerContextOK() or not C.PeerAlive(s,time(),GetTime()) then return end
    if GetTime()<w.sent or GetTime()-w.sent>=10 then s.licenseServe=nil; return end
    if type(records)=="table" then w.records=records end
end

function C.LicenseEvent(p)
    local s=C.peerState
    if not C.LicenseBound(s,p,arg2,time(),GetTime()) then return end
    if p.kind=="DATA" then
        if C.LicenseReceive(s,arg1,arg2,time(),GetTime()) then
            C.licenseNotice=nil; C.remoteLicenses=C.remoteLicenses or {}
            local copy=C.LicenseSavedCopy(s.remoteLicense,s.you,s.realm,DB.peerLinks)
            if copy then
                DB.peerSnapshots=DB.peerSnapshots or {}
                DB.peerSnapshots[s.realm .. ";" .. s.peer]=copy
                C.remoteLicenses[s.realm .. ";" .. s.peer]=copy
            end
            RefreshAccountPanel()
        end
        C.PeerRefresh(); return
    end
    s.licenseSeen=s.licenseSeen or {}
    if s.licenseSeen[p.nonce] or s.licenseServe or s.licenseOut then return end
    if s.licenseNext and GetTime()<s.licenseNext then return end
    local n=0; for _ in pairs(s.licenseSeen) do n=n+1 end
    if n>=8 then return end
    s.licenseSeen[p.nonce]=true; s.licenseNext=GetTime()+10
    s.licenseServe={nonce=p.nonce}
    -- One reciprocal read publishes the initiating account too, without a loop.
    if p.kind=="GET" and not s.licenseWait and not s.licenseAfterLink then s.licenseAfterLink="reply" end
    s.raidServe={nonce=p.nonce,started=GetTime()}
    C.RaidRequestLocal()
    -- Fresh local read, not a SavedVariables cache; no server ownership proof.
    EnsureInviteListener()
    if type(SendChatMessage)=="function" then
        s.licenseServe.sent=GetTime()
        if not pcall(SendChatMessage,".z addinvite list","SAY") then s.licenseServe=nil end
    end
end

function C.PeerTickOne()
    -- Refresh labels once per second; never allocate sidebar rows per frame.
    if not C.peerRefreshAt or GetTime()>=C.peerRefreshAt then
        C.peerRefreshAt=GetTime()+1; C.PeerRefresh()
        for _,label in ipairs(C.licenseAgeLabels or {}) do
            label.text:SetText(C.LicenseAgeLabel(label.snapshot,time()))
        end
    end
    local s=C.peerState
    if not s then return end
    if s.phase=="disabled" and s.licenseAfterLink then
        s.licenseAfterLink=nil; C.licenseNotice="Unavailable: " .. (s.reason or "link not established")
    end
    if s.phase=="disabled" and not C.peerPending then return end
    if s.licenseWait and (GetTime()<s.licenseWait.started or GetTime()-s.licenseWait.started>=45) then
        s.licenseWait=nil; C.licenseNotice="Unavailable: no validated license reply arrived. Try again."
    end
    if s.licenseServe and s.licenseServe.records and (C.raidReadReady or GetTime()-s.licenseServe.sent>=(C.raidAwaitCCP and 9 or 2)) then
        C.RaidReadLocal()
        local rows=C.AccountReadLocal(s.licenseServe.records)
        s.licenseOut=C.AccountPackets(s,s.licenseServe.nonce,DB.syncAccountId,rows,time())
        s.licenseServe=nil
    end
    if s.licenseServe and s.licenseServe.sent and GetTime()-s.licenseServe.sent>=10 then s.licenseServe=nil end
    if s.raidWait and (GetTime()<s.raidWait.started or GetTime()-s.raidWait.started>=45) then s.raidWait=nil end
    if s.raidServe and (C.raidReadReady or GetTime()-s.raidServe.started>=(C.raidAwaitCCP and 10 or 2)) then
        s.raidOut=C.RaidPackets(s,s.raidServe.nonce,C.RaidReadLocal()); s.raidServe=nil
    end
    if not C.PeerContextOK() then C.PeerAbort("Builder closed or local execution active"); return end
    if s.phase ~= "disabled" and not C.PeerAlive(s,time(),GetTime()) then
        C.peerPending=nil
        if C.peerPrompt and C.promptSession==C.activeSession then C.promptSession=nil; C.peerPrompt:Hide() end
        s.reason="Timed out. Receiver may be offline, have SRB closed, or be unable to receive whispers."
        s.licenseAfterLink=nil; s.licenseWait=nil; s.remoteLicense=nil
        C.licenseNotice="Unavailable: " .. s.reason
        C.PeerRefresh(); return
    end
    if s.handOut and not C.peerPending then
        if not C.PlanAuthorized(s,DB.peerLinks,time(),GetTime()) then C.PeerAbort("Handoff transfer cancelled"); return end
        local packet=table.remove(s.handOut,1)
        if table.getn(s.handOut)==0 then s.handOut=nil end
        if packet then C.PeerQueuePacket(packet); C.peerSendAt=math.max(GetTime(),C.peerNextSend or 0) end
    end
    if s.planOut and not C.peerPending then
        if not C.PlanAuthorized(s,DB.peerLinks,time(),GetTime()) then C.PeerAbort("Plan share cancelled"); return end
        local packet=table.remove(s.planOut,1)
        if table.getn(s.planOut)==0 then s.planOut=nil end
        if packet then C.PeerQueuePacket(packet); C.peerSendAt=math.max(GetTime(),C.peerNextSend or 0) end
    end
    if s.licenseOut and not C.peerPending then
        local packet=table.remove(s.licenseOut,1)
        if table.getn(s.licenseOut)==0 then s.licenseOut=nil end
        if packet then C.PeerQueuePacket(packet); C.peerSendAt=math.max(GetTime(),C.peerNextSend or 0) end
    end
    if s.raidOut and not s.licenseOut and not C.peerPending then
        local packet=table.remove(s.raidOut,1)
        if table.getn(s.raidOut)==0 then s.raidOut=nil end
        if packet then C.PeerQueuePacket(packet); C.peerSendAt=math.max(GetTime(),C.peerNextSend or 0) end
    end
    if C.peerPending and GetTime() >= C.peerSendAt and GetTime()>=(C.peerNextSend or 0) then
        local packet=C.peerPending; C.peerPending=nil; C.peerNextSend=GetTime()+0.25
        local parsed=C.LinkParse(packet)
        local hand=C.HandParse(packet)
        local plan=C.PlanParse(packet) or hand
        if plan and not C.PlanAuthorized(s,DB.peerLinks,time(),GetTime()) then C.PeerAbort("Plan share cancelled"); return end
        local license=C.LicenseParse(packet) or C.RaidParse(packet) or C.AccountParse(packet) or plan
        if not (parsed and parsed.expires>time()) and not (license and s.phase=="linked" and C.PeerAlive(s,time(),GetTime())) then C.PeerAbort("Invitation expired; Pair again"); return end
        local ok=false
        if type(SendChatMessage) == "function" then ok=pcall(SendChatMessage, packet, "WHISPER", nil, s.peer) end
        if not ok then C.PeerAbort("Whisper submission failed; Pair again"); return end
        if plan and s.planProgress and s.planProgress.nonce==plan.nonce then s.planProgress.sent=s.planProgress.sent+1 end
        if hand and s.handProgress and s.handProgress.nonce==hand.nonce then s.handProgress.sent=s.handProgress.sent+1 end
    end
    if s.phase=="linked" and s.licenseAfterLink and not C.peerPending then
        local reply=s.licenseAfterLink=="reply"
        s.licenseAfterLink=nil
        C.PeerQueuePacket(C.LicenseRequest(s,C.LinkNonce(),GetTime(),reply))
    end
end

function C.PeerEventOne()
    if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGOUT" then
        C.PeerAbort("Context changed; use Read peer licenses to try again"); return
    end
    if event ~= "CHAT_MSG_WHISPER" or not C.PeerContextOK() then return end
    local license=C.LicenseParse(arg1)
    if license then C.LicenseEvent(license); return end
    local p=C.LinkParse(arg1)
    if not p then return end
    if p.kind == "INVITE" then
        local now=GetTime()
        local s=C.LinkIncoming(arg1,arg2,UnitName("player"),GetRealmName(),C.LinkNonce(),time(),now)
        if not s then return end
        -- Simultaneous invitations choose one initiator, the name that sorts first. An own
        -- invitation still unsent, or made 10 s ago or more, did not cross this one: it went
        -- out while the other side was offline, so this side takes the fresh one instead. A
        -- younger one is sent once more; a copy that crossed is ignored as seen.
        -- Unknown peers still take the explicit approval branch below.
        local w=C.peerState
        if w and w.phase=="waiting" and w.peer==p.sender then
            if p.sender<p.target or C.peerPending or now-w.started>=10 then
                C.PeerClear(w,"Incoming link invitation"); C.peerPending=nil
            elseif w.resent~=w.a then
                w.resent=w.a; w.invitation=C.LinkPacket(w,"INVITE"); C.PeerQueuePacket(w.invitation)
            end
        end
        if C.peerPending or (C.peerState and C.peerState.phase ~= "disabled" and C.peerState.phase ~= "linked") then return end
        if C.activeSession.nextInvite and now < C.activeSession.nextInvite then return end
        C.linkSeen=C.linkSeen or {}
        for key,expiry in pairs(C.linkSeen) do if expiry <= time() then C.linkSeen[key]=nil end end
        local key=s.peer .. ";" .. s.a
        if C.linkSeen[key] then return end
        local count=0; for _ in pairs(C.linkSeen) do count=count+1 end
        if count >= 128 then return end
        C.linkSeen[key]=s.expires; C.activeSession.nextInvite=now+5; C.peerState=s
        if C.LinkKnown(DB.peerLinks,s.you,s.peer,s.realm) then
            s.existing=true
            local all=DB.peerLinks[C.LinkKey(s.you,s.peer,s.realm,true)]
            s.remember=type(all) == "table" and all.revoked ~= true
            C.PeerQueuePacket(C.LinkAccept(s,time(),now))
        else
            if not mainFrame or not mainFrame:IsShown() then C.PeerClear(s,"Open SRB to approve a new link"); return end
            -- Each pending invitation stays in its own session. Prompts are serialized.
            C.activeSession.state=s
        end
        C.PeerRefresh(); return
    end
    local s=C.peerState
    if not s then return end
    local previous=s.phase
    local invitation=s.invitation
    local response=C.LinkReceive(s,arg1,arg2,time(),GetTime())
    if response and previous == "waiting" then
        if C.peerPending == invitation then C.peerPending=nil end
        s.invitation=nil; s.retryAt=nil; s.retries=nil
    end
    if type(response) == "string" then C.PeerQueuePacket(response) end
    if response and s.phase == "linked" and previous ~= "linked" then
        C.LinkSave(DB.peerLinks,s,s.remember)
        C.peerAutoAttempted=C.peerAutoAttempted or {}; C.peerAutoAttempted[s.realm .. ";" .. s.peer]=true
    end
    C.PeerRefresh()
end

function C.PeerOnBuilderOpen(opened)
    C.PeerRestoreConfig()
    if not C.peerDriver then
        C.peerDriver=CreateFrame("Frame")
        for _,name in ipairs({"CHAT_MSG_WHISPER","CHAT_MSG_ADDON","UPDATE_INSTANCE_INFO","PLAYER_LEAVING_WORLD","PLAYER_LOGOUT"}) do C.peerDriver:RegisterEvent(name) end
        C.peerDriver:SetScript("OnEvent",C.PeerEvent); C.peerDriver:SetScript("OnUpdate",C.PeerTick)
    end
end

function C.PeerLogin()
    C.PeerOnBuilderOpen()
    if C.peerLoginDone then return end
    C.peerLoginDone=true
    C.SyncRefreshAll()
end

-- Runtime sessions are never serialized. Each endpoint owns its queue and waits.
function C.SyncStore()
    local session=C.activeSession
    if not session then return end
    session.state=C.peerState; session.pending=C.peerPending
    session.sendAt=C.peerSendAt; session.notice=C.licenseNotice
end

function C.SyncActivate(session)
    C.SyncStore(); C.activeSession=session
    C.peerState=session and session.state; C.peerPending=session and session.pending
    C.peerSendAt=session and session.sendAt; C.licenseNotice=session and session.notice
end

function C.SyncSelect(endpoint,create)
    C.peerSessions=C.peerSessions or {}
    local key=endpoint.realm .. ";" .. endpoint.peer
    local session=C.peerSessions[key]
    if not session and create then
        local n=0; for _ in pairs(C.peerSessions) do n=n+1 end
        if n>=128 then return nil end
        session={state=endpoint}; C.peerSessions[key]=session
    end
    C.SyncActivate(session)
    return session
end

-- Called several times a frame; the sorted list is rebuilt only when sessions change.
function C.SyncKeys()
    C.SyncStore()
    local sessions,n=C.peerSessions or {},0
    for _ in pairs(sessions) do n=n+1 end
    if not C.syncKeys or C.syncKeysOf~=sessions or table.getn(C.syncKeys)~=n then
        local keys={}; for key in pairs(sessions) do table.insert(keys,key) end
        table.sort(keys); C.syncKeys=keys; C.syncKeysOf=sessions
    end
    return C.syncKeys
end

function C.PeerAbortAll(reason)
    for _,key in ipairs(C.SyncKeys()) do
        C.SyncActivate(C.peerSessions[key]); C.PeerAbort(reason)
    end
    C.SyncStore()
end

-- Closing the builder cancels handshakes and unsent local work, but keeps
-- established links so a closed builder can still receive a plan offer.
-- Receipt and approval re-check PlanAuthorized independently.
function C.PeerBuilderClosed(reason)
    for _,key in ipairs(C.SyncKeys()) do
        local session=C.peerSessions[key]; local s=session.state
        C.SyncActivate(session)
        if s.phase=="linked" then
            C.peerPending=nil
            s.planOut=nil; s.licenseOut=nil; s.raidOut=nil; s.licenseAfterLink=nil
            s.licenseWait=nil; s.licenseServe=nil; s.raidWait=nil; s.raidServe=nil
            if C.peerPrompt and C.promptSession==session then C.promptSession=nil; C.peerPrompt:Hide() end
        else C.PeerAbort(reason) end
    end
    C.SyncStore()
end

function C.SyncRefreshAll()
    C.PeerRestoreConfig()
    C.RaidRequestLocal()
    EnsureInviteListener()
    if not C.accountReadAt or GetTime()-C.accountReadAt>=2 then
        C.accountReadAt=GetTime()
        if type(SendChatMessage)=="function" then pcall(SendChatMessage,".z addinvite list","SAY") end
    end
    C.peerAutoAttempted={}
    C.PeerAutoNext()
    C.PeerRefresh()
end

function C.PeerAutoNext()
    if not C.peerAutoAttempted or not C.PeerContextOK() then return end
    local names={}
    for _,p in pairs(DB.peerLinks or {}) do
        if p.realm==GetRealmName() and C.LinkKnown(DB.peerLinks,UnitName("player"),p.peer,p.realm) then names[p.peer]=p end
    end
    local sorted={}; for name in pairs(names) do table.insert(sorted,name) end; table.sort(sorted)
    for _,name in ipairs(sorted) do
        local p=names[name]; local key=p.realm .. ";" .. p.peer
        if not C.peerAutoAttempted[key] then
            C.peerAutoAttempted[key]=true
            local endpoint=C.PeerNew(UnitName("player"),p.peerLabel or p.peer,p.realm)
            local session=endpoint and C.SyncSelect(endpoint,true)
            local s=C.peerState
            if session and not C.peerPending and not s.licenseWait and not s.raidWait
                and not s.licenseAfterLink and not s.licenseOut and not s.raidOut then
                if s.phase=="linked" and C.PeerAlive(s,time(),GetTime()) then
                    C.PeerQueuePacket(C.LicenseRequest(s,C.LinkNonce(),GetTime()))
                elseif s.phase=="disabled" then
                    s.remember=p.scope=="*"; s.licenseAfterLink=true
                    C.PeerQueuePacket(C.LinkInvite(s,C.LinkNonce(),time(),GetTime()))
                end
            end
            C.SyncStore()
        end
    end
end

function C.PeerTick()
    C.HandTick()
    C.PlanPromptTick()
    -- Poll MCP's table each frame, but re-read the account and redraw only once it lands.
    if C.mcpPending then C.RaidReadLocal(); if not C.mcpPending then C.AccountReadLocal(); RefreshAccountPanel() end end
    if C.localRaidPending and (C.raidReadReady or GetTime()-C.localRaidPending>=(C.raidAwaitCCP and 10 or 2)) then
        C.localRaidPending=nil; C.RaidReadLocal(); RefreshAccountPanel()
    end
    for _,key in ipairs(C.SyncKeys()) do
        C.SyncActivate(C.peerSessions[key]); C.PeerTickOne()
    end
    C.SyncStore()
    if not C.peerPrompt or not C.peerPrompt:IsShown() then
        for _,key in ipairs(C.SyncKeys()) do
            local session=C.peerSessions[key]
            if session.state.phase=="approval" and C.PeerContextOK() then
                C.SyncActivate(session); C.promptSession=session; C.LinkShowPrompt(); break
            end
        end
    end
end

function C.LicenseObserve(records)
    if type(records)=="table" then C.AccountReadLocal(records) end
    for _,key in ipairs(C.SyncKeys()) do
        C.SyncActivate(C.peerSessions[key]); C.LicenseObserveOne(records)
    end
    C.SyncStore()
end

function C.PeerEvent()
    if event=="CHAT_MSG_ADDON" then C.RaidLocalEvent(); return end
    if event=="UPDATE_INSTANCE_INFO" then C.raidNativeReady=true; return end
    if event~="CHAT_MSG_WHISPER" then
        -- Leaving the world ends every exchange. A group change does not: link trust rests on
        -- whisper senders, saved approval and session nonces, and every hire changes the roster.
        if event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT" or event=="PLAYER_ENTERING_WORLD" then C.PeerAbortAll("Context changed; refresh to try again") end
        return
    end
    if not C.PeerContextOK() then return end
    local p=C.LinkParse(arg1) or C.LicenseParse(arg1) or C.RaidParse(arg1) or C.AccountParse(arg1) or C.PlanParse(arg1) or C.HandParse(arg1)
    if not p or type(arg2)~="string" or p.sender~=string.lower(arg2)
        or p.target~=string.lower(UnitName("player") or "") or p.realm~=GetRealmName() then return end
    local endpoint=C.PeerNew(UnitName("player"),arg2,GetRealmName())
    if not endpoint or not C.SyncSelect(endpoint,p.kind=="INVITE") then return end
    if C.HandParse(arg1) then
        C.HandReceive(C.peerState,arg1,arg2,DB.peerLinks,time(),GetTime())
    elseif C.PlanParse(arg1) then
        C.PlanReceive(C.peerState,arg1,arg2,DB.peerLinks,time(),GetTime())
    elseif C.AccountParse(arg1) then
        if C.AccountReceive(C.peerState,arg1,arg2,time(),GetTime()) then
            local copy=C.AccountSavedCopy(C.peerState.remoteLicense,UnitName("player"),GetRealmName(),DB.peerLinks)
            local key=p.realm .. ";" .. p.sender
            local previous=DB.peerSnapshots and DB.peerSnapshots[key]
            -- An approved endpoint cannot silently change its saved account identity.
            if copy and (not previous or not previous.accountId or previous.accountId==copy.accountId) then
                DB.peerSnapshots=DB.peerSnapshots or {}; DB.peerSnapshots[key]=copy
                C.LicenseRestoreSaved(); RefreshAccountPanel()
            end
        end
    elseif C.RaidParse(arg1) then
        if C.RaidReceive(C.peerState,arg1,arg2,time(),GetTime()) then
            local r=C.RaidSavedCopy(C.peerState.remoteRaids)
            if r and C.LinkKnown(DB.peerLinks,UnitName("player"),r.source,r.realm) then
                DB.peerRaidSnapshots=DB.peerRaidSnapshots or {}
                DB.peerRaidSnapshots[r.realm .. ";" .. r.source]=r
                C.RaidRestoreSaved(); RefreshAccountPanel()
            end
        end
    else C.PeerEventOne() end
    C.SyncStore(); C.PeerRefresh()
end

function C.RaidRestoreSaved()
    C.remoteRaids={}
    if type(DB.peerRaidSnapshots)~="table" then DB.peerRaidSnapshots={} end
    local n=0
    for key,r in pairs(DB.peerRaidSnapshots) do
        local copy=C.RaidSavedCopy(r)
        if copy and n<128 and key==copy.realm .. ";" .. string.lower(copy.source)
            and copy.realm==GetRealmName() and C.LinkKnown(DB.peerLinks,UnitName("player"),copy.source,copy.realm) then
            C.remoteRaids[key]=copy; n=n+1
        end
    end
end

function C.RaidReadLocal()
    local realm,player=GetRealmName(),UnitName("player")
    if C.mcpRealm~=realm or C.mcpPlayer~=player then
        C.mcpRealm=realm; C.mcpPlayer=player; C.mcpRows={}; C.mcpAlts=nil; C.mcpRoster={}
        C.mcpPending=nil; C.mcpBase=nil; C.localRaids=nil; C.mcpHead=nil
    end
    local data=C.MCPGlobal("MCP_SelfLockData")
    if C.mcpPending and GetTime()>=C.mcpPending and GetTime()-C.mcpPending<10
        and type(data)=="table" and data~=C.mcpBase then
        C.mcpPending=nil
        local now,up=time(),GetTime()
        C.localRaids=C.MCPLockSnapshot(data.locks,now,up)
        C.mcpRows=C.mcpRows or {}
        if C.localRaids.known then C.mcpRows[string.lower(player)]=C.localRaids end
        if type(data.alts)=="table" and data.alts~=C.mcpAlts
            and (type(C.mcpBase)~="table" or data.alts~=C.mcpBase.alts) and table.getn(data.alts)<=128 then
            C.mcpAlts=data.alts; C.mcpRoster={}
            local seen={}
            for _,alt in ipairs(data.alts) do
                if type(alt)=="table" and C.IsSafeCharacterName(alt.name) then
                    local key=string.lower(alt.name)
                    if key~=string.lower(player) and not seen[key] then
                        seen[key]=true
                        if alt.level==60 then table.insert(C.mcpRoster,{name=alt.name,level=60}) end
                        local snapshot=C.MCPLockSnapshot(alt.locks,now,up)
                        if snapshot.known then C.mcpRows[key]=snapshot end
                    end
                end
            end
        end
        C.raidReadReady=true
    end
    if C.mcpPending and (GetTime()<C.mcpPending or GetTime()-C.mcpPending>=10) then C.mcpPending=nil end
    if not C.localRaids then C.localRaids={known=false,observed=time(),entries={}} end
    return C.localRaids
end

function C.MCPGlobal(name)
    if type(_G)=="table" then return _G[name] end
    if type(getglobal)=="function" then return getglobal(name) end
end

function C.RaidRequestLocal()
    if not C.PeerContextOK() then return end
    if C.localRaidPending and GetTime()>=C.localRaidPending and GetTime()-C.localRaidPending<10 then return end
    if C.raidRequestAt and GetTime()>=C.raidRequestAt and GetTime()-C.raidRequestAt<2 then return end
    C.raidRequestAt=GetTime(); C.raidReadReady=nil; C.raidLocalData=nil; C.raidLocalBuffer=nil
    C.localRaidPending=GetTime()
    C.RaidReadLocal()
    C.localRaids={known=false,observed=time(),entries={}}
    C.raidAwaitCCP=true -- retain the bounded ten-second peer response window
    if type(C.MCPGlobal("MCP_Send"))=="function" and type(SendChatMessage)=="function" then
        -- MCP_Send routes to RAID/PARTY when grouped; these are server reads.
        local command=".stats locks"
        if C.MCPGlobal("MCP_SelfLockProto")==2 then command=".stats locks alts" end
        pcall(SendChatMessage,command,"SAY")
    end
end

-- Observe MCP's commit boundary, then read its table on the next tick.
function C.RaidLocalEvent()
    if type(arg1)~="string" or string.len(arg1)>8192 then return end
    if string.find(arg1,"^%[nexus%] ACINFO:SELFLOCK:HEAD %d+:%d+:%d+$")
        or string.find(arg1,"^%[nexus%] ACINFO:SELFLOCK:HEAD %d+:%d+:%d+:%d+:%d+$") then
        C.RaidReadLocal(); C.mcpBase=C.MCPGlobal("MCP_SelfLockData")
        C.mcpHead=GetTime(); C.mcpHeadRealm=GetRealmName(); C.mcpHeadPlayer=UnitName("player")
    elseif arg1=="[nexus] ACINFO:SELFLOCK:END" and C.mcpHead
        and C.mcpHeadRealm==GetRealmName() and C.mcpHeadPlayer==UnitName("player")
        and GetTime()>=C.mcpHead and GetTime()-C.mcpHead<10 then
        C.mcpPending=C.mcpHead; C.mcpHead=nil
    end
end

function C.RaidRowText(snapshot)
    if not snapshot or snapshot.known~=true then return "" end
    return C.SavedRaidLabels(snapshot.entries,type(time)=="function" and time())
end

function C.AccountReadLocal(records)
    EnsureDB()
    local realm=GetRealmName(); local now=type(time)=="function" and time(); local player=UnitName("player")
    if type(DB.localAccountRows)~="table" then DB.localAccountRows={} end
    local old=type(DB.localAccountRows[realm])=="table" and DB.localAccountRows[realm] or {}
    if not C.RaidNumber(now,1,2147483647) then return C.AccountMerge({},old) end
    if not C.AccountIdentity(DB.syncAccountId) then DB.syncAccountId=C.LinkNonce() end
    local input=records
    if not input then
        -- The saved server list refills own characters missing from these rows. It belongs to
        -- this realm on first use, or when it names the character you are on.
        local list=type(DB.inviteCharacters)=="table" and DB.inviteCharacters or {}
        input={}
        if not DB.localAccountRows[realm] or type(list[player or ""])=="table" then
            local have={}
            for _,e in ipairs(old) do if type(e)=="table" and type(e.name)=="string" then have[string.lower(e.name)]=true end end
            for _,e in pairs(list) do
                if type(e)=="table" and type(e.name)=="string" and not have[string.lower(e.name)] then table.insert(input,e) end
            end
        end
    end
    -- Loading screens and logout can report level 0. Characters never lose levels, so only a
    -- real live reading replaces the listed level, and a bad one never drops a level-60 row.
    local live=type(UnitLevel)=="function" and UnitLevel("player") or nil
    if type(live)~="number" or live<1 then live=nil end
    local valid,excluded={},{}
    for _,e in pairs(type(input)=="table" and input or {}) do
        if type(e)=="table" and C.IsSafeCharacterName(e.name) then
            local level=e.level
            if level==nil and type(DB.characterLevels)=="table" then level=DB.characterLevels[e.name] end
            if string.lower(e.name)==string.lower(player or "") and live then level=live end
            if level==60 then
                table.insert(valid,{name=e.name,level=60,dungeonLicense=e.dungeonLicense,raidLicense=e.raidLicense,faction=e.faction})
            elseif level~=nil then excluded[string.lower(e.name)]=true end
        end
    end
    local rows=C.AccountMerge(old,C.AccountCollect(valid,now))
    -- MCP discovers level-60 names, not licenses; never overwrite an existing row.
    local known,discovered={},{}
    for _,e in ipairs(rows) do known[string.lower(e.name)]=true end
    for _,e in ipairs(C.mcpRealm==realm and C.mcpRoster or {}) do
        if not known[string.lower(e.name)] then table.insert(discovered,e) end
    end
    rows=C.AccountMerge(rows,C.AccountCollect(discovered,now))
    local found=false
    for _,e in ipairs(rows) do if string.lower(e.name)==string.lower(player or "") then found=true end end
    if not found and live==60 then
        rows=C.AccountMerge(rows,C.AccountCollect({{name=player,level=60}},now))
    elseif live and live~=60 then excluded[string.lower(player or "")]=true end
    local out={}
    for _,e in ipairs(rows) do
        if not excluded[string.lower(e.name)] then
            local state=C.mcpRealm==realm and C.mcpRows and C.mcpRows[string.lower(e.name)]
            if state then
                C.AccountSetRaids(e,{known=state.known,observedAt=state.observed,instances=state.entries},now)
            end
            table.insert(out,e)
        end
    end
    -- Each row names its character's faction as the server list or the live game gives it,
    -- so a linked account can offer that faction's races.
    local server=type(DB.inviteCharacters)=="table" and DB.inviteCharacters or {}
    for _,e in ipairs(out) do
        if not e.faction and type(server[e.name])=="table" then e.faction=C.KnownFaction(server[e.name].faction) end
        if not e.faction and string.lower(e.name)==string.lower(player or "") and type(UnitFactionGroup)=="function" then e.faction=C.KnownFaction(UnitFactionGroup("player")) end
    end
    DB.localAccountRows[realm]=out
    return out
end

function C.LicenseSidebar(y)
    C.licenseAgeLabels={}
    local peers={}
    for _,p in pairs(DB.peerLinks or {}) do
        if p.realm==GetRealmName() and C.LinkKnown(DB.peerLinks,UnitName("player"),p.peer,p.realm) then peers[p.realm .. ";" .. p.peer]=p end
    end
    local keys={}; for key in pairs(peers) do table.insert(keys,key) end; table.sort(keys)
    local groups,order={},{}
    for _,key in ipairs(keys) do
        local snapshot=C.remoteLicenses and C.remoteLicenses[key]
        local id=snapshot and C.AccountIdentity(snapshot.accountId) and snapshot.realm .. ";" .. snapshot.accountId or key
        if not groups[id] then
            groups[id]={peer=peers[key],source=snapshot,entries={}}; table.insert(order,id)
        end
        if snapshot and snapshot.accountId then groups[id].entries=C.AccountMerge(groups[id].entries,snapshot.entries) end
    end
    for _,id in ipairs(order) do
        local group=groups[id]; local p=group.peer
        local header=C.AccountRow(y,20)
        header.lines[1]:SetTextColor(1,0.82,0)
        header.lines[1]:SetText("Linked: " .. (p.peerLabel or p.peer)); header.lines[1]:Show()
        y=y-22
        for _,entry in ipairs(C.AccountLicenseOrder(group.entries)) do
            local detail=C.AccountRaidLabels(entry,time())
            local source=group.source
            local model=C.CharacterLicenseRow(entry.name,entry,C.NormalHireCountForCharacter(EnsureDB().entries,entry.name),detail,source)

            local row=C.DrawCharacterLicenseRow(model,y)
            row:SetScript("OnClick",function()
                SetStatus(model.title)
            end)
            y=y-model.height-2
        end
    end
    return y
end

function C.PeerChooseKnown()
    local names={}
    for _,p in pairs(DB.peerLinks or {}) do
        if p.realm==GetRealmName() and C.LinkKnown(DB.peerLinks,UnitName("player"),p.peer,p.realm) then names[p.peer]=p.peerLabel or p.peer end
    end
    for _,session in pairs(C.peerSessions or {}) do
        local s=session.state
        if s.realm==GetRealmName() and s.phase~="disabled" then names[s.peer]=s.peerLabel or s.peer end
    end
    local values={}; for _,name in pairs(names) do table.insert(values,name) end; table.sort(values)
    if table.getn(values)==0 then C.peerPanel.knownButton.label:SetText("No known peers"); return end
    local selected=1
    for i,name in ipairs(values) do
        if string.lower(name)==string.lower(C.peerPanel.nameInput:GetText()) then selected=i+1 end
    end
    if selected>table.getn(values) then selected=1 end
    C.peerPanel.nameInput:SetText(values[selected])
    C.peerPanel.knownButton.label:SetText("Peer " .. selected .. "/" .. table.getn(values) .. " >")
    C.PeerRefresh()
end

-- Share only the current composition, addressed to existing linked endpoints.
function C.PlanShareRows()
    local f=C.planShareFrame
    for i,button in ipairs(f.recipientButtons) do
        local row=f.recipients[f.offset+i]
        button.recipient=row
        if row then
            button.label:SetText((f.selected[row.key] and "[x] " or "[ ] ") .. row.label)
            button:Show()
        else button:Hide() end
    end
end

function C.PlanCancelOutgoing()
    local f=C.planShareFrame
    if not f then return end
    for key in pairs(f.selected or {}) do
        local session=C.peerSessions and C.peerSessions[key]
        if session then
            C.SyncActivate(session); session.state.planOut=nil
            if C.PlanParse(C.peerPending) then C.peerPending=nil end
            C.SyncStore()
        end
    end
end

-- Share popup refresh: re-run the normal SRBLINK2 handshake for a saved approval
-- whose live session expired. Entries are keyed by session and never send a plan.
function C.PlanRefreshStart(row,link)
    local entry={status="failed",label=row.label,started=GetTime()}
    local previous=C.activeSession
    local endpoint=C.PeerNew(UnitName("player"),link.peerLabel or link.peer,link.realm)
    local session=endpoint and C.SyncSelect(endpoint,true)
    local s=session and session.state
    if not s then entry.reason="the link could not be prepared."
    elseif not C.PeerContextOK() then entry.reason="the builder is busy."
    elseif s.a and (s.phase=="waiting" or s.phase=="approval" or s.phase=="confirming" or s.phase=="confirm-sent") then
        -- The same recipient's handshake is already running and belongs to someone else.
        -- Observe it by nonce only: never restart, re-queue or cancel it.
        entry.status="pending"; entry.a=s.a; entry.borrowed=true
    elseif s.phase~="disabled" or C.peerPending then entry.status="busy"
    else
        s.remember=link.scope=="*"
        local packet=C.LinkInvite(s,C.LinkNonce(),time(),GetTime())
        if packet then
            s.invitation=packet; C.PeerQueuePacket(packet)
            entry.status="pending"; entry.a=s.a
        else entry.reason="the invitation could not be created." end
    end
    if session then
        C.SyncStore()
        if previous and previous~=session then C.SyncActivate(previous) end
    end
    return entry
end

function C.PlanRefreshCancel(key,entry)
    local session=C.peerSessions and C.peerSessions[key]; local s=session and session.state
    if entry.borrowed or not s or s.a~=entry.a or s.phase=="linked" or s.phase=="disabled" then return end
    local previous=C.activeSession
    C.SyncActivate(session); C.PeerAbort("Share refresh cancelled"); C.SyncStore()
    if previous and previous~=session then C.SyncActivate(previous) end
end

function C.PlanRefreshCancelAll(f)
    for key,entry in pairs(f and f.refresh or {}) do
        if entry.status=="pending" then C.PlanRefreshCancel(key,entry); entry.status="cancelled" end
    end
end

function C.PlanRefreshPending(f)
    for _,entry in pairs(f.refresh or {}) do
        if entry.status=="pending" then return true end
    end
    return false
end

function C.PlanRefreshText(f)
    local keys={}; for key in pairs(f.refresh or {}) do table.insert(keys,key) end; table.sort(keys)
    local pending,ready,waiting=0,0,0; local notes=""
    for _,key in ipairs(keys) do
        local entry=f.refresh[key]
        if entry.status=="pending" and entry.borrowed then waiting=waiting+1
        elseif entry.status=="pending" then pending=pending+1
        elseif entry.status=="ready" then ready=ready+1
        elseif entry.status=="busy" then notes=notes .. "\n" .. entry.label .. " is busy with another exchange. Try again shortly."
        elseif entry.status=="failed" then notes=notes .. "\nRefresh failed for " .. entry.label .. ": " .. (entry.reason or "no reply") end
    end
    if waiting>0 then
        return "Waiting for " .. waiting .. " link exchange(s) already in progress; it is not restarted here.\nNothing is sent. Choose Send again once it is ready." .. (pending>0 and "\nRefreshing " .. pending .. " more link(s)." or "") .. notes
    end
    if pending>0 then
        return "Refreshing " .. pending .. " link(s) through the normal handshake.\nNothing is sent until you choose Send." .. notes
    end
    local text="Refresh finished."
    if ready>0 then text="Refreshed " .. ready .. " link(s); ready to send. Receiver chooses copy or merge." end
    return text .. notes
end

function C.PlanRefreshTick(f)
    local changed=false
    C.SyncStore()
    for key,entry in pairs(f.refresh) do
        if entry.status=="pending" then
            local session=C.peerSessions and C.peerSessions[key]; local s=session and session.state
            if entry.borrowed and s and s.phase~="disabled" and s.a~=entry.a then
                entry.status="failed"; entry.reason="the link exchange was replaced. Close and reopen Share to retry."
            elseif not s then entry.status="failed"; entry.reason="the session was removed."
            elseif s.phase=="linked" and C.PlanAuthorized(s,DB.peerLinks,time(),GetTime()) then
                entry.status="ready"
                for _,row in ipairs(f.recipients) do if row.key==key then row.available=true end end
            elseif s.phase=="disabled" then entry.status="failed"; entry.reason=s.reason or "no reply."
            elseif GetTime()<entry.started or GetTime()-entry.started>=65 then
                C.PlanRefreshCancel(key,entry); entry.status="failed"; entry.reason="timed out. The other account may be offline or have SRB closed."
            end
            if entry.status~="pending" then changed=true end
        end
    end
    if changed and not f.batches then f.message:SetText(C.PlanRefreshText(f)) end
end

function C.PlanSendCurrent()
    local f=C.planShareFrame
    if not f or not C.PeerContextOK() then return end
    C.SyncStore()
    local bank,name=C.PresetBank(DB,DB.uiMode)
    if DB.uiMode~=f.mode or name~=f.name then f.message:SetText("Current plan changed. Close and open Share again."); return end
    local wire=C.PlanEncode(bank[name],f.mode,name)
    if not wire then f.message:SetText("Plan has unsupported names or exceeds the share limit."); return end
    local batches={}; local total=0
    for _,row in ipairs(f.recipients) do
        if f.selected[row.key] then
            local session=C.peerSessions and C.peerSessions[row.key]; local s=session and session.state
            local entry=f.refresh and f.refresh[row.key]
            if entry and entry.borrowed then
                -- A borrowed observation only vouches for its own nonce, checked here
                -- so a replaced handshake cannot slip through before the next tick.
                if entry.status=="pending" and s and s.a==entry.a then f.message:SetText(C.PlanRefreshText(f)); return end
                if entry.status~="ready" or not s or s.a~=entry.a then
                    f.message:SetText("The link exchange this window was watching ended or was replaced.\nNothing was sent. Close and reopen Share to retry."); return
                end
            end
            if not C.PlanAuthorized(s,DB.peerLinks,time(),GetTime()) or s.planOut or session.pending then
                f.message:SetText("Recipient unavailable or busy. Refresh Synchronization, then try again."); return
            end
            local packets=C.PlanPackets(s,wire,C.LinkNonce(),time(),GetTime())
            if not packets then f.message:SetText("Link expires too soon. Refresh Synchronization, then try again."); return end
            total=total+table.getn(packets); table.insert(batches,{state=s,packets=packets})
        end
    end
    if table.getn(batches)<1 or table.getn(batches)>4 then f.message:SetText("Choose one to four linked accounts."); return end
    for _,batch in ipairs(batches) do
        if batch.state.expires-time()<total*0.25+10 then f.message:SetText("Too much data for this link. Send to fewer accounts after refreshing."); return end
    end
    for _,batch in ipairs(batches) do
        batch.progress={nonce=C.PlanParse(batch.packets[1]).nonce,sent=0,total=table.getn(batch.packets)}
        batch.state.planProgress=batch.progress; batch.state.planOut=batch.packets
    end
    f.batches=batches
    f.message:SetText("Queued for receiver approval. Keep this window open.\nNo plan is activated or executed. Cancel stops unsent packets.")
    f.sendButton:Disable()
    for _,button in ipairs(f.recipientButtons) do button:Disable() end
end

-- Row click: toggles selection. In a multi-recipient popup, selecting a stale row
-- starts the refresh for exactly that row.key; deselecting cancels only a refresh
-- this click started. Never starts a send.
function C.PlanToggleRecipient(row)
    local f=C.planShareFrame
    if not f or not row or not row.key then return end
    f.selected[row.key]=not f.selected[row.key] or nil
    local entry=f.refresh and f.refresh[row.key]
    if table.getn(f.recipients)>1 then
        if f.selected[row.key] then
            if not row.available and not (entry and entry.status=="pending") and row.link then
                entry=C.PlanRefreshStart(row,row.link); entry.owned=not entry.borrowed; f.refresh[row.key]=entry
                if not f.batches then f.message:SetText(C.PlanRefreshText(f)) end
            end
        elseif entry and entry.owned and entry.status=="pending" then
            C.PlanRefreshCancel(row.key,entry); entry.status="cancelled"
            if not f.batches then f.message:SetText(C.PlanRefreshText(f)) end
        end
    end
    C.PlanShareRows()
end

function C.OpenPlanShare()
    C.PeerOnBuilderOpen()
    if not C.PeerContextOK() then return end
    local shown=C.planShareFrame
    -- A repeated click while a send or refresh is in flight only raises the popup.
    if shown and shown:IsShown() and (shown.batches or C.PlanRefreshPending(shown)) then shown:Raise(); return end
    if not C.planShareFrame then
        local f=CreateFrame("Frame","ShirsRaidBuilderPlanShare",UIParent); C.planShareFrame=f
        f:SetWidth(550); f:SetHeight(390); f:SetPoint("CENTER",UIParent,"CENTER",0,0); StylePanelFrame(f)
        f.title=MakeCaption(f,"",22,-18); f.title:SetWidth(506); f.title:SetHeight(36)
        f.recipientButtons={}
        for i=1,6 do
            local button=MakeButton(f,"",506,22,-56-(i-1)*28,function()
                local row=this.recipient
                if row then C.PlanToggleRecipient(row) end
            end)
            table.insert(f.recipientButtons,button)
        end
        f.nextButton=MakeButton(f,"Next accounts",144,22,-230,function()
            f.offset=f.offset+6; if f.offset>=table.getn(f.recipients) then f.offset=0 end; C.PlanShareRows()
        end)
        f.message=MakeCaption(f,"",22,-264); f.message:SetWidth(506); f.message:SetHeight(60); f.message:SetJustifyH("LEFT")
        f.sendButton=MakeButton(f,"Send current plan",164,22,18,C.PlanSendCurrent,true)
        f.cancelButton=MakeButton(f,"Cancel / close",144,200,18,function() f:Hide() end,true)
        f:SetScript("OnHide",function() C.PlanCancelOutgoing(); C.PlanRefreshCancelAll(f) end)
    end
    local f=C.planShareFrame; C.PlanCancelOutgoing()
    local _,name=C.PresetBank(DB,DB.uiMode); f.name=name; f.mode=DB.uiMode
    f.selected={}; f.recipients={}; f.offset=0; f.batches=nil
    for _,button in ipairs(f.recipientButtons) do button:Enable() end
    local grouped={}; local keys={}
    for _,p in pairs(DB.peerLinks or {}) do
        if p.realm==GetRealmName() and C.LinkKnown(DB.peerLinks,UnitName("player"),p.peer,p.realm) then
            local key=p.realm .. ";" .. p.peer
            keys[key]=p
        end
    end
    local ordered={}; for key in pairs(keys) do table.insert(ordered,key) end; table.sort(ordered)
    for _,key in ipairs(ordered) do
        local p=keys[key]; local snapshot=C.remoteLicenses and C.remoteLicenses[key]
        local id=snapshot and snapshot.accountId or key
        local session=C.peerSessions and C.peerSessions[key]
        local available=session and C.PlanAuthorized(session.state,DB.peerLinks,time(),GetTime())
        local row={key=key,label=(p.peerLabel or p.peer) .. " / " .. p.realm,available=available,link=p}
        if not grouped[id] then grouped[id]=row; table.insert(f.recipients,row)
        elseif available and not grouped[id].available then
            grouped[id].key=row.key; grouped[id].label=row.label; grouped[id].available=true; grouped[id].link=p
        end
    end
    f.refresh={}
    -- One recipient is unambiguous, so refresh it on open. With several, refresh
    -- only the row the user selects (see C.PlanToggleRecipient).
    if table.getn(f.recipients)==1 then
        local row=f.recipients[1]
        if not row.available then f.refresh[row.key]=C.PlanRefreshStart(row,row.link) end
    end
    f.title:SetText("Share current " .. f.mode .. " plan: " .. name)
    if next(f.refresh) then f.message:SetText(C.PlanRefreshText(f))
    else f.message:SetText("Choose linked accounts. Composition only; no deny/setup settings.\nBoth accounts must refresh first. Receiver chooses copy or merge.") end
    f.sendButton:Enable(); C.PlanShareRows(); f:Show(); f:Raise()
    EnsureEscapeWatcher(); escapeFrame:Show()
end

function C.PlanReceiveChoice(action)
    local f=C.planReceiveFrame; local s=f and f.session and f.session.state
    if not s or not C.PeerContextOK() or s.you~=string.lower(UnitName("player") or "") or s.realm~=GetRealmName() then return end
    local destination=C.Trim(f.destination:GetText())
    local ok,result=C.PlanImport(DB,s,DB.peerLinks,destination,action,time(),GetTime())
    if ok then
        f:Hide(); RefreshPresetButton()
        local report="Raid plan saved to " .. destination .. ": " .. result.added .. " added, " .. result.moved .. " moved to free slots. Select it yourself; nothing was executed."
        SetStatus(report); Chat(report)
    else
        local reasons={
            exists="a plan with this name exists. Copy needs a new name.",
            missing="no existing plan with this name to merge into.",
            capacity="not enough free slots for the moved rows. The plan was left unchanged.",
            destination="invalid destination name.",
            unauthorized="the link expired or was revoked.",
            proposal="the offer is no longer available.",
            invalid="the received plan is invalid.",
            action="unknown approval choice.",
        }
        f.message:SetText("Not imported: " .. (reasons[result] or "the local database is unavailable."))
    end
end

function C.PlanPromptTick()
    local outgoing=C.planShareFrame
    if outgoing and outgoing:IsShown() and outgoing.refresh then C.PlanRefreshTick(outgoing) end
    if outgoing and outgoing:IsShown() and outgoing.batches then
        local complete=true; local stopped=false
        C.SyncStore()
        for _,batch in ipairs(outgoing.batches) do
            if batch.progress.sent~=batch.progress.total then
                complete=false
                if batch.state.phase~="linked" then stopped=true end
            end
        end
        if complete then
            outgoing.message:SetText("Submitted to the whisper service. Delivery and approval are unconfirmed.\nYou can close this window. The receiver must approve the copy.")
            outgoing.batches=nil
        elseif stopped then
            outgoing.message:SetText("Transfer stopped or expired. Receipt is unconfirmed.\nRefresh Synchronization and send again if needed.")
            outgoing.batches=nil
        end
    end
    local f=C.planReceiveFrame
    if f and f:IsShown() then
        local s=f.session and f.session.state
        if not C.PeerContextOK() or not C.PlanAuthorized(s,DB.peerLinks,time(),GetTime()) or not s.planProposal then f:Hide() end
        return
    end
    if not C.PeerContextOK() then return end
    for _,key in ipairs(C.SyncKeys()) do
        local session=C.peerSessions[key]; local s=session.state
        if s.planProposal and C.PlanAuthorized(s,DB.peerLinks,time(),GetTime()) then
            if not f then
                f=CreateFrame("Frame","ShirsRaidBuilderPlanReceive",UIParent); C.planReceiveFrame=f
                f:SetWidth(590); f:SetHeight(290); f:SetPoint("CENTER",UIParent,"CENTER",0,70); StylePanelFrame(f)
                f.title=MakeCaption(f,"",22,-20); f.title:SetWidth(546); f.title:SetHeight(54); f.title:SetJustifyH("LEFT")
                MakeCaption(f,"Destination plan name (same Hire / Sort bank)",22,-82)
                f.destination=MakeInput(f,360,22,-104,"")
                f.message=MakeCaption(f,"",22,-144); f.message:SetWidth(546); f.message:SetHeight(74); f.message:SetJustifyH("LEFT")
                f.copyButton=MakeButton(f,"Approve new copy",164,22,18,function() C.PlanReceiveChoice("copy") end,true)
                f.mergeButton=MakeButton(f,"Approve merge",164,198,18,function() C.PlanReceiveChoice("merge") end,true)
                f.rejectButton=MakeButton(f,"Reject",110,374,18,function() f:Hide() end,true)
                f:SetScript("OnHide",function() C.PlanReject(f.session and f.session.state); f.session=nil end)
            end
            f.session=session
            f.title:SetText(s.peerLabel .. " / " .. s.realm .. " sent a " .. s.planProposal.plan.mode .. " plan:\n" .. s.planProposal.plan.name)
            f.destination:SetText("")
            f.message:SetText("Copy requires a new name. Merge into an existing plan keeps its occupied slots;\nincoming rows for occupied slots move to the first free slots.\nIf free slots run out, nothing is imported. Settings stay local.\nNo activation, hiring, sorting or commands. Reject discards this offer.")
            f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(150); f:Show(); f:Raise()
            for _,control in ipairs({f.dragBar,f.destination,f.copyButton,f.mergeButton,f.rejectButton}) do
                control:SetFrameStrata("FULLSCREEN_DIALOG"); control:SetFrameLevel(151)
            end
            return
        end
    end
end

-- Durable handoffs carry a frozen board and its plan's own commands, never other local settings.
-- It runs every frame through HandTick, so it only binds the saved table: the full repair
-- pass (EnsureDB) rebuilt every board slot each frame. Load and edits still run it.
function C.HandStore()
    if DB~=ShirsRaidBuilderDB or type(DB.presets)~="table" then EnsureDB() end
    if type(DB.handoff)~="table" then DB.handoff={} end
    if not C.handRestored then
        C.handRestored=true
        if DB.handoff.active then
            local h=C.HandRestore(DB.handoff.active,UnitName("player"),GetRealmName(),time())
            DB.handoff.active=h
        end
    end
    return DB.handoff
end

function C.HandStatus(text)
    C.handNotice=text
    if C.handFrame then C.handFrame.message:SetText(text) end
    SetStatus(text)
end

-- This account's own characters, freshly collected: lower-case name -> true.
function C.HandOwn()
    local own={}
    for _,row in ipairs(C.AccountReadLocal()) do own[string.lower(row.name)]=true end
    return own
end

function C.HandStartHire()
    if executing or DB.uiMode=="sort" then return end
    local h=C.HandStore().active
    if h and h.phase~="done" and h.phase~="cancelled" then C.HandStatus("A process is already active or paused. Inspect sent hires, then Cancel process in Hire status before starting another."); return end
    local plan=EnsureDB(); local own=C.HandOwn()
    -- Live sessions are read once here, before actors freeze; the run never re-resolves them.
    local sources=C.HandRemoteSources(C.remoteLicenses,DB.peerLinks,UnitName("player"),GetRealmName(),C.peerSessions,time(),GetTime())
    local actors,remote,conflict,unclear,unknownLegacy=C.HandActors(plan,UnitName("player"),own,sources)
    if unclear then C.HandStatus("Group " .. conflict .. ": " .. unclear .. " is listed by more than one account or linked character. Fix links or the board before Execute."); return end
    if not actors then C.HandStatus("Board hire-from identity is unclear or invalid. Fix the board before Execute; nothing was sent."); return end
    if not remote then C.whisperRun=nil; ExecuteQueue(); return end
    h=C.HandCreate(plan,DB.currentPreset,UnitName("player"),GetRealmName(),actors,C.LinkNonce(),time(),own,sources,true)
    if not h then C.HandStatus("Board hire-from identity is unclear or invalid. Fix the board before Execute; nothing was sent."); return end
    -- Split groups never raise the four-hire limit: the whole frozen plan is checked once,
    -- before any authority, grant or hire.
    local over=C.OverLimitHireCharacter(h.plan.entries,4)
    if over then C.HandStatus(over .. " has more than four normal hires in this plan. Remove extras before Execute; nothing was sent."); return end
    for _,row in ipairs(h.steps) do
        if string.lower(row.actor)~=string.lower(UnitName("player")) and not C.LinkKnown(DB.peerLinks,UnitName("player"),row.actor,h.realm) then C.HandStatus("Link " .. row.actor .. " before Execute."); return end
    end
    h.kind="GRANT"; h.accounts={}; h.expires=time()+7200
    for i,row in ipairs(h.steps) do
        if string.lower(row.actor)==string.lower(UnitName("player")) then h.accounts[i]=DB.syncAccountId
        else
            local r=C.remoteLicenses and C.remoteLicenses[h.realm .. ";" .. string.lower(row.actor)]
            h.accounts[i]=r and r.accountId
        end
        if not C.AccountIdentity(h.accounts[i]) then C.HandStatus("Synchronize " .. row.actor .. " before Execute; its account identity is unavailable."); return end
    end
    if not C.HandEncode(h) then C.HandStatus("Board hire-from identity is unclear or invalid. Fix the board before Execute; nothing was sent."); return end
    -- The plan's own rules and legacy commands go with the run, so every account applies
    -- this plan, never the profile it happens to have open.
    h.extras=C.HandExtras(plan)
    if not h.extras then C.HandStatus("A rule or legacy command in this plan has text a linked account cannot receive. Edit it, then Execute again; nothing was sent."); return end
    if not C.HandEncode(h) then C.HandStatus("This plan's rules and legacy commands are too long to send to a linked account. Remove some, then Execute again; nothing was sent."); return end
    -- A legacy character no account list names follows its group's account; say so.
    if unknownLegacy and table.getn(unknownLegacy)>0 then
        Chat("No account lists legacy " .. table.concat(unknownLegacy, ", ") .. "; its group's account will hire it. If it belongs to a linked account, Refresh Synchronization first.")
    end
    C.HandStore().active=h; C.handAuthority=C.HandRunScope(h)
    -- Board order is kept: a linked account's first group is granted before any local spend.
    if string.lower(h.steps[1].actor)==string.lower(UnitName("player")) then C.HandExecuteLocal()
    else h.phase="waiting"; h.updated=time(); C.HandSendLocal() end
end

function C.HandLocalPlan()
    local h=C.HandStore().active
    if executing or (C.sortFrame and C.sortFrame.busy) then return nil end
    if not h or h.realm~=GetRealmName() or time()>=h.expires then return nil end
    -- A run carrying its plan's commands needs nothing from the open profile, so the
    -- builder's mode does not matter. An older run reads the open hire profile's rules,
    -- which Sort mode would replace with the sort profile.
    if DB.uiMode=="sort" and not h.extras then return nil end
    if h.source and not C.LinkKnown(DB.peerLinks,UnitName("player"),h.source,h.realm) then return nil end
    local plan=C.HandStepPlan(h,EnsureDB(),UnitName("player"),C.HandOwn())
    if plan then for i=1,40 do if not plan.entries[i] then plan.entries[i]={kind="empty"} end end end
    return plan
end

function C.HandExecuteLocal()
    if not mainFrame or not mainFrame:IsShown() then return end
    C.HandRunStep()
end

-- Already-approved work this client did not start is refused one way: execution authority
-- ends, the reason stays visible, and a participant's leader gets one PAUSE bound to this
-- exact run step, sent under a notice scope that is never execution authority.
function C.HandRefuse(text)
    local h=C.HandStore().active
    C.HandPause(text)
    if h and h.kind=="GRANT" and string.lower(h.origin)~=string.lower(UnitName("player")) then
        C.handNotify={scope=C.HandRunScope(h),text=text}; C.HandSendLocal()
    end
end

function C.HandRunStep()
    local active=C.HandStore().active
    if active and active.kind and C.handAuthority~=C.HandRunScope(active) then C.HandStatus("Run authorization expired or was lost on reload. Check sent hires and Cancel before a new Execute."); return end
    local plan=C.HandLocalPlan()
    if not plan and not (active and active.kind) then C.HandStatus("No ready local step for this character. Nothing was sent."); return end
    -- Authorized work that cannot start (a hire-from character not on this account, failed
    -- validation, or a queue that did not start) is refused before any command is sent.
    if not plan then C.HandRefuse("Paused: this character cannot run its granted group; a hire-from character is not on this account, or the run is busy or expired. No hires were sent."); return end
    -- Deny commands are checked for this chunk; the four-hire limit holds for the whole
    -- frozen plan, so trusted input split into small chunks can never raise it.
    local errorText=C.DenyQueueError(C.HandQueue(plan)); local over=C.OverLimitHireCharacter(active.plan.entries,4)
    if errorText then C.HandRefuse("Paused before any hire: " .. errorText); return end
    if over then C.HandRefuse("Paused: " .. over .. " has more than four normal hires in this run. No hires were sent."); return end
    local h=C.HandStore().active
    h.phase="running"; h.updated=time(); C.handRunPlan=plan; C.whisperRun=nil
    ExecuteQueue()
    -- Already finished with no commands and advanced (possibly into the next group).
    if C.handRunPlan~=plan then return end
    if not executing then C.handRunPlan=nil; C.HandRefuse("Paused: this group's queue did not start. No hires were sent."); return end
    C.HandStatus("Local group started. Normal submission advances automatically; server results remain unverified.")
end

function C.HandSendLocal()
    if not C.PeerContextOK() then C.HandStatus("Handoff paused. Wait for the local queue, then recover."); return end
    local h=C.HandStore().active
    -- Execution authority sends GRANT/REPORT; a refusal notice for the same exact run
    -- scope, held only without authority, sends nothing but that step's PAUSE.
    local scope=C.HandRunScope(h)
    local notice=C.handNotify
    local refused=scope~=nil and notice~=nil and notice.scope==scope and C.handAuthority==nil
    if not h or h.realm~=GetRealmName() or time()>=h.expires or (h.kind and C.handAuthority~=scope and not refused) then return end
    local wire,target=C.HandOutgoing(h,UnitName("player"),refused)
    if not wire then return end
    -- A REPORT, and a GRANT to an account that has reported in this run, go short: the
    -- receiver holds the run. A PAUSE ends the run and stays whole.
    local out=C.HandDecode(wire)
    local holds=C.handHolders and C.handHolders[h.id] and C.handHolders[h.id][string.lower(target)]
    if out and (out.kind=="REPORT" or (out.kind=="GRANT" and holds)) then wire=C.HandShort(out) or wire end
    local endpoint=C.PeerNew(UnitName("player"),target,h.realm)
    if not endpoint or not C.SyncSelect(endpoint,true) then C.HandStatus("Handoff paused: linked endpoint unavailable."); return end
    local s=C.peerState
    local packets=C.HandPackets(s,wire,C.LinkNonce(),time(),GetTime())
    if not C.PlanAuthorized(s,DB.peerLinks,time(),GetTime()) or not packets then
        if not C.LinkKnown(DB.peerLinks,s.you,s.peer,s.realm) then C.HandStatus("Handoff paused: peer approval is missing."); return end
        if C.handAwaitLink then return end
        if s.phase=="linked" then C.PeerAbort("Refreshing trusted handoff link"); C.SyncStore() end
        local key=endpoint.realm .. ";" .. endpoint.peer
        local link=DB.peerLinks[C.LinkKey(s.you,s.peer,s.realm,true)] or DB.peerLinks[C.LinkKey(s.you,s.peer,s.realm,false)]
        if not link then C.HandPause("Handoff paused: remembered link unavailable."); return end
        local row={key=key,label=target}
        local entry=C.PlanRefreshStart(row,link)
        C.handAwaitLink={id=h.id,step=h.step,refresh={[key]=entry},recipients={row},message={SetText=function() end},deadline=GetTime()+65}
        C.HandStatus("Refreshing the trusted live link for automatic handoff."); return
    end
    if s.handOut or C.peerPending or (s.handProgress and s.handProgress.sent<s.handProgress.total and s.handProgress.expires>time()) then C.HandStatus("Transfer already pending. Wait, or cancel before retrying."); return end
    local nonce=C.HandParse(packets[1]).nonce
    s.handOut=packets; s.handProgress={nonce=nonce,sent=0,total=table.getn(packets),expires=s.expires}
    C.handTransfer={state=s,progress=s.handProgress,kind=refused and "PAUSE" or (h.origin==UnitName("player") and "GRANT" or "REPORT"),
        target=target,note=refused and notice.text or nil}; C.SyncStore()
    if h.kind=="GRANT" and string.lower(h.origin)==string.lower(UnitName("player")) then C.handReportDeadline=GetTime()+600 end
    if refused then C.HandStatus(notice.text .. " Telling " .. target .. ".")
    else C.HandStatus("Authorized handoff queued. Server results are unverified.") end
end

function C.HandCancelLocal()
    local store=C.HandStore(); local h=store.active
    if C.handRunPlan then StopQueue() end
    if h then
        h.phase="cancelled"; store.seen=store.seen or {}; store.seen[h.id]={step=h.step,expires=h.expires,cancelled=true}
    end
    for _,session in pairs(C.peerSessions or {}) do
        session.state.handOut=nil; session.state.handProposal=nil; session.state.handInput=nil
        if C.HandParse(session.pending) then session.pending=nil end
    end
    if C.HandParse(C.peerPending) then C.peerPending=nil end
    C.handTransfer=nil; C.HandStatus("Cancelled locally. Already delivered steps on other accounts need local cancellation there too.")
    if C.handAwaitLink then C.PlanRefreshCancelAll(C.handAwaitLink) end
    C.handAwaitLink=nil; C.handAuthority=nil; C.handReportDeadline=nil; C.handNotify=nil
end

function C.HandApproveLocal()
    local f=C.handReceiveFrame; local s=f and f.session and f.session.state
    if not f or not f:IsShown() or not C.PeerContextOK() or not C.PlanAuthorized(s,DB.peerLinks,time(),GetTime()) or not s.handProposal then return end
    local h=C.HandDecode(s.handProposal.wire)
    if not C.HandApprove(C.HandStore(),h,s.peer,UnitName("player"),GetRealmName(),time()) then f.message:SetText("Rejected: duplicate, stale, conflicting, expired or wrong-actor process."); return end
    f:Hide(); C.HandStatus("Approved and saved. Open /srbhandoff, Preview, then Execute locally. Nothing was executed.")
end

function C.HandPause(text)
    C.handAuthority=nil; C.handReportDeadline=nil; C.handNotify=nil
    if C.handAwaitLink then C.PlanRefreshCancelAll(C.handAwaitLink) end
    C.handAwaitLink=nil; C.handTransfer=nil
    for _,session in pairs(C.peerSessions or {}) do
        session.state.handOut=nil; session.state.handProposal=nil; session.state.handInput=nil
        if C.HandParse(session.pending) then session.pending=nil end
    end
    if C.HandParse(C.peerPending) then C.peerPending=nil end
    local h=C.HandStore().active
    if C.handRunPlan then StopQueue() end
    if h then h.phase="interrupted" end
    C.HandStatus(text)
end

function C.HandTick()
    local active=C.HandStore().active
    if C.handAuthority and active and (active.realm~=GetRealmName() or time()>=active.expires
        or (C.handReportDeadline and GetTime()>=C.handReportDeadline)) then
        C.HandPause("Process timed out. Check submitted hires before starting another run.")
    end
    local wait=C.handAwaitLink
    if wait then
        local h=C.HandStore().active
        C.PlanRefreshTick(wait)
        if not h or h.id~=wait.id or h.step~=wait.step or GetTime()>=wait.deadline then
            C.HandPause("Automatic handoff stopped. Check submitted hires; no hires will retry.")
        elseif not C.PlanRefreshPending(wait) then
            local ready=true; for _,entry in pairs(wait.refresh) do if entry.status~="ready" then ready=false end end
            C.handAwaitLink=nil
            local target=wait.recipients and wait.recipients[1] and wait.recipients[1].label or "The linked account"
            local lead=h and string.lower(h.origin or "")==string.lower(UnitName("player") or "")
            if ready then C.HandSendLocal()
            else C.HandPause("Paused: " .. target .. " did not answer, so nothing more was sent." .. (lead and " If that account is on another character, Refresh Synchronization, cancel this process and Execute again." or "")) end
        end
    end
    if C.PeerContextOK() then
        for _,key in ipairs(C.SyncKeys()) do
            local session=C.peerSessions[key]; local s=session.state
            if s.handProposal and C.PlanAuthorized(s,DB.peerLinks,time(),GetTime()) then
                local old=C.HandStore().active
                local h=C.HandDecode(s.handProposal.wire) or C.HandExpand(s.handProposal.wire,old)
                local claim=C.remoteLicenses and C.remoteLicenses[s.realm .. ";" .. s.peer]
                -- Answers bind only to a GRANT run this leader holds real authority for, so a
                -- plain, foreign or unauthorized run is never indexed, moved or paused.
                local held=old and old.kind=="GRANT" and C.handAuthority~=nil and C.handAuthority==C.HandRunScope(old)
                if h and h.kind=="REPORT" then
                    if held and claim and claim.accountId==old.accounts[old.step]
                        and C.HandReport(old,h,s.peer,UnitName("player"),GetRealmName(),time()) then
                        C.handReportDeadline=nil
                        C.handHolders=C.handHolders or {}; C.handHolders[old.id]=C.handHolders[old.id] or {}
                        C.handHolders[old.id][string.lower(s.peer)]=true
                        if old.phase=="ready" then C.HandRunStep()
                        elseif old.phase=="waiting" then C.HandSendLocal()
                        else C.handAuthority=nil; C.HandStatus("Process submitted. Check server results; no further group will run.") end
                    else C.HandStatus("Report rejected: wrong account, step or run.") end
                elseif h and h.kind=="PAUSE" then
                    -- A refusal only pauses this leader's exact waiting step: no advance, skip or regrant.
                    if held and claim and claim.accountId==old.accounts[old.step]
                        and C.HandRefusal(old,h,s.peer,UnitName("player"),GetRealmName(),time()) then
                        C.HandPause("Paused: " .. old.steps[old.step].actor .. " could not run or finish its granted group; its chat says why. No further group will run; check submitted hires, then Cancel process before Execute.")
                    else C.HandStatus("Pause rejected: wrong account, step or run.") end
                elseif h and h.kind=="GRANT" then
                    if not executing and claim and C.HandGrantBound(h,s.peer,UnitName("player"),DB.syncAccountId,claim.accountId)
                        and C.HandApprove(C.HandStore(),h,s.peer,UnitName("player"),GetRealmName(),time()) then
                        C.handAuthority=C.HandRunScope(h); C.HandRunStep()
                    else C.HandStatus("Authorization rejected: duplicate, stale, busy, conflicting or wrong account.") end
                elseif h and not h.kind and C.HandApprove(C.HandStore(),h,s.peer,UnitName("player"),GetRealmName(),time()) then
                    C.HandStatus("Legacy handoff saved without execution authority. No hires sent.")
                else C.HandStatus("Handoff rejected: duplicate, stale, conflicting, expired or wrong actor.") end
                s.handProposal=nil; s.handInput=nil
            end
        end
    end
    local out=C.handTransfer
    if out then
        if out.progress.sent==out.progress.total then
            C.handTransfer=nil
            if out.kind=="PAUSE" then
                C.handNotify=nil
                C.HandStatus(out.note .. " The pause was submitted to " .. out.target .. "; delivery is unverified.")
            else
                C.HandStatus("Handoff submitted. Waiting for the authorized group's submission; server results remain unverified.")
                if out.kind=="REPORT" then C.handAuthority=nil end
            end
        elseif out.state.phase~="linked" or time()>=out.progress.expires then C.HandPause("Transfer stopped or timed out. Check sent hires before recovery; no automatic replay.")
        elseif out.shown~=out.progress.sent then
            out.shown=out.progress.sent; C.HandStatus("Handoff packets " .. out.progress.sent .. "/" .. out.progress.total .. ".")
        end
    end
    -- The progress line is rebuilt only when the run, its step or phase, or expiry changes.
    local f=C.handFrame
    if f and f:IsShown() then
        local h=C.HandStore().active
        local expired=h and time()>=h.expires
        if not f.drawn or f.drawnRun~=h or f.drawnStep~=(h and h.step) or f.drawnPhase~=(h and h.phase) or f.drawnExpired~=expired then
            f.drawn=true; f.drawnRun=h; f.drawnStep=h and h.step; f.drawnPhase=h and h.phase; f.drawnExpired=expired
            local row=h and h.steps[h.step]
            local slots=row and row.first and (" slots " .. row.first .. "-" .. row.last) or ""
            f.progress:SetText(h and (h.name .. " | " .. h.phase .. " | Step " .. h.step .. "/" .. table.getn(h.steps) .. (row and (row.group==0 and (" | Commands: " .. row.actor) or (" | Group " .. row.group .. slots .. ": " .. row.actor)) or "") .. (expired and " | EXPIRED" or "")) or "No active process")
        end
    end
end

function C.OpenHandoff()
    C.PeerOnBuilderOpen(); C.HandStore()
    if not C.handFrame then
        local f=CreateFrame("Frame","ShirsRaidBuilderHandoff",UIParent); C.handFrame=f
        -- Status only: the board names each group's account and one Hire Execute runs it.
        f:SetWidth(630); f:SetHeight(250); f:SetPoint("CENTER",UIParent,"CENTER",0,0); StylePanelFrame(f)
        f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
        MakeCaption(f,"Hire status",22,-20)
        f.progress=MakeCaption(f,"",22,-54); f.progress:SetWidth(580); f.progress:SetHeight(44); f.progress:SetJustifyH("LEFT")
        f.message=MakeCaption(f,"",22,-104); f.message:SetWidth(580); f.message:SetHeight(76); f.message:SetJustifyH("LEFT")
        f.cancelButton=MakeButton(f,"Cancel process",150,22,18,C.HandCancelLocal,true)
        f.stopButton=MakeButton(f,"Stop execution",150,184,18,StopQueue,true)
        f.closeButton=MakeButton(f,"Close",110,346,18,function() f:Hide() end,true)
    end
    C.handFrame:Show(); C.handFrame:Raise(); C.HandStatus(C.handNotice or "One Hire Execute runs the prepared plan. Linked accounts run their own hires automatically, in board order, after each prior step is submitted."); C.HandTick()
end

SLASH_SHIRSRAIDBUILDERHANDOFF1="/srbhandoff"
SlashCmdList["SHIRSRAIDBUILDERHANDOFF"]=C.OpenHandoff

function C.OpenPeerPOC()
    C.PeerOnBuilderOpen()
    if not C.peerPanel then
        local f=CreateFrame("Frame","ShirsRaidBuilderPeerPOC",UIParent); C.peerPanel=f
        f:SetWidth(570); f:SetHeight(484); f:SetPoint("CENTER",UIParent,"CENTER",0,0); StylePanelFrame(f)
        MakeCaption(f,"Link another account",22,-14)
        MakeButton(f,"X",22,526,-8,function() f:Hide() end)
        MakeCaption(f,"Known character on this realm",22,-44)
        f.nameInput=MakeInput(f,220,28,-64,"")
        f.nameInput:SetScript("OnTextChanged",function()
            C.PeerRefresh()
        end)
        f.knownButton=MakeButton(f,"Next known peer",160,380,-36,C.PeerChooseKnown)
        f.pairButton=MakeButton(f,"Pair",100,270,-64,C.LinkPair)
        f.rememberCheck=CreateFrame("CheckButton",nil,f,"UICheckButtonTemplate")
        f.rememberCheck:SetWidth(20); f.rememberCheck:SetHeight(20); f.rememberCheck:SetPoint("TOPLEFT",f,"TOPLEFT",22,-100)
        MakeCaption(f,"Remember this link for all characters on this account",48,-104)
        f.status=MakeCaption(f,"",22,-136); f.status:SetWidth(526); f.status:SetHeight(186); f.status:SetJustifyH("LEFT"); f.status:SetJustifyV("TOP")
        f.licenseButton=MakeButton(f,"Read peer licenses",160,380,-64,C.LicenseRefreshRemote)
        f.forgetButton=MakeButton(f,"Unlink character",144,22,-364,function() C.LinkForgetVisible(false) end)
        f.forgetAccountButton=MakeButton(f,"Forget account link",164,176,-364,function() C.LinkForgetVisible(true) end)
        f.cancelButton=MakeButton(f,"Cancel",100,350,-364,function()
            local endpoint=C.PeerVisibleEndpoint()
            if endpoint then C.SyncSelect(endpoint,false); C.PeerAbort("Cancelled locally; the peer will time out") end
        end)
        local help=MakeCaption(f,"Licenses are peer claims, not ownership proof. Accepting a link\nallows plan-scoped hiring and gold spending after Execute on the\ninitiating account. Opening SRB does not sync; use Refresh\nSynchronization to retry. Both peers need this version.",22,-408)
        help:SetWidth(526); help:SetHeight(56); help:SetJustifyH("LEFT")
        f:SetScript("OnHide",function()
            CloseChoiceMenu()
            local endpoint=C.PeerVisibleEndpoint()
            if not endpoint then return end
            -- Like builder close: established links survive; only pending pairing is cancelled.
            local session=C.SyncSelect(endpoint,false)
            if session and session.state.phase=="linked" then return end
            C.PeerAbort("Link panel closed; peer will time out")
        end)
        if C.peerState then
            C.linkUpdating=true; f.nameInput:SetText(C.peerState.peerLabel or C.peerState.peer); C.linkUpdating=nil
        elseif C.peerDraft then f.nameInput:SetText(C.peerDraft)
        end
    end
    C.peerPanel:Show(); EnsureEscapeWatcher(); escapeFrame:Show(); C.PeerRefresh()
end

SLASH_SHIRSRAIDBUILDERPEER1 = "/srbpeer"
SlashCmdList["SHIRSRAIDBUILDERPEER"] = C.OpenPeerPOC

local function CreateMain()
    EnsureDB()
    mainFrame=CreateFrame("Frame","ShirsRaidBuilderMainFrame",UIParent); mainFrame:SetWidth(780); mainFrame:SetHeight(640); mainFrame:SetPoint("CENTER",UIParent,"CENTER",0,0); mainFrame:SetFrameStrata("FULLSCREEN"); mainFrame:SetToplevel(true); mainFrame:SetMovable(true); mainFrame:EnableMouse(true); mainFrame:RegisterForDrag("LeftButton"); mainFrame:SetScript("OnDragStart",function() mainFrame:StartMoving() end); mainFrame:SetScript("OnDragStop",function() mainFrame:StopMovingOrSizing() end)
    mainFrame:SetBackdrop(PANEL_BG); mainFrame:SetBackdropColor(0.03, 0.04, 0.07, 1.0); mainFrame:SetBackdropBorderColor(0.70, 0.70, 0.70, 1.0)
    local title=mainFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight"); title:SetPoint("TOPLEFT",mainFrame,"TOPLEFT",310,-32); title:SetText("Shir's Raid Builder " .. C.VERSION)
    mainFrame.titleText = title
    MakeButton(mainFrame,"X",22,736,-8,function() mainFrame:Hide() end)
    MakeButton(mainFrame,"Link Account",100,22,-8,C.OpenPeerPOC)
    mainFrame.syncButton=MakeButton(mainFrame,"Refresh Synchronization",174,128,-8,C.SyncRefreshAll)
    mainFrame.groupActorsBtn=C.SetTip(MakeButton(mainFrame,"Hire status",100,310,-8,C.OpenHandoff),"Hire status","Shows the running Hire process. Cancel process discards groups not yet sent; a group already delivered to another account finishes there.")
    local drag=CreateFrame("Frame",nil,mainFrame); mainFrame.titleDrag=drag; drag:SetWidth(90); drag:SetHeight(24); drag:SetPoint("TOPLEFT",mainFrame,"TOPLEFT",414,-4); drag:EnableMouse(true); drag:SetScript("OnMouseDown",function() mainFrame:StartMoving() end); drag:SetScript("OnMouseUp",function() mainFrame:StopMovingOrSizing() end)
    MakeCaption(mainFrame, "Profile", 22, -32)
    presetButton=SelectButton(mainFrame,GetPresetNames(),DB.currentPreset,140,22,-48,function(v) SwitchPreset(v) end)
    C.SetTip(presetButton,"Profile","Hire mode and sort mode each have their own saved profiles.")
    mainFrame.shareButton=C.SetTip(MakeButton(mainFrame,"Share Current Plan",132,510,-8,C.OpenPlanShare),"Share Current Plan","Send the open plan to linked accounts. The receiver must approve a copy or merge; nothing is executed.")
    C.SetTip(MakeButton(mainFrame,"Import",76,648,-8,C.OpenPresetImport),"Import","Copy a saved profile into the current profile. Hire and sort profiles stay separate.")
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
    mainFrame.executeBtn=C.SetTip(MakeButton(mainFrame,"Execute",118,388,-76,C.HandStartHire),"Execute","Start this prepared plan once. Trusted linked accounts run only their assigned hires, in board order, after each prior step is submitted.")
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
    mainFrame.accountScroll=CreateFrame("ScrollFrame",nil,mainFrame)
    mainFrame.accountScroll:SetWidth(166); mainFrame.accountScroll:SetHeight(490); mainFrame.accountScroll:SetPoint("TOPLEFT",mainFrame,"TOPLEFT",22,-108)
    mainFrame.accountContent=CreateFrame("Frame",nil,mainFrame.accountScroll); mainFrame.accountContent:SetWidth(165); mainFrame.accountContent:SetHeight(490); mainFrame.accountRows={}
    mainFrame.accountScroll:SetScrollChild(mainFrame.accountContent); mainFrame.accountScroll:EnableMouseWheel(true)
    mainFrame.accountScroll:SetScript("OnMouseWheel",C.AccountWheel)
    mainFrame.accountContent:EnableMouseWheel(true); mainFrame.accountContent:SetScript("OnMouseWheel",C.AccountWheel)
    C.CreateAccountScrollTrack()
    compositionContent=CreateFrame("Frame",nil,mainFrame); compositionContent:SetWidth(550); compositionContent:SetHeight(490); compositionContent:SetPoint("TOPLEFT",mainFrame,"TOPLEFT",204,-108)
    statusText=mainFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); statusText:SetPoint("BOTTOMLEFT",mainFrame,"BOTTOMLEFT",22,16); statusText:SetWidth(430); statusText:SetJustifyH("LEFT"); statusText:SetTextColor(0.75,0.90,0.70)
    mainFrame.roleText=mainFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); mainFrame.roleText:SetPoint("BOTTOMRIGHT",mainFrame,"BOTTOMRIGHT",-24,16); mainFrame.roleText:SetWidth(300); mainFrame.roleText:SetJustifyH("RIGHT"); mainFrame.roleText:SetTextColor(0.85,0.88,0.70)
    mainFrame.roleText:SetText("Tank 0   Healer 0   Melee 0   Range 0")
    RefreshPresetButton(); RefreshComposition(); C.ApplyRaidMode(); EnsureEscapeWatcher(); mainFrame:SetScript("OnShow", function() if escapeFrame then escapeFrame:Show() end; C.ApplyRaidMode(); C.PeerOnBuilderOpen(true) end); mainFrame:Hide(); mainFrame:SetScript("OnHide", HideFloatingPanels)
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
    if command=="demo" then ShowDemo() elseif not mainFrame then CreateMain(); EnsureInviteListener(); mainFrame:Show() elseif mainFrame:IsShown() then mainFrame:Hide() else RefreshComposition(); EnsureInviteListener(); mainFrame:Show() end
end

local init=CreateFrame("Frame"); init:RegisterEvent("ADDON_LOADED"); init:RegisterEvent("VARIABLES_LOADED"); init:RegisterEvent("PLAYER_ENTERING_WORLD"); init:SetScript("OnEvent",function()
    if event == "ADDON_LOADED" and arg1 and arg1 ~= "ShirsRaidBuilder" then return end
    if event == "PLAYER_ENTERING_WORLD" then RememberPlayer(); C.PeerLogin(); if mainFrame then RefreshAccountPanel(); RefreshComposition() end; return end
    BindAccountDB(); EnsureDB()
    if event == "VARIABLES_LOADED" then RememberPlayer(); HarvestKnownFactions(); EnsureInviteListener(); DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffShir's Raid Builder:|r v" .. C.VERSION .. " loaded. Type /srb demo.") end
end)
