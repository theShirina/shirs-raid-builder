-- Exact Lua 5.0.3. Real constructors/handlers and protocol, simulated native UI only.
local file=assert(io.open('test_handoff_chat.lua','r')); local fixture=file:read('*a'); file:close()
local boundary=assert(string.find(fixture,"\ntest('all handoff transport classes hidden",1,true))
local helper=assert(loadstring(string.sub(fixture,1,boundary-1)..'\nreturn {client=client,display=display,deliver=deliver,trust=trust,inventory=inventory,snapshot=snapshot}'))()
local client,display,deliver,trust,inventory,snapshot=helper.client,helper.display,helper.deliver,helper.trust,helper.inventory,helper.snapshot
local failures,passes=0,0
local function test(name,fn)
 local ok,err=pcall(fn)
 if ok then passes=passes+1; print('PASS '..name) else failures=failures+1; print('FAIL '..name..': '..tostring(err)) end
end
local function toggle(h,checked)
 local check=assert(h.env.ShirsRaidBuilderMainFrame.quietCheck,'Quiet mode checkbox missing')
 check:SetChecked(checked); h:click(check)
 return check
end

test('real persistent checkbox defaults on and toggles protocol display immediately with 1/nil',function()
 local h=client('Alice','pfUI'); trust(h,'Bob')
 local e=h.env; local main=e.ShirsRaidBuilderMainFrame
 local check=assert(main.quietCheck,'Quiet mode checkbox missing')
 assert(check.kind=='CheckButton' and check:GetChecked()==1 and e.ShirsRaidBuilderDB.quietMode==true,'default must be checked and strict true')
 assert(check:GetWidth()==16 and check:GetHeight()==16 and check.point[4]==642 and check.point[5]==-30,'compact header anchor changed')
 local packet=inventory(h.C,'Bob','Alice')[1].text
 display(h,'CHAT_MSG_WHISPER',packet,'Bob')
 assert(table.getn(h.rendered)==0,'default protocol suppression lost')
 toggle(h,nil)
 assert(check:GetChecked()==nil and e.ShirsRaidBuilderDB.quietMode==false,'nil was not saved as false')
 display(h,'CHAT_MSG_WHISPER',packet,'Bob')
 assert(table.getn(h.rendered)==2 and table.getn(h.history)==2,'uncheck did not restore full protocol chatter')
 toggle(h,1)
 assert(check:GetChecked()==1 and e.ShirsRaidBuilderDB.quietMode==true,'1 was not saved as true')
 display(h,'CHAT_MSG_WHISPER',packet,'Bob')
 assert(table.getn(h.rendered)==2,'check did not restore suppression immediately')
end)

test('hover explains exact hidden and retained categories and cleans up on leave',function()
 local h=client('Alice'); local check=h.env.ShirsRaidBuilderMainFrame.quietCheck
 local tip=h.env.GameTooltip; local lines={}; tip:Hide()
 tip.SetOwner=function(self,owner,anchor) self.owner=owner; self.anchor=anchor end
 tip.AddLine=function(self,text,r,g,b,wrap) table.insert(lines,text); assert(wrap==1,'tooltip must wrap') end
 h:fire(check,'OnEnter')
 assert(tip:IsVisible() and tip.owner==check and tip.anchor=='ANCHOR_RIGHT','tooltip not owned by hovered checkbox')
 assert(tip:GetText()=='Quiet mode' and check.label:GetText()=='Quiet mode','option/tooltip label mismatch')
 local text=table.concat(lines,' ')
 for _,phrase in ipairs({'routine hiring messages','account-sync chatter','Warnings','errors','progress','Preview','replies','Stop'}) do
  assert(string.find(text,phrase,1,true),'tooltip omits '..phrase)
 end
 assert(string.len(text)<340,'Quiet explanation is too long for players')
 for _,phrase in ipairs({'protocol','authentication','GRINFO','transport','both directions'}) do
  assert(not string.find(text,phrase,1,true),'Quiet tooltip contains implementation jargon: '..phrase)
 end
 h:fire(check,'OnLeave'); assert(not tip:IsVisible(),'tooltip remains after leave')
 h.env.GameTooltip=nil; h:fire(check,'OnEnter'); h:fire(check,'OnLeave')
end)

local function serialize(value)
 if type(value)=='table' then
  local parts={}; for k,v in pairs(value) do table.insert(parts,'['..serialize(k)..']='..serialize(v)) end
  return '{'..table.concat(parts,',')..'}'
 elseif type(value)=='string' then return string.format('%q',value)
 elseif type(value)=='number' or type(value)=='boolean' then return tostring(value) end
 error('unsupported saved fixture value')
