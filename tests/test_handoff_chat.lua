-- Display and protocol share the same event sequence. Exact Lua 5.0.3 only.
-- No game input, real chat or spending. The optional client source is a local,
-- read-only QA input, never a shipped dependency or bundled Blizzard code.
local f=assert(io.open('test_individual_editor.lua','r')); local fixture=f:read('*a'); f:close()
local boundary=assert(string.find(fixture,'\nlocal failures, passes=',1,true))
local source=string.sub(fixture,1,boundary-1)
local count
source,count=string.gsub(source,'local function boot%(saved, player%)','local function boot(saved, player, chatSetup)',1)
assert(count==1)
source,count=string.gsub(source,'    env.ShirsRaidBuilderDB=saved or',
 '    if chatSetup then chatSetup(env,frames,messages,widget) end\n    env.ShirsRaidBuilderDB=saved or',1)
assert(count==1)
local boot=assert(loadstring(source..'\nreturn boot'))()
local exactChat
local path=os.getenv('SRB_CHAT_FRAME_SOURCE')
if path then
 local file=assert(io.open(path,'r')); local text=file:read('*a'); file:close()
 local first=assert(string.find(text,'function ChatFrame_OnEvent(event)',1,true))
 local last=assert(string.find(text,'\nfunction ChatFrame_OnUpdate(',first,true))
 exactChat=string.sub(text,first,last-1)
end
local failures,passes=0,0
local function test(name,fn)
 local ok,err=pcall(fn)
 if ok then passes=passes+1; print('PASS '..name)
 else failures=failures+1; print('FAIL '..name..': '..tostring(err)) end
end
local function snapshot(v)
 if type(v)~='table' then return type(v)..':'..tostring(v) end
 local rows={}; for k,x in pairs(v) do table.insert(rows,snapshot(k)..'='..snapshot(x)) end
 table.sort(rows); return '{'..table.concat(rows,',')..'}'
end
local function pack(...) return arg end
local globals={'this','event','arg1','arg2','arg3','arg4','arg5','arg6','arg7','arg8','arg9'}
local function client(name,style,prior)
 local windows,rendered,history,calls={},{},{},{}
 local function setup(e,frames,messages,widget)
  e.strsub=string.sub; e.strlen=string.len; e.gsub=string.gsub; e.format=string.format
  e.TEXT=function(x) return x end; e.getglobal=function(k) return e[k] end
  e.CHAT_WHISPER_GET='%s whispers: '; e.CHAT_WHISPER_INFORM_GET='To %s: '
  e.CHAT_MONSTER_WHISPER_GET='%s whispers: '; e.CHAT_SAY_GET='%s says: '
  e.ChatTypeInfo={WHISPER={r=1,g=0.5,b=1,id=1},WHISPER_INFORM={r=1,g=0.5,b=1,id=2},
   SYSTEM={r=1,g=1,b=0,id=3},MONSTER_WHISPER={r=1,g=0.5,b=1,id=4},SAY={r=1,g=1,b=1,id=5}}
  e.ChatEdit_SetLastTellTarget=function(box,who) box.lastTell=who end
  e.PlaySound=function() end; e.FCF_FlashTab=function() end; e.CHAT_TELL_ALERT_TIME=1
  for i=1,2 do
   local w=widget('ScrollingMessageFrame','ChatFrame'..i,e.UIParent)
   w.editBox={}; w.defaultLanguage='Common'; w.channelList={}; w.zoneChannelList={}
   w.AddMessage=function(self,text,...) table.insert(rendered,{frame=self,text=text,args=arg}) end
   -- pfUI 5.4.17 formats/caches through AddMessage, not a replacement receiver.
   if style=='pfUI' then
    local previous=w.AddMessage; w.HookAddMessage=previous
    w.AddMessage=function(self,text,...) table.insert(history,{frame=self,text=text}); return previous(self,text,unpack(arg)) end
   end
   for _,ev in ipairs({'CHAT_MSG_WHISPER','CHAT_MSG_WHISPER_INFORM','CHAT_MSG_SYSTEM','CHAT_MSG_MONSTER_WHISPER','CHAT_MSG_SAY'}) do w:RegisterEvent(ev) end
   w:SetScript('OnEvent',function() return e.ChatFrame_OnEvent(e.event) end)
   table.insert(windows,w)
  end
  if exactChat then
   local fn=assert(loadstring(exactChat)); setfenv(fn,e); fn()
  else
   e.ChatFrame_OnEvent=function(ev,...)
    local text=e.arg1
    if ev=='CHAT_MSG_WHISPER' then text=e.arg2..' whispers: '..text
    elseif ev=='CHAT_MSG_WHISPER_INFORM' then text='To '..e.arg2..': '..text end
    e.this:AddMessage(text,1,0.5,1)
   end
  end
  local previous=e.ChatFrame_OnEvent
  e.ChatFrame_OnEvent=function(ev,...)
   table.insert(calls,{event=ev,args=arg,this=e.this,text=e.arg1,other=e.arg2,third=e.arg3})
   if prior then return prior(e,ev,unpack(arg)) end
   return previous(ev,unpack(arg))
  end
 end
 local h=boot(nil,name,setup); h.name=name; h.now=100; h.wall=1800000000
 h.env.GetTime=function() return h.now end; h.env.time=function() return h.wall end
 h.env.SendAddonMessage=function() end; h.env.SendChatMessage=function() end
 h.rendered=rendered; h.history=history; h.displayCalls=calls; h.windows=windows; h.deliveries=0; h.queue={}; h.sent={}
 h.C.peerAutoAttempted=nil
 -- The actual addon init installs after file-load hooks; no UI toggle or game input.
 for _,w in ipairs(h.frames) do
  if w.events.VARIABLES_LOADED then h.env.event='VARIABLES_LOADED'; h:fire(w,'OnEvent') end
 end
 h.env.event=nil
 local driver=h.C.peerDriver; assert(driver and driver.events.CHAT_MSG_WHISPER)
 local receive=driver:GetScript('OnEvent')
 driver:SetScript('OnEvent',function() h.deliveries=h.deliveries+1; return receive() end)
 return h
