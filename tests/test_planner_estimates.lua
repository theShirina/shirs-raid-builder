-- Empirical estimates, never server-returned totals or price locks.
dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua');local C=ShirsRaidBuilderCore
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n..': '..tostring(e)) end end
local sequences={{500,750,1250,2500},{4500,6750,11250,22500},{6000,9000,15000,30000},{9000,13500,22500,45000},{12000,18000,30000,60000},{15000,22500,37500,75000},{35000,52500,87500,175000}}
test('money formats zero copper silver gold and mixed denominations',function()
 assert(C.PlannerMoney(0)=='0c');assert(C.PlannerMoney(9)=='9c');assert(C.PlannerMoney(750)=='7s 50c');assert(C.PlannerMoney(10000)=='1g');assert(C.PlannerMoney(12345)=='1g 23s 45c');assert(C.PlannerMoney(nil)=='unknown');assert(C.PlannerMoney(-1)=='unknown')
end)
test('remaining marginals anchor every observed tier to its own count zero through three',function()
 for _,seq in ipairs(sequences) do for count=0,3 do for offset=0,3-count do assert(C.PlannerEstimateMarginal({count=count,max=4},seq[count+1],offset)==seq[count+offset+1],'wrong remaining ordinal') end end end
 assert(C.PlannerEstimateMarginal({count=0,max=4},1,1)==2,'nearest copper estimate not rounded explicitly')
 assert(not C.PlannerEstimateMarginal({count=3,max=4},5,1));assert(not C.PlannerEstimateMarginal({count=0,max=5},100,0));assert(not C.PlannerEstimateMarginal({count=0,max=4},2147483647,3))
end)
local function fixture()
 local sources={{key='own:alice',name='Alice',accountId='1111111111111111',chosenTier='t1r'},{key='2222222222222222:bob',name='Bob',accountId='2222222222222222',chosenTier='t5r'}}
 local request={quoteNow=100,sources={},quotes={}}
 for _,s in ipairs(sources) do request.sources[s.key]={selected=true,tier=s.chosenTier} end
 request.quotes[sources[1].key]={name='Alice',accountId=sources[1].accountId,tier='t1r',count=1,max=4,received=100,base=3375,ex=1125,qbase=3500,qex=1200,mask='7',friendly='17'}
 request.quotes[sources[2].key]={name='Bob',accountId=sources[2].accountId,tier='t5r',count=2,max=4,received=100,base=37500,ex=12500,qbase=40000,qex=13000,mask='1',friendly='17'}
 local result={normal=4,allocation={{key=sources[1].key},{key=sources[2].key}},plan={entries={{kind='normal',account='Alice',tier='t1r',race='gnome',class='mage'},{kind='legacy',charName='Oldmage'},{kind='normal',account='Bob',tier='t5r',race='human',class='warrior'},{kind='normal',account='Alice',tier='t1r',race='human',class='mage'},{kind='normal',account='Bob',tier='t5r',race='gnome',class='mage'}}}}
 return result,sources,request
end
test('mixed sources count separately and each final row uses its chosen race reputation',function()
 local r,s,q=fixture();C.PlannerEstimate(r,s,q)
 assert(r.estimate.complete and r.estimate.known==4 and r.estimate.unknown==0)
 assert(r.estimate.totalCopper==94250,'total was next-quote sum or quote times allocation count')
 assert(r.allocation[1].estimatedCopper==6750 and r.allocation[2].estimatedCopper==87500,'source totals lost remaining ordinals')
 -- 95-to85 is a race/source applicability change, never a fourth-hire rule.
 local quote={count=0,max=4,base=2250,ex=750,mask='7',friendly='17'}
 local races={'gnome','gnome','gnome','human'};local paid={750,1125,1875,11250}
 for i,race in ipairs(races) do assert(C.PlannerEstimateMarginal(quote,C.PlannerPricePick(quote,{race=race}),i-1)==paid[i]) end
end)
test('missing stale cross-account changed-tier and unknown count contexts stay explicitly partial',function()
 for _,mode in ipairs({'missing','stale','owner','tier','scope'}) do
  local r,s,q=fixture();local k=s[2].key
  if mode=='missing' then q.quotes[k]=nil elseif mode=='stale' then q.quotes[k].received=0 elseif mode=='owner' then q.quotes[k].accountId=s[1].accountId elseif mode=='tier' then q.quotes[k].tier='t4r' else q.quotes[k].max=5 end
  C.PlannerEstimate(r,s,q);assert(not r.estimate.complete and r.estimate.known==2 and r.estimate.unknown==2 and r.estimate.totalCopper==6750,mode..' invented zero/full total')
 end
end)
test('Quick random estimate uses verified all-friendly mask rule not best race discount',function()
 local q={base=100,ex=10,qbase=120,qex=12,mask='1',friendly='17',count=2,max=4}
 assert(C.PlannerEstimateMarginal(q,C.PlannerPricePick(q,{kind='normal',class='random',role='dps'}),1)==240)
 q.mask='17';assert(C.PlannerEstimateMarginal(q,C.PlannerPricePick(q,{kind='normal',class='random',role='dps'}),1)==24)
end)
test('partial proposal labels never present a subtotal as the full estimated total',function()
 local raw=assert(io.open('test_individual_editor.lua'));local src=raw:read('*a');raw:close();local at=assert(string.find(src,'\nlocal failures, passes=',1,true));local boot=assert(loadstring(string.sub(src,1,at-1)..'\nreturn boot'))()
 local h=boot();local r={normal=2,legacy=0,player=0,guest=0,total=2,groups=1,allocation={},plan={entries={{kind='normal',account='Alice',tier='t3r',class='mage',role='rdps',race='gnome',gender='female',spec='fire'},{kind='normal',account='Alice',tier='t3r',class='mage',role='rdps',race='gnome',gender='female',spec='fire'}}},estimate={complete=false,known=1,unknown=1,totalCopper=12345}}
 local text=h.C.PlannerPreviewText(r);assert(string.find(text,'Estimated total: unknown',1,true));assert(string.find(text,'Estimated subtotal: 1g 23s 45c',1,true));assert(not string.find(text,'Estimated total: 1g',1,true))
 r.estimate.complete=true;r.estimate.known=2;r.estimate.unknown=0;text=h.C.PlannerPreviewText(r);assert(string.find(text,'Estimated total: 1g 23s 45c',1,true))
end)
print("Shir's Raid Builder estimate tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'estimate regressions failed')
