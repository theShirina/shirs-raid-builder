-- Production adapter, separate Vanilla environments; no real server traffic.
local f=assert(io.open('test_individual_editor.lua','r')); local source=f:read('*a'); f:close()
local boundary=assert(string.find(source,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(source,1,boundary-1)..'\nreturn boot'))()
-- Compact raid-only presentation; schedules never claim a saved lockout.
do
    local h=boot(); local C=h.C; local now=h.env.time()
    local record={dungeonLicense='t5d',raidLicense='t3r'}
    local model=C.CharacterLicenseRow('Alpha',record,4,'MC BWL AQ40 NAXX',{})
    assert(model.title=='Alpha - T3R','sidebar must combine name and raid tier only')
    assert(model.height==34 and model.raids=='MC BWL AQ40 NAXX')
    assert(record.dungeonLicense=='t5d','presentation must preserve internal dungeon license')
    local entries={}
    for _,name in ipairs({'Naxxramas',"Ahn'Qiraj Temple",'Blackwing Lair','Molten Core','Molten Core',"Zul'Gurub"}) do
        table.insert(entries,{name=name,readyAt=now+3600})
    end
    local raid={known=true,entries=entries}
    assert(C.RaidRowText(raid)=='MC BWL AQ40 NAXX','canonical saved raids only, fixed order and no duplicates')
    entries[1].scheduled=true; entries[2].readyAt=now; entries[3].ready=true
    assert(C.RaidRowText(raid)=='MC','schedule, expired and synthetic Ready rows are not saves')
    assert(C.RaidRowText(nil)=='' and C.RaidRowText({known=true,entries={}})=='')
    local row=C.DrawCharacterLicenseRow(model,0)
    assert(row.lines[2].textColor[1]==1 and row.lines[2].textColor[2]==0.35 and row.lines[2].textColor[3]==0.1,'saved raids need warning color')
    assert(table.getn(row.lines)==2 and row.lines[1]:GetText()=='Alpha - T3R')
    assert(row.lines[2]:GetText()=='MC BWL AQ40 NAXX' and not row:GetScript('OnEnter'),'no verbose hover block')
    row=C.DrawCharacterLicenseRow(C.CharacterLicenseRow('Beta',{raidLicense='t2r',dungeonLicense='unknown'},nil,''),-36)
    assert(row.lines[1]:GetText()=='Beta - T2R' and row:GetHeight()==20 and not row.lines[2]:IsShown())
end
local function snapshot(value)
    if type(value)~='table' then return type(value)..':'..tostring(value) end
    local t={}; for k,v in pairs(value) do table.insert(t,snapshot(k)..'='..snapshot(v)) end
    table.sort(t); return '{'..table.concat(t,',')..'}'
end
local function emit(h,event,text,sender)
    h.env.event=event; h.env.arg2=sender
    for _,frame in ipairs(h.frames) do
        if frame.events[event] and frame:GetScript('OnEvent') then h:fire(frame,'OnEvent',text) end
    end
end
local function client(name,saved)
    local h=boot(saved,name); h.name=name; h.now=100; h.wall=1800000000; h.sent={}; h.history={}; h.reads={}; h.server={}
    h.env.GetTime=function() return h.now end; h.env.time=function() return h.wall end
    h.env.GetNumSavedInstances=function() return 1 end
    h.env.GetSavedInstanceInfo=function() return 'Molten Core',42,7200 end
    h.env.RequestRaidInfo=function() table.insert(h.reads,'native') end
    h.env.MCP_Send=function() error('MCP group routing must not send server reads') end
    h.env.MCP_SelfLockProto=2
    h.env.SendChatMessage=function(text,route,language,target)
        if route=='SAY' then
            if text=='.stats locks alts' then
                table.insert(h.reads,text)
                table.insert(h.server,'[nexus] ACINFO:SELFLOCK:HEAD 1:3:50:2:1')
                table.insert(h.server,'[nexus] ACINFO:SELFLOCK:END')
                return
            end
            assert(text=='.z addinvite list','non-read server command: '..text)
            table.insert(h.reads,text)
            table.insert(h.server,'[nexus] ACINFO:INVITE:LIST '..(h.roster or (name..':warrior:t2d:t3r:A:0:60:0:4 Alt:mage:unavailable:t1r:A:0:60:0:4 Young:mage:t5d:t5r:A:0:59:0:4')))
            return
        end
        assert(route=='WHISPER' and language==nil and type(target)=='string')
        assert(h.C.LinkParse(text) or h.C.LicenseParse(text) or h.C.RaidParse(text) or (h.C.AccountParse and h.C.AccountParse(text)),'unknown outgoing packet')
        assert(string.len(text)<=240)
        table.insert(h.sent,{text=text,target=target}); table.insert(h.history,{text=text,target=target})
    end
    for _,action in ipairs({'InviteByName','UninviteByName','SetRaidSubgroup','SwapRaidSubgroup','PromoteToLeader','SendAddonMessage'}) do
        h.env[action]=function() error('remote data reached action API') end
    end
    return h
