-- Execute reads the live group first: a planned legacy companion that is already in the
-- party or raid is not hired again, while its deny and setup whispers still go out and
-- missing hires keep their order and pacing. Real UI fixture, real Execute click,
-- SYNTHETIC roster and GRINFO replies. Exact Lua 5.0.3.
local f=assert(io.open('test_individual_editor.lua','r')); local fixture=f:read('*a'); f:close()
local boundary=assert(string.find(fixture,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(fixture,1,boundary-1)..'\nreturn boot'))()
local failures,passes=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passes=passes+1; print('PASS '..name)
    else failures=failures+1; print('FAIL '..name..': '..tostring(err)) end
end
local function legacy(name,class,role,denies) return {kind='legacy',charName=name,class=class,role=role,denyList=denies} end
local carol={kind='normal',account='Carol',tier='t2r',class='mage',role='rdps',spec='frost',race='human',gender='female'}
-- rows: the board; members: who is in the group at Execute (besides Alice); records: the
-- server's companion list at Execute; unit: 'party' or 'raid'.
local function run(rows,members,records,unit,rules)
    local entries={}; for i=1,40 do entries[i]=rows[i] or {kind='empty'} end
    -- This regression checks printed skip notices; Quiet mode covers their absence separately.
    local t=boot({quietMode=false,currentPreset='Default',presets={Default={entries=entries,denyRules=rules or {},setupRules={}}},
        inviteCharacters={Alice={name='Alice',level=60,raidLicense='t2r',dungeonLicense='t1d'},
            Carol={name='Carol',level=60,raidLicense='t2r',dungeonLicense='t1d'}}},'Alice')
    local clock,sent,replies,joins=100,{},{},{}
    local group={}; for _,name in ipairs(members) do table.insert(group,name) end
    local listed={}; for _,r in ipairs(records) do table.insert(listed,r) end
    t.env.GetTime=function() return clock end
    t.env.SendChatMessage=function(text,route,language,target)
        table.insert(sent,{at=clock,route=route,target=target,text=text})
        if route~='SAY' then return end
        local _,_,from,class,role=string.find(text,'^%.z addinvite (%a+) %w+ (%a+) (%a+) ')
        if from then
            local name='Hired'..string.char(96+table.getn(sent))
            table.insert(joins,{at=clock+1.5,name=name,record={name=name,class=class,role=role,owner=from}})
        end
        local _,_,real=string.find(text,'^%.z addlegacy "(%a+)"')
        if real then table.insert(joins,{at=clock+1.5,name=t.C.NormalizeLegacyName(real)}) end
    end
    t.env.SendAddonMessage=function(prefix,text)
        if prefix~='nexus' or text~='GRINFO:ALL:FULL' then return end
        local out={}
        for _,r in ipairs(listed) do table.insert(out,r.name..':Human:'..r.class..':'..r.role..':Uncommon:'..r.owner) end
        table.insert(replies,'[nexus] GRINFO:ALL:FULL '..table.concat(out,' '))
    end
    if unit=='raid' then
        t.env.GetNumRaidMembers=function() return table.getn(group)+1 end
        t.env.UnitName=function(u)
            if u=='player' or u=='raid1' then return 'Alice' end
            local _,_,n=string.find(tostring(u),'^raid(%d+)$')
            return n and group[tonumber(n)-1]
        end
    else
        t.env.GetNumPartyMembers=function() return table.getn(group) end
        t.env.UnitName=function(u)
            if u=='player' then return 'Alice' end
            local _,_,n=string.find(tostring(u),'^party(%d+)$')
            return n and group[tonumber(n)]
        end
    end
    t:click(t.env.ShirsRaidBuilderMainFrame.executeBtn)
    for _=1,480 do
        clock=clock+0.25
        local k=1
        while joins[k] do
            if joins[k].at<=clock then
                local j=table.remove(joins,k); table.insert(group,j.name)
                if j.record then table.insert(listed,j.record) end
            else k=k+1 end
        end
        for _,w in ipairs(t.frames) do if w.scripts.OnUpdate and w:IsVisible() then t:fire(w,'OnUpdate',0.25) end end
        while table.getn(replies)>0 do
            local text=table.remove(replies,1)
            t.env.event='CHAT_MSG_ADDON'; t.env.arg2='nexus'
            for _,w in ipairs(t.frames) do if w.events.CHAT_MSG_ADDON and w.scripts.OnEvent then t:fire(w,'OnEvent',text) end end
        end
    end
    local hires,whispers,lines={},{},{}
    for _,s in ipairs(sent) do
        table.insert(lines,string.format('%.2f %s %s %s',s.at,s.route,tostring(s.target),s.text))
        if s.route=='SAY' and (string.find(s.text,'^%.z addlegacy "') or string.find(s.text,'^%.z addinvite %a')) then table.insert(hires,s) end
        if s.route=='WHISPER' then table.insert(whispers,s.target..': '..s.text) end
    end
    return hires,whispers,table.concat(lines,' | '),t
