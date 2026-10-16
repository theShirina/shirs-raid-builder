-- Native asynchronous quote adapter, server-shaped payloads; no real server.
local f=assert(io.open('test_individual_editor.lua'));local t=f:read('*a');f:close();local at=assert(string.find(t,'\nlocal failures, passes=',1,true));local boot=assert(loadstring(string.sub(t,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n..': '..tostring(e)) end end
local function start()
 local db={syncAccountId='1111111111111111',currentPreset='Default',presets={Default={entries={},denyRules={},setupRules={}}},inviteCharacters={}}
 for _,name in ipairs({'Alice','Bravo'}) do db.inviteCharacters[name]={name=name,level=60,dungeonLicense='t2d',raidLicense='t3r',faction='Alliance',count=0,maxCount=4} end
 local h=boot(db,'Alice');if h.nativeQuoteStart then h.C.PlannerQuoteStart=h.nativeQuoteStart end
 local clock,sent=100,{};h.env.GetTime=function()return clock end;h.env.SendChatMessage=function(command,route,_,target)table.insert(sent,{command=command,route=route,target=target,at=clock})end
 h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn);local p=h.C.plannerFrame
 for _,r in ipairs(p.sourceRows) do r.normalCheck:SetChecked(1);h:fire(r.normalCheck,'OnClick') end
 h:click(h:button(p,'Composition'));p.countInputs['mage:rdps']:SetText('1')
 function h:tick(seconds)clock=clock+(seconds or 1);assert(self.C.plannerQuoteDriver,'quote driver missing');self:fire(self.C.plannerQuoteDriver,'OnUpdate',seconds or 1)end
 function h:quote(name,base,count,max)self.env.event='CHAT_MSG_ADDON';self.env.arg2='nexus';self:fire(self.C.plannerQuoteDriver,'OnEvent','[nexus] ACINFO:COST:INVITE '..name..':'..base..':'..base..':0:0:'..base..':'..base..':'..(count or 0)..':'..(max or 4))end
 return h,p,sent
end
test('Build waits for every selected full source/licence; cheaper same-tier next quote wins in both policies',function()
 for _,save in ipairs({true,false}) do local h,p,sent=start();p.request.saveGold=save;h:click(p.buildButton);assert(not p.proposal and h.C.plannerQuotes,'Build bypassed prices');h:tick();assert(table.getn(sent)==1 and sent[1].command=='.z addinvite quote Alice t3r' and sent[1].route=='SAY');h:quote('Alice',9000);assert(not p.proposal);h:tick();assert(sent[2].command=='.z addinvite quote Bravo t3r');h:quote('Bravo',1000);h:tick();local r=assert(p.proposal,p.message:GetText());for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then assert(e.account=='Bravo' and e.tier=='t3r') end end;assert(table.getn(sent)==2 and string.find(table.concat(r.notes,' '),'next',1,true));p.nameInput:SetText('Quoted');h:click(p.applyButton);h.env.RefreshComposition();assert(h:preset().entries[40].charName=='Alice') end
end)
test('cancel drains old reply; changed licence cannot accept old in-flight quote',function()
 local h,p,sent=start();h:click(p.buildButton);h:tick();h:click(p.buildButton);assert(not h.C.plannerQuotes and not p.proposal);h:click(p.buildButton);assert(not h.C.plannerQuotes and string.find(string.lower(p.message:GetText()),'previous',1,true));h:quote('Alice',9000);assert(not p.proposal);h:click(p.buildButton);h:tick();assert(h.C.plannerQuotes);h:click(h:button(p,'Sources'));local r=p.sourceRows[1];h:choose(r.tierButton,'t2r');assert(not h.C.plannerQuotes and not p.proposal)
end)
test('timeout wrong-source malformed and changed count never produce a fabricated proposal',function()
 local h,p,sent=start();h:click(p.buildButton);h:tick();h:quote('Unknown',100);assert(not p.proposal);h:tick(16);assert(not h.C.plannerQuotes and not p.proposal and string.find(string.lower(p.message:GetText()),'timeout',1,true))
 local a,q=start();a:click(q.buildButton);a:tick();a:quote('Alice',100,4,4);assert(not q.proposal and not a.C.plannerQuotes,'exhausted quote capacity accepted')
end)
test('remote account needs an authorized quote route, never local-account discount substitution',function()
 local h,p,sent=start();p.sources[1].localSource=false;p.sources[1].live=false
 local result,why=h.C.PlannerQuoteStart(p.sources,p.request,function()error('unsupported route completed')end)
 assert(not result and why and string.find(string.lower(why),'trusted link',1,true) and table.getn(sent)==0)
end)
test('MCP invite owns its character-only replies while open; no global hijack',function()
 local h,p,sent=start();h.env.MCPInviteFrame=h.env.CreateFrame('Frame');h.env.MCP_InviteName='Unrelated';h:click(p.buildButton);assert(not p.proposal and table.getn(sent)==0 and h.env.MCP_InviteName=='Unrelated')
end)
test('malformed expired and race-specific quotes fail closed; quality priority beats cheap lower licence',function()
 local h,p=start();local C=h.C
 assert(not C.PlannerQuoteParse('[nexus] ACINFO:COST:INVITE Alice:999999999999:1:0:0:1:1:0:4'))
 assert(not C.PlannerQuoteParse('[nexus] ACINFO:COST:INVITE Alice:1:1:0:0:1:1:5:4'))
 local sources=p.sources;local req={sources={},counts={['warrior:tank']=1,['mage:rdps']=1},priorityMode='custom',customOrder={'warrior:tank','mage:rdps'},saveGold=false,quotes={},quoteNow=100}
 for _,s in ipairs(sources) do local tier=s.name=='Alice' and 't3r' or 't2r';req.sources[s.key]={selected=true,tier=tier};req.quotes[s.key]={name=s.name,tier=tier,accountId=s.accountId,base=s.name=='Alice' and 90000 or 100,ex=100,mask='0',count=0,max=1,received=100} end
 local r=assert(C.PlannerBuild(p.base,sources,req));for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then assert(e.tier==(e.role=='tank' and 't3r' or 't2r'),'price demoted tank') end end
 req.quoteNow=131;assert(not C.PlannerBuild(p.base,sources,req),'stale quotes accepted')
 req.quoteNow=100;req.customOrder={'mage:rdps','warrior:tank'};r=assert(C.PlannerBuild(p.base,sources,req));for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then assert(e.tier==(e.class=='mage' and 't3r' or 't2r')) end end
end)
print("Shir's Raid Builder planner quote tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'planner quote regressions failed')