end
local function display(h,ev,text,other,...)
 local e=h.env; local old={}
 for _,k in ipairs(globals) do old[k]=e[k] end
 e.event=ev; e.arg1=text; e.arg2=other; e.arg3=''; e.arg4=''; e.arg5=''; e.arg6=''; e.arg7=0; e.arg8=0; e.arg9=''
 local out
 for _,w in ipairs(h.windows) do e.this=w; out=pack(e.ChatFrame_OnEvent(ev,unpack(arg))) end
 for _,k in ipairs(globals) do e[k]=old[k] end
 return out
end
local function deliver(h,ev,text,other,displayFirst)
 local e=h.env; local old={}; for _,k in ipairs(globals) do old[k]=e[k] end
 e.event=ev; e.arg2=other
 if displayFirst then display(h,ev,text,other) end
 for _,w in ipairs(h.frames) do
  if w.events[ev] and w.scripts.OnEvent and w~=h.windows[1] and w~=h.windows[2] then h:fire(w,'OnEvent',text) end
 end
 if not displayFirst then display(h,ev,text,other) end
 for _,k in ipairs(globals) do e[k]=old[k] end
end
local ids={alice='1111111111111111',bob='2222222222222222'}
local function trust(h,peer,alts,account)
 local C,db=h.C,h.env.ShirsRaidBuilderDB
 local s=C.PeerNew(h.name,peer,'FixtureRealm'); s.phase='linked'; assert(C.LinkSave(db.peerLinks,s,account~=false))
 local rows={{name=peer,level=60,dungeonLicense='t1d',raidLicense='t2r',observed=h.wall-600}}
 for _,n in ipairs(alts or {}) do table.insert(rows,{name=n,level=60,dungeonLicense='t1d',raidLicense='t2r',observed=h.wall-600}) end
 db.peerSnapshots['FixtureRealm;'..string.lower(peer)]={accountId=ids[string.lower(peer)],source=string.lower(peer),realm='FixtureRealm',
  received=h.wall-600,observed=h.wall-600,entries=rows,authoritative=false}
 C.LicenseRestoreSaved(); db.syncAccountId=ids[string.lower(h.name)]
end
local function wireState(C,from,to)
 local s=assert(C.PeerNew(from,to,'FixtureRealm'))
 s.phase='linked'; s.a='100001'; s.b='100002'; s.expires=1800000060; s.started=100; s.deadline=160
 return s
