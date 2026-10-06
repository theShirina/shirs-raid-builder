-- Single-leader run authority on the real UI fixture, peer driver and whisper transport.
-- One leader Execute freezes the run; a trusted participant auto-runs only its granted
-- group and REPORTs to the leader; only the leader advances. Exact Lua 5.0.3.
local f=assert(io.open('test_individual_editor.lua','r')); local fixture=f:read('*a'); f:close()
local boundary=assert(string.find(fixture,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(fixture,1,boundary-1)..'\nreturn boot'))()
-- The same boot without opening the builder: a client that has only logged in.
local bareSource,opens=string.gsub(string.sub(fixture,1,boundary-1),"env%.SlashCmdList%.SHIRSRAIDBUILDER%('demo'%)","",1)
assert(opens==1,'fixture no longer opens the builder at boot')
local bareBoot=assert(loadstring(bareSource..'\nreturn boot'))()
local ids={alice='1111111111111111',bob='2222222222222222'}
local world,trace,at,parts,runs={},{},{},{},{}
local elapsed=0
local function log(line) table.insert(trace,line); table.insert(at,elapsed) end
local function snapshot(value)
 if type(value)~='table' then return type(value)..':'..tostring(value) end
 local t={}; for k,v in pairs(value) do table.insert(t,snapshot(k)..'='..snapshot(v)) end
 table.sort(t); return '{'..table.concat(t,',')..'}'
end
-- Reassemble each outgoing SRBHAND5 transfer and log its decoded run message. A short
-- message is rebuilt from the sender's own copy of the run; run.packets is its size.
local function record(h,text)
 local p=h.C.HandParse(text)
 if not p then return end
 local key=p.sender..';'..p.nonce
 if p.index==1 then parts[key]={} end
 local list=parts[key]
 if not list or p.index~=table.getn(list)+1 then parts[key]=nil; return end
 table.insert(list,p.data)
 if p.index<p.total then return end
 parts[key]=nil
 local wire=table.concat(list)
 local held=h.env.ShirsRaidBuilderDB.handoff and h.env.ShirsRaidBuilderDB.handoff.active
 local run=h.C.HandDecode(wire) or (h.C.HandExpand and h.C.HandExpand(wire,held))
 if not run then log(p.sender..' undecodable to '..p.target); return end
 run.packets=p.total
 table.insert(runs,run)
 local line=p.sender..' '..(run.kind or 'H5')..' '..run.step..' to '..p.target
 if run.kind=='GRANT' then line=line..' accounts '..table.concat(run.accounts,',') end
 log(line)
end
-- saved: the client's SavedVariables; bare: its builder is never opened.
local function client(name,base,saved,bare)
 local h=(bare and bareBoot or boot)(saved,name); h.name=name; h.base=base; h.now=base; h.wall=1800000000; h.queue={}; h.whispers={}
 h.env.GetTime=function() return h.now end; h.env.time=function() return h.wall end
 h.env.SendAddonMessage=function() end
 h.env.SendChatMessage=function(text,route,language,target)
  if route=='SAY' then
   if (string.find(text,'^%.z addlegacy ') or string.find(text,'^%.z addinvite ')) and text~='.z addlegacy list' and text~='.z addinvite list' then
    log(string.lower(name)..' hires '..text)
   end
   return
  end
  table.insert(h.whispers,{text=text,route=route,language=language,target=target})
  table.insert(h.queue,{text=text,target=target}); record(h,text)
 end
 if not bare then h.C.PeerOnBuilderOpen(); h.C.peerAutoAttempted=nil end
 h.env.ShirsRaidBuilderDB.syncAccountId=ids[string.lower(name)]
 table.insert(world,h)
 return h
end
-- Saved state after a completed link and account sync: remembered consent plus the
-- peer's opaque account claim. No live session exists; the run must renew one.
-- alts are further level-60 characters the peer's account snapshot lists.
local function trust(h,peer,alts)
 local db=h.env.ShirsRaidBuilderDB; local key='FixtureRealm;'..string.lower(peer); local seen=1799999400
 local s=h.C.PeerNew(h.name,peer,'FixtureRealm'); s.phase='linked'; assert(h.C.LinkSave(db.peerLinks,s,true))
 local listed={{name=peer,level=60,dungeonLicense='t1d',raidLicense='t2r',observed=seen}}
 for _,name in ipairs(alts or {}) do table.insert(listed,{name=name,level=60,dungeonLicense='t1d',raidLicense='t2r',observed=seen}) end
 db.peerSnapshots[key]={accountId=ids[string.lower(peer)],source=string.lower(peer),realm='FixtureRealm',received=seen,observed=seen,
  entries=listed,authoritative=false}
 h.C.LicenseRestoreSaved()
 assert(h.C.remoteLicenses[key] and h.C.remoteLicenses[key].accountId==ids[string.lower(peer)],'fixture account claim rejected')
end
local function deliver()
 for _,from in ipairs(world) do
  while table.getn(from.queue)>0 do
   local row=table.remove(from.queue,1)
   for _,to in ipairs(world) do
    if string.lower(to.name)==string.lower(row.target or '') then
     to.env.event='CHAT_MSG_WHISPER'; to.env.arg2=from.name
     for _,w in ipairs(to.frames) do
      if w.events.CHAT_MSG_WHISPER and w.scripts.OnEvent then to:fire(w,'OnEvent',row.text) end
     end
    end
   end
  end
 end
end
-- Both clients keep running; as in the client, only visible frames receive OnUpdate.
-- observe, when set, runs once per tick after whisper delivery.
local observe
local function pump(seconds)
 for i=1,seconds*4 do
  elapsed=elapsed+0.25
  for _,h in ipairs(world) do
   h.now=h.base+elapsed; h.wall=1800000000+math.floor(elapsed)
   for _,w in ipairs(h.frames) do
    if w.scripts.OnUpdate and w:IsVisible() then h:fire(w,'OnUpdate',0.25) end
   end
  end
  deliver()
  if observe then observe() end
 end
end
local a=client('Alice',100); local b=client('Bob',7000)
do -- Frozen run scope on the wire; progress is separate from the revision.
 local C=a.C
 local p={entries={[1]={kind='legacy',charName='First',class='mage',role='rdps'},[6]={kind='legacy',charName='Second',class='mage',role='rdps'}}}
 local h=assert(C.HandCreate(p,'Run','Alice','FixtureRealm',{'Alice','Bob'},'1234567890123456',1800000000))
 h.kind='GRANT'; h.accounts={'1111111111111111','2222222222222222'}; h.expires=1800007200
 local wire=assert(C.HandEncode(h)); local decoded=assert(C.HandDecode(wire))
 assert(decoded.kind=='GRANT' and decoded.accounts[2]==h.accounts[2],'run authority lost on wire')
 assert(C.HandRunScope(h)==C.HandRunScope(decoded),'scope drift')
 decoded.step=2; assert(C.HandRunScope(h)==C.HandRunScope(decoded),'progress changes scope')
 decoded.plan.entries[6].charName='Changed'; assert(C.HandRunScope(h)~=C.HandRunScope(decoded),'revision not bound')
end
trust(a,'Bob'); trust(b,'Alice')
local entries={[1]={kind='legacy',charName='First',class='mage',role='rdps'},
 [6]={kind='normal',account='Bob',class='mage',role='rdps',race='human',gender='female',tier='t2r',spec='frost'},
 [11]={kind='legacy',charName='Third',class='mage',role='rdps'}}
for i=1,40 do if not entries[i] then entries[i]={kind='empty'} end end
a:preset().entries=entries
-- Ordinary prepared board, no manual assignment: the normal row names Bob's hire-from
-- character; legacy-only groups belong to the initiator. No /srbhandoff. Stale saved
-- actors from the retired Group actors panel must never override board identity.
a:preset().groupActors={[1]='Mallory',[2]='Mallory',[3]='Mallory'}
b.env.ShirsRaidBuilderMainFrame:Hide() -- the participant runs in the background
local board=snapshot(b:preset())
a:click(a.env.ShirsRaidBuilderMainFrame.executeBtn)
assert(table.getn(trace)==1,'leader Execute did not start its own group; status: '..tostring(a.C.handNotice))
a:preset().entries[11]={kind='legacy',charName='Edited',class='mage',role='rdps'} -- later edits never reach the frozen run
pump(120)
local want=table.concat({
 'alice hires .z addlegacy "First" rdps',
 'alice GRANT 2 to bob accounts 1111111111111111,2222222222222222,1111111111111111',
 'bob hires .z addinvite Bob t2r mage rdps frost human female',
 'bob REPORT 2 to alice',
 'alice hires .z addlegacy "Third" rdps'},'\n')
local got=table.concat(trace,'\n')
assert(got==want,'single-leader run incomplete.\nExpected:\n'..want..'\nObserved:\n'..got
 ..'\nLeader status: '..tostring(a.C.handNotice)..'\nParticipant status: '..tostring(b.C.handNotice))
assert(at[3]-at[1]>=7.5 and at[5]-at[3]>=7.5,'a group started before the previous paced group finished')
assert(runs[1].id==runs[2].id and a.C.HandRunScope(runs[1])==a.C.HandRunScope(runs[2]),'REPORT not bound to the granted run revision')
assert(not b.env.ShirsRaidBuilderMainFrame:IsShown(),'remote run opened the participant builder')
assert(not (b.C.handFrame and b.C.handFrame:IsShown()),'remote run needed the participant process panel')
assert(snapshot(b:preset())==board,'remote run changed the participant plan')
assert(not a.C.handAuthority and not b.C.handAuthority,'completion retained execution permission')
for _,h in ipairs(world) do
 for _,row in ipairs(h.whispers) do
  local target=string.lower(row.target or '')
  assert(row.route=='WHISPER' and row.language==nil and (target=='alice' or target=='bob')
   and (h.C.LinkParse(row.text) or h.C.HandParse(row.text) or h.C.LicenseParse(row.text) or h.C.AccountParse(row.text) or h.C.RaidParse(row.text)),
   'run sent a non-protocol message: '..tostring(row.route)..' '..tostring(row.text))
 end
end
-- Stop while waiting for a remote report must revoke the leader's run too.
world={};trace={};at={};parts={};runs={};elapsed=0
local stopped=client('Alice',100);trust(stopped,'Bob')
stopped:preset().entries=entries
stopped:click(stopped.env.ShirsRaidBuilderMainFrame.executeBtn)
pump(12)
local current=stopped.env.ShirsRaidBuilderDB.handoff.active
assert(current.phase=='waiting' and stopped.C.handAuthority,'fixture did not reach waiting')
stopped:click(stopped:button(stopped.env.ShirsRaidBuilderMainFrame,'Stop'))
assert(not stopped.C.handAuthority and current.phase=='interrupted','Stop while awaiting remote group retained execution authority')
pump(100)
local hires=0;for _,line in ipairs(trace) do if string.find(line,' hires ',1,true) then hires=hires+1 end end
assert(hires==1,'Stop or timeout replayed hires')
-- Real receive path: saving an H5 board is not authority; unknown/wrong peers,
-- wrong account claims, expiry and replay may never trigger another hire.
local grant=assert(a.C.HandDecode(a.C.HandEncode(runs[1] or a.env.ShirsRaidBuilderDB.handoff.active)))
grant.step=2;grant.kind='GRANT';grant.expires=1800007200
local function receiver(known)
 world={};trace={};at={};parts={};runs={};elapsed=0
 local h=client('Bob',100)
 if known then trust(h,'Alice') end
 local s=h.C.PeerNew('Bob','Alice','FixtureRealm')
 s.phase='linked';s.a='100001';s.b='100002';s.started=100;s.deadline=160;s.expires=1800000060
 h.C.SyncSelect(s,true);h.C.peerState=s;h.C.SyncStore()
 return h,s
end
local function receiveGrant(h,s,wire,sender,nonce)
 local tx=h.C.PeerNew('Alice','Bob','FixtureRealm')
 tx.phase='linked';tx.a=s.a;tx.b=s.b;tx.started=s.started;tx.deadline=s.deadline;tx.expires=s.expires
 for _,text in ipairs(assert(h.C.HandPackets(tx,wire,nonce,h.wall,h.now))) do
  h.env.event='CHAT_MSG_WHISPER';h.env.arg2=sender;h:fire(h.C.peerDriver,'OnEvent',text)
 end
 h.C.HandTick()
end
for _,case in ipairs({'unknown','wrong-peer','wrong-account','expired','plain-board'}) do
 local h,s=receiver(case~='unknown');local g=assert(h.C.HandDecode(h.C.HandEncode(grant)))
 local sender='Alice'
 if case=='wrong-peer' then sender='Mallory'
 elseif case=='wrong-account' then g.accounts[2]='3333333333333333'
 elseif case=='expired' then g.expires=h.wall
 elseif case=='plain-board' then g.kind=nil;g.accounts=nil end
 receiveGrant(h,s,assert(h.C.HandEncode(g)),sender,'400001')
 assert(table.getn(trace)==0 and not h.C.handAuthority,'untrusted input executed: '..case)
end
local h,s=receiver(true)
receiveGrant(h,s,assert(h.C.HandEncode(grant)),'Alice','400001')
assert(table.getn(trace)==1 and h.C.handAuthority,'valid authorization failed')
receiveGrant(h,s,assert(h.C.HandEncode(grant)),'Alice','400002')
assert(table.getn(trace)==1,'fresh transport nonce replayed the authorized step')
h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Stop'))
assert(not h.C.handAuthority and h.env.ShirsRaidBuilderDB.handoff.active.phase=='interrupted','interrupted remote group retained authority')
receiveGrant(h,s,assert(h.C.HandEncode(grant)),'Alice','400003')
assert(table.getn(trace)==1,'interrupted authorization replayed a hire')
-- Offline link renewal expires visibly, without replaying the submitted leader group.
world={};trace={};at={};parts={};runs={};elapsed=0
local offline=client('Alice',100);trust(offline,'Bob')
offline:preset().entries=entries
offline:click(offline.env.ShirsRaidBuilderMainFrame.executeBtn);pump(100)
assert(not offline.C.handAuthority and offline.env.ShirsRaidBuilderDB.handoff.active.phase=='interrupted','offline renewal did not pause')
local count=0;for _,line in ipairs(trace) do if string.find(line,' hires ',1,true) then count=count+1 end end
assert(count==1,'failed renewal retried a submitted hire')
-- Stop must discard unsent grants, not only drop the local authority flag.
local pending=client('Alice',100);trust(pending,'Bob')
local ps=pending.C.PeerNew('Alice','Bob','FixtureRealm')
ps.phase='linked';ps.a='100001';ps.b='100002';ps.started=100;ps.deadline=160;ps.expires=1800000060
pending.C.SyncSelect(ps,true);pending.C.peerState=ps;pending.C.SyncStore()
local queued=assert(pending.C.HandDecode(pending.C.HandEncode(grant)));queued.phase='waiting'
pending.C.HandStore().active=queued;pending.C.handAuthority=pending.C.HandRunScope(queued)
pending.C.HandSendLocal();assert(ps.handOut,'fixture did not queue a grant')
pending:click(pending:button(pending.env.ShirsRaidBuilderMainFrame,'Stop'))
assert(not ps.handOut and not pending.C.peerPending,'Stop retained an unsent execution grant')
-- Mixed-account runs: each normal row's hire-from character resolves to the client whose
-- account lists it. This account's own characters (AccountReadLocal) run locally; a
-- trusted linked peer's snapshot characters run on that linked endpoint. The row's
-- account is the .z addinvite source and never changes. The current player's row is
-- only a board position, never an actor declaration.
local function characters(names)
 local out={}; for _,name in ipairs(names) do table.insert(out,{name=name,level=60,dungeonLicense='t1d',raidLicense='t2r'}) end
 return out
end
local function normal(account) return {kind='normal',account=account,class='mage',role='rdps',race='human',gender='female',tier='t2r',spec='frost'} end
local function mixed(board,own,peerAlts,peerOwn,seconds)
 world={};trace={};at={};parts={};runs={};elapsed=0
 local lead=client('Alice',100); local peer=client('Bob',7000)
 trust(lead,'Bob',peerAlts); trust(peer,'Alice')
 lead.C.AccountReadLocal(characters(own)); peer.C.AccountReadLocal(characters(peerOwn))
 local e={}; for i=1,40 do e[i]=board[i] or {kind='empty'} end
 lead:preset().entries=e
 peer.env.ShirsRaidBuilderMainFrame:Hide()
 lead:click(lead.env.ShirsRaidBuilderMainFrame.executeBtn); pump(seconds)
 return lead,peer
end
local function expect(case,lines,lead,peer)
 local wanted=table.concat(lines,'\n'); local seen=table.concat(trace,'\n')
 assert(seen==wanted,case..' run incomplete.\nExpected:\n'..wanted..'\nObserved:\n'..seen
  ..'\nLeader status: '..tostring(lead.C.handNotice)..'\nParticipant status: '..tostring(peer.C.handNotice))