end
local function tick(h,seconds)
    h.now=h.now+(seconds or 0.25); h.wall=1800000000+math.floor(h.now-100)
    h:fire(h.C.peerDriver,'OnUpdate',seconds or 0.25)
end
local function run(clients,seconds,approve)
    local byName={}; for _,h in ipairs(clients) do byName[string.lower(h.name)]=h end
    for i=1,seconds*4 do
        for _,h in ipairs(clients) do tick(h) end
        for _,h in ipairs(clients) do
            while table.getn(h.sent)>0 do
                local packet=table.remove(h.sent,1); local to=byName[packet.target]
                if to then emit(to,'CHAT_MSG_WHISPER',packet.text,h.name) end
            end
            while table.getn(h.server)>0 do
                local text=table.remove(h.server,1)
                emit(h,'CHAT_MSG_ADDON',text,'nexus')
                if text=='[nexus] ACINFO:SELFLOCK:END' then
                    h.env.MCP_SelfLockData={locks=h.locks or {{map=409,id=42,resetAt=h.now+7200}},alts={},sched={{map=469,resetAt=h.now+8000}}}
                end
            end
            if approve and h.C.peerPrompt and h.C.peerPrompt:IsShown() then
                h.C.peerPrompt.rememberCheck:SetChecked(1); h:click(h.C.peerPrompt.acceptButton)
            end
        end
    end
end
local function pair(h,name)
    h.C.OpenPeerPOC(); h.C.peerPanel.nameInput:SetText(name)
    h.C.peerPanel.rememberCheck:SetChecked(1); h:click(h.C.peerPanel.pairButton)
end
local function state(h,name) return h.C.peerSessions['FixtureRealm;'..string.lower(name)].state end
local function requests(h,name)
    local n=0
    for _,packet in ipairs(h.history) do
        local p=h.C.LicenseParse(packet.text)
        if p and (p.kind=='GET' or p.kind=='GETONCE') and packet.target==string.lower(name) then n=n+1 end
    end
    return n
end
local a,b,c=client('Alice'),client('Bob'),client('Carol')
assert(type(a.C.SyncRefreshAll)=='function','manual refresh-all runtime missing')
local beforeA=snapshot(a:preset()); local beforeB=snapshot(b:preset()); local beforeC=snapshot(c:preset())
local queues=snapshot(a.C.BuildQueue(a:preset()))
pair(a,'Bob'); local bob=state(a,'Bob'); local invitation=a.C.peerPending
pair(a,'Carol')
assert(state(a,'Bob')==bob and bob.phase=='waiting','selector or new peer cancelled invitation')
assert(a.C.peerSessions['FixtureRealm;bob'].pending==invitation)
assert(table.getn(a.history)==0,'send must be deferred')
run({a,b,c},8,true)
assert(requests(a,'Bob')==0 and requests(a,'Carol')==0,'Pair must only establish consent')
a.C.SyncRefreshAll(); run({a,b,c},25,true)
assert(state(a,'Bob').phase=='linked' and state(a,'Carol').phase=='linked','multiple endpoints failed to link')
assert(requests(a,'Bob')==1 and requests(a,'Carol')==1,'one batch per new link')
for _,name in ipairs({'bob','carol'}) do
    local key='FixtureRealm;'..name
    local licenses=assert(a.C.remoteLicenses[key],'missing license snapshot '..name)
    assert(licenses.accountId and licenses.entries[1].level==60,'account identity/level missing from received snapshot')
    assert(table.getn(licenses.entries)==2 and licenses.entries[1].name=='Alt')
    assert(licenses.entries[1].dungeonLicense=='unknown' and licenses.entries[1].raidLicense=='t1r')
    local raids=assert(a.C.remoteRaids[key],'missing raid snapshot '..name)
    assert(raids.character==name or string.lower(raids.character)==name)
    assert(raids.entries[1].id==42,'MCP lock missing')
    assert(table.getn(raids.entries)==1 and not raids.entries[1].scheduled,'general schedule leaked into peer stream')
    assert(not state(a,name).licenseWait and not state(a,name).raidWait,'separate streams failed completion')
