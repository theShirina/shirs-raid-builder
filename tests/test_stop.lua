-- Exact Lua 5.0.3: production constructors, registered handlers and transport.
-- Offline fixtures prove local state/dispatch only, not in-game/server behavior.
local f=assert(io.open('test_individual_editor.lua','r')); local fixture=f:read('*a'); f:close()
local boundary=assert(string.find(fixture,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(fixture,1,boundary-1)..'\nreturn boot'))()
local ids={Alice='1111111111111111',Bob='2222222222222222'}
local function client(name)
 local h=boot(nil,name or 'Alice'); h.name=name or 'Alice'; h.now=100; h.wall=1800000000; h.sent={}; h.addon={}
 h.env.GetTime=function() return h.now end; h.env.time=function() return h.wall end
 h.env.SendChatMessage=function(text,route,lang,target) table.insert(h.sent,{text=text,route=route,target=target}) end
 h.env.SendAddonMessage=function(prefix,text) table.insert(h.addon,{prefix=prefix,text=text}) end
 h.C.PeerOnBuilderOpen(); h.C.peerAutoAttempted=nil
 h.env.ShirsRaidBuilderDB.syncAccountId=ids[h.name]
 return h
end
local function pump(h,seconds)
 for i=1,seconds*4 do
  h.now=h.now+0.25; h.wall=1800000000+math.floor(h.now-100)
  for _,w in ipairs(h.frames) do if w.scripts.OnUpdate and w:IsVisible() then h:fire(w,'OnUpdate',0.25) end end
 end
end
local function stop(h) h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Stop')) end
local function normal(who) return {kind='normal',account=who,class='mage',role='rdps',spec='frost',tier='t2r',race='human',gender='female'} end
local function board(h,entries)
 local p=h:preset(); p.entries={}; p.denyRules={}; p.setupRules={}
 for i=1,40 do p.entries[i]=entries[i] or {kind='empty'} end
end
local function link(h,peer,live)
 local C,db=h.C,h.env.ShirsRaidBuilderDB
 local s=C.PeerNew(h.name,peer,'FixtureRealm'); s.phase='linked'; assert(C.LinkSave(db.peerLinks,s,true))
 db.peerSnapshots['FixtureRealm;'..string.lower(peer)]={accountId=ids[peer],source=string.lower(peer),realm='FixtureRealm',received=h.wall-600,observed=h.wall-600,
  entries={{name=peer,level=60,dungeonLicense='t1d',raidLicense='t2r',observed=h.wall-600}},authoritative=false}
 C.LicenseRestoreSaved()
 if live then
  s.phase='linked'; s.a='100001'; s.b='100002'; s.started=h.now; s.deadline=h.now+60; s.expires=h.wall+60
 end
 C.SyncSelect(s,true); C.peerState=s; C.SyncStore()
 return s
end
local failed,passed=0,0
local function test(name,fn)
 local ok,err=pcall(fn)
 if ok then passed=passed+1; print('PASS '..name) else failed=failed+1; print('FAIL '..name..': '..tostring(err)) end
end

test('Stop cancels a first remote group before any local command or grant send',function()
 local h=client(); local s=link(h,'Bob',true)
 board(h,{[1]=normal('Bob'),[6]={kind='legacy',charName='Later',class='mage',role='rdps'}})
 h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn)
 local store=h.C.HandStore(); local run=assert(store.active)
 assert(run.phase=='waiting' and s.handOut and h.C.handAuthority and table.getn(h.sent)==0,'fixture did not queue the first grant')
 local step=run.step
 stop(h)
 assert(run.phase=='cancelled','main Stop only pauses the run; separate Cancel process is still required')
 assert(store.seen[run.id] and store.seen[run.id].cancelled,'Stop did not tombstone the cancelled run')
 assert(not h.C.handAuthority and not h.C.handRunPlan and not h.C.handAwaitLink and not h.C.handTransfer and not h.C.handReportDeadline and not h.C.handNotify,'Stop retained a continuation')
 assert(not s.handOut and not s.handInput and not s.handProposal and not s.handProgress and not h.C.HandParse(h.C.peerPending),'Stop retained handoff packets')
 local notice=h.C.handNotice
 stop(h); pump(h,120)
 assert(table.getn(h.sent)==0 and run.phase=='cancelled' and run.step==step and h.C.handNotice==notice,'repeated Stop or peer ticking changed the stopped run')
