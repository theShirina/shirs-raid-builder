-- Regression contract: sorting belongs only to Sort mode.
local path = "../addon/ShirsRaidBuilder/ShirsRaidBuilder.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local finishStart = assert(string.find(source, "local function FinishExecute", 1, true))
local finishStop = assert(string.find(source, "local function StopQueue", finishStart, true))
local finishBody = string.sub(source, finishStart, finishStop - 1)

assert(not string.find(finishBody, "StartRaidSort", 1, true), "hire execution must not start raid sorting")
assert(string.find(source, "showBtn(mainFrame.sortBtn, sort)", 1, true), "Sort button must be visible only in Sort mode")
assert(string.find(source, "local function StartRaidSort", 1, true), "Sort mode must retain the paced raid sorter")
assert(string.find(source, "mainFrame.sortBtn", 1, true), "Sort mode must retain its Sort action")
assert(not string.find(source, "then legacy overwrite, then sort the raid", 1, true), "Hire Execute tooltip must not promise sorting")

local panelStart = assert(string.find(source, "local function StylePanelFrame", 1, true))
local panelStop = assert(string.find(source, "local function RegisterEscapeFrame", panelStart, true))
local panelBody = string.sub(source, panelStart, panelStop - 1)
assert(string.find(panelBody, "frame:EnableMouse(true)", 1, true), "submenu panels must retain mouse capture for their controls")
assert(string.find(panelBody, "frame.dragBar = CreateFrame(\"Frame\", nil, frame)", 1, true), "submenu panels must have a dedicated title drag strip")
assert(string.find(panelBody, 'frame.dragBar:RegisterForDrag("LeftButton")', 1, true), "submenu dragging must require an explicit drag gesture")
assert(string.find(panelBody, 'frame.dragBar:SetScript("OnDragStart"', 1, true), "submenu drag strip must start moving")
assert(string.find(panelBody, 'frame.dragBar:SetScript("OnDragStop"', 1, true), "submenu drag strip must stop moving")
assert(string.find(panelBody, 'frame.dragBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -4)', 1, true), "submenu drag strip must leave room for the close button")
assert(not string.find(panelBody, 'frame:SetScript("OnMouseDown"', 1, true), "submenu background clicks must not start moving")
assert(not string.find(panelBody, 'frame:SetScript("OnMouseUp"', 1, true), "submenu background clicks must not stop a hidden drag")
assert(not string.find(panelBody, "dragHandle", 1, true), "submenu movement must use the shared drag strip")
assert(string.find(source, 'mainFrame:RegisterForDrag("LeftButton")', 1, true), "the main panel must be draggable")
assert(string.find(source, 'MakeButton(mainFrame,"New",88,168,-48', 1, true), "New must use the shared top-row grid")
assert(string.find(source, 'MakeButton(mainFrame,"Rename",88,260,-48', 1, true), "Rename must use the shared top-row grid")
assert(string.find(source, 'MakeButton(mainFrame,"Delete",88,352,-48', 1, true), "Delete must use the shared top-row grid")
assert(string.find(source, 'MakeButton(mainFrame,"Add Normal",88,444,-48', 1, true), "Add Normal must align to top-row slot four")
assert(string.find(source, 'MakeButton(mainFrame,"Add Legacy",88,536,-48', 1, true), "Add Legacy must align to top-row slot five")
assert(string.find(source, 'MakeButton(mainFrame,"Capture",88,444,-48', 1, true), "Capture must share Add Normal geometry")
assert(string.find(source, 'MakeButton(mainFrame,"Save",88,536,-48', 1, true), "Save must share Add Legacy geometry")
assert(string.find(source, 'MakeButton(mainFrame,"Sort Mode",88,628,-48', 1, true), "Mode switch must use top-row slot six")
assert(string.find(source, 'MakeButton(mainFrame,"Deny Rules",118,22,-76', 1, true), "bottom-row buttons must share one width")
assert(string.find(source, 'MakeButton(mainFrame,"Other Commands",118,144,-76', 1, true), "Other Commands must align to bottom-row slot two")
assert(string.find(source, 'MakeButton(mainFrame,"Preview",118,266,-76', 1, true), "Preview must align to bottom-row slot three")
assert(string.find(source, 'MakeButton(mainFrame,"Execute",118,388,-76', 1, true), "Execute must align to bottom-row slot four")
assert(string.find(source, 'MakeButton(mainFrame,"Whispers",118,388,-76', 1, true), "Whispers must share Execute geometry")
assert(string.find(source, 'MakeButton(mainFrame,"Stop",118,510,-76', 1, true), "Stop must align to bottom-row slot five")
assert(string.find(source, 'MakeButton(mainFrame,"Sort",118,632,-76', 1, true), "Sort must align to bottom-row slot six")
assert(string.find(source, 'MakeButton(mainFrame,"Capture",88,444,-48,C.RequestCaptureLayout)', 1, true), "Capture must route through overwrite confirmation")
assert(string.find(source, "This will overwrite the current sort profile", 1, true), "Capture confirmation must name the destructive effect")
assert(string.find(source, "Don't show this warning again for this character", 1, true), "Capture confirmation must offer a per-character opt-out")
assert(string.find(source, "C.PlanRaidOrderSwaps", 1, true), "Sort mode must check exact within-group order")
assert(string.find(source, "C.PlanRaidOrderRebuild", 1, true), "Sort mode must stage a wrong subgroup through an empty buffer")
assert(string.find(source, "SetRaidSubgroup(row.index, action.group)", 1, true), "Sort mode must execute each staged slot-order action by fresh name lookup")
assert(string.find(source, "orderActionAttempts > 3", 1, true), "Sort mode must bound failed staged actions")
assert(string.find(source, "orderProcessed", 1, true), "Sort mode must mark one completed pass and continue to later groups")
assert(string.find(source, 'return "order-partial"', 1, true), "Sort mode must report partial exact ordering after checking every group")
assert(string.find(source, 'line1:SetText(tostring(spawnNumber) .. " " .. name)', 1, true), "slot number and name must share one text run so low UI scales cannot overlap them")
assert(string.find(source, 'C.FitCardLine(line2, row.tierText, CLASS_LABELS[classKey] or classKey, ROLE_SHORT[entry.role] or entry.role or "")', 1, true)
    and string.find(source, 'line:SetText(cut .. " " .. role)', 1, true), "class and role must use the narrow single-space card label")
