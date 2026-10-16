-- Licence-neutral saved cost preference, actual checkbox and exact allocations.
local f=assert(io.open('test_planner_priority.lua'));local text=f:read('*a');f:close();local at=assert(string.find(text,"\ntest('Custom supplied",1,true));local start,dump,roleTiers=assert(loadstring(string.sub(text,1,at-1)..'\nreturn start,dump,roleTiers'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n..': '..tostring(e)) end end
for _,tiers in ipairs({{'t3r','t2r'},{'t2r','t1r'},{'t4d','t2d'},{'t5r','t4r'}}) do
 local hi,lo=tiers[1],tiers[2]
 test('checked avoids fourth '..hi..'; unchecked prefers fourth over '..lo,function()
  local h=start();local C=h.C;local s={{key='a',name='Alpha',localSource=true,eligible=true,capacity=4,faction='Alliance',tiers={hi}},{key='b',name='Bravo',localSource=true,eligible=true,capacity=4,faction='Alliance',tiers={lo}}}
  local req={counts={['mage:rdps']=4},sources={a={selected=true,tier=hi},b={selected=true,tier=lo}},saveGold=true}
  local a=assert(C.PlannerBuild({entries={}},s,req));req.saveGold=false;local b=assert(C.PlannerBuild({entries={}},s,req));assert(a.allocation[1].count==3 and a.allocation[2].count==1);assert(b.allocation[1].count==4 and b.allocation[2].count==0,'unchecked did not maximize chosen highest licence')
  req.saveGold=true;req.counts['mage:rdps']=5;s[2].capacity=1;local necessary=assert(C.PlannerBuild({entries={}},s,req));assert(necessary.allocation[1].count==4 and necessary.normal==5 and string.find(table.concat(necessary.notes,' '),'fourth',1,true))
  req.counts={['warrior:tank']=4,['paladin:healer']=1};s[1].faction='Horde';s[2].capacity=1;local faction=assert(C.PlannerBuild({entries={}},s,req));assert(faction.normal==5 and faction.allocation[1].count==4 and faction.allocation[2].count==1)
 end)
end
test('registered Save gold default ON persists OFF through Create refresh logout and fresh UI',function()
 local h,p=start();local C=h.C
 for _,record in pairs(h.env.ShirsRaidBuilderDB.inviteCharacters) do record.maxCount=4 end
 C.ClosePlanner();h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn)
 h:click(h:button(p,'Composition'));assert(p.saveGoldCheck and p.saveGoldCheck:GetChecked(),'default not checked')
 local tip=p.saveGoldCheck.tip;assert(tip and string.find(tip,'fourth',1,true) and not string.find(tip,'T5',1,true))
 for _,r in ipairs(p.sourceRows) do r.normalCheck:SetChecked(1);h:fire(r.normalCheck,'OnClick') end
 p.saveGoldCheck:SetChecked(nil);h:fire(p.saveGoldCheck,'OnClick');assert(p.request.saveGold==false)
 p.countInputs['mage:rdps']:SetText('4');h:click(p.buildButton);local proposal=assert(p.proposal,p.message:GetText());local tiers=roleTiers(proposal.plan);for _,e in ipairs(proposal.plan.entries) do if e.kind=='normal' then assert(e.tier=='t5r') end end
 p.nameInput:SetText('Cost mode');h:click(p.applyButton);h.env.RefreshComposition();h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn);assert(p.request.saveGold==false)
 h.env.event='PLAYER_LOGOUT';for _,w in ipairs(h.frames) do if w.events.PLAYER_LOGOUT and w.scripts.OnEvent then h:fire(w,'OnEvent') end end
 local file=assert(io.open('test_individual_editor.lua'));local t=file:read('*a');file:close();local boundary=assert(string.find(t,'\nlocal failures, passes=',1,true));local boot=assert(loadstring(string.sub(t,1,boundary-1)..'\nreturn boot'))()
 local fresh=boot(assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))(),'Alice');fresh:click(fresh.env.ShirsRaidBuilderMainFrame.plannerBtn);assert(fresh.C.plannerFrame.request.saveGold==false and not fresh.C.plannerFrame.saveGoldCheck:GetChecked())
end)
print("Shir's Raid Builder Save gold tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'Save gold regressions failed')
