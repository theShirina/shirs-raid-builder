-- Native registered Refresh/quote callbacks. Synthetic transport, no game input.
local f=assert(io.open('test_planner_linked_quotes.lua'));local text=f:read('*a');f:close()
local cut=assert(string.find(text,"\ntest('mixed own",1,true));local fixture=assert(loadstring(string.sub(text,1,cut-1)..'\nreturn fixture'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n..': '..tostring(e))end end
local function normal(name)return {kind='normal',account=name,tier='t3r',class='mage',role='rdps',race='gnome',gender='female',spec='fire'}end
local function plan(h,rows)
 local p=h:preset();p.entries={};for i=1,40 do p.entries[i]=rows[i]or{kind='empty'}end
 p.entries[40]={kind='player',charName=h.name,class='warrior',role='tank'};p.plannerPlayerSlot=40;h.env.RefreshComposition();return p
end
local function refresh(h)h:click(h.env.ShirsRaidBuilderMainFrame.syncButton)end
local function settle(h,pump)
 for i=1,800 do pump(0.25);if h.C.visiblePrice and h.C.visiblePrice.phase=='done'then return h.C.visiblePrice end end
 error('unsettled native price check: '..tostring(h.C.visiblePriceWhy))
end
local function suffix(i)return string.char(97+math.floor((i-1)/26))..string.char(97+math.mod(i-1,26))end
local function catalog(n)
 local a,b,c,pump,open,emit,state=fixture();local rows,names={},{}
 for side,h in ipairs({b,c})do
  local roster={}
  for i=1,n do
   local name=i==1 and h.name or h.name..suffix(i);h.prices[name]=1000+side*100+i
   table.insert(roster,name..':mage:t2d:t3r:A:0:60:0:4');table.insert(rows,normal(name));names[name]=true
  end
  h.roster=table.concat(roster,' ')
 end
 plan(a,{});refresh(a)
 for i=1,400 do pump(0.25);if a.C.peerRefreshBatch and a.C.peerRefreshBatch.done then break end end
 local found=0;for _,s in ipairs(a.C.PlannerReadSources())do if names[s.name]then assert(s.eligible and s.capacity==4 and not s.conflict);found=found+1 end end
 assert(found==2*n,'native roster missing valid sources: '..found)
 return a,b,c,pump,open,emit,state,rows,names
end
local function safe(a,b,c)
 for _,h in ipairs({a,b,c})do
  assert(not h.C.handAuthority and not h.C.handRunPlan,'price check granted hiring authority')
  local contexts={}
  for i,read in ipairs(h.quoteReads)do
   local key=read.name..':'..read.tier;contexts[key]=(contexts[key]or 0)+1
   assert(contexts[key]<=2,'more than two reads of one exact source/licence context')
   if i>1 then assert(read.at-h.quoteReads[i-1].at>=0.7,'character-only server reads overlap')end
  end
 end
end
local function idle(a,b,c,pump)
 local reads=table.getn(a.quoteReads)+table.getn(b.quoteReads)+table.getn(c.quoteReads)
 pump(130);assert(reads==table.getn(a.quoteReads)+table.getn(b.quoteReads)+table.getn(c.quoteReads),'completed batch started background quotes')
end
local function exact(a,b,c,w,rows)
 local expected=0;local wanted={}
 for _,r in ipairs(rows)do expected=expected+(b.prices[r.account]or c.prices[r.account]);wanted[r.account]=true end
 assert(w.estimate.complete and w.estimate.known==table.getn(rows)and w.estimate.unknown==0 and w.estimate.totalCopper==expected,'fresh complete estimate absent: '..w.estimate.known..'/'..w.estimate.unknown..' '..tostring(w.reason))
 local oldest=0;for _,q in pairs(w.quotes)do
  assert(wanted[q.name]and q.base==(b.prices[q.name]or c.prices[q.name]),'source-specific price crossed')
  assert(q.accountId==(b.prices[q.name]and '2222222222222222'or '3333333333333333')and q.tier=='t3r','identity or licence crossed')
  oldest=math.max(oldest,a.now-q.received)
 end
 assert(oldest<=25 and w.expires-a.now>=5,'result has no usable fresh display window')
 print('  rows='..table.getn(rows)..' oldest='..oldest..' remaining='..(w.expires-a.now)..'s reads='..table.getn(b.quoteReads)..'/'..table.getn(c.quoteReads))
end

test('settled own refusal continues later own and linked sources',function()
 local a,b,c,pump=fixture();a.counts.Alice=4;a.prices.Alina=700
 a.roster='Alice:warrior:t2d:t3r:A:0:60:0:4 Alina:mage:t2d:t3r:A:0:60:0:4'
 a.env.ShirsRaidBuilderDB.inviteCharacters.Alina={name='Alina',level=60,dungeonLicense='t2d',raidLicense='t3r',faction='Alliance'}
 plan(a,{normal('Alice'),normal('Alina'),normal('Bob'),normal('Carol')});refresh(a);local w=settle(a,pump)
 assert(w.estimate.known==3 and w.estimate.unknown==1 and w.estimate.totalCopper==2700,'settled refusal aborted independent sources')
 assert(table.getn(a.quoteReads)==2 and table.getn(b.quoteReads)==1 and table.getn(c.quoteReads)==1);safe(a,b,c)
end)

for _,n in ipairs({10,20})do
 test('native '..(2*n)..'-character catalogue prices valid board with one human tail',function()
  local a,b,c,pump,open,emit,state,rows=catalog(n)
  if table.getn(rows)==40 then table.remove(rows,40)end -- 39 normals + human = 40 occupied slots
  plan(a,rows);local saved=a.C.PlannerCopy(a:preset());local started=a.now;local syncAt
  local collect=a.C.VisiblePriceCollect;a.C.VisiblePriceCollect=function(w)syncAt=a.now;return collect(w)end
  refresh(a);local w=settle(a,pump);exact(a,b,c,w,rows)
  print('  sync='..(syncAt-started)..'s quotes='..(a.now-syncAt)..'s')
  assert(table.getn(b.quoteReads)+table.getn(c.quoteReads)==table.getn(rows),'responsive batch duplicated background reads')
  assert(a.C.PlannerEqual(saved,a:preset()),'collection edited visible plan');pump(0.25);assert(a.C.visiblePrice==w,'zero-delay native result immediately expired')
  safe(a,b,c);idle(a,b,c,pump)
 end)
end

test('native Build checks forty selected distinct source contexts before a 39-hire proposal',function()
 local a,b,c,pump,open,emit,state,rows,names=catalog(20);local p=open(a,names,39);p.request.saveGold=false
 a:click(p.buildButton)
 for i=1,800 do pump(0.25);if p.proposal or not a.C.plannerQuotes and not a.C.plannerSync then break end end
 local r=assert(p.proposal,p.message:GetText());local count=0
 for _,q in pairs(p.request.quotes)do count=count+1;assert(a.now-q.received<=30 and q.base==(b.prices[q.name]or c.prices[q.name]))end
 assert(count==40 and r.estimate.complete and r.normal==39 and r.plan.entries[40].charName=='Alice','selected source coverage/40-slot proposal failed')
 assert(table.getn(b.quoteReads)+table.getn(c.quoteReads)==40,'responsive forty-context batch re-quoted unnecessarily');safe(a,b,c);idle(a,b,c,pump)
end)

test('slow server collection ends bounded and never presents stale prices or an expired footer',function()
 local a,b,c,pump,open,emit,state,rows=catalog(20);table.remove(rows,40);plan(a,rows);b.noReply=true;c.noReply=true
 local batch;local start=a.C.QuoteStartBatch;a.C.QuoteStartBatch=function(...)
  local ok,why=start(unpack(arg));batch=a.C.plannerQuotes or batch;return ok,why
 end
 refresh(a);local sent={};local started=a.now;local w
 for i=1,800 do
  pump(0.25)
  for _,h in ipairs({b,c})do local flight=h.C.plannerQuoteFlight
   if flight and not flight.drain and not sent[flight]and h.now-flight.started>=2 then
    sent[flight]=true;local price=h.prices[flight.source.name]
    emit(h,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE '..flight.source.name..':'..price..':'..price..':0:0:'..price..':'..price..':0:4','nexus')
   end
  end
  w=a.C.visiblePrice;if w and w.phase=='done'then break end
 end
 assert(w and w.phase=='done'and a.now-started<=190,'unbounded revalidation/renewal')
 assert(not w.estimate.complete and w.estimate.unknown>0,'slow batch falsely complete')
 assert(table.getn(b.quoteReads)+table.getn(c.quoteReads)<=78,'more than one revalidation per exact source context')
 for _,q in pairs(w.quotes)do assert(a.now-q.received<=25,'stale/near-expiry quote retained in partial result')end
 if w.estimate.known>0 then assert(w.expires-a.now>=5,'partial footer already expiring')end
 local renewals=0;for _,n in pairs(assert(batch).renewals)do assert(n<=2,'renewal exceeded bound');renewals=renewals+n end
 assert(renewals>0,'fixture never renewed a needed link while quote batch pending')
 print('  slow total='..(a.now-started)..'s known='..w.estimate.known..' unknown='..w.estimate.unknown..' reads='..table.getn(b.quoteReads)..'/'..table.getn(c.quoteReads)..' renewals='..renewals)
 assert(w.reason and string.len(w.reason)>0,'partial result hides bounded collection reason');safe(a,b,c);idle(a,b,c,pump)
end)

test('one bounded fresh pass recovers a transient delay without extending quote freshness',function()
 local a,b,c,pump,open,emit,state,rows=catalog(10);plan(a,rows);b.noReply=true
 local batch;local start=a.C.QuoteStartBatch;a.C.QuoteStartBatch=function(...)
  local ok,why=start(unpack(arg));batch=a.C.plannerQuotes or batch;return ok,why
 end
 local finish=a.C.QuoteCollectionFinish;a.C.QuoteCollectionFinish=function(q)
  local was=q.revalidated;finish(q)
  if not was and q.revalidated then
   for _,h in ipairs({b,c})do for name,price in pairs(h.prices)do h.prices[name]=price+100 end end
  end
 end
 refresh(a);local delayed=false;local w
 for i=1,800 do
  pump(0.25);local flight=b.C.plannerQuoteFlight
  if not delayed and flight and not flight.drain and b.now-flight.started>=14 then
   delayed=true;b.noReply=false;local price=b.prices[flight.source.name]
   emit(b,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE '..flight.source.name..':'..price..':'..price..':0:0:'..price..':'..price..':0:4','nexus')
  end
  w=a.C.visiblePrice;if w and w.phase=='done'then break end
 end
 assert(delayed and batch and batch.revalidated,'fixture did not exercise a real corrective pass')
 exact(a,b,c,w,rows)
 assert(table.getn(b.quoteReads)+table.getn(c.quoteReads)<=40,'corrective pass repeated indefinitely');safe(a,b,c);idle(a,b,c,pump)
end)

print("Shir's Raid Builder pricing bounds tests: "..(fail==0 and 'PASS'or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'pricing collection bounds regressions')
