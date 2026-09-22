-- Reuse the whole-module widget harness without running its individual tests.
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
    h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Add Legacy'))
    return h.env.ShirsRaidBuilderAddLegacy
end

test('saved invite class fills the real legacy editor and Add entry',function()
    local h=boot({inviteCharacters={Caster={name='Caster',class='mage',level=60}},presets={}})
    local f=open(h); f.nameInput:SetText('cAsTeR')
    assert(f.classButton.label:GetText()=='Mage','saved class was not reused')
    assert(f.roleButton.label:GetText()=='Ranged DPS','class and role disagree')
    h:click(f.addButton)
    local e=h:entry('cAsTeR'); assert(e.class=='mage' and e.role=='rdps')
    assert(h.C.BuildHireCommand(e)=='.z addlegacy "Caster" rdps',tostring(h.C.BuildHireCommand(e)))
end)
test('manual legacy class survives a new addon session',function()
    local h=boot(); local f=open(h); f.nameInput:SetText('Healone')
    h:choose(f.roleButton,'Healer'); h:choose(f.classButton,'Priest'); h:click(f.addButton)
    local saved=h.env.ShirsRaidBuilderDB
    assert(saved.legacyCharacters and saved.legacyCharacters.healone=='priest','manual class not saved')
    local again=boot(saved); local g=open(again); g.nameInput:SetText('HEALONE')
    assert(g.classButton.label:GetText()=='Priest','manual class not restored')
    again:choose(g.roleButton,'Healer')
    assert(g.classButton.label:GetText()=='Priest','role change discards known class')
end)

test('legacy list request and event save class without hiring',function()
    local h=boot(); local clock=100; local sent={}
    h.env.GetTime=function() return clock end
    h.env.SendChatMessage=function(message,channel) table.insert(sent,{message,channel}) end
    local f=open(h); f.nameInput:SetText('Fetchmage')
    clock=101
    for _,w in ipairs(h.frames) do if w.scripts.OnUpdate then h:fire(w,'OnUpdate',1) end end
    assert(table.getn(sent)==1 and sent[1][1]=='.z addlegacy list' and sent[1][2]=='SAY','missing bounded legacy list request')
    h.env.event='CHAT_MSG_MONSTER_WHISPER'; h.env.arg2='nexus'
    for _,w in ipairs(h.frames) do
        if w.events.CHAT_MSG_MONSTER_WHISPER then h:fire(w,'OnEvent','[nexus] ACINFO:LEGACY:LIST Fetchmage:Mage:0 Fetchpriest:Priest:1') end
    end
    assert(h.env.ShirsRaidBuilderDB.legacyCharacters.fetchmage=='mage','legacy reply not saved')
    assert(h.env.ShirsRaidBuilderDB.legacyCharacters.fetchpriest=='priest','hired flag must not discard class')
    assert(f.classButton.label:GetText()=='Mage','open editor not refreshed')
    local again=boot(h.env.ShirsRaidBuilderDB); local g=open(again); g.nameInput:SetText('FETCHMAGE')
    assert(g.classButton.label:GetText()=='Mage','fetched class did not survive restart')
end)

test('old saved legacy entries supply class without changing the profile',function()
    local h=boot(); local f=open(h); f.nameInput:SetText('Othermag')
    assert(f.classButton.label:GetText()=='Mage','saved legacy entry ignored')
    assert(h:entry('Othermag').spec=='fire')
end)

test('late replies do not undo a manual class correction',function()
    local h=boot({inviteCharacters={Healone={name='Healone',class='shaman'}},presets={}})
    local f=open(h); f.nameInput:SetText('Healone')
    h:choose(f.roleButton,'Healer'); h:choose(f.classButton,'Priest')
    h.env.event='CHAT_MSG_ADDON'
    for _,w in ipairs(h.frames) do
        if w.events.CHAT_MSG_ADDON then h:fire(w,'OnEvent','[nexus] ACINFO:LEGACY:LIST Healone:Shaman:0') end
    end
    assert(f.classButton.label:GetText()=='Priest','late reply overwrote visible choice')
    h:click(f.addButton); assert(h:entry('Healone').class=='priest')
end)

