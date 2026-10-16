-- Adversarial checks through registered trusted-link and server receive events.
local f=assert(io.open('test_planner_linked_quotes.lua'));local t=f:read('*a');f:close()
local at=assert(string.find(t,"\ntest('mixed own",1,true));local fixture=assert(loadstring(string.sub(t,1,at-1)..'\nreturn fixture'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n..': '..tostring(e)) end end
local function waiting()
 local a,b,c,pump,open,emit,state=fixture();b.noReply=true;local p=open(a,{Bob=true});a:click(p.buildButton);pump(2)
 local w=assert(a.C.plannerQuotes and a.C.plannerQuotes.wait,'no pending peer request');assert(b.C.plannerQuoteFlight and b.C.plannerQuoteFlight.job,'peer server query did not start')
 return a,b,c,pump,p,emit,state,w
end
local function server(emit,h,name,price,count)emit(h,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE '..name..':'..price..':'..price..':0:0:'..price..':'..price..':'..(count or 0)..':4','nexus')end
local function packet(b,state,w,kind,data,field,value)
 local q={nonce=w.nonce,requester=w.requester,owner=w.owner,name=w.name,tier=w.tier};if field then q[field]=value end
 return assert(b.C.QuotePacket(state(b,'Alice'),kind,q,data))
end

test('spoof wrong account source tier nonce link version and arbitrary whispered prices cannot resolve a pending quote',function()
 local a,b,c,pump,p,emit,state,w=waiting();local good=packet(b,state,w,'P','1000:1000:1000:1000')
 for _,from in ipairs({'Mallory','Carol','Alice'}) do emit(a,'CHAT_MSG_WHISPER',good,from) end
 for _,change in ipairs({{'owner','3333333333333333'},{'requester','9999999999999999'},{'name','Alice'},{'tier','t2r'},{'nonce','999999'}}) do emit(a,'CHAT_MSG_WHISPER',packet(b,state,w,'P','1000:1000:1000:1000',change[1],change[2]),'Bob') end
 emit(a,'CHAT_MSG_WHISPER',string.gsub(good,'SRBQUOTE1','SRBQUOTE2'),'Bob')
 emit(a,'CHAT_MSG_WHISPER',string.gsub(good,';'..w.a..';',';999999;'),'Bob')
 emit(a,'CHAT_MSG_WHISPER','[nexus] ACINFO:COST:INVITE Bob:1:1:0:0:1:1:0:4','Bob')
 assert(a.C.plannerQuotes.wait==w and not w.price and not p.proposal,'unsolicited data authorized a price')
 assert(not a.C.peerSessions['FixtureRealm;mallory'],'untrusted price created a session')
 server(emit,b,'Bob',1000);pump(2);assert(p.proposal,p.message:GetText())
 local before=table.getn(b.quoteReads)
 for _,item in ipairs(a.quotePackets) do local q=a.C.QuoteParse(item.text);if q.kind=='H' or q.kind=='G' then emit(b,'CHAT_MSG_WHISPER',item.text,'Alice') end end
 pump(1);assert(table.getn(b.quoteReads)==before,'replay sent another server request')
end)

test('cancel removes pending peer work and late replies cannot restart a Build',function()
 local a,b,c,pump,p,emit,state,w=waiting();a:click(p.buildButton);pump(1)
 assert(not a.C.plannerQuotes and b.C.plannerQuoteFlight and b.C.plannerQuoteFlight.drain,'peer cancellation did not fence its server flight')
 server(emit,b,'Bob',1000);pump(1)
 emit(a,'CHAT_MSG_WHISPER',packet(b,state,w,'P','1000:1000:1000:1000'),'Bob')
 emit(a,'CHAT_MSG_WHISPER',packet(b,state,w,'M','0:0:0:4:'..a.wall),'Bob');pump(1)
 assert(not p.proposal and not a.C.plannerQuotes and not b.C.plannerQuoteFlight and table.getn(b.C.quoteJobs or {})==0,'late peer reply revived cancelled work')
end)

test('tier handler cancels old quote and a new run cannot accept the old peer nonce',function()
 local a,b,c,pump,p,emit,state,w=waiting();a:click(a:button(p,'Sources'))
 for _,r in ipairs(p.sourceRows) do if r.source.name=='Bob' then a:choose(r.tierButton,'t2r') end end
 pump(1);server(emit,b,'Bob',1000);pump(1);b.noReply=false;b.prices.Bob=500
 a:click(p.buildButton);emit(a,'CHAT_MSG_WHISPER',packet(b,state,w,'P','1:1:1:1'),'Bob');emit(a,'CHAT_MSG_WHISPER',packet(b,state,w,'M','0:0:0:4:'..a.wall),'Bob')
 pump(4);local r=assert(p.proposal,p.message:GetText());assert(b.quoteReads[2].tier=='t2r')
 for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then assert(e.tier=='t2r') end end
 assert(p.request.quotes[w.key].base==500 and p.request.quotes[w.key].requestId~=w.nonce,'old tier reply became new-tier authority')
end)

test('unknown or old peer quote protocol times out visibly without a local-account substitute',function()
 local a,b,c,pump,open,emit=fixture();local previous=b.C.peerDriver:GetScript('OnEvent')
 b.C.peerDriver:SetScript('OnEvent',function()if b.env.event=='CHAT_MSG_WHISPER' and b.C.QuoteParse(b.env.arg1) then return end;previous()end)
 local p=open(a,{Bob=true});a:click(p.buildButton);pump(10)
 assert(not p.proposal and not a.C.plannerQuotes and table.getn(a.quoteReads)==0 and table.getn(b.quoteReads)==0)
 local text=string.lower(p.message:GetText());assert(string.find(text,'timeout',1,true) and string.find(text,'both clients',1,true),'missing peer version/offline feedback')
end)

test('conflicting response parts stale metadata and exhausted source counts fail visibly',function()
 local a,b,c,pump,p,emit,state,w=waiting()
 emit(a,'CHAT_MSG_WHISPER',packet(b,state,w,'P','1000:1000:1000:1000'),'Bob')
 emit(a,'CHAT_MSG_WHISPER',packet(b,state,w,'P','1001:1000:1000:1000'),'Bob');assert(not a.C.plannerQuotes and not p.proposal)
 a,b,c,pump,p,emit,state,w=waiting();emit(a,'CHAT_MSG_WHISPER',packet(b,state,w,'P','1000:1000:1000:1000'),'Bob');emit(a,'CHAT_MSG_WHISPER',packet(b,state,w,'M','0:0:0:4:'..(a.wall-31)),'Bob');assert(not a.C.plannerQuotes and not p.proposal)
 a,b,c,pump,p,emit,state,w=waiting();server(emit,b,'Bob',1000,4);pump(2);assert(not a.C.plannerQuotes and not p.proposal and string.find(p.message:GetText(),'capacity',1,true))
end)

test('MCP Invite conflict on either client invalidates the read and changes no MCP selection globals',function()
 for _,side in ipairs({'local','peer'}) do
  local a,b,c,pump,p,emit,state,w=waiting();local h=side=='local' and a or b
  h.env.MCP_InviteName='Untouched';h.env.MCP_InviteLicItr=5;h.env.MCPInviteFrame=h.env.CreateFrame('Frame')
  server(emit,b,'Bob',1000);pump(2)
  assert(not p.proposal and not a.C.plannerQuotes,'MCP conflict accepted a quote')
  assert(h.env.MCP_InviteName=='Untouched' and h.env.MCP_InviteLicItr==5,'MCP globals were hijacked')
  if side=='peer' then assert(h.C.quoteUnsafeMCP,'overlapping character-only server replies not fenced') end
 end
end)

test('a peer becoming busy before its server reply cannot return a usable quote',function()
 local a,b,c,pump,p,emit,state,w=waiting();b.C.sortFrame={busy=true};server(emit,b,'Bob',1000);b.C.sortFrame.busy=false;pump(2)
 assert(not p.proposal and not a.C.plannerQuotes,'busy peer supplied a price from changed live work')
end)

test('two simultaneous initiators share one peer server reader without crossing request identities',function()
 local a,b,c,pump,open,emit,state=fixture()
 -- All three relationships completed their real handshake and account read.
 local pa=open(a,{Bob=true});local pc=open(c,{Bob=true});a:click(pa.buildButton);c:click(pc.buildButton);pump(8)
 assert(pa.proposal,pa.message:GetText());assert(pc.proposal,pc.message:GetText());assert(table.getn(b.quoteReads)==2,'concurrent peer reads were dropped or duplicated')
 assert(b.quoteReads[2].at-b.quoteReads[1].at>=0.7,'server queries overlapped')
 local qa=pa.request.quotes['2222222222222222:bob'];local qc=pc.request.quotes['2222222222222222:bob'];assert(qa.requestId~=qc.requestId and qa.base==qc.base,'requester identity crossed')
end)

test('quote quiet filtering is structural trusted and display-only in both modes',function()
 for _,quiet in ipairs({true,false}) do
  local a,b,c,pump,open,emit,state=fixture();local p=open(a,{Bob=true});local seen,received=0,0
  a.env.ChatFrame_OnEvent=function()seen=seen+1 end;a.C.InstallHandoffChatFilter();a.env.ShirsRaidBuilderDB.quietMode=quiet
  local previous=a.C.QuoteEvent;a.C.QuoteEvent=function(...)received=received+1;return previous(unpack(arg))end
  a:click(p.buildButton);pump(4);assert(p.proposal,p.message:GetText());assert(received>=3,'display flag blocked protocol receipt')
  for _,item in ipairs(b.quotePackets) do a.env.arg1=item.text;a.env.arg2='Bob';a.env.ChatFrame_OnEvent('CHAT_MSG_WHISPER') end
  assert(seen==(quiet and 0 or table.getn(b.quotePackets)),'quote packet display did not follow Quiet')
  a.env.arg1='Price error: refresh the peer';a.env.arg2='Bob';a.env.ChatFrame_OnEvent('CHAT_MSG_WHISPER');local before=seen
  a.env.arg1=b.quotePackets[1].text;a.env.arg2='Mallory';a.env.ChatFrame_OnEvent('CHAT_MSG_WHISPER');assert(seen==before+1,'untrusted whisper suppressed')
  a.env.arg1='SRBQUOTE1;arbitrary price';a.env.arg2='Bob';a.env.ChatFrame_OnEvent('CHAT_MSG_WHISPER');assert(seen==before+2,'ordinary/malformed whisper suppressed')
 end
end)

print("Shir's Raid Builder quote safety tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'quote safety regressions failed')