end
local function inventory(C,from,to)
 local s=wireState(C,from,to); local all={}
 local function add(label,text) assert(type(text)=='string',label); table.insert(all,{label=label,text=text}) end
 for _,kind in ipairs({'INVITE','ACCEPT','CONFIRM','READY','REJECT'}) do
  local b=s.b; if kind=='INVITE' or kind=='REJECT' then s.b='-' end
  add('SRBLINK2 '..kind,C.LinkPacket(s,kind)); s.b=b
 end
 for _,kind in ipairs({'GET','GETONCE'}) do add('SRBLIC2 '..kind,C.LicensePacket(s,kind,'200001')) end
 add('SRBLIC2 DATA',C.LicensePacket(s,'DATA','200001',1,1,'Alicia','t1d','t2r',1800000000))
 for _,known in ipairs({false,true}) do
  add('SRBRAID3 '..(known and 'EMPTY' or 'UNKNOWN'),C.RaidPackets(s,'200002',{known=known,observed=1800000000,entries={}})[1])
 end
 add('SRBRAID3 DATA',C.RaidPackets(s,'200003',{known=true,observed=1800000000,entries={{name='Molten Core',id=1,readyAt=1800003600,scheduled=false}}})[1])
 local rows={{name='Alicia',level=60,dungeonLicense='t1d',raidLicense='t2r',observed=1800000000,faction='Alliance',raidObserved=1800000000,saves={0,1,0,0}}}
 for _,text in ipairs(assert(C.AccountPackets(s,'200004','1111111111111111',rows,1800000000))) do add('SRBACC4 '..assert(C.AccountParse(text)).kind,text) end
 local oldrow=C.AccountPackets(s,'200005','1111111111111111',{{name='Alicia',level=60,dungeonLicense='t1d',raidLicense='t2r',observed=1800000000}},1800000000)[2]
 add('SRBACC4 old ROW',oldrow)
 local h=assert(C.HandCreate({entries={[1]={kind='legacy',charName='First',class='mage',role='rdps'},[6]={kind='normal',account='Bob',class='mage',role='rdps'}}},
  'Run','Alice','FixtureRealm',{'Alice','Bob'},'1234567890123456',1800000000))
 for _,kind in ipairs({'GRANT','REPORT','PAUSE'}) do
  h.kind=kind; h.accounts={ids.alice,ids.bob}; h.expires=1800007200; h.step=2
  for _,text in ipairs(assert(C.HandPackets(s,assert(C.HandEncode(h)),'200006',1800000000,100))) do add('SRBHAND5 H6 '..kind,text) end
  add('SRBHAND5 H7 '..kind,C.HandPackets(s,assert(C.HandShort(h)),'200007',1800000000,100)[1])
 end
 h.kind=nil; h.accounts=nil
 for _,text in ipairs(assert(C.HandPackets(s,assert(C.HandEncode(h)),'200008',1800000000,100))) do add('SRBHAND5 H5 legacy',text) end
 return all
end

test('all handoff transport classes hidden in both directions, delivered once',function()
 for _,style in ipairs({'stock','pfUI'}) do
  local h=client('Alice',style); trust(h,'Bob')
  for _,direction in ipairs({'incoming','outgoing'}) do
   local incoming=direction=='incoming'; local from=incoming and 'Bob' or 'Alice'; local to=incoming and 'Alice' or 'Bob'
   local ev=incoming and 'CHAT_MSG_WHISPER' or 'CHAT_MSG_WHISPER_INFORM'
   for i,row in ipairs(inventory(h.C,from,to)) do
    local before,cache,received=table.getn(h.rendered),table.getn(h.history),h.deliveries
    deliver(h,ev,row.text,'Bob',math.mod(i,2)==0)
    assert(table.getn(h.rendered)==before,style..' '..direction..' rendered '..row.label)
    assert(table.getn(h.history)==cache,'pfUI history captured '..row.label)
    assert(h.deliveries==received+(incoming and 1 or 0),direction..' delivery count changed: '..row.label)
   end
  end
 end
end)

