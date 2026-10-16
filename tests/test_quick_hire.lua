-- Exact Lua 5.0.3; real constructor/registered Vanilla handlers. Synthetic UI only.
local f=assert(io.open('test_individual_editor.lua','r')); local fixture=f:read('*a'); f:close()
local boundary=assert(string.find(fixture,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(fixture,1,boundary-1)..'\nreturn boot'))()
local failures,passes=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passes=passes+1; print('PASS '..name)
    else failures=failures+1; print('FAIL '..name..': '..tostring(err)) end
end
local function saved()
    local entries={}; for i=1,40 do entries[i]={kind='empty'} end
    entries[1]={kind='player',charName='Alice',class='warrior',role='tank'}
    return {currentPreset='Default',presets={Default={entries=entries,denyRules={},setupRules={}}},
        inviteCharacters={Alice={name='Alice',level=60,raidLicense='t3r',dungeonLicense='t2d',faction='Alliance'},
            Hordealt={name='Hordealt',level=60,raidLicense='t1r',dungeonLicense='none',faction='Horde'}}}
end
local function start(db)
    local h=boot(db or saved(),'Alice')
    function h:empty(index)
        local group=math.floor((index-1)/5); local col=index-1-group*5
        for _,w in ipairs(self.frames) do
            if w.kind=='Button' and w:IsVisible() and w.fonts[1] and w.fonts[1]:GetText()=='empty'
                and w.point and w.point[4]==2+col*102 and w.point[5]==-21-group*51 then return w end
        end
        error('empty slot missing: '..index)
    end
    function h:normal(name,tier)
        self:click(self:button(self.env.ShirsRaidBuilderMainFrame,'Add Normal'))
        local n=self.env.ShirsRaidBuilderAddNormal
        self:choose(n.characterButton,name or 'Alice')
        if tier then self:choose(n.tierButton,tier) end
        return n
    end
    function h:quick(index)
        self:click(self:empty(index or 9))
        local q=self.env.ShirsRaidBuilderQuickHire
        assert(q and q:IsVisible(),'empty-slot click must open quick hire')
        return q
    end
    return h
end
local function hidden(w) return not w or not w:IsVisible() end
local function has(list,value) for _,v in ipairs(list or {}) do if v==value then return true end end; return false end

test('Random Tank uses explicit chosen eligible tier and exact empty slot, without spending',function()
    local h=start(); local n=h:normal('Alice','t1r'); local original=h:preset().entries[2]
    local q=h:quick(9)
    assert(q.sourceButton.label:GetText()=='Alice','visible source was not captured at click time')
    assert(q.tierButton.label:GetText()=='t1r','visible tier was not shown')
    assert(hidden(n),'normal panel must not overlap the compact flow')
    h:click(h:button(q,'Random')); h:click(h:button(q,'Tank'))
    h:click(h:button(q,'Add'))
    assert(h:preset().entries[9].kind=='empty','an inherited tier is not an explicit quick tier choice')
    h:choose(q.tierButton,'t2d'); h:choose(q.tierButton,'t0d')
    h:click(h:button(q,'Add'))
    local entry=h:preset().entries[9]
    assert(entry.kind=='normal' and entry.account=='Alice' and entry.role=='tank')
    assert(entry.tier=='t0d','selected tier changed or upgraded')
    assert(entry.class=='random' and entry.role=='tank' and entry.spec==nil and entry.race==nil and entry.gender==nil)
       assert(h:preset().entries[2]==original,'quick hire filled an earlier empty slot')
       assert(h.C.BuildNormalHireCommand(entry)=='.z addi Alice t0d tank')
       assert(q:IsVisible() and hidden(h.env.ShirsRaidBuilderChoiceMenu),'repeated-add panel closed or left dropdown')
end)

