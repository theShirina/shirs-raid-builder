-- Synthetic exact-Lua player-anchor, composition totals and tank grouping tests.
local f=assert(io.open('test_individual_editor.lua')); local text=f:read('*a'); f:close()
local at=assert(string.find(text,'\nlocal failures, passes=',1,true)); local boot=assert(loadstring(string.sub(text,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(name,fn) local ok,e=pcall(fn); if ok then pass=pass+1; print('PASS '..name) else fail=fail+1; print('FAIL '..name..': '..tostring(e)) end end
local function dump(v)
    if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end
    local keys,out={},{}; for k in pairs(v) do table.insert(keys,k) end; table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do table.insert(out,'['..dump(k)..']='..dump(v[k])) end; return '{'..table.concat(out,',')..'}'
end
local function start(entries)
    entries=entries or {}; for i=1,40 do if not entries[i] then entries[i]={kind='empty'} end end
    local db={currentPreset='Default',presets={Default={entries=entries or {},denyRules={},setupRules={}}},inviteCharacters={},legacyCharacters={bravo='druid',charlie='priest'},legacyCharacterRoles={bravo='mdps',charlie='healer'}}
    for _,name in ipairs({'Alice','Bravo','Charlie','Delta','Echo','Foxtrot','Golf','Hotel','India','Juliet'}) do db.inviteCharacters[name]={name=name,level=60,dungeonLicense='t2d',raidLicense='t5r',faction='Alliance'} end
    local h=boot(db,'Alice'); h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn); local p=h.C.plannerFrame
    function h:row(name) for _,r in ipairs(p.sourceRows) do if r.source and r.source.name==name then return r end end; error('missing source') end
    function h:legacy(name,value) local r=self:row(name); r.legacyCheck:SetChecked(value and 1 or nil); self:fire(r.legacyCheck,'OnClick') end
    function h:select(name) local r=self:row(name); r.normalCheck:SetChecked(1); self:fire(r.normalCheck,'OnClick') end
    function h:counts(key,n) self:click(self:button(p,'Composition')); p.countInputs[key]:SetText(tostring(n)) end
    function h:build() self:click(p.buildButton); return assert(p.proposal,p.message:GetText()) end
    return h,p
end
local function selfCount(entries) local n=0; for _,e in ipairs(entries) do if e.kind=='player' and e.charName=='Alice' then n=n+1 end end; return n end

test('current runtime player reserves40 before grouping on empty/new and existing-self plans',function()
    for _,old in ipairs({{},{{kind='player',charName='Alice',class='warrior',role='tank'}}}) do
        local h,p=start(old); h:select('Bravo'); h:counts('rogue:mdps',2); local r=h:build()
        assert(r.plan.entries[40].kind=='player' and r.plan.entries[40].charName=='Alice' and selfCount(r.plan.entries)==1)
        assert(r.plan.entries[1].kind=='normal' and r.total==3 and r.groups==8 and r.plan.plannerPlayerSlot==40)
        assert(r.plan.entries[40].charName~='Bravo','hire-from was mistaken for player')
        local again=h:build(); assert(dump(r.plan)==dump(again.plan),'repeat build moved groups')
    end
end)
test('occupied40 stages safe visible relocation, preserving unrelated fixed human/legacy rows',function()
    local entries={{kind='player',charName='Alice',class='warrior',role='tank'}}
    entries[12]={kind='legacy',sourceName='Charlie',charName='Charlie',class='priest',role='healer'}
    entries[40]={kind='guest',companionName='Human',charName='Human',class='mage',role='rdps'}
    local h,p=start(entries); h:select('Bravo'); h:counts('mage:rdps',1); local r=h:build()
    assert(r.plan.entries[40].charName=='Alice' and r.plan.entries[1].charName=='Human')
    local kept=false; for _,e in ipairs(r.plan.entries) do if e.kind=='legacy' and e.sourceName=='Charlie' then kept=true end end; assert(kept,'legacy identity lost')
    assert(r.total==4 and r.guest==1 and r.legacy==1 and string.find(table.concat(r.notes,' '),'40',1,true))
end)
test('39 companions plus self fits; 40 companions plus self fails without overwrite',function()
    local h,p=start(); for _,s in ipairs(p.sources) do p.request.sources[s.key].selected=true end
    h:counts('mage:rdps',39); local r=h:build(); assert(r.total==40 and r.normal==39 and selfCount(r.plan.entries)==1 and r.plan.entries[40].kind=='player')
    local before=dump(h:preset()); h:counts('mage:rdps',40); h:click(p.buildButton); assert(not p.proposal and string.find(p.message:GetText(),'40',1,true) and before==dump(h:preset()))
end)
test('Create Plan registered handler and refresh/reload retain self40 and exact proposed companion groups',function()
    local h,p=start(); h:select('Bravo'); h:counts('rogue:mdps',2); local r=h:build(); local expected=dump(r.plan.entries)
    p.nameInput:SetText('Generated'); h:click(p.applyButton)
    assert(h.env.ShirsRaidBuilderDB.currentPreset=='Generated' and dump(h:preset().entries)==expected and h:preset().entries[1].kind=='normal' and h:preset().entries[40].charName=='Alice')
    h.env.RefreshComposition(); assert(dump(h:preset().entries)==expected)
    local restored=boot(assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))(),'Alice')
    assert(dump(restored:preset().entries)==expected and selfCount(restored:preset().entries)==1)
    for _,item in ipairs(h.C.BuildQueue(h:preset())) do assert(item.kind~='player','queue hires player') end
end)
test('selected legacies count by verified class/role with existing-anchor dedupe and exact proposal totals',function()
    local h,p=start({{kind='player',charName='Alice',class='warrior',role='tank'},
        {kind='legacy',sourceName='Charlie',charName='Charlie',class='priest',role='healer'}})
    h:select('Alice'); h:legacy('Bravo',true); h:legacy('Charlie',true); h:counts('mage:rdps',2)
    local totals=h.C.PlannerCompositionTotals(p.base,p.sources,p.request)
    assert(totals.total==5 and totals.normal==2 and totals.legacy==2 and totals.player==1 and totals.roles.mdps==1 and totals.roles.healer==1 and totals.roles.tank==0 and totals.roles.rdps==2)
    assert(string.find(p.countSummary:GetText(),'Occupied 5/40',1,true) and string.find(p.countSummary:GetText(),'Legacy 2',1,true))
    local r=h:build(); local companions={};for _,e in ipairs(r.plan.entries) do if e.kind=='normal' or e.kind=='legacy' then table.insert(companions,e) end end
    assert(r.total==totals.total and r.legacy==totals.legacy and dump(h.C.CountRoles(companions))==dump(totals.roles))
    h:click(h:button(p,'Sources')); h:legacy('Bravo',false); assert(string.find(p.countSummary:GetText(),'Occupied 4/40',1,true))
    h:legacy('Bravo',true); h:choose(h:row('Bravo').roleButton,'rdps')
    totals=h.C.PlannerCompositionTotals(p.base,p.sources,p.request); assert(totals.roles.mdps==0 and totals.roles.rdps==3)
end)
test('slot40 player marker preserves other human player rows during actual Apply refresh',function()
    local h,p=start(); local other={kind='player',charName='Human',class='mage',role='rdps'}
    p.base.entries[18]=other; p.preset.entries[18]=h.C.PlannerCopy(other)
    h:select('Bravo'); h:counts('mage:rdps',1); local r=h:build(); p.nameInput:SetText('Humans'); h:click(p.applyButton)
    assert(h:preset().entries[39].charName=='Human' and h:preset().entries[40].charName=='Alice' and h.C.FilledCount(h:preset().entries)==3)
end)
test('Warrior tanks co-locate but Druid/Paladin tanks do not gain that class-only preference',function()
    local h,p=start(); local C=h.C
    assert(C.PlannerPair({kind='normal',class='warrior',role='tank'},{kind='normal',class='warrior',role='tank'})>0)
    assert(C.PlannerPair({kind='normal',class='druid',role='tank'},{kind='normal',class='paladin',role='tank'})<=0)
    for _,n in ipairs({3,7}) do
        local entries,tanks={},{}; for i=1,40 do entries[i]={kind='empty'} end
        for i=1,n do local e={kind='normal',class='warrior',role='tank',account='Tank'..i}; entries[(i-1)*5+1]=e; table.insert(tanks,e) end
        C.PlannerGroup(entries,{},8); local groups={}
        for i,e in ipairs(entries) do if e.kind=='normal' then local g=math.floor((i-1)/5)+1; groups[g]=(groups[g] or 0)+1; assert(g<=4) end end
        local count=0; for _,v in pairs(groups) do assert(v<=5); count=count+1 end
        assert(count==(n<=5 and 1 or 2),'Warrior tanks split needlessly')
    end
end)
print("Shir's Raid Builder planner player tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('planner player regressions failed') end