end)

test('only main Stop remains; progress and pause recovery stay on retained UI',function()
 local h=client(); local main=h.env.ShirsRaidBuilderMainFrame
 for _,w in ipairs(h.frames) do
  local label=w.kind=='Button' and w.label and w.label:GetText()
  assert(label~='Hire status' and label~='Hire Status','retired Hire status button was constructed')
 end
 h.C.OpenHandoff()
 local panel=assert(h.C.handFrame)
 for _,w in ipairs(h.frames) do
  local label=w.kind=='Button' and w.label and w.label:GetText()
  assert(label~='Cancel process' and label~='Cancel execution' and label~='Stop execution','redundant execution control was constructed: '..tostring(label))
 end
 panel:Hide()
 link(h,'Bob',true); board(h,{[1]=normal('Bob'),[6]={kind='legacy',charName='Later',class='mage',role='rdps'}})
 h:click(main.executeBtn); h.C.HandTick()
 assert(main.handProgress==nil,'obsolete persistent top progress still exists')
 assert(string.find(main.stopBtn.tip,'waiting',1,true),'Stop hover lost live process progress')
 assert(main.plannerBtn and main.plannerBtn.point[4]==310 and main.plannerBtn.point[5]==-8,'planner must use the retired status-button area without restoring that button')
 local reason='Process timed out. Check submitted hires before starting another run.'
 h.C.HandPause(reason)
 stop(h); h.C.HandTick()
 assert(string.find(h.C.handNotice,reason,1,true),'Stop hid the prior pause reason')
 local button=h:button(main,'Stop')
 assert(string.find(button.tip,'Bob',1,true) and string.find(button.tip,h.C.handNotice,1,true),'Stop hover lost actor, progress or recovery detail')
 local lines={}; h.env.GameTooltip.AddLine=function(self,text) table.insert(lines,text) end
 h:fire(button,'OnEnter')
 assert(table.concat(lines,'\n')==button.tip,'registered Stop hover did not render diagnostics')
 h:fire(button,'OnLeave'); assert(not h.env.GameTooltip:IsShown(),'Stop hover did not close')
 assert(main.handProgress==nil and string.find(button.tip,'cancelled',1,true),'Stop diagnostics missing or obsolete top caption returned')
 local notice=h.C.handNotice; stop(h); pump(h,80)
 assert(h.C.handNotice==notice,'idle Stop hid recovery text')
 local count=0; for _,w in ipairs(h.frames) do if w.parent==main and w.kind=='Button' and w.label and w.label:GetText()=='Stop' then count=count+1 end end
 assert(count==1,'main Stop is missing or duplicated')
 assert(button.point[4]==510 and button.point[5]==-76 and button:GetWidth()==118,'existing Stop geometry changed')
end)

local function event(h,name,text,sender)
 h.env.event=name; h.env.arg2=sender
 for _,w in ipairs(h.frames) do if w.events[name] and w.scripts.OnEvent then h:fire(w,'OnEvent',text) end end
end
local function receive(h,s,g,nonce)
 local tx=h.C.PeerNew(s.peerLabel,h.name,'FixtureRealm')
 tx.phase='linked'; tx.a=s.a; tx.b=s.b; tx.started=h.now; tx.deadline=h.now+60; tx.expires=s.expires
 local packets=assert(h.C.HandPackets(tx,assert(h.C.HandEncode(g)),nonce,h.wall,h.now))
 for _,text in ipairs(packets) do event(h,'CHAT_MSG_WHISPER',text,s.peerLabel) end
 return packets
end
local function grant(h)
 local g=assert(h.C.HandCreate({entries={[1]=normal('Bob'),[6]={kind='legacy',charName='Later',class='mage',role='rdps'}}},
  'Stopped run','Alice','FixtureRealm',{'Bob','Alice'},'1234567890123456',h.wall,nil,nil,true))
 g.kind='GRANT'; g.accounts={ids.Bob,ids.Alice}; g.expires=h.wall+7200
 return g