end
local function said(t,text)
    for _,m in ipairs(t.messages) do if string.find(m,text,1,true) then return true end end
    return false
end
local function whispered(whispers,target,word)
    for _,w in ipairs(whispers) do
        if string.find(w,target..': ',1,true)==1 and string.find(w,word,1,true) then return true end
    end
    return false
end
local tankRule={{class='warrior',role='tank',abilities={'Shield Wall'}}}

test('three legacy already in the raid: only the missing hires go out, in order and paced',function()
    local rows={[1]=legacy('Warsoap','warrior','tank',{'Taunt'}),[2]=legacy('Lifesoap','druid','healer'),
        [3]=legacy('Sulfsoap','shaman','mdps'),[4]=carol,[5]=legacy('Newsoap','mage','rdps')}
    -- Newsoap is a player with the legacy's base name; Davecomp is another owner's mage.
    local hires,whispers,all,t=run(rows,{'Warsoap-lite','Lifesoa-lite','Sulfsoa-lite','Newsoap','Davecomp','Unknown'},
        {{name='Davecomp',class='mage',role='rdps',owner='Dave'}},'raid',tankRule)
    assert(table.getn(hires)==2,'expected 2 hires, saw '..table.getn(hires)..': '..all)
    assert(hires[1].text=='.z addinvite Carol t2r mage rdps frost human female','first hire: '..all)
    assert(hires[2].text=='.z addlegacy "Newsoap" rdps','second hire: '..all)
    assert(hires[2].at-hires[1].at>=2.5,'missing hires lost their pacing: '..all)
    assert(whispered(whispers,'Warsoap-lite','Taunt'),'present legacy lost its own denies: '..all)
    assert(whispered(whispers,'Warsoap-lite','Shield Wall'),'present legacy lost its group rule: '..all)
    assert(said(t,'Skipped 3 legacy hire(s) already in the group.'),'skip not reported')
end)

test('every hire already in the party: no hire, commands still whispered',function()
    local rows={[1]=legacy('Warsoap','warrior','tank',{'Taunt'}),[2]=legacy('Lifesoap','druid','healer'),
        [3]=legacy('Sulfsoap','shaman','mdps'),[4]=carol}
    local hires,whispers,all,t=run(rows,{'Warsoap-lite','Lifesoa-lite','Sulfsoa-lite','Carolcomp'},
        {{name='Carolcomp',class='mage',role='rdps',owner='Carol'}},'party',tankRule)
    assert(table.getn(hires)==0,'rerun hired again: '..all)
    assert(whispered(whispers,'Warsoap-lite','Taunt') and whispered(whispers,'Warsoap-lite','Shield Wall'),'rerun skipped commands: '..all)
    assert(said(t,'Skipped 3 legacy hire(s) already in the group.'),'legacy skip not reported')
    assert(said(t,'Skipped 1 normal hire(s) already present in the group.'),'normal skip not reported')
end)

test('only legacy rows, all present, no commands: completes without sending',function()
    local rows={[1]=legacy('Warsoap','warrior','tank'),[2]=legacy('Lifesoap','druid','healer'),[3]=legacy('Sulfsoap','shaman','mdps')}
    local hires,whispers,all,t=run(rows,{'Warsoap-lite','Lifesoa-lite','Sulfsoa-lite'},{},'party')
    assert(table.getn(hires)==0 and table.getn(whispers)==0,'sent commands: '..all)
    assert(said(t,'Skipped 3 legacy hire(s) already in the group.'),'skip not reported')
end)

    test('ambiguous live alias never skips one full identity or hires the other',function()
    -- Both full names share one server alias; no choice is safe at Execute.
    local rows={[1]=legacy('Shirsham','shaman','healer'),[2]=legacy('Shirshaman','shaman','healer')}
    local hires,_,all,t=run(rows,{'Shirsha-lite'},{},'party')
    assert(table.getn(hires)==0 and t.C.LegacyTargetError(t:preset().entries),'ambiguous identity sent a hire: '..all)
end)

test('a player or normal companion named like the legacy never counts as present',function()
    local rows={[1]=legacy('Warsoap','warrior','tank')}
    local hires,_,all=run(rows,{'Warsoap','Warsoap-lit'},{{name='Warsoap',class='warrior',role='tank',owner='Dave'}},'party')
    assert(table.getn(hires)==1 and hires[1].text=='.z addlegacy "Warsoap" tank','lookalike counted as present: '..all)
end)

test('normal hire dedupe stays owner-scoped beside present legacy',function()
    local rows={[1]=legacy('Warsoap','warrior','tank'),[2]=carol}
    local hires,_,all=run(rows,{'Warsoap-lite','Davecomp'},{{name='Davecomp',class='mage',role='rdps',owner='Dave'}},'party')
    assert(table.getn(hires)==1 and hires[1].text=='.z addinvite Carol t2r mage rdps frost human female','owner scope broke: '..all)
end)

print('passes='..passes..' failures='..failures)
assert(failures==0,failures..' present legacy test(s) failed')
print("Shir's Raid Builder present legacy tests: PASS")
