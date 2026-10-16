-- Current saved plans may mix licences and have holes; ordinals remain per character.
dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua');local C=ShirsRaidBuilderCore
local sources={{key='own:alice',name='Alice',accountId=string.rep('1',16),tiers={'t2d','t3r'},eligible=true},{key='linked:bob',name='Bob',accountId=string.rep('2',16),tiers={'t3r'},eligible=true}}
local function quote(name,tier,count,base,ex,mask,id)return {name=name,tier=tier,count=count,max=4,base=base,ex=ex,qbase=base+20,qex=ex+2,mask=mask,friendly='17',accountId=string.rep(tostring(id),16),received=100} end
local function estimate(entries,quotes)
 local r={plan={entries=entries},allocation={}};C.PlannerEstimate(r,sources,{planQuotes=quotes,quoteNow=100,sources={}});return r.estimate
end
local q={['own:alice:t3r']=quote('Alice','t3r',1,9000,900,'7',1),['own:alice:t2d']=quote('Alice','t2d',1,3000,300,'1',1),['linked:bob:t3r']=quote('Bob','t3r',0,1000,100,'1',2)}
local function row(name,tier,race)return {kind='normal',account=name,tier=tier,race=race or 'gnome',class='mage',role='rdps'} end
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n..': '..tostring(e)) end end

test('sparse actual slots and mixed selected licences preserve each character remaining ordinal',function()
 local t=estimate({[2]=row('Alice','t3r'),[9]=row('Bob','t3r','human'),[31]=row('Alice','t2d','human')},q)
 assert(t.complete and t.known==3 and t.totalCopper==1500,'sparse row or second licence restarted ordinals') -- 900 + 100 + 500
end)
test('a missing first-licence quote does not shift a later known hire to a cheaper ordinal',function()
 local t=estimate({row('Alice','t4r'),row('Alice','t3r')},q)
 assert(not t.complete and t.known==1 and t.unknown==1 and t.totalCopper==1500,'unknown hire skipped remaining ordinal')
end)
test('inconsistent counts for one character invalidate every licence quote for that character',function()
 local quotes=C.PlannerCopy(q);quotes['own:alice:t2d'].count=2
 local t=estimate({row('Alice','t3r'),row('Alice','t2d','human'),row('Bob','t3r','human')},quotes)
 assert(not t.complete and t.known==1 and t.unknown==2 and t.totalCopper==100,'mixed licence counts invented full total')
end)
test('remaining cap applies across licences, not separately per tier',function()
 local quotes=C.PlannerCopy(q);quotes['own:alice:t3r'].count=2;quotes['own:alice:t2d'].count=2
 local t=estimate({row('Alice','t3r'),row('Alice','t2d','human'),row('Alice','t3r')},quotes)
 assert(not t.complete and t.known==2 and t.unknown==1 and t.totalCopper==1500,'tier switch bypassed cap')
end)
print("Shir's Raid Builder visible price ordinal tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'visible ordinal regressions failed')