end
local function queueFrame(h)
 for _,w in ipairs(h.frames) do
  local fn=w.scripts.OnUpdate; local i=1
  while fn do
   local name=debug.getupvalue(fn,i); if not name then break end
   if name=='executeIndex' then return w,fn end
   i=i+1
  end
 end
 error('real execution OnUpdate missing')
end
local function values(fn)
 local out,i={},1
 while true do local name,v=debug.getupvalue(fn,i); if not name then return out end; out[name]=v; i=i+1 end
end
local function quietAfter(h,fn,expected)
 local n,a=table.getn(h.sent),table.getn(h.addon)
 stop(h); if fn then fn() end
 event(h,'CHAT_MSG_TEXT_EMOTE','First-lite nods at you.','First-lite')
 event(h,'CHAT_MSG_ADDON','[nexus] GRINFO:ALL:FULL First-lite:Human:mage:rdps:Uncommon:Alice','nexus')
 pump(h,100)
 assert(table.getn(h.sent)==n and table.getn(h.addon)==a,'Stop left sends or discovery callbacks running')
 if fn then
  local v=values(fn)
  assert(not v.executing and not v.executeQueue and v.executeIndex==0 and not v.executeWaitingNod and not v.executeNodReady and v.executeHireReadyAt==0,'private execution state survived Stop')
 end
 for _,key in ipairs({'hireBefore','hireJoinedAt','legacyWait','executePreflightStarted','executePreflightComplete','grinfoAskedAt','whisperRun','scopeAsks','scopeCheckedAt','scopeShort','grinfoRefresh'}) do
  assert(h.C[key]==nil,'Stop retained '..key)
 end
 if expected then assert(n==expected,'fixture sent '..n..' messages, expected '..expected) end
end

test('Stop clears a paced local hire and every execution wait',function()
 local h=client(); board(h,{[1]=normal('Alice'),[2]=normal('Alice')})
 h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn)
 local w,fn=queueFrame(h)
 assert(table.getn(h.sent)==1 and h.C.hireBefore and values(fn).executeHireReadyAt>h.now,'fixture did not start its first paced hire')
 quietAfter(h,fn,1); assert(not w.scripts.OnUpdate,'execution handler remained registered')
end)

test('Stop before first send cancels preflight and a late companion list',function()
 local h=client(); board(h,{[1]=normal('Alice')})
 h.env.GetNumPartyMembers=function() return 1 end
 h.env.UnitName=function(unit) if unit=='player' then return 'Alice' elseif unit=='party1' then return 'Oldcomp' end end
 h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn)
 local w,fn=queueFrame(h)
 assert(table.getn(h.sent)==0 and table.getn(h.addon)==0 and not h.C.executePreflightComplete,'fixture did not wait before first send')
 quietAfter(h,fn,0)
end)

test('Stop cancels running and paced whispers without a final deny',function()
 for _,paced in ipairs({false,true}) do
  local h=client(); board(h,{[1]={kind='legacy',charName='First',class='mage',role='rdps',denyList={'Blink','Blizzard'}}})
  h.env.GetNumPartyMembers=function() return 1 end
  h.env.UnitName=function(unit) if unit=='player' then return 'Alice' elseif unit=='party1' then return 'First-lite' end end
  h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn)
  local _,fn=queueFrame(h)
  assert(table.getn(h.sent)==1 and h.sent[1].route=='WHISPER','fixture did not send its first deny')
  if paced then event(h,'CHAT_MSG_TEXT_EMOTE','First-lite nods at you.','First-lite'); pump(h,0.25); assert(values(values(fn).ReadyForNext).executeWhisperGap>0,'fixture never paced whispers') end
  quietAfter(h,fn,1)
 end
end)

test('Stop tombstones a received GRANT before approval, including fresh nonce retry',function()
 local h=client('Bob'); local s=link(h,'Alice',true); local g=grant(h)
 receive(h,s,g,'600001'); assert(s.handProposal and not h.C.HandStore().active and table.getn(h.sent)==0,'fixture did not hold an unapproved GRANT')
 stop(h)
 local seen=h.C.HandStore().seen
 assert(seen and seen[g.id] and seen[g.id].cancelled,'Stop discarded the proposal without revoking its run')
 local notice=h.C.handNotice
 receive(h,s,g,'600002'); h.C.HandTick(); pump(h,20)
 assert(not h.C.handAuthority and not h.C.HandStore().active and table.getn(h.sent)==0,'late GRANT started a stopped run')
 assert(h.C.handNotice==notice,'late stopped GRANT hid recovery status')
end)