end

test('saved boolean survives fresh module reload; old or malformed values default on',function()
 local f=assert(io.open('test_individual_editor.lua','r')); local s=f:read('*a'); f:close()
 local at=assert(string.find(s,'\nlocal failures, passes=',1,true))
 local boot=assert(loadstring(string.sub(s,1,at-1)..'\nreturn boot'))()
 for _,checked in ipairs({1,0}) do
  local h=client('Alice'); toggle(h,checked==1 and 1 or nil)
  local saved=assert(loadstring('return '..serialize(h.env.ShirsRaidBuilderDB)))()
  local fresh=boot(saved,'Alice')
  assert(fresh.env.ShirsRaidBuilderDB.quietMode==(checked==1),'saved preference changed on reload')
  assert(fresh.env.ShirsRaidBuilderMainFrame.quietCheck:GetChecked()==(checked==1 and 1 or nil),'reloaded checkbox disagrees')
 end
 for _,bad in ipairs({'missing',1,0,'false',{}}) do
  local saved={quietMode=bad~='missing' and bad or nil,marker='preserve',presets={Default={entries={}}},currentPreset='Default'}
  local fresh=boot(saved,'Alice')
  assert(saved.quietMode==true and fresh.env.ShirsRaidBuilderMainFrame.quietCheck:GetChecked()==1,'default/migration is not strict true')
  assert(saved.marker=='preserve','migration changed unrelated state')
 end
end)

local function statusWidget(h)
 for _,font in ipairs(h.env.ShirsRaidBuilderMainFrame.fonts) do
  if font.point and font.point[1]=='BOTTOMLEFT' and font.point[4]==22 and font.point[5]==16 then return font end
 end
 error('main status line missing')
end
local function contains(rows,text)
 for _,row in ipairs(rows) do if string.find(row,text,1,true) then return true end end
 return false
end
local function runLocal(quiet,options)
 options=options or {}
 local h=client('Alice','pfUI'); toggle(h,quiet and 1 or nil)
 h.C.AccountReadLocal({{name='Alice',level=60,dungeonLicense='t1d',raidLicense='t2r'}})
 local entries={}; for i=1,40 do entries[i]={kind='empty'} end
 entries[1]={kind='normal',account='Alice',tier='t2r',class='warrior',role='tank',spec='default',race='human',gender='female'}
 entries[2]={kind='legacy',charName='Warsoap',class='warrior',role='tank',denyList={'Taunt'}}
 local p=h:preset(); p.entries=entries; p.denyRules={{class='warrior',role='tank',abilities={'Shield Wall'}}}; p.setupRules={}
 local sent,replies,joins,acks,party,records,trace,statuses={},{},{},{},{},{},{},{}
 if options.present then
  party={'Alicecomp','Warsoap-lite'}
  records={{name='Alicecomp',class='warrior',role='tank',owner='Alice'}}
 end
 local line=statusWidget(h); local original=line.SetText
 line.SetText=function(self,text) original(self,text); table.insert(statuses,text) end
 h.env.GetNumPartyMembers=function() return table.getn(party) end
 h.env.UnitName=function(unit)
  if unit=='player' then return 'Alice' end
  local _,_,index=string.find(tostring(unit),'^party(%d+)$'); return index and party[tonumber(index)]
 end
 h.env.SendChatMessage=function(text,route,lang,target)
  table.insert(sent,{at=h.now,text=text,route=route,target=target})
  table.insert(trace,string.format('%.2f %s %s %s',h.now,route,tostring(target),text))
  if route=='WHISPER' then
   if not options.noAck then table.insert(acks,{at=h.now+0.25,target=target}) end
  elseif string.find(text,'^%.z addinvite ') then
   table.insert(joins,{at=h.now+1.5,name='Alicecomp',record={name='Alicecomp',class='warrior',role='tank',owner='Alice'}})
  elseif string.find(text,'^%.z addlegacy ') then table.insert(joins,{at=h.now+1.5,name='Warsoap-lite'}) end
 end
 h.env.SendAddonMessage=function(prefix,text)
  assert(prefix=='nexus' and text=='GRINFO:ALL:FULL','unexpected metadata query')
  table.insert(trace,string.format('%.2f QUERY %s',h.now,text))
  if options.noReply then return end
  local rows={}; for _,r in ipairs(records) do table.insert(rows,r.name..':Human:'..r.class..':'..r.role..':Uncommon:'..r.owner) end
  table.insert(replies,'[nexus] GRINFO:ALL:FULL '..table.concat(rows,' '))
 end
 local function eventAll(ev,text,sender)
  h.env.event=ev; h.env.arg2=sender; h.env.arg3='BATTLEGROUND'
  for _,w in ipairs(h.frames) do if w.events[ev] and w.scripts.OnEvent then h:fire(w,'OnEvent',text) end end
  h.env.event=nil; h.env.arg2=nil; h.env.arg3=nil
 end
 local first=table.getn(h.messages)+1
 h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn)
 for i=1,240 do
  h.now=h.now+0.25
  while joins[1] and joins[1].at<=h.now do
   local j=table.remove(joins,1); table.insert(party,j.name); if j.record then table.insert(records,j.record) end
  end
  while acks[1] and acks[1].at<=h.now do local a=table.remove(acks,1); eventAll('CHAT_MSG_TEXT_EMOTE',a.target..' nods at you.',a.target) end
  for _,w in ipairs(h.frames) do if w.scripts.OnUpdate and w:IsVisible() then h:fire(w,'OnUpdate',0.25) end end
  while replies[1] do eventAll('CHAT_MSG_ADDON',table.remove(replies,1),'nexus') end
 end
 local messages={}; for i=first,table.getn(h.messages) do table.insert(messages,h.messages[i]) end
 return {h=h,sent=sent,trace=trace,statuses=statuses,messages=messages,status=line:GetText()}
