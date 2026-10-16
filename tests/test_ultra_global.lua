-- A full assignment can improve when the last-priority row is on a three-hire
-- high source. Single-row swaps from only four-hire sources cannot find it.
-- Native Build/quote/Create/reload below use synthetic server replies only.
dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua');local C=ShirsRaidBuilderCore
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n..': '..tostring(e))end end
local function setup(mode)
 local s={
  {key='a',name='Alpha',accountId='1111111111111111',localSource=true,eligible=true,capacity=4,faction='Horde',tiers={'t5r'},chosenTier='t5r'},
  {key='b',name='Bravo',accountId='2222222222222222',eligible=true,live=true,capacity=4,faction='Alliance',tiers={'t5r'},chosenTier='t5r'},
  {key='c',name='Charlie',accountId='3333333333333333',eligible=true,live=true,capacity=4,faction='Alliance',tiers={'t4r','t5r'},chosenTier='t4r'}}
 local q={counts={['warrior:tank']=4,['mage:rdps']=2,['paladin:healer']=1},sources={},quotes={},quoteNow=100,saveGold=false,ultraGold=true,gender='female'}
 for i,v in ipairs(s)do
  q.sources[v.key]={selected=true,tier=v.chosenTier};local price=({1000,1100,800})[i]
  q.quotes[v.key]={name=v.name,accountId=v.accountId,tier=v.chosenTier,base=price,ex=price,qbase=price,qex=price,mask='0',friendly='0',count=0,max=4,received=100}
 end
 if mode=='custom'then q.priorityMode='custom';q.customOrder={'warrior:tank','mage:rdps','paladin:healer'}end
 return s,q
end
local function summarize(r)
 local n,roles,high={}, {},{}
 for _,e in ipairs(r.plan.entries)do if e.kind=='normal'then
  n[e.account]=(n[e.account]or 0)+1;local id=e.class..':'..e.role;roles[id]=(roles[id]or 0)+1
  if e.tier=='t5r'then high[id]=(high[id]or 0)+1 end
 end end
 return n,roles,high
end
local function conserved(r,q)
 local n,roles,high=summarize(r);assert(roles['warrior:tank']==4 and roles['mage:rdps']==2 and roles['paladin:healer']==1,'composition changed')
 for _,e in ipairs(r.plan.entries)do if e.kind=='normal'then assert(e.tier==(e.account=='Charlie'and't4r'or't5r'),'manual licence changed')end end
 assert(r.estimate.complete and r.estimate.known==7 and r.estimate.unknown==0)
 return n,high
end
for _,mode in ipairs({'auto','custom'})do
 test(mode..' global reassignment removes a fourth without weakening earlier roles',function()
  local s,q=setup(mode);local off=C.PlannerCopy(q);off.ultraGold=false
  local base=assert(C.PlannerBuild({entries={}},s,off));local n=conserved(base,q)
  assert(n.Alpha==4 and n.Bravo==3 and not n.Charlie,'fixture did not put the final-priority Paladin on the three-hire source')
  local r=assert(C.PlannerBuild({entries={}},s,q));local now,high=conserved(r,q)
  assert(now.Alpha==3 and now.Bravo==3 and now.Charlie==1,'valid global move was missed')
  assert(high['warrior:tank']==4 and high['mage:rdps']==2 and not high['paladin:healer'],'earlier role lost stronger licence')
  assert(r.fourths==0 and r.ultra.replacements==1 and r.ultra.savedCopper>0 and r.estimate.totalCopper<base.estimate.totalCopper,'missing full-order saving')
 end)
end
test('Auto treats all healers as one tier-priority group; a faction-locked Shaman cannot block Priests',function()
 local s,q=setup();s[1].faction='Alliance';s[2].faction='Horde'
 q.counts={['priest:healer']=4,['shaman:healer']=4}
 local r=assert(C.PlannerBuild({entries={}},s,q));local n=summarize(r)
 assert(n.Bravo==4 and n.Alpha==3 and n.Charlie==1 and r.ultra.replacements==1,'ineligible last healer class blocked another eligible healer')
 q.priorityMode='custom';q.customOrder={'priest:healer','shaman:healer'}
 r=assert(C.PlannerBuild({entries={}},s,q));n=summarize(r)
 assert(n.Alpha==4 and n.Bravo==4 and not n.Charlie and r.ultra.replacements==0,'explicit Custom role order was relaxed')
end)

