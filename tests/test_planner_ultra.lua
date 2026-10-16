-- Cost-aware opt-in Ultra over the full grouped plan, exact Lua 5.0.3.
dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua');local C=ShirsRaidBuilderCore
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n..': '..tostring(e))end end
local function setup(hi,lo)
 hi=hi or 't5r';lo=lo or 't4r'
 local sources={{key='a',name='Alpha',accountId='1111111111111111',localSource=true,eligible=true,capacity=4,faction='Alliance',tiers={hi},chosenTier=hi},
 {key='b',name='Bravo',accountId='2222222222222222',localSource=false,live=true,eligible=true,capacity=4,faction='Alliance',tiers={lo},chosenTier=lo}}
 local req={counts={['mage:rdps']=4},sources={a={selected=true,tier=hi},b={selected=true,tier=lo}},saveGold=false,ultraGold=true,quoteNow=100,quotes={},gender='female'}
 for _,s in ipairs(sources)do req.quotes[s.key]={name=s.name,tier=s.chosenTier,accountId=s.accountId,base=1000,ex=1000,qbase=1000,qex=1000,mask='0',friendly='0',count=0,max=4,received=100}end
 return sources,req
end
local function build(s,r,base)return C.PlannerBuild(base or {entries={}},s,r)end
local function counts(r)local out={};for _,a in ipairs(r.allocation)do out[a.name]=a.count end;return out end
local function conservation(r,req)
 local actual={}
 for _,e in ipairs(r.plan.entries)do if e.kind=='normal'then actual[e.class..':'..e.role]=(actual[e.class..':'..e.role]or 0)+1 end end
 for key,n in pairs(req.counts)do assert(actual[key]==n,'composition changed: '..key)end
 for key in pairs(actual)do assert(req.counts[key],'invented role')end
 assert(r.estimate.complete and r.estimate.unknown==0,'Ultra used unknown prices')
end

for _,tiers in ipairs({{'t5r','t4r'},{'t3r','t2r'},{'t2d','t1d'},{'t1r','t5d'},{'t1d','t0d'}})do
 test('cheaper next chosen licence on another character avoids fourth '..tiers[1],function()
  local s,q=setup(tiers[1],tiers[2]);q.quotes.b.base=2000;q.quotes.b.ex=2000
  local r=assert(build(s,q));local n=counts(r);assert(n.Alpha==3 and n.Bravo==1,'Ultra did not replace fourth highest hire')
  for _,e in ipairs(r.plan.entries)do if e.kind=='normal'then assert(e.tier==(e.account=='Alpha'and tiers[1]or tiers[2]),'source licence silently changed')end end
  assert(r.ultra and r.ultra.replacements==1 and r.ultra.savedCopper==3000,'missing honest cost comparison');conservation(r,q)
 end)
end

test('existing Save gold stays unchanged; Ultra is different when discounted lower licence costs more',function()
 local s,q=setup();q.saveGold=true;q.ultraGold=false;q.quotes.b.base=6000;q.quotes.b.ex=6000
 local soft=assert(build(s,q));assert(counts(soft).Alpha==3 and counts(soft).Bravo==1,'existing Save gold semantics changed')
 q.ultraGold=true;local r=assert(build(s,q));assert(counts(r).Alpha==4 and counts(r).Bravo==0,'Ultra assumed lower tier is cheaper')
 assert(r.ultra and r.ultra.replacements==0 and string.find(table.concat(r.notes,' '),'no cheaper',1,true),'missing no-alternative explanation')
 q.ultraGold=false;local again=assert(build(s,q));assert(counts(again).Alpha==3 and counts(again).Bravo==1)
end)

test('discounted race alternatives and current character ordinal decide the comparison',function()
 local s,q=setup();q.counts['mage:rdps']=1;q.quotes.a.count=3;q.quotes.a.base=9000;q.quotes.a.ex=800;q.quotes.a.mask='7'
 q.quotes.b.base=1200;q.quotes.b.ex=50;q.quotes.b.mask='1'
 local r=assert(build(s,q));assert(counts(r).Alpha==1 and counts(r).Bravo==0,'wrong reputation or endpoint count made the lower source cheaper')
 q.quotes.b.mask='7';r=assert(build(s,q));assert(counts(r).Alpha==0 and counts(r).Bravo==1,'fresh applicable discount was ignored');conservation(r,q)
 q.quotes.b.count=3;q.quotes.b.ex=1000;r=assert(build(s,q));assert(counts(r).Alpha==1,'lower character fourth hire used an invented first-hire price')
end)

