-- Exact Lua 5.0.3; synthetic plans, never chat or paid hires.
dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')
local C=ShirsRaidBuilderCore
local pass,fail=0,0
local function test(name,fn) local ok,e=pcall(fn); if ok then pass=pass+1; print('PASS '..name) else fail=fail+1; print('FAIL '..name..': '..tostring(e)) end end
local function dump(v)
    if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end
    local keys,out={},{}; for k in pairs(v) do table.insert(keys,k) end; table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do table.insert(out,'['..dump(k)..']='..dump(v[k])) end; return '{'..table.concat(out,',')..'}'
end
local function source(key,tier,capacity,faction)
    return {key=key,name=key,accountId='1111111111111111',localSource=true,eligible=true,tiers={'t0d',tier},chosenTier=tier,capacity=capacity or 4,faction=faction or 'Alliance'}
end
local function build(rows,counts,anchors,settings)
    local req={sources={},counts=counts,gender='female',race='auto',spec='auto'}
    for _,s in ipairs(rows) do req.sources[s.key]={selected=true,tier=s.chosenTier} end
    for k,v in pairs(settings or {}) do req[k]=v end
    return C.PlannerBuild({entries=anchors or {},denyRules={},setupRules={}},rows,req)
end
local function byRole(r)
    local out={}; for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then out[e.role]=out[e.role] or {}; table.insert(out[e.role],e) end end
    return out
end
local function entry(class,role,kind,spec,name)
    return {kind=kind or 'normal',class=class,role=role,spec=spec or 'default',account=name or class,charName=name or class,sourceName=name or class,tier='t2r'}
end
local function groupOf(entries,e) for i,v in ipairs(entries) do if v==e then return math.floor((i-1)/5)+1 end end end
local function optimize(entries,pinned,groups)
    for i=1,groups*5 do if not entries[i] then entries[i]={kind='empty'} end end
    local seen={}; for _,e in ipairs(entries) do seen[e]=true end
    local fixed={}; for i in pairs(pinned or {}) do fixed[i]=entries[i] end
    local a=C.PlannerGroup(entries,pinned or {},groups)
    for i,e in ipairs(entries) do assert(seen[e],'duplicated row'); seen[e]=nil; if fixed[i] then assert(fixed[i]==e,'anchor moved') end end
    assert(not next(seen),'lost row'); assert(a.moves<=40)
    return entries
end

