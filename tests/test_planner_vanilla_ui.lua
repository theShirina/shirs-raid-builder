-- Exact Lua 5.0.3, type-accurate Vanilla EditBox surface; no live client input.
local f=assert(io.open('test_individual_editor.lua','r')); local source=f:read('*a'); f:close()
local at=assert(string.find(source,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(source,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(name,fn) local ok,e=pcall(fn); if ok then pass=pass+1; print('PASS '..name) else fail=fail+1; print('FAIL '..name..': '..tostring(e)) end end
local function start()
 local h=boot({currentPreset='Default',presets={Default={entries={{kind='player',charName='Alice',class='warrior',role='tank'}},denyRules={},setupRules={}}},inviteCharacters={Alice={name='Alice',level=60,raidLicense='t3r',dungeonLicense='t2d',faction='Alliance'}}},'Alice')
 h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn)
 return h,assert(h.env.ShirsRaidBuilderPlanner)
end
local function checkInput(w,editable)
 assert(w.kind=='EditBox' and w.Enable==nil and w.Disable==nil and w.IsEnabled==nil,'fixture grants Button methods to EditBox')
 assert(w.mouse==editable and w.keyboard==editable,'profile name input state is not type-correct')
 if not editable then assert(not w:HasFocus(),'read-only name retained keyboard focus') end
end

test('registered launcher opens with real EditBox methods and reopening restores name editing',function()
 local h,p=start(); assert(p:IsVisible() and not p.applyButton:IsEnabled())
 checkInput(p.nameInput,true)
 p.nameInput:SetText('Kept name'); p.nameInput:SetFocus()
 p.replaceCheck:SetChecked(1); h:fire(p.replaceCheck,'OnClick')
 checkInput(p.nameInput,false); assert(p.nameInput:GetText()=='Kept name' and p.applyButton.label:GetText()=='Apply Plan')
 p.nameInput:SetFocus(); assert(not p.nameInput:HasFocus(),'read-only input accepted focus')
 p.replaceCheck:SetChecked(nil); h:fire(p.replaceCheck,'OnClick')
 checkInput(p.nameInput,true); assert(p.nameInput:GetText()=='Kept name')
 p.nameInput:SetFocus(); assert(p.nameInput:HasFocus())
 p.replaceCheck:SetChecked(1); h:fire(p.replaceCheck,'OnClick'); p:Hide()
 h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn)
 assert(p:IsVisible() and not p.replaceCheck:GetChecked() and p.nameInput:GetText()=='Kept name','reopen lost typed name')
 checkInput(p.nameInput,true); assert(not p.applyButton:IsEnabled())
end)

test('valid proposal and capacity failures preserve Button disabled semantics with strict widget types',function()
 local h,p=start(); local row
 for _,r in ipairs(p.sourceRows) do if r.source and r.source.name=='Alice' then row=r end end
 assert(row); row.normalCheck:SetChecked(1); h:fire(row.normalCheck,'OnClick'); h:choose(row.tierButton,'t1r')
 h:click(h:button(p,'Composition')); p.countInputs['mage:rdps']:SetText('1')
 h:click(p.buildButton); assert(p.proposal and p.applyButton:IsEnabled())
 h:click(h:button(p,'Composition')); p.countInputs['mage:rdps']:SetText('5')
 assert(not p.proposal and not p.applyButton:IsEnabled()); h:click(p.buildButton)
 assert(not p.proposal and not p.applyButton:IsEnabled() and string.len(p.message:GetText())>0)
 for _,w in ipairs(h.frames) do
  if w.parent==p or w.parent==p.panels.counts then
   if w.kind=='EditBox' then assert(w.Enable==nil and w.Disable==nil) end
  end
 end
end)

test('no available sources still opens read-only source display and refuses Apply without sending',function()
 local h,p=start(); p:Hide(); h.C.PlannerReadSources=function() return {} end
 h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn)
 assert(p:IsVisible() and table.getn(p.sources)==0 and not p.previousSources and not p.nextSources and p.sourceMax==0 and not p.sourceSlider:IsShown())
 checkInput(p.nameInput,true)
 h:click(h:button(p,'Composition')); p.countInputs['mage:rdps']:SetText('1'); h:click(p.buildButton)
 assert(not p.proposal and not p.applyButton:IsEnabled() and string.len(p.message:GetText())>0)
 for _,r in ipairs(p.sourceRows) do assert(not r:IsVisible()) end
end)

print("Shir's Raid Builder planner Vanilla UI tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('planner Vanilla UI regressions failed') end