test('human whispers, lookalikes, companion replies and errors pass unchanged',function()
 local h=client('Alice','pfUI'); trust(h,'Bob')
 local packet=inventory(h.C,'Bob','Alice')[1].text
 local cases={{'CHAT_MSG_WHISPER','Hello, are you ready?','Bob'},
  {'CHAT_MSG_WHISPER','Please inspect '..packet,'Bob'},{'CHAT_MSG_WHISPER','SRBHAND5; hello there','Bob'},
  {'CHAT_MSG_WHISPER','SRBLINK2;INVITE;FixtureRealm;Bob;Alice;bad;-;1800000060','Bob'},
  {'CHAT_MSG_WHISPER','SRBLINK2;INVITE;FixtureRealm;Bob;Alice;100001;100002;1800000060','Bob'},
  {'CHAT_MSG_WHISPER','SRBLINK2;CONFIRM;FixtureRealm;Bob;Alice;100001;-;1800000060','Bob'},
  {'CHAT_MSG_WHISPER','SRBHAND5;FixtureRealm;Bob;Alice;100001;100002;900001;1800000060;1;1;hello','Bob'},
  {'CHAT_MSG_WHISPER','SRBHAND5;FixtureRealm;Bob;Alice;100001;100002;900001;1800000060;1;2;human prose','Bob'},
  {'CHAT_MSG_WHISPER',packet..';extra prose','Bob'}, {'CHAT_MSG_WHISPER_INFORM','Are you ready?','Bob'},
  {'CHAT_MSG_WHISPER','Not enough gold to hire this companion.','Bobcomp'},
  {'CHAT_MSG_WHISPER','Unknown command.','Bob'}, {'CHAT_MSG_SYSTEM','Player not found.',''},
  {'CHAT_MSG_MONSTER_WHISPER',packet,'Bob'}, {'CHAT_MSG_SAY',packet,'Bob'},
  {'CHAT_MSG_WHISPER',packet,'Mallory'}, -- not the packet sender
  {'CHAT_MSG_WHISPER',inventory(h.C,'Mallory','Alice')[1].text,'Mallory'}, -- not trusted
  {'CHAT_MSG_WHISPER',inventory(h.C,'Bob','Carol')[1].text,'Bob'}, -- wrong target
  {'CHAT_MSG_WHISPER_INFORM',packet,'Bob'}, -- wrong direction
  {'CHAT_MSG_WHISPER',string.gsub(packet,'FixtureRealm','OtherRealm'),'Bob'}}
 -- Standalone plan sharing is outside this handoff filter's five wire families.
 local s=wireState(h.C,'Bob','Alice')
 local plan=assert(h.C.PlanEncode({entries={{kind='legacy',charName='First'}}},'hire','Shared'))
 table.insert(cases,{'CHAT_MSG_WHISPER',h.C.PlanPackets(s,plan,'900001',h.wall,h.now)[1],'Bob'})
 for _,row in ipairs(cases) do
  local shown,called,cache=table.getn(h.rendered),table.getn(h.displayCalls),table.getn(h.history)
  display(h,row[1],row[2],row[3])
  assert(table.getn(h.rendered)==shown+2,'ordinary text hidden: '..row[2])
  assert(table.getn(h.history)==cache+2 and table.getn(h.displayCalls)==called+2,'prior/pfUI chain bypassed: '..row[2])
  assert(h.displayCalls[called+1].text==row[2] and h.displayCalls[called+1].other==row[3],'globals changed before original handler')
 end
 -- Direct operational status never enters the whisper filter.
 h.C.OpenHandoff(); h.C.HandStatus('Paused: group could not run; check submitted hires.')
 assert(h.C.handFrame.message:GetText()=='Paused: group could not run; check submitted hires.','pause status hidden')
 local messages=table.getn(h.messages); h.env.DEFAULT_CHAT_FRAME:AddMessage('Whisper submission failed; check connection.')
 assert(table.getn(h.messages)==messages+1,'direct error chat hidden')
end)

