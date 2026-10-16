-- Observed amounts and source/count quote boundaries, not future-discount promises.
-- The player confirmed the changed discount was character reputation, not an ordinal rule.
dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua');local C=ShirsRaidBuilderCore
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n..': '..tostring(e)) end end
local sequences={{500,750,1250,2500},{4500,6750,11250,22500},{6000,9000,15000,30000},{9000,13500,22500,45000},{12000,18000,30000,60000},{15000,22500,37500,75000},{35000,52500,87500,175000}}
test('observed sequences replay only their actual quote at each existing count; future discounts stay unknown',function()
 assert(type(C.PlannerQuoteMarginal)=='function','quote price boundary missing')
 for _,sequence in ipairs(sequences) do
  for count=0,3 do
   local q={count=count,max=4}
   assert(C.PlannerQuoteMarginal(q,sequence[count+1],0)==sequence[count+1],'actual count-specific quote changed')
   for offset=1,3 do assert(C.PlannerQuoteMarginal(q,sequence[count+1],offset)==nil,'current discounted quote extrapolated to an unknown future discount') end
  end
 end
 local variable={750,1125,1875,11250};local discount={95,95,95,85};local full={15000,22500,37500,75000}
 for i=1,4 do assert(variable[i]*100/(100-discount[i])==full[i]);assert(C.PlannerQuoteMarginal({count=i-1,max=4},variable[i],0)==variable[i]) end
 assert(variable[4]~=variable[1]*5,'fixture no longer detects the fourth discount change')
 assert(not C.PlannerQuoteMarginal({count=0,max=4},750,3),'95 percent discount was silently reused at fourth')
end)
test('minimum-copper fractional calibration other count scopes and oversized estimates stay unknown',function()
 assert(C.PlannerQuoteMarginal({count=0,max=4},1,0)==1,'actual one-copper next quote lost')
 assert(not C.PlannerQuoteMarginal({count=0,max=4},1,1),'one-copper floor extrapolated')
 assert(not C.PlannerQuoteMarginal({count=0,max=4},3,1),'fractional future price rounded without evidence')
 assert(not C.PlannerQuoteMarginal({count=1,max=4},751,1),'nonintegral calibration accepted')
 assert(not C.PlannerQuoteMarginal({count=0,max=5},100,1),'unknown count scope treated as four normals')
 assert(not C.PlannerQuoteMarginal({count=0,max=4},2147483647,3),'out-of-range price accepted')
end)
local function build(count,save,qa,qb)
 local sources={{key='own:alice',name='Alice',localSource=true,eligible=true,faction='Alliance',accountId='1111111111111111',tiers={'t3r'},capacity=4},{key='2222222222222222:bob',name='Bob',localSource=false,live=true,eligible=true,faction='Alliance',accountId='2222222222222222',tiers={'t3r'},capacity=4}}
 local request={sources={},counts={['mage:rdps']=count},saveGold=save,quotes={},quoteNow=100}
 for i,s in ipairs(sources) do local v=i==1 and qa or qb;request.sources[s.key]={selected=true,tier='t3r'};request.quotes[s.key]={name=s.name,tier='t3r',accountId=s.accountId,base=v[1],ex=v[1],mask='0',friendly='0',qbase=1,qex=1,count=v[2],max=4,received=100} end
 return assert(C.PlannerBuild({entries={},denyRules={},setupRules={}},sources,request))
