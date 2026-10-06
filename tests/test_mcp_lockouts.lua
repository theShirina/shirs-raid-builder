dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')
local C=ShirsRaidBuilderCore
assert(type(C.MCPLockSnapshot)=='function','MCP-only snapshot adapter missing')
local now,up=1800000000,100
local r=C.MCPLockSnapshot({},now,up)
assert(r.known and table.getn(r.entries)==0,'empty live locks are free, not schedule saves')
r=C.MCPLockSnapshot({{map=409,id=12,resetAt=200,cost=0}},now,up)
assert(r.known and C.SavedRaidLabels(r.entries,now)=='MC','zero-cost live lock is saved')
assert(C.RaidCopySnapshot(r),'MCP snapshot must fit peer wire format')
assert(C.MCPLockSnapshot({{map=409,id=12,resetAt=200.5}},now,100.25).known,'fractional GetTime rejected')
for _,map in ipairs({249,309,509,999}) do
 r=C.MCPLockSnapshot({{map=map,id=12,resetAt=200}},now,up)
 assert(r.known and table.getn(r.entries)==0,'untracked raid leakage')
end
for _,v in ipairs({0,100,-1,math.huge,'200',{},0/0}) do
 r=C.MCPLockSnapshot({{map=409,id=12,resetAt=v}},now,up)
 assert(not r.known or table.getn(r.entries)==0,'unsafe reset')
end
local untimed=C.MCPLockSnapshot({{map=409,id=12}},now,up)
assert(untimed.known and C.SavedRaidLabels(untimed.entries,now)=='MC','MCP real lock with unknown reset lost saved marker')
assert(C.RaidCopySnapshot(untimed),'untimed saved snapshot lost at peer boundary')
assert(not C.MCPLockSnapshot({[2]={map=409,id=12,resetAt=200}},now,up).known,'sparse lock data cannot clear saves')
local f=assert(io.open('test_individual_editor.lua','r'));local s=f:read('*a');f:close()
local pos=assert(string.find(s,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(s,1,pos-1)..'\nreturn boot'))()
local h=boot(); C=h.C; local e=h.env
local wall,uptime=now,up
e.time=function() return wall end;e.GetTime=function() return uptime end
local realm='Realm';e.GetRealmName=function() return realm end
local player=e.UnitName('player')
local staleAlts={{name='Oldalt',level=60,locks={{map=469,id=2,resetAt=300}}}}
e.MCP_SelfLockData={locks={},alts=staleAlts}
e.arg1='[nexus] ACINFO:SELFLOCK:HEAD 1:3:50:2:0'; C.RaidLocalEvent()
e.arg1='[nexus] ACINFO:SELFLOCK:END'; C.RaidLocalEvent()
e.MCP_SelfLockData={locks={},alts=staleAlts}; C.RaidReadLocal()
assert(not C.mcpRows.oldalt,'first self-only response re-aged preserved alt data')
local send={};e.MCP_Send=function(cmd) table.insert(send,cmd) end
-- This existing MCP API routes by group, so requests must use explicit SAY.
e.SendChatMessage=function(msg,route) assert(route=='SAY');table.insert(send,msg) end
e.MCP_SelfLockProto=2
e.GetNumSavedInstances=function() return 1 end
e.GetSavedInstanceInfo=function() return 'Molten Core',9,1000 end
e.ShirsLazyTrixDB={cooldownsByCharacter={}}
C.PeerContextOK=function() return true end
local function receipt(data)
 e.arg1='[nexus] ACINFO:SELFLOCK:HEAD 1:3:50';C.RaidLocalEvent()
 e.arg1='[nexus] ACINFO:SELFLOCK:END';C.RaidLocalEvent()
 e.MCP_SelfLockData=data
 C.RaidReadLocal()
