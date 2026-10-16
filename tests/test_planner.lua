-- Exact Lua 5.0.3. Planner tests are synthetic; no client input or spending.
dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')
local C=ShirsRaidBuilderCore
local passes,failures=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passes=passes+1; print('PASS '..name) else failures=failures+1; print('FAIL '..name..': '..tostring(err)) end
end
local function dump(v)
    if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end
    local keys,out={},{}; for k in pairs(v) do table.insert(keys,k) end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do table.insert(out,'['..dump(k)..']='..dump(v[k])) end
    return '{'..table.concat(out,',')..'}'
end
local names={'Alpha','Bravo','Charlie','Delta','Echo','Foxtrot','Golf','Hotel','India','Juliet'}
local function sources(n)
    local out={}
    for i=1,n do out[i]={key='own:'..string.lower(names[i]),name=names[i],accountId='11111111',endpoint='Alpha',localSource=true,
        eligible=true,faction='Alliance',tiers={'t0d','t1r','t2r'},capacity=4,freshness='remembered',legacyClass='priest',legacyRole='healer'} end
    return out
end
local function selected(rows)
    local out={}; for _,s in ipairs(rows) do out[s.key]={selected=true,tier='t1r',includeLegacy=false} end; return out
end
local function proposal(rows,counts,anchors,options)
    local request={sources=selected(rows),counts=counts or {},gender='female',race='auto',spec='auto'}
    for k,v in pairs(options or {}) do request[k]=v end
    return C.PlannerBuild({entries=anchors or {},denyRules={{class='priest',role='healer',abilities={'Holy Nova'}}},setupRules={}},rows,request)
end
local function totals(plan)
    local counts,alloc={},{}
    for _,e in ipairs(plan.entries) do if e.kind=='normal' then
        local key=e.class..':'..e.role; counts[key]=(counts[key] or 0)+1
        alloc[e.account]=(alloc[e.account] or 0)+1; assert(e.tier=='t1r')
        assert(C.BuildNormalHireCommand(e))
    end end
    return counts,alloc
end