end
assert(snapshot(a:preset())==beforeA and snapshot(b:preset())==beforeB and snapshot(c:preset())==beforeC,'remote traffic mutated plans')
assert(snapshot(a.C.BuildQueue(a:preset()))==queues,'remote claims changed action queue')
local ownFound=false
for _,row in ipairs(a.env.ShirsRaidBuilderMainFrame.accountRows) do
    if row.model and row.model.name=='Alice' and not row.model.source then
        ownFound=true; assert(row.model.raids=='MC','current native raid rows missing locally')
    end
end
assert(ownFound)
local main=a.env.ShirsRaidBuilderMainFrame
assert(main.accountBar and main.accountBar.kind=='Button' and main.accountBar.thumb,'reuse custom track/thumb pattern')
local host=a.env.CreateFrame('Frame',nil,main)
local list=a.C.EnsureDenyListScroll(host,{width=100,rowHeight=20,x=0,y=0,
    createRow=function(parent) return a.env.CreateFrame('Button',nil,parent) end,bindRow=function() end})
assert(main.accountBar.backdrop==list.track.backdrop and main.accountBar.thumb.backdrop==list.thumb.backdrop)
assert(snapshot(main.accountBar.backdropColor)==snapshot(list.track.backdropColor))
assert(snapshot(main.accountBar.thumb.backdropColor)==snapshot(list.thumb.backdropColor))
assert(main.accountBar:GetWidth()==list.track:GetWidth() and main.accountBar.thumb:GetWidth()==list.thumb:GetWidth())
local remoteRows=0; local alts=0; local linkedOrder={}
for _,row in ipairs(main.accountRows) do
    if row.model and row.model.source then
        remoteRows=remoteRows+1
        table.insert(linkedOrder,row.model.name)
        assert(row.lines[1]:GetText()==row.model.title and row.lines[2]:GetText()==row.model.raids)
        assert(table.getn(row.lines)==2 and not row:GetScript('OnEnter'))
        if row.model.name=='Alt' then
            alts=alts+1; assert(row.model.raids=='','current lockouts assigned to alt')
        end
        a:click(row)
    end
    assert(not string.find(row.lines[1]:GetText(),'Read-only / not live',1,true),'large linked header returned')
