-- Whole-module import controls; synthetic Vanilla widgets, no real game/chat.
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
local function open(h)
    h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Import'))
    return h.env.ShirsRaidBuilderImport
end
local function profiles(h)
    local db=h.env.ShirsRaidBuilderDB
    db.presets.Older={entries={{kind='legacy',charName='Oldmage',class='mage',role='rdps',denyList={'Fireball'},setup={pet='imp'}}},denyRules={{class='mage',role='rdps',abilities={'Frostbolt'}}},setupRules={{class='mage',role='rdps',drink='30'}}}
    return db,db.presets.Default,db.presets.Older
end

test('select older preset, cancel warning, then overwrite independent copy',function()
    local h=boot(); local db,dest,src=profiles(h)
    local f=open(h)
    assert(f.sourceButton.options[1]=='Older' and table.getn(f.sourceButton.options)==1)
    assert(f.warningCheck:GetChecked()==1,'overwrite warning must default on')
    h:choose(f.sourceButton,'Older'); h:click(f.importButton)
    assert(db.presets.Default==dest and f.importButton.label:GetText()=='Overwrite','first click silently overwrites')
    assert(string.find(f.message:GetText(),'Default',1,true) and string.find(f.message:GetText(),'Older',1,true))
    h:click(h:button(f,'Cancel')); assert(db.presets.Default==dest)
    f=open(h); h:choose(f.sourceButton,'Older'); h:click(f.importButton); h:click(f.importButton)
    local copied=db.presets.Default
    assert(db.currentPreset=='Default' and copied~=dest and copied~=src and not f:IsShown())
    assert(copied.entries[1].charName=='Oldmage' and copied.denyRules[1].abilities[1]=='Frostbolt')
    copied.entries[1].denyList[1]='Changed'; copied.entries[1].setup.pet='changed'; copied.setupRules[1].drink='90'; copied.denyRules[1].abilities[1]='Changed'
    assert(src.entries[1].denyList[1]=='Fireball' and src.entries[1].setup.pet=='imp' and src.setupRules[1].drink=='30' and src.denyRules[1].abilities[1]=='Frostbolt','source shares nested tables')
end)

test('warning toggle persists per character and realm, can be restored',function()
    local h=boot(); local db=profiles(h); local f=open(h)
    f.warningCheck:SetChecked(nil); h:click(f.warningCheck)
    assert(db.importWarningHidden and db.importWarningHidden['fixturerealm:tester']==true,'suppression not saved')
    h:click(f.importButton); assert(not f:IsShown(),'suppressed warning still requires confirmation')
    local again=boot(db); f=open(again); assert(not f.warningCheck:GetChecked(),'suppression lost across session')
    again.env.UnitName=function() return 'Otherchar' end
    f=open(again); assert(f.warningCheck:GetChecked()==1,'other character inherited suppression')
    again.env.UnitName=function() return 'Tester' end
    again.env.GetRealmName=function() return 'Otherrealm' end
    f=open(again); assert(f.warningCheck:GetChecked()==1,'other realm inherited suppression')
    again.env.GetRealmName=function() return 'FixtureRealm' end
    f=open(again); f.warningCheck:SetChecked(1); again:click(f.warningCheck)
    assert(not db.importWarningHidden['fixturerealm:tester'],'warning cannot be restored')
    again:click(f.importButton); assert(f:IsShown() and f.importButton.label:GetText()=='Overwrite')
    assert(again.C.ShouldShowCaptureWarning(db,'Tester','FixtureRealm'),'import changed capture warning')
end)

test('all saved profiles remain reachable through bounded pages',function()
    local h=boot(); local db=profiles(h)
    for i=1,24 do db.presets[string.format('Saved%02d',i)]={entries={},denyRules={},setupRules={}} end
    local f=open(h); local seen={}
    repeat
        assert(table.getn(f.sourceButton.options)<=8,'import dropdown exceeds bounded page')
        for _,name in ipairs(f.sourceButton.options) do seen[name]=true end
        if not f.nextButton:IsEnabled() then break end
        h:click(f.nextButton)
    until false
    assert(seen.Older and seen.Saved24 and not seen.Default)
    local count=0; for _ in pairs(seen) do count=count+1 end; assert(count==25)
    h:choose(f.sourceButton,'Saved24'); h:click(f.importButton); h:click(f.importButton)
    assert(db.currentPreset=='Default' and not f:IsShown())
end)