test('late REPORT and duplicate GRANT cannot advance or hide a stopped run',function()
 local h=client(); local s=link(h,'Bob',true)
 board(h,{[1]=normal('Bob'),[6]={kind='legacy',charName='Later',class='mage',role='rdps'}})
 h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn)
 local run=h.C.HandStore().active; local r=assert(h.C.HandDecode(h.C.HandEncode(run))); r.kind='REPORT'
 stop(h); local notice=h.C.handNotice
 receive(h,s,r,'600003'); h.C.HandTick(); pump(h,10)
 assert(run.phase=='cancelled' and run.step==1 and not h.C.handAuthority and table.getn(h.sent)==0,'late REPORT advanced the stopped run')
 assert(h.C.handNotice==notice,'late stopped REPORT hid recovery status')
 local b=client('Bob'); local bs=link(b,'Alice',true); local g=grant(b)
 receive(b,bs,g,'600001'); b.C.HandTick(); assert(table.getn(b.sent)==1 and b.C.handAuthority,'fixture did not run a granted hire')
 stop(b); local before=table.getn(b.sent); notice=b.C.handNotice
 receive(b,bs,g,'600002'); b.C.HandTick(); pump(b,20)
 assert(table.getn(b.sent)==before and not b.C.handAuthority and b.C.HandStore().active.phase=='cancelled','duplicate GRANT resumed a stopped participant')
 assert(b.C.handNotice==notice,'duplicate stopped GRANT hid recovery status')
end)

test('automatic pause keeps refusal semantics distinct from explicit Stop',function()
 local h=client('Bob'); local s=link(h,'Alice',true); local g=grant(h)
 receive(h,s,g,'600001'); h.C.HandTick()
 local run=h.C.HandStore().active; assert(h.C.handRunPlan and table.getn(h.sent)==1,'fixture did not run a granted queue')
 h.C.HandPause('Paused: companion discovery timed out.')
 assert(run.phase=='interrupted' and not h.C.handAuthority and not h.C.handRunPlan,'natural pause failed')
 assert(not h.C.HandStore().seen[run.id].cancelled,'automatic pause used explicit cancellation/tombstone behavior')
 assert(h.C.handNotice=='Paused: companion discovery timed out.','natural pause reason changed')
end)

test('Stop cancels its trusted renewal but leaves a borrowed handshake alone',function()
 for _,borrowed in ipairs({false,true}) do
  local h=client(); local s=link(h,'Bob',false); s.phase='disabled'
  local packet
  if borrowed then packet=assert(h.C.LinkInvite(s,'700001',h.wall,h.now)); h.C.PeerQueuePacket(packet); h.C.SyncStore() end
  board(h,{[1]=normal('Bob'),[6]={kind='legacy',charName='Later',class='mage',role='rdps'}})
  h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn)
  local wait=assert(h.C.handAwaitLink,'fixture did not start renewal'); local run=h.C.HandStore().active
  local entry=wait.refresh['FixtureRealm;bob']; assert(entry and entry.status=='pending' and (entry.borrowed==true)==borrowed,'wrong renewal ownership')
  stop(h)
  assert(run.phase=='cancelled' and not h.C.handAwaitLink and not h.C.handAuthority and not h.C.handTransfer,'Stop kept renewal continuation')
  if borrowed then assert(s.phase=='waiting' and h.C.peerPending==packet,'Stop cancelled an unrelated borrowed handshake')
  else assert(s.phase=='disabled' and not h.C.peerPending and entry.status=='cancelled','Stop kept its own renewal invitation') end
  pump(h,100)
  for _,row in ipairs(h.sent) do assert(row.route~='SAY' and not h.C.HandParse(row.text),'renewal resumed a grant or hire after Stop') end
 end
end)

