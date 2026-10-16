-- Generated planner rows through actual Execute/peer driver, synthetic transport only.
local passes,failures=0,0
local function test(name,fn) local ok,e=pcall(fn); if ok then passes=passes+1; print('PASS '..name) else failures=failures+1; print('FAIL '..name..': '..tostring(e)) end end
local function harness()
    local f=assert(io.open('test_run_authorization.lua','r')); local text=f:read('*a'); f:close()
    local at=assert(string.find(text,"\nlocal a=client('Alice',100)",1,true))
    return assert(loadstring(string.sub(text,1,at-1)..'\nreturn client,trust,pump,trace,runs'))()
end
local function linkedPlan()
    local client,trust,pump,trace,runs=harness()
    local function saved(name)
        return {currentPreset='Default',presets={Default={entries={},denyRules={},setupRules={}}},
            inviteCharacters={[name]={name=name,level=60,dungeonLicense='t1d',raidLicense='t2r',faction='Alliance'}}}
    end
    local a=client('Alice',100,saved('Alice')); local b=client('Bob',7000,saved('Bob'))
    trust(a,'Bob'); trust(b,'Alice')
    for _,h in ipairs({a,b}) do
        for _,snap in pairs(h.env.ShirsRaidBuilderDB.peerSnapshots) do for _,row in ipairs(snap.entries) do row.faction='Alliance' end end
        h.C.LicenseRestoreSaved()
        h.env.SetRaidSubgroup=function() error('planner must not sort') end
        h.env.SwapRaidSubgroup=h.env.SetRaidSubgroup
    end
    -- Real planner read -> build, no manual per-row owner assignment.
    local sources=a.C.PlannerReadSources(); local selection={}
    for _,s in ipairs(sources) do selection[s.key]={selected=true,tier=s.localSource and 't1d' or 't2r'} end
    local r=assert(a.C.PlannerBuild(a:preset(),sources,{sources=selection,counts={['mage:rdps']=4},gender='female'}))
    a:preset().entries=r.plan.entries
    assert(table.getn(trace)==0,'building a proposal started commands')
    return a,b,pump,trace,runs,r
end