assert(string.find(source, 'b:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)', 1, true), "context buttons must chain from the prior button for stable low-scale spacing")
assert(string.find(source, 'if type(DB.characterRoles) ~= "table" then DB.characterRoles = {} end', 1, true), "account DB must retain player roles by character")
assert(string.find(source, 'C.RememberCharacterRole(DB.characterRoles, live.charName, live.class, value)', 1, true), "changing a player role must persist it by character")
assert(string.find(source, 'C.RememberedCharacterRole(DB.characterRoles, you, class)', 1, true), "board refresh must restore the current character role")
assert(string.find(source, 'local function RefreshAbilitySuggestions(input, class, role)', 1, true), "deny autocomplete must receive both class and role")
assert(string.find(source, 'if role ~= "all" and not C.RoleAllowedForClass(class, role) then return end', 1, true), "deny autocomplete must reject invalid class-role pairs")
assert(string.find(source, '{"All Roles","Tank","Healer","Ranged DPS","Melee DPS"}', 1, true), "deny rules must offer a class-wide All Roles scope")
assert(string.find(source, "function C.ResetDenyRuleEditor", 1, true), "deny rules need one shared fresh-rule reset")
assert(not string.find(source, "settingsRuleIndex", 1, true), "deny editor must not keep a hidden edit target; the dropdowns alone decide where Add writes")
assert(string.find(source, "FindDenyRule(p.denyRules, role, class)", 1, true), "ability suggestions must follow the current dropdown selection")
assert(string.find(source, "function C.FindDenyRule", 1, true) or string.find(source, "C.FindDenyRule", 1, true), "deny rules must be found by role+class values resolved from the dropdowns")
assert(string.find(source, "FindDenyRule(EnsureDB().denyRules, role, class)", 1, true), "ability suggestions must follow the current dropdown selection")
local addStart = assert(string.find(source, 'local addAbility=MakeButton(settingsFrame,"Add Ability",86,214,-106,function()', 1, true))
local addStop = assert(string.find(source, "        end)", addStart, true))
local addBody = string.sub(source, addStart, addStop)
assert(string.find(addBody, "RoleValue(settingsRoleButton.label:GetText())", 1, true), "Add Ability must read Role from the dropdown at click time")
assert(string.find(addBody, "ClassValue(settingsClassButton.label:GetText())", 1, true), "Add Ability must read Class from the dropdown at click time")
assert(string.find(addBody, "C.RoleAllowedForClass(class,role)", 1, true), "Add Ability must reject invalid class-role pairs instead of creating unreachable rules")
assert(string.find(addBody, "FindDenyRule(p.denyRules, role, class)", 1, true), "Add Ability must append to the exact role+class rule or create it")
assert(not string.find(addBody, ".role=", 1, true), "adding an ability must never re-key an existing rule to a new role or class")
local denyRemoveStart = assert(string.find(source, 'MakeButton(row,"Remove",64,296,0,function()', 1, true))
local denyRemoveStop = assert(string.find(source, "        end)", denyRemoveStart, true))
local denyRemoveBody = string.sub(source, denyRemoveStart, denyRemoveStop)
assert(string.find(denyRemoveBody, "all[ri]==rule", 1, true), "deny Remove must match the rule by identity, not row position")
assert(string.find(denyRemoveBody, "table.remove(all,ri)", 1, true), "deny Remove must delete only its own rule")
assert(string.find(denyRemoveBody, "C.ResetDenyRuleEditor()", 1, true), "removing a deny rule must immediately enter fresh-rule mode")
assert(string.find(source, 'MakeButton(settingsFrame,"New",64,18,14,C.ResetDenyRuleEditor,true)', 1, true), "New and Remove must use the same deny editor reset")
assert(string.find(source, "C.AppendLegacyGroupMembers(C.KeepPresentCompanions(executeCompanionList, present), plan.entries, present)", 1, true), "group commands must include legacy board members the server companion list omits")
assert(string.find(source, "C.latestCompanionList = companions", 1, true), "GRINFO replies must be cached even before execution starts")
assert(string.find(source, "C.InfoCoversGroup", 1, true), "cached GRINFO data must be checked against the current group")
local cachePosition = assert(string.find(source, "C.latestCompanionList = companions", 1, true))
local idleReturnPosition = assert(string.find(source, "if (not executing) and (not C.sortWaiting) then return end", 1, true))
assert(cachePosition < idleReturnPosition, "GRINFO replies must be cached before idle execution returns")
assert(string.find(source, "executeGrinfoReady = false", 1, true), "a hire must invalidate the previous companion list before group expansion")
assert(string.find(source, "function C.EnsureDenyListScroll(host, spec)", 1, true), "deny lists share one five-row scroll factory")
assert(string.find(source, "if C.DenyListNeedsScrollbar(count) and (not spec.minScrollCount or count >= spec.minScrollCount) then", 1, true), "deny lists retain the five-item default; legacy names may request six")
assert(string.find(source, "C.EnsureDenyListScroll(denyFrame", 1, true), "extra denies must use the five-row viewport")
assert(string.find(source, "C.EnsureDenyListScroll(settingsFrame", 1, true), "deny rules must use the five-row viewport")
assert(string.find(source, "C.DENY_LIST_VISIBLE_ROWS", 1, true), "deny list height must stay pinned to five visible rows")
assert(string.find(source, 'if type(ShirsRaidBuilderDB) ~= "table" then ShirsRaidBuilderDB = {} end', 1, true), "BindAccountDB must create the SavedVariable global, never return without binding; a missing global means logout saves nil and profiles vanish")