end
C.RaidRequestLocal();C.RaidRequestLocal();assert(table.getn(send)==1,'duplicate refresh')
local alts={{name='Offline',level=60,locks={{map=469,id=2,resetAt=300}}},{name=player,level=60,locks={{map=533,id=3,resetAt=300}}}}
receipt({locks={},alts=alts,sched={{map=409,resetAt=900}}})
assert(C.localRaids.known and table.getn(C.localRaids.entries)==0,'native/schedule must not override current free')
local rows=C.AccountReadLocal();local offline
for _,row in ipairs(rows) do
 if row.name=='Offline' then offline=row;assert(C.AccountRaidLabels(row,wall)=='BWL') end
 if row.name==player then assert(C.AccountRaidLabels(row,wall)=='','current duplicate in alts') end
end
assert(offline,'offline level60 discovery')
local observed=offline.raidObserved
uptime=120;wall=now+20
receipt({locks={{map=409,id=1,resetAt=220,cost=0}},alts=alts})
rows=C.AccountReadLocal()
for _,row in ipairs(rows) do
 if row.name=='Offline' then assert(row.raidObserved==observed,'self-only reply re-aged offline data') end
 if row.name==player then assert(C.AccountRaidLabels(row,wall)=='MC') end
end
receipt({locks={},alts={{name='Offline',level=60,locks={}}}})
for _,row in ipairs(C.AccountReadLocal()) do assert(C.AccountRaidLabels(row,wall)=='','fresh empty must clear') end
-- Nil global support uses getglobal; no dependency on interpreter _G.
local old=e._G;e._G=false;e.getglobal=function(name) return e[name] end
receipt({locks={{map=531,id=1,resetAt=220}},alts={}})
assert(C.RaidRowText(C.localRaids)=='AQ40')
e._G=old
-- Unknown/malformed and missing responses retain advisory saves without re-aging.
local stamp=C.mcpRows[string.lower(player)].observed
wall=wall+1;uptime=uptime+1
receipt({locks={{map=531,id=1,resetAt='invalid'}},alts={}})
assert(C.mcpRows[string.lower(player)].observed==stamp,'unknown reset erased observation')
e.arg1='[nexus] ACINFO:SELFLOCK:HEAD invalid'; C.RaidLocalEvent()
e.arg1='[nexus] ACINFO:SELFLOCK:END'; C.RaidLocalEvent()
e.MCP_SelfLockData={locks={},alts={}}; C.RaidReadLocal()
assert(C.mcpRows[string.lower(player)].observed==stamp,'invalid HEAD cleared known save')
assert(table.getn(C.mcpRows[string.lower(player)].entries)==1,'invalid HEAD cleared save entries')
e.arg1='[nexus] ACINFO:SELFLOCK:HEAD 1:3:50'; C.RaidLocalEvent()
e.arg1='[nexus] ACINFO:SELFLOCK:END'; C.RaidLocalEvent()
uptime=uptime+11;wall=wall+11;C.RaidReadLocal()
assert(not C.mcpPending and C.mcpRows[string.lower(player)].observed==stamp,'timeout refreshed stale data')
receipt({locks={},alts={{name='Offline',level=60,locks={{map=469,id=2,resetAt=300}}}}})
realm='Other';assert(not C.RaidReadLocal().known,'realm cache leakage')
assert(not C.mcpRoster or table.getn(C.mcpRoster)==0,'MCP roster leaked into another realm')
print('MCP lockout tests: PASS')
-- Independent MCP character records through account wire receive and the real sidebar.
do
 ShirsRaidBuilderCore=nil -- each boot must own its Core, not inherit the earlier global core test
 local tank=boot(nil,'Shirtank'); local viewer=boot(nil,'Viewer')
 for _,h in ipairs({tank,viewer}) do
  h.env.time=function() return now end; h.env.GetTime=function() return 100 end
  h.env.UnitLevel=function() return 60 end; h.C.PeerOnBuilderOpen(); h.C.peerAutoAttempted=nil
 end
 local function receiptFor(h,data)
  h.env.arg1='[nexus] ACINFO:SELFLOCK:HEAD 1:3:50:2:1';h.C.RaidLocalEvent()
  h.env.arg1='[nexus] ACINFO:SELFLOCK:END';h.C.RaidLocalEvent()
  h.env.MCP_SelfLockData=data;h.C.RaidReadLocal()
 end
 local alt={name='Shirpriest',level=60,locks={{map=409,id=72}}}
 receiptFor(tank,{locks={{map=409,id=71}},alts={alt}})
 local input={{name='Shirtank',level=60,dungeonLicense='t4d',raidLicense='t4r'},
  {name='Shirpriest',level=60,dungeonLicense='t4d',raidLicense='t4r'}}
 local rows=tank.C.AccountReadLocal(input)
 local found={}
 for _,row in ipairs(rows) do
  if row.name=='Shirtank' or row.name=='Shirpriest' then
   assert(row.raidLicense=='t4r','MCP roster discovery overwrote the known raid license: '..row.name)
   found[row.name]=true;assert(tank.C.AccountRaidLabels(row,now)=='MC' and row.saves[2]==0,'character MCP MC/free state lost: '..row.name..' '..tank.C.AccountRaidLabels(row,now)..' '..tostring(row.raidObserved))
  end
 end
 assert(found.Shirtank and found.Shirpriest,'fixture characters missing')
 local tx=tank.C.PeerNew('Shirtank','Viewer','FixtureRealm')
 local rx=viewer.C.PeerNew('Viewer','Shirtank','FixtureRealm')
 for _,s in ipairs({tx,rx}) do s.phase='linked';s.a='100001';s.b='100002';s.started=100;s.deadline=160;s.expires=now+60 end
 tank.C.LinkSave(tank.env.ShirsRaidBuilderDB.peerLinks,tx,true)
 viewer.C.LinkSave(viewer.env.ShirsRaidBuilderDB.peerLinks,rx,true)
 viewer.C.SyncSelect(rx,true);viewer.C.peerState=rx;viewer.C.SyncStore()
 local function sync(values,nonce)
  viewer.C.LicenseRequest(rx,nonce,100)
  local packets=assert(tank.C.AccountPackets(tx,nonce,'1234567890123456',values,now))
  for _,packet in ipairs(packets) do viewer.env.event='CHAT_MSG_WHISPER';viewer.env.arg1=packet;viewer.env.arg2='Shirtank';viewer.C.PeerEvent() end
  local markers={}
  for _,row in ipairs(viewer.env.ShirsRaidBuilderMainFrame.accountRows) do
   if row.lines[1]:GetText()=='Shirtank - T4R' then markers.tank=row.lines[2]:GetText() end
   if row.lines[1]:GetText()=='Shirpriest - T4R' then markers.priest=row.lines[2]:GetText() end
  end
  return markers
 end
 local markers=sync(rows,'200001');assert(markers.tank=='MC' and markers.priest=='MC','synced orange MC rows missing')
 local stamp=rows[1].raidObserved
 receiptFor(tank,{locks={{map=409,id=71}},alts={alt}}) -- retained table must not re-age the alt
 local retained=tank.C.AccountReadLocal(input)
 for _,row in ipairs(retained) do if row.name=='Shirpriest' then assert(row.raidObserved==stamp) end end
 receiptFor(tank,{locks={{map=409,id=71}},alts={{name='Shirpriest',level=60,locks={}}}})
 markers=sync(tank.C.AccountReadLocal(input),'200002')
 assert(markers.tank=='MC' and markers.priest~='MC','tank lock leaked into independently free priest')
 -- Missing/malformed priest data cannot manufacture a save or borrow tank's lock.
 receiptFor(tank,{locks={{map=409,id=71}},alts={{name='Shirpriest',level=60}}})
 markers=sync(tank.C.AccountReadLocal(input),'200003')
 assert(markers.tank=='MC' and markers.priest~='MC','missing priest data borrowed tank marker')
end
