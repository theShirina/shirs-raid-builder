-- Real Execute/preflight/linked handoff and command expansion; synthetic server records.
-- The first ten slots mirror the reported shape with generic character names. This does
-- not establish what the live server sent, nor replace in-game QA. Exact Lua 5.0.3.
local f=assert(io.open('test_run_authorization.lua','r')); local source=f:read('*a'); f:close()
local boundary=assert(string.find(source,"\nlocal a=client('Alice',100)",1,true))
local harness=string.sub(source,1,boundary-1)..'\n'..[[
return {client=client,trust=trust,pump=pump,world=world,trace=trace,
 observe=function(fn) observe=function() fn(elapsed) end end}
]]
local failures,passes=0,0
local function test(name,fn)
 local ok,err=pcall(fn)
 if ok then passes=passes+1; print('PASS '..name)
 else failures=failures+1; print('FAIL '..name..': '..tostring(err)) end
end
local function normal(owner,class,role)
 return {kind='normal',account=owner,class=class or 'warrior',role=role or 'mdps',
  tier='t0d',spec='default',race=class=='shaman' and 'troll' or 'human',gender='female'}
end
local function legacy(name,class,role) return {kind='legacy',charName=name,sourceName=name,class=class,role=role,denyList={}} end
local function firstTen(druid,swap)
 local p={entries={},denyRules={{class='warrior',role='mdps',abilities={'Cleave'}},
  {class='warrior',role='tank',abilities={'Thunder Clap'}},{class='shaman',role='mdps',abilities={'Chain Heal'}}},
  setupRules={{class='shaman',role='all',spec='all',air='Grace of Air Totem'}}}
 local e=p.entries
 for i=1,40 do e[i]={kind='empty'} end
 e[1]=normal('Localheal','shaman','healer'); e[2]=normal('Alice'); e[3]=legacy(druid and 'Bearalt' or 'Alice',druid and 'druid' or 'warrior','mdps')
 e[4]=normal('Localmage'); e[5]=legacy('Tankalt','warrior','tank'); e[6]=legacy('Localheal','shaman','mdps')
 e[7]=normal('Localrogue'); e[8]=normal('Alice'); e[9]=normal('Alice','warrior','tank'); e[10]=normal('Alice','warrior','tank')
 e[36]={kind='player',charName='Alice',class='warrior',role='mdps'}
 if swap then e[6],e[7]=e[7],e[6] end
 return p
end
local function said(h,text)
 for _,m in ipairs(h.messages) do if string.find(m,text,1,true) then return true end end
 return false
