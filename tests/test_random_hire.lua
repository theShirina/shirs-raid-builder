-- User-confirmed role-only addi; exact Lua 5.0.3, synthetic GRINFO only.
-- No client APIs, chat transport, game input, random rolls, or paid hires.
dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')
local C=ShirsRaidBuilderCore
local passes,failures=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passes=passes+1; print('PASS '..name)
    else failures=failures+1; print('FAIL '..name..': '..tostring(err)) end
end
local function random(role,source,tier)
    return {kind='normal',account=source or 'Alice',class='random',role=role or 'dps',tier=tier or 't0d'}
end
local function concrete(class,role,source)
    return {kind='normal',account=source or 'Alice',class=class or 'mage',role=role or 'rdps',
        tier='t1r',spec='frost',race='human',gender='female'}
end
local function record(name,class,role,owner)
    return {name=name,class=class,role=role,owner=owner or 'Alice'}
end
local function copy(value)
    if type(value)~='table' then return value end
    local out={}; for k,v in pairs(value) do out[k]=copy(v) end; return out
end
local function dump(value)
    if type(value)~='table' then return type(value)=='string' and string.format('%q',value) or tostring(value) end
    local keys,out={},{}; for k in pairs(value) do table.insert(keys,k) end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do table.insert(out,'['..dump(k)..']='..dump(value[k])) end
    return '{'..table.concat(out,',')..'}'
end
local function queued(entries)
    local out={}
    for i=1,40 do if entries[i] and entries[i].kind=='normal' then table.insert(out,{kind='normal',sourceEntryIndex=i}) end end
    return out
end
local function hasName(records,name)
    for _,r in ipairs(records) do if r.name==name then return true end end
    return false
end

for _,role in ipairs({'tank','healer','dps'}) do
    local role=role
    test('user-confirmed role-only command '..role,function()
        assert(C.BuildNormalHireCommand(random(role))=='.z addi Alice t0d '..role,'server-random command is not user-confirmed role-only syntax')
        for _,tier in ipairs({'t1d','t2d','t3d','t4d','t5d','t1r','t2r','t3r','t4r','t5r'}) do
            assert(C.BuildNormalHireCommand(random(role,'Bobalt',tier))=='.z addi Bobalt '..tier..' '..role,'chosen tier/source changed')
        end
    end)
end

test('random commands reject invalid source, role, tier and concrete fields',function()
    local e=random()
    for _,field in ipairs({'account','role','tier'}) do
        local bad=copy(e); bad[field]=nil; assert(not C.BuildNormalHireCommand(bad),'missing '..field..' defaulted')
    end
    for _,source in ipairs({'','A','Alice Bob','Alice;Bob','Alice-lite','123','Longcharactername'}) do
        local bad=copy(e); bad.account=source; assert(not C.BuildNormalHireCommand(bad),'invalid source accepted')
    end
    for _,role in ipairs({'','mdps','rdps','all','Tank','DPS',' tank','healer ','tank;dps','random'}) do
        local bad=copy(e); bad.role=role; assert(not C.BuildNormalHireCommand(bad),'invalid role accepted: '..role)
    end
    for _,tier in ipairs({'','none','t0','t0r','t6d','t6r','T1R','t1r ',' t0d','t1d;dps','t1','t10r','garbage'}) do
        local bad=copy(e); bad.tier=tier; assert(not C.BuildNormalHireCommand(bad),'invalid tier accepted: '..tier)
    end
    for _,field in ipairs({'spec','race','gender'}) do
        local bad=copy(e); bad[field]='default'; assert(not C.BuildNormalHireCommand(bad),'random accepted concrete '..field)
    end
end)

test('sentinel is normal intent only, never a legacy/player/guest command',function()
    assert(type(C.IsRandomHire)=='function' and C.IsRandomHire(random()))
    assert(not C.IsRandomHire(concrete()) and not C.IsRandomHire(nil))
    for _,kind in ipairs({'legacy','player','guest','empty'}) do
        local e=random(); e.kind=kind; e.charName='Named'; e.sourceName='Named'
        assert(not C.IsRandomHire(e),'non-normal sentinel accepted')
        assert(not C.BuildNormalHireCommand(e),'non-normal random command emitted')
        assert(not C.PlanEntry(e),'non-normal random survived plan validation')
        assert(C.NormalizeBoardEntry(copy(e)).kind=='empty','non-normal random normalized into a hire')
        if kind=='legacy' then assert(not C.BuildHireCommand(e),'legacy random emitted addlegacy') end
    end
end)