test('Class DPS Mage picker keeps source/tier explicit, cancels unchanged, and confirms race/gender',function()
    local h=start(); h:normal('Alice','t3r')
    local p=h:preset(); local slot=p.entries[9]
    local q=h:quick(9)
    h:click(h:button(q,'Class')); h:click(h:button(q,'DPS')); h:click(h:button(q,'Mage'))
    assert(p.entries[9]==slot,'class selection materialized a row before confirm')
    assert(table.concat(q.raceButton.options,',')=='Human,Gnome','Mage race list is not class/faction valid')
    h:choose(q.raceButton,'Gnome'); h:choose(q.genderButton,'Female')
    h:choose(q.specButton,'Fire')
    h:click(h:button(q,'Add'))
    assert(p.entries[9]==slot,'class picker inherited a tier without explicit choice')
    h:choose(q.tierButton,'t2r'); h:choose(q.tierButton,'t1d')
    assert(string.find(q.note:GetText(),'t1d',1,true),'selected tier is not visible before Add')
    h:click(h:button(q,'Cancel'))
    assert(p.entries[9]==slot and hidden(q),'cancel changed the plan')
    q=h:quick(9); h:choose(q.sourceButton,'Alice')
    h:click(h:button(q,'Class')); h:click(h:button(q,'DPS')); h:click(h:button(q,'Mage'))
    h:choose(q.raceButton,'Gnome'); h:choose(q.genderButton,'Female'); h:choose(q.specButton,'Fire')
    h:choose(q.tierButton,'t2d'); h:choose(q.tierButton,'t1r')
    h:click(h:button(q,'Add'))
    assert(h.C.BuildNormalHireCommand(p.entries[9])=='.z addinvite Alice t1r mage rdps fire gnome female')
end)

local function dump(value)
    if type(value)~='table' then return type(value)=='string' and string.format('%q',value) or tostring(value) end
    local keys,parts={},{}; for key in pairs(value) do table.insert(keys,key) end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,key in ipairs(keys) do table.insert(parts,'['..dump(key)..']='..dump(value[key])) end
    return '{'..table.concat(parts,',')..'}'
end
local function prepare(h,branch,role,class,index)
    local q=h:quick(index or 9)
    if q.sourceButton.label:GetText()~='Alice' then h:choose(q.sourceButton,'Alice') end
    h:click(h:button(q,branch)); h:click(h:button(q,role))
    if class then h:click(h:button(q,class)) end
    h:choose(q.tierButton,'t1r') -- Manual-Add fixtures choose tier last; final-choice handlers have a separate suite.
    return q
end

test('Escape closes dropdown then quick flow; main hide and Sort close every quick overlay',function()
    local h=start(); local q=prepare(h,'Class','DPS','Mage')
    local before=dump(h:preset())
    h:click(q.raceButton)
    h.env.ShirsRaidBuilderEscaper:Hide()
    assert(hidden(h.env.ShirsRaidBuilderChoiceMenu) and q:IsVisible(),'first Escape did not dismiss only the dropdown')
    h.env.ShirsRaidBuilderEscaper:Hide()
    assert(hidden(q) and h.env.ShirsRaidBuilderMainFrame:IsVisible(),'second Escape must dismiss quick flow, not main')
    q=prepare(h,'Random','Healer'); h:click(q.tierButton)
    h.env.ShirsRaidBuilderMainFrame:Hide()
    assert(hidden(q) and hidden(h.env.ShirsRaidBuilderChoiceMenu),'builder hide left an orphan quick overlay')
    h.env.ShirsRaidBuilderMainFrame:Show()
    q=prepare(h,'Class','DPS','Mage'); h:click(q.genderButton)
    h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Sort Mode'))
    assert(hidden(q) and hidden(h.env.ShirsRaidBuilderChoiceMenu),'mode change left an orphan quick overlay')
    h:click(h:empty(9)); assert(hidden(q),'Sort empty slot opened hiring')
    assert(dump(h.env.ShirsRaidBuilderDB.presets.Default)==before,'cancel/Escape/Sort changed the hire plan')
end)

