-- Native registered quote-driver regression; synthetic server/peers only.
local f=assert(io.open('test_pricing_bounds.lua'));local src=f:read('*a');f:close()
local at=assert(string.find(src,"\ntest('settled own",1,true))
local catalog,normal,plan=assert(loadstring(string.sub(src,1,at-1)..'\nreturn catalog,normal,plan'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n..': '..tostring(e))end end
local function pending(n,bank)
 local a,b,c,pump,open,emit,state,rows,names=catalog(n)
 if n==1 then table.insert(rows,normal('Alice'))else table.remove(rows,40)end
 plan(a,rows)
 for i=2,bank do a.env.ShirsRaidBuilderDB.presets['Bank '..i]=a.C.PlannerCopy(a:preset())end
 a:click(a.env.ShirsRaidBuilderMainFrame.syncButton)
 for i=1,160 do pump(0.25);if a.C.visiblePrice and a.C.visiblePrice.phase=='quotes'then break end end
 assert(a.C.visiblePrice and a.C.visiblePrice.phase=='quotes')
 return a,b,c,pump,emit
end
for _,size in ipairs({1,20})do
 test('one source observation per unchanged registered callback size '..size,function()
  local a,b,c,pump=pending(size,100);local C=a.C;local q=assert(C.plannerQuotes);local before=C.PlannerCopy(a:preset());local reads=0;local read=C.PlannerReadSources
  C.PlannerReadSources=function(...)reads=reads+1;return read(unpack(arg))end
  for i=1,12 do a:fire(C.plannerQuoteDriver,'OnUpdate',1/60)end
  assert(C.plannerQuotes==q,'unchanged callback cancelled batch')
  assert(reads==12,'full source constructions for 12 callbacks: '..reads)
  assert(C.PlannerEqual(before,a:preset()),'callback edited plan')
  local beforeRead=reads
  assert(C.PlannerQuoteUnchanged(q),'direct boundary recheck rejected unchanged plan')
  assert(reads==beforeRead+1,'observation escaped its driver callback')
  for i=1,800 do pump(0.25);if C.visiblePrice and C.visiblePrice.phase=='done'then break end end
  assert(C.visiblePrice and C.visiblePrice.estimate and C.visiblePrice.estimate.complete,'completion lost fresh prices')
 end)
end
test('in-place race mutation invalidates next callback and drains submitted work',function()
 local a,b,c,pump=pending(1,1);local C=a.C
 a:fire(C.plannerQuoteDriver,'OnUpdate',1/60)
 a:preset().entries[1].race='human'
 a:fire(C.plannerQuoteDriver,'OnUpdate',1/60)
 assert(not C.plannerQuotes and not C.visiblePrice,'stale callback observation survived mutation')
end)
test('finished consumption always re-reads sources and refuses changed plan',function()
 local a,b,c,pump=pending(1,1);local C=a.C;local w=C.visiblePrice;local reads=0;local read=C.PlannerReadSources
 a:fire(C.plannerQuoteDriver,'OnUpdate',1/60)
 C.PlannerReadSources=function(...)reads=reads+1;return read(unpack(arg))end
 a:preset().entries[1].tier='t2d'
 C.VisiblePriceFinish(w,{})
 assert(not C.visiblePrice and not C.plannerQuotes,'consumption accepted stale plan')
end)
print('quote observation tests: '..pass..' passed, '..fail..' failed');assert(fail==0)