test('invite event keeps class after a later empty invite list',function()
    local h=boot(); local f=open(h); f.nameInput:SetText('Freshmage')
    h.env.event='CHAT_MSG_ADDON'; h.env.arg2=''
    local listener
    for _,w in ipairs(h.frames) do if w.events.CHAT_MSG_MONSTER_WHISPER then listener=w end end
    h:fire(listener,'OnEvent','[nexus] ACINFO:INVITE:LIST Freshmage:Mage:t1:t1:A:0:60:0:4:0')
    assert(f.classButton.label:GetText()=='Mage','invite response did not refresh class')
    h:fire(listener,'OnEvent','[nexus] ACINFO:INVITE:LIST invalid')
    assert(h.C.LegacyCharacterClass(h.env.ShirsRaidBuilderDB,'Freshmage')=='mage','invite refresh erased class')
end)

test('malformed data and full-name collisions fail closed',function()
    local h=boot(); local C=h.C; local db={}
    local bad={'[nexus] ACINFO:LEGACY:LIST A:Mage:0 Bad:Monk:0 Foo:Mage:8 Bad-name:Mage:0 Xxxxxxxxxxxxx:Mage:0 xxGood:Mage:0oops',
        'ACINFO:LEGACY:LIST Plain:Mage:0','[other] ACINFO:LEGACY:LIST Other:Mage:0','prefix [nexus] ACINFO:LEGACY:LIST Inject:Mage:0'}
    for _,raw in ipairs(bad) do C.StoreLegacyCharacterList(db,raw) end
    assert(db.legacyCharacters==nil,'malformed record accepted')
    C.StoreLegacyCharacterList(db,'[nexus] ACINFO:LEGACY:LIST Longname:Mage:0 Longnamer:Priest:1')
    assert(C.LegacyCharacterClass(db,'longname')=='mage' and C.LegacyCharacterClass(db,'longnamer')=='priest')
    assert(C.LegacyCharacterClass(db,'Longnam')==nil and C.LegacyCharacterClass(db,'Longnam-lite')==nil)
    C.StoreLegacyCharacterList(db,'[nexus] ACINFO:LEGACY:LIST ')
    assert(C.LegacyCharacterClass(db,'Longname')=='mage')
    for _,value in ipairs({false,17,{},'monk'}) do
        assert(C.LegacyCharacterClass({legacyCharacters={bad=value},inviteCharacters={Bad={class=value}}},'Bad')==nil)
    end
    local conflict={presets={A={entries={{kind='legacy',charName='Ambiguous',class='mage'}}},B={entries={{kind='legacy',charName='Ambiguous',class='priest'}}}}}
    assert(C.LegacyCharacterClass(conflict,'Ambiguous')==nil)
end)

test('request is delayed, one-shot, rate limited and cancelled on close',function()
    local h=boot(); local clock=100; local sent=0
    h.env.GetTime=function() return clock end; h.env.SendChatMessage=function(msg) assert(msg=='.z addlegacy list'); sent=sent+1 end
    local f=open(h); local q=h.C.legacyQueryFrame
    h:fire(q,'OnUpdate',0.1); assert(sent==0)
    clock=100.6; h:fire(q,'OnUpdate',0.6); assert(sent==1 and not q.scripts.OnUpdate)
    h.C.RequestLegacyCharacters(f); assert(not q.scripts.OnUpdate)
    clock=103; h.C.RequestLegacyCharacters(f); f:Hide(); clock=104
    h:fire(q,'OnUpdate',1); assert(sent==1 and not q.scripts.OnUpdate)
    h.env.GetTime=nil; h.C.RequestLegacyCharacters(f); assert(not q.scripts.OnUpdate)
end)

