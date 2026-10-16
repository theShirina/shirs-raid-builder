-- Native quote events/rate backoff. Every refusal here is explicitly synthetic.
local f=assert(io.open('test_planner_linked_quotes.lua'));local src=f:read('*a');f:close();local at=assert(string.find(src,"\ntest('mixed own",1,true));local fixture=assert(loadstring(string.sub(src,1,at-1)..'\nreturn fixture'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n..': '..tostring(e))end end
local function normal(name)return {kind='normal',account=name,tier='t3r',class='mage',role='rdps',spec='fire',race='gnome',gender='female'}end
local function setplan(h,rows)local p=h:preset();p.entries={};for i=1,40 do p.entries[i]=rows[i]or{kind='empty'}end;p.entries[40]={kind='player',charName=h.name,class='warrior',role='tank'};p.plannerPlayerSlot=40;h.env.RefreshComposition()end
local function waitflight(h,pump)for i=1,120 do pump(0.25);if h.C.plannerQuoteFlight then return h.C.plannerQuoteFlight end end;error('no server flight')end
local function refusal(h,emit,text)emit(h,'CHAT_MSG_SYSTEM',text or 'Price request rate limit reached. Please wait.','')end
local function reply(h,emit,name)emit(h,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE '..name..':1000:1000:0:0:1000:1000:0:4','nexus')end

test('synthetic server rate warning stops submitted work but never drains a character-only flight',function()
 local a,b,c,pump,open,emit=fixture();a.noReply=true;local p=open(a,{Alice=true},1);a:click(p.buildButton);local flight=waitflight(a,pump);refusal(a,emit);pump(0.25)
 assert(not a.C.plannerQuotes and not p.proposal and a.C.plannerQuoteFlight==flight and flight.drain,'rate refusal did not stop and retain drain')
 assert(string.find(string.lower(p.message:GetText()),'rate limit',1,true),'rate reason hidden')
 for i=1,12 do a:click(p.buildButton)end;pump(16);assert(table.getn(a.quoteReads)==1 and a.C.plannerQuoteFlight==flight,'retry or timeout bypassed drain')
end)

test('drained rate warning keeps a shared five-second cooldown across Build and peer jobs',function()
 local a,b,c,pump,open,emit=fixture();a.noReply=true;local p=open(a,{Alice=true},1);a:click(p.buildButton);waitflight(a,pump);refusal(a,emit);reply(a,emit,'Alice');pump(0.25)
 assert(not a.C.plannerQuoteFlight,'matching result did not drain');local refusedAt=a.now;a.noReply=false
 for i=1,8 do a:click(p.buildButton)end;pump(2)
 assert(table.getn(a.quoteReads)==1,'cooldown repeated Build sent more server reads')
 local pb=open(b,{Alice=true},1);b:click(pb.buildButton);pump(1);assert(table.getn(a.quoteReads)==1,'peer job bypassed shared cooldown')
 assert(a.C.quoteBackoffUntil and a.C.quoteBackoffUntil>=refusedAt+4,'shared backoff missing')
 pump(6);assert(table.getn(a.quoteReads)==1,'backoff restarted cancelled work automatically')
 a:click(p.buildButton);pump(8);assert(p.proposal,p.message:GetText());assert(table.getn(a.quoteReads)==2,'explicit retry did not recover')
end)

test('actual linked RATE envelope marks that account unpriced without continuing its queued source storm',function()
 local file=assert(io.open('test_pricing_bounds.lua'));local text=file:read('*a');file:close();local cut=assert(string.find(text,"\ntest('settled own",1,true));local catalog=assert(loadstring(string.sub(text,1,cut-1)..'\nreturn catalog'))()
 local a,b,c,pump,open,emit,state=catalog(3)
 setplan(a,{normal('Bob'),normal('Bobab'),normal('Bobac'),normal('Carol')});a:click(a.env.ShirsRaidBuilderMainFrame.syncButton)
 local rateSent=false;local finish=b.C.QuoteEvent;b.C.QuoteEvent=function(p,sender)
  if p.kind=='H' and not rateSent then rateSent=true;b.C.QuoteQueue(b.C.peerState,'E',p,'RATE');return end;return finish(p,sender)
 end
 for i=1,240 do pump(0.25);if a.C.visiblePrice and a.C.visiblePrice.phase=='done'then break end end
 local w=assert(a.C.visiblePrice,'visible cancelled: '..tostring(a.C.visiblePriceWhy)..' rate='..tostring(rateSent)..' reads='..table.getn(b.quoteReads)..'/'..table.getn(c.quoteReads));assert(rateSent and w.phase=='done'and w.estimate.known==1 and w.estimate.unknown==3,'RATE did not quarantine account with honest partial result')
 assert(table.getn(b.quoteReads)==0 and table.getn(c.quoteReads)==1,'new source requests continued after RATE')
 assert(w.reason and string.find(string.lower(w.reason),'rate limit',1,true),'raw RATE or generic protocol advice replaced actionable reason')
 local n=table.getn(b.quoteReads);pump(130);assert(table.getn(b.quoteReads)==n,'RATE retried in background')
end)

test('repeated Refresh during native pending price check coalesces; peer Refresh preserves flight',function()
 local a,b,c,pump,open,emit=fixture();b.noReply=true;setplan(a,{normal('Bob'),normal('Carol')});a:click(a.env.ShirsRaidBuilderMainFrame.syncButton);local flight=waitflight(b,pump)
 local q=a.C.plannerQuotes;for i=1,20 do a:click(a.env.ShirsRaidBuilderMainFrame.syncButton)end;b:click(b.env.ShirsRaidBuilderMainFrame.syncButton);pump(1)
 assert(a.C.plannerQuotes==q and b.C.plannerQuoteFlight==flight and table.getn(b.quoteReads)==1,'Refresh duplicated or replaced work')
 reply(b,emit,'Bob');pump(8);assert(a.C.visiblePrice and a.C.visiblePrice.estimate.complete,'Refresh lost valid result')
end)

test('late G admitted before a rate warning cannot restart after cooldown',function()
 local a,b,c,pump,open,emit,state=fixture();local p=open(a,{Bob=true});a:click(p.buildButton)
 for i=1,80 do pump(0.25);local q=a.C.plannerQuotes;if q and q.wait and q.wait.stage=='quote'and not b.C.plannerQuoteFlight then break end end
 local q=assert(a.C.plannerQuotes);assert(q.wait and q.wait.stage=='quote'and not b.C.plannerQuoteFlight,'missed native H/A -> G transition')
 b.C.QuoteRateLimit();pump(8);assert(table.getn(b.quoteReads)==0 and not p.proposal and table.getn(b.C.quoteJobs or {})==0,'late admitted G restarted work after a rate notice')
end)

test('unrelated system text and whispers cannot manufacture a settled quote or rate refusal',function()
 local a,b,c,pump,open,emit=fixture();a.noReply=true;local p=open(a,{Alice=true});a:click(p.buildButton);local flight=waitflight(a,pump)
 emit(a,'CHAT_MSG_WHISPER','rate limit reached','Bob');emit(a,'CHAT_MSG_SYSTEM','The game has been saved.','');pump(0.25)
 assert(a.C.plannerQuotes and a.C.plannerQuoteFlight==flight and not flight.drain and not a.C.quoteBackoffUntil)
end)

print("Shir's Raid Builder quote rate tests: "..(fail==0 and 'PASS'or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0)