test('profile switching away and back invalidates slot dialog; normal editor cannot retarget it',function()
    local db=saved(); db.presets.Other={entries={},denyRules={},setupRules={}}
    local h=start(db); local q=prepare(h,'Random','Tank'); local before=dump(h:preset())
    local profile
    for _,w in ipairs(h.frames) do
        if w.parent==h.env.ShirsRaidBuilderMainFrame and w.options and has(w.options,'Other') then profile=w end
    end
    assert(profile,'profile selector missing')
    h:choose(profile,'Other'); assert(hidden(q),'profile change must close quick flow immediately')
    h:choose(profile,'Default'); assert(hidden(q),'returning to the same name revived the old dialog')
    assert(dump(h:preset())==before)
    q=prepare(h,'Class','DPS','Mage')
    h:normal('Hordealt','t1r')
    assert(hidden(q),'reopening the visible normal editor leaves a stale quick target')
    q=h:quick(9)
    assert(q.sourceButton.label:GetText()=='Hordealt' and q.tierButton.label:GetText()=='t1r','new click did not capture current visible normal source/tier')
end)

test('changing quick source retains branch and valid tier while refreshing unavailable class',function()
    local h=start(); local q=prepare(h,'Class','Healer','Paladin')
    local before=dump(h:preset())
    h:choose(q.sourceButton,'Hordealt')
    assert(q.mode=='class' and q.group=='healer' and not q.pickedClass)
    assert(q.tierButton.label:GetText()=='t1r' and q.tierChosen)
    assert(table.concat(q.tierButton.options,',')=='t0d,t1r','source licences were not refreshed')
    h:choose(q.tierButton,'t0d')
    assert(not pcall(function() h:button(q,'Paladin') end),'Horde offers Paladin')
    h:click(h:button(q,'Shaman'))
    assert(table.concat(q.raceButton.options,',')=='Orc,Tauren,Troll')
    h:choose(q.raceButton,'Troll'); h:choose(q.genderButton,'Female')
    assert(dump(h:preset())~=before and h:preset().entries[9].kind=='normal','final valid choice did not add')
    assert(h.C.BuildNormalHireCommand(h:preset().entries[9])=='.z addinvite Hordealt t0d shaman healer default troll female')
end)

test('filled slot or replaced profile invalidates Add without overwriting any row',function()
    for _,replace in ipairs({'slot','profile','entries','realm','player'}) do
        local h=start(); local q=prepare(h,'Class','DPS','Mage'); local original=h:preset()
        local occupied={kind='guest',companionName='Guest',class='warrior',role='tank'}
        if replace=='slot' then original.entries[9]=occupied
        elseif replace=='profile' then h.env.ShirsRaidBuilderDB.presets.Default={entries={},denyRules={},setupRules={}}
        elseif replace=='entries' then original.entries={}
        elseif replace=='realm' then h.env.GetRealmName=function() return 'ChangedRealm' end
        else h.env.UnitName=function() return 'Changedplayer' end end
        local before=dump(h.env.ShirsRaidBuilderDB.presets)
        h:click(h:button(q,'Add'))
        assert(hidden(q) and dump(h.env.ShirsRaidBuilderDB.presets)==before,'invalid '..replace..' context mutated a plan')
    end
end)

local classRoles={warrior={'tank','mdps'},mage={'rdps'},warlock={'rdps'},priest={'healer','rdps'},
    druid={'tank','healer','mdps','rdps'},paladin={'tank','healer','mdps'},shaman={'tank','healer','mdps','rdps'},hunter={'rdps'},rogue={'mdps'}}
local raceLists={
    Alliance={warrior='Human,Gnome,Night Elf,Dwarf',mage='Human,Gnome',warlock='Human,Gnome',priest='Human,Night Elf,Dwarf',
        druid='Night Elf',paladin='Human,Dwarf',hunter='Night Elf,Dwarf',rogue='Human,Gnome,Night Elf,Dwarf'},
    Horde={warrior='Orc,Undead,Tauren,Troll',mage='Undead,Troll',warlock='Orc,Undead',priest='Undead,Troll',
        druid='Tauren',shaman='Orc,Tauren,Troll',hunter='Orc,Tauren,Troll',rogue='Orc,Undead,Troll'}}
