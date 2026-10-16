-- Registered Custom/Ultra/Build controls plus independent pure-Core priorities.
local f=assert(io.open('test_planner_linked_quotes.lua'));local src=f:read('*a');f:close()
local at=assert(string.find(src,"\ntest('mixed own",1,true));local fixture=assert(loadstring(string.sub(src,1,at-1)..'\nreturn fixture'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n..': '..tostring(e))end end
local function build(ultra,first)
 local a,b,c,pump,open,emit=fixture();local p=open(a,{Alice=true,Bob=true},2)
 a:click(a:button(p,'Sources'));local bob
 for _,r in ipairs(p.sourceRows)do if r.source.name=='Bob'then bob=r end end
 a:choose(assert(bob).tierButton,'t2r')
 a:click(a:button(p,'Tier priority'));a:choose(p.priorityMode,'Custom')
 local order={first,first=='warrior:tank'and'mage:rdps'or'warrior:tank'}
 for target,id in ipairs(order)do
  local index;for i,v in ipairs(p.request.customOrder)do if v==id then index=i end end
  while index>target do a:click(p.priorityRows[index].up);index=index-1 end
 end
 assert(p.request.customOrder[1]==order[1]and p.request.customOrder[2]==order[2])
 a:click(a:button(p,'Composition'));p.countInputs['warrior:tank']:SetText('2');p.countInputs['mage:rdps']:SetText('2')
 p.saveGoldCheck:SetChecked(nil);a:fire(p.saveGoldCheck,'OnClick')
 p.ultraGoldCheck:SetChecked(ultra and 1 or nil);a:fire(p.ultraGoldCheck,'OnClick')
 a.noReply=true;b.noReply=true;a:click(p.buildButton);local sent={}
 for i=1,320 do
  pump(0.25)
  for _,h in ipairs({a,b})do
   local flight=h.C.plannerQuoteFlight
   if flight and not flight.drain and not sent[flight]then
    sent[flight]=true
    local base,ex=10000,1000;if h==b then base,ex=12000,10000 end
    emit(h,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE '..flight.source.name..':'..base..':'..ex..':7:0:'..base..':'..ex..':0:4','nexus')
   end
  end
  if p.proposal then break end
 end
 local r=assert(p.proposal,p.message:GetText());local highTank,highMage,lowTank,lowMage=0,0,0,0
 for _,e in ipairs(r.plan.entries)do if e.kind=='normal'then
  assert(e.race==(e.class=='warrior'and'human'or'gnome'),'race preference changed')
  if e.account=='Alice'then assert(e.tier=='t3r');if e.class=='warrior'then highTank=highTank+1 else highMage=highMage+1 end
  else assert(e.account=='Bob'and e.tier=='t2r');if e.class=='warrior'then lowTank=lowTank+1 else lowMage=lowMage+1 end end
 end end
 assert(r.normal==4 and r.estimate.complete and not a.C.handAuthority and not b.C.handAuthority)
 assert(p.request.sources['own:alice'].tier=='t3r'and p.request.sources['2222222222222222:bob'].tier=='t2r','chosen licence changed')
 return highTank,highMage,lowTank,lowMage,r
end

test('Ultra-off native control keeps both Tank-first pairs high at 32500 copper',function()
 local t,m,lt,lm,r=build(false,'warrior:tank');assert(t==2 and m==2 and lt==0 and lm==0 and r.estimate.totalCopper==32500)
end)
test('Mage-first native Ultra can move the lower-priority Tank for 6500 copper saving',function()
 local t,m,lt,lm,r=build(true,'mage:rdps');assert(t==1 and m==2 and lt==1 and lm==0 and r.estimate.totalCopper==26000 and r.ultra.savedCopper==6500)
end)
test('Tank-first native Ultra keeps high fourth when only a higher-priority move saves money',function()
 local t,m,lt,lm,r=build(true,'warrior:tank');assert(t==2 and m==2 and lt==0 and lm==0 and r.estimate.totalCopper==32500 and r.ultra.replacements==0 and r.ultra.savedCopper==0)
end)

dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua');local C=ShirsRaidBuilderCore
for _,tiers in ipairs({{'t3r','t2r'},{'t5r','t4r'},{'t5d','t4d'}})do
 for _,first in ipairs({'warrior:tank','mage:rdps'})do
  for _,mode in ipairs({'expensiveMage','cheapMage','ineligibleMage'})do
   test('pure Custom '..tiers[1]..' '..first..' '..mode,function()
    local s={{key='a',name='Alpha',accountId='1111111111111111',localSource=true,eligible=true,capacity=4,faction='Alliance',tiers={'t5r',tiers[1]}},
     {key='b',name='Bravo',accountId='2222222222222222',localSource=false,live=true,eligible=true,capacity=4,faction='Alliance',tiers={'t5r',tiers[2]}}}
    local q={counts={['warrior:tank']=2,['mage:rdps']=2},sources={a={selected=true,tier=tiers[1]},b={selected=true,tier=tiers[2]}},saveGold=false,ultraGold=true,
     priorityMode='custom',customOrder={first,first=='warrior:tank'and'mage:rdps'or'warrior:tank'},quoteNow=100,gender='female',quotes={}}
    for i,source in ipairs(s)do q.quotes[source.key]={name=source.name,accountId=source.accountId,tier=tiers[i],base=i==1 and 10000 or 12000,ex=i==1 and 1000 or 10000,qbase=10000,qex=1000,mask='7',friendly='0',count=0,max=4,received=100}end
    -- Use the selected high/low licences, even with stronger manual choices available.
    q.quotes.a.tier=tiers[1];q.quotes.b.tier=tiers[2]
    if mode=='cheapMage'then q.quotes.b.ex=500 end
    if mode=='ineligibleMage'then s[2].faction='Horde';q.defaults={warrior={roles={tank='auto'}},mage={race='gnome'}} end
    local r=assert(C.PlannerBuild({entries={}},s,q));local high={};local roles={};local offsets={};local copper=0;local curve={1,1.5,2.5,5}
    for _,e in ipairs(r.plan.entries)do if e.kind=='normal'then
     local id=e.class..':'..e.role;roles[id]=(roles[id]or 0)+1
     local key=e.account=='Alpha'and'a'or'b';assert(e.account=='Alpha'or e.account=='Bravo')
     if key=='a'then high[id]=(high[id]or 0)+1 end
     assert(e.tier==q.sources[key].tier,'manual licence was changed')
     offsets[key]=(offsets[key]or 0)+1;local quote=q.quotes[key];local price=e.race=='gnome'and quote.ex or quote.base
     copper=copper+math.floor(price*curve[offsets[key]]+0.5)
    end end
    assert(roles['warrior:tank']==2 and roles['mage:rdps']==2 and r.estimate.complete and r.estimate.totalCopper==copper,'composition/race estimate changed')
    if mode=='expensiveMage'and first=='warrior:tank'then assert(high['warrior:tank']==2 and high['mage:rdps']==2 and r.ultra.replacements==0,'cost overrode first Custom role')
    elseif mode=='ineligibleMage'then assert(high['mage:rdps']==2 and (first~='warrior:tank'or high['warrior:tank']==2),'no eligible lower-priority move must retain the high fourth')
    else assert(high[first]==2,'strongest tier left first Custom role')end
   end)
  end
 end
end
print("Shir's Raid Builder Ultra priority tests: "..(fail==0 and 'PASS'or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'Ultra priority regressions')