test('no selected eligible adjacent alternative keeps fourth without changing composition',function()
 for _,mode in ipairs({'unselected','cap','faction','gap','same'})do
  local s,q=setup()
  if mode=='unselected'then q.sources.b.selected=false
  elseif mode=='cap'then s[2].capacity=0
  elseif mode=='faction'then s[2].faction='Horde';q.defaults={mage={race='gnome'}}
  elseif mode=='gap'then s[2].tiers={'t3r'};q.sources.b.tier='t3r';q.quotes.b.tier='t3r'
  else s[2].name='Alpha';q.sources.b.selected=false end
  local r=assert(build(s,q));assert(counts(r).Alpha==4,mode..' invented cheaper capacity');conservation(r,q)
 end
end)

test('manual tier selections stay exact even when sources have higher licences available',function()
 local s,q=setup('t3r','t2r');s[1].tiers={'t3r','t4r','t5r'};s[2].tiers={'t1r','t2r','t3r'}
 local r=assert(build(s,q));assert(counts(r).Alpha==3 and counts(r).Bravo==1)
 for _,e in ipairs(r.plan.entries)do if e.kind=='normal'then assert(e.tier==(e.account=='Alpha'and 't3r'or 't2r'))end end
 q.sources.b.selected=false;r=assert(build(s,q));assert(counts(r).Alpha==4,'Ultra downgraded the same character to an unchosen licence')
end)

test('missing stale mismatched or unsupported estimates fail closed only in explicit Ultra',function()
 for _,mode in ipairs({'missing','stale','future','identity','count','cap'})do
  local s,q=setup()
  if mode=='missing'then q.quotes=nil
  elseif mode=='stale'then q.quotes.b.received=69
  elseif mode=='future'then q.quotes.b.received=101
  elseif mode=='identity'then q.quotes.b.accountId='3333333333333333'
  elseif mode=='count'then q.quotes.b.count=4
  else q.quotes.b.max=5 end
  local r,why=build(s,q);assert(not r and type(why)=='string',mode..' silently guessed Ultra savings')
 end
 local s,q=setup();q.quotes=nil;q.ultraGold=false;assert(build(s,q),'legacy no-price planning behavior changed')
end)

test('custom priority keeps strongest tiers for the earlier class role while cheaper replacement preserves exact counts',function()
 for _,first in ipairs({'warrior:tank','mage:rdps'})do
  local s,q=setup();q.counts={['warrior:tank']=2,['mage:rdps']=2};q.priorityMode='custom';q.customOrder={first,first=='mage:rdps'and 'warrior:tank'or 'mage:rdps'}
  local r=assert(build(s,q));conservation(r,q);local lower
  for _,e in ipairs(r.plan.entries)do if e.kind=='normal'and e.account=='Bravo'then lower=e.class..':'..e.role end end
  assert(lower and lower~=first,'Ultra took stronger capacity from the earlier custom priority')
 end
end)

test('included legacies and human tail remain separate and unchanged by Ultra',function()
 local s,q=setup();q.player={name='Player',class='warrior',role='tank'};s[2].legacyClass='priest';s[2].legacyRole='healer';q.sources.b.includeLegacy=true
 local base={entries={[35]={kind='player',charName='Visitor',class='priest',role='healer'},[34]={kind='guest',charName='Unresolved',class='mage',role='rdps'}}}
 local r=assert(build(s,q,base));conservation(r,q);assert(r.player==2 and r.guest==1 and r.legacy==1 and r.normal==4)
 assert(r.plan.entries[40].charName=='Player'and r.plan.entries[39].charName=='Visitor','human tail changed')
 assert(r.plan.entries[34].charName=='Unresolved'and r.plan.entries[34].kind=='guest','unresolved guest reclassified')
 local found=false;for _,e in ipairs(r.plan.entries)do if e.kind=='legacy'then found=true;assert(e.sourceName=='Bravo'and e.class=='priest'and e.role=='healer')end end;assert(found)
end)

print("Shir's Raid Builder Ultra tests: "..(fail==0 and 'PASS'or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'Ultra regressions failed')