for _,class in ipairs({'warrior','paladin','hunter','warlock','priest','druid','shaman','rogue','mage'}) do
    local key=class
    test('saved class and valid role matrix: '..key,function()
        local h=boot({legacyCharacters={matrix=key},presets={}}); local f=open(h); f.nameInput:SetText('Matrix')
        assert(string.lower(f.classButton.label:GetText())==key)
        h:click(f.addButton); local e=h:entry('Matrix')
        assert(e.class==key and h.C.RoleAllowedForClass(key,e.role))
    end)
end

test('selected Druid role is saved and reused after a new session',function()
    local h=boot({presets={}}); local f=open(h); f.nameInput:SetText('RoleDruid')
    h:choose(f.roleButton,'Healer'); h:choose(f.classButton,'Druid'); h:click(f.addButton)
    local saved=h.env.ShirsRaidBuilderDB
    assert(saved.legacyCharacters.roledruid=='druid','class save changed')
    assert(saved.legacyCharacterRoles and saved.legacyCharacterRoles.roledruid=='healer','selected role not saved')
    -- Remove composition entries: reuse must come from account data.
    saved.presets={}
    local again=boot(saved); local g=open(again); g.nameInput:SetText('rOlEdRuId')
    assert(g.classButton.label:GetText()=='Druid','class not restored')
    assert(g.roleButton.label:GetText()=='Healer','role not restored')
    again:click(g.addButton)
    assert(again:entry('rOlEdRuId').role=='healer','Add ignored restored role')
end)

test('manual role correction survives late class replies and is saved',function()
    local h=boot({legacyCharacters={roledruid='druid'},legacyCharacterRoles={roledruid='healer'},presets={}})
    local f=open(h); f.nameInput:SetText('RoleDruid')
    h:choose(f.roleButton,'Tank')
    assert(f.roleButton.label:GetText()=='Tank','saved role overwrote manual correction')
    assert(f.classButton.label:GetText()=='Druid','role correction discarded known class')
    h.env.event='CHAT_MSG_ADDON'; h.env.arg2=''
    for _,w in ipairs(h.frames) do
        if w.events.CHAT_MSG_ADDON then h:fire(w,'OnEvent','[nexus] ACINFO:LEGACY:LIST RoleDruid:Druid:0') end
    end
    assert(f.roleButton.label:GetText()=='Tank','late reply overwrote manual role')
    h:click(f.addButton)
    assert(h.env.ShirsRaidBuilderDB.legacyCharacterRoles.roledruid=='tank','correction not saved')
    f:Hide(); f=open(h)
    assert(f.roleButton.label:GetText()=='Tank','reopen lost manual role')
    f.nameInput:SetText('Othername'); f.nameInput:SetText('ROLEDRUID')
    assert(f.roleButton.label:GetText()=='Tank','name switching did not restore corrected role')
end)

test('missing malformed and incompatible roles keep the valid current role',function()
    for _,bad in ipairs({false,17,{},'invalid','all','Healer',' healer '}) do
        local h=boot({legacyCharacters={roledruid='druid'},legacyCharacterRoles={roledruid=bad},presets={}})
        local f=open(h); f.nameInput:SetText('RoleDruid')
        assert(f.classButton.label:GetText()=='Druid' and f.roleButton.label:GetText()=='Melee DPS','invalid saved role entered UI')
    end
    for _,badMap in ipairs({false,17,'healer',{}, {other='healer'}}) do
        local h=boot({legacyCharacters={roledruid='druid'},legacyCharacterRoles=badMap,presets={}})
        local f=open(h); h:choose(f.roleButton,'Tank'); f.nameInput:SetText('RoleDruid')
        assert(f.roleButton.label:GetText()=='Tank','missing role replaced valid current role')
    end
    local h=boot({legacyCharacters={rolemage='mage'},legacyCharacterRoles={rolemage='healer'},presets={}})
    local f=open(h); f.nameInput:SetText('RoleMage')
    assert(f.roleButton.label:GetText()=='Ranged DPS','incompatible role accepted')
end)

