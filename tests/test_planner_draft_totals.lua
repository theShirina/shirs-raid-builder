-- Draft counters are independent of carried rows; existing input loading stays safe.
local f=assert(io.open('test_individual_editor.lua'));local src=f:read('*a');f:close()
local at=assert(string.find(src,'\nlocal failures, passes=',1,true));local boot=assert(loadstring(string.sub(src,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n..': '..tostring(e)) end end
local function fixture()
 local db={syncAccountId=string.rep('1',16),currentPreset='Default',presets={Default={entries={{kind='normal',account='Alice',tier='t3r',class='mage',role='rdps',race='gnome',gender='female',spec='fire'},{kind='legacy',sourceName='Bob',charName='Bob',class='priest',role='healer'},{kind='guest',charName='Human',companionName='Human',class='warrior',role='tank'}},denyRules={},setupRules={}}},inviteCharacters={Alice={name='Alice',level=60,dungeonLicense='t2d',raidLicense='t3r',faction='Alliance'},Bob={name='Bob',level=60,dungeonLicense='t2d',raidLicense='t3r',faction='Alliance'}},legacyCharacters={bob='priest'},legacyCharacterRoles={bob='healer'}}
 local h=boot(db,'Alice');h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn);return h,h.C.plannerFrame
end
test('loaded normal inputs stay safe while draft roles exclude unselected saved legacy and humans',function()
 local h,p=fixture();local before=h.C.PlannerCopy(h:preset());assert(p.countInputs['mage:rdps']:GetText()=='1','silently changed draft loading policy')
 local t=h.C.PlannerDraftTotals(p.base,p.sources,p.request)
 assert(t.normal==1 and t.legacy==0 and t.roles.rdps==1 and t.roles.healer==0 and t.roles.tank==0,'saved or human role leaked into draft')
 assert(t.saved.normal==1 and t.saved.legacy==1 and t.humans==2 and t.carriedLegacy==1 and t.occupied==4)
 assert(string.find(p.countSummary:GetText(),'Draft companions 1',1,true) and string.find(p.countSummary:GetText(),'Healers 0',1,true))
 assert(p.savedCountSummary and string.find(p.savedCountSummary:GetText(),'Saved: Normal 1 | Legacy 1',1,true))
 assert(h.C.PlannerEqual(before,h:preset()),'counting edited saved plan')
end)
test('selected legacy counts once in draft and capacity; unchecking never removes carried saved identity',function()
 local h,p=fixture();local before=h.C.PlannerCopy(h:preset());local row
 for _,r in ipairs(p.sourceRows) do if r.source.name=='Bob' then row=r end end
 row.legacyCheck:SetChecked(1);h:fire(row.legacyCheck,'OnClick');local t=h.C.PlannerDraftTotals(p.base,p.sources,p.request)
 assert(t.legacy==1 and t.roles.healer==1 and t.carriedLegacy==0 and t.occupied==4)
 row.legacyCheck:SetChecked(nil);h:fire(row.legacyCheck,'OnClick');p.countInputs['mage:rdps']:SetText('3')
 t=h.C.PlannerDraftTotals(p.base,p.sources,p.request);assert(t.normal==3 and t.saved.normal==1 and t.legacy==0 and t.carriedLegacy==1 and t.occupied==6)
 assert(h.C.PlannerEqual(before,h:preset()),'draft replaced saved profile')
end)
print("Shir's Raid Builder draft totals tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'draft totals regressions failed')