end
test('allocation uses actual next quotes without assuming a constant future discount',function()
 for _,save in ipairs({true,false}) do local r=build(2,save,{100,0},{1000,0});local counts={};for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then counts[e.account]=(counts[e.account] or 0)+1 end end;assert(counts.Alice==1 and counts.Bob==1,'unknown future discount priced as a cheap next hire');assert(string.find(table.concat(r.notes,' '),'remain unknown',1,true),'unknown future price limit hidden') end
end)
test('Save gold applies to an actual fourth ordinal at nonzero count without demoting explicit tiers',function()
 local on=build(1,true,{500,3},{5000,0});local off=build(1,false,{500,3},{5000,0})
 assert(on.plan.entries[1].account=='Bob','Save gold ignored existing source count')
 assert(off.plan.entries[1].account=='Alice' and off.fourths==1,'unchecked policy hid cheaper quoted actual fourth hire')
end)
test('relay schema rejects oversized unknown-version executable and malformed payloads',function()
 local s={a=string.rep('1',32),b=string.rep('2',32)};local w={nonce=string.rep('3',32),requester=string.rep('4',32),owner=string.rep('5',32),name='Twelveletter',tier='t5r'}
 local p=assert(C.QuotePacket(s,'H',w));assert(string.len(p)<=240 and C.QuoteParse(p))
 local prices=C.QuotePacket(s,'P',w,'2147483647:2147483647:2147483647:2147483647');assert(not prices or string.len(prices)<=240)
 assert(not C.QuoteParse(p..';extra'));assert(not C.QuoteParse(string.gsub(p,'SRBQUOTE1','SRBQUOTE9')))
 assert(not C.QuotePacket(s,'EXECUTE',w,'.z add warrior tank'));assert(not C.QuotePacket(s,'P',w,'1:-2:3:4'))
 assert(not C.QuotePacket(s,'M',w,'0:0:5:4:1800000000'))
 local a={nonce='100001',requester='1111111111111111',owner='2222222222222222',name='Twin',tier='t2r'};local b=C.PlannerCopy(a);b.owner='3333333333333333';assert(not C.QuoteSame(a,b),'same source name crossed account identities')
end)
test('per-character detailed race and Quick coverage choose their own MCP price fields',function()
 assert(type(C.PlannerPricePick)=='function','race-aware quote selector missing')
 local q={base=11250,ex=3750,qbase=12000,qex=4000,mask='17',friendly='17'}
 assert(C.PlannerPricePick(q,{race='human'})==3750 and C.PlannerPricePick(q,{race='gnome'})==3750)
 assert(C.PlannerPricePick(q,{race='nightelf'})==11250,'best reputation price reused for an ineligible race')
 assert(C.PlannerPricePick(q,{race='random',class='random'})==4000,'Quick all-friendly coverage ignored')
 q.mask='1';assert(C.PlannerPricePick(q,{race='random',class='random'})==12000,'unknown Quick outcome promised exalted')
 q.friendly='0';assert(C.PlannerPricePick(q,{race='random',class='random'})==12000)
 assert(not C.PlannerPricePick(q,{race='unknown'}),'unsupported detailed race invented')
 assert(not C.PlannerPricePick({base=1,ex=-1,mask='1'},{race='human'}),'invalid chosen amount accepted')
end)
test('mixed race jobs allocate with each source mask rather than one best discount or a false block',function()
 local sources={{key='own:alice',name='Alice',localSource=true,eligible=true,faction='Alliance',accountId='1111111111111111',tiers={'t3r'},capacity=4},{key='2222222222222222:bob',name='Bob',localSource=false,live=true,eligible=true,faction='Alliance',accountId='2222222222222222',tiers={'t3r'},capacity=4}}
 local req={sources={},counts={['mage:rdps']=1,['druid:rdps']=1},defaults={mage={race='human'},druid={race='nightelf'}},quotes={},quoteNow=100,saveGold=false}
 for i,s in ipairs(sources) do req.sources[s.key]={selected=true,tier='t3r'};req.quotes[s.key]={name=s.name,tier='t3r',accountId=s.accountId,base=10000,ex=i==1 and 500 or 600,mask=i==1 and '1' or '4',friendly='147',qbase=999,qex=1,count=0,max=4,received=100} end
 local r,why=C.PlannerBuild({entries={},denyRules={},setupRules={}},sources,req);assert(r,why)
 for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then assert(e.account==(e.class=='mage' and 'Alice' or 'Bob'),'race-specific next quote lost in allocation') end end
 -- A source with mixed reputation prices can still supply both classes. These
 -- next-price benchmarks are not a future order/discount/total-price guarantee.
 req.sources[sources[2].key].selected=false
 r,why=C.PlannerBuild({entries={},denyRules={},setupRules={}},sources,req);assert(r,why);assert(r.normal==2 and r.allocation[1].nextMin==500 and r.allocation[1].nextMax==10000,'mixed-race quote range lost')
 assert(not string.find(string.lower(table.concat(r.notes,' ')),'suspected server',1,true),'superseded bug assumption remains in proposal')
end)
print("Shir's Raid Builder quote curve tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'quote curve regressions failed')