test('Stop after a zero-command player group cancels the waiting peer',function()
 local h=client(); link(h,'Bob',true)
 board(h,{[1]={kind='player',charName='Alice',class='warrior',role='tank'},[6]=normal('Bob'),[11]={kind='legacy',charName='Later',class='mage',role='rdps'}})
 h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn)
 local run=h.C.HandStore().active
 assert(run and run.step==2 and run.phase=='waiting' and not h.C.handRunPlan and table.getn(h.sent)==0,'fixture did not finish the empty local command step')
 stop(h); pump(h,100)
 assert(run.step==2 and run.phase=='cancelled' and table.getn(h.sent)==0 and not h.C.handAuthority,'zero-command Stop resumed the run')
end)

test('Stop discards a partially received handoff and its remaining packets',function()
 local h=client('Bob'); local s=link(h,'Alice',true); local g=grant(h)
 local tx=h.C.PeerNew('Alice','Bob','FixtureRealm'); tx.phase='linked'; tx.a=s.a; tx.b=s.b; tx.started=h.now; tx.deadline=h.now+60; tx.expires=s.expires
 local packets=assert(h.C.HandPackets(tx,assert(h.C.HandEncode(g)),'600001',h.wall,h.now))
 assert(table.getn(packets)>1,'fixture handoff was not fragmented')
 event(h,'CHAT_MSG_WHISPER',packets[1],'Alice'); assert(s.handInput and not s.handProposal,'fixture did not hold partial input')
 stop(h); assert(not s.handInput and not s.handProposal,'Stop retained partial handoff')
 for _,text in ipairs(packets) do event(h,'CHAT_MSG_WHISPER',text,'Alice') end
 h.C.HandTick(); pump(h,30)
 assert(not h.C.HandStore().active and not h.C.handAuthority and table.getn(h.sent)==0,'old fragmented transfer resumed after Stop')
end)

test('Stop retains Sort cancellation without hiring or changing the Hire plan',function()
 local h=client(); local main=h.env.ShirsRaidBuilderMainFrame
 local hire=h:preset(); local first=hire.entries[1]; local moves=0
 h:click(main.modeBtn)
 local p=h.C.ActivePreset(h.env.ShirsRaidBuilderDB,'sort')
 p.entries={}; for i=1,40 do p.entries[i]={kind='empty'} end
 p.entries[1]={kind='player',charName='Alice',class='warrior',role='tank'}
 h.env.GetNumRaidMembers=function() return 1 end
 h.env.GetRaidRosterInfo=function() return 'Alice',0,2,60,'Warrior' end
 h.env.IsRaidLeader=function() return 1 end
 h.env.SetRaidSubgroup=function() moves=moves+1 end
 h:click(main.sortBtn)
 assert(h.C.sortFrame and h.C.sortFrame.busy,'Sort fixture did not start')
 stop(h); pump(h,20)
 assert(not h.C.sortFrame.busy and not h.C.sortFrame.onDone and not h.C.sortFrame.scripts.OnUpdate and not h.C.sortWaiting,'Sort Stop retained work')
 assert(moves==0 and table.getn(h.sent)==0 and table.getn(h.addon)==0,'Sort Stop hired, whispered, discovered or moved a raid member')
 assert(hire.entries[1]==first and not h.C.HandStore().active,'Sort Stop changed Hire state')
end)

test('recovery guidance never points to removed execution controls',function()
 local f=assert(io.open('../addon/ShirsRaidBuilder/ShirsRaidBuilder.lua','r')); local source=f:read('*a'); f:close()
 for _,phrase in ipairs({'Cancel process','in Hire status','Cancel before a new Execute','cancel this process'}) do
  assert(not string.find(source,phrase,1,true),'obsolete recovery instruction: '..phrase)
 end
end)

test('current usage and recovery help name the retained main Stop',function()
 for _,path in ipairs({'../README.md','../addon/ShirsRaidBuilder/README.txt'}) do
  local f=assert(io.open(path,'r')); local text=f:read('*a'); f:close()
  assert(not string.find(text,'Cancel process',1,true),path..' directs recovery to a removed button')
  assert(string.find(text,'Stop on the main builder',1,true),path..' does not explain consolidated Stop')
 end
end)

