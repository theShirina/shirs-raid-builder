-- Full class:role priority, migrations, actual reorder controls and allocations.
local f=assert(io.open('test_individual_editor.lua')); local text=f:read('*a'); f:close()
local at=assert(string.find(text,'\nlocal failures, passes=',1,true)); local boot=assert(loadstring(string.sub(text,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(name,fn) local ok,e=pcall(fn); if ok then pass=pass+1; print('PASS '..name) else fail=fail+1; print('FAIL '..name..': '..tostring(e)) end end
local function dump(v)
    if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end
    local keys,out={},{}; for k in pairs(v) do table.insert(keys,k) end; table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do table.insert(out,'['..dump(k)..']='..dump(v[k])) end; return '{'..table.concat(out,',')..'}'
end
local function start()
    local db={syncAccountId='1111111111111111',currentPreset='Default',presets={Default={entries={},denyRules={},setupRules={}}},inviteCharacters={}}
    local names={'Alice','Bravo','Charlie','Delta','Echo'}
    for i,name in ipairs(names) do db.inviteCharacters[name]={name=name,level=60,dungeonLicense='none',raidLicense='t'..i..'r',faction='Alliance',count=0,maxCount=1} end
    local h=boot(db,'Alice'); h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn); return h,h.C.plannerFrame
end
local function prefix(C,ids)
    local out,seen={},{}; for _,id in ipairs(ids) do table.insert(out,id); seen[id]=true end
    for _,id in ipairs(C.PlannerAutoOrder()) do if not seen[id] then table.insert(out,id) end end; return out
end
local function roleTiers(plan)
    local out={}; for _,e in ipairs(plan.entries) do if e.kind=='normal' then out[e.class..':'..e.role]=e.tier end end; return out
end
local supplied={'warrior:tank','mage:rdps','druid:tank','warrior:mdps','warlock:rdps'}

test('Custom supplied example changes actual eligible source tiers in exact class/role sequence',function()
    local h,p=start(); local C=h.C; local request={sources={},counts={},gender='female',priorityMode='custom',customOrder=prefix(C,supplied)}
    for _,s in ipairs(p.sources) do request.sources[s.key]={selected=true,tier=C.PlannerHighestTier(s)} end
    for _,id in ipairs(supplied) do request.counts[id]=1 end
    local r=assert(C.PlannerBuild(p.base,p.sources,request)); local tiers=roleTiers(r.plan)
    for i,id in ipairs(supplied) do assert(tiers[id]=='t'..(6-i)..'r',id..' got '..tostring(tiers[id])) end
    request.priorityMode='auto'; local a=assert(C.PlannerBuild(p.base,p.sources,request)); local auto=roleTiers(a.plan)
    assert(auto['druid:tank']=='t4r' and auto['mage:rdps']=='t2r','Auto bucket order lost')
end)
test('priority set exactly covers every supported concrete combination, with disjoint ranged buckets',function()
    local h,p=start(); local C=h.C; local order=C.PlannerAutoOrder(); local seen={}; local count=0
    for _,id in ipairs(order) do assert(not seen[id]); seen[id]=true; count=count+1 end
    local expected=0
    for _,class in ipairs(C.PLANNER_CLASSES) do for _,role in ipairs(C.PLANNER_ROLES) do if C.RoleAllowedForClass(class,role) then expected=expected+1; assert(seen[class..':'..role]) end end end
    assert(count==expected and table.getn(p.priorityRows)==expected)
    assert(C.PlannerBucket({class='mage',role='rdps'})=='mage' and C.PlannerBucket({class='warlock',role='rdps'})=='warlock')
    assert(C.PlannerBucket({class='druid',role='rdps'})=='rdps' and C.PlannerBucket({class='hunter',role='rdps'})=='rdps')
    assert(C.PlannerBucket({class='druid',role='tank'})=='tank' and C.PlannerBucket({class='paladin',role='healer'})=='healer' and C.PlannerBucket({class='shaman',role='mdps'})=='mdps')
    local mage,warlock,other
    for i,id in ipairs(order) do if id=='mage:rdps' then mage=i elseif id=='warlock:rdps' then warlock=i elseif id=='hunter:rdps' then other=i end end
    assert(mage<warlock and warlock<other)
end)
test('actual supported combinations allocate once each across mixed factions without identity/count loss',function()
    local h,p=start(); local C=h.C; local sources,req={},{sources={},counts={},priorityMode='custom',customOrder=prefix(C,supplied),gender='female'}
    for i,name in ipairs({'Alpha','Bravo','Charlie','Delta','Echo','Foxtrot','Golf','Hotel','India','Juliet'}) do
        local s={key=name,name=name,eligible=true,localSource=true,tiers={'t2r'},capacity=4,faction=i<=5 and 'Alliance' or 'Horde'}; table.insert(sources,s); req.sources[name]={selected=true,tier='t2r'}
    end
    for _,id in ipairs(C.PlannerAutoOrder()) do req.counts[id]=1 end
    local r=assert(C.PlannerBuild({entries={}},sources,req)); local seen={}
    for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then local id=e.class..':'..e.role; assert(not seen[id]); seen[id]=true; assert(e.tier=='t2r') end end
    assert(r.normal==table.getn(C.PlannerAutoOrder()) and r.total==r.normal and r.fourths==0)
    for id in pairs(req.counts) do assert(seen[id]) end
end)
test('four/six bucket migration expands in place; partial concrete orders append new supported IDs',function()
    local h,p=start(); local C=h.C
    for _,old in ipairs({{'healer','rdps','mdps','tank'},{'warlock','mage','healer','tank','rdps','mdps'}}) do
        local mode,order=C.PlannerLoadPriority({priorityMode='custom',customOrder=old}); assert(mode=='custom' and table.getn(order)==table.getn(C.PlannerAutoOrder()))
        local bucket=C.PlannerBucket({class=string.sub(order[1],1,string.find(order[1],':')-1),role=string.sub(order[1],string.find(order[1],':')+1)})
        assert(bucket==old[1]); local seen={}; for _,id in ipairs(order) do assert(not seen[id]); seen[id]=true end
    end
    local mode,order=C.PlannerLoadPriority({priorityMode='custom',customOrder={'mage:rdps','warrior:tank'}})
    assert(mode=='custom' and order[1]=='mage:rdps' and order[2]=='warrior:tank' and table.getn(order)==table.getn(C.PlannerAutoOrder()))
    for _,bad in ipairs({{'mage:rdps','mage:rdps'},{'mage:rdps','madeup:tank'},{[1]='mage:rdps',[3]='warrior:tank'},{'tank','mdps','rdps','healer','mage'}}) do
        local m,o=C.PlannerLoadPriority({priorityMode='custom',customOrder=bad}); assert(m=='auto' and dump(o)==dump(C.PlannerAutoOrder()))
    end
end)
test('actual longer-list Up/Down handlers build the requested order, scroll to end, save and reload',function()
    local h,p=start(); local C=h.C; local original=dump(h:preset())
    for _,r in ipairs(p.sourceRows) do r.normalCheck:SetChecked(1); h:fire(r.normalCheck,'OnClick') end
    local choices=dump(p.request.sources)
    h:click(h:button(p,'Tier priority')); h:choose(p.priorityMode,'Custom')
    for target,id in ipairs(supplied) do
        local index; for i,v in ipairs(p.request.customOrder) do if v==id then index=i end end
        while index>target do h:click(p.priorityRows[index].up); index=index-1 end
    end
    for i,id in ipairs(supplied) do assert(p.request.customOrder[i]==id and string.find(p.priorityRows[i].label:GetText(),C.PlannerPriorityLabel(id),1,true)) end
    assert(p.priorityMax>0); h:fire(p.priorityScroll,'OnMouseWheel',-1); assert(p.priorityScroll:GetVerticalScroll()>0)
    p.prioritySlider:SetValue(p.priorityMax); assert(p.priorityScroll:GetVerticalScroll()==p.priorityContent:GetHeight()-p.priorityScroll:GetHeight())
    for _,row in ipairs(p.priorityRows) do assert(row:GetWidth()<=p.priorityContent:GetWidth() and -row.point[5]+row:GetHeight()<=p.priorityContent:GetHeight()) end
    assert(not p.priorityRows[1].up:IsEnabled() and not p.priorityRows[table.getn(p.priorityRows)].down:IsEnabled())
    h:click(p.priorityRows[1].down); h:click(p.priorityRows[2].up)
    h:choose(p.priorityMode,'Auto'); h:choose(p.priorityMode,'Custom'); assert(p.request.customOrder[1]==supplied[1] and dump(p.request.sources)==choices and dump(h:preset())==original)
    h:click(h:button(p,'Composition')); for _,id in ipairs(supplied) do p.countInputs[id]:SetText('1') end
    h:click(p.buildButton); local r=assert(p.proposal,p.message:GetText()); local tiers=roleTiers(r.plan)
    for i,id in ipairs(supplied) do assert(tiers[id]=='t'..(6-i)..'r','actual reorder did not affect allocation') end
    local db=assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))(); local restored=boot(db,'Alice'); restored:click(restored.env.ShirsRaidBuilderMainFrame.plannerBtn)
    local q=restored.C.plannerFrame; assert(q.request.priorityMode=='custom' and dump(q.request.customOrder)==dump(p.request.customOrder) and dump(q.request.sources)==choices)
end)
test('registered reorder survives close reopen Create logout and fresh login; Auto retains last Custom',function()
    local h,p=start(); local C=h.C
    for _,r in ipairs(p.sourceRows) do r.normalCheck:SetChecked(1); h:fire(r.normalCheck,'OnClick') end
    local sourceChoices=dump(p.request.sources)
    h:click(h:button(p,'Tier priority')); h:choose(p.priorityMode,'Custom')
    for target,id in ipairs(supplied) do
        local index; for i,v in ipairs(p.request.customOrder) do if v==id then index=i end end
        while index>target do h:click(p.priorityRows[index].up); index=index-1 end
    end
    local expected=dump(p.request.customOrder)
    h:click(h:button(p,'Cancel')); h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn)
    assert(p.request.priorityMode=='custom' and dump(p.request.customOrder)==expected and dump(p.request.sources)==sourceChoices,'close/reopen lost priority')
    h:click(h:button(p,'Composition')); for _,id in ipairs(supplied) do p.countInputs[id]:SetText('1') end
    h:click(p.buildButton); local r=assert(p.proposal,p.message:GetText()); local tiers=roleTiers(r.plan)
    for i,id in ipairs(supplied) do assert(tiers[id]=='t'..(6-i)..'r') end
    p.nameInput:SetText('Saved priority');h:click(p.applyButton);h.env.RefreshComposition()
    h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn);assert(p.request.priorityMode=='custom' and dump(p.request.customOrder)==expected)
    h:click(h:button(p,'Tier priority'));h:choose(p.priorityMode,'Auto')
    h.env.event='PLAYER_LOGOUT';for _,w in ipairs(h.frames) do if w.events.PLAYER_LOGOUT and w.scripts.OnEvent then h:fire(w,'OnEvent') end end
    local saved=assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))();local fresh=boot(saved,'Alice');fresh:click(fresh.env.ShirsRaidBuilderMainFrame.plannerBtn);local q=fresh.C.plannerFrame
    assert(q.request.priorityMode=='auto' and dump(q.request.customOrder)==expected,'logout/fresh login lost Auto/custom order')
    fresh:click(fresh:button(q,'Tier priority'));fresh:choose(q.priorityMode,'Custom');assert(dump(q.request.customOrder)==expected and dump(q.request.sources)==sourceChoices)
    fresh:click(q.buildButton);local actual=roleTiers(assert(q.proposal,q.message:GetText()).plan);for id,tier in pairs(tiers) do assert(actual[id]==tier,'restored priority did not allocate tiers') end
end)
print("Shir's Raid Builder planner priority tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('planner priority regressions failed') end