test('Auto can pass a faction-locked healer after all eligible healers moved, without taking tiers from Tanks',function()
 local s,q=setup();s[1].faction='Alliance'
 local d={key='d',name='Delta',accountId='4444444444444444',eligible=true,live=true,capacity=4,faction='Horde',tiers={'t5r'},chosenTier='t5r'}
 table.insert(s,d);q.sources.d={selected=true,tier='t5r'};q.quotes.d=C.PlannerCopy(q.quotes.a);q.quotes.d.name='Delta';q.quotes.d.accountId=d.accountId
 q.counts={['warrior:tank']=4,['mage:rdps']=3,['paladin:healer']=1,['shaman:healer']=4}
 local r=assert(C.PlannerBuild({entries={}},s,q));local n,roles,high=summarize(r)
 assert(n.Delta==4 and n.Alpha==3 and n.Bravo==3 and n.Charlie==2 and r.ultra.replacements==2,'unavoidable Shaman fourth blocked a valid cheaper Mage transfer')
 assert(high['warrior:tank']==4 and high['mage:rdps']==2 and high['shaman:healer']==4 and not high['paladin:healer'],'Auto priority or faction changed')
end)

test('global mixed-race reputation discounts keep Custom order and the full marginal saving',function()
 for _,mode in ipairs({'auto','custom'})do
  local s,q=setup(mode)
  for i,v in ipairs(s)do local quote=q.quotes[v.key];quote.base=({1200,1600,1000})[i];quote.ex=({600,900,400})[i];quote.mask=({'8','7','3'})[i]end
  local r=assert(C.PlannerBuild({entries={}},s,q));local n,high=conserved(r,q)
  assert(n.Alpha==3 and n.Bravo==3 and n.Charlie==1 and high['warrior:tank']==4 and high['mage:rdps']==2 and r.ultra.savedCopper>0,'global discounted alternative missed')
  local offsets,total={},0;local curve={1,1.5,2.5,5};local key={Alpha='a',Bravo='b',Charlie='c'}
  for _,e in ipairs(r.plan.entries)do if e.kind=='normal'then
   local k=key[e.account];offsets[k]=(offsets[k]or 0)+1;local quote=q.quotes[k]
   local exalted=(k=='a'and e.race=='troll')or(k=='b'and e.race=='gnome')or(k=='c'and e.race=='dwarf')
   total=total+math.floor((exalted and quote.ex or quote.base)*curve[offsets[k]]+0.5)
  end end
  assert(r.estimate.totalCopper==total,'race-specific marginal estimate crossed sources')
 end
end)

test('global move stays off when all priority-preserving alternatives cost more',function()
 local s,q=setup('custom');q.quotes.c.base=30000;q.quotes.c.ex=30000
 local r=assert(C.PlannerBuild({entries={}},s,q));local n=conserved(r,q)
 assert(n.Alpha==4 and n.Bravo==3 and not n.Charlie and r.ultra.replacements==0)
end)
test('wrong faction or manual race blocks the lower role rather than downgrading Tanks',function()
 for _,mode in ipairs({'faction','race'})do
  local s,q=setup('custom');if mode=='faction'then s[3].faction='Horde'else q.defaults={paladin={race='dwarf'}};s[3].faction='Horde'end
  local r=assert(C.PlannerBuild({entries={}},s,q));local n=conserved(r,q)
  assert(n.Alpha==4 and n.Bravo==3 and not n.Charlie and r.ultra.replacements==0,'priority/eligibility bypassed')
 end
end)
test('existing counts bound low-source remaining capacity and estimated ordinal',function()
 local s,q=setup('custom');q.quotes.c.count=3;q.quotes.c.base=18000;q.quotes.c.ex=18000
 local r=assert(C.PlannerBuild({entries={}},s,q));assert(r.ultra.replacements==0,'expensive actual fourth treated as cheap first')
 q.quotes.c.base=800;q.quotes.c.ex=800;r=assert(C.PlannerBuild({entries={}},s,q));local n=conserved(r,q)
 assert(n.Charlie==1 and r.ultra.replacements==1,'remaining fourth cannot be used despite a cheaper actual marginal cost')
end)
test('missing quote remains explicitly unknown, no invented saving',function()
 local s,q=setup();q.quotes.c=nil;local r,why=C.PlannerBuild({entries={}},s,q)
 assert(not r and (string.find(why,'fresh',1,true) or string.find(why,'missing',1,true)),'unknown alternative accepted')
end)