end
local function run(plan,linked,initial,existing)
 local x=assert(loadstring(harness))()
 local a=x.client('Alice',100); local b
 if linked then b=x.client('Bob',7000) end
 local own={{name='Alice',level=60,dungeonLicense='t1d',raidLicense='t2r'},
  {name='Localheal',level=60,dungeonLicense='t1d',raidLicense='t2r'},
  {name='Localmage',level=60,dungeonLicense='t1d',raidLicense='t2r'},
  {name='Localrogue',level=60,dungeonLicense='t1d',raidLicense='t2r'},
  {name='Bearalt',level=60,dungeonLicense='t1d',raidLicense='t2r'}}
 if not linked then table.insert(own,{name='Tankalt',level=60,dungeonLicense='t1d',raidLicense='t2r'}) end
 a.C.AccountReadLocal(own)
 if b then
  x.trust(a,'Bob',{'Tankalt'}); x.trust(b,'Alice',{'Localheal','Localmage','Localrogue','Bearalt'})
  b.C.AccountReadLocal({{name='Bob',level=60,dungeonLicense='t1d',raidLicense='t2r'},
   {name='Tankalt',level=60,dungeonLicense='t1d',raidLicense='t2r'}})
 end
 local members,records,sent,joins,replies,seq={},{},{},{},{},0
 for _,name in ipairs(initial or {}) do table.insert(members,name) end
 for _,r in ipairs(existing or {}) do table.insert(records,r) end
 -- A human with matching class/role in the roster has no companion GRINFO record.
 table.insert(members,'Humanwar')
 local function contains(name) for _,v in ipairs(members) do if v==name then return true end end end
 local function add(name,class,role,owner)
  if not contains(name) then table.insert(members,name) end
  table.insert(records,{name=name,class=class,role=role,owner=owner})
 end
 for _,client in ipairs(x.world) do
  local h=client
  local old=h.env.SendChatMessage
  h.env.GetNumRaidMembers=function() return table.getn(members)+1+(b and 1 or 0) end
  h.env.GetNumPartyMembers=function() return 0 end
  h.env.UnitName=function(unit)
   if unit=='player' or unit=='raid1' then return h.name end
   local _,_,n=string.find(tostring(unit),'^raid(%d+)$')
   if n then
    n=tonumber(n)
    if b and n==2 then return h==a and 'Bob' or 'Alice' end
    return members[n-1-(b and 1 or 0)]
   end
  end
  h.env.SendChatMessage=function(text,route,language,target)
   table.insert(sent,{actor=h.name,at=h.now-h.base,route=route,target=target,text=text})
   old(text,route,language,target)
   if route~='SAY' then return end
   local _,_,owner,class,role=string.find(text,'^%.z addinvite (%a+) %w+ (%a+) (%a+) ')
   if owner then
    seq=seq+1
    local name=owner=='Localrogue' and 'Betona' or 'Comp'..string.char(96+seq)
    table.insert(joins,{at=h.now-h.base+1.5,name=name,class=class,role=role,owner=owner})
   end
   local _,_,real,legacyRole=string.find(text,'^%.z addlegacy "(%a+)" (%a+)$')
   if real then
    for _,entry in ipairs(plan.entries) do
     if entry.kind=='legacy' and entry.charName==real then
      table.insert(joins,{at=h.now-h.base+1.5,name=h.C.GetLegacyWhisperName(entry),class=entry.class,role=legacyRole,owner=h.name})
      break
     end
    end
   end
  end
  h.env.SendAddonMessage=function(prefix,text)
   if prefix~='nexus' or text~='GRINFO:ALL:FULL' then return end
   local rows={}
   for _,r in ipairs(records) do table.insert(rows,r.name..':Human:'..r.class..':'..r.role..':Uncommon:'..r.owner) end
   table.insert(replies,{h=h,text='[nexus] GRINFO:ALL:FULL '..table.concat(rows,' ')})
  end
 end
 x.observe(function(elapsed)
  local i=1
  while joins[i] do
   if joins[i].at<=elapsed then local j=table.remove(joins,i); add(j.name,j.class,j.role,j.owner)
   else i=i+1 end
  end
  while table.getn(replies)>0 do
   local r=table.remove(replies,1); local h=r.h
   h.env.event='CHAT_MSG_ADDON'; h.env.arg2='nexus'
   for _,w in ipairs(h.frames) do if w.events.CHAT_MSG_ADDON and w.scripts.OnEvent then h:fire(w,'OnEvent',r.text) end end
  end
 end)
 a:preset().entries=plan.entries; a:preset().denyRules=plan.denyRules or {}; a:preset().setupRules=plan.setupRules or {}
 a:click(a.env.ShirsRaidBuilderMainFrame.executeBtn)
 x.pump(300)
 local hires,whispers={},{}
 for _,s in ipairs(sent) do
  if s.route=='SAY' and (string.find(s.text,'^%.z addinvite %a') or string.find(s.text,'^%.z addlegacy "')) then table.insert(hires,s) end
  if s.route=='WHISPER' and (string.find(s.text,'^deny ') or string.find(s.text,'^set ')) then table.insert(whispers,s) end
 end
 return {a=a,b=b,hires=hires,whispers=whispers,records=records,members=members,sent=sent,trace=x.trace}
end
local function audit(r,expected)
 assert(table.getn(r.hires)==expected,'expected '..expected..' hires, got '..table.getn(r.hires)..': '..table.concat(r.trace,' | '))
 local tanks,rogue=0,0
 for _,h in ipairs(r.hires) do
  if string.find(h.text,'warrior tank',1,true) then tanks=tanks+1 end
  if string.find(h.text,'addinvite Localrogue ',1,true) then rogue=rogue+1 end
 end
 if expected>0 then assert(tanks==2 and rogue==1,'two tanks and the other owner MDPS must all be hired') end
 for _,h in ipairs({r.a,r.b}) do
  assert(not said(h,"is not in the server's companion list"),'false missing warning: '..table.concat(h.messages,' | '))
 end
 local betona,legacyDeny,setup=false,false,false
 for _,w in ipairs(r.whispers) do
  if w.target=='Betona' and string.find(w.text,'Cleave',1,true) then betona=true end
  if w.target=='Alice-lite' and string.find(w.text,'Cleave',1,true) then legacyDeny=true end
  if w.target=='Localhe-lite' and string.find(w.text,'set totem',1,true) then setup=true end
  assert(w.target~='Humanwar','human received companion commands')
 end
 assert(betona,'Betona Owner Localrogue, Master Alice lost its MDPS deny')
 assert(setup,'legacy Shaman lost class setup')
 return legacyDeny
end

test('local first ten: Warrior legacy cannot remove normal MDPS; all denies/setup survive',function()
 local r=run(firstTen(false),false,{'Alice-lite'},{{name='Alice-lite',class='warrior',role='mdps',owner='Alice'}})
 audit(r,9); assert(not said(r.a,'normal hire(s) already present'),'legacy caused normal skip')
end)
for _,swap in ipairs({false,true}) do
 test('linked first ten, Warrior legacy, swap6/7='..tostring(swap),function()
  local r=run(firstTen(false,swap),true,{'Alice-lite'},{{name='Alice-lite',class='warrior',role='mdps',owner='Alice'}})
  assert(audit(r,9),'legacy Warrior lost its own deny')
  assert(r.a.env.ShirsRaidBuilderDB.handoff.active.phase=='done','linked run did not complete')
  local saw=false; for _,line in ipairs(r.trace) do if string.find(line,'GRANT',1,true) then saw=true end end
  assert(saw,'fixture bypassed handoff')
 end)