test('a fresh nonce cannot revive a partial run stopped before its identity is known',function()
 local h=client('Bob'); local s=link(h,'Alice',true); local g=grant(h)
 local tx=h.C.PeerNew('Alice','Bob','FixtureRealm'); tx.phase='linked'; tx.a=s.a; tx.b=s.b; tx.started=h.now; tx.deadline=h.now+60; tx.expires=s.expires
 local packets=assert(h.C.HandPackets(tx,assert(h.C.HandEncode(g)),'600001',h.wall,h.now))
 event(h,'CHAT_MSG_WHISPER',packets[1],'Alice'); assert(s.handInput and not h.C.HandStore().active,'fixture did not hold partial unknown run')
 stop(h); local notice=h.C.handNotice
 receive(h,s,g,'600002'); h.C.HandTick(); pump(h,2)
 assert(not h.C.HandStore().active and not h.C.handAuthority and table.getn(h.sent)==0,'fresh nonce revived partial work after Stop')
 assert(h.C.handNotice==notice,'partial-run retry hid recovery status')
end)

test('partial Stop preserves plan offers and a renewed trusted link accepts a new run',function()
 local a,b=client('Alice'),client('Bob'); link(a,'Bob',true); local s=link(b,'Alice',true); local g=grant(b)
 local tx=b.C.PeerNew('Alice','Bob','FixtureRealm'); tx.phase='linked'; tx.a=s.a; tx.b=s.b; tx.started=b.now; tx.deadline=b.now+60; tx.expires=s.expires
 local packets=assert(b.C.HandPackets(tx,assert(b.C.HandEncode(g)),'600001',b.wall,b.now))
 event(b,'CHAT_MSG_WHISPER',packets[1],'Alice'); stop(b)
 assert(b.C.LinkKnown(b.env.ShirsRaidBuilderDB.peerLinks,'Bob','Alice','FixtureRealm'),'partial Stop revoked saved trust')
 assert(string.find(b.C.handNotice,'Refresh Synchronization',1,true),'partial Stop lost link recovery guidance')
 local wire=assert(b.C.PlanEncode({entries={[1]=normal('Bob')}},'hire','Unrelated offer'))
 for _,text in ipairs(assert(b.C.PlanPackets(tx,wire,'600005',b.wall,b.now))) do event(b,'CHAT_MSG_WHISPER',text,'Alice') end
 assert(s.planProposal and s.planProposal.plan.name=='Unrelated offer','partial Stop blocked unrelated plan sharing')
 local oldA,oldB=s.a,s.b
 local cursors={0,0}; local clients={a,b}
 b:click(b.env.ShirsRaidBuilderMainFrame.syncButton)
 for _=1,80 do
  for _,h in ipairs(clients) do
   h.now=h.now+0.25; h.wall=1800000000+math.floor(h.now-100)
   for _,w in ipairs(h.frames) do if w.scripts.OnUpdate and w:IsVisible() then h:fire(w,'OnUpdate',0.25) end end
  end
  for i,h in ipairs(clients) do
   while cursors[i]<table.getn(h.sent) do
    cursors[i]=cursors[i]+1; local row=h.sent[cursors[i]]; local other=i==1 and b or a
    if row.route=='WHISPER' and string.lower(row.target or '')==string.lower(other.name) then event(other,'CHAT_MSG_WHISPER',row.text,h.name) end
   end
  end
  local live=b.C.peerSessions['FixtureRealm;alice'].state
  if live.phase=='linked' and (live.a~=oldA or live.b~=oldB) then s=live; break end
 end
 assert(s.phase=='linked' and (s.a~=oldA or s.b~=oldB),'registered trusted-link renewal did not complete')
 g.id='1234567890123457'; g.expires=b.wall+7200
 receive(b,s,g,'600006'); b.C.HandTick()
 local count=0; for _,row in ipairs(b.sent) do if string.find(row.text,'^%.z addinvite Bob ') then count=count+1 end end
 assert(count==1 and b.C.handAuthority and b.C.HandStore().active.id==g.id,'partial Stop permanently blocked a new run after link renewal')
end)

assert(failed==0,failed..' Stop regression(s) failed')
print("Shir's Raid Builder stop tests: PASS ("..passed.." cases)")