-- Execute the actual account renderer with only its surrounding UI dependencies stubbed.
do
    dofile("../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua")
    local C = ShirsRaidBuilderCore
    local first = assert(string.find(source, "function C.AccountScroll(value)", 1, true))
    local last = assert(string.find(source, "CloseContext = function()", first, true))
    local body = string.sub(source, first, last-1)
    local collectStart=assert(string.find(source,'function C.AccountReadLocal(records)',1,true))
    local collectEnd=assert(string.find(source,'function C.LicenseSidebar(y)',collectStart,true))
    body=string.sub(source,collectStart,collectEnd-1)..body
    local function widget(parent)
        local w = {parent=parent, fonts={}, scripts={}, shown=true}
        function w:SetWidth(v) self.width=v end
        function w:SetHeight(v) self.height=v end
        function w:GetHeight() return self.height or 490 end
        function w:ClearAllPoints() self.point=nil end
        function w:EnableMouseWheel(v) self.wheel=v end
        function w:GetVerticalScroll() return self.scroll or 0 end
        function w:SetVerticalScroll(v) self.scroll=v end
        function w:SetPoint(...) self.point=arg end
        function w:SetText(v) self.text=v end
        function w:GetStringWidth() return string.len(self.text or "")*6 end
        function w:SetTextColor(...) end
        function w:SetJustifyH(v) self.justify=v end
        function w:SetScript(k,v) self.scripts[k]=v end
        function w:Hide() self.shown=false end
        function w:Show() self.shown=true end
        function w:SetParent(v) self.parent=v end
        function w:CreateFontString()
            local f=widget(self); table.insert(self.fonts,f); return f
        end
        return w
    end
    local content = widget()
    local frame = {accountContent=content,accountScroll=widget()}
    local db = {uiMode="hire", inviteCharacters={
        Alpha={name="Alpha",level=60,raidLicense="t4r",dungeonLicense="t2d"},
        Beta={name="Beta",level=60,raidLicense="t2r",dungeonLicense="none"},
        Gamma={name="Gamma",level=60,raidLicense="t1r",dungeonLicense="t1d"},
        Unknown={name="Unknown",level=60}, Young={name="Young",level=59}}}
    C.LinkNonce=function() return '1234567890123456' end
    local preset = {entries={{kind="normal",account="Alpha"}}}
    local status
    local env = {C=C, DB=db, mainFrame=frame,
        EnsureDB=function() return preset end,
        DiscoverCharacterNames=function() return {"Unknown", "Gamma", "Beta", "Alpha"} end,
        CreateFrame=function(kind,name,parent) return widget(parent) end,
        GetRealmName=function() return "Realm" end,
        UnitName=function() return "Alpha" end, UnitLevel=function() return 60 end,
        time=function() return 1800000000 end,
        SetStatus=function(v) status=v end}
    setmetatable(env, {__index=_G})
    local chunk=assert(loadstring(body, "account renderer")); setfenv(chunk,env); chunk()
    local function refresh() env.RefreshAccountPanel(); return frame.accountRows end
    local rows=refresh()
    assert(table.getn(rows)==4 and rows[1].lines[1].text=="Alpha - T4R")
    assert(table.getn(rows[1].fonts)==3 and rows[1].lines[2].text=="", "two text lines plus the count region")
    assert(rows[1].fonts[3]==rows[1].countText, "count is the third FontString")
    assert(rows[2].lines[1].text=="Beta - T2R")
    assert(rows[1].countText.text=="1/4", "Alpha has one normal hire in the preset")
    assert(rows[2].countText.text=="0/4", "Beta has zero normal hires in the preset")
    assert(rows[1].lines[1].width==153-rows[1].countText:GetStringWidth()-6, "title width must leave room for the measured count")
    assert(rows[1].height==20 and rows[4].height==20, "unknown licenses retain compact rows")
    local sep=string.char(31)
    local function state(names)
        local instances={}
        for _,name in ipairs(names) do table.insert(instances,{name=name,id="42",readyAt=1800000100}) end
        return {raidInfo={known=true,observedAt=1800000000,instances=instances}}
    end
    local provider={cooldownsByCharacter={
        ["Realm"..sep.."Alpha"]=state({"Naxxramas","Ahn'Qiraj Temple","Blackwing Lair","Molten Core"}),
        ["Realm"..sep.."Beta"]=state({"Molten Core"}),
        ["Realm"..sep.."Gamma"]=state({"Zul'Gurub"}),
        ["Realm"..sep.."Unknown"]=state({"Blackwing Lair"}),
        ["Foreign"..sep.."Gamma"]=state({"Naxxramas"})}}
    C.mcpRealm='Realm'; C.mcpRows={}
    for key,value in pairs(provider.cooldownsByCharacter) do
        local _,_,character=string.find(key,'^Realm'..sep..'(.+)$')
        if character then C.mcpRows[string.lower(character)]={known=true,observed=value.raidInfo.observedAt,entries=value.raidInfo.instances} end
    end
    rows=refresh()
    assert(rows[1].lines[2].text=="MC BWL AQ40 NAXX", "confirmed saves render in one second line")
    assert(rows[2].lines[2].text=="MC", "each character renders its own saves")
    assert(rows[3].lines[2].text=="" and rows[3].height==20, "no confirmed saves keeps baseline row")
    assert(rows[4].lines[2].text=="BWL", "missing license still shows confirmed saves")
    assert(rows[1].lines[1].text=="Alpha - T4R")
    for _,i in ipairs({1,2,4}) do
        local row=rows[i]
        local raid=row.lines[2]; local preceding=row.lines[1]
        assert(raid.parent==row and raid.point[2]==row and raid.point[1]=="TOPLEFT")
        assert(preceding.point[1]=="TOPLEFT" and raid.point[5] <= preceding.point[5]-14, "raid text must sit below prior line")
        assert(raid.width and raid.width+raid.point[4]<=row.width, "raid line must stay inside row width")
        assert(-raid.point[5]+12<=row.height, "row must enclose last text line")
        if rows[i+1] then assert(rows[i+1].point[5] <= row.point[5]-row.height-2, "next row must not overlap") end
    end
    assert(content.height>=-rows[4].point[5]+rows[4].height, "content must reach the last row")
    rows[1].scripts.OnClick()
    assert(status=="Alpha has 1 hire(s) in this preset.", "row click semantics stay unchanged")
    local old=rows
    C.mcpRows.alpha.entries={}
    rows=refresh()
    assert(rows[1].lines[2].text=="" and rows[1].height==20, "refresh removes stale raid text and extra height")
    for i,row in ipairs(old) do assert(row==rows[i] and row.parent==content, "refresh reuses the same bounded row pool") end
    db.uiMode="sort"; refresh(); assert(not content.shown, "Sort mode hides all account labels")
    db.uiMode="hire"; C.mcpRows=nil; rows=refresh()
    assert(content.shown and rows[2].lines[2].text=="MC" and rows[4].height==34, "provider absence preserves saved observations")
    env.ShirsLazyTrixDB=provider; env.time=nil; rows=refresh()
    assert(rows[2].lines[2].text=="", "missing clock must not guess saved status")
    assert(provider.cooldownsByCharacter["Realm"..sep.."Beta"].raidInfo.instances[1].readyAt==1800000100)
    assert(not string.find(body,"SendChatMessage",1,true) and not string.find(body,"RequestRaidInfo",1,true), "rendering must not query or send")