local labels={warrior='Warrior',mage='Mage',warlock='Warlock',priest='Priest',druid='Druid',paladin='Paladin',shaman='Shaman',hunter='Hunter',rogue='Rogue'}
for _,faction in ipairs({'Alliance','Horde'}) do
    for _,group in ipairs({'tank','healer','dps'}) do
        for _,class in ipairs({'warrior','mage','warlock','priest','druid','paladin','shaman','hunter','rogue'}) do
            local faction,group,class=faction,group,class
            test('Class matrix '..faction..' '..group..' '..class,function()
                local h=start(); local q=h:quick(9)
                h:choose(q.sourceButton,faction=='Alliance' and 'Alice' or 'Hordealt')
                h:click(h:button(q,'Class')); h:click(h:button(q,group=='dps' and 'DPS' or group=='tank' and 'Tank' or 'Healer'))
                local validRoles={}
                for _,role in ipairs(classRoles[class]) do
                    if group==role or (group=='dps' and (role=='mdps' or role=='rdps')) then table.insert(validRoles,role) end
                end
                local allowed=raceLists[faction][class] and table.getn(validRoles)>0
                local offered,button=pcall(function() return h:button(q,labels[class]) end)
                assert(offered==(allowed and true or false),'invalid class/role/faction menu')
                if not allowed then h:click(h:button(q,'Cancel')); return end
                h:click(button)
                assert(table.concat(q.raceButton.options,',')==raceLists[faction][class],'race matrix differs')
                assert(table.getn(q.roleButton.options)==table.getn(validRoles),'DPS lost a valid melee/ranged role')
                for _,role in ipairs(validRoles) do
                    h:choose(q.roleButton,role=='tank' and 'Tank' or role=='healer' and 'Healer' or role=='mdps' and 'Melee DPS' or 'Ranged DPS')
                    assert(has(q.specButton.options,q.specButton.label:GetText()),'invalid default spec')
                end
                for _,race in ipairs(q.raceButton.options) do h:choose(q.raceButton,race) end
                h:choose(q.genderButton,'Male'); h:choose(q.genderButton,'Female')
                h:choose(q.tierButton,'t0d') -- Explore every choice without committing each row.
                h:click(h:button(q,'Add'))
                local entry=h:preset().entries[9]
                assert(entry.class==class and has(validRoles,entry.role) and entry.gender=='female' and entry.tier=='t0d')
                assert(h.C.BuildNormalHireCommand(entry),'class matrix command missing')
            end)
        end
    end
end

test('Random matrix retains MCP role-only intent for both factions and all three role branches',function()
    for _,faction in ipairs({'Alliance','Horde'}) do
        for _,group in ipairs({'tank','healer','dps'}) do
            local h=start(); local q=h:quick(9)
            h.env.math=setmetatable({random=function() error('Quick Add must never roll a local class') end},{__index=math})
            local source=faction=='Alliance' and 'Alice' or 'Hordealt'
            h:choose(q.sourceButton,source); h:choose(q.tierButton,'t0d')
            h:click(h:button(q,'Random')); h:click(h:button(q,group=='dps' and 'DPS' or group=='tank' and 'Tank' or 'Healer'))
            local e=h:preset().entries[9]
            assert(e.kind=='normal' and e.class=='random' and e.role==group)
            assert(e.spec==nil and e.race==nil and e.gender==nil,'server choices were invented')
            assert(h.C.BuildNormalHireCommand(e)=='.z addi '..source..' t0d '..group)
            assert(q:IsVisible() and q.slot==10,'repeat-add target not preserved')
        end
    end
end)

test('closed normal editor is not a hidden source; unknown licences offer explicit base tier only',function()
    local h=start(); local n=h:normal('Hordealt','t1r'); n:Hide()
    local q=h:quick(9)
    assert(q.sourceButton.label:GetText()=='(choose source)','closed normal editor supplied a hidden target')
    h:choose(q.sourceButton,'Alice')
    local db=h.env.ShirsRaidBuilderDB
    db.inviteCharacters.Alice.raidLicense='unknown'; db.inviteCharacters.Alice.dungeonLicense='unknown'
    db.localAccountRows={}
    h:choose(q.sourceButton,'Alice')
    assert(table.concat(q.tierButton.options,',')=='t0d','unknown licences invent a paid tier')
    h:choose(q.tierButton,'t0d'); h:click(h:button(q,'Random')); h:click(h:button(q,'Healer')); h:click(h:button(q,'Add'))
    assert(h:preset().entries[9].tier=='t0d')
end)