test('concrete normal and legacy syntax remain unchanged',function()
    assert(C.BuildNormalHireCommand(concrete())=='.z addinvite Alice t1r mage rdps frost human female')
    assert(C.BuildNormalHireCommand({kind='normal',account='Alice'})=='.z addinvite Alice t2r warrior mdps default human male')
    assert(C.BuildHireCommand({kind='legacy',charName='Legacy',class='warrior',role='tank',spec='default'})=='.z addlegacy "Legacy" tank')
    assert(C.PlanEntry(concrete()).class=='mage')
end)

test('normalization and serialized reload keep random intent without invented fields',function()
    for _,role in ipairs({'tank','healer','dps'}) do
        local e=random(role,'Bobalt','t2d'); local before=dump(e)
        local rows={e,concrete()}; C.RepairRaidEntries(rows)
        local restored=assert(loadstring('return '..dump(rows)))(); C.RepairRaidEntries(restored)
        assert(dump(restored[1])==before,'reload changed server-random intent')
        assert(restored[1].spec==nil and restored[1].race==nil and restored[1].gender==nil)
        assert(C.BuildNormalHireCommand(restored[1])=='.z addi Bobalt t2d '..role)
        assert(restored[2].class=='mage' and restored[2].role=='rdps','concrete row converted')
    end
end)

test('existing PLAN_FIELDS carry canonical random roundtrip, with no new fields',function()
    assert(table.concat(C.PLAN_FIELDS,',')=='kind,account,charName,sourceName,companionName,class,role,spec,tier,race,gender')
    local p={entries={random('tank'),random('healer','Bobalt','t2d'),random('dps','Alice','t3r'),concrete()}}
    local text=assert(C.PlanEncode(p,'hire','Random plan'))
    assert(string.find(text,'normal,Alice,_,_,_,random,tank,_,t0d,_,_',1,true),'random did not use existing row encoding')
    local decoded=assert(C.PlanDecode(text)); assert(C.PlanEncode(decoded,'hire','Random plan')==text)
    for i=1,3 do assert(dump(decoded.entries[i])==dump(p.entries[i])) end
    for _,field in ipairs({'role','tier','spec','race','gender'}) do
        local bad=copy(p); bad.entries[1][field]='invalid'
        assert(not C.PlanEntry(bad.entries[1]) and not C.PlanEncode(bad,'hire','Random plan'),'malformed random '..field..' encoded')
    end
    local missing=random(); missing.tier=nil; assert(not C.PlanEntry(missing),'missing random tier encoded')
    assert(not C.PlanDecode(string.gsub(text,',random,tank,',',random,mdps,')),'wire accepted invalid random role')
    assert(not C.PlanDecode(string.gsub(text,',t0d,',',t6r,')),'wire accepted invalid random tier')
end)

test('BuildQueue sends the three actual short commands and keeps concrete rows',function()
    local p={entries={random('tank'),random('healer','Bobalt','t1d'),random('dps','Alice','t2r'),concrete()}}
    local before=dump(p); local q=C.BuildQueue(p)
    assert(table.getn(q)==4,'random hire missing from queue')
    for i,expected in ipairs({'.z addi Alice t0d tank','.z addi Bobalt t1d healer','.z addi Alice t2r dps',
        '.z addinvite Alice t1r mage rdps frost human female'}) do
        assert(q[i].command==expected and q[i].kind=='normal' and q[i].sourceEntryIndex==i,'queue command/index changed')
    end
    assert(dump(p)==before,'queue rewrote intent')
end)