test('display does not change protocol state; late duplicates stay hidden',function()
 local h=client('Alice','pfUI'); trust(h,'Bob')
 local s=wireState(h.C,'Alice','Bob'); h.C.SyncSelect(s,true); h.C.peerState=s; h.C.SyncStore()
 local packets=inventory(h.C,'Bob','Alice')
 local before=snapshot({db=h.env.ShirsRaidBuilderDB,sessions=h.C.peerSessions})
 for _,row in ipairs(packets) do display(h,'CHAT_MSG_WHISPER',row.text,'Bob') end
 assert(snapshot({db=h.env.ShirsRaidBuilderDB,sessions=h.C.peerSessions})==before,'display mutated auth, session, queue or SavedVariables')
 h.C.PeerClear(s,'completed'); h.C.HandStore().active=nil; h.now=1000; h.wall=1800001000
 local shown=table.getn(h.rendered)
 for _,row in ipairs(packets) do
  deliver(h,'CHAT_MSG_WHISPER',row.text,'Bob',true); deliver(h,'CHAT_MSG_WHISPER',row.text,'Bob',false)
 end
 assert(table.getn(h.rendered)==shown,'expired/duplicate transport became visible')
 assert(not h.C.handAuthority and not s.handProposal,'late packet gained authority')
 -- A revoked character binding is respected even under account-wide trust.
 h.env.ShirsRaidBuilderDB.peerLinks[h.C.LinkKey('Alice','Bob','FixtureRealm',false)]={revoked=true}
 display(h,'CHAT_MSG_WHISPER',packets[1].text,'Bob')
 assert(table.getn(h.rendered)==shown+2,'revoked peer still suppressed')
 local scoped=client('Carol'); trust(scoped,'Bob',nil,false)
 scoped.env.UnitName=function() return 'Alice' end
 display(scoped,'CHAT_MSG_WHISPER',packets[1].text,'Bob')
 assert(table.getn(scoped.rendered)==2,'character-only link widened to another character')
end)

test('old and later hooks, nil APIs, varargs and returns remain safe',function()
 local received
 local h=client('Alice','stock',function(e,ev,...) received={event=ev,args=arg,this=e.this,text=e.arg1,third=e.arg3}; return 'prior',nil,'tail',nil end)
 trust(h,'Bob')
 local installed=h.env.ChatFrame_OnEvent
 assert(type(h.C.InstallHandoffChatFilter)=='function','display installer missing')
 for i=1,3 do h.C.InstallHandoffChatFilter() end
 assert(h.env.ChatFrame_OnEvent==installed,'repeat install wrapped itself')
 local laterCalls=0
 h.env.ChatFrame_OnEvent=function(ev,...) laterCalls=laterCalls+1; return installed(ev,unpack(arg)) end
 h.C.InstallHandoffChatFilter()
 local e=h.env; e.this=h.windows[1]; e.event='CHAT_MSG_WHISPER'; e.arg1='hello'; e.arg2='Bob'; e.arg3='Common'
 local out=pack(e.ChatFrame_OnEvent('CHAT_MSG_WHISPER',nil,17,nil))
 assert(out.n==4 and out[1]=='prior' and out[2]==nil and out[3]=='tail' and out[4]==nil,'original return values truncated')
 assert(received.args.n==3 and received.args[1]==nil and received.args[2]==17 and received.args[3]==nil,'original varargs truncated')
 assert(received.event=='CHAT_MSG_WHISPER' and received.this==h.windows[1] and received.text=='hello' and received.third=='Common','legacy globals changed')
 assert(e.this==h.windows[1] and e.arg1=='hello' and e.event=='CHAT_MSG_WHISPER','wrapper altered globals')
 e.arg1=inventory(h.C,'Bob','Alice')[1].text; received=nil
 e.ChatFrame_OnEvent('CHAT_MSG_WHISPER')
 assert(not received and laterCalls==2,'existing/later hook ordering broke filtering')
 -- Calls with missing optional game APIs must fall through without error.
 e.UnitName=false; e.ChatFrame_OnEvent('CHAT_MSG_WHISPER'); assert(received,'missing UnitName swallowed chat')
 e.UnitName=function() return 'Alice' end; e.GetRealmName=false; received=nil; e.ChatFrame_OnEvent('CHAT_MSG_WHISPER'); assert(received)
 local absent=client('Alice'); absent.env.ChatFrame_OnEvent=nil; absent.C.handChatFilter=nil
 assert(absent.C.InstallHandoffChatFilter()==false and absent.env.ChatFrame_OnEvent==nil,'invented a missing chat API')
 local later=function() return 'available' end; absent.env.ChatFrame_OnEvent=later
 assert(absent.C.InstallHandoffChatFilter()==true and absent.env.ChatFrame_OnEvent~=later,'missing dispatcher could not be installed once available')
 -- A recipient without this addon still renders the original wire; no sender rewrite.
 received=nil; installed=h.env.ChatFrame_OnEvent
 local plain=client('Bob','pfUI'); plain.env.ChatFrame_OnEvent=function(ev) plain.windows[1]:AddMessage(plain.env.arg1) end
 display(plain,'CHAT_MSG_WHISPER',inventory(h.C,'Alice','Bob')[1].text,'Alice')
 assert(table.getn(plain.rendered)==2,'non-addon recipient was somehow filtered')
end)