test('both branches reject invalid or withdrawn source/tier eligibility without clamping or adding',function()
    for _,branch in ipairs({'Random','Class'}) do
        for _,bad in ipairs({'tier','withdrawn','source','untrusted'}) do
            local h=start(); local q=prepare(h,branch,'DPS',branch=='Class' and 'Mage' or nil)
            local before=dump(h:preset())
            if bad=='tier' then q.tierButton.label:SetText('t5r')
            elseif bad=='withdrawn' then
                h.env.ShirsRaidBuilderDB.inviteCharacters.Alice.raidLicense='none'
                h.env.ShirsRaidBuilderDB.localAccountRows={}
            elseif bad=='source' then q.sourceButton.label:SetText('Nobody')
            else
                q.sourceButton.label:SetText('Outsider')
                h.env.ShirsRaidBuilderDB.knownCharacters.Outsider=true
                h.env.ShirsRaidBuilderDB.characterLevels.Outsider=60
            end
            h:click(h:button(q,'Add'))
            assert(dump(h:preset())==before,'invalid '..bad..' mutated '..branch..' plan')
            h:click(h:button(q,'Cancel'))
        end
    end
end)

test('trusted linked planning source uses its own faction/tiers; removing trust invalidates Add',function()
    local h=start(); local db=h.env.ShirsRaidBuilderDB; local C=h.C
    db.peerLinks={}; local link=C.PeerNew('Alice','Bob','FixtureRealm'); link.phase='linked'; C.LinkSave(db.peerLinks,link,true)
    db.peerSnapshots={['FixtureRealm;bob']={accountId='1234567890123456',source='bob',realm='FixtureRealm',received=1800000000,observed=1800000000,authoritative=false,
        entries={{name='Linkedalt',level=60,dungeonLicense='t1d',raidLicense='t2r',observed=1800000000,faction='Horde'}}}}
    local q=h:quick(9); h:choose(q.sourceButton,'Linkedalt')
    assert(table.concat(q.tierButton.options,',')=='t0d,t1d,t1r,t2r')
    h:choose(q.tierButton,'t1d'); h:click(h:button(q,'Class')); h:click(h:button(q,'Healer')); h:click(h:button(q,'Shaman'))
    local before=dump(h:preset()); db.peerLinks={}
    h:click(h:button(q,'Add')); assert(dump(h:preset())==before,'untrusted linked row was accepted')
end)

test('four-normal cap survives mid-dialog changes and never changes player/guest/legacy or rules',function()
    for _,branch in ipairs({'Random','Class'}) do
        local h=start(); local p=h:preset(); local q=prepare(h,branch,'DPS',branch=='Class' and 'Mage' or nil)
        for i=2,5 do p.entries[i]={kind='normal',account=i==2 and 'alice' or 'Alice',class='mage',role='rdps',tier='t1r',spec='frost',race='human',gender='male'} end
        p.entries[6]={kind='legacy',charName='Legacy',class='shaman',role='mdps',denyList={'Lightning Bolt'}}
        p.entries[7]={kind='guest',companionName='Guest',class='warlock',role='rdps'}
        p.denyRules={{class='mage',role='all',abilities={'Frost Nova'}}}; p.setupRules={{class='mage',role='all',magic='arcane'}}
        h.C.RepairRaidEntries(p.entries) -- Existing editor/save normalization, before the no-change snapshot.
        local before=dump(p)
        h:click(h:button(q,'Add')); assert(dump(p)==before,'four-normal limit or existing rows/rules changed')
        h:click(h:button(q,'Cancel'))
        for _,slot in ipairs({1,2,6,7}) do h.C.OpenQuickHire(slot,h.env.ShirsRaidBuilderMainFrame); assert(hidden(q),'filled '..slot..' opened quick hire') end
    end
end)