test('existing legacy composition restores its role before the new cache exists',function()
    local saved={currentPreset='Default',presets={Default={entries={{kind='legacy',charName='OldDruid',class='druid',role='healer'}}}}}
    local h=boot(saved); local f=open(h); f.nameInput:SetText('OLDDRUID')
    assert(f.classButton.label:GetText()=='Druid')
    assert(f.roleButton.label:GetText()=='Healer','existing saved role ignored')
end)

test('account database binding preserves pending saved role',function()
    local h=boot({presets={}}); local f=open(h); f.nameInput:SetText('BindDruid')
    h:choose(f.roleButton,'Healer'); h:choose(f.classButton,'Druid'); h:click(f.addButton)
    h.env.ShirsRaidBuilderDB={presets={}}
    h.env.SlashCmdList.SHIRSRAIDBUILDER('demo')
    assert(h.env.ShirsRaidBuilderDB.legacyCharacterRoles and h.env.ShirsRaidBuilderDB.legacyCharacterRoles.binddruid=='healer','binding lost pending role')
end)

test('role lookup rejects bad old entries and ambiguous full-name matches',function()
    local C=boot().C
    local function db(role)
        return {presets={A={entries={{kind='legacy',charName='Longname',class='druid',role=role}}}}}
    end
    for _,bad in ipairs({false,17,{},'invalid','all'}) do assert(C.LegacyCharacterRole(db(bad),'Longname','druid')==nil) end
    assert(C.LegacyCharacterRole(db(nil),'Longname','druid')==nil)
    local saved=db('healer')
    saved.presets.B={entries={{kind='legacy',charName='LONGNAME',class='druid',role='tank'}}}
    assert(C.LegacyCharacterRole(saved,'Longname','druid')==nil,'conflicting old roles selected arbitrarily')
    saved.legacyCharacterRoles={longname='rdps',longnamer='tank'}
    assert(C.LegacyCharacterRole(saved,'LONGNAME','druid')=='rdps','latest successful Add must win')
    assert(C.LegacyCharacterRole(saved,'Longnamer','druid')=='tank')
    assert(C.LegacyCharacterRole(saved,'Longnam','druid')==nil)
    assert(C.LegacyCharacterRole(saved,'Longnam-lite','druid')==nil)
    assert(C.LegacyCharacterRole(saved,'Longname','mage')=='rdps')
    saved.legacyCharacterRoles.longname=false
    assert(C.LegacyCharacterRole(saved,'Longname','druid')==nil,'malformed cache must not fall through')
end)

test('class-only refresh preserves saved role and invalid writes cannot replace it',function()
    local C=boot().C; local saved={}
    C.RememberLegacyCharacter(saved,'RoleDruid','Druid','healer')
    C.StoreLegacyCharacterList(saved,'[nexus] ACINFO:LEGACY:LIST RoleDruid:Druid:0')
    assert(C.LegacyCharacterRole(saved,'ROLEDRUID','druid')=='healer')
    for _,bad in ipairs({false,17,{},'invalid','all'}) do C.RememberLegacyCharacter(saved,'RoleDruid','druid',bad) end
    assert(C.LegacyCharacterRole(saved,'RoleDruid','druid')=='healer')
    C.RememberLegacyCharacter(saved,'RoleDruid','mage')
    assert(C.LegacyCharacterRole(saved,'RoleDruid','mage')==nil,'role must match refreshed class')
end)