-- Actual Execute -> renewal -> GRANT -> participant queue -> REPORT -> leader advance.
-- Simulated native events and server timing only; all execution code is production.
local world,elapsed,hires,transfers,classes,echoes={},0,{},{},{},0
local function normal(account) return {kind='normal',account=account,class='mage',role='rdps',spec='frost',tier='t2r',race='human',gender='female'} end
local function runClient(name,alts)
 local h=client(name,'pfUI'); h.base=name=='Alice' and 100 or 7000; h.now=h.base
 local rows={}; for _,n in ipairs(alts) do table.insert(rows,{name=n,level=60,dungeonLicense='t1d',raidLicense='t2r'}) end
 h.C.AccountReadLocal(rows)
 h.env.SendChatMessage=function(text,route,lang,target)
  if route=='SAY' then
   if string.find(text,'^%.z addinvite ') and text~='.z addinvite list' then table.insert(hires,name..' '..text) end
   return
  end
  assert(route=='WHISPER' and lang==nil,'transport changed')
  table.insert(h.sent,{text=text,target=target}); table.insert(h.queue,{text=text,target=target})
  local p=h.C.LinkParse(text) or h.C.LicenseParse(text) or h.C.RaidParse(text) or h.C.AccountParse(text) or h.C.HandParse(text)
  assert(p,'unexpected run whisper: '..text)
  local family=string.sub(text,1,assert(string.find(text,';',1,true))-1)
  classes[family..' '..(p.kind or 'packet')]=(classes[family..' '..(p.kind or 'packet')] or 0)+1
  local before=table.getn(h.rendered); deliver(h,'CHAT_MSG_WHISPER_INFORM',text,target,true); echoes=echoes+1
  assert(table.getn(h.rendered)==before,'outgoing run packet rendered: '..text)
  local hp=h.C.HandParse(text)
  if hp then
   local key=p.sender..';'..p.nonce; if hp.index==1 then transfers[key]={} end
   table.insert(transfers[key],hp.data)
  end
 end
 table.insert(world,h); return h
end
local function pump(seconds)
 for i=1,seconds*4 do
  elapsed=elapsed+0.25
  for _,h in ipairs(world) do
   h.now=h.base+elapsed; h.wall=1800000000+math.floor(elapsed)
   for _,w in ipairs(h.frames) do if w.scripts.OnUpdate and w:IsVisible() then h:fire(w,'OnUpdate',0.25) end end
  end
  for _,from in ipairs(world) do
   while table.getn(from.queue)>0 do
    local row=table.remove(from.queue,1)
    for _,to in ipairs(world) do
     if string.lower(to.name)==string.lower(row.target) then
      local shown,n=table.getn(to.rendered),to.deliveries
      deliver(to,'CHAT_MSG_WHISPER',row.text,from.name,math.mod(to.deliveries,2)==0)
      assert(to.deliveries==n+1,'incoming run delivered other than once')
      assert(table.getn(to.rendered)==shown,'incoming run packet rendered: '..row.text)
     end
    end
   end
  end
 end
end
local function start(missing,offline)
 world={};elapsed=0;hires={};transfers={};classes={};echoes=0
 local a=runClient('Alice',{'Alice','Alicia','Aliana'})
 local b
 if not offline then b=runClient('Bob',missing and {'Bob'} or {'Bob','Bobalt','Bobina'}) end
 trust(a,'Bob',{'Bobalt','Bobina'}); if b then trust(b,'Alice',{'Alicia','Aliana'}); b.env.ShirsRaidBuilderMainFrame:Hide() end
 local board={}; for i=1,40 do board[i]={kind='empty'} end
 for g=1,6 do board[(g-1)*5+1]=normal(g<=3 and 'Alicia' or 'Aliana'); board[(g-1)*5+2]=normal(g<=3 and 'Bobalt' or 'Bobina') end
 a:preset().entries=board; a:click(a.env.ShirsRaidBuilderMainFrame.executeBtn)
 return a,b
