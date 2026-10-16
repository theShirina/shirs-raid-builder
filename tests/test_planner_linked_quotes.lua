-- Actual registered link/account/Build/timer events in isolated Vanilla clients.
-- All server messages are synthetic; this never performs game input or paid hires.
local file=assert(io.open('test_sync_ui.lua'));local src=file:read('*a');file:close()
local boundary=assert(string.find(src,"\nlocal a,b,c=client('Alice')",1,true))
local client,emit,run,pair,state=assert(loadstring(string.sub(src,1,boundary-1)..'\nreturn client,emit,run,pair,state'))()
local pass,fail=0,0
local function test(name,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..name) else fail=fail+1;print('FAIL '..name..': '..tostring(e)) end end
local function fixture()
 local clients,byName={},{}
 for i,name in ipairs({'Alice','Bob','Carol'}) do
  local db={syncAccountId=string.rep(tostring(i),16),currentPreset='Default',presets={Default={entries={},denyRules={},setupRules={}}},inviteCharacters={[name]={name=name,level=60,dungeonLicense='t2d',raidLicense='t3r',faction='Alliance'}}}
  local h=client(name,db);h.C.PlannerQuoteStart=h.nativeQuoteStart;h.quoteReads={};h.quotePackets={};h.prices={};h.prices[name]=i==1 and 9000 or 1000;h.counts={};h.noReply=false
  local original=h.env.SendChatMessage
  h.env.SendChatMessage=function(text,route,language,target)
   if string.find(text,'.z addinvite quote ',1,true)==1 then
    local _,_,source,tier=string.find(text,'^%.z addinvite quote (%a+) (t[0-5][dr])$');assert(source and tier,'invalid quote request')
    table.insert(h.quoteReads,{name=source,tier=tier,at=h.now,route=route});local price=assert(h.prices[source],'wrong account asked to quote '..source)
    if not h.noReply then table.insert(h.server,'[nexus] ACINFO:COST:INVITE '..source..':'..price..':'..price..':0:0:'..price..':'..price..':'..(h.counts[source] or 0)..':4') end
   elseif string.find(text,'SRBQUOTE',1,true)==1 then
    assert(route=='WHISPER' and language==nil and h.C.QuoteParse(text) and string.len(text)<=240,'bad quote envelope')
    table.insert(h.sent,{text=text,target=target});table.insert(h.quotePackets,{text=text,target=target})
   else original(text,route,language,target) end
  end
  clients[i]=h;byName[string.lower(name)]=h
 end
 local a,b,c=unpack(clients);pair(a,'Bob');pair(a,'Carol');pair(b,'Carol');run(clients,8,true)
 for _,h in ipairs(clients) do h.C.SyncRefreshAll() end;run(clients,20,true)
 for _,h in ipairs(clients) do h.C.peerAutoAttempted=nil end
 local function pump(seconds)
  for step=1,seconds*4 do
   for _,h in ipairs(clients) do
    h.now=h.now+0.25;h.wall=1800000000+math.floor(h.now-100)
    if h.C.plannerQuoteDriver then h:fire(h.C.plannerQuoteDriver,'OnUpdate',0.25) end
    h:fire(h.C.peerDriver,'OnUpdate',0.25)
   end
   for _,h in ipairs(clients) do
    while table.getn(h.sent)>0 do local p=table.remove(h.sent,1);local to=byName[p.target];if to then emit(to,'CHAT_MSG_WHISPER',p.text,h.name) end end
    while table.getn(h.server)>0 do emit(h,'CHAT_MSG_ADDON',table.remove(h.server,1),'nexus') end
   end
  end
 end
 local function open(h,names,count)
  h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn);local p=h.C.plannerFrame
  for _,row in ipairs(p.sourceRows) do row.normalCheck:SetChecked(names[row.source.name] and 1 or nil);h:fire(row.normalCheck,'OnClick') end
  h:click(h:button(p,'Composition'));p.countInputs['mage:rdps']:SetText(tostring(count or 1));return p
 end
 return a,b,c,pump,open,emit,state
end