test('handoff freezes, validates, restores and queues random rows with the existing protocol',function()
    local p={entries={[1]=random('dps','Alt','t2d'),[6]=random('healer','Bobalt','t1r')},
        denyRules={{class='mage',role='rdps',abilities={'Frost Nova'}}},
        setupRules={{class='mage',role='all',magic='amplify'}}}
    local own={alice=true,alt=true}; local sources={bobalt={endpoint='Bob',accountId='2222222222222222'}}
    local actors=assert(C.HandActors(p,'Alice',own,sources))
    local h=assert(C.HandCreate(p,'Random plan','Alice','FixtureRealm',actors,'1234567890123456',1800000000,own,sources,true),'random handoff refused')
    h.kind='GRANT'; h.accounts={}
    for i,s in ipairs(h.steps) do h.accounts[i]=s.actor=='Alice' and '1111111111111111' or '2222222222222222' end
    h.extras=assert(C.HandExtras(p)); local wire=assert(C.HandEncode(h)); local decoded=assert(C.HandDecode(wire))
    assert(C.HandEncode(decoded)==wire and C.HandRestore(h,'Alice','FixtureRealm',1800000001),'random handoff is not restorable')
    p.entries[1].tier='t5r'; p.entries[1].role='tank'
    assert(decoded.plan.entries[1].class=='random' and decoded.plan.entries[1].role=='dps' and decoded.plan.entries[1].tier=='t2d','frozen intent changed')
    decoded.phase='ready'; local part=assert(C.HandStepPlan(decoded,{},'Alice',own)); C.PadRaidSlots(part.entries,40)
    local q=C.HandQueue(part); assert(table.getn(q)==1 and q[1].command=='.z addi Alt t2d dps','handoff queue did not use role-only command')
    local bad=copy(decoded); bad.plan.entries[1].role='rdps'; assert(not C.HandEncode(bad),'malformed random frozen revision encoded')
end)

test('random matching requires an observed known concrete class and class-valid role',function()
    for _,class in ipairs({'warrior','paladin','hunter','rogue','priest','shaman','mage','warlock','druid'}) do
        for _,role in ipairs({'tank','healer','mdps','rdps'}) do
            for _,wanted in ipairs({'tank','healer','dps'}) do
                local allowed=C.RoleAllowedForClass(class,role) and (wanted==role or (wanted=='dps' and (role=='mdps' or role=='rdps')))
                assert(C.NormalHireMatchesInfo(random(wanted),record('Companion',class,role))==(allowed and true or false),class..' '..role..' '..wanted)
            end
        end
    end
    assert(C.NormalHireMatchesInfo(random('dps','Alice'),record('Companion','Mage','Ranged DPS','aLiCe')),'observed label/owner normalization lost')
end)

test('random cannot match legacy, foreign, unknown, nameless or wrong-role records',function()
    local e=random('dps'); e.companionName='Companion'
    for _,r in ipairs({record('Alice-lite','mage','rdps'),record(' Other-LiTe ','mage','rdps'),
        record('Companion','mage','rdps','Bob'),record('Companion','mage','rdps',''),
        record('Companion','random','rdps'),record('Companion','unknown','rdps'),record('Companion',nil,'rdps'),
        record('Companion','mage',nil),record('Companion','mage','dps'),record('Companion','mage','healer'),
        record('Companion','priest','healer'),record('','mage','rdps'),{name='Companion',class='mage',role='rdps'}}) do
        assert(not C.NormalHireMatchesInfo(e,r),'random matched unproven metadata: '..dump(r))
    end
    local bad=random(); bad.tier=nil
    assert(not C.NormalHireMatchesInfo(bad,record('Companion','mage','rdps')),'invalid random intent matched')
end)

test('preflight consumes once and reserves concrete/named rows before random',function()
    local e={random(),concrete()}
    local q=queued(e); local out,n=C.FilterExistingNormalHires(q,e,{record('Onlymage','mage','rdps')})
    assert(n==1 and table.getn(out)==1 and out[1].sourceEntryIndex==1,'random stole the only concrete record')
    out,n=C.FilterExistingNormalHires(q,e,{record('Onlymage','mage','rdps'),record('Hunter','hunter','rdps')})
    assert(n==2 and table.getn(out)==0,'concrete/random overlap left a false missing hire')
    e={random(),concrete(),concrete()}; e[3].companionName='Named'
    out,n=C.FilterExistingNormalHires(queued(e),e,{record('Named','mage','rdps')})
    assert(n==1 and table.getn(out)==2 and out[1].sourceEntryIndex==1 and out[2].sourceEntryIndex==2,'named concrete did not have priority')
    e={random(),random(),random('dps','Bob')}
    out,n=C.FilterExistingNormalHires(queued(e),e,{record('Alice-lite','mage','rdps'),record('First','mage','rdps'),record('Foreign','mage','rdps','Bob')})
    assert(n==2 and table.getn(out)==1 and out[1].sourceEntryIndex==2,'owner/type/one-to-one boundary lost')
end)