end

test('one Execute completes linked run with renewals and no rendered transport',function()
 local a,b=start(false,false); local peerBoard=snapshot(b:preset())
 pump(400)
 local run=a.C.HandStore().active
 assert(run and run.phase=='done' and not a.C.handAuthority and not b.C.handAuthority,'linked run failed: '..tostring(a.C.handNotice))
 assert(table.getn(hires)==12,'missing or duplicated hires: '..table.getn(hires))
 for g=1,6 do
  local localName=g<=3 and 'Alicia' or 'Aliana'; local peerName=g<=3 and 'Bobalt' or 'Bobina'
  assert(string.find(hires[2*g-1],'Alice .z addinvite '..localName,1,true)==1 and string.find(hires[2*g],'Bob .z addinvite '..peerName,1,true)==1,'handoff order changed')
 end
 assert(classes['SRBLINK2 INVITE']>=2 and classes['SRBLINK2 ACCEPT']>=2 and classes['SRBLINK2 CONFIRM']>=2 and classes['SRBLINK2 READY']>=2,'renewal handshake not exercised')
 local kinds={}
 for _,parts in pairs(transfers) do
  local wire=table.concat(parts); local p=a.C.HandDecode(wire) or a.C.HandShortParse(wire)
  assert(p,'incomplete run transfer'); kinds[p.kind]=(kinds[p.kind] or 0)+1
 end
 assert(kinds.GRANT==6 and kinds.REPORT==6,'GRANT/REPORT progression changed')
 assert(table.getn(a.rendered)==0 and table.getn(b.rendered)==0 and table.getn(a.history)==0 and table.getn(b.history)==0,'protocol remained in chat/history')
 assert(echoes>0 and a.deliveries>0 and b.deliveries>0,'no actual display/receive sequence exercised')
 assert(snapshot(b:preset())==peerBoard,'filter changed participant profile')
 deliver(a,'CHAT_MSG_WHISPER','Ready for the next raid?','Bob',true)
 deliver(b,'CHAT_MSG_WHISPER','Yes, thank you.','Alice',false)
 assert(table.getn(a.rendered)==2 and table.getn(b.rendered)==2,'human whispers hidden after run')
 print('TRACE linked run: 12 ordered hires, 6 GRANT, 6 REPORT, '..classes['SRBLINK2 INVITE']..' link invitations; '..echoes..' outgoing echoes hidden')
end)

test('refusal packets hidden but actionable pause and timeout remain visible',function()
 local a,b=start(true,false); pump(120)
 local run=a.C.HandStore().active
 assert(run.phase=='interrupted' and not a.C.handAuthority and not b.C.handAuthority,'refusal did not pause leader')
 assert(table.getn(hires)==1,'refusal spent more than initial local hire')
 local pause=false
 for _,parts in pairs(transfers) do local p=a.C.HandDecode(table.concat(parts)); if p and p.kind=='PAUSE' then pause=true end end
 assert(pause and string.find(tostring(a.C.handNotice),'Bob',1,true) and string.find(tostring(b.C.handNotice),'Paused',1,true),'PAUSE or status missing')
 a.C.OpenHandoff()
 assert(string.find(a.C.handFrame.message:GetText(),'Paused:',1,true) and table.getn(a.rendered)==0 and table.getn(b.rendered)==0,'actionable status hidden or PAUSE payload shown')
 a=start(false,true); pump(120)
 assert(a.C.HandStore().active.phase=='interrupted' and not a.C.handAuthority and table.getn(hires)==1,'offline renewal retried or continued')
 assert(string.find(tostring(a.C.handNotice),'did not answer',1,true),'offline failure invisible: '..tostring(a.C.handNotice))
 display(a,'CHAT_MSG_SYSTEM','Player not found.','')
 assert(table.getn(a.rendered)==2,'server transport error hidden')
end)

assert(failures==0,failures..' handoff chat test(s) failed')
print("Shir's Raid Builder handoff chat tests: PASS ("..passes..' scenarios; '..(exactChat and 'exact local ChatFrame_OnEvent' or 'stock display stand-in')..')')
