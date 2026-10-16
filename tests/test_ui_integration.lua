-- Exact Lua 5.0.3 integration checks over all three real UI/transport paths.
-- Synthetic native widgets, clock and messages only; no game/server QA claim.
local f=assert(io.open('test_handoff_chat.lua','r')); local text=f:read('*a'); f:close()
local at=assert(string.find(text,"\ntest('all handoff transport classes hidden",1,true))
local fixture=assert(loadstring(string.sub(text,1,at-1)..'\nreturn {client=client,display=display,deliver=deliver,trust=trust,wireState=wireState,inventory=inventory,snapshot=snapshot}'))()
local failures,passes=0,0
local function test(name,fn)
 local ok,err=pcall(fn)
 if ok then passes=passes+1; print('PASS '..name) else failures=failures+1; print('FAIL '..name..': '..tostring(err)) end
end
local function normal(who)
 return {kind='normal',account=who,tier='t2r',class='mage',role='rdps',spec='frost',race='human',gender='female'}
end
local function refresh(h)
 local main=h.env.ShirsRaidBuilderMainFrame
 main:Hide(); h.env.SlashCmdList.SHIRSRAIDBUILDER('')
end
local function start(name)
 local h=fixture.client(name or 'Alice','pfUI')
 h.C.AccountReadLocal({{name=h.name,level=60,dungeonLicense='t2d',raidLicense='t3r',faction='Alliance'}})
 h:preset().entries={}; for i=1,40 do h:preset().entries[i]={kind='empty'} end
 h:preset().entries[1]={kind='player',charName=h.name,class='warrior',role='tank'}
 h:preset().denyRules={}; h:preset().setupRules={}; refresh(h)
 h.sent={}; h.queries={}
 h.env.SendChatMessage=function(command,route,lang,target) table.insert(h.sent,{command=command,route=route,target=target}) end
 h.env.SendAddonMessage=function(prefix,query) table.insert(h.queries,{prefix=prefix,query=query}) end
 return h
end
local function toggle(h,on)
 local w=assert(h.env.ShirsRaidBuilderMainFrame.quietCheck,'integrated Quiet checkbox missing')
 w:SetChecked(on and 1 or nil); h:click(w)
 assert(h.env.ShirsRaidBuilderDB.quietMode==on,'Vanilla check state did not normalize')
end
local function status(h)
 for _,w in ipairs(h.env.ShirsRaidBuilderMainFrame.fonts) do
  if w.point and w.point[1]=='BOTTOMLEFT' and w.point[4]==22 and w.point[5]==16 then return w end
 end
 error('main status missing')
end
local function empty(h,index)
 local group=math.floor((index-1)/5); local col=index-1-group*5
 for _,w in ipairs(h.frames) do
  if w.kind=='Button' and w:IsVisible() and w.fonts[1] and w.fonts[1]:GetText()=='empty'
   and w.point and w.point[4]==2+col*102 and w.point[5]==-21-group*51 then return w end
 end
 error('visible empty slot missing')
end
local function quick(h,branch,source,tier)
 h:click(empty(h,9)); local q=assert(h.env.ShirsRaidBuilderQuickHire,'integrated quick dialog missing')
 h:choose(q.sourceButton,source or h.name)
 h:click(h:button(q,branch)); h:click(h:button(q,'DPS'))
 if branch=='Class' then
  h:click(h:button(q,'Mage')); h:choose(q.raceButton,'Gnome'); h:choose(q.genderButton,'Female'); h:choose(q.specButton,'Fire')
 end
 h:choose(q.tierButton,tier or 't1d') -- Existing explicit-Add integration scenarios.
 return q
end
local function pump(h,seconds)
 for i=1,seconds*4 do
  h.now=h.now+0.25; h.wall=1800000000+math.floor(h.now-100)
  for _,w in ipairs(h.frames) do if w.scripts.OnUpdate and w:IsVisible() then h:fire(w,'OnUpdate',0.25) end end
 end
end
local function live(h,other)
 fixture.trust(h,other)
 local s=fixture.wireState(h.C,h.name,other)
 assert(h.C.SyncSelect(s,true)); h.C.peerState=s; h.C.SyncStore()
 return s