test('earlier random reservation cannot steal a current concrete row',function()
    local e={[1]=random(),[6]=concrete()}
    local h={step=2,steps={{group=1,actor='Alice'},{group=2,actor='Alice'}},plan={entries=e}}
    local mage=record('Onlymage','mage','rdps'); local hunter=record('Hunter','hunter','rdps')
    local left=C.HandUnclaimed(h,{mage,hunter})
    assert(table.getn(left)==1 and left[1]==mage,'earlier wildcard took current concrete companion')
    local out,n=C.FilterExistingNormalHires({{kind='normal',sourceEntryIndex=6}},e,left)
    assert(n==1 and table.getn(out)==0,'current concrete became a duplicate hire')
    left=C.HandUnclaimed(h,{mage})
    assert(table.getn(left)==1 and left[1]==mage,'unresolved earlier wildcard took the only concrete record')
    e[6].account='Alt'
    left=C.HandUnclaimed(h,{mage,hunter})
    assert(table.getn(left)==1 and left[1]==mage,'earlier wildcard took a concrete hirer-fallback match')
end)

test('named reservation finds its exact name before a same-class fallback',function()
    local e={[1]=concrete(),[6]=concrete(),[11]=random()}; e[1].companionName='Named'
    local h={step=2,steps={{group=1,actor='Alice'},{group=2,actor='Alice'},{group=3,actor='Alice'}},plan={entries=e}}
    local other=record('Other','mage','rdps'); local named=record('Named','mage','rdps'); local hunter=record('Hunter','hunter','rdps')
    local left=C.HandUnclaimed(h,{other,named,hunter})
    assert(table.getn(left)==2 and left[1]==other and left[2]==hunter,'named reservation consumed a different concrete companion')
end)

test('concrete-only owner priority and earlier-step fallback stay unchanged',function()
    local alt=concrete('mage','rdps','Alt'); alt.companionName='Absent'
    local own=concrete(); local mage=record('Observed','mage','rdps')
    local chosen,missing=C.HandScopeFound({alt,own},{mage},'Alice',{}, {alice=true,alt=true})
    assert(table.getn(chosen)==1 and missing[1]==1,'named fallback stole another concrete rows exact owner')
    local h={step=2,steps={{group=1,actor='Alice'},{group=2,actor='Alice'}},plan={entries={[1]=alt,[6]=own}}}
    assert(table.getn(C.HandUnclaimed(h,{mage}))==0,'later concrete exact owner changed earlier concrete reservation')
end)

test('duplicate live names consume once and malformed metadata fails closed',function()
    local e={random(),random()}
    local out,n=C.FilterExistingNormalHires(queued(e),e,{record('Only','mage','rdps'),record('ONLY','mage','rdps')})
    assert(n==1 and table.getn(out)==1,'duplicate GRINFO name covered two random hires')
    local chosen,missing=C.HandScopeFound(e,{false,{},record('Only','mage','rdps')},'Alice',{}, {alice=true})
    assert(table.getn(chosen)==1 and table.getn(missing)==1,'malformed record did not fail closed')
end)

test('earlier concrete reservation and hirer fallback preserve random validation/type guards',function()
    local e={[1]=concrete('mage','rdps','Alt'),[6]=random('dps','Alt')}
    local h={step=2,steps={{group=1,actor='Alice'},{group=2,actor='Alice'}},plan={entries=e}}
    local lite=record('Alt-lite','mage','rdps'); local mage=record('Magesent','mage','rdps'); local hunter=record('Huntersent','hunter','rdps')
    local left=C.HandUnclaimed(h,{lite,mage,hunter})
    assert(table.getn(left)==2 and left[1]==lite and left[2]==hunter,'earlier concrete fallback consumed the wrong record')
    assert(C.HandHiredBy(random('dps','Alt'),hunter,'Alice'),'random fallback lost explicit tier/role')
    assert(not C.HandHiredBy(random('dps','Alt'),lite,'Alice'),'fallback matched legacy')
    assert(not C.HandHiredBy(random('tank','Alt'),hunter,'Alice'),'fallback ignored selected role')
    assert(not C.HandHiredBy(random('dps','Alt'),record('Foreign','hunter','rdps','Bob'),'Alice'),'fallback ignored owner')
    local bad=random('dps','Alt'); bad.tier=nil; assert(not C.HandHiredBy(bad,hunter,'Alice'),'fallback repaired invalid intent')
    bad=random('dps','Alt'); bad.account=nil; assert(not C.HandHiredBy(bad,hunter,'Alice'),'fallback repaired missing source')
    bad=random('dps','Alt'); bad.account='Alice;Bob'; assert(not C.HandHiredBy(bad,hunter,'Alice'),'fallback repaired invalid source')
end)