end
local you={kind='player',charName='Alice',class='warrior',role='tank'}
local grantLine='alice GRANT 2 to bob accounts 1111111111111111,2222222222222222,1111111111111111'
-- Local own-account alt Alicia in a local -> Bob -> local plan.
local lead,peer=mixed({[1]=normal('Alicia'),[6]=normal('Bob'),[11]={kind='legacy',charName='Third',class='mage',role='rdps'},[12]=you},
 {'Alice','Alicia'},nil,{'Bob'},120)
expect('local alt',{'alice hires .z addinvite Alicia t2r mage rdps frost human female',grantLine,
 'bob hires .z addinvite Bob t2r mage rdps frost human female','bob REPORT 2 to alice','alice hires .z addlegacy "Third" rdps'},lead,peer)
assert(runs[1].steps[1].actor=='Alice' and runs[1].plan.entries[1].account=='Alicia','local alt changed actor or hire-from source')
assert(not peer.env.ShirsRaidBuilderMainFrame:IsShown() and not peer.C.handAuthority and not lead.C.handAuthority,'local alt run retained authority or opened the participant')
-- Bob's account alt Bobalt: listed in the trusted Bob snapshot and in Bob's own local
-- rows. No link to Bobalt exists; the grant goes to linked Bob with unchanged fields.
lead,peer=mixed({[1]={kind='legacy',charName='First',class='mage',role='rdps'},[6]=normal('Bobalt'),
 [11]={kind='legacy',charName='Third',class='mage',role='rdps'},[12]=you},{'Alice'},{'Bobalt'},{'Bob','Bobalt'},120)
assert(not lead.C.LinkKnown(lead.env.ShirsRaidBuilderDB.peerLinks,'Alice','Bobalt','FixtureRealm'),'fixture linked Bobalt directly')
expect('linked alt',{'alice hires .z addlegacy "First" rdps',grantLine,
 'bob hires .z addinvite Bobalt t2r mage rdps frost human female','bob REPORT 2 to alice','alice hires .z addlegacy "Third" rdps'},lead,peer)
assert(runs[1].steps[2].actor=='Bob' and runs[1].plan.entries[6].account=='Bobalt','linked alt changed actor or hire-from source')
for _,h in ipairs(world) do
 for _,row in ipairs(h.whispers) do
  local target=string.lower(row.target or '')
  assert(target=='alice' or target=='bob','linked alt run whispered an unlinked character: '..tostring(row.target))
 end
end
-- The receiver never infers ownership: without Bobalt in Bob's own rows it hires nothing
-- and the leader never advances past the granted group.
lead,peer=mixed({[1]={kind='legacy',charName='First',class='mage',role='rdps'},[6]=normal('Bobalt'),
 [11]={kind='legacy',charName='Third',class='mage',role='rdps'},[12]=you},{'Alice'},{'Bobalt'},{'Bob'},120)
for _,line in ipairs(trace) do
 assert(not string.find(line,'bob hires',1,true) and not string.find(line,'Third',1,true),'receiver hired or leader advanced on an unowned alt: '..line)