end
assert(remoteRows==4 and alts==2,'source/realm/character dedupe lost a distinct peer claim')
assert(table.concat(linkedOrder,',')=='Bob,Alt,Carol,Alt','linked accounts must remain contiguous, each descending by raid tier')
assert(snapshot(a:preset())==beforeA,'remote row click mutated plan')
local pooled=table.getn(main.accountPool); local frameCount=table.getn(a.frames)
for i=1,20 do a.env.RefreshAccountPanel() end
assert(table.getn(main.accountPool)==pooled and table.getn(a.frames)==frameCount,'sidebar refresh allocates frames')
-- Force actual overflow now that rows are compact.
main.accountScroll:SetHeight(80); a.env.RefreshAccountPanel()
assert(main.accountContent:GetHeight()>main.accountScroll:GetHeight())
a:fire(main.accountRows[1],'OnMouseWheel',-1)
assert(main.accountRows[1].wheel and main.accountScroll:GetVerticalScroll()==math.min(60,main.accountBar.maximum),'row wheel must scroll within range')
a:fire(main.accountBar.thumb,'OnMouseDown','LeftButton')
a.env.GetCursorPosition=function() return 0,-99999 end
a:fire(main.accountBar.thumb,'OnUpdate',0.1)
assert(main.accountScroll:GetVerticalScroll()==main.accountBar.maximum,'drag scroll not clamped')
a:fire(main.accountBar.thumb,'OnMouseUp','LeftButton')
assert(not main.accountBar.dragging)
a.C.AccountScroll(0); assert(main.accountScroll:GetVerticalScroll()==0)
assert(main.syncButton.point[4]+main.syncButton:GetWidth()<main.titleDrag.point[4],'title drag overlaps refresh')
a.C.peerPanel.nameInput:SetText('Bob'); a:click(a.C.peerPanel.knownButton)
assert(a.C.peerPanel.nameInput:GetText()=='Carol','visible known-peer selector')
local saved=a.env.ShirsRaidBuilderDB
local frozen=snapshot(saved.peerSnapshots); local raidFrozen=snapshot(saved.peerRaidSnapshots)
local sent=table.getn(a.history)
local reads=table.getn(a.reads)+table.getn(b.reads)+table.getn(c.reads)
run({a,b,c},180,true)
assert(table.getn(a.history)==sent,'periodic keepalive or repeated synchronization')
assert(table.getn(a.reads)+table.getn(b.reads)+table.getn(c.reads)==reads,'periodic local data requests')
assert(snapshot(saved.peerSnapshots)==frozen and snapshot(saved.peerRaidSnapshots)==raidFrozen,'expiry deleted snapshots')
assert(string.find(a.C.LicenseAgeLabel(a.C.remoteLicenses['FixtureRealm;bob'],a.wall),'stale',1,true))
-- Explicit all-peer refresh while selector points at just one peer.
a:click(main.syncButton); a:click(main.syncButton); run({a,b,c},25,true)
assert(requests(a,'Bob')==2 and requests(a,'Carol')==2,'manual refresh did not cover every linked endpoint')
sent=table.getn(a.history); run({a,b,c},90,true); assert(table.getn(a.history)==sent)
-- Opening must never start synchronization or a server read.
local openSent=table.getn(a.history); local openReads=table.getn(a.reads)
main:Hide(); main:Show(); run({a,b,c},25,true)
assert(table.getn(a.history)==openSent and table.getn(a.reads)==openReads,'open initiated synchronization')
-- Revocation targets only visible endpoint and prevents saved restore.
a.C.OpenPeerPOC(); a.C.peerPanel.nameInput:SetText('Bob'); a:click(a.C.peerPanel.forgetButton)
assert(not a.C.LinkKnown(saved.peerLinks,'Alice','Bob','FixtureRealm'))
assert(a.C.LinkKnown(saved.peerLinks,'Alice','Carol','FixtureRealm'))
assert(not a.C.remoteLicenses['FixtureRealm;bob'] and not a.C.remoteRaids['FixtureRealm;bob'])
assert(a.C.remoteLicenses['FixtureRealm;carol'] and state(a,'Carol').phase=='disabled')
local reload=client('Alice',saved)
reload.C.PeerLogin()
assert(not reload.C.remoteLicenses['FixtureRealm;bob'] and reload.C.remoteLicenses['FixtureRealm;carol'])
assert(not reload.C.remoteRaids['FixtureRealm;bob'] and reload.C.remoteRaids['FixtureRealm;carol'])
assert(not state(reload,'Carol').remoteLicense and state(reload,'Carol').phase=='waiting','reload restored a live session')
run({reload},70,false)
assert(table.getn(reload.history)==1,'offline startup repeats invitations')
assert(reload.C.remoteLicenses['FixtureRealm;carol'],'offline timeout removed saved rows')
-- Separate inbound invitations, approval UI and edits cannot cancel each other.
local x,y,z=client('Dora'),client('Eric'),client('Faye')
pair(y,'Dora'); pair(z,'Dora'); run({x,y,z},2,false)
assert(state(x,'Eric').phase=='approval' and state(x,'Faye').phase=='approval')
x.C.OpenPeerPOC(); x.C.peerPanel.nameInput:SetText('Other')
assert(state(x,'Eric').phase=='approval' and state(x,'Faye').phase=='approval')
run({x,y,z},23,true)
assert(x.C.LinkKnown(x.env.ShirsRaidBuilderDB.peerLinks,'Dora','Eric','FixtureRealm'))
assert(x.C.LinkKnown(x.env.ShirsRaidBuilderDB.peerLinks,'Dora','Faye','FixtureRealm'))
-- Unknown native API sends UNKNOWN, never invents an empty known lockout list.
local unknown=client('Gina'); unknown.env.GetNumSavedInstances=nil; unknown.env.GetSavedInstanceInfo=nil
assert(not unknown.C.RaidReadLocal().known)
-- Exact CCP event channel only; expired schedule rejected, future schedule accepted.
unknown.C.RaidRequestLocal()
emit(unknown,'CHAT_MSG_MONSTER_WHISPER','[nexus] ACINFO:SELFLOCK:HEAD 1:3:50','nexus')
assert(not unknown.C.raidLocalBuffer,'wrong CCP event channel accepted')
assert(unknown.C.LicenseAgeLabel({source='Bob',realm='FixtureRealm'},unknown.wall)=='Age unavailable','missing snapshot invented a timestamp')
-- Account-forget removes every saved scope for that endpoint, not another peer.
local linkDB={}
local sa=a.C.PeerNew('Alice','Bob','FixtureRealm'); sa.phase='linked'
local sc=a.C.PeerNew('Alice','Carol','FixtureRealm'); sc.phase='linked'
a.C.LinkSave(linkDB,sa,false); a.C.LinkSave(linkDB,sa,true); a.C.LinkSave(linkDB,sc,true)
a.C.LinkForget(linkDB,'Alice','Bob','FixtureRealm',true)
assert(not a.C.LinkKnown(linkDB,'Alice','Bob','FixtureRealm') and a.C.LinkKnown(linkDB,'Alice','Carol','FixtureRealm'))
-- Sort hides the scrollbar as well as all character rows.
a.env.ShirsRaidBuilderDB.uiMode='sort'; a.C.ApplyRaidMode()
assert(not main.accountContent:IsShown() and not main.accountBar:IsShown())
a.env.ShirsRaidBuilderDB.uiMode='hire'; a.C.ApplyRaidMode(); a.env.RefreshAccountPanel()
assert(main.accountContent:IsShown())
-- Simultaneous explicit invitations still require one visible approval.
local p,q=client('Iris'),client('Jack')
pair(p,'Jack'); pair(q,'Iris'); run({q,p},25,true)
assert(state(p,'Jack').phase=='linked' and state(q,'Iris').phase=='linked','simultaneous new invitations stalled')
-- Saved-link collision election is independent of delivery order.
for _,reverse in ipairs({false,true}) do
    local p,q=client('Gwen'),client('Hugh')
    local ps=p.C.PeerNew('Gwen','Hugh','FixtureRealm'); ps.phase='linked'
    local qs=q.C.PeerNew('Hugh','Gwen','FixtureRealm'); qs.phase='linked'
    p.C.LinkSave(p.env.ShirsRaidBuilderDB.peerLinks,ps,true)
    q.C.LinkSave(q.env.ShirsRaidBuilderDB.peerLinks,qs,true)
    p.C.SyncRefreshAll(); q.C.SyncRefreshAll()
    if reverse then run({q,p},25,true) else run({p,q},25,true) end
    assert(state(p,'Hugh').phase=='linked' and state(q,'Gwen').phase=='linked','saved collision order')
    assert(requests(p,'Hugh')==1 and requests(q,'Gwen')==1,'collision duplicated sync')