end

test('quiet queue hides routine echoes while native sends timing acknowledgments and status stay equal',function()
 local quiet=runLocal(true); local verbose=runLocal(false)
 assert(snapshot(quiet.trace)==snapshot(verbose.trace),'presentation changed native calls or timing')
 assert(snapshot(quiet.statuses)==snapshot(verbose.statuses),'essential status or pacing disappeared')
 assert(quiet.status=='Execution complete. All queued commands were sent.','queue did not finish: '..quiet.status)
 assert(contains(quiet.statuses,'Pacing whispers.') and contains(quiet.statuses,'Waiting for the last companion to join.'),'actual pacing/ack sequence not exercised')
 assert(contains(verbose.messages,'say -> .z addinvite Alice') and contains(verbose.messages,'whisper Warsoap-lite -> deny add Taunt'),'verbose command echoes missing')
 assert(contains(verbose.messages,'Matched ') and contains(verbose.messages,'Asking the server') and contains(verbose.messages,'Received ') and contains(verbose.messages,'Group commands will whisper'),'metadata/matching progress not exercised')
 assert(table.getn(quiet.messages)==0,'quiet routine chatter leaked: '..table.concat(quiet.messages,' | '))
 assert(table.getn(quiet.sent)==5,'hire/deny sends were not all exercised')
end)

test('already-present normal and legacy notices are routine but their denies and final status remain',function()
 local quiet=runLocal(true,{present=true}); local verbose=runLocal(false,{present=true})
 assert(snapshot(quiet.trace)==snapshot(verbose.trace),'present-hire suppression changed sends or timing')
 assert(contains(verbose.messages,'Skipped 1 legacy hire(s)') and contains(verbose.messages,'Skipped 1 normal hire(s)'),'both skip paths not exercised')
 assert(not contains(quiet.messages,'Skipped '),'quiet already-present notice leaked')
 assert(quiet.status=='Execution complete. All queued commands were sent.' and verbose.status==quiet.status,'final state hidden/changed')
 for _,send in ipairs(quiet.sent) do assert(send.route=='WHISPER','already-present companion hired again') end
 assert(table.getn(quiet.sent)==3,'present companions lost their denies')
end)

test('timeouts warnings missing ownership Stop and final states remain visible when quiet',function()
 local q=runLocal(true,{noAck=true}); local v=runLocal(false,{noAck=true})
 assert(contains(q.messages,'No nod from ') and snapshot(q.trace)==snapshot(v.trace),'missing ack warning or pacing changed')
 q=runLocal(true,{noReply=true}); v=runLocal(false,{noReply=true})
 assert(contains(q.messages,'No companion list from the server; group denies were skipped.'),'discovery timeout warning hidden')
 assert(string.find(q.status,'Execution complete.',1,true)==1 and q.status==v.status and snapshot(q.statuses)==snapshot(v.statuses),'timeout final status hidden/changed: '..q.status)
 local h=q.h; local line=statusWidget(h)
 for _,text in ipairs({'Paused: no owner can run the next group. Nothing was sent.','Process timed out. Check submitted hires before starting another run.','Missing ownership: synchronize the hiring account before Execute.'}) do
  h.C.HandStatus(text); assert(line:GetText()==text,'actionable status not on main frame')
  toggle(h,nil); toggle(h,1); assert(line:GetText()==text,'Quiet toggle erased actionable status')
 end
 -- No queue/run remains here. Idle Stop keeps the last actionable warning;
 -- active terminal Stop is exercised by test_stop.lua and the integration suite.
 local beforeStop=line:GetText()
 h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Stop'))
 assert(line:GetText()==beforeStop,'idle Stop hid the last actionable warning')
end)