ShirsRaidBuilderCore=nil -- Each native environment must own its Core, not inherit the pure table.
local f=assert(io.open('test_planner_linked_quotes.lua'));local src=f:read('*a');f:close();local at=assert(string.find(src,"\ntest('mixed own",1,true));local fixture=assert(loadstring(string.sub(src,1,at-1)..'\nreturn fixture'))()
local file=assert(io.open('test_individual_editor.lua'));src=file:read('*a');file:close();at=assert(string.find(src,'\nlocal failures, passes=',1,true));local boot=assert(loadstring(string.sub(src,1,at-1)..'\nreturn boot'))()
local function native(ultra,save,expensive)
 local a,b,c,pump,open,emit=fixture()
 for _,h in ipairs({a,b,c})do
  local faction=h==a and 'Horde'or'Alliance';h.env.UnitFactionGroup=function()return faction end
  local rec=h.env.ShirsRaidBuilderDB.inviteCharacters[h.name];rec.faction=faction;rec.dungeonLicense='t5d';rec.raidLicense='t5r'
  h.roster=h.name..':warrior:t5d:t5r:'..(faction=='Horde'and'H'or'A')..':0:60:0:4'
 end
 for _,h in ipairs({a,b,c})do h.C.SyncRefreshAll()end;pump(20)
 local p=open(a,{Alice=true,Bob=true,Carol=true},2)
 a:click(a:button(p,'Sources'));for _,row in ipairs(p.sourceRows)do if row.source.name=='Carol'then a:choose(row.tierButton,'t4r')end end
 a:click(a:button(p,'Tier priority'));a:choose(p.priorityMode,'Custom')
 for target,id in ipairs({'warrior:tank','mage:rdps','paladin:healer'})do
  local index;for i,v in ipairs(p.request.customOrder)do if v==id then index=i end end
  while index>target do a:click(p.priorityRows[index].up);index=index-1 end
 end
 a:click(a:button(p,'Composition'));p.countInputs['warrior:tank']:SetText('4');p.countInputs['paladin:healer']:SetText('1')
 p.saveGoldCheck:SetChecked(save and 1 or nil);a:fire(p.saveGoldCheck,'OnClick')
 p.ultraGoldCheck:SetChecked(ultra and 1 or nil);a:fire(p.ultraGoldCheck,'OnClick')
 a.prices.Alice=1000;b.prices.Bob=1100;c.prices.Carol=expensive and 30000 or 800
 local before=a.C.PlannerCopy(a:preset());a:click(p.buildButton);assert(not p.proposal,'native quote path bypassed');pump(20)
 local r=assert(p.proposal,p.message:GetText());local n,high={},{}
 for _,e in ipairs(r.plan.entries)do if e.kind=='normal'then n[e.account]=(n[e.account]or 0)+1;local id=e.class..':'..e.role
  if e.tier=='t5r'then high[id]=(high[id]or 0)+1 end
  assert(e.tier==(e.account=='Carol'and't4r'or't5r'),'native source tier changed')
 end end
 assert(r.estimate.complete and a.C.PlannerEqual(before,a:preset()),'Build changed saved plan or left price unknown')
 for _,h in ipairs({a,b,c})do assert(table.getn(h.quoteReads)>0 and not h.C.handAuthority and not h.C.handRunPlan,'quote flow missing or granted spending')end
 return a,b,c,p,r,n,high,boot
end

test('registered Ultra Build globally reallocates, Preview/Create and fresh reload keep exact rows',function()
 local a,b,c,p,r,n,high,reboot=native(true,false,false)
 assert(n.Alice==3 and n.Bob==3 and n.Carol==1 and high['warrior:tank']==4 and high['mage:rdps']==2 and not high['paladin:healer'],'native global assignment missed')
 assert(r.ultra.replacements==1 and r.ultra.savedCopper>0 and string.find(p.previewText:GetText(),'Estimated total:',1,true),'preview not actual proposal')
 local expected=a.C.PlannerCopy(r.plan);local choices=a.C.PlannerCopy(p.request.sources)
 p.nameInput:SetText('Global Ultra candidate');a:click(p.applyButton);a.env.RefreshComposition()
 assert(a.C.PlannerEqual(expected,a:preset()),'Create saved a different proposal')
 local re=reboot(a.C.PlannerCopy(a.env.ShirsRaidBuilderDB),'Alice');assert(re.C.PlannerEqual(expected,re:preset()),'fresh reload changed proposal')
 re:click(re.env.ShirsRaidBuilderMainFrame.plannerBtn);local rp=re.C.plannerFrame
 assert(rp.request.ultraGold and re.C.PlannerEqual(rp.request.sources,choices),'reopen lost Ultra or manual sources')
 assert(rp.request.customOrder[1]=='warrior:tank'and rp.request.customOrder[2]=='mage:rdps','Custom order not persisted')
end)
test('native strongest off, ordinary Save gold and expensive Ultra controls stay distinct',function()
 local a,b,c,p,r,n=native(false,false,false);assert(n.Alice==4 and n.Bob==3 and not n.Carol and not r.ultra)
 a,b,c,p,r,n=native(false,true,true);assert(n.Alice==3 and n.Bob==3 and n.Carol==1 and not r.ultra,'ordinary Save gold behavior changed')
 a,b,c,p,r,n=native(true,true,true);assert(n.Alice==4 and n.Bob==3 and not n.Carol and r.ultra.replacements==0,'Ultra assumed lower licence is cheaper')
end)
print("Shir's Raid Builder Ultra global tests: "..(fail==0 and 'PASS'or'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'Ultra global regressions')