end
-- Logins seconds apart: the first account's invitation goes out while the other is offline
-- and is lost, and stays open for 60 s. The second's invitation then reaches a side still
-- waiting on its own; the pair must still link and swap rows, whichever name sorts first.
-- 5 s apart the first sends its invitation again; 15 and 45 s apart it takes the fresh one,
-- since a link lasts only as long as the invitation it came from.
for _,gap in ipairs({5,15,45}) do
    for _,order in ipairs({{'Kate','Liam'},{'Liam','Kate'}}) do
        local first,second=client(order[1]),client(order[2])
        pair(first,order[2]); run({first,second},25,true)
        local again=client(order[1],first.env.ShirsRaidBuilderDB)
        again.now=first.now; again.wall=first.wall; again.C.PeerLogin(); run({again},gap,false)
        local later=client(order[2],second.env.ShirsRaidBuilderDB)
        later.now=again.now; later.wall=again.wall; later.C.PeerLogin(); run({again,later},40,true)
        assert(again.C.remoteLicenses['FixtureRealm;'..string.lower(order[2])] and later.C.remoteLicenses['FixtureRealm;'..string.lower(order[1])],
            order[1]..' logged in '..gap..' s before '..order[2]..' and the pair never swapped rows: '..tostring(state(again,order[2]).reason)..' / '..tostring(state(later,order[1]).reason))
        assert(requests(again,order[2])<=1 and requests(later,order[1])<=1,'a late login duplicated the sync')
    end