end
-- Unclear identity refuses before any command: a hire-from name no local row or
-- trusted snapshot lists. Visible, nothing sent. (Two accounts in one group is a valid
-- chunked run; see the two-entry cases at the end.)
for _,case in ipairs({{'unknown','Zed',{[1]={kind='legacy',charName='First',class='mage',role='rdps'},[2]=you,[6]=normal('Zed')}}}) do
 lead,peer=mixed(case[3],{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'},20)
 local active=lead.env.ShirsRaidBuilderDB.handoff and lead.env.ShirsRaidBuilderDB.handoff.active
 assert(table.getn(trace)==0 and not lead.C.handAuthority and not (active and active.phase~='cancelled'),case[1]..' identity sent commands or started a run: '..table.concat(trace,' | '))
 assert(string.find(tostring(lead.C.handNotice),case[2],1,true),case[1]..' identity refusal not visible: '..tostring(lead.C.handNotice))
end
-- Stop cannot recall a group already delivered to a running participant: Bob's second
-- paced hire still sends after the leader's Stop, but his REPORT no longer advances it.
local second=normal('Bob'); second.class='warlock'; second.spec='default'
lead,peer=mixed({[1]={kind='legacy',charName='First',class='mage',role='rdps'},[2]=you,[6]=normal('Bob'),[7]=second,
 [11]={kind='legacy',charName='Third',class='mage',role='rdps'}},{'Alice'},nil,{'Bob'},0)
local stopAt
for _=1,480 do
 pump(0.25)
 local started=0; for _,line in ipairs(trace) do if string.find(line,'bob hires',1,true) then started=started+1 end end
 if started==1 then stopAt=elapsed; break end
end
assert(stopAt,'participant never started its granted group: '..table.concat(trace,' | '))
local stoppedRun=lead.env.ShirsRaidBuilderDB.handoff.active
lead:click(lead:button(lead.env.ShirsRaidBuilderMainFrame,'Stop'))
assert(not lead.C.handAuthority and stoppedRun.phase=='interrupted','leader Stop retained authority')
pump(120)
expect('delivered group after Stop',{'alice hires .z addlegacy "First" rdps',grantLine,'bob hires .z addinvite Bob t2r mage rdps frost human female',
 'bob hires .z addinvite Bob t2r warlock rdps default human female','bob REPORT 2 to alice'},lead,peer)
assert(at[4]>stopAt,'second participant hire was not paced after the leader Stop')
assert(not lead.C.handAuthority and lead.env.ShirsRaidBuilderDB.handoff.active==stoppedRun and stoppedRun.phase=='interrupted' and stoppedRun.step==2,
 'REPORT after Stop advanced or re-armed the leader')
-- The first occupied group may belong to a linked account: one leader Execute grants it
-- first, the initiator stays origin, and the later local group follows Bob's REPORT.
lead,peer=mixed({[1]=normal('Bob'),[6]={kind='legacy',charName='Third',class='mage',role='rdps'},[7]=you},{'Alice'},nil,{'Bob'},120)
expect('first remote',{'alice GRANT 1 to bob accounts 2222222222222222,1111111111111111',
 'bob hires .z addinvite Bob t2r mage rdps frost human female','bob REPORT 1 to alice','alice hires .z addlegacy "Third" rdps'},lead,peer)
assert(runs[1].origin=='Alice' and runs[1].step==1 and runs[1].steps[1].actor=='Bob' and runs[1].steps[2].actor=='Alice',
 'first remote run reordered groups or changed origin')
assert(not peer.env.ShirsRaidBuilderMainFrame:IsShown() and not peer.C.handAuthority and not lead.C.handAuthority,
 'first remote run retained authority or opened the participant')
-- A group holding only the current player's board row has nothing to hire. It is passed
-- without a command, an interruption, another click or a completion confirmation.
lead,peer=mixed({[1]=you,[6]=normal('Bob'),[11]={kind='legacy',charName='Third',class='mage',role='rdps'}},{'Alice'},nil,{'Bob'},120)
expect('player-only first group',{grantLine,'bob hires .z addinvite Bob t2r mage rdps frost human female','bob REPORT 2 to alice',
 'alice hires .z addlegacy "Third" rdps'},lead,peer)
local order={}; for _,row in ipairs(runs[1].steps) do table.insert(order,row.group..'='..row.actor) end
assert(table.concat(order,',')=='1=Alice,2=Bob,3=Alice' and runs[1].origin=='Alice' and runs[1].step==2,'player-only run changed group order or actors: '..table.concat(order,','))
local finished=lead.env.ShirsRaidBuilderDB.handoff.active
assert(finished.phase=='done' and not lead.C.handAuthority and not peer.C.handAuthority,'player-only first group left the run '..tostring(finished.phase)..' or kept authority')
-- The same holds when the passive group comes last: the run finishes after Bob's REPORT.
lead,peer=mixed({[1]={kind='legacy',charName='First',class='mage',role='rdps'},[6]=normal('Bob'),[11]=you},{'Alice'},nil,{'Bob'},120)
expect('player-only final group',{'alice hires .z addlegacy "First" rdps',grantLine,'bob hires .z addinvite Bob t2r mage rdps frost human female',
 'bob REPORT 2 to alice'},lead,peer)
finished=lead.env.ShirsRaidBuilderDB.handoff.active
assert(finished.phase=='done' and not lead.C.handAuthority and not peer.C.handAuthority,'player-only final group left the run '..tostring(finished.phase)..' or kept authority')
-- Two normal entries in one raid group from one leader Execute. A same-account pair stays
-- one submitter's group; a mixed-account group runs as exact chunks in slot order: the
-- local alt's row here, then only the linked alt's row on Bob, then the next group here.
-- Each .z hire-from name stays the row's own; pacing holds across chunks and accounts.
do
 local function paired(first,second)
  return {[1]={kind='legacy',charName='First',class='mage',role='rdps'},[2]=you,[6]=normal(first),[7]=normal(second),
   [11]={kind='legacy',charName='Third',class='mage',role='rdps'}}
 end
 local function paced(case)
  local last
  for i,line in ipairs(trace) do
   if string.find(line,' hires ',1,true) then
    assert(not last or at[i]-last>=1.0,case..' hire paced under 1s: '..line)
    last=at[i]
   end
  end
 end
 local function invite(who,account) return who..' hires .z addinvite '..account..' t2r mage rdps frost human female' end
 local first,third='alice hires .z addlegacy "First" rdps','alice hires .z addlegacy "Third" rdps'
 lead,peer=mixed(paired('Alicia','Alice'),{'Alice','Alicia'},nil,{'Bob'},60)
 expect('same local account pair',{first,invite('alice','Alicia'),invite('alice','Alice'),third},lead,peer)
 paced('same local account pair')
 assert(not lead.C.handAuthority and not peer.C.handAuthority,'same local account pair kept authority')
 lead,peer=mixed(paired('Bob','Bobalt'),{'Alice'},{'Bobalt'},{'Bob','Bobalt'},120)
 expect('same linked account pair',{first,grantLine,invite('bob','Bob'),invite('bob','Bobalt'),'bob REPORT 2 to alice',third},lead,peer)
 paced('same linked account pair')
 assert(lead.env.ShirsRaidBuilderDB.handoff.active.phase=='done' and not lead.C.handAuthority and not peer.C.handAuthority,
  'same linked account pair did not finish or kept authority')
 lead,peer=mixed(paired('Alicia','Bobalt'),{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'},120)
 expect('mixed account pair',{first,invite('alice','Alicia'),'alice GRANT 3 to bob accounts '..table.concat({ids.alice,ids.alice,ids.bob,ids.alice},','),
  invite('bob','Bobalt'),'bob REPORT 3 to alice',third},lead,peer)
 paced('mixed account pair')
 local chunks={}; for _,row in ipairs(runs[1].steps) do table.insert(chunks,row.group..'='..row.actor) end
 assert(table.concat(chunks,',')=='1=Alice,2=Alice,2=Bob,3=Alice','mixed account pair chunks: '..table.concat(chunks,','))
 assert(runs[1].plan.entries[6].account=='Alicia' and runs[1].plan.entries[7].account=='Bobalt','mixed account pair changed a hire-from source')
 assert(lead.env.ShirsRaidBuilderDB.handoff.active.phase=='done' and not lead.C.handAuthority and not peer.C.handAuthority,
  'mixed account pair did not finish or kept authority')
 assert(not peer.env.ShirsRaidBuilderMainFrame:IsShown(),'mixed account pair opened the participant builder')
 for _,h in ipairs(world) do
  for _,row in ipairs(h.whispers) do
   local target=string.lower(row.target or '')
   assert(target=='alice' or target=='bob','mixed account pair whispered an unlinked character: '..tostring(row.target))
  end
 end
 -- Literally two normal entries and nothing else, in one raid group: same local account,
 -- same linked account, mixed accounts, and mixed with the linked account's row first.
 local function only(first,second) return {[1]=normal(first),[2]=normal(second)} end
 local function finished(case)
  local run=lead.env.ShirsRaidBuilderDB.handoff.active
  assert(run and run.phase=='done' and not lead.C.handAuthority and not peer.C.handAuthority,case..' did not finish or kept authority')
 end
 lead,peer=mixed(only('Alicia','Alice'),{'Alice','Alicia'},nil,{'Bob'},30)
 expect('two-only same local account',{invite('alice','Alicia'),invite('alice','Alice')},lead,peer)
 paced('two-only same local account')
 assert(not lead.C.handAuthority and not peer.C.handAuthority,'two-only same local account kept authority')
 lead,peer=mixed(only('Bob','Bobalt'),{'Alice'},{'Bobalt'},{'Bob','Bobalt'},120)
 expect('two-only same linked account',{'alice GRANT 1 to bob accounts '..ids.bob,invite('bob','Bob'),invite('bob','Bobalt'),
  'bob REPORT 1 to alice'},lead,peer)
 paced('two-only same linked account'); finished('two-only same linked account')
 lead,peer=mixed(only('Alicia','Bobalt'),{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'},120)
 expect('two-only mixed accounts',{invite('alice','Alicia'),'alice GRANT 2 to bob accounts '..ids.alice..','..ids.bob,
  invite('bob','Bobalt'),'bob REPORT 2 to alice'},lead,peer)
 paced('two-only mixed accounts'); finished('two-only mixed accounts')
 lead,peer=mixed(only('Bobalt','Alicia'),{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'},120)
 expect('two-only linked first',{'alice GRANT 1 to bob accounts '..ids.bob..','..ids.alice,invite('bob','Bobalt'),
  'bob REPORT 1 to alice',invite('alice','Alicia')},lead,peer)
 paced('two-only linked first'); finished('two-only linked first')
 -- Repeated back-and-forth from one leader Execute: twelve alternating chunks over six
 -- groups return to Bob six times, past eight groups and past the first 60s link, which
 -- must renew. Distinct alts keep each hire-from character within four hires, and each
 -- receiver's own rows list exactly the alts it is granted.
 local layout,wanted,claims={},{},{}
 for g=1,6 do
  layout[(g-1)*5+1]=normal(g<=3 and 'Alicia' or 'Aliana'); layout[(g-1)*5+2]=normal(g<=3 and 'Bobalt' or 'Bobina')
  table.insert(claims,ids.alice); table.insert(claims,ids.bob)
 end
 for g=1,6 do
  table.insert(wanted,invite('alice',g<=3 and 'Alicia' or 'Aliana'))
  table.insert(wanted,'alice GRANT '..(2*g)..' to bob accounts '..table.concat(claims,','))
  table.insert(wanted,invite('bob',g<=3 and 'Bobalt' or 'Bobina'))
  table.insert(wanted,'bob REPORT '..(2*g)..' to alice')
 end
 lead,peer=mixed(layout,{'Alice','Alicia','Aliana'},{'Bobalt','Bobina'},{'Bob','Bobalt','Bobina'},0)
 local saved=snapshot(peer:preset())
 for _=1,120 do
  pump(4)
  local run=lead.env.ShirsRaidBuilderDB.handoff.active
  if run and run.phase=='done' and not peer.C.handAuthority then break end
 end
 expect('repeated return',wanted,lead,peer)
 paced('repeated return'); finished('repeated return')
 assert(at[table.getn(at)]-at[1]>60,'repeated run fit inside the first link')
 local invites=0
 for _,h in ipairs(world) do
  for _,row in ipairs(h.whispers) do
   local p=h.C.LinkParse(row.text)
   if p and p.kind=='INVITE' then invites=invites+1 end
   local target=string.lower(row.target or '')
   assert(target=='alice' or target=='bob','repeated run whispered an unlinked character: '..tostring(row.target))
  end
 end
 assert(invites>=2,'repeated run never renewed its trusted link')
 assert(snapshot(peer:preset())==saved and not peer.env.ShirsRaidBuilderMainFrame:IsShown()
  and not (peer.C.handFrame and peer.C.handFrame:IsShown()),'repeated run changed the receiver plan or opened its UI')
 -- A receiver that cannot run its granted chunk (its own rows lack the hire-from alt)
 -- refuses visibly, and the leader learns promptly instead of waiting out the report
 -- deadline: the run pauses, neither side keeps authority, and nothing more is hired.
 lead,peer=mixed(only('Alicia','Bobalt'),{'Alice','Alicia'},{'Bobalt'},{'Bob'},60)
 for _,line in ipairs(trace) do assert(not string.find(line,'bob hires',1,true),'receiver hired an unowned alt: '..line) end
 assert(string.find(tostring(peer.C.handNotice),'Paused',1,true) and not peer.C.handAuthority,'receiver refusal not visible: '..tostring(peer.C.handNotice))
 local paused=lead.env.ShirsRaidBuilderDB.handoff.active
 assert(paused and paused.phase=='interrupted' and not lead.C.handAuthority and string.find(tostring(lead.C.handNotice),'Bob',1,true),
  'leader did not learn the refusal within 60s: phase '..tostring(paused and paused.phase)..', leader authority '
  ..tostring(lead.C.handAuthority~=nil)..', leader notice: '..tostring(lead.C.handNotice))
 -- Neighbouring boundaries. Each scenario starts fresh clients; failures are collected so
 -- one run reports every one of them.
 local failed={}
 local function scenario(name,fn)
  local ok,err=pcall(fn)
  if not ok then table.insert(failed,name..': '..tostring(err)) end
 end
 -- A group over the four-hire limit (five normal hires from one hire-from character) is
 -- refused twice, independently. The leader's Execute preflight blocks the board before any
 -- hire, grant or authority. A receiver handed an otherwise valid, fully scoped GRANT for
 -- it (Bob owns Bobalt) refuses like a missing alt: no hire, no retained authority, a
 -- visible pause and one PAUSE bound to exactly the granted run step.
 scenario('over-limit granted group',function()
  local five={}; for i=1,5 do five[i]=normal('Bobalt') end
  lead,peer=mixed(five,{'Alice'},{'Bobalt'},{'Bob','Bobalt'},10)
  local blocked=lead.env.ShirsRaidBuilderDB.handoff and lead.env.ShirsRaidBuilderDB.handoff.active
  assert(table.getn(trace)==0 and table.getn(lead.whispers)==0 and not lead.C.handAuthority and not peer.C.handAuthority
   and not blocked and string.find(tostring(lead.C.handNotice),'Bobalt',1,true),
   'leader preflight did not block the over-limit group: '..table.concat(trace,' | ')..'; '..tostring(lead.C.handNotice))
  local h,s=receiver(true)
  h.C.AccountReadLocal(characters({'Bob','Bobalt'})); h.env.ShirsRaidBuilderMainFrame:Hide()
  local board={}; for i=1,5 do board[i]=normal('Bobalt') end
  local g=assert(h.C.HandCreate({entries=board},'Run','Alice','FixtureRealm',{'Bob'},'1234567890123471',1800000000,{},
   {bobalt={endpoint='Bob',accountId=ids.bob}},true),'five-Bobalt grant fixture refused')
  g.kind='GRANT';g.accounts={ids.bob};g.expires=1800007200
  receiveGrant(h,s,assert(h.C.HandEncode(g)),'Alice','400001')
  pump(10)
  assert(table.getn(trace)==1 and trace[1]=='bob PAUSE 1 to alice','receiver hired or did not answer one PAUSE: '..table.concat(trace,' | '))
  local mine=h.env.ShirsRaidBuilderDB.handoff.active
  assert(mine.step==1 and mine.phase=='interrupted' and not h.C.handAuthority and string.find(tostring(h.C.handNotice),'Paused',1,true)
   and string.find(tostring(h.C.handNotice),'Bobalt',1,true),'receiver kept authority or hid its refusal: '..tostring(mine.phase)..', '..tostring(h.C.handNotice))
  assert(table.getn(runs)==1 and runs[1].kind=='PAUSE' and runs[1].step==g.step and h.C.HandRunScope(runs[1])==h.C.HandRunScope(g),
   'PAUSE not bound to the granted run step')
 end)
 -- Receive guard: a restored plain H5 run has no account claims and no run
 -- authority. A REPORT for its waiting step over a live trusted session is rejected without
 -- a script error; the run neither advances nor gains authority, and the input is consumed.
 scenario('REPORT against a restored plain run',function()
  world={};trace={};at={};parts={};runs={};elapsed=0
  local h=client('Alice',100);trust(h,'Bob')
  local plain=assert(h.C.HandCreate({entries={[1]={kind='legacy',charName='First',class='mage',role='rdps'},[6]=normal('Bob')}},
   'Plain','Alice','FixtureRealm',{'Alice','Bob'},'1234567890123470',1800000000))
  plain.step=2;plain.phase='waiting'
  h.C.HandStore().active=plain;h.C.handRestored=nil
  local old=h.C.HandStore().active
  assert(old and old~=plain and not old.kind and not old.accounts and old.phase=='waiting' and old.step==2 and not h.C.handAuthority,
   'fixture did not restore a plain waiting run')
  local live=h.C.PeerNew('Alice','Bob','FixtureRealm')
  live.phase='linked';live.a='100001';live.b='100002';live.started=100;live.deadline=160;live.expires=1800000060
  h.C.SyncSelect(live,true);h.C.peerState=live;h.C.SyncStore()
  local r=assert(h.C.HandDecode(assert(h.C.HandEncode(old))));r.kind='REPORT';r.accounts={ids.alice,ids.bob}
  local tx=h.C.PeerNew('Bob','Alice','FixtureRealm')
  tx.phase='linked';tx.a=live.a;tx.b=live.b;tx.started=live.started;tx.deadline=live.deadline;tx.expires=live.expires
  for _,text in ipairs(assert(h.C.HandPackets(tx,assert(h.C.HandEncode(r)),'600001',h.wall,h.now))) do
   h.env.event='CHAT_MSG_WHISPER';h.env.arg2='Bob';h:fire(h.C.peerDriver,'OnEvent',text)
  end
  assert(live.handProposal,'fixture REPORT was not received on the live session')
  local ok,err=pcall(pump,1)
  assert(ok,'REPORT against a restored plain run raised: '..tostring(err))
  assert(h.C.HandStore().active==old and old.step==2 and old.phase=='waiting' and not old.kind and not h.C.handAuthority
   and not live.handProposal and table.getn(trace)==0,'REPORT moved, authorized or left pending a restored plain run')
 end)
 -- A later return chunk refuses the same way: Bob runs his first chunk, the leader its next
 -- one, then Bob, whose own rows lack Bobina, pauses step 4 without hiring.
 scenario('later return chunk refusal',function()
  lead,peer=mixed({[1]=normal('Alicia'),[2]=normal('Bobalt'),[6]=normal('Aliana'),[7]=normal('Bobina')},
   {'Alice','Alicia','Aliana'},{'Bobalt','Bobina'},{'Bob','Bobalt'},0)
  local run=lead.env.ShirsRaidBuilderDB.handoff.active
  for _=1,60 do pump(4); if run.phase=='interrupted' and not peer.C.handTransfer then break end end
  local claims=table.concat({ids.alice,ids.bob,ids.alice,ids.bob},',')
  expect('later return chunk refusal',{invite('alice','Alicia'),'alice GRANT 2 to bob accounts '..claims,invite('bob','Bobalt'),
   'bob REPORT 2 to alice',invite('alice','Aliana'),'alice GRANT 4 to bob accounts '..claims,'bob PAUSE 4 to alice'},lead,peer)
  paced('later return chunk refusal')
  assert(run.step==4 and not lead.C.handAuthority and string.find(tostring(lead.C.handNotice),'Bob',1,true),
   'leader did not visibly pause the refused return chunk: '..tostring(lead.C.handNotice))
  local mine=peer.env.ShirsRaidBuilderDB.handoff.active
  assert(mine.step==4 and mine.phase=='interrupted' and not peer.C.handAuthority and string.find(tostring(peer.C.handNotice),'Paused',1,true),
   'receiver did not visibly pause its return chunk: '..tostring(peer.C.handNotice))
  assert(lead.C.HandRunScope(runs[table.getn(runs)])==lead.C.HandRunScope(runs[1]),'return-chunk PAUSE not bound to the run')
 end)
 -- The missing-alt refusal, up to the moment its PAUSE transfer is queued on Bob.
 local function refusing()
  lead,peer=mixed(only('Alicia','Bobalt'),{'Alice','Alicia'},{'Bobalt'},{'Bob'},0)
  for _=1,240 do
   pump(0.25)
   local out=peer.C.handTransfer
   if out and out.kind=='PAUSE' then return out end
  end
  error('receiver never queued its PAUSE: '..table.concat(trace,' | '))
 end
 -- Local Stop on the refusing receiver discards the unsent PAUSE and creates no new one.
 -- The partial transfer never pauses the leader; its finite report deadline then
 -- interrupts it visibly, without a second grant or any further hire.
 scenario('Stop during a pending PAUSE',function()
  local out=refusing()
  assert(out.progress.sent<out.progress.total,'PAUSE completed before Stop')
  peer.env.SlashCmdList.SHIRSRAIDBUILDERHANDOFF()
  local sent=table.getn(peer.whispers)
  peer:click(peer:button(peer.C.handFrame,'Stop execution'))
  assert(not peer.C.handTransfer and not peer.C.handAuthority and not peer.C.HandParse(peer.C.peerPending),'Stop kept the PAUSE transfer or authority')
  for _,session in pairs(peer.C.peerSessions) do assert(not session.state.handOut and not peer.C.HandParse(session.pending),'Stop kept unsent PAUSE packets') end
  local run=lead.env.ShirsRaidBuilderDB.handoff.active
  pump(60)
  assert(table.getn(peer.whispers)==sent,'Stop let the PAUSE or a new one through')
  assert(run.phase=='waiting' and run.step==2 and lead.C.handAuthority,'a discarded PAUSE paused the leader')
  for _=1,180 do pump(4); if run.phase~='waiting' then break end end
  assert(run.phase=='interrupted' and run.step==2 and not lead.C.handAuthority and string.find(tostring(lead.C.handNotice),'timed out',1,true),
   'report deadline did not visibly interrupt the leader: '..tostring(run.phase)..', '..tostring(lead.C.handNotice))
  expect('Stop during a pending PAUSE',{invite('alice','Alicia'),'alice GRANT 2 to bob accounts '..ids.alice..','..ids.bob},lead,peer)
 end)
 -- Cancel on the refusing receiver discards the unsent PAUSE the same way.
 scenario('Cancel during a pending PAUSE',function()
  refusing()
  peer.env.SlashCmdList.SHIRSRAIDBUILDERHANDOFF()
  local sent=table.getn(peer.whispers)
  peer:click(peer:button(peer.C.handFrame,'Cancel process'))
  assert(peer.env.ShirsRaidBuilderDB.handoff.active.phase=='cancelled' and not peer.C.handTransfer and not peer.C.handAuthority
   and not peer.C.HandParse(peer.C.peerPending),'Cancel kept the PAUSE transfer or authority')
  for _,session in pairs(peer.C.peerSessions) do assert(not session.state.handOut and not peer.C.HandParse(session.pending),'Cancel kept unsent PAUSE packets') end
  pump(30)
  local run=lead.env.ShirsRaidBuilderDB.handoff.active
  assert(table.getn(peer.whispers)==sent and run.phase=='waiting' and lead.C.handAuthority,'Cancel let the PAUSE or a new one through')
 end)
 -- Real receive: a stale-step or wrong-claim PAUSE on Bob's live session, or any PAUSE from
 -- an unlinked character, never pauses a valid waiting run; the run then finishes normally.
 scenario('mismatched PAUSE',function()
  lead,peer=mixed(only('Alicia','Bobalt'),{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'},0)
  for _=1,240 do pump(0.25); if string.find(trace[table.getn(trace)] or '','bob hires',1,true) then break end end
  local run=lead.env.ShirsRaidBuilderDB.handoff.active
  assert(run.phase=='waiting' and run.step==2 and lead.C.handAuthority,'fixture did not reach the granted step')
  local live=lead.C.peerSessions['FixtureRealm;bob'].state
  local function inject(sender,nonce,edit)
   local r=assert(lead.C.HandDecode(lead.C.HandEncode(runs[1]))); r.kind='PAUSE'; edit(r)
   local tx=lead.C.PeerNew(sender,'Alice','FixtureRealm')
   tx.phase='linked';tx.a=live.a;tx.b=live.b;tx.started=lead.now;tx.deadline=lead.now+60;tx.expires=live.expires
   for _,text in ipairs(assert(lead.C.HandPackets(tx,assert(lead.C.HandEncode(r)),nonce,lead.wall,lead.now))) do
    lead.env.event='CHAT_MSG_WHISPER';lead.env.arg2=sender;lead:fire(lead.C.peerDriver,'OnEvent',text)
   end
   pump(0.25)
   assert(run.phase=='waiting' and run.step==2 and lead.C.handAuthority,'mismatched PAUSE paused or moved the run: '..nonce)
  end
  inject('Bob','700001',function(r) r.step=1 end)
  assert(string.find(tostring(lead.C.handNotice),'rejected',1,true),'stale PAUSE rejection not visible: '..tostring(lead.C.handNotice))
  inject('Bob','700002',function(r) r.accounts[2]='3333333333333333' end)
  inject('Mallory','700003',function() end)
  for _=1,30 do pump(4); if run.phase=='done' then break end end
  expect('mismatched PAUSE',{invite('alice','Alicia'),'alice GRANT 2 to bob accounts '..ids.alice..','..ids.bob,invite('bob','Bobalt'),
   'bob REPORT 2 to alice'},lead,peer)
  paced('mismatched PAUSE'); finished('mismatched PAUSE')
 end)
 -- The four-hire limit holds for the whole frozen plan, not per chunk: five Bobalt rows in
 -- chunks of at most two, between safe local Alicia/Aliana rows, refuse at the leader's
 -- Execute before any hire, grant or execution authority.
 scenario('over-limit across chunks',function()
  lead,peer=mixed({[1]=normal('Alicia'),[2]=normal('Bobalt'),[3]=normal('Bobalt'),[6]=normal('Aliana'),[7]=normal('Bobalt'),
   [8]=normal('Bobalt'),[11]=normal('Alicia'),[12]=normal('Bobalt')},{'Alice','Alicia','Aliana'},{'Bobalt'},{'Bob','Bobalt'},150)
  local bobalt=0; for _,line in ipairs(trace) do if string.find(line,'addinvite Bobalt ',1,true) then bobalt=bobalt+1 end end
  local active=lead.env.ShirsRaidBuilderDB.handoff and lead.env.ShirsRaidBuilderDB.handoff.active
  assert(table.getn(trace)==0 and table.getn(lead.whispers)==0 and not lead.C.handAuthority and not peer.C.handAuthority
   and not (active and active.phase~='cancelled'),'over-limit plan spent or started ('..bobalt..' Bobalt hires): '..table.concat(trace,' | '))
  assert(string.find(tostring(lead.C.handNotice),'Bobalt',1,true) and string.find(tostring(lead.C.handNotice),'more than four',1,true),
   'whole-plan over-limit refusal not visible: '..tostring(lead.C.handNotice))
 end)
 assert(table.getn(failed)==0,table.getn(failed)..' neighbouring run boundary scenario(s) failed:\n'..table.concat(failed,'\n\n'))
end
-- Coverage for cross-account handoffs: the literal five-slot group, saved
-- endpoints of one account, and legacy rows, on the same boot, Execute button, whisper
-- driver and visible-only OnUpdate transport. Each scenario prints its trace: hires,
-- protocol messages, companion whispers and each client's run step/phase changes ('.').
-- Microbot server replies are SYNTHETIC: queued per client and delivered on the next tick
-- as CHAT_MSG_ADDON from nexus, the existing fixture contract. They prove client logic
-- only, never server acceptance.
do
 local failed,states={},{}
 local function scenario(name,fn)
  local ok,err=pcall(fn)
  if not ok then table.insert(failed,name..': '..tostring(err)) end
 end
 -- SYNTHETIC shared raid, when set: both players and every companion. A hire adds its
 -- companion one second later (a legacy hire its -lite member); each join then delivers
 -- PARTY_MEMBERS_CHANGED and RAID_ROSTER_UPDATE through every client's registered handlers.
 local raid
 -- Queue position read from the production executeFrame callback's private upvalues
 -- (tests only): executing, executeIndex and executeQueue.
 local queued
 local function queueOf(h)
  if not h.queueFn then
   for _,w in ipairs(h.frames) do
    local fn,i=w.scripts.OnUpdate,1
    while fn and not h.queueFn do
     local name=debug.getupvalue(fn,i)
     if not name then break end
     if name=='executeIndex' then h.queueFn=fn end
     i=i+1
    end
   end
  end
  if not h.queueFn then return 'idle' end
  local values,i={},1
  while true do
   local name,value=debug.getupvalue(h.queueFn,i)
   if not name then break end
   values[name]=value; i=i+1
  end
  if not values.executing then return 'idle' end
  return values.executeIndex..'/'..table.getn(values.executeQueue or {})
 end
 observe=function()
  if raid then
   local joined,k=0,1
   while raid.pending[k] do
    if raid.pending[k].at<=elapsed then table.insert(raid.members,table.remove(raid.pending,k)); joined=joined+1 else k=k+1 end
   end
   if joined>0 then
    for _,h in ipairs(world) do
     for _,ev in ipairs({'PARTY_MEMBERS_CHANGED','RAID_ROSTER_UPDATE'}) do
      h.env.event=ev
      for _,w in ipairs(h.frames) do if w.events[ev] and w.scripts.OnEvent then h:fire(w,'OnEvent') end end
     end
    end
    table.insert(states,{t=elapsed,text='raid '..table.getn(raid.members)..' members: roster events to every client'})
   end
  end
  for _,h in ipairs(world) do
   if queued then
    local q=queueOf(h)
    if h.lastQueue~=q then table.insert(states,{t=elapsed,text=string.lower(h.name)..' queue '..(h.lastQueue or 'idle')..' -> '..q}); h.lastQueue=q end
    -- Ticks spent with GRINFO ready, group commands not yet expanded and a GRINFO name
    -- not yet visible in the raid roster: the production name wait.
    if raid and h.queueFn then
     local v,u={},1
     while true do local name,value=debug.getupvalue(h.queueFn,u); if not name then break end; v[name]=value; u=u+1 end
     if v.executing and v.executeGrinfoReady and not v.executeGrinfoExpanded then
      local seen={}
      for _,m in ipairs(raid.members) do seen[m.name]=true end
      for _,c in ipairs(v.executeCompanionList or {}) do
       if c.name and not seen[c.name] then h.nameWaits=(h.nameWaits or 0)+1; break end
      end
     end
    end
   end
   while h.server and table.getn(h.server)>0 do
    local text=table.remove(h.server,1)
    h.env.event='CHAT_MSG_ADDON'; h.env.arg2='nexus'
    for _,w in ipairs(h.frames) do
     if w.events.CHAT_MSG_ADDON and w.scripts.OnEvent then h:fire(w,'OnEvent',text) end
    end
   end
  end
  for i,h in ipairs(world) do
   local db=h.env.ShirsRaidBuilderDB
   local run=db.handoff and db.handoff.active
   local now=run and (run.step..'/'..table.getn(run.steps)..' '..run.phase) or 'none'
   if h.lastRun~=now then
    table.insert(states,{t=elapsed,text=string.lower(h.name)..' run '..(h.lastRun or 'none')..' -> '..now})
    h.lastRun=now
   end
   if i>1 and h.env.ShirsRaidBuilderMainFrame:IsShown() then h.opened=true end
  end
 end
 -- Printed with account claims shortened to A and B and the fixed ' t2r'/' human female'
 -- invite fields dropped; assertions use the full values.
 local function show(name)
  local rows={}
  for i,line in ipairs(trace) do table.insert(rows,{t=at[i],o=i,text=line}) end
  for i,s in ipairs(states) do
   if not string.find(s.text,' run none -> none',1,true) then table.insert(rows,{t=s.t,o=100000+i,text='. '..s.text}) end
  end
  table.sort(rows,function(x,y) if x.t~=y.t then return x.t<y.t end return x.o<y.o end)
  print('TRACE '..name)
  for _,r in ipairs(rows) do
   local text=string.gsub(string.gsub(r.text,ids.alice,'A'),ids.bob,'B')
   text=string.gsub(string.gsub(text,' t2r ',' '),' human female$','')
   print(string.format('%7.2f %s',r.t,text))
  end
  for _,h in ipairs(world) do
   for _,m in ipairs(h.messages) do
    if string.find(m,'Skipped',1,true) then print('   chat '..string.lower(h.name)..': '..string.gsub(m,'^.-|r ','')) end
   end
  end
 end
 -- Exact trace; on failure only the first differing line and both statuses (the full
 -- trace is already printed by show).
 local function match(name,lines,lead,peer)
  for i=1,math.max(table.getn(lines),table.getn(trace)) do
   if lines[i]~=trace[i] then
    error(name..': line '..i..' expected ['..tostring(lines[i])..'] observed ['..tostring(trace[i])..']; leader: '
     ..tostring(lead.C.handNotice)..'; participant: '..tostring(peer and peer.C.handNotice))
   end
  end
 end
 -- Synthetic server for one client. '.z addinvite list' answers with rows. With roster, a
 -- hire adds a companion to the hirer's own party (a legacy hire adds its -lite member) and
 -- GRINFO:ALL:FULL lists the party's hired companions as name:race:class:role:tier:owner,
 -- owner being the hire-from character. No nods are sent; the queue waits out its timeout.
 local function serve(h,rows,roster)
  h.server={}; h.party={}
  local send=h.env.SendChatMessage
  h.env.SendChatMessage=function(text,route,language,target)
   if route=='SAY' and text=='.z addinvite list' then
    if rows then table.insert(h.server,'[nexus] ACINFO:INVITE:LIST '..rows) end
    return
   end
   if route=='SAY' and roster then
    local _,_,from,class,role=string.find(text,'^%.z addinvite (%a+) %w+ (%a+) (%a+) ')
    if from then table.insert(h.party,{name=h.name..'comp'..string.char(97+table.getn(h.party)),class=class,role=role,owner=from}) end
    local _,_,real=string.find(text,'^%.z addlegacy "(%a+)"')
    if real then table.insert(h.party,{name=h.C.NormalizeLegacyName(real)}) end
   elseif route=='WHISPER' and not (h.C.LinkParse(text) or h.C.HandParse(text) or h.C.LicenseParse(text) or h.C.AccountParse(text) or h.C.RaidParse(text)) then
    log(string.lower(h.name)..' whispers '..tostring(target)..': '..text)
   end
   return send(text,route,language,target)
  end
  if not roster then return end
  h.env.SendAddonMessage=function(prefix,text)
   if prefix~='nexus' or text~='GRINFO:ALL:FULL' then return end
   local listed={}
   for _,c in ipairs(h.party) do
    if c.owner then table.insert(listed,c.name..':Human:'..c.class..':'..c.role..':Uncommon:'..c.owner) end
   end
   table.insert(h.server,'[nexus] GRINFO:ALL:FULL '..table.concat(listed,' '))
  end
  h.env.GetNumPartyMembers=function() return table.getn(h.party) end
  h.env.UnitName=function(unit)
   if unit=='player' then return h.name end
   local _,_,n=string.find(tostring(unit),'^party(%d+)$')
   local c=n and h.party[tonumber(n)]
   return c and c.name
  end
 end
 local function hire(account,class,role,spec)
  local r=normal(account); r.class=class; r.role=role; r.spec=spec; return r
 end
 local function invite(account,class,role,spec) return '.z addinvite '..account..' t2r '..class..' '..role..' '..spec..' human female' end
 -- Raid group g as the literal sequence: hire-from x in slots 1-2, y in 3, z in 4-5.
 local five={{'mage','rdps','frost'},{'warlock','rdps','default'},{'priest','healer','default'},{'priest','rdps','default'},{'mage','rdps','arcane'}}
 local function literal(board,g,x,y,z)
  local from={x,x,y,z,z}
  for i=1,5 do local s=five[i]; board[(g-1)*5+i]=hire(from[i],s[1],s[2],s[3]) end
  return board
 end
 -- The exact trace one leader Execute must produce: per step {actor,first,last}, or {actor}
 -- for a commands step (no hires). A remote batch, one actor's steps in a row, opens with
 -- its GRANT and ends with one REPORT for its last step; each step lists its hires in slot
 -- order with unchanged sources, then its extra lines.
 local function expected(board,steps,extra)
  local out,claims={},{}
  for _,s in ipairs(steps) do table.insert(claims,ids[s[1]]) end
  for k,s in ipairs(steps) do
   local opens=k==1 or steps[k-1][1]~=s[1]
   local closes=k==table.getn(steps) or steps[k+1][1]~=s[1]
   if s[1]~='alice' and opens then table.insert(out,'alice GRANT '..k..' to '..s[1]..' accounts '..table.concat(claims,',')) end
   for i=s[2] or 1,s[3] or 0 do
    local e=board[i]
    if e and e.kind=='normal' then table.insert(out,s[1]..' hires '..invite(e.account,e.class,e.role,e.spec)) end
    if e and e.kind=='legacy' then table.insert(out,s[1]..' hires .z addlegacy "'..e.charName..'" '..e.role) end
   end
   for _,line in ipairs(extra and extra[k] or {}) do table.insert(out,line) end
   if s[1]~='alice' and closes then table.insert(out,s[1]..' REPORT '..k..' to alice') end
  end
  return out
 end
 local function shape(run)
  local out={}
  for _,s in ipairs(run.steps) do table.insert(out,s.group..'='..s.actor..(s.first and ('@'..s.first..'-'..s.last) or '')) end
  return table.concat(out,',')
 end
 local function pacing(name)
  local last
  for i,line in ipairs(trace) do
   if string.find(line,' hires ',1,true) then
    assert(not last or at[i]-last>=1.0,name..': hire paced under 1s: '..line)
    last=at[i]
   end
  end
 end
 -- Every decoded GRANT/REPORT belongs to the first one's run, revision and claims.
 local function bound(name)
  for _,r in ipairs(runs) do
   assert(r.id==runs[1].id and world[1].C.HandRunScope(r)==world[1].C.HandRunScope(runs[1]),name..': '..tostring(r.kind)..' '..tostring(r.step)..' left the run')
  end
 end
 -- Completion, no retained authority or transfer, frozen hire-from sources, and a
 -- participant that ran only the leader's grant: no builder, status panel or Execute.
 local function settled(name,lead,peer,board)
  local run=lead.env.ShirsRaidBuilderDB.handoff.active
  assert(run.phase=='done' and not lead.C.handAuthority and not peer.C.handAuthority and not lead.C.handTransfer and not peer.C.handTransfer,
   name..': run '..tostring(run.phase)..' or authority kept; leader: '..tostring(lead.C.handNotice)..'; participant: '..tostring(peer.C.handNotice))
  assert(not peer.opened and not (peer.C.handFrame and peer.C.handFrame:IsShown()),name..': participant builder or status panel opened')
  local mine=peer.env.ShirsRaidBuilderDB.handoff.active
  assert(mine and mine.kind=='GRANT' and mine.source=='alice' and mine.id==run.id,name..': participant run did not come from the leader grant')
  for i,e in pairs(board) do
   if e.kind=='normal' then assert(run.plan.entries[i].account==e.account,name..': hire-from changed in slot '..i) end
  end
 end
 local function start(board,own,peerAlts,peerOwn)
  world={};trace={};at={};parts={};runs={};elapsed=0;states={}
  local lead=client('Alice',100); local peer=client('Bob',7000)
  trust(lead,'Bob',peerAlts); trust(peer,'Alice')
  lead.C.AccountReadLocal(characters(own)); peer.C.AccountReadLocal(characters(peerOwn))
  local e={}; for i=1,40 do e[i]=board[i] or {kind='empty'} end
  lead:preset().entries=e
  peer.env.ShirsRaidBuilderMainFrame:Hide()
  return lead,peer
 end
 local function execute(lead,seconds) lead:click(lead.env.ShirsRaidBuilderMainFrame.executeBtn); pump(seconds) end

 -- 1. The literal five-slot raid group, one leader Execute, Bob's builder hidden.
 scenario('five-slot: Alice 1-2, Bob 3, Alice 4-5',function()
  local board=literal({},1,'Alicia','Bobalt','Alicia')
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  local plan=snapshot(peer:preset())
  execute(lead,90); show('five-slot forward')
  match('five-slot forward',expected(board,{{'alice',1,2},{'bob',3,3},{'alice',4,5}}),lead,peer)
  assert(shape(runs[1])=='1=Alice@1-2,1=Bob@3-3,1=Alice@4-5','five-slot forward chunks: '..shape(runs[1]))
  assert(runs[1].kind=='GRANT' and runs[1].step==2 and runs[2].kind=='REPORT' and runs[2].step==2,'five-slot forward protocol steps')
  bound('five-slot forward'); pacing('five-slot forward'); settled('five-slot forward',lead,peer,board)
  assert(snapshot(peer:preset())==plan,'five-slot forward changed the participant plan')
 end)
 scenario('five-slot reverse: Bob 1-2, Alice 3, Bob 4-5',function()
  local board=literal({},1,'Bobalt','Alicia','Bobalt')
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  execute(lead,120); show('five-slot reverse')
  match('five-slot reverse',expected(board,{{'bob',1,2},{'alice',3,3},{'bob',4,5}}),lead,peer)
  assert(shape(runs[1])=='1=Bob@1-2,1=Alice@3-3,1=Bob@4-5','five-slot reverse chunks: '..shape(runs[1]))
  bound('five-slot reverse'); pacing('five-slot reverse'); settled('five-slot reverse',lead,peer,board)
 end)
 -- Same-account controls: no split and, for the local account, no cross-account process.
 scenario('five-slot same local account',function()
  local board=literal({},1,'Alicia','Aliana','Alicia')
  local lead,peer=start(board,{'Alice','Alicia','Aliana'},{'Bobalt'},{'Bob','Bobalt'})
  execute(lead,60); show('five-slot same local account')
  match('five-slot same local account',expected(board,{{'alice',1,5}}),lead,peer)
  pacing('five-slot same local account')
  local db=lead.env.ShirsRaidBuilderDB
  assert(not (db.handoff and db.handoff.active) and table.getn(lead.whispers)==0 and table.getn(peer.whispers)==0,'same local account used a cross-account process')
 end)
 scenario('five-slot same linked account',function()
  local board=literal({},1,'Bobalt','Bobina','Bobalt')
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt','Bobina'},{'Bob','Bobalt','Bobina'})
  execute(lead,90); show('five-slot same linked account')
  match('five-slot same linked account',expected(board,{{'bob',1,5}}),lead,peer)
  assert(shape(runs[1])=='1=Bob','same linked account split its group: '..shape(runs[1]))
  bound('five-slot same linked account'); pacing('five-slot same linked account'); settled('five-slot same linked account',lead,peer,board)
 end)
 -- The sequence twice (groups 1 and 2): Bob is granted twice and the run outlives a link.
 scenario('five-slot sequence twice, past 60s',function()
  local board=literal(literal({},1,'Alicia','Bobalt','Alicia'),2,'Aliana','Bobina','Aliana')
  local lead,peer=start(board,{'Alice','Alicia','Aliana'},{'Bobalt','Bobina'},{'Bob','Bobalt','Bobina'})
  execute(lead,170); show('five-slot twice')
  match('five-slot twice',expected(board,{{'alice',1,2},{'bob',3,3},{'alice',4,5},{'alice',6,7},{'bob',8,8},{'alice',9,10}}),lead,peer)
  assert(at[table.getn(at)]-at[1]>60,'repeated five-slot run fit inside one link')
  local invites=0
  for _,h in ipairs(world) do
   for _,w in ipairs(h.whispers) do local p=h.C.LinkParse(w.text); if p and p.kind=='INVITE' then invites=invites+1 end end
  end
  assert(invites>=2,'repeated five-slot run never renewed its link')
  bound('five-slot twice'); pacing('five-slot twice'); settled('five-slot twice',lead,peer,board)
 end)
 -- With a synthetic party roster and GRINFO: hired companions join their hirer's party,
 -- so every later step reads the companion list before hiring.
 scenario('five-slot, synthetic roster and GRINFO',function()
  local board=literal({},1,'Alicia','Bobalt','Alicia')
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  serve(lead,nil,true); serve(peer,nil,true)
  execute(lead,110); show('five-slot synthetic roster')
  match('five-slot synthetic roster',expected(board,{{'alice',1,2},{'bob',3,3},{'alice',4,5}}),lead,peer)
  pacing('five-slot synthetic roster'); settled('five-slot synthetic roster',lead,peer,board)
 end)
 -- The plan has a priest/healer deny rule. Bob's granted chunk hires from Bobalt (an alt),
 -- or from Bob itself. Once every hire is done, Bob's commands step sends the plan's rule
 -- to that companion only; Alice's rows match no rule, so she has no commands step.
 for _,from in ipairs({'Bobalt','Bob'}) do
  local source=from
  scenario('five-slot, participant deny rule, slot 3 from '..source,function()
   local board=literal({},1,'Alicia',source,'Alicia')
   local lead,peer=start(board,{'Alice','Alicia'},source=='Bobalt' and {'Bobalt'} or nil,{'Bob','Bobalt'})
   serve(lead,nil,true); serve(peer,nil,true)
   lead:preset().denyRules={{class='priest',role='healer',abilities={'Holy Nova'}}}
   execute(lead,120); show('five-slot deny rule from '..source)
   match('five-slot deny rule from '..source,expected(board,{{'alice',1,2},{'bob',3,3},{'alice',4,5},{'bob'}},
    {[4]={'bob whispers Bobcompa: deny add Holy Nova'}}),lead,peer)
   pacing('five-slot deny rule from '..source); settled('five-slot deny rule from '..source,lead,peer,board)
  end)
 end

 -- 2. Saved endpoints of one account. Alice remembers Bob and Bobby (both account B, both
 -- listing Bob, Bobby and Bobalt). Bobby has no client: offline. Bob is online; a real
 -- Refresh Synchronization links him live, and his account claim arrives in that session
 -- (synthetic reply to his '.z addinvite list'). Bob's own rows list Bobby and Bobalt.
 ids.bobby=ids.bob
 local bobRows='Bob:warrior:t1d:t2r:A:0:60:0:4 Bobby:mage:t1d:t2r:A:0:60:0:4 Bobalt:mage:t1d:t2r:A:0:60:0:4'
 local third={kind='legacy',charName='Third',class='mage',role='rdps'}
 local function endpoints(board,live,edit)
  world={};trace={};at={};parts={};runs={};elapsed=0;states={}
  local lead=client('Alice',100); local peer=client('Bob',7000)
  trust(lead,'Bob',{'Bobby','Bobalt'}); trust(lead,'Bobby',{'Bob','Bobalt'}); trust(peer,'Alice')
  lead.C.AccountReadLocal(characters({'Alice','Alicia'})); peer.C.AccountReadLocal(characters({'Bob','Bobby','Bobalt'}))
  serve(peer,bobRows)
  if edit then edit(lead,peer) end
  local e={}; for i=1,40 do e[i]=board[i] or {kind='empty'} end
  lead:preset().entries=e
  peer.env.ShirsRaidBuilderMainFrame:Hide()
  if live then lead:click(lead.env.ShirsRaidBuilderMainFrame.syncButton); pump(live) end
  return lead,peer
 end
 local function liveClaim(lead,id)
  local s=lead.C.peerSessions['FixtureRealm;bob'].state
  assert(s.phase=='linked' and s.remoteLicense and s.remoteLicense.accountId==id,'fixture did not reach a live Bob session with account claim '..id)
  local o=lead.C.peerSessions['FixtureRealm;bobby'].state
  assert(o.phase~='linked','fixture linked offline Bobby')
 end
 -- The frozen run kept saved Bobby: no hire, no work granted to Bob, a visible pause.
 local function keptSaved(name,lead,from)
  local run=lead.env.ShirsRaidBuilderDB.handoff.active
  assert(run and run.steps[1].actor=='Bobby' and run.plan.entries[1].account==from,name..': frozen actor or source changed: '..tostring(run and run.steps[1].actor))
  assert(run.phase=='interrupted' and not lead.C.handAuthority,name..': run '..tostring(run.phase)..', '..tostring(lead.C.handNotice))
  for _,line in ipairs(trace) do assert(not string.find(line,' hires ',1,true) and not string.find(line,'GRANT',1,true),name..': '..line) end
 end
 for _,from in ipairs({'Bobby','Bobalt'}) do
  local source=from
  scenario('saved Bobby offline, Bob live: '..source..' row',function()
   local board={[1]=hire(source,'mage','rdps','frost'),[6]=third}
   local lead,peer=endpoints(board,20)
   liveClaim(lead,ids.bob)
   local sent=table.getn(lead.whispers)
   execute(lead,60); show('saved endpoint, Bob live, '..source..' row')
   match('saved endpoint '..source,expected(board,{{'bob',1,1},{'alice',6,6}}),lead,peer)
   assert(runs[1].steps[1].actor=='Bob' and runs[1].plan.entries[1].account==source,'live endpoint changed the hire-from source')
   for i=sent+1,table.getn(lead.whispers) do assert(string.lower(lead.whispers[i].target)~='bobby','run addressed offline Bobby') end
   bound('saved endpoint '..source); settled('saved endpoint '..source,lead,peer,board)
  end)
 end
 scenario('saved Bobby offline, no live session',function()
  local lead,peer=endpoints({[1]=hire('Bobby','mage','rdps','frost'),[6]=third})
  execute(lead,90); show('saved endpoint, no live session')
  keptSaved('no live session',lead,'Bobby')
  for _,w in ipairs(lead.whispers) do assert(string.lower(w.target)~='bob','no-live run whispered Bob') end
 end)
 -- Any character of an account hires from any other, so a run goes to the account's current
 -- character. With Bob's session expired, his refreshed snapshot is still the account's
 -- newest: the run renews Bob's link and Bob hires the Bobby row; offline Bobby is never asked.
 scenario('saved Bobby offline, Bob session expired',function()
  local board={[1]=hire('Bobby','mage','rdps','frost'),[6]=third}
  local lead,peer=endpoints(board,20)
  liveClaim(lead,ids.bob); pump(45)
  assert(lead.C.peerSessions['FixtureRealm;bob'].state.phase=='disabled','fixture session did not expire')
  assert(lead.C.remoteLicenses['FixtureRealm;bob'].received>1800000000,'fixture did not refresh the saved Bob snapshot')
  local sent=table.getn(lead.whispers)
  execute(lead,90); show('saved endpoint, expired session')
  match('expired session',expected(board,{{'bob',1,1},{'alice',6,6}}),lead,peer)
  for i=sent+1,table.getn(lead.whispers) do assert(string.lower(lead.whispers[i].target)~='bobby','run addressed offline Bobby') end
  bound('expired session'); settled('expired session',lead,peer,board)
 end)
 -- No session at all: Bob's account was synced from Bobby a day ago and from
 -- Bob last, and is on Bob now. Its normal and legacy Bobby rows are hired through Bob.
 local function older(h,peer,seconds)
  local r=h.env.ShirsRaidBuilderDB.peerSnapshots['FixtureRealm;'..string.lower(peer)]
  r.received=r.received-seconds; r.observed=r.observed-seconds
  for _,e in ipairs(r.entries) do e.observed=e.observed-seconds end
  h.C.LicenseRestoreSaved()
 end
 scenario('Bob synced last, saved Bobby offline: Bobby rows',function()
  local board={[1]=hire('Bobby','mage','rdps','frost'),[2]={kind='legacy',charName='Bobby',sourceName='Bobby',class='mage',role='rdps'},[6]=third}
  local lead,peer=endpoints(board,nil,function(l) older(l,'Bobby',86400) end)
  execute(lead,90); show('Bob synced last, Bobby rows')
  match('Bob synced last',expected(board,{{'bob',1,2},{'alice',6,6}}),lead,peer)
  for _,w in ipairs(lead.whispers) do assert(string.lower(w.target)~='bobby','run addressed offline Bobby') end
  bound('Bob synced last'); settled('Bob synced last',lead,peer,board)
 end)
 -- The newest snapshot can be wrong: Bobby synced last but has no client. Nothing remote is
 -- hired, and the pause names the character that did not answer.
 scenario('Bobby synced last but offline',function()
  local lead,peer=endpoints({[1]=hire('Bob','mage','rdps','frost'),[6]=third},nil,function(l) older(l,'Bob',86400) end)
  execute(lead,120); show('Bobby synced last, offline')
  keptSaved('newest offline',lead,'Bob')
  assert(string.find(tostring(lead.C.handNotice),'Bobby did not answer',1,true),'pause did not name the silent character: '..tostring(lead.C.handNotice))
 end)
 scenario('saved Bobby offline, Bob live with another account claim',function()
  local lead,peer=endpoints({[1]=hire('Bobby','mage','rdps','frost'),[6]=third},20,
   function(_,bob) bob.env.ShirsRaidBuilderDB.syncAccountId='3333333333333333' end)
  liveClaim(lead,'3333333333333333')
  assert(lead.C.remoteLicenses['FixtureRealm;bob'].accountId==ids.bob,'fixture replaced the saved Bob account claim')
  execute(lead,90); show('saved endpoint, account claim mismatch')
  keptSaved('account claim mismatch',lead,'Bobby')
 end)
 scenario('saved Bobby offline, Bob live then unlinked',function()
  local lead,peer=endpoints({[1]=hire('Bobby','mage','rdps','frost'),[6]=third},20)
  liveClaim(lead,ids.bob)
  lead.C.OpenPeerPOC(); lead.C.peerPanel.nameInput:SetText('Bob'); lead:click(lead.C.peerPanel.forgetButton); lead.C.peerPanel:Hide()
  assert(not lead.C.LinkKnown(lead.env.ShirsRaidBuilderDB.peerLinks,'Alice','Bob','FixtureRealm'),'fixture did not unlink Bob')
  execute(lead,90); show('saved endpoint, unlinked session')
  keptSaved('unlinked session',lead,'Bobby')
 end)
 -- Two live endpoints claiming one account are genuinely ambiguous for a third name:
 -- Execute refuses before any command, as before.
 scenario('Bob and Bobby both live: Bobalt row',function()
  world={};trace={};at={};parts={};runs={};elapsed=0;states={}
  local lead=client('Alice',100); local bob=client('Bob',7000); local bobby=client('Bobby',9000)
  trust(lead,'Bob',{'Bobby','Bobalt'}); trust(lead,'Bobby',{'Bob','Bobalt'}); trust(bob,'Alice'); trust(bobby,'Alice')
  lead.C.AccountReadLocal(characters({'Alice'}))
  for _,h in ipairs({bob,bobby}) do
   h.C.AccountReadLocal(characters({'Bob','Bobby','Bobalt'})); serve(h,bobRows); h.env.ShirsRaidBuilderMainFrame:Hide()
  end
  local e={}; for i=1,40 do e[i]={kind='empty'} end; e[1]=hire('Bobalt','mage','rdps','frost')
  lead:preset().entries=e
  lead:click(lead.env.ShirsRaidBuilderMainFrame.syncButton); pump(20)
  for _,key in ipairs({'FixtureRealm;bob','FixtureRealm;bobby'}) do
   local s=lead.C.peerSessions[key].state
   assert(s.phase=='linked' and s.remoteLicense and s.remoteLicense.accountId==ids.bob,'fixture did not link '..key..' live')
  end
  execute(lead,10); show('two live endpoints')
  local db=lead.env.ShirsRaidBuilderDB
  assert(table.getn(trace)==0 and not lead.C.handAuthority and not (db.handoff and db.handoff.active)
   and string.find(tostring(lead.C.handNotice),'Bobalt',1,true),'two live endpoints routed Bobalt: '..tostring(lead.C.handNotice))
 end)

 -- 3. Legacy rows added through the real Add Legacy editor: frozen into the run, granted
 -- by chunk, validated and hired by the receiver with the real name; -lite names are
 -- whisper targets only. Sorting is never touched.
 local function nosort(h)
  for _,name in ipairs({'SetRaidSubgroup','SwapRaidSubgroup','ConvertToRaid'}) do
   local api=name; h.env[api]=function() log(string.lower(h.name)..' SORT '..api) end
  end
 end
 local function addLegacy(h,name,role,class)
  h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Add Legacy'))
  local f=h.env.ShirsRaidBuilderAddLegacy
  f.nameInput:SetText(name); h:choose(f.roleButton,role); h:choose(f.classButton,class); h:click(f.addButton); f:Hide()
  local entries=h:preset().entries
  for i=1,40 do
   local e=entries[i]
   if e.kind=='legacy' and e.charName==name then
    assert(e.sourceName==name and e.whisperName==h.C.NormalizeLegacyName(name) and h.C.GetLegacyWhisperName(e)==e.whisperName,'Add Legacy saved row: '..snapshot(e))
    return i
   end
  end
  error('Add Legacy did not save '..name)
 end
 -- Group 1: Alicia 1-2, Bobalt 3, legacy Longlegacynm 4 (a later remote chunk: it joins the
 -- preceding normal row's actor, Bob), Alicia 5. Group 2: legacy Typedlegacy 6 leads, so it
 -- joins the group's first normal actor (Bobalt 7, Bob); Alicia 8; legacy Ownlegacy 9 joins
 -- Alicia's chunk with the player's own board row 10. Typedlegacy is typed, never discovered.
 -- Add Legacy fills the first empty slot; the board keeps the player's row in place.
 local function legacyBoard(lead)
  local e={}; for i=1,40 do e[i]={kind='empty'} end
  e[1]=hire('Alicia','mage','rdps','frost'); e[2]=hire('Alicia','warlock','rdps','default'); e[3]=hire('Bobalt','priest','healer','default')
  e[5]=hire('Alicia','mage','rdps','arcane'); e[7]=hire('Bobalt','warlock','rdps','default'); e[8]=hire('Alicia','priest','rdps','default')
  e[10]={kind='player',charName='Alice',class='warrior',role='tank'}
  lead:preset().entries=e
  assert(addLegacy(lead,'Longlegacynm','Ranged DPS','Mage')==4,'long legacy row not in slot 4')
  assert(addLegacy(lead,'Typedlegacy','Healer','Priest')==6,'typed legacy row not in slot 6')
  assert(addLegacy(lead,'Ownlegacy','Ranged DPS','Mage')==9,'own legacy row not in slot 9')
  assert(lead:preset().entries[10].kind=='player','player row moved')
  return lead:preset().entries
 end
 local legacySteps={{'alice',1,2},{'bob',3,4},{'alice',5,5},{'bob',6,7},{'alice',8,10}}
 -- With commands on both accounts: Alice's commands step follows her last chunk, then Bob's.
 local legacyCommandSteps={{'alice',1,2},{'bob',3,4},{'alice',5,5},{'bob',6,7},{'alice',8,10},{'alice'},{'bob'}}
 local function legacyChecks(name,lead,peer,board,commands)
  assert(shape(runs[1])=='1=Alice@1-2,1=Bob@3-4,1=Alice@5-5,2=Bob@6-7,2=Alice@8-10'..(commands and ',0=Alice,0=Bob' or ''),'legacy chunks: '..shape(runs[1]))
  local wire=runs[1].plan.entries
  assert(wire[4].kind=='legacy' and wire[4].sourceName=='Longlegacynm' and wire[6].sourceName=='Typedlegacy' and wire[9].sourceName=='Ownlegacy',
   'legacy real names lost on the wire')
  bound(name); pacing(name); settled(name,lead,peer,board)
 end
 scenario('legacy rows in a mixed run',function()
  world={};trace={};at={};parts={};runs={};elapsed=0;states={}
  local lead=client('Alice',100); local peer=client('Bob',7000)
  trust(lead,'Bob',{'Bobalt'}); trust(peer,'Alice')
  lead.C.AccountReadLocal(characters({'Alice','Alicia'})); peer.C.AccountReadLocal(characters({'Bob','Bobalt'}))
  -- Bob answers GRINFO: legacy setups wait for the companion list and his -lite member.
  serve(lead); serve(peer,nil,true); nosort(lead); nosort(peer)
  local board=legacyBoard(lead)
  -- Per-row deny lists through the real individual editor, on a leader row and a granted row.
  for _,who in ipairs({'Ownlegacy','Longlegacynm'}) do
   local d=lead:open(who); d.input:SetText('Blizzard'); lead:fire(d.input,'OnEnterPressed'); lead:click(lead:button(d,'Save'))
   assert(lead:entry(who).denyList[1]=='Blizzard','fixture deny list not saved for '..who)
  end
  -- Individual setups on the granted row, stored as the setup editor saves them.
  local long=lead:entry('Longlegacynm'); long.magic='Amplify'; long.setupRules={{class='mage',role='all',spec='all',drink='40'}}
  peer.env.ShirsRaidBuilderMainFrame:Hide()
  execute(lead,260); show('legacy mixed run')
  -- The frozen plan keeps each legacy row's own commands: the account that hires the row
  -- whispers them to its -lite name once every hire is done, on either account, each once.
  match('legacy mixed run',expected(board,legacyCommandSteps,{
   [6]={'alice whispers Ownlega-lite: deny add Blizzard'},
   [7]={'bob whispers Longleg-lite: set magic amplify','bob whispers Longleg-lite: set drink 40','bob whispers Longleg-lite: deny add Blizzard'}}),lead,peer)
  legacyChecks('legacy mixed run',lead,peer,board,true)
 end)
 -- Legacy-only control: no linked step, so an ordinary local run hires each real name once
 -- and whispers the per-row deny list to the -lite name afterwards.
 scenario('legacy-only control',function()
  world={};trace={};at={};parts={};runs={};elapsed=0;states={}
  local lead=client('Alice',100); local peer=client('Bob',7000)
  trust(lead,'Bob',{'Bobalt'}); trust(peer,'Alice')
  serve(lead); nosort(lead)
  local e={}; for i=1,40 do e[i]={kind='empty'} end
  e[5]={kind='player',charName='Alice',class='warrior',role='tank'}
  lead:preset().entries=e
  assert(addLegacy(lead,'Longlegacynm','Ranged DPS','Mage')==1 and addLegacy(lead,'Typedlegacy','Healer','Priest')==2,'legacy-only rows not in slots 1-2')
  local d=lead:open('Longlegacynm'); d.input:SetText('Blizzard'); lead:fire(d.input,'OnEnterPressed'); lead:click(lead:button(d,'Save'))
  execute(lead,40); show('legacy-only control')
  match('legacy-only control',{'alice hires .z addlegacy "Longlegacynm" rdps','alice hires .z addlegacy "Typedlegacy" healer',
   'alice whispers Longleg-lite: deny add Blizzard'},lead,peer)
  pacing('legacy-only control')
  local db=lead.env.ShirsRaidBuilderDB
  assert(not (db.handoff and db.handoff.active) and table.getn(peer.whispers)==0,'legacy-only plan used a cross-account process')
 end)
 -- The same mixed run with a synthetic roster and GRINFO on both accounts. The plan has a
 -- mage setup rule and a priest healer deny rule; Bob's open profile has different ones.
 -- Once every hire is done, each account applies the plan's rules to its own companions,
 -- companions first, then legacy -lite members (never the real name), as a single builder
 -- does; Bob's own profile rules never fire.
 scenario('legacy mixed run, plan rules on both accounts',function()
  world={};trace={};at={};parts={};runs={};elapsed=0;states={}
  local lead=client('Alice',100); local peer=client('Bob',7000)
  trust(lead,'Bob',{'Bobalt'}); trust(peer,'Alice')
  lead.C.AccountReadLocal(characters({'Alice','Alicia'})); peer.C.AccountReadLocal(characters({'Bob','Bobalt'}))
  serve(lead,nil,true); serve(peer,nil,true); nosort(lead); nosort(peer)
  peer:preset().setupRules={{class='mage',role='all',drink='30'}}
  peer:preset().denyRules={{class='mage',role='rdps',abilities={'Blizzard'}}}
  local board=legacyBoard(lead)
  lead:preset().setupRules={{class='mage',role='all',spec='all',drink='40'}}
  lead:preset().denyRules={{class='priest',role='healer',abilities={'Holy Nova'}}}
  peer.env.ShirsRaidBuilderMainFrame:Hide()
  execute(lead,300); show('legacy mixed run, plan rules')
  match('plan rules',expected(board,legacyCommandSteps,{
   [6]={'alice whispers Alicecompa: set drink 40','alice whispers Alicecompc: set drink 40','alice whispers Ownlega-lite: set drink 40'},
   [7]={'bob whispers Bobcompa: deny add Holy Nova','bob whispers Longleg-lite: set drink 40','bob whispers Typedle-lite: deny add Holy Nova'}}),lead,peer)
  legacyChecks('plan rules',lead,peer,board,true)
 end)
 -- Shared-raid client: the hirer's companion joins the raid; GRINFO lists every hired
 -- companion in the raid (both accounts), owner being the hire-from character, or the
 -- character that sent the hire when raid.ownerIsHirer is set (the server's choice is
 -- not known).
 local function serveRaid(h,delay)
  h.server={}; h.hired=0
  local send=h.env.SendChatMessage
  h.env.SendChatMessage=function(text,route,language,target)
   if route=='SAY' then
    local _,_,from,class,role=string.find(text,'^%.z addinvite (%a+) %w+ (%a+) (%a+) ')
    if from then h.hired=h.hired+1; table.insert(raid.pending,{at=elapsed+(delay or 1),name=h.name..'comp'..string.char(96+h.hired),class=class,role=role,owner=raid.ownerIsHirer and h.name or from}) end
    local _,_,real=string.find(text,'^%.z addlegacy "(%a+)"')
    if real then table.insert(raid.pending,{at=elapsed+(delay or 1),name=h.C.NormalizeLegacyName(real)}) end
   elseif route=='WHISPER' and not (h.C.LinkParse(text) or h.C.HandParse(text) or h.C.LicenseParse(text) or h.C.AccountParse(text) or h.C.RaidParse(text)) then
    log(string.lower(h.name)..' whispers '..tostring(target)..': '..text)
   end
   return send(text,route,language,target)
  end
  h.env.SendAddonMessage=function(prefix,text)
   if prefix~='nexus' or text~='GRINFO:ALL:FULL' then return end
   local listed={}
   for _,list in ipairs({raid.members,raid.early and raid.pending or {}}) do
    for _,c in ipairs(list) do if c.owner then table.insert(listed,c.name..':Human:'..c.class..':'..c.role..':Uncommon:'..c.owner) end end
   end
   table.insert(h.server,'[nexus] GRINFO:ALL:FULL '..table.concat(listed,' '))
  end
  h.env.GetNumPartyMembers=function() return 0 end
  h.env.GetNumRaidMembers=function() return table.getn(raid.members) end
  h.env.UnitName=function(unit)
   if unit=='player' then return h.name end
   local _,_,n=string.find(tostring(unit),'^raid(%d+)$')
   local c=n and raid.members[tonumber(n)]
   return c and c.name
  end
 end
 -- peerDelay: the participant's companions join that many seconds after the hire, and
 -- GRINFO already lists hired companions that have not joined yet (raid.early).
 local function raided(lead,peer,members,peerDelay,pending)
  raid={members=members or {{name='Alice'},{name='Bob'}},pending=pending or {},early=peerDelay~=nil}; queued=true
  serveRaid(lead); serveRaid(peer,peerDelay)
  local who={}
  for i,h in ipairs(world) do table.insert(who,string.lower(h.name)..'=UnitName("player") '..h.env.UnitName('player')..(i==1 and ' leader' or ' participant')) end
  print('CLIENTS '..table.concat(who,'; '))
 end
 local function renewals(h)
  local n=0
  for _,w in ipairs(h.whispers) do local p=h.C.LinkParse(w.text); if p and p.kind=='INVITE' then n=n+1 end end
  return n
 end
 -- Literal 1-2 / 3 / 4-5 in one raid with real roster events. A join never touches the
 -- links: Bob reports on the session his grant opened, with no renewal. Distinct rows.
 scenario('roster events: five-slot forward in one raid',function()
  local board=literal({},1,'Alicia','Bobalt','Alicia')
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  raided(lead,peer)
  execute(lead,130); show('roster events five-slot forward')
  match('roster five-slot',expected(board,{{'alice',1,2},{'bob',3,3},{'alice',4,5}}),lead,peer)
  assert(table.getn(raid.members)==7 and renewals(peer)==0,'no roster join, or a join forced a participant link renewal: '..table.getn(raid.members)..', '..renewals(peer))
  pacing('roster five-slot'); settled('roster five-slot',lead,peer,board)
 end)
 -- The mixed legacy run in the same raid with roster events.
 scenario('roster events: legacy mixed run in one raid',function()
  world={};trace={};at={};parts={};runs={};elapsed=0;states={}
  local lead=client('Alice',100); local peer=client('Bob',7000)
  trust(lead,'Bob',{'Bobalt'}); trust(peer,'Alice')
  lead.C.AccountReadLocal(characters({'Alice','Alicia'})); peer.C.AccountReadLocal(characters({'Bob','Bobalt'}))
  nosort(lead); nosort(peer)
  local board=legacyBoard(lead)
  peer.env.ShirsRaidBuilderMainFrame:Hide()
  raided(lead,peer)
  execute(lead,220); show('roster events legacy mixed run')
  match('roster legacy',expected(board,legacySteps),lead,peer)
  legacyChecks('roster legacy',lead,peer,board)
 end)
 -- Repeated same owner/class/role rows (Alicia mage in slots 1-2 and 4-5, Bobalt mage
 -- in 3) and one mage deny rule on BOTH endpoints. Once every hire is done, each account's
 -- commands step sends the rule to its own companions, never the other account's. A rerun
 -- of the same board then spends nothing.
 local same={}
 for i=1,5 do same[i]=hire(i==3 and 'Bobalt' or 'Alicia','mage','rdps','frost') end
 local rule={{class='mage',role='rdps',abilities={'Blizzard'}}}
 local function deny(who,comp) return who..' whispers '..comp..': deny add Blizzard' end
 scenario('repeated rows, group rule on both endpoints, then rerun',function()
  local lead,peer=start(same,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  lead:preset().denyRules=rule; peer:preset().denyRules={{class='mage',role='rdps',abilities={'Blizzard'}}}
  raided(lead,peer)
  execute(lead,150); show('repeated rows with rule')
  match('repeated rows',expected(same,{{'alice',1,2},{'bob',3,3},{'alice',4,5},{'alice'},{'bob'}},
   {[4]={deny('alice','Alicecompa'),deny('alice','Alicecompb'),deny('alice','Alicecompc'),deny('alice','Alicecompd')},[5]={deny('bob','Bobcompa')}}),lead,peer)
  settled('repeated rows',lead,peer,same)
  local before=table.getn(trace)
  execute(lead,150); show('repeated rows rerun')
  for i=before+1,table.getn(trace) do assert(not string.find(trace[i],' hires ',1,true),'rerun spent again: '..trace[i]) end
  assert(lead.env.ShirsRaidBuilderDB.handoff.active.phase=='done','rerun did not finish: '..tostring(lead.C.handNotice))
 end)
 -- The same with a companion already in the raid before Execute (owner Alicia, mage).
 -- It satisfies slot 1 one-to-one; later chunks still hire and configure their own.
 scenario('repeated rows with a pre-existing companion',function()
  local lead,peer=start(same,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  lead:preset().denyRules=rule; peer:preset().denyRules={{class='mage',role='rdps',abilities={'Blizzard'}}}
  raided(lead,peer,{{name='Alice'},{name='Bob'},{name='Oldcomp',class='mage',role='rdps',owner='Alicia'}})
  execute(lead,150); show('repeated rows, pre-existing companion')
  local claims=table.concat({ids.alice,ids.bob,ids.alice,ids.alice,ids.bob},',')
  match('pre-existing companion',{'alice hires '..invite('Alicia','mage','rdps','frost'),
   'alice GRANT 2 to bob accounts '..claims,'bob hires '..invite('Bobalt','mage','rdps','frost'),'bob REPORT 2 to alice',
   'alice hires '..invite('Alicia','mage','rdps','frost'),'alice hires '..invite('Alicia','mage','rdps','frost'),
   deny('alice','Oldcomp'),deny('alice','Alicecompa'),deny('alice','Alicecompb'),deny('alice','Alicecompc'),
   'alice GRANT 5 to bob accounts '..claims,deny('bob','Bobcompa'),'bob REPORT 5 to alice'},lead,peer)
  settled('pre-existing companion',lead,peer,same)
 end)
 -- Same-account control: all five rows on Alice's account, no linked step. One plain
 -- queue hires five and the rule reaches each new companion once.
 scenario('repeated rows, same-account control in one raid',function()
  local board={}
  for i=1,5 do board[i]=hire(i==3 and 'Aliana' or 'Alicia','mage','rdps','frost') end
  local lead,peer=start(board,{'Alice','Alicia','Aliana'},{'Bobalt'},{'Bob','Bobalt'})
  lead:preset().denyRules=rule
  raided(lead,peer)
  execute(lead,80); show('repeated rows, same-account control')
  local lines=expected(board,{{'alice',1,5}})
  for _,c in ipairs({'a','b','c','d','e'}) do table.insert(lines,deny('alice','Alicecomp'..c)) end
  match('same-account control',lines,lead,peer)
  local db=lead.env.ShirsRaidBuilderDB
  assert(not (db.handoff and db.handoff.active) and table.getn(peer.whispers)==0,'same-account control used a cross-account process')
 end)
 -- Timing check. SYNTHETIC timing assumption: GRINFO already lists Bob's hired companion
 -- while the raid roster shows it only 10 s after the hire, inside the 12 s grace, so
 -- Bob's queue must wait several ticks with its group command still held. Roster events
 -- still fire on every join. Bob has one priest/healer deny rule.
 local holy={{class='priest',role='healer',abilities={'Holy Nova'}}}
 local function waited(name,peer) assert((peer.nameWaits or 0)>=2,name..': fixture never waited for roster visibility ('..tostring(peer.nameWaits)..' ticks)') end
 -- Bob's chunk is the run's last, so his commands step runs in the same batch, right after
 -- his hires. A lone hire at queue index 1, already sent when the list expands.
 scenario('timing: lone hire, GRINFO before roster',function()
  local board={hire('Alicia','mage','rdps','frost'),hire('Alicia','warlock','rdps','default'),hire('Bobalt','priest','healer','default')}
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  lead:preset().denyRules=holy
  raided(lead,peer,nil,10)
  execute(lead,140); show('timing lone hire')
  match('timing lone hire',expected(board,{{'alice',1,2},{'bob',3,3},{'bob'}},{[3]={'bob whispers Bobcompa: deny add Holy Nova'}}),lead,peer)
  waited('timing lone hire',peer); pacing('timing lone hire'); settled('timing lone hire',lead,peer,board)
 end)
 -- Two hires; the queue is parked on the last sent index (executeIndex > 1).
 scenario('timing: two hires, GRINFO before roster',function()
  local board={hire('Alicia','mage','rdps','frost'),hire('Alicia','warlock','rdps','default'),hire('Bobalt','priest','healer','default'),
   hire('Bobalt','priest','rdps','default')}
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  lead:preset().denyRules={{class='priest',role='healer',abilities={'Holy Nova'}}}
  raided(lead,peer,nil,10)
  execute(lead,150); show('timing two hires')
  match('timing two hires',expected(board,{{'alice',1,2},{'bob',3,4},{'bob'}},{[3]={'bob whispers Bobcompa: deny add Holy Nova'}}),lead,peer)
  assert(shape(runs[1])=='1=Alice@1-2,1=Bob@3-4,0=Bob','timing two hires chunks: '..shape(runs[1]))
  waited('timing two hires',peer); pacing('timing two hires'); settled('timing two hires',lead,peer,board)
 end)
 -- Held first: Bob's only hire is already present (Oldbob), so his queue starts on the
 -- held deny; another raid member listed by GRINFO joins only at 45 s, after Bob's name
 -- wait for the plan's rule ends.
 scenario('timing: held first, all hires already present',function()
  local board={hire('Alicia','mage','rdps','frost'),hire('Alicia','warlock','rdps','default'),hire('Bobalt','priest','healer','default')}
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  lead:preset().denyRules={{class='priest',role='healer',abilities={'Holy Nova'}}}
  raided(lead,peer,{{name='Alice'},{name='Bob'},{name='Oldbob',class='priest',role='healer',owner='Bobalt'}},10,
   {{at=45,name='Latecomp',class='warrior',role='tank',owner='Carol'}})
  execute(lead,140); show('timing held first')
  local lines=expected(board,{{'alice',1,2},{'bob',3,3},{'bob'}},{[3]={'bob whispers Oldbob: deny add Holy Nova'}})
  table.remove(lines,4) -- slot 3 is already present: no hire
  match('timing held first',lines,lead,peer)
  waited('timing held first',peer); pacing('timing held first'); settled('timing held first',lead,peer,board)
 end)
 raid=nil; queued=nil
 -- 3. Five transfers received by the inviting endpoint across a link renewal, on the real
 -- whisper receive path. Alice invites both times (Refresh Synchronization), so her
 -- session state is reused; Bob's state is new per invite. Each transfer has a new nonce.
 scenario('inviting endpoint: five transfers across a renewal',function()
  world={};trace={};at={};parts={};runs={};elapsed=0;states={}
  local lead=client('Alice',100); local peer=client('Bob',7000)
  trust(lead,'Bob'); trust(peer,'Alice')
  peer.env.ShirsRaidBuilderMainFrame:Hide()
  local wire=assert(lead.C.HandEncode(assert(lead.C.HandCreate({entries={[1]={kind='legacy',charName='First',class='mage',role='rdps'}}},
   'Probe','Bob','FixtureRealm',{'Bob'},'1234567890123499',1800000000))))
  local function link()
   lead:click(lead.env.ShirsRaidBuilderMainFrame.syncButton); pump(6)
   local s=lead.C.peerSessions['FixtureRealm;bob'].state
   assert(s.phase=='linked' and peer.C.peerSessions['FixtureRealm;alice'].state.phase=='linked','fixture did not link')
   return s
  end
  local function packets(nonce)
   return assert(peer.C.HandPackets(peer.C.peerSessions['FixtureRealm;alice'].state,wire,nonce,peer.wall,peer.now),'Bob could not packetize')
  end
  local function deliver(list,first)
   for i=first or 1,table.getn(list) do
    lead.env.event='CHAT_MSG_WHISPER'; lead.env.arg2='Bob'; lead:fire(lead.C.peerDriver,'OnEvent',list[i])
   end
   local got=lead.C.peerSessions['FixtureRealm;bob'].state.handProposal~=nil
   pump(1)
   return got
  end
  local s1=link()
  local old=packets('500002')
  assert(deliver(packets('500001')) and deliver(old),'first session refused its first transfers')
  pump(62)
  assert(s1.phase=='disabled','fixture session did not expire')
  local s2=link()
  print('TRACE five transfers: inviting state reused across renewal: '..tostring(s2==s1))
  local results={}
  for _,nonce in ipairs({'500003','500004','500005'}) do table.insert(results,nonce..'='..tostring(deliver(packets(nonce)))) end
  print('TRACE five transfers: session 1 received 500001, 500002; session 2 '..table.concat(results,' '))
  assert(results[3]=='500005=true','fifth transfer overall (third in the renewed session) was dropped: '..table.concat(results,' '))
  assert(deliver(packets('500006')),'fourth transfer in the renewed session refused')
  assert(not deliver(packets('500007')),'fifth transfer in one live session accepted')
  assert(not deliver(packets('500003')),'same-session replayed nonce accepted')
  assert(not deliver(old),'old-session packets accepted in the renewed session')
  local twoPart=packets('500008')
  if table.getn(twoPart)>1 then assert(not deliver(twoPart,2),'out-of-order transfer accepted') end
  lead.C.OpenPeerPOC(); lead.C.peerPanel.nameInput:SetText('Bob'); lead:click(lead.C.peerPanel.forgetButton); lead.C.peerPanel:Hide()
  assert(not lead.C.LinkKnown(lead.env.ShirsRaidBuilderDB.peerLinks,'Alice','Bob','FixtureRealm'),'fixture did not revoke Bob')
  local revoked=peer.C.HandPackets(peer.C.peerSessions['FixtureRealm;alice'].state,wire,'500009',peer.wall,peer.now)
  assert(not revoked or not deliver(revoked),'revoked trust accepted a transfer')
 end)
 -- Bulk hand-off: one account's groups in a row are one grant, one queue and one report.
 -- The steps on the wire do not change, so both sides find the same batch.
 scenario('bulk: two groups in a row on the participant',function()
  local board={[1]=hire('Alicia','mage','rdps','frost'),[6]=hire('Bobalt','mage','rdps','frost'),
   [11]=hire('Bobalt','warlock','rdps','default'),[16]=third}
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  execute(lead,120); show('bulk participant')
  local claims=ids.alice..','..ids.bob..','..ids.bob..','..ids.alice
  match('bulk participant',{'alice hires '..invite('Alicia','mage','rdps','frost'),'alice GRANT 2 to bob accounts '..claims,
   'bob hires '..invite('Bobalt','mage','rdps','frost'),'bob hires '..invite('Bobalt','warlock','rdps','default'),
   'bob REPORT 3 to alice','alice hires .z addlegacy "Third" rdps'},lead,peer)
  assert(shape(runs[1])=='1=Alice,2=Bob,3=Bob,4=Alice','bulk changed the steps: '..shape(runs[1]))
  bound('bulk participant'); settled('bulk participant',lead,peer,board)
 end)
 scenario('bulk: two groups in a row on the leader',function()
  local board={[1]=hire('Alicia','mage','rdps','frost'),[6]=hire('Alicia','warlock','rdps','default'),[11]=hire('Bobalt','mage','rdps','frost')}
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  serve(lead,nil,true)
  execute(lead,120); show('bulk leader')
  match('bulk leader',expected(board,{{'alice',1,5},{'alice',6,10},{'bob',11,15}}),lead,peer)
  assert(at[2]-at[1]<7.5,'the leader ran its two groups as separate steps: hires '..(at[2]-at[1])..' s apart')
  settled('bulk leader',lead,peer,board)
 end)
 -- A legacy companion can take longer to arrive than the 7.5-8.5 s settle time. Bob's legacy
 -- row has a setup and a deny list; his companion joins 12 s after the hire. Both whispers
 -- wait until it is in the group, instead of going to no one or being dropped.
 scenario('slow legacy join: setup and deny wait for the companion',function()
  local board={[1]=hire('Alicia','mage','rdps','frost'),
   [6]={kind='legacy',charName='Bobleg',sourceName='Bobleg',class='mage',role='rdps',denyList={'Frost Nova'},magic='Amplify'}}
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt','Bobleg'},{'Bob','Bobalt','Bobleg'})
  raided(lead,peer,nil,12)
  local send=peer.env.SendChatMessage
  peer.env.SendChatMessage=function(text,route,language,target)
   if route=='WHISPER' and target=='Bobleg-lite' then
    local here=false
    for _,m in ipairs(raid.members) do if m.name==target then here=true end end
    if not here then log('bob whispers Bobleg-lite before it joined') end
   end
   return send(text,route,language,target)
  end
  execute(lead,150); show('slow legacy join')
  match('slow legacy join',expected(board,{{'alice',1,5},{'bob',6,10},{'bob'}},
   {[3]={'bob whispers Bobleg-lite: set magic amplify','bob whispers Bobleg-lite: deny add Frost Nova'}}),lead,peer)
  settled('slow legacy join',lead,peer,board)
  raid=nil; queued=nil
 end)
 -- Bob's legacy row has only a deny list, so nothing waits for the companion list; the
 -- whisper must still wait for the companion instead of leaving at the settle time.
 scenario('slow legacy join: deny list only',function()
  local board={[1]=hire('Alicia','mage','rdps','frost'),
   [6]={kind='legacy',charName='Bobleg',sourceName='Bobleg',class='mage',role='rdps',denyList={'Frost Nova','Blizzard'}}}
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt','Bobleg'},{'Bob','Bobalt','Bobleg'})
  raided(lead,peer,nil,12)
  local send=peer.env.SendChatMessage
  peer.env.SendChatMessage=function(text,route,language,target)
   if route=='WHISPER' and target=='Bobleg-lite' then
    local here=false
    for _,m in ipairs(raid.members) do if m.name==target then here=true end end
    if not here then log('bob whispers Bobleg-lite before it joined') end
   end
   return send(text,route,language,target)
  end
  execute(lead,150); show('slow legacy deny only')
  match('slow legacy deny only',expected(board,{{'alice',1,5},{'bob',6,10},{'bob'}},
   {[3]={'bob whispers Bobleg-lite: deny add Frost Nova, Blizzard'}}),lead,peer)
  settled('slow legacy deny only',lead,peer,board)
  raid=nil; queued=nil
 end)
 -- The participant hires two warriors from its own alt and the plan has a warrior rule.
 -- Its batch must not stop while placing its companions for the group commands, which
 -- would leave the last two groups unhired and the leader waiting. Each case
 -- below is one way that placing can fall short; the run must finish either way.
 local warriorRule={{class='warrior',role='mdps',abilities={'Bloodthirst'}}}
 local function bt(who,comp) return who..' whispers '..comp..': deny add Bloodthirst' end
 local warriors={[1]=hire('Alice','warrior','mdps','default'),[6]=hire('Bobalt','warrior','mdps','default'),
  [7]=hire('Bobalt','warrior','mdps','default'),[11]=third}
 local warriorSteps={{'alice',1,5},{'bob',6,10},{'alice',11,15},{'alice'},{'bob'}}
 -- The server names the character that sent the hire (Bob) as owner, not Bobalt.
 scenario('owner is the hirer: participant alt rows keep their group rule',function()
  local lead,peer=start(warriors,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  lead:preset().denyRules=warriorRule
  raided(lead,peer); raid.ownerIsHirer=true
  execute(lead,150); show('owner is the hirer')
  match('owner is the hirer',expected(warriors,warriorSteps,{[4]={bt('alice','Alicecompa')},[5]={bt('bob','Bobcompa'),bt('bob','Bobcompb')}}),lead,peer)
  settled('owner is the hirer',lead,peer,warriors)
  raid=nil; queued=nil
 end)
 -- Another addon's question gets an answer while Bob's last hire is still settling, so
 -- that list lacks the newest companion. Bob waits for a list after the hire instead. Bob
 -- hires last here, so his commands step follows his hires in one batch.
 scenario('a companion list from before the last hire settled',function()
  local lastBob={[1]=warriors[1],[6]=warriors[6],[7]=warriors[7]}
  local lead,peer=start(lastBob,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  lead:preset().denyRules=warriorRule
  raided(lead,peer)
  local send=peer.env.SendChatMessage; local sent=0
  peer.env.SendChatMessage=function(text,route,language,target)
   send(text,route,language,target)
   if route=='SAY' and string.find(text,'^%.z addinvite ') then
    sent=sent+1
    if sent==2 then
     local listed={}
     for _,c in ipairs(raid.members) do if c.owner then table.insert(listed,c.name..':Human:'..c.class..':'..c.role..':Uncommon:'..c.owner) end end
     table.insert(peer.server,'[nexus] GRINFO:ALL:FULL '..table.concat(listed,' '))
    end
   end
  end
  execute(lead,150); show('companion list before the last hire settled')
  assert(sent==2,'fixture: Bob sent '..sent..' hires')
  match('early companion list',expected(lastBob,{{'alice',1,5},{'bob',6,10},{'bob'},{'alice'}},
   {[3]={bt('bob','Bobcompa'),bt('bob','Bobcompb')},[4]={bt('alice','Alicecompa')}}),lead,peer)
  settled('early companion list',lead,peer,lastBob)
  raid=nil; queued=nil
 end)
 -- A companion that never arrives (the server refused its hire) costs only its own
 -- commands: the rest of the batch gets the rule, the chat names the missing one, and the
 -- run goes on.
 scenario('a batch companion never joins',function()
  local board={[1]=hire('Alice','warrior','mdps','default'),[6]=hire('Bobalt','warrior','mdps','default'),
   [7]={kind='legacy',charName='Bobleg',sourceName='Bobleg',class='mage',role='rdps'},[11]=third}
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt','Bobleg'},{'Bob','Bobalt','Bobleg'})
  lead:preset().denyRules=warriorRule
  raided(lead,peer)
  local send=peer.env.SendChatMessage
  peer.env.SendChatMessage=function(text,route,language,target)
   send(text,route,language,target)
   for k=table.getn(raid.pending),1,-1 do if raid.pending[k].name=='Bobleg-lite' then table.remove(raid.pending,k) end end
  end
  execute(lead,180); show('a batch companion never joins')
  match('companion never joins',expected(board,warriorSteps,{[4]={bt('alice','Alicecompa')},[5]={bt('bob','Bobcompa')}}),lead,peer)
  local noted
  for _,m in ipairs(peer.messages) do if string.find(m,'Bobleg-lite',1,true) and string.find(m,'not in the group',1,true) then noted=m end end
  assert(noted,'the missing companion was not named in the participant chat')
  settled('companion never joins',lead,peer,board)
  raid=nil; queued=nil
 end)
 -- A participant batch that stops tells the leader at once,
 -- instead of leaving it waiting ten minutes for a report.
 local mages={[1]=hire('Alice','mage','rdps','frost'),[6]=hire('Bobalt','mage','rdps','frost'),[11]=third}
 local function silent(peer) local answer=peer.env.SendAddonMessage; peer.env.SendAddonMessage=function() end; return answer end
 scenario('a participant stop pauses the leader',function()
  local lead,peer=start(mages,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  raided(lead,peer); silent(peer) -- Bob never gets a companion list, so his batch cannot start
  execute(lead,60); show('participant stop')
  local run=lead.env.ShirsRaidBuilderDB.handoff.active
  assert(run.phase=='interrupted' and not lead.C.handAuthority and string.find(tostring(lead.C.handNotice),'Bob',1,true),
   'leader not paused after the participant stopped: '..tostring(run.phase)..'; leader: '..tostring(lead.C.handNotice)..'; participant: '..tostring(peer.C.handNotice))
  raid=nil; queued=nil
 end)
 -- After that stop the leader cancels and executes again. The participant takes the new
 -- run instead of refusing it as busy, and remembers the stopped one as cancelled.
 scenario('a new run replaces a stopped one on the participant',function()
  local lead,peer=start(mages,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  raided(lead,peer); local answer=silent(peer)
  execute(lead,60)
  local first=lead.env.ShirsRaidBuilderDB.handoff.active
  peer.env.SendAddonMessage=answer
  lead.C.HandCancelLocal()
  execute(lead,120); show('new run after a participant stop')
  local second=lead.env.ShirsRaidBuilderDB.handoff.active
  local mine=peer.env.ShirsRaidBuilderDB.handoff
  assert(second.id~=first.id and second.phase=='done','the new run did not finish: '..tostring(second.phase)..'; leader: '..tostring(lead.C.handNotice)..'; participant: '..tostring(peer.C.handNotice))
  assert(mine.active.id==second.id and mine.seen[first.id] and mine.seen[first.id].cancelled,'participant kept the stopped run')
  raid=nil; queued=nil
 end)
 -- A small mixed board: both accounts hire companions and a legacy character
 -- in alternating groups, with a warrior rule and legacy deny lists. Every hire comes
 -- first; then each account sends its commands, companions first and legacy characters
 -- last, as a single builder does. Alice hired last, so her commands go first.
 scenario('commands at the end: companions first, then legacy characters',function()
  local board={[1]={kind='legacy',charName='Aliceleg',sourceName='Aliceleg',class='priest',role='rdps',denyList={'Holy Fire'}},
   [2]=hire('Alicia','warrior','mdps','default'),[3]=hire('Alicia','warrior','mdps','default'),
   [6]=hire('Bobalt','warrior','mdps','default'),[7]={kind='legacy',charName='Bobleg',sourceName='Bobleg',class='mage',role='rdps',denyList={'Frost Nova'}},
   [8]=hire('Bobalt','warrior','mdps','default'),[11]=hire('Alicia','warrior','mdps','default')}
  local lead,peer=start(board,{'Alice','Alicia','Aliceleg'},{'Bobalt','Bobleg'},{'Bob','Bobalt','Bobleg'})
  lead:preset().denyRules=warriorRule
  raided(lead,peer)
  execute(lead,220); show('commands at the end')
  match('commands at the end',expected(board,{{'alice',1,5},{'bob',6,10},{'alice',11,15},{'alice'},{'bob'}},
   {[4]={bt('alice','Alicecompa'),bt('alice','Alicecompb'),bt('alice','Alicecompc'),'alice whispers Alicele-lite: deny add Holy Fire'},
    [5]={bt('bob','Bobcompa'),bt('bob','Bobcompb'),'bob whispers Bobleg-lite: deny add Frost Nova'}}),lead,peer)
  local lastHire,firstWhisper=0,nil
  for i,line in ipairs(trace) do
   if string.find(line,' hires ',1,true) then lastHire=i end
   if not firstWhisper and string.find(line,' whispers ',1,true) then firstWhisper=i end
  end
  assert(firstWhisper and firstWhisper>lastHire,'a command went out before the last hire')
  assert(shape(runs[1])=='1=Alice,2=Bob,3=Alice,0=Alice,0=Bob','commands steps: '..shape(runs[1]))
  bound('commands at the end'); pacing('commands at the end'); settled('commands at the end',lead,peer,board)
  raid=nil; queued=nil
 end)
 -- A 35-slot board, three accounts: Alice (alt Alicia), Bob (alt Bobalt) and Carol (alts
 -- Carola to Carold); the player sits in slot 36. The plan has warrior and mage deny rules,
 -- paladin and mage setup rules and a legacy deny list. Every row is hired once by its own
 -- account, and every companion and legacy character a command names gets it once, after
 -- the hires.
 scenario('three accounts, the 35-slot board of 6 Oct',function()
  world={};trace={};at={};parts={};runs={};elapsed=0;states={}
  ids.carol='3333333333333333'
  local lead=client('Alice',100); local bob=client('Bob',7000); local carol=client('Carol',14000)
  trust(lead,'Bob',{'Bobalt'}); trust(lead,'Carol',{'Carola','Carolb','Carolc','Carold'}); trust(bob,'Alice'); trust(carol,'Alice')
  lead.C.AccountReadLocal(characters({'Alice','Alicia'})); bob.C.AccountReadLocal(characters({'Bob','Bobalt'}))
  carol.C.AccountReadLocal(characters({'Carol','Carola','Carolb','Carolc','Carold'}))
  local function leg(name,class,role,denies) return {kind='legacy',charName=name,sourceName=name,class=class,role=role,denyList=denies} end
  local b={[1]=leg('Alicia','warrior','tank'),[5]=leg('Alice','priest','rdps'),[7]=leg('Bob','paladin','healer'),
   [10]=leg('Bobalt','priest','rdps',{'Abolish Disease','Cure Disease','Divine Spirit','Levitate','Dispel Magic','Devouring Plague'}),
   [36]={kind='player',charName='Alice',class='priest',role='rdps'}}
  for _,i in ipairs({2,3,4,6}) do b[i]=hire('Alice','warrior','mdps','default') end
  for _,i in ipairs({8,9}) do b[i]=hire('Bobalt','warrior','mdps','default') end
  for _,i in ipairs({11,16,17,18}) do b[i]=hire('Bob','mage','rdps','frost') end
  for i=12,15 do b[i]=hire('Alicia','paladin','mdps','default') end
  for _,i in ipairs({19,20}) do b[i]=hire('Bobalt','mage','rdps','frost') end
  local from={[21]='Carol',[24]='Carola',[27]='Carolb',[30]='Carolc',[33]='Carold'}
  local kinds={[21]={'warrior','tank'},[24]={'druid','healer'},[27]={'priest','healer'},[30]={'paladin','healer'},[33]={'paladin','healer'}}
  for first,owner in pairs(from) do for i=first,first+2 do b[i]=hire(owner,kinds[first][1],kinds[first][2],'default') end end
  local e={}; for i=1,40 do e[i]=b[i] or {kind='empty'} end
  lead:preset().entries=e
  lead:preset().denyRules={{class='warrior',role='mdps',abilities={'Bloodthirst','Concussion Blow','Death Wish','Challenging Shout','Demoralizing Shout','Defensive Stance'}},
   {class='mage',role='rdps',abilities={'Arcane Brilliance','Arcane Intellect','Blink','Conjure Mana Citrine','Detect Magic','Combustion'}}}
  lead:preset().setupRules={{class='paladin',role='all',spec='all',aura='Devotion Aura'},{class='mage',role='all',spec='all',drink='30',magic='None'}}
  bob.env.ShirsRaidBuilderMainFrame:Hide(); carol.env.ShirsRaidBuilderMainFrame:Hide()
  raided(lead,bob); serveRaid(carol); table.insert(raid.members,{name='Carol'})
  execute(lead,900); show('three accounts, 35 slots')
  local runOf=function(h) return h.env.ShirsRaidBuilderDB.handoff.active end
  for _,h in ipairs({lead,bob,carol}) do
   local r=runOf(h)
   assert(r and r.id==runOf(lead).id and (r.phase=='done' or (h==lead and r.phase=='done')),'run not finished on '..h.name..': '..tostring(r and r.phase)..' '..tostring(h.C.handNotice))
  end
  assert(shape(runs[1])=='1=Alice,2=Alice@6-6,2=Bob@7-10,3=Bob@11-11,3=Alice@12-15,4=Bob,5=Carol,6=Carol,7=Carol,8=Alice,0=Alice,0=Bob,0=Carol',
   'steps: '..shape(runs[1]))
  -- Hires: each row once, by its own account, in board order within each batch.
  local wanted,seen={},{}
  for i=1,35 do
   local r=b[i]; local who=(i<=6 or (i>=12 and i<=15)) and 'alice' or (i<=20 and 'bob' or 'carol')
   local line=r.kind=='legacy' and (who..' hires .z addlegacy "'..r.charName..'" '..r.role) or (who..' hires '..invite(r.account,r.class,r.role,r.spec))
   wanted[line]=(wanted[line] or 0)+1
  end
  local lastHire,firstWhisper=0,nil
  for i,line in ipairs(trace) do
   if string.find(line,' hires ',1,true) then seen[line]=(seen[line] or 0)+1; lastHire=i end
   if not firstWhisper and string.find(line,' whispers ',1,true) then firstWhisper=i end
  end
  for line,n in pairs(wanted) do assert(seen[line]==n,'hired '..tostring(seen[line] or 0)..' of '..n..': '..line) end
  for line,n in pairs(seen) do assert(wanted[line]==n,'unplanned hire: '..line) end
  assert(firstWhisper and firstWhisper>lastHire,'a command went out before the last hire')
  -- Commands: who gets what, once each; per account, companions before legacy characters.
  local got,lite={},{}
  for _,line in ipairs(trace) do
   local _,_,who,target,text=string.find(line,'^(%a+) whispers ([%a%-]+): (.+)$')
   if who then
    local key=target..': '..text; got[key]=(got[key] or 0)+1
    if string.find(target,'%-lite$') then lite[who]=true else assert(not lite[who],who..' whispered a companion after a legacy character: '..line) end
   end
  end
  local denyWarrior='deny add Bloodthirst, Concussion Blow, Death Wish, Challenging Shout, Demoralizing Shout, Defensive Stance'
  local denyMage='deny add Arcane Brilliance, Arcane Intellect, Blink, Conjure Mana Citrine, Detect Magic, Combustion'
  local function count(prefix,text) local n=0; for key,k in pairs(got) do if string.find(key,'^'..prefix) and string.sub(key,-string.len(text))==text then n=n+k end end; return n end
  assert(count('Alicecomp',denyWarrior)==4 and count('Bobcomp',denyWarrior)==2,'warrior rule: '..count('Alicecomp',denyWarrior)..' and '..count('Bobcomp',denyWarrior))
  assert(count('Bobcomp',denyMage)==6 and count('Bobcomp','set drink 30')==6,'mage rules: '..count('Bobcomp',denyMage)..', '..count('Bobcomp','set drink 30'))
  local aura=0; for key,k in pairs(got) do if string.find(key,'aura') then aura=aura+k end end
  assert(aura==11,'paladin aura went to '..aura..' of 11 (4 Alice, 6 Carol, Bob-lite)')
  assert(got['Bobalt-lite: deny add Abolish Disease, Cure Disease, Divine Spirit, Levitate, Dispel Magic, Devouring Plague']==1,'Bobalt-lite deny list')
  for key,k in pairs(got) do assert(k==1,'sent '..k..' times: '..key) end
  -- Each account gets the full run once; every later message, either way, is one packet.
  local full={}
  for _,r in ipairs(runs) do
   if r.packets>1 then
    assert(r.kind=='GRANT' and not full[r.steps[r.step].actor],'long '..r.kind..' '..r.step..' ('..r.packets..' packets)')
    full[r.steps[r.step].actor]=true
   end
  end
  assert(full.Bob and full.Carol,'first GRANTs were not the full run')
  raid=nil; queued=nil; ids.carol=nil
 end)
 -- After an account's first GRANT, every hand-off message is one packet: the receiver
 -- rebuilds it from its own copy of the run. (Sent in full, a 35-slot run takes 70 packets
 -- for every GRANT and 58 for every REPORT, about 640 packets and 2.7 minutes in all.)
 scenario('short hand-offs after the first GRANT',function()
  local board={[1]=hire('Alice','warrior','mdps','default'),[6]=hire('Bobalt','warrior','mdps','default'),
   [11]=hire('Alice','warrior','mdps','default'),[16]=hire('Bobalt','warrior','mdps','default')}
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  lead:preset().denyRules=warriorRule
  raided(lead,peer)
  execute(lead,300); show('short hand-offs')
  match('short hand-offs',expected(board,{{'alice',1,5},{'bob',6,10},{'alice',11,15},{'bob',16,20},{'bob'},{'alice'}},
   {[5]={bt('bob','Bobcompa'),bt('bob','Bobcompb')},[6]={bt('alice','Alicecompa'),bt('alice','Alicecompb')}}),lead,peer)
  assert(table.getn(runs)==4 and runs[1].kind=='GRANT' and runs[1].packets>=20,'first GRANT was not the full run: '..tostring(runs[1] and runs[1].packets))
  for k=2,table.getn(runs) do assert(runs[k].packets==1,runs[k].kind..' '..runs[k].step..' took '..runs[k].packets..' packets') end
  bound('short hand-offs'); settled('short hand-offs',lead,peer,board)
  raid=nil; queued=nil
 end)
 -- Ten accounts: Alice leads; Bob to Judy are nine linked accounts, each hiring from its
 -- main and an alt ending in "a". Each account's player takes a raid slot, so 30 companions
 -- fill a 40-man raid. Every row is hired once by its own account, every command goes out
 -- once after the last hire, and each account gets the full run once. Interleaved slot by
 -- slot, 39 hires make 39 hire steps and ten commands steps, beyond the old 48-step cap.
 local TEN={'Alice','Bob','Carol','Dave','Erin','Frank','Grace','Heidi','Ivan','Judy'}
 local tenKinds={{'warrior','mdps','default'},{'mage','rdps','frost'},{'priest','healer','default'},{'warlock','rdps','default'}}
 local function tenAccounts(name,b,seconds)
  world={};trace={};at={};parts={};runs={};elapsed=0;states={}
  local saved={}; for k,m in ipairs(TEN) do saved[k]=ids[string.lower(m)]; ids[string.lower(m)]='10000000000000'..string.format('%02d',k) end
  local cl={}
  for k,m in ipairs(TEN) do cl[k]=client(m,100+7000*(k-1)) end
  local lead=cl[1]
  for k=2,10 do
   trust(lead,TEN[k],{TEN[k]..'a'}); trust(cl[k],'Alice')
   cl[k].C.AccountReadLocal(characters({TEN[k],TEN[k]..'a'})); cl[k].env.ShirsRaidBuilderMainFrame:Hide()
  end
  lead.C.AccountReadLocal(characters({'Alice','Alicea'}))
  local e={}; for i=1,40 do e[i]=b[i] or {kind='empty'} end
  lead:preset().entries=e
  lead:preset().denyRules={{class='warrior',role='mdps',abilities={'Bloodthirst'}}}
  lead:preset().setupRules={{class='mage',role='all',spec='all',drink='30',magic='None'}}
  raid={members={},pending={},early=false}; queued=true
  for k=1,10 do serveRaid(cl[k]); table.insert(raid.members,{name=TEN[k]}) end
  execute(lead,seconds)
  local run=lead.env.ShirsRaidBuilderDB.handoff.active
  assert(run,name..': no run; '..tostring(lead.C.handNotice))
  for k,h in ipairs(cl) do
   local r=h.env.ShirsRaidBuilderDB.handoff and h.env.ShirsRaidBuilderDB.handoff.active
   assert(r and r.id==run.id and r.phase=='done',name..': '..TEN[k]..' did not finish: '..tostring(r and r.phase)..' '..tostring(h.C.handNotice))
  end
  local function owner(a) for _,m in ipairs(TEN) do if a==m or a==m..'a' then return string.lower(m) end end end
  local wanted,seen,lastHire,firstWhisper={},{},0,nil
  for i=1,40 do local r=b[i]; if r and r.kind=='normal' then local line=owner(r.account)..' hires '..invite(r.account,r.class,r.role,r.spec); wanted[line]=(wanted[line] or 0)+1 end end
  for i,line in ipairs(trace) do
   if string.find(line,' hires ',1,true) then seen[line]=(seen[line] or 0)+1; lastHire=i end
   if not firstWhisper and string.find(line,' whispers ',1,true) then firstWhisper=i end
  end
  for line,n in pairs(wanted) do assert(seen[line]==n,name..': hired '..tostring(seen[line] or 0)..' of '..n..': '..line) end
  for line,n in pairs(seen) do assert(wanted[line]==n,name..': unplanned hire: '..line) end
  assert(firstWhisper and firstWhisper>lastHire,name..': a command went out before the last hire')
  local got,warriors,mages,deny,drink={},0,0,0,0
  for i=1,40 do local r=b[i]; if r and r.kind=='normal' then if r.class=='warrior' then warriors=warriors+1 elseif r.class=='mage' then mages=mages+1 end end end
  for _,line in ipairs(trace) do
   local _,_,who,target,text=string.find(line,'^(%a+) whispers ([%a%-]+): (.+)$')
   if who then local key=target..': '..text; got[key]=(got[key] or 0)+1 end
  end
  for key,n in pairs(got) do
   assert(n==1,name..': sent '..n..' times: '..key)
   if string.find(key,'deny add Bloodthirst',1,true) then deny=deny+1 end
   if string.find(key,'set drink 30',1,true) then drink=drink+1 end
  end
  assert(deny==warriors and drink==mages,name..': commands reached '..deny..' of '..warriors..' warriors and '..drink..' of '..mages..' mages')
  local full={}
  for _,r in ipairs(runs) do
   if r.packets>1 then
    local who=r.steps[r.step].actor
    assert(r.kind=='GRANT' and not full[who],name..': long '..r.kind..' '..r.step..' ('..r.packets..' packets)')
    full[who]=true
   end
  end
  for k=2,10 do assert(full[TEN[k]],name..': '..TEN[k]..' never got the full run') end
  for k,m in ipairs(TEN) do ids[string.lower(m)]=saved[k] end
  raid=nil; queued=nil
  return run
 end
 scenario('ten accounts, 30 hires in board order',function()
  local b={}
  for i=1,30 do
   local m=TEN[math.floor((i-1)/3)+1]; local c=tenKinds[math.mod(i-1,4)+1]
   b[i]=hire(math.mod(i-1,3)<2 and m or m..'a',c[1],c[2],c[3])
  end
  b[31]={kind='player',charName='Alice',class='priest',role='rdps'}
  local run=tenAccounts('ten accounts, 30 hires',b,900)
  assert(table.getn(run.steps)==25,'ten accounts, 30 hires: '..table.getn(run.steps)..' steps')
 end)
 scenario('ten accounts, 39 hires slot by slot',function()
  local b={}
  for i=1,39 do
   local m=TEN[math.mod(i-1,10)+1]; local c=tenKinds[math.mod(i-1,4)+1]
   b[i]=hire(i<=20 and m or m..'a',c[1],c[2],c[3])
  end
  b[40]={kind='player',charName='Alice',class='priest',role='rdps'}
  local run=tenAccounts('ten accounts, 39 hires slot by slot',b,1500)
  assert(table.getn(run.steps)==49,'ten accounts slot by slot: '..table.getn(run.steps)..' steps')
 end)
 observe=nil
 -- A legacy character that Bob's trusted snapshot lists is hired by Bob, alone in its group
 -- or beside one of Alice's own hires; one leader Execute, Bob's builder hidden.
 local function bobLegacy() return {kind='legacy',charName='Bobleg',sourceName='Bobleg',class='mage',role='rdps'} end
 scenario('linked legacy alone in a group',function()
  local board={[1]=bobLegacy()}
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt','Bobleg'},{'Bob','Bobalt','Bobleg'})
  execute(lead,60); show('linked legacy alone')
  match('linked legacy alone',expected(board,{{'bob',1,1}}),lead,peer)
  settled('linked legacy alone',lead,peer,board)
 end)
 scenario('linked legacy beside a local hire',function()
  local board={[1]=hire('Alicia','mage','rdps','frost'),[2]=bobLegacy()}
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt','Bobleg'},{'Bob','Bobalt','Bobleg'})
  execute(lead,90); show('linked legacy beside')
  match('linked legacy beside',expected(board,{{'alice',1,1},{'bob',2,2}}),lead,peer)
  assert(shape(runs[1])=='1=Alice@1-1,1=Bob@2-2','linked legacy chunks: '..shape(runs[1]))
  pacing('linked legacy beside'); settled('linked legacy beside',lead,peer,board)
 end)
 -- A group change mid-transfer: RAID_ROSTER_UPDATE and PARTY_MEMBERS_CHANGED reach every
 -- registered handler on both clients while the GRANT is half sent. The link survives and
 -- the run completes.
 scenario('roster event during a GRANT transfer',function()
  local board={[1]=normal('Alicia'),[6]=normal('Bobalt')}
  local lead,peer=start(board,{'Alice','Alicia'},{'Bobalt'},{'Bob','Bobalt'})
  lead:click(lead.env.ShirsRaidBuilderMainFrame.executeBtn)
  local fired
  for _=1,360 do
   pump(0.25)
   local t=lead.C.handTransfer
   if not fired and t and t.kind=='GRANT' and t.progress.sent>=3 and t.progress.sent<t.progress.total then
    fired=t.progress.sent..'/'..t.progress.total
    for _,h in ipairs(world) do
     for _,ev in ipairs({'RAID_ROSTER_UPDATE','PARTY_MEMBERS_CHANGED'}) do
      h.env.event=ev
      for _,w in ipairs(h.frames) do if w.events[ev] and w.scripts.OnEvent then h:fire(w,'OnEvent') end end
     end
    end
   end
  end
  show('roster event mid-transfer, fired at packet '..tostring(fired))
  assert(fired,'fixture never caught the GRANT mid-transfer')
  match('roster mid-transfer',expected(board,{{'alice',1,5},{'bob',6,10}}),lead,peer)
  bound('roster mid-transfer'); settled('roster mid-transfer',lead,peer,board)
 end)
 -- The plan lives only on the account that presses Execute. Bob has only logged in: his
 -- builder was never opened (no window exists), another plan of his is open with its own
 -- rule, and in the second case the builder was left in Sort mode. The grant carries the
 -- board, rules and legacy commands, so Bob runs exactly the leader's chunk, and his own
 -- plan, mode and window stay as they were.
 local function fire(h,ev)
  h.env.event=ev
  for _,w in ipairs(h.frames) do if w.events[ev] and w.scripts.OnEvent then h:fire(w,'OnEvent') end end
 end
 for _,mode in ipairs({'hire','sort'}) do
  local m=mode
  scenario('plan only on the leader, participant in '..m..' mode, builder never opened',function()
   world={};trace={};at={};parts={};runs={};elapsed=0;states={}
   local mine={kind='normal',account='Bob',class='warrior',role='tank',race='human',gender='male',tier='t2r',spec='default'}
   local saved={currentPreset='Bob plan',uiMode=m,peerLinks={},peerSnapshots={},presets={['Bob plan']={entries={[1]=mine},
    denyRules={{class='mage',role='rdps',abilities={'Blizzard'}}},setupRules={}}}}
   local lead=client('Alice',100); local peer=client('Bob',7000,saved,true)
   serve(peer); fire(peer,'VARIABLES_LOADED')
   trust(lead,'Bob',{'Bobalt','Bobleg'}); trust(peer,'Alice')
   lead.C.AccountReadLocal(characters({'Alice','Alicia'})); peer.C.AccountReadLocal(characters({'Bob','Bobalt','Bobleg'}))
   fire(peer,'PLAYER_ENTERING_WORLD'); pump(10)
   assert(not peer.env.ShirsRaidBuilderMainFrame,'fixture opened the participant builder')
   local before=snapshot(peer.env.ShirsRaidBuilderDB.presets)
   local board={[1]=hire('Alicia','mage','rdps','frost'),[6]=hire('Bobalt','mage','rdps','frost'),
    [7]={kind='legacy',charName='Bobleg',sourceName='Bobleg',class='mage',role='rdps',denyList={'Frost Nova'}}}
   local e={}; for i=1,40 do e[i]=board[i] or {kind='empty'} end
   lead:preset().entries=e
   execute(lead,90); show('plan only on the leader, '..m..' mode')
   match('plan only on the leader, '..m,expected(board,{{'alice',1,5},{'bob',6,10},{'bob'}},{[3]={'bob whispers Bobleg-lite: deny add Frost Nova'}}),lead,peer)
   assert(not peer.env.ShirsRaidBuilderMainFrame,'the run opened the participant builder')
   local db=peer.env.ShirsRaidBuilderDB
   assert(db.uiMode==m and db.currentPreset=='Bob plan' and snapshot(db.presets)==before,'the run changed the participant plan or mode')
   bound('plan only on the leader, '..m); settled('plan only on the leader, '..m,lead,peer,board)
  end)
 end
 assert(table.getn(failed)==0,table.getn(failed)..' investigation scenario(s) failed:\n'..table.concat(failed,'\n\n'))
end
print("Shir's Raid Builder run authorization tests: PASS")