end
test('linked Warrior case does not lose a normal row during final command scoping',function()
 local r=run(firstTen(false),true,{'Alice-lite'},{{name='Alice-lite',class='warrior',role='mdps',owner='Alice'}})
 for _,h in ipairs({r.a,r.b}) do
  assert(not said(h,"is not in the server's companion list"),'false warning after the same Execute: '..table.concat(h.messages,' | '))
 end
end)
test('Druid workaround control and all-present rerun',function()
 local first=run(firstTen(true),true,{'Bearalt-lite'},{{name='Bearalt-lite',class='druid',role='mdps',owner='Alice'}})
 audit(first,9)
 local again=run(firstTen(true),true,first.members,first.records)
 audit(again,0)
end)
test('Warrior all-present rerun keeps owner-scoped one-to-one matching and commands',function()
 local first=run(firstTen(false),true,{'Alice-lite'},{{name='Alice-lite',class='warrior',role='mdps',owner='Alice'}})
 audit(first,9)
 local again=run(firstTen(false),true,first.members,first.records)
 assert(audit(again,0),'present legacy lost its deny on rerun')
end)

dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')
local C=ShirsRaidBuilderCore
test('common normal matcher rejects every -lite record including explicit name and hirer fallback',function()
 local e=normal('Alice')
 for _,name in ipairs({'Alice-lite','aLiCe-LiTe',' Other-lite '}) do
  local r={name=name,owner='Alice',class='warrior',role='mdps'}
  assert(not C.NormalHireMatchesInfo(e,r),'normal accepted legacy '..name)
  e.companionName=C.Trim(name)
  assert(not C.NormalHireMatchesInfo(e,r),'explicit companionName accepted legacy '..name)
  assert(not C.HandHiredBy(normal('Alt'),r,'Alice'),'hirer fallback accepted legacy '..name)
 end
 assert(C.NormalHireMatchesInfo(normal('Alice'),{name='Betona',owner='aLiCe',class='Warrior',role='MDPS'}),'valid normal stopped matching')
 assert(not C.NormalHireMatchesInfo({kind='player',charName='Alice',class='warrior',role='mdps'},{name='Alice',owner='Alice',class='warrior',role='mdps'}),'player row became a hire')
end)
test('previous-step reservation cannot consume legacy and steal another owners normal',function()
 local entries={[1]=normal('Alice'),[6]=normal('Alice')}
 local lite={name='Earlier-lite',owner='Alice',class='warrior',role='mdps'}
 local first={name='First',owner='Alice',class='warrior',role='mdps'}
 local second={name='Second',owner='Alice',class='warrior',role='mdps'}
 local info={lite,first,second,{name='Foreign',owner='Bob',class='warrior',role='mdps'}}
 local h={step=2,steps={{group=1,actor='Alice'},{group=2,actor='Alice'}},plan={entries=entries}}
 local free=C.HandUnclaimed(h,info)
 assert(table.getn(free)==3 and free[1]==lite and free[2]==second,'previous step reserved -lite instead of its normal')
 local q={{kind='normal',sourceEntryIndex=6}}
 local out,skipped=C.FilterExistingNormalHires(q,entries,free)
 assert(skipped==1 and table.getn(out)==0,'legitimate remaining normal did not dedupe')
 local chosen,missing=C.HandScopeFound({[6]=entries[6]},{lite,second,info[4]},'Alice',{['Earlier-lite']=true,Second=true,Foreign=true},{alice=true})
 assert(table.getn(missing)==0 and table.getn(chosen)==1 and chosen[1]==second,'out-of-batch legacy counted as normal scope')
 local _,absent=C.HandScopeFound({[6]=entries[6]},{lite,info[4]},'Alice',{['Earlier-lite']=true,Foreign=true},{alice=true})
 assert(absent[1]==6,'foreign owner or out-of-batch legacy filled missing normal')
end)
test('two same-role normals consume two distinct own records, never legacy or another owner',function()
 local e={normal('Alice'),normal('Alice'),normal('Bob')}
 local q={{kind='normal',sourceEntryIndex=1},{kind='normal',sourceEntryIndex=2},{kind='normal',sourceEntryIndex=3}}
 local out,skipped=C.FilterExistingNormalHires(q,e,{{name='Alice-lite',owner='Alice',class='warrior',role='mdps'},
  {name='First',owner='Alice',class='warrior',role='mdps'},{name='Bobcomp',owner='Bob',class='warrior',role='mdps'}})
 assert(skipped==2 and table.getn(out)==1 and out[1].sourceEntryIndex==2,'normal owner/one-to-one boundary lost')
end)

print('passes='..passes..' failures='..failures)
assert(failures==0,failures..' normal legacy regression(s) failed')
print("Shir's Raid Builder normal legacy tests: PASS")