test('unsuccessful Add never saves a role',function()
    local h=boot({presets={}}); local f=open(h)
    h:click(f.addButton); assert(h.env.ShirsRaidBuilderDB.legacyCharacterRoles==nil)
    f.nameInput:SetText('FullDruid'); h:choose(f.roleButton,'Healer'); h:choose(f.classButton,'Druid')
    for i=1,40 do h:preset().entries[i]={kind='guest',charName='Guest',class='mage',role='rdps'} end
    h:click(f.addButton)
    assert(h.env.ShirsRaidBuilderDB.legacyCharacterRoles==nil,'full board saved unadded role')
end)

for _,role in ipairs({'tank','healer','mdps','rdps'}) do
    local key=role
    test('saved Druid role matrix: '..key,function()
        local h=boot({legacyCharacters={matrix='druid'},legacyCharacterRoles={matrix=key},presets={}})
        local f=open(h); f.nameInput:SetText('MATRIX'); h:click(f.addButton)
        assert(h:entry('MATRIX').role==key)
    end)
end

test('successful Add clears only the name and leaves the next hire ready',function()
    local h=boot({presets={}}); local f=open(h)
    f.nameInput:SetText('Firstdruid')
    h:choose(f.roleButton,'Healer'); h:choose(f.classButton,'Druid')
    h:click(f.addButton)
    local first=h:entry('Firstdruid')
    assert(first.class=='druid' and first.role=='healer')
    assert(f.nameInput:GetText()=='','successful Add retained the legacy name')
    assert(f:IsVisible(),'Add closed the editor')
    assert(f.classButton.label:GetText()=='Druid' and f.roleButton.label:GetText()=='Healer','Add cleared other fields')
    local menu=h.env.ShirsRaidBuilderLegacyNameMenu
    assert(not menu or not menu:IsVisible(),'name reset left suggestions open')
    assert(h.env.ShirsRaidBuilderDB.legacyCharacters.firstdruid=='druid')
    assert(h.env.ShirsRaidBuilderDB.legacyCharacterRoles.firstdruid=='healer')
    local count=table.getn(h:preset().entries)
    h:click(f.addButton)
    assert(table.getn(h:preset().entries)==count,'second blank click duplicated a hire')
    f.nameInput:SetText('Nextdruid'); h:click(f.addButton)
    assert(h:entry('Nextdruid').class=='druid' and h:entry('Nextdruid').role=='healer')
    assert(h:entry('Firstdruid')==first,'repeated Add changed the first entry identity')
    assert(f.nameInput:GetText()=='')
    f:Hide(); f=open(h); assert(f.nameInput:GetText()=='','reopen restored the previous name')
    f.nameInput:SetText('FIRSTDRUID')
    assert(f.classButton.label:GetText()=='Druid' and f.roleButton.label:GetText()=='Healer','saved reuse lost after reset')
end)

test('invalid and full-board Add preserve the entered name and choices',function()
    local h=boot({presets={}}); local f=open(h)
    for _,name in ipairs({'',' ','A','Bad123','Longnam-lite'}) do
        f.nameInput:SetText(name); local count=table.getn(h:preset().entries)
        h:click(f.addButton)
        assert(f.nameInput:GetText()==name,'rejected Add cleared input')
        assert(table.getn(h:preset().entries)==count,'invalid Add inserted an entry')
    end
    f.nameInput:SetText('FullDruid'); h:choose(f.roleButton,'Healer'); h:choose(f.classButton,'Druid')
    for i=1,40 do h:preset().entries[i]={kind='guest',charName='Guest',class='mage',role='rdps'} end
    h:click(f.addButton)
    assert(f.nameInput:GetText()=='FullDruid','full-board Add cleared input')
    assert(f.classButton.label:GetText()=='Druid' and f.roleButton.label:GetText()=='Healer')
    assert(h.env.ShirsRaidBuilderDB.legacyCharacterRoles==nil,'rejected Add saved a role')
end)