test('verified raid/dungeon ranking is explicit and independent of option order',function()
    assert(C.PlannerTierRank('t1r')>C.PlannerTierRank('t5d'))
    assert(C.PlannerTierRank('t5r')>C.PlannerTierRank('t4r') and not C.PlannerTierRank('unknown'))
    assert(C.PlannerHighestTier({eligible=true,tiers={'t3r','t0d','t5d','t1r'}})=='t3r')
    assert(C.PlannerHighestTier({eligible=true,tiers={'t2d','t5d','t0d'}})=='t5d')
    assert(not C.PlannerHighestTier({eligible=false,tiers={'t5r'}}))
end)
test('scarce high tiers go to Tank MDPS RDPS before Healer regardless of class/source enumeration',function()
    local rows={source('Aalow','t0d'),source('Zzhigh','t5r',3)}
    local counts={['paladin:tank']=1,['druid:mdps']=1,['warlock:rdps']=1,['priest:healer']=1}
    local a=assert(build(rows,counts)); local roles=byRole(a)
    for _,role in ipairs({'tank','mdps','rdps'}) do assert(roles[role][1].tier=='t5r',role..' lost scarce high tier') end
    assert(roles.healer[1].tier=='t0d' and a.fourths==0)
    local b=assert(build({rows[2],rows[1]},counts)); assert(dump(a)==dump(b),'source order changed proposal')
end)
test('all four role priorities have distinct tiers; deliberate override is not silently upgraded',function()
    local rows={source('Alpha','t1d',1),source('Bravo','t5d',1),source('Charlie','t1r',1),source('Delta','t5r',1)}
    local r=assert(build(rows,{['paladin:tank']=1,['rogue:mdps']=1,['mage:rdps']=1,['priest:healer']=1})); local roles=byRole(r)
    assert(roles.tank[1].tier=='t5r' and roles.mdps[1].tier=='t1r' and roles.rdps[1].tier=='t5d' and roles.healer[1].tier=='t1d')
    rows[4].tiers={'t0d','t1d','t5r'}; rows[4].chosenTier='t1d'
    r=assert(build(rows,{['paladin:tank']=1,['priest:healer']=3})); roles=byRole(r)
    assert(roles.tank[1].tier=='t1r'); for _,e in ipairs(r.plan.entries) do if e.kind=='normal' and e.account=='Delta' then assert(e.tier=='t1d') end end
end)
test('preferred three beats a needless fourth high-tier hire and explains limits',function()
    local r=assert(build({source('High','t5r'),source('Low','t1d')},{['warrior:tank']=1,['rogue:mdps']=1,['mage:rdps']=1,['priest:healer']=1}))
    local roles=byRole(r); assert(r.fourths==0 and roles.healer[1].tier=='t1d')
    for _,role in ipairs({'tank','mdps','rdps'}) do assert(roles[role][1].tier=='t5r') end
    assert(string.find(table.concat(r.notes,' '),'three',1,true) and string.find(table.concat(r.notes,' '),'Tanks',1,true))
    r=assert(build({source('High','t5r'),source('Low','t1d')},{['warrior:tank']=3,['mage:rdps']=3,['priest:healer']=2}))
    assert(r.fourths==2); local high=0; for _,e in ipairs(r.plan.entries) do if e.kind=='normal' and e.account=='High' then high=high+1; assert(e.role~='healer') end end; assert(high==4)
end)
test('restricted faction/race capacity takes priority without stealing a feasible high-tier tank',function()
    local rows={source('Highhorde','t5r',1,'Horde'),source('Lowalliance','t1d',2),source('Middlealliance','t2r',1)}
    local r=assert(build(rows,{['paladin:tank']=1,['shaman:mdps']=1,['mage:rdps']=1,['priest:healer']=1})); local roles=byRole(r)
    assert(roles.mdps[1].account=='Highhorde' and roles.tank[1].account=='Middlealliance' and roles.healer[1].tier=='t1d')
    local bad=build(rows,{['paladin:tank']=4}); assert(not bad,'faction capacity bypassed')
    rows[1].eligible=false; bad=build(rows,{['shaman:mdps']=1}); assert(not bad,'unknown source eligibility bypassed')
end)
test('role priority cannot depend on Warrior being enumerated before Priest or Paladin',function()
    local r=assert(build({source('Alpha','t0d',3),source('Zulu','t5r',1)},{['paladin:tank']=1,['priest:healer']=2,['mage:rdps']=1}))
    assert(byRole(r).tank[1].tier=='t5r')
end)
test('tank and MDPS prefer groups 1-4; fixed anchors and exact row identities survive',function()
    local entries={}; for i=1,20 do entries[i]=entry('mage','rdps',nil,'frost','M'..i) end
    for i=21,30 do entries[i]=entry(i<=22 and 'warrior' or 'rogue',i<=22 and 'tank' or 'mdps',nil,nil,'P'..i) end
    entries[40]=entry('warrior','tank','player',nil,'Anchor')
    optimize(entries,{[40]=true},8)
    for i,e in ipairs(entries) do if e.kind~='empty' and e.role=='mdps' then assert(i<=20,'movable melee stayed behind ranged') end end
    for i,e in ipairs(entries) do if e.kind=='normal' and e.role=='tank' then assert(i<=20) end end
    assert(entries[40].charName=='Anchor')
end)
test('over twenty melee and early pinned ranged allow valid disclosed overflow',function()
    local anchors={}; for i=1,4 do anchors[i]=entry('mage','rdps','guest','frost','Guest'..i) end
    local rows={}; for _,name in ipairs({'Alpha','Bravo','Charlie','Delta','Echo','Foxtrot','Golf','Hotel'}) do table.insert(rows,source(name,'t2r')) end
    local r=assert(build(rows,{['warrior:tank']=2,['rogue:mdps']=21},anchors)); assert(r.total==27)
    local front,back=0,0; for i,e in ipairs(r.plan.entries) do if e.role=='tank' or e.role=='mdps' then if i<=20 then front=front+1 else back=back+1 end end end
    assert(front==16 and back==7); for i=1,4 do assert(dump(r.plan.entries[i])==dump(anchors[i])) end
    assert(string.find(table.concat(r.notes,' '),'groups 1-4',1,true),'front overflow not disclosed')
end)
test('Balance prefers included legacy Mage or Warlock over ordinary Fire/Warlock, without inventing sources',function()
    for _,class in ipairs({'mage','warlock'}) do
        local d=entry('druid','rdps'); local legacy=entry(class,'rdps','legacy',nil,'Legacycaster')
        local entries={legacy,entry('priest','healer'),entry('paladin','healer'),entry('mage','rdps',nil,'frost'),entry('mage','rdps',nil,'frost'),d,
            entry('mage','rdps',nil,'fire'),entry('mage','rdps',nil,'fire'),entry('warlock','rdps'),entry('warlock','rdps')}
        optimize(entries,{[1]=true},2); assert(groupOf(entries,d)==1,'Balance missed included legacy '..class)
    end
end)
test('known Fire Mage outranks ordinary Warlock; unknown Mage never counts as Fire',function()
    for _,spec in ipairs({'fire','default'}) do
        local d=entry('druid','rdps'); local mage=entry('mage','rdps','normal',spec); local warlock=entry('warlock','rdps')
        local entries={mage,entry('priest','healer'),entry('mage','rdps',nil,'frost'),entry('mage','rdps',nil,'frost'),entry('mage','rdps',nil,'frost'),warlock,d,
            entry('priest','healer'),entry('warrior','mdps'),entry('rogue','mdps')}
        optimize(entries,{[1]=true,[6]=true},2)
        assert(groupOf(entries,d)==(spec=='fire' and 1 or 2),'wrong verified caster choice for '..spec)
    end
end)
test('actual Paladin/Druid MDPS share Warrior/Shaman preference; healer and Balance are not melee',function()
    assert(C.PlannerPhysical(entry('paladin','mdps')) and C.PlannerPhysical(entry('druid','mdps')))
    assert(not C.PlannerPhysical(entry('paladin','healer')) and not C.PlannerPhysical(entry('druid','rdps')))
    local pal,druid,heal,balance=entry('paladin','mdps'),entry('druid','mdps'),entry('paladin','healer'),entry('druid','rdps')
    local entries={entry('warrior','mdps'),entry('shaman','healer'),heal,balance,entry('mage','rdps',nil,'fire'),pal,druid,entry('warlock','rdps'),entry('priest','healer'),entry('mage','rdps',nil,'frost')}
    optimize(entries,{[1]=true,[2]=true},2)
    assert(groupOf(entries,pal)==1 and groupOf(entries,druid)==1,'hybrid MDPS missed physical group')
    assert(groupOf(entries,heal)==1 and groupOf(entries,balance)==2,'last physical group must receive supplied Paladin healing without pulling Balance into physical grouping')
end)
test('small raids and scarce support remain valid, deterministic and class/role conserving',function()
    local rows={source('Alpha','t5r',4,'Horde'),source('Bravo','t1d',4,'Horde')}
    local counts={['druid:mdps']=2,['druid:rdps']=1,['shaman:healer']=1,['warrior:tank']=1,['mage:rdps']=1}
    local a=assert(build(rows,counts)); local b=assert(build(rows,counts)); assert(dump(a)==dump(b) and a.total==6 and a.groups==2)
    assert(string.find(table.concat(a.notes,' '),'staged preferences',1,true))
end)
test('Custom healer-first reverses allocation roles only; Auto and same-tier ties stay stable',function()
    local rows={source('Alpha','t0d',3),source('Zulu','t5r',1)}
    local counts={['paladin:tank']=1,['rogue:mdps']=1,['mage:rdps']=1,['priest:healer']=1}
    local auto=assert(build(rows,counts)); local custom=assert(build(rows,counts,nil,{priorityMode='custom',customOrder={'healer','rdps','mdps','tank'}}))
    assert(byRole(auto).tank[1].tier=='t5r' and byRole(custom).healer[1].tier=='t5r' and byRole(custom).tank[1].tier=='t0d')
    local explicit=assert(build(rows,counts,nil,{priorityMode='auto',customOrder={'healer','rdps','mdps','tank'}})); assert(dump(auto)==dump(explicit))
    local malformed=assert(build(rows,counts,nil,{priorityMode='custom',customOrder={'healer','healer','mdps','tank'}})); assert(dump(auto)==dump(malformed))
    rows[2].chosenTier='t0d'; local a=assert(build(rows,counts)); local b=assert(build(rows,counts,nil,{priorityMode='custom',customOrder={'healer','rdps','mdps','tank'}}))
    assert(dump(a.plan)==dump(b.plan),'same-tier tie-break changed with priority')
end)
test('otherwise unconstrained extra groups receive one available Paladin healer before stacking',function()
    for _,supply in ipairs({2,3}) do
        local entries,palas,pins={},{},{[1]=true}
        for i=1,15 do entries[i]=entry('priest','healer',nil,nil,'Priest'..i) end
        for i=1,supply do local p=entry('paladin','healer',nil,nil,'Paladin'..i); entries[i]=p; table.insert(palas,p) end
        optimize(entries,pins,3); local seen={}
        for _,p in ipairs(palas) do local g=groupOf(entries,p); assert(not seen[g],'needlessly stacked Paladin healers'); seen[g]=true end
    end
end)
print("Shir's Raid Builder planner refinements tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('planner refinements regressions failed') end