test('10 sources / 30 normals uses exactly three each and conserves totals/tier',function()
    local r=assert(proposal(sources(10),{['mage:rdps']=30}))
    local c,a=totals(r.plan); assert(c['mage:rdps']==30 and r.normal==30 and r.total==30 and r.fourths==0)
    for _,name in ipairs(names) do assert(a[name]==3) end
end)
test('40 normal slots use fourth hires explicitly; 41 fails',function()
    local r=assert(proposal(sources(10),{['warrior:mdps']=40})); assert(r.total==40 and r.fourths==10)
    assert(string.find(table.concat(r.notes,' '),'fourth',1,true))
    local bad,why=proposal(sources(10),{['warrior:mdps']=41}); assert(not bad and string.find(why,'40',1,true))
end)
test('only selected source and exact selected tier; no hidden upgrade',function()
    local rows=sources(3); local sel=selected(rows); sel[rows[2].key].selected=false; sel[rows[3].key].selected=false
    local r=assert(proposal(rows,{['mage:rdps']=4},nil,{sources=sel})); local _,a=totals(r.plan); assert(a.Alpha==4 and not a.Bravo)
    sel[rows[1].key].tier='t5r'; local bad,why=proposal(rows,{['mage:rdps']=1},nil,{sources=sel}); assert(not bad and why)
end)
test('invalid unknown and missing sources fail without mutating original',function()
    for _,kind in ipairs({'unknown','invalid','missing','none'}) do
        local rows=sources(1); local sel=selected(rows)
        if kind=='unknown' then rows[1].eligible=false; rows[1].reason='licences unknown'
        elseif kind=='invalid' then rows[1].faction=nil
        elseif kind=='missing' then rows={} else sel={} end
        local original={entries={{kind='player',charName='Alpha',class='warrior',role='tank'}},denyRules={}}; local before=dump(original)
        local r,why=C.PlannerBuild(original,rows,{sources=sel,counts={['mage:rdps']=1},gender='female',race='auto',spec='auto'})
        assert(not r and why); assert(before==dump(original))
    end
end)
test('insufficient capacity and faction-constrained allocation use no fallback',function()
    local rows=sources(2); rows[1].capacity=1; rows[2].faction='Horde'
    local r,why=proposal(rows,{['paladin:healer']=2}); assert(not r and why)
    r=assert(proposal(rows,{['paladin:healer']=1,['shaman:mdps']=4})); local c,a=totals(r.plan)
    assert(c['shaman:mdps']==4 and a.Alpha==1 and a.Bravo==4 and r.fourths==1)
end)
test('all supported roles produce concrete valid class race faction spec defaults',function()
    for _,class in ipairs({'warrior','paladin','hunter','rogue','priest','shaman','mage','warlock','druid'}) do
        for _,role in ipairs({'tank','healer','mdps','rdps'}) do
            if C.RoleAllowedForClass(class,role) then
                local rows=sources(1); if class=='shaman' then rows[1].faction='Horde' end
                local r=assert(proposal(rows,{[class..':'..role]=1})); local c=totals(r.plan); assert(c[class..':'..role]==1)
                for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then assert(e.gender=='female' and e.race and e.spec and C.ClassAllowedForFaction(e.class,rows[1].faction)) end end
            end
        end
    end
end)
test('human anchors and full legacy identity/rules survive regrouping; counts are NORMAL totals',function()
    local entries={}; entries[2]={kind='player',charName='Alpha',class='warrior',role='tank'}
    entries[7]={kind='legacy',sourceName='Bravo',charName='Bravo',class='priest',role='healer',denyList={'Holy Nova'}}
    entries[9]={kind='guest',charName='Human',companionName='Human',class='mage',role='rdps'}
    entries[10]={kind='normal',account='Nobody',class='mage',role='rdps'}
    local before=dump(entries); local r=assert(proposal(sources(2),{['mage:rdps']=2},entries))
    assert(r.normal==2 and r.legacy==1 and r.player==1 and r.guest==1 and r.total==5)
    assert(dump(r.plan.entries[2])==dump(entries[2]) and dump(r.plan.entries[9])==dump(entries[9]))
    local kept=0; for _,e in ipairs(r.plan.entries) do if e.kind=='legacy' then assert(dump(e)==dump(entries[7]) and e~=entries[7]); kept=kept+1 end end
    assert(kept==1 and before==dump(entries) and r.replaced==1)
    assert(r.plan.denyRules[1].abilities[1]=='Holy Nova')
end)
test('legacy checkbox adds exact remembered identity once without using normal budget',function()
    local rows=sources(2); local sel=selected(rows); sel[rows[1].key].includeLegacy=true; sel[rows[2].key].includeLegacy=true
    local r=assert(proposal(rows,{['mage:rdps']=6},nil,{sources=sel})); assert(r.normal==6 and r.legacy==2 and r.total==8 and r.fourths==0)
    local seen={}; for _,e in ipairs(r.plan.entries) do if e.kind=='legacy' then seen[e.sourceName]=true; assert(e.role=='healer' and e.class=='priest') end end
    assert(seen.Alpha and seen.Bravo)
    local anchors={{kind='legacy',sourceName='Alpha',charName='Alpha',class='priest',role='healer',denyList={'Holy Nova'}}}
    r=assert(proposal(rows,{['mage:rdps']=6},anchors,{sources=sel})); assert(r.legacy==2)
    local kept=0; for _,e in ipairs(r.plan.entries) do if e.kind=='legacy' and e.sourceName=='Alpha' then assert(dump(e)==dump(anchors[1])); kept=kept+1 end end; assert(kept==1)
    sel[rows[2].key].includeLegacy=false; r=assert(proposal(rows,{},anchors,{sources=sel})); assert(r.legacy==1)
end)
test('legacy missing role, changed remembered role and lite-name collisions are actionable',function()
    local rows=sources(2); local sel=selected(rows); sel[rows[1].key].includeLegacy=true
    rows[1].legacyRole=nil; local bad,why=proposal(rows,{},nil,{sources=sel}); assert(not bad and why)
    sel[rows[1].key].legacyRole='rdps'; assert(proposal(rows,{},nil,{sources=sel}))
    rows[1].legacyRole='rdps'; sel[rows[1].key].legacyRole=nil
    local anchors={{kind='legacy',sourceName='Alpha',charName='Alpha',class='priest',role='healer'}}
    bad,why=proposal(rows,{},anchors,{sources=sel}); assert(not bad and string.find(why,'anchor',1,true))
    rows[1].name='Longnameone'; rows[2].name='Longnametwo'; rows[1].legacyRole='healer'; sel[rows[2].key].includeLegacy=true
    local distinct=assert(proposal(rows,{},nil,{sources=sel})); assert(distinct.legacy==2 and C.LegacyTargetError(distinct.plan.entries),'planner full identities must stay distinct while Execute guards the shared live alias')
end)
test('40 cap includes added legacy anchors and no normal request corruption',function()
    local rows=sources(10); local sel=selected(rows); sel[rows[1].key].includeLegacy=true
    local bad,why=proposal(rows,{['mage:rdps']=40},nil,{sources=sel}); assert(not bad and string.find(why,'40',1,true))
end)
test('source ordering and count table order do not change deterministic proposal',function()
    local rows=sources(3); local first=assert(proposal(rows,{['mage:rdps']=4,['priest:healer']=2,['warrior:tank']=1}))
    local reversed={rows[3],rows[2],rows[1]}; local second=assert(proposal(reversed,{['warrior:tank']=1,['priest:healer']=2,['mage:rdps']=4}))
    assert(dump(first)==dump(second))
end)
test('group optimizer preserves identities/pins with bounded explainable support preferences',function()
    local rows=sources(10); for _,s in ipairs(rows) do s.faction='Horde' end
    -- Soft preferences do not imply faction-breaking Paladin hires.
    local r=assert(proposal(rows,{['shaman:healer']=2,['warrior:mdps']=6,['druid:tank']=2,['hunter:rdps']=2,['mage:rdps']=6,['priest:healer']=2}))
    local counts=totals(r.plan); assert(counts['warrior:mdps']==6 and counts['shaman:healer']==2)
    assert(r.score and r.grouping and r.grouping.moves<=40)
    local r2=assert(proposal(sources(10),{['priest:healer']=2,['paladin:healer']=2,['mage:rdps']=6}))
    for g=1,2 do local p,a=0,0; for i=(g-1)*5+1,g*5 do local e=r2.plan.entries[i]; if e.class=='priest' then p=p+1 elseif e.class=='paladin' then a=a+1 end end; assert(p==1 and a==1) end
    local scarce=assert(proposal(rows,{['warrior:mdps']=12,['shaman:healer']=1,['mage:rdps']=6,['priest:healer']=1}))
    assert(string.find(table.concat(scarce.notes,' '),'without',1,true),'scarce support preference must be disclosed')
end)
test('bad counts never get clamped or silently ignored',function()
    for _,counts in ipairs({{['mage:rdps']=-1},{['mage:rdps']=1.5},{['mage:tank']=1},{['madeup:healer']=1},{['mage:rdps']='2'}}) do
        local r,why=proposal(sources(1),counts); assert(not r and why)
    end
end)

