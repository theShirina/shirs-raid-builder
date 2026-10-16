-- Exact Lua 5.0.3; real Execute, six-field discovery, setup and rerun, synthetic world only.
local f=assert(io.open('test_quick_followup.lua','r')); local text=f:read('*a'); f:close()
local at=assert(string.find(text,"\ntest('shared normal",1,true))
local start=assert(loadstring(string.sub(text,1,at-1)..'\nreturn start'))()
local failures,passes=0,0
local function test(name,fn)
 local ok,err=pcall(fn)
 if ok then passes=passes+1; print('PASS '..name) else failures=failures+1; print('FAIL '..name..': '..tostring(err)) end
end
local function exercise(missing)
 local h=start(); local C=h.C; local clock=100; local p=h:preset()
 C.AccountReadLocal({{name='Alice',level=60,dungeonLicense='t2d',raidLicense='t3r',faction='Alliance'}})
 p.entries[2]={kind='normal',account='Alice',class='random',role='dps',tier='t1r'}
 p.entries[3]={kind='normal',account='Alice',class='mage',role='rdps',tier='t1r',spec='fire',race='human',gender='female'}
 p.entries[4]={kind='legacy',charName='Legacy',class='mage',role='rdps',denyList={}}
 p.denyRules={{class='mage',role='rdps',abilities={'Frost Nova'}},{class='warrior',role='mdps',abilities={'Cleave'}}}
 p.setupRules={{class='mage',role='all',magic='amplify'}}
 local records={{name='Legacy-lite',class='mage',role='rdps',owner='Alice'},{name='Existing',class='mage',role='rdps',owner='Alice'}}
 local party={'Legacy-lite','Existing'}; local sent,replies,joins,acks={},{},{},{}
 h.env.GetTime=function() return clock end
 h.env.GetNumPartyMembers=function() return table.getn(party) end
 h.env.UnitName=function(unit)
  if unit=='player' then return 'Alice' end
  local _,_,i=string.find(tostring(unit),'^party(%d+)$'); return i and party[tonumber(i)]
 end
 h.env.SendChatMessage=function(command,route,language,target)
  table.insert(sent,{command=command,route=route,target=target})
  if command=='.z addi Alice t1r dps' then table.insert(joins,{at=clock+1,name='Randomwar'})
  elseif route=='SAY' then error('concrete/legacy was hired despite verified presence: '..command)
  elseif route=='WHISPER' then table.insert(acks,{at=clock+0.25,name=target}) end
 end
 h.env.SendAddonMessage=function(prefix,query)
  assert(prefix=='nexus' and query=='GRINFO:ALL:FULL')
  if missing then return end
  local rows={}; for _,r in ipairs(records) do table.insert(rows,r.name..':Human:'..r.class..':'..r.role..':Uncommon:'..r.owner) end
  table.insert(replies,'[nexus] GRINFO:ALL:FULL '..table.concat(rows,' '))
 end
 local function event(ev,text,sender)
  h.env.event=ev; h.env.arg2=sender
  for _,w in ipairs(h.frames) do if w.events[ev] and w.scripts.OnEvent then h:fire(w,'OnEvent',text) end end
 end
 local function pump()
  for i=1,300 do
   clock=clock+0.25
   while joins[1] and joins[1].at<=clock do
    local join=table.remove(joins,1); table.insert(party,join.name)
    table.insert(records,{name=join.name,class='warrior',role='mdps',owner='Alice'})
   end
   while acks[1] and acks[1].at<=clock do local ack=table.remove(acks,1); event('CHAT_MSG_TEXT_EMOTE',ack.name..' nods at you.',ack.name) end
   for _,w in ipairs(h.frames) do if w:IsVisible() and w.scripts.OnUpdate then h:fire(w,'OnUpdate',0.25) end end
   while replies[1] do event('CHAT_MSG_ADDON',table.remove(replies,1),'nexus') end
  end
 end
 h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Preview')); assert(table.getn(sent)==0)
 if missing then
  -- No current group => this case starts one hire, but absent metadata cannot expand random group commands.
  party={}; records={}; p.entries[3]={kind='empty'}; p.entries[4]={kind='empty'}
 end
 h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn); pump()
 local hires=0; local targets={}
 for _,row in ipairs(sent) do
  if row.route=='SAY' then hires=hires+1; assert(row.command=='.z addi Alice t1r dps')
  elseif row.route=='WHISPER' then targets[(row.target or '')..' '..row.command]=true end
 end
 assert(hires==1,'random not hired exactly once, or concrete reservation stolen')
 assert(p.entries[2].class=='random' and p.entries[2].role=='dps' and p.entries[2].spec==nil,'discovery persisted invented concrete intent')
 if missing then
  assert(not targets['Randomwar deny add Cleave'],'missing metadata invented command target')
  local warned=false; for _,message in ipairs(h.messages) do if string.find(message,'No companion list',1,true) then warned=true end end
  assert(warned,'missing discovery was silently accepted')
 else
  assert(targets['Randomwar deny add Cleave'],'actual warrior outcome lost its matching deny')
  assert(not targets['Randomwar deny add Frost Nova'],'random was falsely assumed to be mage')
  assert(targets['Existing deny add Frost Nova'] and targets['Legacy-lite deny add Frost Nova'],'concrete/legacy setup lost')
  assert(targets['Existing set magic amplify'] and targets['Legacy-lite set magic amplify'],'concrete/legacy Mage setup lost')
  local before=table.getn(sent); h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn); pump()
  for i=before+1,table.getn(sent) do assert(sent[i].route~='SAY','owner-scoped rerun hired existing random again') end
 end