test('active queue or frozen/pending handoff prevents quick add including dialog opened before Execute',function()
    for _,state in ipairs({'running','paused','waiting','authority','await','plan','sort'}) do
        local h=start(); local q=prepare(h,'Class','DPS','Mage'); local before=dump(h:preset())
        if state=='authority' then h.C.handAuthority={}
        elseif state=='await' then h.C.handAwaitLink={}
        elseif state=='plan' then h.C.handRunPlan={}
        elseif state=='sort' then h.C.sortFrame={busy=true}
        else h.env.ShirsRaidBuilderDB.handoff={active={phase=state}} end
        h:click(h:button(q,'Add'))
        assert(hidden(q) and dump(h:preset())==before,'active '..state..' plan mutated')
        h:click(h:empty(9)); assert(hidden(q),'active '..state..' reopened quick hiring')
    end
end)

test('quick dialog does not leave the existing row drag ghost or faded source stuck',function()
    local h=start(); local player
    for _,w in ipairs(h.frames) do if w:IsVisible() and w.scripts.OnDragStart and w.fonts[1] and string.find(w.fonts[1]:GetText(),'Alice',1,true) then player=w end end
    assert(player,'player drag source missing'); player.SetAlpha=function(self,value) self.alpha=value end
    h:fire(player,'OnDragStart','LeftButton')
    assert(player.alpha==0.35)
    local q=h:quick(9)
    assert(player.alpha==1,'quick menu cancelled drag without restoring the row alpha')
    h:click(h:button(q,'Cancel'))
end)

test('persisted Random and Class rows give identical Preview and real Execute commands on both reruns',function()
    for _,branch in ipairs({'Random','Class'}) do
        local h=start(); local q=prepare(h,branch,'DPS',branch=='Class' and 'Mage' or nil)
        h:choose(q.tierButton,'t2d')
        if branch=='Class' then h:choose(q.raceButton,'Gnome'); h:choose(q.genderButton,'Female'); h:choose(q.specButton,'Arcane')
        else h:click(h:button(q,'Add')) end
        local command=h.C.BuildNormalHireCommand(h:preset().entries[9])
        local prefix=branch=='Random' and '^%.z addi Alice t2d ' or '^%.z addinvite Alice t2d '
        assert(command and string.find(command,prefix),'quick tier not used in command')
        local frozen=dump(h:preset().entries[9])
        h.env.math=setmetatable({random=function(n) assert(n==nil,'plan rerolled a concrete choice'); return 0.5 end},{__index=math})
        h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Preview'))
        assert(dump(h:preset().entries[9])==frozen)
        local printed=false; for _,line in ipairs(h.messages) do if string.find(line,command,1,true) then printed=true end end
        assert(printed,'real Preview did not print saved concrete command')
        local copied=assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))()
        local t=start(copied); local C=t.C; local clock=100; local sent={}
        t.env.GetTime=function() return clock end
        t.env.math=setmetatable({random=function(n) assert(n==nil,'reload or Execute rerolled a concrete choice'); return 0.5 end},{__index=math})
        t.env.SendChatMessage=function(text,route,language,target) table.insert(sent,{text=text,route=route,target=target}) end
        t.env.SendAddonMessage=function() end -- Synthetic metadata transport only, never the game.
        assert(C.BuildNormalHireCommand(t:preset().entries[9])==command,'SavedVariables reload changed concrete hire')
        for run=1,2 do
            t:click(t:button(t.env.ShirsRaidBuilderMainFrame,'Preview'))
            assert(table.getn(sent)==run-1,'Preview sent a command')
            t:click(t.env.ShirsRaidBuilderMainFrame.executeBtn)
            for tick=1,120 do
                clock=clock+0.25
                for _,w in ipairs(t.frames) do if w.scripts.OnUpdate and w:IsVisible() then t:fire(w,'OnUpdate',0.25) end end
            end
            assert(table.getn(sent)==run,'Execute sent wrong command count')
            assert(sent[run].route=='SAY' and sent[run].text==command,'Preview/Execute or repeat mismatch')
            assert(dump(t:preset().entries[9])==frozen,'execution changed saved quick entry')
        end
    end
end)