test('addon legacy response reads arg2 through the registered receive handler',function()
    local h=boot({presets={}}); local f=open(h); f.nameInput:SetText('Wiremage')
    h.env.event='CHAT_MSG_ADDON'; h.env.arg2='[nexus] ACINFO:LEGACY:LIST Wiremage:Mage:0 Wirepriest:Priest:1'
    h.env.arg3='WHISPER'; h.env.arg4='nexus'
    local listeners=0
    for _,w in ipairs(h.frames) do
        if w.events.CHAT_MSG_ADDON and w.events.CHAT_MSG_MONSTER_WHISPER then
            listeners=listeners+1; h:fire(w,'OnEvent','nexus')
        end
    end
    assert(listeners==1,'real receive listener missing')
    assert(h.C.LegacyCharacterClass(h.env.ShirsRaidBuilderDB,'Wiremage')=='mage','arg2 legacy payload was not stored')
    assert(h.C.LegacyCharacterClass(h.env.ShirsRaidBuilderDB,'Wirepriest')=='priest')
    assert(f.classButton.label:GetText()=='Mage','arg2 reply did not refresh the editor')
    h:click(f.addButton); assert(h:entry('Wiremage').class=='mage')
end)

test('incomplete and unknown licences omit tier text without inventing data',function()
    local C=boot().C
    assert(C.CurrentLicenseTier(nil)==nil)
    local invalid={{},{raidLicense='t2r'},{dungeonLicense='t2d'},
        {raidLicense='',dungeonLicense='t2d'},{raidLicense='t2r',dungeonLicense=''},
        {raidLicense='future',dungeonLicense='t2d'},{raidLicense='t2r',dungeonLicense='future'},
        {raidLicense='t9r',dungeonLicense='t2d'},{raidLicense='t2r',dungeonLicense='t9d'},
        {raidLicense='t2d',dungeonLicense='t2r'},
        {raidLicense=false,dungeonLicense='t2d'},{raidLicense='t2r',dungeonLicense={}}}
    for _,record in ipairs(invalid) do
        assert(C.CurrentLicenseTier(record)==nil,'incomplete or unknown licence fabricated a tier')
        record.name='Wiremage'; record.class='mage'; record.level=60
        local h=boot({inviteCharacters={Wiremage=record},presets={}})
        local found=false
        for _,row in ipairs(h.env.ShirsRaidBuilderMainFrame.accountRows) do
            if row.fonts[1]:GetText()=='Wiremage  [0]' then
                found=true; assert(table.getn(row.fonts)==1 and row:GetHeight()==22,'unknown licence rendered an extra tier line')
            end
        end
        assert(found,'licence fixture never reached account renderer')
    end
    assert(C.CurrentLicenseTier({raidLicense='t4r',dungeonLicense='t2d'})=='T4R - T2D')
    assert(C.CurrentLicenseTier({raidLicense='t2r',dungeonLicense='NONE'})=='T2R - T0D','explicit no dungeon licence retains known base tier')
    assert(C.CurrentLicenseTier({raidLicense='t1',dungeonLicense='t1'})=='T1 - T1')
end)