test('Preview normal whispers refusals and unrelated addon output pass in both modes',function()
 for _,checked in ipairs({1,0}) do
  local h=client('Alice','pfUI'); trust(h,'Bob'); toggle(h,checked==1 and 1 or nil)
  local sent=0; h.env.SendChatMessage=function() sent=sent+1 end
  h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Preview'))
  assert(contains(h.messages,'Preview ') and contains(h.messages,': .z addlegacy '),'explicit Preview hidden')
  assert(sent==0,'Preview/option spent or sent')
  for _,row in ipairs({{'CHAT_MSG_WHISPER','Ready for the raid?','Bob'},
   {'CHAT_MSG_WHISPER_INFORM','Yes, ready.','Bob'},
   {'CHAT_MSG_WHISPER','Not enough gold to hire this companion.','Alicecomp'},
   {'CHAT_MSG_WHISPER','I have blacklisted Taunt.','Alicecomp'},
   {'CHAT_MSG_SYSTEM','Player not found.',''},
   {'CHAT_MSG_WHISPER','SRBHAND5; hello there','Bob'}}) do
   local n=table.getn(h.rendered); deliver(h,row[1],row[2],row[3],true)
   assert(table.getn(h.rendered)==n+2,'ordinary whisper/refusal hidden: '..row[2])
  end
  local n=table.getn(h.messages); h.env.DEFAULT_CHAT_FRAME:AddMessage('Another addon: routine progress')
  assert(table.getn(h.messages)==n+1,'unrelated addon output hidden')
 end
end)

test('every recognized protocol family switches display both ways without losing receive delivery',function()
 for _,style in ipairs({'stock','pfUI'}) do
  local h=client('Alice',style); trust(h,'Bob')
  for _,direction in ipairs({'incoming','outgoing'}) do
   local incoming=direction=='incoming'; local ev=incoming and 'CHAT_MSG_WHISPER' or 'CHAT_MSG_WHISPER_INFORM'
   local from=incoming and 'Bob' or 'Alice'; local to=incoming and 'Alice' or 'Bob'
   for _,row in ipairs(inventory(h.C,from,to)) do
    for _,checked in ipairs({1,0}) do
     toggle(h,checked==1 and 1 or nil)
     local shown,received=table.getn(h.rendered),h.deliveries
     deliver(h,ev,row.text,'Bob',checked==1)
     assert(table.getn(h.rendered)==shown+(checked==1 and 0 or 2),style..' '..direction..' toggle failed for '..row.label)
     assert(h.deliveries==received+(incoming and 1 or 0),'option changed native delivery: '..row.label)
    end
   end
  end
 end
end)