test('Back dismisses a picker dropdown before hiding its owner controls',function()
    local h=start(); local q=prepare(h,'Class','DPS','Mage')
    h:click(q.raceButton); assert(h.env.ShirsRaidBuilderChoiceMenu:IsVisible())
    h:click(h:button(q,'Back'))
    assert(hidden(h.env.ShirsRaidBuilderChoiceMenu),'Back left an orphan dropdown over the class menu')
    h:click(h:button(q,'Mage')); h:click(q.sourceButton)
    h.env.ShirsRaidBuilderEscaper:Hide()
    assert(q:IsVisible() and hidden(h.env.ShirsRaidBuilderCharacterChoices),'source choices must dismiss before the quick dialog')
    h:click(h:button(q,'Cancel'))
end)

test('class confirmation rejects invalid race/gender/spec choices rather than coercing them',function()
    for _,field in ipairs({'raceButton','genderButton','specButton','roleButton'}) do
        local h=start(); local q=prepare(h,'Class','DPS','Mage'); local before=dump(h:preset())
        q[field].label:SetText(field=='raceButton' and 'Dwarf' or field=='roleButton' and 'Tank' or 'Invalid')
        h:click(h:button(q,'Add'))
        assert(dump(h:preset())==before,'invalid '..field..' got silently replaced/added')
    end
end)

test('adding at the clicked slot leaves other rows/profile rules and saved actor identities unchanged',function()
    local db=saved(); db.presets.Other={entries={},denyRules={},setupRules={}}
    db.presets.Default.entries[3]={kind='legacy',charName='Legacy',class='shaman',role='mdps',denyList={'Lightning Bolt'}}
    db.presets.Default.entries[4]={kind='guest',companionName='Guest',class='priest',role='healer'}
    db.presets.Default.denyRules={{class='mage',role='all',abilities={'Frost Nova'}}}
    local h=start(db); local q=prepare(h,'Class','DPS','Mage'); local p=h:preset(); local empty=p.entries[9]
    local before=dump(h.env.ShirsRaidBuilderDB.presets); local identity=h.env.ShirsRaidBuilderDB.syncAccountId
    h:click(h:button(q,'Add')); local added=p.entries[9]
    assert(added.kind=='normal' and h.env.ShirsRaidBuilderDB.syncAccountId==identity)
    p.entries[9]=empty; assert(dump(h.env.ShirsRaidBuilderDB.presets)==before,'quick add changed data outside its own slot'); p.entries[9]=added
    local row
    for _,w in ipairs(h.frames) do if w:IsVisible() and w.scripts.OnMouseUp and w.fonts[1] and w.fonts[1]:GetText()=='9 Alice' then row=w end end
    assert(row,'concrete result row missing')
    local lines={}; h.env.GameTooltip.AddLine=function(self,line) table.insert(lines,line) end
    h:fire(row,'OnEnter')
    local detail=false
    for _,line in ipairs(lines) do if string.find(line,'Human',1,true) and string.find(line,'Male',1,true) then detail=true end end
    assert(detail,'concrete race/gender outcome is not shown by the normal row')
end)

test('actual local Execute starting mid-dialog cannot add to the active plan',function()
    local db=saved(); db.presets.Default.entries[2]={kind='normal',account='Alice',tier='t0d',class='mage',role='rdps',spec='frost',race='human',gender='female'}
    local h=start(db); local q=prepare(h,'Random','Tank'); local before=dump(h:preset()); local sent={}
    h.env.SendChatMessage=function(text) table.insert(sent,text) end
    h.env.SendAddonMessage=function() end
    h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn)
    assert(table.getn(sent)==1 and sent[1]=='.z addinvite Alice t0d mage rdps frost human female','fixture must start real local execution')
    h:click(h:button(q,'Add'))
    assert(hidden(q) and dump(h:preset())==before and table.getn(sent)==1,'quick add changed or sent from a running local plan')
    h:click(h:empty(9)); assert(hidden(q))
end)

if failures>0 then error(tostring(failures)..' quick hire regression(s) failed') end
print("Shir's Raid Builder quick hire tests: PASS ("..passes.." cases)")