test('mixed own and two trusted linked accounts collect exact quotes before Build in both Save gold modes',function()
 for _,save in ipairs({true,false}) do
  local a,b,c,pump,open=fixture();local p=open(a,{Alice=true,Bob=true,Carol=true});p.request.saveGold=save
  a:click(p.buildButton);assert(not p.proposal,'Build skipped quotes');pump(12)
  local r=assert(p.proposal,p.message:GetText());assert(table.getn(a.quoteReads)==1 and table.getn(b.quoteReads)==1 and table.getn(c.quoteReads)==1,'quote not read on owning account')
  assert(a.quoteReads[1].name=='Alice' and b.quoteReads[1].name=='Bob' and c.quoteReads[1].name=='Carol')
  for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then assert(e.account=='Bob' and e.tier=='t3r','actual cheaper remote quote did not affect equal-quality allocation') end end
  assert(p.request.quotes['own:alice'].base==9000 and p.request.quotes['2222222222222222:bob'].base==1000 and p.request.quotes['3333333333333333:carol'].base==1000,'cache identities crossed')
  for _,h in ipairs({a,b,c}) do assert(not h.C.handAuthority and not h.C.handRunPlan,'quote granted hiring authority') end
  p.nameInput:SetText('Linked quote plan');a:click(p.applyButton);a.env.RefreshComposition();assert(a:preset().entries[40].charName=='Alice')
 end
end)

test('metadata changes after an early quote invalidate the whole mixed-account Build',function()
 local a,b,c,pump,open=fixture();local p=open(a,{Alice=true,Bob=true,Carol=true});c.noReply=true
 a:click(p.buildButton);pump(3);assert(a.C.plannerQuotes and a.C.plannerQuotes.results['2222222222222222:bob'],'fixture did not collect its early quote')
 a.env.ShirsRaidBuilderDB.inviteCharacters.Alice.count=2;a.env.ShirsRaidBuilderDB.inviteCharacters.Alice.maxCount=4
 pump(1);assert(not a.C.plannerQuotes and not p.proposal,'changed source count retained stale price snapshot')
end)

test('legacy-only composition skips paid-normal quotes even with selected normal source choices',function()
 local a,b,c,pump,open=fixture();a.env.ShirsRaidBuilderDB.legacyCharacters={bob='mage'};a.env.ShirsRaidBuilderDB.legacyCharacterRoles={bob='rdps'}
 local p=open(a,{Alice=true,Bob=true},0)
 for _,row in ipairs(p.sourceRows) do if row.source.name=='Bob' then row.legacyCheck:SetChecked(1);a:fire(row.legacyCheck,'OnClick') end end
 a:click(p.buildButton);local r=assert(p.proposal,p.message:GetText())
 assert(r.normal==0 and r.legacy==1 and table.getn(a.quoteReads)==0 and table.getn(b.quoteReads)==0,'legacy-only quote created an unnecessary blocker')
end)

test('actual peer envelopes retain character race reputation masks and chosen races change allocation',function()
 local a,b,c,pump,open,emit=fixture();b.noReply=true;c.noReply=true
 local p=open(a,{Bob=true,Carol=true});local function build(race)
  a:click(a:button(p,'Composition'));a:choose(p.classDefaults.mage.raceButton,race);a:click(p.buildButton)
  for i=1,60 do
   pump(0.25)
   for _,h in ipairs({b,c}) do local flight=h.C.plannerQuoteFlight
    if flight and not flight.drain then local mask=h==b and '1' or '7';local base=h==b and 5000 or 4000;local ex=h==b and 500 or 400
     emit(h,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE '..h.name..':'..base..':'..ex..':'..mask..':17:999:111:0:4','nexus')
    end
   end
   if p.proposal then break end
  end
  local result=assert(p.proposal,p.message:GetText());local source
  for _,e in ipairs(result.plan.entries) do if e.kind=='normal' then assert(e.race==race);source=e.account end end
  assert(p.request.quotes['2222222222222222:bob'].mask=='1' and p.request.quotes['3333333333333333:carol'].mask=='7','peer reputation masks crossed')
  return source
 end
 assert(build('human')=='Bob','Human exalted quote not selected');assert(build('gnome')=='Carol','source change reused another character reputation discount')
end)

test('registered race change cancels pending read and cannot accept the old context',function()
 local a,b,c,pump,open,emit=fixture();b.noReply=true;local p=open(a,{Bob=true});a:click(p.buildButton);pump(2)
 assert(a.C.plannerQuotes and b.C.plannerQuoteFlight);a:click(a:button(p,'Composition'));a:choose(p.classDefaults.mage.raceButton,'gnome');pump(1)
 emit(b,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE Bob:5000:500:1:17:999:111:0:4','nexus');pump(1)
 assert(not p.proposal and not a.C.plannerQuotes and p.request.defaults.mage.race=='gnome','old race context survived cancel')
end)

print("Shir's Raid Builder linked quote tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'linked quote regressions failed')