end
-- Ten accounts, every pair linked, logging in one by one 15 s apart: each login links with
-- whoever is online, so after the last one every account holds every other's rows, and
-- every faction and licence with them.
do
    local names={'Mona','Nate','Olga','Pete','Quin','Rosa','Saul','Tina','Umar','Vera'}
    local first={}
    for k,name in ipairs(names) do
        first[k]=client(name)
        first[k].roster=name..':warrior:none:t'..(1+math.mod(k,5))..'r:A:0:60:0:4 '..name..'a:priest:t2d:t4r:'..(math.mod(k,3)==0 and 'H' or 'A')..':0:60:0:4'
    end
    for i=1,10 do
        for j=i+1,10 do pair(first[i],names[j]) end
        run(first,30,true)
    end
    local online={}
    for k,name in ipairs(names) do
        local h=client(name,first[k].env.ShirsRaidBuilderDB); h.roster=first[k].roster
        local clock=online[1] or first[1]
        h.now=clock.now; h.wall=clock.wall
        table.insert(online,h); h.C.PeerLogin(); run(online,15,true)
    end
    run(online,60,true)
    for i,h in ipairs(online) do
        for j,name in ipairs(names) do
            if i~=j then
                local rows=h.C.remoteLicenses['FixtureRealm;'..string.lower(name)]
                assert(rows,names[i]..' never got '..name..' rows after ten logins 15 s apart')
                local alt
                for _,r in ipairs(rows.entries) do if r.name==name..'a' then alt=r end end
                assert(alt and alt.faction==(math.mod(j,3)==0 and 'Horde' or 'Alliance') and alt.raidLicense=='t4r',names[i]..' got '..name..'a without its faction or licence')
            end
        end
    end
end
-- Same account, two approved character endpoints, offline druid snapshot retained.
local viewer,druid=client('Viewer'),client('Druid')
druid.roster='Druid:druid:t3d:t4r:A:0:60:0:4 Warrior:warrior:t2d:t2r:A:0:60:0:4 Young:mage:t5d:t5r:A:0:59:0:4'
pair(viewer,'Druid'); run({viewer,druid},8,true); viewer.C.SyncRefreshAll(); run({viewer,druid},25,true)
local accountId=assert(druid.env.ShirsRaidBuilderDB.syncAccountId)
local warrior=client('Warrior',druid.env.ShirsRaidBuilderDB)
warrior.now=viewer.now; warrior.wall=viewer.wall
warrior.roster='Warrior:warrior:t2d:t3r:A:0:60:0:4 Young:mage:t5d:t5r:A:0:59:0:4'
warrior.locks={{map=469,id=77,resetAt=warrior.now+9000}}
pair(warrior,'Viewer'); run({viewer,warrior},8,true); warrior.C.SyncRefreshAll(); run({viewer,warrior},25,true)
assert(warrior.env.ShirsRaidBuilderDB.syncAccountId==accountId,'account ID changed with character')
local headers,druidRows,warriorRows=0,0,0
for _,row in ipairs(viewer.env.ShirsRaidBuilderMainFrame.accountRows) do
    if string.find(row.lines[1]:GetText(),'Linked:',1,true) then headers=headers+1 end
    if row.model and row.model.source then
        assert(row.model.name~='Young','lower-level remote row')
        if row.model.name=='Druid' then druidRows=druidRows+1; assert(row.model.raids=='MC','warrior refresh lost druid saves') end
        if row.model.name=='Warrior' then warriorRows=warriorRows+1; assert(row.model.raids=='BWL','warrior owns only MCP saves: '..row.model.raids) end
    end
end
assert(headers==1 and druidRows==1 and warriorRows==1,'duplicate account section or lost character')
for _,row in ipairs(warrior.env.ShirsRaidBuilderMainFrame.accountRows) do
    assert(not row.model or row.model.name~='Young','lower-level local row')
end
local sentBefore=table.getn(warrior.history); local readsBefore=table.getn(warrior.reads)
warrior.env.SlashCmdList.SHIRSRAIDBUILDER(''); warrior.env.SlashCmdList.SHIRSRAIDBUILDER('')
run({warrior},70,false)
assert(table.getn(warrior.history)==sentBefore and table.getn(warrior.reads)==readsBefore,'slash reopen sync')
local restored=client('Warrior',warrior.env.ShirsRaidBuilderDB)
assert(restored.env.ShirsRaidBuilderDB.syncAccountId==accountId)
local collected=restored.C.AccountReadLocal()
local found=false
for _,row in ipairs(collected) do if row.name=='Druid' then found=true; assert(restored.C.AccountRaidLabels(row,restored.wall)=='MC') end end
assert(found,'offline druid lost after reload')
print("Shir's Raid Builder sync UI tests: PASS")