test('HandScopeFound prioritizes concrete/named rows and keeps actual observed fields',function()
    local e={[1]=random(),[2]=concrete(),[3]=random('tank')}; local before=dump(e)
    local mage=record('Mage','mage','rdps'); local hunter=record('Hunter','hunter','rdps'); local bear=record('Bear','druid','tank')
    local chosen,missing=C.HandScopeFound(e,{mage,hunter,bear},'Alice',{}, {alice=true})
    assert(table.getn(missing)==0 and table.getn(chosen)==3 and hasName(chosen,'Mage') and hasName(chosen,'Hunter') and hasName(chosen,'Bear'),'valid random scope incomplete')
    assert(chosen[1]==mage,'specific row did not reserve Mage before wildcard')
    assert(dump(e)==before and chosen[2].class~='random','scope changed plan or invented observed class')
    chosen,missing=C.HandScopeFound({[1]=random(),[2]=concrete()},{mage},'Alice',{}, {alice=true})
    assert(table.getn(chosen)==1 and chosen[1]==mage and table.getn(missing)==1 and missing[1]==1,'random stole concrete scope')
end)

test('random scope fallback requires owned source, rejects legacy, and fails closed without metadata',function()
    local e={[6]=random('dps','Alt')}; local hunter=record('Hunter','hunter','rdps')
    assert(C.HandScope(e,{hunter},'Alice',{}, {alt=true}),'owned source hirer fallback refused')
    assert(not C.HandScope(e,{hunter},'Alice',{}, {}),'unproven source used hirer fallback')
    for _,records in ipairs({{}, {record('Alt-lite','hunter','rdps')}, {record('Hunter','unknown','rdps')},
        {record('Hunter','hunter','tank')}, {record('Hunter','hunter','rdps','Bob')}, {{name='Hunter',class='hunter',role='rdps'}}}) do
        local chosen,missing=C.HandScopeFound(e,records,'Alice',{Hunter=true,['Alt-lite']=true},{alt=true})
        assert(table.getn(chosen)==0 and missing[1]==6 and not C.HandScope(e,records,'Alice',{Hunter=true},{alt=true}),'random scope guessed from absent/invalid metadata')
    end
end)

test('setup and deny expansion uses actual random outcomes, never guessed class/spec',function()
    local entries={random(),random(),random('tank')}; local before=dump(entries)
    local parsed,valid=C.ParseGrinfoResponse('[nexus] GRINFO:ALL:FULL Mage:Human:Mage:RDPS:Uncommon:Alice Hunter:Orc:Hunter:RDPS:Uncommon:Alice Bear:Tauren:Druid:Tank:Uncommon:Alice')
    assert(valid and parsed[1].owner=='Alice' and parsed[1].spec==nil,'six-field GRINFO owner/spec boundary changed')
    local live=assert(C.HandScope(entries,parsed,'Alice',{}, {alice=true}))
    local setups=C.BuildClassSetupPlan({{class='mage',role='rdps',magic='amplify'},
        {class='hunter',role='all',pet='off'},{class='mage',role='rdps',spec='frost',magic='dampen'}})
    local denies=C.BuildGroupDenyPlan({{class='mage',role='rdps',abilities={'Frost Nova'}},
        {class='hunter',role='all',abilities={'Growl'}},{class='druid',role='tank',abilities={'Swipe'}},
        {class='warrior',role='tank',abilities={'Cleave'}}})
    local commands=C.AssembleLiveGroupCommands(setups,denies,{}, {},live,{})
    assert(table.getn(commands)==5,'actual class/role setup/deny expansion count differs')
    local seen={}; for _,item in ipairs(commands) do seen[item.target..'|'..item.command]=true; assert(item.class~='random') end
    assert(seen['Mage|set magic amplify'] and seen['Hunter|set pet off'] and seen['Mage|deny add Frost Nova']
        and seen['Hunter|deny add Growl'] and seen['Bear|deny add Swipe'],'actual outcomes lost commands')
    assert(dump(entries)==before,'observed outcome rewrote saved random intent')
    assert(table.getn(C.AssembleLiveGroupCommands(setups,denies,{}, {},{},{}))==0,'missing metadata invented targets')
end)