test('generated mixed account source tiers survive real queue frozen handoff and single Execute',function()
    local a,b,pump,trace,runs,r=linkedPlan()
    local preview=a.C.BuildQueue(a:preset()); local expected={}; local total=0
    for _,e in ipairs(preview) do if e.kind=='normal' then expected[e.command]=(expected[e.command] or 0)+1; total=total+1 end end
    assert(total==4)
    a:click(a.env.ShirsRaidBuilderMainFrame.executeBtn); pump(240)
    local owners={alice=0,bob=0}; local count=0
    for _,line in ipairs(trace) do
        local _,_,owner,command=string.find(line,'^(%a+) hires (.+)$')
        if owner then owners[owner]=owners[owner]+1; count=count+1; assert(expected[command] and expected[command]>0,'command/source/tier drift: '..command); expected[command]=expected[command]-1 end
    end
    assert(count==4 and owners.alice==1 and owners.bob==3,'generated plan did not complete mixed account hires: '..table.concat(trace,' | '))
    assert(table.getn(runs)>0 and not a.C.handAuthority and not b.C.handAuthority)
    for _,n in pairs(expected) do assert(n==0) end
end)
test('main Stop cancels generated linked work and later ticks do not restart it',function()
    local a,b,pump,trace=linkedPlan(); a:click(a.env.ShirsRaidBuilderMainFrame.executeBtn)
    a:click(a:button(a.env.ShirsRaidBuilderMainFrame,'Stop')); local before=table.getn(trace); pump(240)
    assert(not a.C.handAuthority and not b.C.handAuthority and table.getn(trace)==before,'Stop restarted generated work')
end)
test('generated normals rerun remains owner-scoped and never consumes matching legacy',function()
    local f=assert(io.open('test_present_legacy.lua','r')); local text=f:read('*a'); f:close()
    local at=assert(string.find(text,"\ntest('three legacy already",1,true))
    local run=assert(loadstring(string.sub(text,1,at-1)..'\nreturn run'))()
    local isolated={}; setmetatable(isolated,{__index=_G})
    local load=assert(loadfile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')); setfenv(load,isolated); load()
    local C=isolated.ShirsRaidBuilderCore
    local sources={{key='own:carol',name='Carol',faction='Alliance',localSource=true,eligible=true,capacity=4,tiers={'t2r'}}}
    local r=assert(C.PlannerBuild({entries={{kind='legacy',sourceName='Carol',charName='Carol',class='mage',role='rdps'}},denyRules={},setupRules={}},sources,
        {sources={['own:carol']={selected=true,tier='t2r'}},counts={['mage:rdps']=2},gender='female'}))
    local records={{name='Carol-lite',class='mage',role='rdps',owner='Carol'},{name='First',class='mage',role='rdps',owner='Carol'},
        {name='Foreign',class='mage',role='rdps',owner='Other'}}
    local hires=run(r.plan.entries,{'Carol-lite','First','Foreign'},records,'party',{})
    assert(table.getn(hires)==1 and string.find(hires[1].text,'.z addinvite Carol t2r',1,true)==1,'legacy or foreign row suppressed a generated normal')
    table.insert(records,{name='Second',class='mage',role='rdps',owner='Carol'})
    hires=run(r.plan.entries,{'Carol-lite','First','Second','Foreign'},records,'party',{})
    assert(table.getn(hires)==0,'rerun duplicated confirmed owner-scoped generated hires')
end)
test('generated Include legacy rows keep exact full names and actor identity in real linked Execute',function()
    local a,b,pump,trace,runs,r=linkedPlan()
    local db=a.env.ShirsRaidBuilderDB; db.legacyCharacters={alice='warrior',bob='priest'}; db.legacyCharacterRoles={alice='tank',bob='healer'}
    local sources=a.C.PlannerReadSources(); local selection={}
    for _,s in ipairs(sources) do selection[s.key]={selected=true,tier=s.localSource and 't1d' or 't2r',includeLegacy=true} end
    r=assert(a.C.PlannerBuild(a:preset(),sources,{sources=selection,counts={['mage:rdps']=4},gender='female'}))
    assert(r.normal==4 and r.legacy==2 and r.total==7 and r.fourths==0)
    a:preset().entries=r.plan.entries
    local expected={}; for _,e in ipairs(a.C.BuildQueue(a:preset())) do if e.kind=='normal' or e.kind=='hire' then expected[e.command]=(expected[e.command] or 0)+1 end end
    assert(expected['.z addlegacy "Alice" tank']==1 and expected['.z addlegacy "Bob" healer']==1)
    a:click(a.env.ShirsRaidBuilderMainFrame.executeBtn); pump(300)
    local hires=0
    for _,line in ipairs(trace) do
        local _,_,actor,command=string.find(line,'^(%a+) hires (.+)$')
        if actor then
            hires=hires+1; assert(expected[command] and expected[command]>0,'unexpected generated command: '..line); expected[command]=expected[command]-1
            if command=='.z addlegacy "Bob" healer' then assert(actor=='bob') end
            if command=='.z addlegacy "Alice" tank' then assert(actor=='alice') end
        end
    end
    assert(hires==6 and not a.C.handAuthority and not b.C.handAuthority,'legacy generated plan stalled: '..table.concat(trace,' | '))
    for _,n in pairs(expected) do assert(n==0) end
end)

test('remembered offline source permits proposal but cannot authorize remote spending',function()
    local client,trust,pump,trace=harness()
    local a=client('Alice',100,{currentPreset='Default',presets={Default={entries={},denyRules={},setupRules={}}}})
    trust(a,'Bob')
    local db=a.env.ShirsRaidBuilderDB
    for _,snap in pairs(db.peerSnapshots) do for _,row in ipairs(snap.entries) do row.faction='Alliance' end end
    db.legacyCharacters={bob='priest'}; db.legacyCharacterRoles={bob='healer'}
    a.C.LicenseRestoreSaved()
    local selection={}; local sources=a.C.PlannerReadSources()
    for _,s in ipairs(sources) do if not s.localSource then selection[s.key]={selected=true,tier='t2r',includeLegacy=true}; assert(not s.live) end end
    local r=assert(a.C.PlannerBuild(a:preset(),sources,{sources=selection,counts={['mage:rdps']=2},gender='female'}))
    a:preset().entries=r.plan.entries
    local before=table.getn(trace); a:click(a:button(a.env.ShirsRaidBuilderMainFrame,'Preview')); assert(table.getn(trace)==before)
    a:click(a.env.ShirsRaidBuilderMainFrame.executeBtn); pump(150)
    for _,line in ipairs(trace) do assert(not string.find(line,' hires ',1,true),'offline source was hired by wrong actor') end
    assert(not a.C.handAuthority,'offline link retained spend authority')
end)

print("Shir's Raid Builder planner execution tests: "..(failures==0 and 'PASS' or 'FAIL')..' ('..passes..' passed, '..failures..' failed)')
if failures>0 then error('planner execution regressions failed') end
