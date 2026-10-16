-- Registered UI choices and native trusted quote/Build flow, no live server.
local f=assert(io.open('test_planner_linked_quotes.lua'));local s=f:read('*a');f:close();local at=assert(string.find(s,"\ntest('mixed own",1,true));local fixture=assert(loadstring(string.sub(s,1,at-1)..'\nreturn fixture'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n..': '..tostring(e))end end
local function tick(h,p,value)p.ultraGoldCheck:SetChecked(value and 1 or nil);h:fire(p.ultraGoldCheck,'OnClick')end
local function source(p,name)for _,r in ipairs(p.sourceRows)do if r.source.name==name then return r end end;error('source absent')end

test('Ultra defaults off, persists separately, and toggling never changes saved plans or sends quotes',function()
 local a,b,c,pump,open=fixture();local p=open(a,{Alice=true,Bob=true},4);local before=a.C.PlannerCopy(a:preset())
 assert(p.ultraGoldCheck and not p.ultraGoldCheck:GetChecked() and p.request.ultraGold==false,'Ultra opt-in control missing')
 local saved=p.request.saveGold;tick(a,p,true);assert(p.request.ultraGold==true and p.request.saveGold==saved and not p.saveGoldCheck:IsEnabled())
 assert(table.getn(a.quoteReads)==0 and table.getn(b.quoteReads)==0 and a.C.PlannerEqual(before,a:preset()),'option performed work')
 a.C.ClosePlanner();a:click(a.env.ShirsRaidBuilderMainFrame.plannerBtn);p=a.C.plannerFrame
 assert(p.ultraGoldCheck:GetChecked() and p.request.ultraGold==true and p.request.saveGold==saved,'Ultra did not persist on reopen')
 local file=assert(io.open('test_individual_editor.lua'));local src=file:read('*a');file:close();local boundary=assert(string.find(src,'\nlocal failures, passes=',1,true));local boot=assert(loadstring(string.sub(src,1,boundary-1)..'\nreturn boot'))()
 local re=boot(a.C.PlannerCopy(a.env.ShirsRaidBuilderDB),'Alice');re:click(re.env.ShirsRaidBuilderMainFrame.plannerBtn);local rp=re.C.plannerFrame
 assert(rp.ultraGoldCheck:GetChecked() and rp.request.ultraGold==true,'Ultra preference lost after fresh load')
 tick(a,p,false);assert(p.request.ultraGold==false and p.saveGoldCheck:IsEnabled() and p.request.saveGold==saved,'ordinary Save gold was not restored')
 assert(p.ultraGoldCheck.tip and string.find(p.ultraGoldCheck.tip,'another',1,true) and string.find(p.ultraGoldCheck.tip,'discount',1,true),'incomplete player-facing boundary')
end)

test('native quote-backed Build distinguishes expensive lower tier from ordinary Save gold without changing selections',function()
 local a,b,c,pump,open=fixture();local p=open(a,{Alice=true,Bob=true},4)
 -- Both endpoints have t3r; choose a deliberate lower licence on Bob.
 a:click(a:button(p,'Sources'));a:choose(source(p,'Bob').tierButton,'t2r');a:click(a:button(p,'Composition'));a.prices.Alice=1000;b.prices.Bob=6000
 tick(a,p,true);a:click(p.buildButton);pump(16);local r=assert(p.proposal,p.message:GetText())
 assert(r.ultra and r.ultra.replacements==0,'expensive lower licence replaced a cheaper fourth')
 for _,e in ipairs(r.plan.entries)do if e.kind=='normal'then assert(e.account=='Alice' and e.tier=='t3r')end end
 assert(p.request.sources['2222222222222222:bob'].tier=='t2r','manual tier changed')
 a:click(a:button(p,'Composition'));tick(a,p,false);a:click(p.buildButton);pump(16);r=assert(p.proposal,p.message:GetText());local low=0
 for _,e in ipairs(r.plan.entries)do if e.kind=='normal' and e.account=='Bob'then low=low+1;assert(e.tier=='t2r')end end
 assert(low==1,'existing Save gold behavior was changed by Ultra')
end)

test('registered Ultra choice cancels pending quotes and late replies cannot build another mode',function()
 local a,b,c,pump,open,emit=fixture();local p=open(a,{Bob=true},1);b.noReply=true;a:click(p.buildButton);pump(2)
 assert(a.C.plannerQuotes and b.C.plannerQuoteFlight,'fixture did not reach real linked quote')
 tick(a,p,true);emit(b,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE Bob:1000:1000:0:0:1000:1000:0:4','nexus');pump(3)
 assert(not p.proposal and not a.C.plannerQuotes and not a.C.handAuthority,'old-mode quote continued after toggle')
end)
test('native Ultra Build chooses the cheaper other character without changing either selected licence',function()
 local a,b,c,pump,open=fixture();local p=open(a,{Alice=true,Bob=true},4)
 a:click(a:button(p,'Sources'));a:choose(source(p,'Bob').tierButton,'t2r');a:click(a:button(p,'Composition'))
 a.prices.Alice=1000;b.prices.Bob=2000;tick(a,p,true);a:click(p.buildButton);pump(16)
 local r=assert(p.proposal,p.message:GetText());local high,low=0,0
 for _,e in ipairs(r.plan.entries)do if e.kind=='normal'then
  if e.account=='Alice'then high=high+1;assert(e.tier=='t3r')else low=low+1;assert(e.account=='Bob'and e.tier=='t2r')end
 end end
 assert(high==3 and low==1 and r.ultra.replacements==1 and r.ultra.savedCopper==3000,'native Build did not apply cheaper adjacent source')
 assert(r.estimate.complete and r.estimate.totalCopper==7000,'wrong grouped discounted total')
 assert(p.request.sources['own:alice'].tier=='t3r'and p.request.sources['2222222222222222:bob'].tier=='t2r','selected licences changed')
 assert(not a.C.handAuthority and not b.C.handAuthority,'Build granted spending authority')
end)

print("Shir's Raid Builder Ultra UI tests: "..(fail==0 and 'PASS'or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'Ultra UI regressions failed')