test('random potential commands retain handoff commands steps without inventing an outcome',function()
    local p={entries={random('dps')},denyRules={{class='mage',role='rdps',abilities={'Frost Nova'}}}}
    assert(C.RowsNeedCommands(p,{[1]=p.entries[1]}),'possible observed DPS rule was omitted')
    assert(not C.RowsNeedCommands(p,{[1]=random('tank')}),'tank intent assumed a Mage DPS outcome')
    assert(not C.RowsNeedCommands({entries=p.entries,denyRules={{class='warrior',role='tank',abilities={'Cleave'}}}},{[1]=p.entries[1]}),'DPS intent assumed tank role')
    local h=assert(C.HandCreate(p,'Random commands','Alice','FixtureRealm',{'Alice'},'1234567890123457',1800000000,{alice=true},nil,true))
    assert(table.getn(h.steps)==2 and h.steps[2].group==0,'random actor lost final commands step')
end)

test('live assignments match random after concrete and never persist the observed outcome',function()
    local e={random(),concrete()}; local before=dump(e[1])
    local mage=record('Mage','mage','rdps'); local hunter=record('Hunter','hunter','rdps')
    local roster={{name='Mage',class='mage',group=2},{name='Hunter',class='hunter',group=2}}
    local map=C.BuildLiveRaidAssignments(e,{},roster,{mage,hunter},'Alice')
    assert(C.SlotAssignmentForName(map,'Mage')==2 and C.SlotAssignmentForName(map,'Hunter')==1,'wildcard assignment stole concrete companion')
    assert(dump(e[1])==before and e[1].companionName==nil,'assignment saved observed random outcome')
    assert(e[2].class=='mage' and e[2].companionName=='Mage','concrete assignment behavior changed')
end)

test('random assignments reject human/legacy/detected-name shortcuts and absent metadata',function()
    local roster={{name='Human',class='mage',group=1},{name='Alice-lite',class='mage',group=1}}
    local e={random()}; e[1].companionName='Human'; local before=dump(e)
    local map=C.BuildLiveRaidAssignments(e,{[1]='Human'},roster,{},'Alice')
    assert(not C.AssignmentForName(map,'Human') and not C.AssignmentForName(map,'Alice-lite'),'roster-only human or detected name filled random slot')
    for _,r in ipairs({record('Human','unknown','rdps'),record('Alice-lite','mage','rdps'),record('Human','mage','healer'),record('Human','mage','rdps','Bob')}) do
        map=C.BuildLiveRaidAssignments(e,{[1]=r.name},roster,{r},'Alice')
        assert(not C.AssignmentForName(map,r.name),'unproven random assignment accepted')
    end
    map=C.BuildLiveRaidAssignments(e,{},{{name='Other',class='mage',group=1}},{record('Notpresent','mage','rdps')},'Alice')
    assert(not C.AssignmentForName(map,'Notpresent'),'absent GRINFO member assigned')
    assert(dump(e)==before,'failed random assignment changed intent')
end)

test('random DPS count/cap stays normal without claiming melee or ranged',function()
    local e={random(),random('tank'),random('healer'),concrete(),random('dps','Bob')}
    assert(C.NormalHireCountForCharacter(e,'Alice')==4 and not C.CanAddNormalHire(e,'Alice',4),'random escaped normal cap')
    local counts=C.CountRoles(e)
    assert(counts.dps==2 and counts.tank==1 and counts.healer==1 and counts.rdps==1 and counts.mdps==0,'random DPS was lost or guessed as melee/ranged')
end)

print('passes='..passes..' failures='..failures)
assert(failures==0,tostring(failures)..' random hire regression(s) failed')
print("Shir's Raid Builder random hire tests: PASS ("..passes.." cases)")