test('source inventory separates account identity endpoint freshness and unknown licences',function()
    local db={syncAccountId='1111111111111111',peerLinks={},inviteCharacters={},legacyCharacters={remotealt='priest'},legacyCharacterRoles={remotealt='healer'}}
    local link=C.PeerNew('Alpha','Peer','Realm'); link.phase='linked'; assert(C.LinkSave(db.peerLinks,link,true))
    local own={{name='Alpha',level=60,dungeonLicense='t2d',raidLicense='t2r',faction='Alliance',observed=1800000000},
        {name='Unknown',level=60,dungeonLicense='unknown',raidLicense='t2r',faction='Alliance',observed=1800000000}}
    local snap={accountId='2222222222222222',source='peer',realm='Realm',received=1799999000,observed=1799999000,authoritative=false,
        entries={{name='Remotealt',level=60,dungeonLicense='t1d',raidLicense='t3r',faction='Horde',observed=1799999000}}}
    local licenses={['Realm;peer']=snap}
    local rows=C.PlannerSources(db,'Alpha','Realm',own,licenses,{},1800000000,100)
    assert(table.getn(rows)==3); local by={}; for _,s in ipairs(rows) do by[s.name]=s end
    assert(by.Alpha.localSource and by.Alpha.endpoint=='Alpha' and by.Alpha.eligible)
    assert(by.Remotealt.accountId==snap.accountId and by.Remotealt.endpoint=='Peer' and not by.Remotealt.localSource)
    assert(by.Remotealt.freshness=='remembered' and not by.Remotealt.live and by.Remotealt.legacyRole=='healer')
    assert(not by.Unknown.eligible and not by.Unknown.tiers,'unknown dungeon licence invented base eligibility')
    assert(C.PlannerHas(by.Remotealt.tiers,'t3r') and not C.PlannerHas(by.Remotealt.tiers,'t4r'))
    C.LinkForget(db.peerLinks,'Alpha','Peer','Realm',true)
    assert(table.getn(C.PlannerSources(db,'Alpha','Realm',own,licenses,{},1800000000,100))==2,'revoked linked data remained selectable')
end)
test('ambiguous local/linked name forbids normal and legacy inclusion',function()
    local db={peerLinks={},inviteCharacters={},legacyCharacters={alpha='warrior'},legacyCharacterRoles={alpha='tank'}}
    local link=C.PeerNew('Alpha','Peer','Realm'); link.phase='linked'; C.LinkSave(db.peerLinks,link,true)
    local row={name='Alpha',level=60,dungeonLicense='none',raidLicense='t2r',faction='Alliance',observed=1800000000}
    local snap={accountId='2222222222222222',source='peer',realm='Realm',received=1800000000,observed=1800000000,authoritative=false,entries={row}}
    local rows=C.PlannerSources(db,'Alpha','Realm',{row},{['Realm;peer']=snap},{},1800000000,100)
    assert(table.getn(rows)==2 and rows[1].key~=rows[2].key,'separate account identities were merged')
    for _,s in ipairs(rows) do
        assert(s.conflict and not s.eligible)
        for _,selection in ipairs({{includeLegacy=true},{selected=true,tier='t2r'}}) do
            local bad,why=proposal(rows,{},nil,{sources={[s.key]=selection}})
            assert(not bad and string.find(why,'identity',1,true),'ambiguous normal/legacy identity was accepted')
        end
    end
end)
test('remembered role refresh and invalid explicit roles never reuse the normal-player role',function()
    local rows=sources(1); rows[1].legacyRole='rdps'; local sel=selected(rows); sel[rows[1].key].includeLegacy=true
    local r=assert(proposal(rows,{},nil,{sources=sel})); assert(r.plan.entries[1].role=='rdps')
    rows[1].legacyRole='healer'; r=assert(proposal(rows,{},nil,{sources=sel})); assert(r.plan.entries[1].role=='healer')
    sel[rows[1].key].legacyRole='tank'; assert(not proposal(rows,{},nil,{sources=sel}))
end)

test('group swaps conserve every row identity, fixed slots and exact source-tier multiset',function()
    local entries,pinned,seen={}, {[1]=true,[17]=true}, {}
    for i=1,40 do
        local e={kind='normal',account='Source'..i,tier=i<=20 and 't1r' or 't3r',class=math.mod(i,4)==0 and 'shaman' or 'warrior',role='mdps'}
        entries[i]=e; seen[e]=true
    end
    local first,seventeenth=entries[1],entries[17]
    local before=0; for g=1,8 do before=before+C.PlannerGroupScore(entries,g) end
    local result=C.PlannerGroup(entries,pinned,8); assert(result.score>=before and result.moves<=40)
    assert(entries[1]==first and entries[17]==seventeenth)
    for i=1,40 do local e=entries[i]; assert(seen[e],'row duplicated or invented'); seen[e]=nil end
    assert(not next(seen),'row lost during grouping')
end)

print("Shir's Raid Builder planner tests: "..(failures==0 and 'PASS' or 'FAIL')..' ('..passes..' passed, '..failures..' failed)')
if failures>0 then error('planner regressions failed') end
