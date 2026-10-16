-- Registered UI repaint/pool regressions, exact Lua 5.0.3. No native hit-test claim.
local f=assert(io.open('test_individual_editor.lua'));local s=f:read('*a');f:close()
local at=assert(string.find(s,'\nlocal failures, passes=',1,true));local boot=assert(loadstring(string.sub(s,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n..': '..tostring(e))end end
local function full()
 local p={entries={},denyRules={},setupRules={},plannerPlayerSlot=40}
 for i=1,39 do p.entries[i]={kind='normal',account='Alpha',class='mage',role='rdps',tier='t5r',spec='frost',race='gnome',gender='female'}end
 p.entries[40]={kind='player',charName='Tester',class='warrior',role='tank'}
 return boot({presets={Full=p},currentPreset='Full',inviteCharacters={Alpha={name='Alpha',level=60,raidLicense='t5r',dungeonLicense='t5d',faction='Alliance'}}})
end
local function card(h,index)
 local group=math.floor((index-1)/5);local slot=index-1-group*5;local found
 for _,w in ipairs(h.frames)do if w.kind=='Button'and w:IsVisible()and w.point and w.point[4]==2+slot*102 and w.point[5]==-21-group*51 then found=w end end
 return assert(found,'card missing at '..index)
end
test('100 unchanged full board paints create zero warm widgets',function()
 local h=full();h.env.RefreshComposition();local n=table.getn(h.frames);local before=h.C.PlannerCopy(h:preset())
 for i=1,100 do h.env.RefreshComposition()end
 assert(table.getn(h.frames)==n,'warm board widget growth: '..(table.getn(h.frames)-n))
 assert(h.C.PlannerEqual(before,h:preset()),'pool changed plan')
end)
test('board pools survive every row type empty shrink grow and stale callbacks',function()
 local h=full();local p=h:preset();local original=h.C.PlannerCopy(p);local old=card(h,1);local oldMouse=old.scripts.OnMouseUp
 local kinds={
  {kind='empty'},
  {kind='legacy',charName='Legacy',sourceName='Legacy',class='shaman',role='healer',denyList={}},
  {kind='guest',charName='Guest',companionName='Guest',class='priest',role='healer'},
  {kind='normal',class='random',role='dps',account='Alpha',tier='t3r'},
  original.entries[1]
 }
 for _,e in ipairs(kinds)do p.entries[1]=h.C.PlannerCopy(e);h.env.RefreshComposition()end
 local n=table.getn(h.frames)
 for cycle=1,100 do for _,e in ipairs(kinds)do p.entries[1]=h.C.PlannerCopy(e);h.env.RefreshComposition()end end
 assert(table.getn(h.frames)==n,'type-cycle widget growth')
 local row=card(h,1);local remove=h:button(row,'X');h:click(remove);assert(p.entries[1].kind=='empty','rebound X did not remove current row')
 local current=h.C.PlannerCopy(p);local oldThis,oldArg=h.env.this,h.env.arg1;h.env.this=old;h.env.arg1='RightButton';oldMouse();h.env.this=oldThis;h.env.arg1=oldArg
 assert(not h.env.ShirsRaidBuilderContextFrame or not h.env.ShirsRaidBuilderContextFrame:IsVisible(),'stale row opened context for replacement')
 assert(h.C.PlannerEqual(current,p),'stale row altered plan')
end)
test('a retained handler from the same row cannot act after rebind',function()
 local h=full();local p=h:preset();local row=card(h,1);local old=h:button(row,'X').scripts.OnClick
 h.env.RefreshComposition();old()
 assert(p.entries[1].kind=='normal','old remove handler acted after rebind')
 local fresh=h:button(card(h,1),'X');h:click(fresh);assert(p.entries[1].kind=='empty','fresh remove handler failed')
end)
test('100 ability searches reuse options and clear hidden or stale bindings',function()
 local h=full();h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Deny Rules'))
 local input
 for _,w in ipairs(h.frames)do if w.kind=='EditBox'and w:IsVisible()and w.scripts.OnTextChanged then input=w end end
 assert(input);input:SetText('f');local menu=assert(h.env.ShirsRaidBuilderAbilityMenu)
 local options={};for _,w in ipairs(h.frames)do if w.kind=='Button'and w.parent==menu and w:IsVisible()then table.insert(options,w)end end
 assert(table.getn(options)>1);local old=options[1].scripts.OnClick;input:SetText('')
 local n=table.getn(h.frames)
 for i=1,100 do input:SetText('f');input:SetText('frost');input:SetText('')end
 assert(table.getn(h.frames)==n,'ability widget growth')
 old();assert(input:GetText()=='','hidden old ability handler changed text')
 input:SetText('f');local expected=options[1].fonts[1]:GetText();h:click(options[1]);assert(input:GetText()==expected,'option text/target stale')
 input:SetText('f');local stale=options[1].scripts.OnClick;input:SetText('frost');stale()
 assert(input:GetText()=='frost','superseded suggestion changed text')
 menu:Hide();for _,w in ipairs(options)do assert(not w:IsVisible(),'hidden menu option visible')end
end)
test('100 context page cycles reuse buttons and fence old profile/page actions',function()
 local h=full();local row=card(h,1)
 local function open() h:fire(row,'OnMouseUp','RightButton');return h.env.ShirsRaidBuilderContextFrame end
 local menu=open();h:click(h:button(menu,'Tier: T5R'));h:click(h:button(menu,'Back'));h:click(h:button(menu,'Close'))
 local n=table.getn(h.frames)
 for i=1,100 do menu=open();h:click(h:button(menu,'Tier: T5R'));h:click(h:button(menu,'Back'));h:click(h:button(menu,'Close'))end
 assert(table.getn(h.frames)==n,'context widget growth')
 menu=open();h:click(h:button(menu,'Tier: T5R'));local b=h:button(menu,'t2r');local stale=b.scripts.OnClick
 h:click(h:button(menu,'Back'));stale();assert(h:preset().entries[1].tier=='t5r','stale page action applied')
 h:click(h:button(menu,'Tier: T5R'));b=h:button(menu,'t2r');stale=b.scripts.OnClick
 local db=h.env.ShirsRaidBuilderDB;db.presets.Other=h.C.PlannerCopy(h:preset());db.currentPreset='Other';h.env.RefreshComposition();stale()
 assert(h:preset().entries[1].tier=='t5r','old profile action applied to new plan')
 h:fire(card(h,1),'OnMouseUp','RightButton');menu=h.env.ShirsRaidBuilderContextFrame
 if not pcall(function()return h:button(menu,'Tier: T5R')end)then h:fire(card(h,1),'OnMouseUp','RightButton')end
 h:click(h:button(menu,'Tier: T5R'));h:click(h:button(menu,'t2r'));assert(h:preset().entries[1].tier=='t2r','current page selection failed')
end)
print('pool tests: '..pass..' passed, '..fail..' failed');assert(fail==0)