test('sort import stays in sort bank and stale destination fails closed',function()
    local h=boot(); local db,hire=profiles(h)
    db.sortPresets.Oldsort={entries={{kind='player',charName='Tester',role='tank'}},denyRules={},setupRules={},sortLayout=true}
    h.C.ToggleRaidMode(); local f=open(h)
    assert(table.getn(f.sourceButton.options)==1 and f.sourceButton.options[1]=='Oldsort')
    h:click(f.importButton); h:click(f.importButton)
    assert(db.sortPresets.Default.sortLayout==true and db.presets.Default==hire and db.currentSortPreset=='Default')
    h.C.ToggleRaidMode(); f=open(h); h:click(f.importButton)
    db.currentPreset='Older'; h:click(f.importButton)
    assert(db.presets.Default==hire and not f:IsShown(),'stale current profile overwritten')
end)

test('source deletion, replacement and mode change cancel pending import',function()
    for _,change in ipairs({'delete','replace','mode'}) do
        local h=boot(); local db,dest=profiles(h); local f=open(h); h:click(f.importButton)
        if change=='delete' then db.presets.Older=nil elseif change=='replace' then db.presets.Older={} else h.C.ToggleRaidMode() end
        h:click(f.importButton); assert(db.presets.Default==dest and not f:IsShown())
    end
end)

test('empty list, Escape and main close are non-destructive',function()
    local h=boot(); local f=open(h); assert(not f.importButton:IsEnabled())
    assert(f:GetFrameStrata()=='FULLSCREEN_DIALOG' and f.topLevel)
    local db,dest=profiles(h); f=open(h); h:click(f.importButton)
    h.env.ShirsRaidBuilderEscaper:Hide(); assert(not f:IsShown() and db.presets.Default==dest)
    f=open(h); h:click(f.sourceButton); h.env.ShirsRaidBuilderMainFrame:Hide()
    assert(not f:IsShown() and not h.env.ShirsRaidBuilderChoiceMenu:IsShown())
end)

test('invalid suppression and missing identity retain warning',function()
    local h=boot(); local db=profiles(h)
    db.importWarningHidden={['fixturerealm:tester']=1}; local f=open(h); assert(f.warningCheck:GetChecked())
    h.env.UnitName=function() return nil end; f=open(h); f.warningCheck:SetChecked(nil); h:click(f.warningCheck)
    assert(f.warningCheck:GetChecked() and not db.importWarningHidden[''])
    h:click(f.importButton); assert(f.importButton.label:GetText()=='Overwrite')
end)

test('core rejects absent, self and wrong-mode sources without mutation',function()
    local h=boot(); local db,dest=profiles(h)
    assert(not h.C.ImportPreset(db,'hire','Default','Default'))
    assert(not h.C.ImportPreset(db,'hire','Missing','Default'))
    assert(not h.C.ImportPreset(db,'invalid','Older','Default'))
    assert(not h.C.ImportPreset(db,'sort','Older','Default'))
    assert(db.presets.Default==dest)
end)

test('New then Import preserves the new name and the old profile',function()
    local h=boot(); local db,old=profiles(h)
    h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'New'))
    local prompt=h.env.ShirsRaidBuilderNamePrompt; prompt.input:SetText('Profile 1'); h:click(h:button(prompt,'Save'))
    assert(db.currentPreset=='Profile 1')
    local f=open(h); h:choose(f.sourceButton,'Older'); h:click(f.importButton); h:click(f.importButton)
    assert(db.currentPreset=='Profile 1' and db.presets.Default==old and db.presets['Profile 1'].entries[1].charName=='Oldmage')
end)

test('busy sort blocks open and a run started during confirmation blocks overwrite',function()
    local h=boot(); local db,dest=profiles(h)
    h.C.sortFrame={busy=true}; h.C.OpenPresetImport(); assert(not h.C.importFrame)
    h.C.sortFrame.busy=nil; local f=open(h); h:click(f.importButton)
    h.C.sortFrame.busy=true; h:click(f.importButton)
    assert(not f:IsShown() and db.presets.Default==dest)
end)

test('import header button stays outside title drag strip and other controls',function()
    local h=boot(); local main=h.env.ShirsRaidBuilderMainFrame; local b=h:button(main,'Import')
    assert(b.point[4]==648 and b.point[5]==-8 and b:GetWidth()==76 and b:GetHeight()==22)
    local close=h:button(main,'X'); assert(b.point[4]+b:GetWidth()<close.point[4])
end)

print('Preset import tests: '..passes..' PASS, '..failures..' FAIL')
assert(failures==0,'preset import regression failures')
print("Shir's Raid Builder preset import tests: PASS")
