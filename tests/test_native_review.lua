-- Registered peer Refresh/Stop controls and real quote jobs; synthetic clients.
local f=assert(io.open('test_planner_linked_quotes.lua'));local src=f:read('*a');f:close()
local at=assert(string.find(src,"\ntest('mixed own",1,true));local fixture=assert(loadstring(string.sub(src,1,at-1)..'\nreturn fixture'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n..': '..tostring(e))end end
local function normal(name)return {kind='normal',account=name,tier='t3r',class='mage',role='rdps',race='gnome',gender='female',spec='fire'}end
local function plan(h,rows)
 local p=h:preset();p.entries={};for i=1,40 do p.entries[i]=rows[i]or{kind='empty'}end
 p.entries[40]={kind='player',charName=h.name,class='warrior',role='tank'};p.plannerPlayerSlot=40;h.env.RefreshComposition()
end
local function refresh(h)h:click(h.env.ShirsRaidBuilderMainFrame.syncButton)end
local function settle(h,pump)
 for i=1,640 do pump(0.25);if h.C.visiblePrice and h.C.visiblePrice.phase=='done'then return h.C.visiblePrice end end
 error('native price result did not settle: '..tostring(h.C.visiblePriceWhy))
end
local function reply(emit,h,name)emit(h,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE '..name..':1000:1000:0:0:1000:1000:0:4','nexus')end

for _,peerRefresh in ipairs({false,true})do
 test('6.25s server response with peer Refresh='..tostring(peerRefresh),function()
  local a,b,c,pump,open,emit,state=fixture();b.noReply=true;plan(a,{normal('Bob'),normal('Carol')});refresh(a)
  for i=1,200 do pump(0.25);if b.C.plannerQuoteFlight then break end end
  local flight=assert(b.C.plannerQuoteFlight);pump(6);local s=state(b,'Alice');local nonce=s.a
  assert(s.expires-b.wall==35,'review timing/lease control drifted')
  if peerRefresh then refresh(b)end
  pump(0.25);assert(b.now-flight.started==6.25 and s.a==nonce and s.phase=='linked','Refresh replaced active job')
  reply(emit,b,'Bob');local w=settle(a,pump)
  assert(w.estimate.known==2 and w.estimate.unknown==0 and w.estimate.totalCopper==2000,'in-deadline reply dropped')
  assert(table.getn(b.quoteReads)==1 and table.getn(c.quoteReads)==1)
 end)
end

test('registered peer Refresh defers renewal while another request is queued behind a real flight',function()
 local a,b,c,pump,open,emit,state=fixture();b.noReply=true;local pa=open(a,{Bob=true});local pc=open(c,{Bob=true})
 a:click(pa.buildButton)
 for i=1,80 do pump(0.25);if b.C.plannerQuoteFlight then break end end
 c:click(pc.buildButton)
 for i=1,80 do pump(0.25);if table.getn(b.C.quoteJobs or {})>0 then break end end
 assert(b.C.plannerQuoteFlight and b.C.plannerQuoteFlight.job and table.getn(b.C.quoteJobs or {})==1,'no actual queued server job')
 local job=b.C.quoteJobs[1];local nonce=job.state.a;refresh(b);pump(0.25)
 assert(job.state.phase=='linked'and job.state.a==nonce,'Refresh cancelled queued job')
 reply(emit,b,'Bob');pump(1)
 assert(b.C.plannerQuoteFlight and b.C.plannerQuoteFlight.job,'queued second read was lost');reply(emit,b,'Bob');pump(3)
 assert(pa.proposal and pc.proposal,'queued/active native Build failed after peer Refresh')
 assert(table.getn(b.quoteReads)==2 and b.quoteReads[2].at-b.quoteReads[1].at>=0.7,'server serialization lost')
end)

test('multi-lane Stop cancels every pending peer and retains both character-only drain fences',function()
 local a,b,c,pump,open,emit=fixture();b.noReply=true;c.noReply=true;plan(a,{normal('Bob'),normal('Carol')});refresh(a)
 for i=1,200 do pump(0.25);if b.C.plannerQuoteFlight and c.C.plannerQuoteFlight then break end end
 assert(b.C.plannerQuoteFlight and c.C.plannerQuoteFlight,'independent clients did not run together')
 a:click(a.env.ShirsRaidBuilderMainFrame.stopBtn);pump(1)
 assert(not a.C.visiblePrice and not a.C.plannerQuotes and b.C.plannerQuoteFlight.drain and c.C.plannerQuoteFlight.drain,'Stop missed a lane')
 reply(emit,b,'Bob');reply(emit,c,'Carol');pump(2)
 assert(not a.C.visiblePrice and not b.C.plannerQuoteFlight and not c.C.plannerQuoteFlight,'late stopped result returned')
 b.noReply=false;c.noReply=false;refresh(a);local w=settle(a,pump);assert(w.estimate.complete and w.estimate.totalCopper==2000,'retry reused cancelled result')
end)

test('unresolved local timeout never advances a second same-client licence read',function()
 local a,b,c,pump,open,emit=fixture();a.noReply=true
 local second=normal('Alice');second.tier='t2d';plan(a,{normal('Alice'),second,normal('Bob')});refresh(a)
 local w=settle(a,pump);assert(a.C.plannerQuoteFlight and a.C.plannerQuoteFlight.drain,'timeout lost unresolved flight')
 assert(table.getn(a.quoteReads)==1 and w.estimate.unknown>=2,'unresolved character reply bypassed')
 reply(emit,a,'Alice');pump(1);assert(not a.C.plannerQuoteFlight,'matching old reply did not drain')
end)

test('explicit source approval revocation remains terminal for an active reply despite Refresh busy deferral',function()
 local a,b,c,pump,open,emit,state=fixture();b.noReply=true;plan(a,{normal('Bob')});refresh(a)
 for i=1,200 do pump(0.25);if b.C.plannerQuoteFlight then break end end
 local s=state(b,'Alice');local old=s.a;refresh(b)
 b.C.OpenPeerPOC();b.C.peerPanel.nameInput:SetText('Alice');b:click(b.C.peerPanel.forgetButton);reply(emit,b,'Bob');pump(2)
 assert(s.a~=old and table.getn(b.quoteReads)==1,'explicit abort was ignored')
 local w=settle(a,pump);assert(w.estimate.unknown==1 and w.estimate.known==0,'invalid session reply supplied a price')
end)

test('peer Refresh also preserves the live hello-to-job transition',function()
 local a,b,c,pump,open,emit,state=fixture();local p=open(a,{Bob=true});a:click(p.buildButton)
 for i=1,80 do pump(0.25);local q=a.C.plannerQuotes;if q and q.wait and q.wait.stage=='quote'and not b.C.plannerQuoteFlight then break end end
 local q=assert(a.C.plannerQuotes);assert(q.wait and q.wait.stage=='quote'and not b.C.plannerQuoteFlight,'hello transition fixture missed')
 local s=state(b,'Alice');local nonce=s.a;refresh(b);assert(s.a==nonce and s.phase=='linked','Refresh replaced live hello transition')
 pump(5);assert(p.proposal,p.message:GetText())
end)

print("Shir's Raid Builder native review tests: "..(fail==0 and 'PASS'or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'native review regressions')
