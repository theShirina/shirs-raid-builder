-- Real Add callback in the whole-module Vanilla widget harness; no live UI proof.
local file=assert(io.open('test_individual_editor.lua','r'))
local fixture=file:read('*a'); file:close()
local boundary=assert(string.find(fixture,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(fixture,1,boundary-1)..'\nreturn boot'))()
local failures,passes=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passes=passes+1; print('PASS '..name)
    else failures=failures+1; print('FAIL '..name..': '..tostring(err)) end
end
local function open()
    local h=boot({presets={}})
    h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Add Legacy'))
    return h,h.env.ShirsRaidBuilderAddLegacy
end
local function count(h)
    local n=0
    for _,entry in pairs(h:preset().entries) do if entry.kind=='legacy' then n=n+1 end end
    return n
end
local function snapshot(value)
    if type(value)~='table' then return type(value)..':'..tostring(value) end
    local parts={}
    for k,v in pairs(value) do table.insert(parts,snapshot(k)..'='..snapshot(v)) end
    table.sort(parts); return '{'..table.concat(parts,',')..'}'
end
for _,name in ipairs({'Caster','cAsTeR'}) do
    local duplicate=name
    test('reject duplicate without mutating input selection or saved state: '..duplicate,function()
        local h,f=open(); f.nameInput:SetText('Caster')
        h:choose(f.roleButton,'Healer'); h:choose(f.classButton,'Priest'); h:click(f.addButton)
        local original=h:entry('Caster')
        f.nameInput:SetText(duplicate)
        h:choose(f.roleButton,'Healer')
        f.nameInput:SetFocus()
        local menu=h.env.ShirsRaidBuilderLegacyNameMenu
        local visible=menu and menu:IsVisible()
        local edited,roleEdited=f.legacyEditedName,f.legacyRoleEditedName
        local before=snapshot(h.env.ShirsRaidBuilderDB)
        h:click(f.addButton)
        assert(count(h)==1,'duplicate legacy inserted')
        assert(h:entry('Caster')==original and snapshot(h.env.ShirsRaidBuilderDB)==before,'existing entry or saved data changed')
        assert(f.nameInput:GetText()==duplicate and f.nameInput:HasFocus(),'input lost')
        assert(f.roleButton.label:GetText()=='Healer' and f.classButton.label:GetText()=='Priest','selection lost')
        assert(f.legacyEditedName==edited and f.legacyRoleEditedName==roleEdited,'manual selection identity lost')
        assert((menu and menu:IsVisible())==visible and f:IsVisible(),'panel or suggestion state changed')
        local found=false
        for _,w in ipairs(h.frames) do if w.kind=='FontString' and w:GetText()==duplicate..' is already in this hiring plan.' then found=true end end
        assert(found,'duplicate rejection status missing')
        f.nameInput:SetText('Othercaster'); h:click(f.addButton)
        assert(count(h)==2 and h:entry('Othercaster'),'distinct add after rejection failed')
        assert(f.nameInput:GetText()=='' and not menu:IsVisible() and f:IsVisible(),'successful field reset changed')
    end)
end

test('source identity wins over display name role class and whisper target',function()
    local h,f=open()
    h:preset().entries[35]={kind='legacy',sourceName='Longname',charName='Other-lite',whisperName='Elsewhere',class='warrior',role='tank',denyList={}}
    f.nameInput:SetText('LONGNAME'); h:click(f.addButton)
    assert(count(h)==1,'source identity duplicate inserted at sparse slot')
end)
test('older charName identity is rejected without a sourceName',function()
    local h,f=open()
    h:preset().entries[35]={kind='legacy',charName='Oldername',class='warrior',role='tank'}
    f.nameInput:SetText('olderNAME'); h:click(f.addButton)
    assert(count(h)==1,'older identity duplicate inserted')
end)
test('distinct real names sharing the same derived whisper suffix remain valid',function()
    local h,f=open()
    for _,name in ipairs({'Longname','Longnamer'}) do f.nameInput:SetText(name); h:click(f.addButton) end
    assert(count(h)==2,'distinct real identities conflated')
    assert(h:entry('Longname').whisperName==h:entry('Longnamer').whisperName)
    assert(f.nameInput:GetText()=='','successful add did not clear field')
end)
test('normal hires and other profiles do not block the current profile',function()
    local h,f=open()
    h:preset().entries[1]={kind='normal',account='Caster',charName='Caster',class='warrior',role='tank'}
    h.env.ShirsRaidBuilderDB.presets.Other={entries={{kind='legacy',charName='Caster',class='mage',role='rdps'}}}
    f.nameInput:SetText('Caster'); h:click(f.addButton)
    assert(count(h)==1 and h:preset().entries[1].kind=='normal')
end)
print('Legacy duplicate tests: '..passes..' PASS, '..failures..' FAIL')
assert(failures==0,'legacy duplicate regression failures')
print("Shir's Raid Builder legacy duplicate tests: PASS")