end
local function incoming(h,s,grant,nonce)
 local tx=fixture.wireState(h.C,s.peerLabel,h.name)
 tx.a=s.a; tx.b=s.b; tx.expires=s.expires; tx.started=h.now; tx.deadline=h.now+60
 for _,packet in ipairs(assert(h.C.HandPackets(tx,assert(h.C.HandEncode(grant)),nonce,h.wall,h.now))) do
  fixture.deliver(h,'CHAT_MSG_WHISPER',packet,s.peerLabel,true)
 end
end
local function stopped(h)
 h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Stop'))
end

 test('all three real controls compose without changing agreed geometry or tooltip ownership',function()
 local h=start(); local main=h.env.ShirsRaidBuilderMainFrame
 local q=assert(main.quietCheck,'Quiet checkbox missing')
 assert(q.point[4]==642 and q.point[5]==-30 and main.handProgress==nil,'Quiet geometry changed or obsolete status returned')
 assert(main.plannerBtn and main.plannerBtn.point[4]==310 and main.plannerBtn.point[5]==-8,'planner launcher changed its reserved top-bar location')
 assert(main.stopBtn and main.stopBtn.point[4]==510 and main.stopBtn.point[5]==-76)
 local lines={}; h.env.GameTooltip.AddLine=function(self,line) table.insert(lines,line) end
 h:fire(q,'OnEnter'); assert(h.env.GameTooltip:IsVisible() and string.find(table.concat(lines,' '),'Stop',1,true))
 h:fire(q,'OnLeave'); assert(not h.env.GameTooltip:IsVisible())
 local before=fixture.snapshot(h:preset()); local menu=quick(h,'Class')
 h:click(h:button(menu,'Cancel')); assert(fixture.snapshot(h:preset())==before and table.getn(h.sent)==0 and table.getn(h.queries)==0)
end)

for _,branch in ipairs({'Random','Class'}) do
 local branch=branch
 test(branch..' explicit tier and saved intent survive Quiet Preview Execute and Stop; no quick spend',function()
  local h=start(); local q=quick(h,branch,'Alice','t1d')
  toggle(h,false); toggle(h,true); h:click(h:button(q,'Add'))
  local row=h:preset().entries[9]; local command=assert(h.C.BuildNormalHireCommand(row))
  assert(row.kind=='normal' and row.account=='Alice' and row.tier=='t1d','tier/schema changed')
  if branch=='Class' then assert(command=='.z addinvite Alice t1d mage rdps fire gnome female') end
  assert(table.getn(h.sent)==0 and table.getn(h.queries)==0,'quick flow spent or queried')
  local board=fixture.snapshot(h:preset()); h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Preview'))
  local printed=false; for _,message in ipairs(h.messages) do if string.find(message,command,1,true) then printed=true end end
  assert(printed and table.getn(h.sent)==0,'Quiet hid explicit Preview or Preview sent')
  h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn)
  assert(table.getn(h.sent)==1 and h.sent[1].command==command and h.sent[1].route=='SAY','real Execute differs from quick Preview')
  stopped(h); local notice=status(h):GetText(); local n=table.getn(h.sent)
  toggle(h,false); toggle(h,true); pump(h,35)
  assert(status(h):GetText()==notice and string.find(notice,'stopped',1,true),'Stop status disappeared under Quiet')
  assert(table.getn(h.sent)==n and fixture.snapshot(h:preset())==board,'Stop/late timer changed row or submitted more work')
 end)
end

test('a quick dialog opened before linked Execute closes without hiding handoff or Stop recovery status',function()
 local h=start(); live(h,'Bob')
 h:preset().entries[2]=normal('Bob'); refresh(h)
 local q=quick(h,'Class','Alice','t1d'); local before=fixture.snapshot(h:preset())
 h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn)
 local run=assert(h.C.HandStore().active); assert(run.phase=='waiting' and h.C.handAuthority,'remote-first fixture did not freeze')
 local notice=h.C.handNotice; pump(h,0.25)
 assert(not q:IsVisible(),'quick dialog survived a frozen plan')
 assert(fixture.snapshot(h:preset())==before and status(h):GetText()==h.C.handNotice,'quick cleanup hid essential handoff status')
 assert(notice and string.find(h.env.ShirsRaidBuilderMainFrame.stopBtn.tip,'waiting',1,true))
 h.C.HandPause('Paused: missing ownership. Refresh Synchronization, then Stop before Execute.')
 stopped(h); notice=h.C.handNotice
 toggle(h,false); toggle(h,true); pump(h,15)
 assert(string.find(notice,'missing ownership',1,true) and status(h):GetText()==notice,'Stop/Quiet hid previous failure reason')
 assert(string.find(h.env.ShirsRaidBuilderMainFrame.stopBtn.tip,notice,1,true),'Stop hover lost recovery')
 assert(run.phase=='cancelled' and not h.C.handAuthority and not h.C.handTransfer and not h.C.handAwaitLink)
