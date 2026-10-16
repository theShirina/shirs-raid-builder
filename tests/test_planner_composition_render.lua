-- Constructor geometry and registered page lifecycle; this is not pixel QA.
local f=assert(io.open('test_individual_editor.lua')); local text=f:read('*a'); f:close()
local at=assert(string.find(text,'\nlocal failures, passes=',1,true)); text=string.sub(text,1,at-1)
text=string.gsub(text,'local function widget%(kind,name,parent%)','local function widget(kind,name,parent,template)')
text=string.gsub(text,'kind=kind,name=name,parent=parent,shown=true','kind=kind,name=name,parent=parent,template=template,shown=true')
text=string.gsub(text,'local noop=function%(%) end','function methods:SetTextInsets(...) self.textInsets=arg end\n    local noop=function() end')
local boot=assert(loadstring(text..'\nreturn boot'))()
local pass,fail=0,0
local function test(name,fn) local ok,e=pcall(fn); if ok then pass=pass+1; print('PASS '..name) else fail=fail+1; print('FAIL '..name..': '..tostring(e)) end end
local function start()
 local h=boot({currentPreset='Default',presets={Default={entries={{kind='player',charName='Alice',class='warrior',role='tank'}},denyRules={},setupRules={}}}},'Alice')
 h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn); return h,h.C.plannerFrame
end
local function bounds(w,root)
 if w==root then return {x=0,y=0,w=w:GetWidth(),h=w:GetHeight()} end
 local p=w.point; assert(p and p[1]=='TOPLEFT' and p[3]=='TOPLEFT','fixture needs complete top-left geometry')
 local parent=bounds(p[2],root)
 return {x=parent.x+p[4],y=parent.y-p[5],w=w:GetWidth(),h=w:GetHeight()}
end
local function overlaps(a,b) return a.x<b.x+b.w and b.x<a.x+a.w and a.y<b.y+b.h and b.y<a.y+a.h end

test('Composition count backgrounds are bounded to their own input, not anonymous template regions',function()
 local h,p=start(); h:click(h:button(p,'Composition')); local name=bounds(p.nameInput,p)
 assert(p.nameInput.template=='InputBoxTemplate','unrelated shared name input was redesigned')
 for key,input in pairs(p.countInputs) do
  assert(not input.template,'Composition still uses anonymous InputBoxTemplate regions: '..key)
  assert(input.backdrop and input.backdrop.bgFile and input.borderColor,'count field has no owned bounded background')
  assert(input.textInsets and input.textInsets[1]>=3 and input.textInsets[2]>=3,'text not inset from owned border')
  local b=bounds(input,p)
  assert(b.w>=32 and b.h==20 and b.x>=24 and b.x+b.w<=872 and b.y>=124 and b.y+b.h<=514,'Composition control outside page')
  assert(not overlaps(name,b),'Composition count field overlaps the shared name input')
  assert(input.Enable==nil and input.Disable==nil,'EditBox received Button-only methods')
 end
 assert(p.panels.counts:GetFrameLevel()==p.panels.sources:GetFrameLevel(),'Composition layer globally raised')
 assert(p.nameInput:GetFrameLevel()==p:GetFrameLevel()+1 and p.nameInput:GetFrameStrata()==p:GetFrameStrata(),'footer input elevated to hide a page defect')
end)

test('same name and focus survive Sources Composition Proposed groups Tier priority and back',function()
 local h,p=start(); local input=p.nameInput; input:SetFocus(); input:SetText('Second iteration')
 local level,strata=input:GetFrameLevel(),input:GetFrameStrata()
 for _,label in ipairs({'Composition','Proposed groups','Sources','Composition','Tier priority','Composition','Sources'}) do
  h:click(h:button(p,label)); assert(input:IsVisible() and input:GetText()=='Second iteration','page switch changed or hid typed name')
  assert(input:HasFocus() and input.mouse==true and input.keyboard==true,'page left new-name field read-only')
  assert(input.textColor[1]==0.95 and input.textColor[2]==0.97 and input.textColor[3]==1.0,'page changed name text color')
  assert(input:GetFrameLevel()==level and input:GetFrameStrata()==strata,'page used global layer workaround')
 end
 input:SetText(input:GetText()..' A'); assert(input:GetText()=='Second iteration A')
 h:click(h:button(p,'Composition')); p.replaceCheck:SetChecked(1); h:fire(p.replaceCheck,'OnClick')
 assert(not input:HasFocus() and input.mouse==false and input.keyboard==false)
 h:click(h:button(p,'Sources')); p.replaceCheck:SetChecked(nil); h:fire(p.replaceCheck,'OnClick')
 h:click(h:button(p,'Composition')); input:SetFocus(); assert(input:HasFocus() and input:GetText()=='Second iteration A' and input.mouse==true and input.keyboard==true)
 p:Hide(); h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn); h:click(h:button(p,'Composition'))
 assert(input:GetText()=='Second iteration A' and input.mouse==true and input.keyboard==true and not p.replaceCheck:GetChecked(),'reopen discarded typed name')
 input:SetFocus(); input:SetText(input:GetText()..' B'); assert(input:HasFocus() and input:GetText()=='Second iteration A B')
end)
print("Shir's Raid Builder composition rendering tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('Composition rendering regressions failed') end
