-- Real constructors and registered Vanilla handlers, synthetic UI/no chat.
local f=assert(io.open('test_individual_editor.lua','r')); local text=f:read('*a'); f:close()
local at=assert(string.find(text,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(text,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(name,fn) local ok,e=pcall(fn); if ok then pass=pass+1; print('PASS '..name) else fail=fail+1; print('FAIL '..name..': '..tostring(e)) end end
local function dump(v)
    if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end
    local keys,out={},{}; for k in pairs(v) do table.insert(keys,k) end; table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do table.insert(out,'['..dump(k)..']='..dump(v[k])) end; return '{'..table.concat(out,',')..'}'
end
local function saved()
    return {currentPreset='Default',presets={Default={entries={{kind='player',charName='Alice',class='warrior',role='tank'},
        {kind='legacy',charName='Bravo',sourceName='Bravo',class='priest',role='healer',denyList={'Holy Nova'}}},
        denyRules={{class='priest',role='healer',abilities={'Holy Nova'}}},setupRules={}}},
        inviteCharacters={Alice={name='Alice',level=60,raidLicense='t3r',dungeonLicense='t2d',faction='Alliance'},
            Bravo={name='Bravo',level=60,raidLicense='t2r',dungeonLicense='t1d',faction='Alliance'},
            Hordealt={name='Hordealt',level=60,raidLicense='t2r',dungeonLicense='none',faction='Horde'}},
        legacyCharacters={alice='warrior',bravo='priest',hordealt='shaman'},legacyCharacterRoles={alice='tank',bravo='healer',hordealt='healer'}}
end
local function start(db)
    local h=boot(db or saved(),'Alice')
    h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Raid Builder'))
    local p=assert(h.env.ShirsRaidBuilderPlanner,'planner window missing'); assert(p:IsVisible())
    function h:source(name)
        for _,row in ipairs(p.sourceRows) do if row.source and row.source.name==name then return row end end
        error('source not displayed: '..name)
    end
    function h:select(name,tier,legacy)
        local row=self:source(name); if not row.normalCheck:GetChecked() then row.normalCheck:SetChecked(1); self:fire(row.normalCheck,'OnClick') end
        self:choose(row.tierButton,tier or 't1r')
        if legacy then row.legacyCheck:SetChecked(1); self:fire(row.legacyCheck,'OnClick') end
        return row
    end
    function h:counts(key,n) self:click(self:button(p,'Composition')); p.countInputs[key]:SetText(tostring(n)) end
    function h:build() self:click(self:button(p,'Build Proposal')); return p.proposal end
    return h,p
end

test('launcher is Hire-only at old status area; independent modal and harmless Cancel',function()
    local h,p=start(); local main=h.env.ShirsRaidBuilderMainFrame
    assert(main.plannerBtn.point[4]==310 and main.plannerBtn.point[5]==-8)
    assert(p:GetFrameStrata()=='FULLSCREEN_DIALOG' and p.topLevel and p.dragBar)
    local before=dump(h:preset()); h:select('Alice','t1r',true); h:counts('mage:rdps',2)
    h:click(h:button(p,'Cancel')); assert(not p:IsVisible() and before==dump(h:preset()))
    h:click(h:button(main,'Sort Mode')); assert(not main.plannerBtn:IsVisible())
end)
test('actual source/tier/legacy controls survive tab/count edits and build shows exact allocation',function()
    local h,p=start(); h:select('Alice','t2d',true); h:select('Bravo','t1r',true)
    h:counts('mage:rdps',4); h:counts('paladin:healer',1)
    h:click(h:button(p,'Sources'))
    assert(h:source('Alice').normalCheck:GetChecked() and h:source('Alice').legacyCheck:GetChecked())
    assert(h:source('Alice').tierButton.label:GetText()=='t2d')
    local before=dump(h:preset()); local r=assert(h:build()); assert(r.normal==5 and r.legacy==2 and r.player==1 and r.total==8)
    assert(string.find(p.previewText:GetText(),'T2D',1,true) and string.find(p.previewText:GetText(),'Estimated total:',1,true))
    for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then assert(e.gender=='female','compact display changed saved gender') end end
    assert(before==dump(h:preset()) and p.applyButton:IsEnabled())
    assert(string.find(p.countSummary:GetText(),'Normal 5',1,true),'live count summary missing')
end)
test('new profile is default and atomically copies rules and fixed anchors without touching source',function()
    local h,p=start(); local db=h.env.ShirsRaidBuilderDB; local original=h:preset(); local before=dump(original)
    h:select('Alice','t1r'); h:counts('mage:rdps',2); assert(h:build())
    p.nameInput:SetText('Composition A'); h:click(p.applyButton)
    assert(db.currentPreset=='Composition A' and db.presets.Default==original and dump(original)==before)
    local plan=h:preset(); local kept=false; for _,e in ipairs(plan.entries) do if e.kind=='legacy' and e.sourceName=='Bravo' then kept=true end end
    assert(plan.entries[40].kind=='player' and kept and plan.denyRules[1].abilities[1]=='Holy Nova')
    assert(plan.denyRules~=original.denyRules and not p:IsVisible())
    local restored=boot(assert(loadstring('return '..dump(db)))(),'Alice'); assert(restored.env.ShirsRaidBuilderDB.presets['Composition A'])
end)
test('replace requires one named warning; Cancel warning changes nothing; confirms staged exact rows',function()
    local h,p=start(); h:select('Alice','t1r'); h:counts('mage:rdps',1); assert(h:build())
    p.replaceCheck:SetChecked(1); h:fire(p.replaceCheck,'OnClick')
    local original=h:preset(); local before=dump(original); h:click(p.applyButton)
    assert(p.confirmFrame:IsVisible() and string.find(p.confirmText:GetText(),'Default',1,true)); assert(before==dump(original))
    h:click(h:button(p.confirmFrame,'Cancel')); assert(before==dump(h:preset()) and h:preset()==original)
    h:click(p.applyButton); h:click(h:button(p.confirmFrame,'Replace'))
    assert(h:preset()~=original and h:preset().denyRules[1].abilities[1]=='Holy Nova')
end)
test('count/source/default edits invalidate proposal; failed build keeps plan and selections',function()
    local h,p=start(); h:select('Alice','t1r'); h:counts('mage:rdps',2); assert(h:build())
    h:counts('mage:rdps',3); assert(not p.proposal and not p.applyButton:IsEnabled())
    h:counts('mage:rdps',5); local before=dump(h:preset()); assert(not h:build())
    assert(before==dump(h:preset()) and string.len(p.message:GetText())>0)
    h:click(h:button(p,'Sources')); assert(h:source('Alice').tierButton.label:GetText()=='t1r')
end)
test('explicit per-class race/spec and global gender appear in concrete generated rows',function()
    local h,p=start(); h:select('Alice','t1r'); h:counts('mage:rdps',2)
    h:choose(p.classDefaults.mage.raceButton,'gnome'); h:choose(p.classDefaults.mage.specButton,'fire'); h:choose(p.genderButton,'male')
    local r=assert(h:build()); for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then assert(e.race=='gnome' and e.spec=='fire' and e.gender=='male') end end
end)
test('unknown legacy role has explicit supported role control, never player role fallback',function()
    local db=saved(); db.legacyCharacterRoles.alice=nil
    local h,p=start(db); local row=h:source('Alice'); row.legacyCheck:SetChecked(1); h:fire(row.legacyCheck,'OnClick')
    assert(not h:build()); h:click(h:button(p,'Sources')); h:choose(row.roleButton,'mdps')
    local r=assert(h:build()); local found=false
    for _,e in ipairs(r.plan.entries) do if e.kind=='legacy' and e.sourceName=='Alice' then found=true; assert(e.role=='mdps') end end; assert(found)
end)
test('Escape child dropdown then planner; parent hide/mode/profile invalidate stale proposal',function()
    local h,p=start(); h:click(h:source('Alice').tierButton); h.env.ShirsRaidBuilderEscaper:Hide()
    assert(p:IsVisible() and not h.env.ShirsRaidBuilderChoiceMenu:IsVisible()); h.env.ShirsRaidBuilderEscaper:Hide(); assert(not p:IsVisible())
    h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Raid Builder')); h:select('Alice','t1r'); h:counts('mage:rdps',1); assert(h:build())
    local before=dump(h.env.ShirsRaidBuilderDB.presets); h.env.ShirsRaidBuilderDB.presets.Default.entries[5]={kind='guest',companionName='Bob',class='mage',role='rdps'}
    before=dump(h.env.ShirsRaidBuilderDB.presets); h:click(p.applyButton); assert(before==dump(h.env.ShirsRaidBuilderDB.presets))
    h.env.ShirsRaidBuilderMainFrame:Hide(); assert(not p:IsVisible())
end)
test('highest default, fractional counts, duplicate target name and active run guards',function()
    local h,p=start(); local row=h:source('Alice'); row.normalCheck:SetChecked(1); h:fire(row.normalCheck,'OnClick'); h:counts('mage:rdps',1)
    assert(h:build()); h:click(h:button(p,'Sources')); h:choose(row.tierButton,'t1r'); h:counts('mage:rdps','1.5'); assert(not h:build())
    h:counts('mage:rdps',1); assert(h:build()); p.nameInput:SetText('Default'); local before=dump(h.env.ShirsRaidBuilderDB.presets); h:click(p.applyButton); assert(before==dump(h.env.ShirsRaidBuilderDB.presets))
    p.nameInput:SetText('New'); h.C.handAuthority='busy'; h:click(p.applyButton); assert(before==dump(h.env.ShirsRaidBuilderDB.presets))
end)
test('remembered and partial live sources are unioned, malformed snapshots do not grant identity',function()
    local db=saved(); db.peerLinks={}; db.peerSnapshots={}
    local h,p=start(db); local C=h.C
    local function remember(peer,id,name,tier)
        local link=C.PeerNew('Alice',peer,'FixtureRealm'); link.phase='linked'; assert(C.LinkSave(db.peerLinks,link,true))
        local snap={accountId=id,source=string.lower(peer),realm='FixtureRealm',received=1800000000,observed=1800000000,authoritative=false,
            entries={{name=name,level=60,dungeonLicense='none',raidLicense=tier,faction='Alliance',observed=1800000000}}}
        db.peerSnapshots['FixtureRealm;'..string.lower(peer)]=snap
        return snap
    end
    local first=remember('Peerone','2222222222222222','Remoteone','t2r')
    remember('Peertwo','3333333333333333','Remotetwo','t3r')
    h.C.remoteLicenses={}
    local function inventory() local by={}; for _,s in ipairs(C.PlannerReadSources()) do by[s.name]=s end; return by end
    local by=inventory(); assert(by.Remoteone and by.Remotetwo,'empty live table hid remembered accounts')
    assert(string.find(by.Alice.freshness,'not live',1,true),'a saved local list was presented as live eligibility')
    h.C.remoteLicenses['FixtureRealm;peerone']=first
    by=inventory(); assert(by.Remotetwo and by.Remoteone.endpoint=='Peerone' and not by.Remoteone.live,'partial live table hid second account or granted spend')
    h.C.remoteLicenses['FixtureRealm;peerone']={source='peerone',accountId='bad',entries={}}
    by=inventory(); assert(by.Remoteone and by.Remoteone.accountId=='2222222222222222','bad live metadata replaced established source')
    h.C.remoteLicenses['not-canonical']=first
    C.LinkForget(db.peerLinks,'Alice','Peertwo','FixtureRealm',true)
    by=inventory(); assert(not by.Remotetwo and by.Remoteone,'untrusted/canonical-key data entered selectable union')
end)

test('single source view preserves independent tier and legacy choices across more than five rows',function()
    local db=saved()
    for _,name in ipairs({'Charlie','Delta','Echo','Foxtrot','Golf','Hotel','India'}) do
        db.inviteCharacters[name]={name=name,level=60,raidLicense='t3r',dungeonLicense='t2d',faction='Alliance'}
        db.legacyCharacters[string.lower(name)]='priest'; db.legacyCharacterRoles[string.lower(name)]='healer'
    end
    local h,p=start(db); h:select('Alice','t2d',true)
    assert(not p.nextSources and not p.previousSources and table.getn(p.sourceRows)==10)
    local name=p.sourceRows[10].source.name; h:select(name,'t3r',true)
    h:counts('mage:rdps',4); h:click(h:button(p,'Sources')); assert(not p.sourcePage)
    assert(h:source(name).tierButton.label:GetText()=='t3r' and h:source(name).legacyCheck:GetChecked())
    assert(h:source('Alice').tierButton.label:GetText()=='t2d' and h:source('Alice').legacyCheck:GetChecked())
    local r=assert(h:build()); assert(r.normal==4 and r.legacy==3)
    local tiers={}; for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then tiers[e.account]=e.tier end end
    assert(tiers.Alice=='t2d' and tiers[name]=='t3r')
end)

test('planner uses completed shared dropdown toggle and owner lifecycle without resetting sources',function()
    local h,p=start(); local row=h:select('Alice','t1r',true)
    h:click(row.tierButton); assert(h.env.ShirsRaidBuilderChoiceMenu:IsVisible())
    h:click(row.tierButton); assert(not h.env.ShirsRaidBuilderChoiceMenu:IsVisible(),'second click left menu')
    h:click(row.tierButton); h:click(h:button(p,'Composition')); assert(not h.env.ShirsRaidBuilderChoiceMenu:IsVisible())
    local button=p.classDefaults.mage.raceButton
    h:click(button); h:click(button); assert(not h.env.ShirsRaidBuilderChoiceMenu:IsVisible())
    h:click(button); p:Hide(); assert(not h.env.ShirsRaidBuilderChoiceMenu:IsVisible(),'hidden planner left orphan')
    h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Raid Builder')); row=h:select('Alice','t1r')
    h:click(row.tierButton); h.env.ShirsRaidBuilderEscaper:Hide(); assert(p:IsVisible() and not h.env.ShirsRaidBuilderChoiceMenu:IsVisible())
end)

test('40-slot preview is scrollable to group eight with wrapped text budget and role totals',function()
    local db=saved(); db.presets.Default.entries={}
    for _,name in ipairs({'Charlie','Delta','Echo','Foxtrot','Golf','Hotel','India'}) do
        db.inviteCharacters[name]={name=name,level=60,raidLicense='t3r',dungeonLicense='t2d',faction='Alliance'}
    end
    local h,p=start(db)
    for _,s in ipairs(p.sources) do p.request.sources[s.key]={selected=true,tier='t1r'} end
    h:counts('mage:rdps',39); local r=assert(h:build(),p.message:GetText()); assert(r.total==40 and r.player==1)
    assert(string.find(p.previewText:GetText(),'Group 8',1,true) and string.find(p.previewText:GetText(),'40.',1,true))
    assert(string.find(p.previewText:GetText(),'Ranged DPS 39',1,true),'four-role summary missing')
    local budget=40; for line in string.gfind(p.previewText:GetText()..'\n','([^\n]*)\n') do budget=budget+math.max(1,math.ceil(string.len(line)/85))*16 end
    assert(p.previewContent:GetHeight()>=budget,'wrapped text can be cut off')
    h:fire(p.previewScroll,'OnMouseWheel',-1); assert(p.previewSlider:GetValue()>0 and p.previewScroll:GetVerticalScroll()==p.previewSlider:GetValue())
    p.previewSlider:SetValue(p.previewMax); assert(p.previewScroll:GetVerticalScroll()==p.previewContent:GetHeight()-p.previewScroll:GetHeight())
end)

test('changed licence or remembered legacy role after proposal rejects Apply with no write',function()
    for _,changed in ipairs({'tier','legacy'}) do
        local h,p=start(); h:select('Alice','t3r',true); h:counts('mage:rdps',1); assert(h:build())
        local before=dump(h.env.ShirsRaidBuilderDB.presets)
        if changed=='tier' then
            for _,row in ipairs(h.env.ShirsRaidBuilderDB.localAccountRows.FixtureRealm) do if row.name=='Alice' then row.raidLicense='t1r' end end
            h.env.ShirsRaidBuilderDB.inviteCharacters.Alice.raidLicense='t1r'
        else h.env.ShirsRaidBuilderDB.legacyCharacterRoles.alice='mdps' end
        h:click(p.applyButton); assert(not p.proposal and not p.applyButton:IsEnabled() and before==dump(h.env.ShirsRaidBuilderDB.presets))
    end
end)

print("Shir's Raid Builder planner UI tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('planner UI regressions failed') end