end

test('real mixed random/concrete/legacy Execute discovers actual class and reruns without paid duplicates',function() exercise(false) end)
test('real random Execute with missing metadata never invents setup or deny targets',function() exercise(true) end)

test('real linked role-only Execute retains source and tier through two handoffs, discovery and rerun',function()
 -- Reuse the established multi-client world. Only its synthetic server learns the
 -- new short command; addon handlers, transport and execution remain untouched.
 local file=assert(io.open('test_normal_legacy.lua','r')); local body=file:read('*a'); file:close()
 local boundary=assert(string.find(body,"\ntest('local first ten",1,true))
 body=string.sub(body,1,boundary-1)
 local parser="local _,_,owner,class,role=string.find(text,'^%.z addinvite (%a+) %w+ (%a+) (%a+) ')"
 local first,last=string.find(body,parser,1,true); assert(first,'synthetic server parser moved')
 local addition=[[
   -- Fixed server fixtures are observed outcomes, never addon class selection.
   if not owner then
    local _,_,randomOwner,randomRole=string.find(text,'^%.z addi (%a+) %w+ (%a+)$')
    if randomOwner then
     owner=randomOwner
     if randomRole=='tank' then class='druid'; role='tank'
     elseif randomRole=='healer' then class='priest'; role='healer'
     elseif randomRole=='dps' then class='mage'; role='rdps'
     else error('invalid synthetic random role') end
    end
   end
 ]]
 body=string.sub(body,1,last)..'\n'..addition..string.sub(body,last+1)
 local run=assert(loadstring(body..'\nreturn run'))()
 local function concrete(owner,class,role)
  return {kind='normal',account=owner,class=class,role=role,tier='t1r',spec='default',race='human',gender='female'}
 end
 local plan={entries={},denyRules={{class='mage',role='rdps',abilities={'Frost Nova'}},
  {class='priest',role='healer',abilities={'Holy Nova'}},{class='druid',role='tank',abilities={'Swipe'}}},
  setupRules={{class='mage',role='all',magic='amplify'}}}
 for i=1,40 do plan.entries[i]={kind='empty'} end
 plan.entries[1]={kind='normal',account='Alice',class='random',role='dps',tier='t1d'}
 plan.entries[2]=concrete('Alice','mage','rdps')
 plan.entries[3]={kind='legacy',charName='Alice',class='mage',role='rdps',denyList={}}
 plan.entries[6]={kind='normal',account='Tankalt',class='random',role='healer',tier='t2r'}
 plan.entries[7]=concrete('Tankalt','priest','healer')
 plan.entries[11]={kind='normal',account='Localmage',class='random',role='tank',tier='t1d'}
 local initial={'Existingmage','Existingpriest','Alice-lite'}
 local records={{name='Existingmage',class='mage',role='rdps',owner='Alice'},
  {name='Existingpriest',class='priest',role='healer',owner='Tankalt'},
  {name='Alice-lite',class='mage',role='rdps',owner='Alice'}}
 local result=run(plan,true,initial,records)
 local expected={{actor='Alice',command='.z addi Alice t1d dps'},
  {actor='Bob',command='.z addi Tankalt t2r healer'},
  {actor='Alice',command='.z addi Localmage t1d tank'}}
 local hires,targets={},{}
 for _,row in ipairs(result.sent) do
  if row.route=='SAY' then table.insert(hires,row)
  elseif row.route=='WHISPER' and (string.find(row.text,'^deny ') or string.find(row.text,'^set ')) then targets[(row.target or '')..' '..row.text]=true end
 end
 assert(table.getn(hires)==3,'wildcard stole concrete or legacy reservation, or missed a hire')
 for i,wanted in ipairs(expected) do assert(hires[i].actor==wanted.actor and hires[i].text==wanted.command,'source/tier/role/actor changed during handoff') end
 assert(result.a.env.ShirsRaidBuilderDB.handoff.active.phase=='done','linked random run did not finish')
 local grants=0; for _,line in ipairs(result.trace) do if string.find(line,'GRANT',1,true) then grants=grants+1 end end
 assert(grants>=1,'fixture bypassed real grant transport')
 local seen={}; for key in pairs(targets) do table.insert(seen,key) end; table.sort(seen)
 assert(targets['Compa deny add Frost Nova'] and targets['Compa set magic amplify'],'actual random Mage lost setup or deny: '..table.concat(seen,' | '))
 assert(targets['Compb deny add Holy Nova'] and targets['Compc deny add Swipe'],'remote/local random outcomes lost role denies')
 assert(targets['Existingmage deny add Frost Nova'] and targets['Alice-lite deny add Frost Nova'],'concrete or legacy commands lost')
 for _,slot in ipairs({1,6,11}) do assert(plan.entries[slot].class=='random' and plan.entries[slot].spec==nil,'discovery rewrote saved intent') end
 local rerun=run(plan,true,result.members,result.records)
 for _,row in ipairs(rerun.sent) do assert(row.route~='SAY','linked rerun paid for an existing companion') end
end)
assert(failures==0,tostring(failures)..' random runtime regression(s) failed')
print("Shir's Raid Builder random runtime tests: PASS ("..passes..' cases)')