-- Reuse the full two-client transport fixture, not an imitation of handoff logic.
-- Only adapt its display expectations and click the real checkbox before Execute.
local function handoffHarness()
 local f=assert(io.open('test_handoff_chat.lua','r')); local s=f:read('*a'); f:close()
 local head=assert(string.find(s,"\ntest('all handoff transport classes hidden",1,true))
 local first=assert(string.find(s,'-- Actual Execute -> renewal',1,true))
 local last=assert(string.find(s,"\ntest('one Execute completes linked run",first,true))
 local body=string.sub(s,1,head-1)..'\nlocal quietMode=true\n'..string.sub(s,first,last-1)
 local function replace(needle,value)
  local a,b=string.find(body,needle,1,true); assert(a,'fixture anchor missing: '..needle)
  assert(not string.find(body,needle,b+1,true),'fixture anchor is not unique')
  body=string.sub(body,1,a-1)..value..string.sub(body,b+1)
 end
 replace(' h.C.AccountReadLocal(rows)',' h.C.AccountReadLocal(rows)\n local check=h.env.ShirsRaidBuilderMainFrame.quietCheck; check:SetChecked(quietMode and 1 or nil); h:click(check)')
 replace('table.insert(h.sent,{text=text,target=target})','table.insert(h.sent,{at=elapsed,text=text,target=target})')
 replace("assert(table.getn(h.rendered)==before,'outgoing run packet rendered: '..text)","assert(table.getn(h.rendered)==before+(quietMode and 0 or 2),'outgoing display option mismatch: '..text)")
 replace("assert(table.getn(to.rendered)==shown,'incoming run packet rendered: '..row.text)","assert(table.getn(to.rendered)==shown+(to.env.ShirsRaidBuilderDB.quietMode and 0 or 2),'incoming display option mismatch: '..row.text)")
 body=body..[[
 return {start=function(quiet,missing,offline) quietMode=quiet; return start(missing,offline) end,pump=pump,
  result=function()
   local timeline={}; local kinds={}; local deliveries={}
   for _,h in ipairs(world) do
    deliveries[h.name]=h.deliveries
    for _,row in ipairs(h.sent) do
     local p=h.C.LinkParse(row.text) or h.C.LicenseParse(row.text) or h.C.RaidParse(row.text) or h.C.AccountParse(row.text) or h.C.HandParse(row.text)
     table.insert(timeline,string.format('%.2f %s %s %s %s %s',row.at,h.name,row.target,string.sub(row.text,1,assert(string.find(row.text,';',1,true))-1),p.kind or 'packet',p.index or '-'))
    end
   end
   for _,parts in pairs(transfers) do
    local p=world[1].C.HandDecode(table.concat(parts)) or world[1].C.HandShortParse(table.concat(parts)); assert(p)
    kinds[p.kind]=(kinds[p.kind] or 0)+1
   end
   return {hires=hires,classes=classes,timeline=timeline,kinds=kinds,deliveries=deliveries}
  end}
 ]]
 return assert(loadstring(body))()
end

test('same actual linked Execute renewal GRANT REPORT and ordered hires finish quiet or verbose',function()
 local results={}
 for _,quiet in ipairs({true,false}) do
  local harness=handoffHarness(); local a,b=harness.start(quiet,false,false)
  local board=snapshot(b:preset()); harness.pump(400)
  local r=harness.result(); local active=a.C.HandStore().active
  assert(active.phase=='done' and not a.C.handAuthority and not b.C.handAuthority,'linked run failed')
  assert(table.getn(r.hires)==12 and r.kinds.GRANT==6 and r.kinds.REPORT==6,'ordered linked work did not finish once')
  assert(r.classes['SRBLINK2 INVITE']>=2 and r.classes['SRBLINK2 READY']>=2,'renewal was not exercised')
  assert(snapshot(b:preset())==board,'option changed receiving profile')
  for _,h in ipairs({a,b}) do
   if quiet then assert(table.getn(h.rendered)==0 and table.getn(h.history)==0,'quiet protocol leaked')
   else assert(table.getn(h.rendered)>0 and table.getn(h.history)==table.getn(h.rendered),'verbose protocol missing from chat/history') end
   local before=table.getn(h.rendered); display(h,'CHAT_MSG_WHISPER','Ready for the next raid?',h==a and 'Bob' or 'Alice')
   assert(table.getn(h.rendered)==before+2,'normal whisper hidden after handoff')
  end
  table.insert(results,r)
 end
 assert(snapshot(results[1])==snapshot(results[2]),'option changed transport class counts, timing, deliveries, receipts or hires')
end)

test('actual linked refusals and offline timeout still stop visibly in either mode',function()
 for _,quiet in ipairs({true,false}) do
  local x=handoffHarness(); local a,b=x.start(quiet,true,false); x.pump(120)
  assert(a.C.HandStore().active.phase=='interrupted' and not a.C.handAuthority and not b.C.handAuthority,'owner refusal did not pause')
  assert(x.result().kinds.PAUSE and string.find(statusWidget(a):GetText(),'Paused:',1,true),'leader pause invisible')
  assert(string.find(statusWidget(b):GetText(),'Paused',1,true),'participant refusal invisible')
  x=handoffHarness(); a=x.start(quiet,false,true); x.pump(120)
  assert(a.C.HandStore().active.phase=='interrupted' and not a.C.handAuthority,'offline run continued')
  assert(string.find(statusWidget(a):GetText(),'did not answer',1,true),'offline timeout hidden from main status')
 end
end)

assert(failures==0,failures..' quiet mode test(s) failed')
print("Shir's Raid Builder quiet mode tests: PASS ("..passes..' scenarios)')