-- Count real profile initialization through the registered Vanilla event path.
-- Timing/FPS is deliberately not asserted by this offline regression.
test('idle message traffic never repeats profile initialization',function()
    local saved={presets={},currentPreset='Profile1'}
    for i=1,15 do saved.presets['Profile'..i]={entries={{kind='legacy',charName='Caster',class='mage',role='rdps'}}} end
    local h=boot(saved)
    h.env.ShirsRaidBuilderMainFrame:Hide()
    h.env.event='VARIABLES_LOADED'
    for _,w in ipairs(h.frames) do if w.events.VARIABLES_LOADED then h:fire(w,'OnEvent') end end
    local calls=0; local original=h.C.MigrateCharacterRoles
    h.C.MigrateCharacterRoles=function(roles,presets,current)
        calls=calls+1; return original(roles,presets,current)
    end
    local function receive(kind,a,b)
        h.env.event=kind; h.env.arg2=b; h.env.arg3=nil
        for _,w in ipairs(h.frames) do if w.events[kind] then h:fire(w,'OnEvent',a) end end
    end
    for i=1,100 do
        receive('CHAT_MSG_ADDON','nexus','STATS:X unrelated')
        receive('CHAT_MSG_MONSTER_WHISPER','unrelated','nexus')
    end
    assert(calls==0,'unrelated messages repeated full initialization: '..calls)
    receive('CHAT_MSG_ADDON','nexus','[nexus] ACINFO:LEGACY:LIST Wiremage:Mage:0')
    receive('CHAT_MSG_MONSTER_WHISPER','[nexus] ACINFO:LEGACY:LIST Wirepriest:Priest:1','nexus')
    assert(calls==0,'legacy replies repeated full initialization')
    assert(saved.legacyCharacters.wiremage=='mage' and saved.legacyCharacters.wirepriest=='priest')
    -- Rebinding must still repair absent SavedVariables and retain pending data.
    h.env.ShirsRaidBuilderDB=nil
    receive('CHAT_MSG_MONSTER_WHISPER','[nexus] ACINFO:LEGACY:LIST Newmage:Mage:0','nexus')
    assert(calls==1,'missing DB did not initialize once')
    local rebound=h.env.ShirsRaidBuilderDB
    assert(rebound.presets.Profile15 and rebound.legacyCharacters.newmage=='mage')
    receive('CHAT_MSG_ADDON','nexus','unrelated')
    assert(calls==1,'rebound DB initialized again')
    rebound.presets=nil
    receive('CHAT_MSG_ADDON','nexus','unrelated')
    assert(calls==2 and type(rebound.presets)=='table','missing presets not repaired')
end)

test('listener first use binds and initializes an absent database',function()
    local source=string.sub(fixture,1,boundary-1)
    local first,last=string.find(source,"    env.SlashCmdList.SHIRSRAIDBUILDER('demo')",1,true)
    assert(first and last)
    source=string.sub(source,1,first-1)..'    env.ShirsRaidBuilderDB=nil'..string.sub(source,last+1)
    local coldBoot=assert(loadstring(source..'\nreturn boot'))()
    local h=coldBoot(); local listenerFactory
    for i=1,32 do
        local name,value=debug.getupvalue(h.env.SlashCmdList.SHIRSRAIDBUILDER,i)
        if name=='EnsureInviteListener' then listenerFactory=value end
    end
    assert(listenerFactory,'real listener factory not found'); listenerFactory()
    local calls=0; local original=h.C.MigrateCharacterRoles
    h.C.MigrateCharacterRoles=function(roles,presets,current)
        calls=calls+1; return original(roles,presets,current)
    end
    h.env.event='CHAT_MSG_MONSTER_WHISPER'; h.env.arg2='nexus'
    for _,w in ipairs(h.frames) do
        if w.events.CHAT_MSG_MONSTER_WHISPER then
            h:fire(w,'OnEvent','[nexus] ACINFO:LEGACY:LIST Coldmage:Mage:0')
            h:fire(w,'OnEvent','unrelated')
        end
    end
    assert(calls==1,'cold listener must initialize exactly once')
    local saved=h.env.ShirsRaidBuilderDB
    assert(saved.presets[saved.currentPreset] and saved.legacyCharacters.coldmage=='mage')
    -- The real startup boundary may run later and must keep the early reply.
    h.env.event='ADDON_LOADED'
    for _,w in ipairs(h.frames) do if w.events.ADDON_LOADED then h:fire(w,'OnEvent','ShirsRaidBuilder') end end
    assert(h.env.ShirsRaidBuilderDB==saved and saved.legacyCharacters.coldmage=='mage')
end)

print('Legacy character tests: '..passes..' PASS, '..failures..' FAIL')
assert(failures==0,'legacy character regression failures')
print("Shir's Raid Builder legacy character tests: PASS")