end)

test('Quiet still delivers a real GRANT; main Stop rejects a late nonce and quick-add cannot mutate its frozen plan',function()
 local h=start('Bob'); local s=live(h,'Alice')
 local menu=quick(h,'Random','Bob','t1d'); local before=fixture.snapshot(h:preset())
 local g=assert(h.C.HandCreate({entries={[1]=normal('Bob'),[6]=normal('Alice')}},h.C.HandWireName('Name/with/slash'),'Alice','FixtureRealm',{'Bob','Alice'},'1234567890123456',h.wall,nil,nil,true))
 g.kind='GRANT'; g.accounts={'2222222222222222','1111111111111111'}; g.expires=h.wall+7200
 incoming(h,s,g,'800001'); h.C.HandTick()
 assert(h.C.handAuthority and h.C.HandStore().active and table.getn(h.sent)==1,'Quiet lost receive or grant execution')
 local handoffStatus=h.C.handNotice
 h:click(h:button(menu,'Add'))
 assert(not menu:IsVisible() and fixture.snapshot(h:preset())==before and table.getn(h.sent)==1,'quick add changed receiving active plan')
 assert(status(h):GetText()==handoffStatus,'quick Add refusal hid essential handoff status')
 stopped(h); local notice=h.C.handNotice; local n=table.getn(h.sent); local received=h.deliveries
 incoming(h,s,g,'800002'); h.C.HandTick(); pump(h,15)
 assert(h.deliveries>received and table.getn(h.rendered)==0,'Quiet stopped native delivery or leaked protocol')
 assert(table.getn(h.sent)==n and h.C.HandStore().active.phase=='cancelled' and not h.C.handAuthority,'late nonce resumed stopped work')
 assert(h.C.handNotice==notice and status(h):GetText()==notice,'late receipt/Quiet hid Stop reason')
 assert(fixture.snapshot(h:preset())==before,'receiving profile changed')
end)

test('partial handoff Stop keeps Quiet recovery and user whispers while shared controls remain usable',function()
 local h=start('Bob'); local s=live(h,'Alice')
 local g=assert(h.C.HandCreate({entries={[1]=normal('Bob'),[6]=normal('Alice')}},'Partial','Alice','FixtureRealm',{'Bob','Alice'},'1234567890123456',h.wall,nil,nil,true))
 g.kind='GRANT'; g.accounts={'2222222222222222','1111111111111111'}; g.expires=h.wall+7200
 local tx=fixture.wireState(h.C,'Alice','Bob')
 local packets=assert(h.C.HandPackets(tx,assert(h.C.HandEncode(g)),'800003',h.wall,h.now))
 fixture.deliver(h,'CHAT_MSG_WHISPER',packets[1],'Alice',true); assert(s.handInput)
 stopped(h); local notice=h.C.handNotice; assert(string.find(notice,'Refresh Synchronization',1,true))
 incoming(h,s,g,'800004'); h.C.HandTick()
 assert(not h.C.HandStore().active and not h.C.handAuthority and table.getn(h.sent)==0)
 toggle(h,false); toggle(h,true); assert(status(h):GetText()==notice)
 fixture.deliver(h,'CHAT_MSG_WHISPER','Stop here, please.','Alice',false)
 assert(table.getn(h.rendered)==2,'human whisper hidden after partial Stop')
 local q=quick(h,'Class','Bob','t0d'); h:click(h:button(q,'Cancel'))
 assert(status(h):GetText()==notice,'cancel of fresh quick menu hid handoff recovery')
end)

assert(failures==0,failures..' integrated UI regression(s) failed')
print("Shir's Raid Builder integrated UI tests: PASS ("..passes..' scenarios)')