end

do
    local first = assert(string.find(source, "-- Account link adapter.", 1, true))
    local last = assert(string.find(source, "local function CreateMain()", first, true))
    local peer = string.sub(source, first, last - 1)
    -- v2 reads the local license list; remove only that exact read from the
    -- action denylist scan, not a broad '.z add' or SAY exemption.
    local guarded=string.gsub(peer,'pcall%(SendChatMessage,"%.z addinvite list","SAY"%)','LOCAL_READ')
    guarded=string.gsub(guarded,'pcall%(SendChatMessage,command,"SAY"%)','MCP_READ')
    local handStart=assert(string.find(guarded,"-- Durable handoffs carry a frozen board",1,true))
    local handEnd=assert(string.find(guarded,"function C.OpenPeerPOC()",handStart,true))
    guarded=string.sub(guarded,1,handStart-1)..string.sub(guarded,handEnd)
    for _, forbidden in ipairs({"ExecuteQueue", "BuildQueue", "SendQueueEntry", "SendAddonMessage", ".z add", "deny add", '"SAY"', "DB.presets ="}) do
        assert(not string.find(guarded, forbidden, 1, true), "peer adapter crosses advisory-only boundary: " .. forbidden)
    end
    assert(string.find(peer, 'pcall(SendChatMessage, packet, "WHISPER", nil, s.peer)', 1, true))
    assert(not string.find(peer, '"Execute"', 1, true), "no remote Execute control")
    assert(string.find(source, "local HIRE_DELAY_MIN = 7.5", 1, true))
    assert(string.find(source, "local HIRE_DELAY_MAX = 8.5", 1, true))
    assert(string.find(source, "local WHISPER_GAP_SECONDS = 0.7", 1, true))
end

print("Shir's Raid Builder mode contract tests: PASS")
