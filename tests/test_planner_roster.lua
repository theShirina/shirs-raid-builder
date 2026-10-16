-- Real launcher and registered handlers under strict Vanilla widget types.
local f=assert(io.open('test_individual_editor.lua')); local text=f:read('*a'); f:close()
local at=assert(string.find(text,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(text,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(name,fn) local ok,e=pcall(fn); if ok then pass=pass+1; print('PASS '..name) else fail=fail+1; print('FAIL '..name..': '..tostring(e)) end end
local function dump(v)
    if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end
    local keys,out={},{}; for k in pairs(v) do table.insert(keys,k) end; table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do table.insert(out,'['..dump(k)..']='..dump(v[k])) end; return '{'..table.concat(out,',')..'}'
end
local function saved(n)
    local db={syncAccountId='1111111111111111',currentPreset='Default',presets={Default={entries={{kind='player',charName='Alice',class='warrior',role='tank'}},denyRules={},setupRules={}}},inviteCharacters={},legacyCharacters={},legacyCharacterRoles={}}
    local names={'Alice','Bravo','Charlie','Delta','Echo','Foxtrot','Golf','Hotel','India','Juliet','Kilo','Lima','Mike','November','Oscar','Papa','Quebec','Romeo','Sierra','Tango','Uniform','Victor','Whiskey','Xray','Yankee','Zulu'}
    for i=1,n or 10 do local name=names[i] or ('Alt'..string.char(65+math.floor((i-1)/26))..string.char(65+math.mod(i-1,26)))
        db.inviteCharacters[name]={name=name,level=60,dungeonLicense='t5d',raidLicense='t2r',faction='Alliance'}
        db.legacyCharacters[string.lower(name)]='priest'; db.legacyCharacterRoles[string.lower(name)]='healer'
    end
    return db
end
local function start(db)
    local h=boot(db or saved(),'Alice'); h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn)
    local p=h.C.plannerFrame; assert(p:IsVisible() and p.nameInput.Enable==nil)
    function h:row(name) for _,r in ipairs(p.sourceRows) do if r.source and r.source.name==name then return r end end; error('missing source '..name) end
    function h:reopen() p:Hide(); self:click(self.env.ShirsRaidBuilderMainFrame.plannerBtn) end
    return h,p
end
local function toggle(h,w,value) w:SetChecked(value and 1 or nil); h:fire(w,'OnClick') end
local function checkGeometry(p)
    local boxes={}
    for _,row in ipairs(p.sourceRows) do if row.source then
        local x,y=row.point[4],-row.point[5]; local w,h=row:GetWidth(),row:GetHeight()
        assert(x>=0 and x+w<=p.sourceContent:GetWidth() and y>=0 and y+h<=p.sourceContent:GetHeight(),'source outside scroll content')
        for _,b in ipairs(boxes) do assert(x>=b.x+b.w or b.x>=x+w or y>=b.y+b.h or b.y>=y+h,'source cells overlap') end
        table.insert(boxes,{x=x,y=y,w=w,h=h})
        for _,control in ipairs({row.normalCheck,row.tierButton,row.legacyCheck,row.roleButton}) do
            local cx,cy=control.point[4],-control.point[5]
            assert(cx>=0 and cx+control:GetWidth()<=w and cy>=0 and cy+control:GetHeight()<=h,'control clipped')
        end
        assert(row.normalCheck.label:GetWidth()>=84 and row.legacyCheck.label:GetWidth()>=42,'label lacks readable budget')
        assert(row.tierButton:GetWidth()>=58 and row.roleButton:GetWidth()>=110)
    end end
    return table.getn(boxes)
end

test('twenty ordinary sources fit one readable multicolumn view without paging/scrolling',function()
    local h,p=start(saved(20)); assert(not p.nextSources and not p.previousSources and not p.sourcePage,'paging remains')
    assert(checkGeometry(p)==20 and p.sourceMax==0 and not p.sourceSlider:IsShown(),'ordinary full roster requires scrolling')
    assert(p.sourceScroll:GetHeight()<=p.panels.sources:GetHeight())
    for _,row in ipairs(p.sourceRows) do assert(row:IsVisible() and row.normalCheck:IsVisible() and row.legacyCheck:IsVisible() and row.tierButton:IsVisible()) end
    h:choose(h:row('Tango').tierButton,'t1d'); toggle(h,h:row('Tango').normalCheck,true)
    assert(p.request.sources[h:row('Tango').source.key].selected)
end)
test('overflow has one continuous reachable scroll, never pages or clipped controls',function()
    local h,p=start(saved(42)); assert(checkGeometry(p)==42 and p.sourceMax>0 and p.sourceSlider:IsShown())
    h:fire(p.sourceScroll,'OnMouseWheel',-1); assert(p.sourceScroll:GetVerticalScroll()>0)
    p.sourceSlider:SetValue(p.sourceMax); assert(p.sourceScroll:GetVerticalScroll()==p.sourceContent:GetHeight()-p.sourceScroll:GetHeight())
    local last=p.sourceRows[42]; assert(-last.point[5]+last:GetHeight()<=p.sourceContent:GetHeight())
    toggle(h,last.normalCheck,true); assert(p.request.sources[last.source.key].selected)
    assert(not p.nextSources and not p.previousSources)
end)
test('highest verified tier is default; lower override and explicit unchecked state survive reopen and reload',function()
    local h,p=start(); local row=h:row('Alice'); assert(row.tierButton.label:GetText()=='t2r' and not row.normalCheck:GetChecked())
    toggle(h,row.normalCheck,true); h:choose(row.tierButton,'t1d'); toggle(h,row.legacyCheck,true); h:choose(row.roleButton,'rdps')
    toggle(h,h:row('Bravo').normalCheck,true); toggle(h,h:row('Bravo').normalCheck,false)
    local before=dump(h:preset()); h:reopen(); row=h:row('Alice')
    assert(row.normalCheck:GetChecked() and row.legacyCheck:GetChecked() and row.tierButton.label:GetText()=='t1d' and row.roleButton.label:GetText()=='rdps')
    assert(not h:row('Bravo').normalCheck:GetChecked() and before==dump(h:preset()))
    local restored=assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))(); h,p=start(restored); row=h:row('Alice')
    assert(row.normalCheck:GetChecked() and row.legacyCheck:GetChecked() and row.tierButton.label:GetText()=='t1d' and row.roleButton.label:GetText()=='rdps')
end)
test('preferences are local-account/realm/full-source scoped; new same-name remote identity never inherits selection',function()
    local h,p=start(); toggle(h,h:row('Alice').normalCheck,true); h:choose(h:row('Alice').tierButton,'t1d')
    local db=h.env.ShirsRaidBuilderDB; local other=assert(loadstring('return '..dump(db)))(); other.syncAccountId='9999999999999999'
    local h2,p2=start(other); assert(not h2:row('Alice').normalCheck:GetChecked() and h2:row('Alice').tierButton.label:GetText()=='t2r')
    local C=h.C; local s={key='old',name='Remote',accountId='2222222222222222',eligible=true,tiers={'t0d','t3r'}}
    assert(C.PlannerSaveSource(db,'FixtureRealm',s,{selected=true,tier='t1r',includeLegacy=true}))
    local sel=C.PlannerRestoreSources(db,'OtherRealm',{s}); assert(not sel.old.selected)
    s.accountId='3333333333333333'; s.key='new'; sel=C.PlannerRestoreSources(db,'FixtureRealm',{s}); assert(not sel.new.selected and not sel.new.includeLegacy)
    s.accountId='2222222222222222'; s.key='old'; sel=C.PlannerRestoreSources(db,'FixtureRealm',{s}); assert(sel.old.selected)
end)
test('removed chosen tier stays visibly unavailable and cannot silently upgrade; unknown source gets no default',function()
    local h,p=start(); toggle(h,h:row('Alice').normalCheck,true); h:choose(h:row('Alice').tierButton,'t2r')
    for _,r in ipairs(h.env.ShirsRaidBuilderDB.localAccountRows.FixtureRealm) do if r.name=='Alice' then r.raidLicense='t1r' end end
    h.env.ShirsRaidBuilderDB.inviteCharacters.Alice.raidLicense='t1r'; h:reopen()
    local row=h:row('Alice'); assert(row.tierButton.label:GetText()=='t2r' and string.find(row.warning,'unavailable',1,true))
    h:click(h:button(p,'Composition')); p.countInputs['mage:rdps']:SetText('1'); h:click(p.buildButton); assert(not p.proposal)
    local db=saved(2); db.inviteCharacters.Bravo.dungeonLicense='unknown'; h,p=start(db); row=h:row('Bravo')
    assert(row.tierButton.label:GetText()~='t0d' and not row.normalCheck:IsEnabled() and string.find(row.warning,'unknown',1,true))
end)
test('primary source text is short; identity stays optional and actionable warnings remain',function()
    local h,p=start(); local row=h:row('Alice'); local detail=row.warning
    assert(not string.find(detail,'account',1,true) and not string.find(detail,'remembered',1,true) and not string.find(detail,'11111111',1,true))
    assert(row.normalCheck.tip and string.find(row.normalCheck.tip,'1111111111111111',1,true),'optional full identity missing')
    row.source.conflict=true; row.source.eligible=false; row.source.reason='account identity is ambiguous'; h.C.PlannerPaintSources()
    assert(string.find(row.warning,'ambiguous',1,true) and not row.normalCheck:IsEnabled() and not row.legacyCheck:IsEnabled())
end)
test('Auto and Custom actual controls preserve sources, invalidate only proposal, and persist valid order',function()
    local h,p=start(saved(2)); local before=dump(h:preset()); toggle(h,h:row('Alice').normalCheck,true); h:choose(h:row('Alice').tierButton,'t1d')
    h:click(h:button(p,'Tier priority')); assert(p.priorityMode.label:GetText()=='Auto')
    assert(string.find(p.priorityOrder:GetText(),'Tanks > Melee DPS > Mage > Warlock > RDPS > Healers',1,true))
    h:choose(p.priorityMode,'Custom'); assert(table.getn(p.priorityRows)==table.getn(h.C.PlannerAutoOrder()))
    local index; for i,id in ipairs(p.request.customOrder) do if id=='priest:healer' then index=i end end
    while index>1 do h:click(p.priorityRows[index].up); index=index-1 end
    assert(p.request.customOrder[1]=='priest:healer' and string.find(p.priorityRows[1].label:GetText(),'Priest Healer',1,true))
    local sourceBefore=dump(p.request.sources); p.proposal={sentinel=true}; p.applyButton:Enable()
    h:choose(p.priorityMode,'Auto'); assert(not p.proposal and not p.applyButton:IsEnabled() and dump(p.request.sources)==sourceBefore and before==dump(h:preset()))
    assert(not p.priorityRows[1].down:IsEnabled()); h:choose(p.priorityMode,'Custom'); assert(p.request.customOrder[1]=='priest:healer')
    local db=assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))(); h,p=start(db)
    assert(p.request.priorityMode=='custom' and p.request.customOrder[1]=='priest:healer' and h:row('Alice').tierButton.label:GetText()=='t1d' and h:row('Alice').normalCheck:GetChecked())
end)
test('malformed persisted modes/orders fail safely without losing any role',function()
    local h,p=start(); local db=h.env.ShirsRaidBuilderDB
    for _,order in ipairs({{}, {'tank','tank','rdps','healer'},{'tank','mdps','rdps'},{'tank','mdps','rdps','bogus'},{'healer','rdps','mdps','tank','extra'}}) do
        local mode,custom=h.C.PlannerLoadPriority({priorityMode='custom',customOrder=order})
        assert(mode=='auto' and dump(custom)==dump(h.C.PlannerAutoOrder()))
    end
    local mode,custom=h.C.PlannerLoadPriority(nil); assert(mode=='auto' and table.getn(custom)==table.getn(h.C.PlannerAutoOrder()))
    local sel=h.C.PlannerRestoreSources({syncAccountId=db.syncAccountId,plannerPreferences='bad'},'FixtureRealm',p.sources)
    for _,s in ipairs(p.sources) do assert(not sel[s.key].selected and sel[s.key].tier=='t2r') end
end)
print("Shir's Raid Builder planner roster tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('planner roster regressions failed') end
