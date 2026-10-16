-- Normal Hire board footer, actual refresh/profile/new/reload paths. No native game input.
local f=assert(io.open('test_save_plan.lua'));local src=f:read('*a');f:close();local at=assert(string.find(src,"\ntest('Create saves",1,true))
local start,copy,dump=assert(loadstring(string.sub(src,1,at-1)..'\nreturn start,copy,dump'))()
local f=assert(io.open('test_individual_editor.lua'));local src=f:read('*a');f:close();local at=assert(string.find(src,'\nlocal failures, passes=',1,true));local boot=assert(loadstring(string.sub(src,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n..': '..tostring(e))end end
local function assertFooter(h,roles,humans,slots)
 local main=h.env.ShirsRaidBuilderMainFrame;local text=main.roleText:GetText()
 assert(text==roles..'\nHumans '..humans,'footer counted humans as companions: '..text)
 assert(main.countText:GetText()==slots..'/40','humans lost occupied capacity: '..main.countText:GetText()..' expected '..slots..'/40')
 assert(main.roleText.point[5]+main.roleText:GetHeight()<=main.priceFrame.point[5]-4,'human footer overlaps price estimate')
end

test('remembered Tank player no longer inflates normal Hire footer',function()
 local h,p=start();h:click(h:button(p,'Cancel'));h.env.RefreshComposition()
 assertFooter(h,'Tank 4   Healer 2   Melee 0   Range 3',1,10) -- unresolved guest remains a companion, not a human
end)

test('40 occupied mixed rows and eight legacies retain roles, identities and all humans on reload',function()
 local h,p=start();h:click(h:button(p,'Cancel'));local plan=h:preset();plan.entries={};local n=0
 for i=1,29 do n=n+1;plan.entries[n]={kind='normal',account='Owner'..i,tier='t3r',class='mage',role='rdps',spec='fire',race='gnome',gender='female'}end
 for i=1,8 do n=n+1;plan.entries[n]={kind='legacy',charName='Legacy'..string.char(64+i),class='priest',role='healer'}end
 plan.entries[38]={kind='player',charName='Humanhealer',class='priest',role='healer'};plan.entries[39]={kind='player',charName='Humanrange',class='mage',role='rdps'};plan.entries[40]={kind='player',charName='Alice',class='warrior',role='tank'};plan.plannerPlayerSlot=40
 h.env.RefreshComposition();local expected=copy(plan);assertFooter(h,'Tank 0   Healer 8   Melee 0   Range 29',3,40)
 local re=boot(assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))(),'Alice');assertFooter(re,'Tank 0   Healer 8   Melee 0   Range 29',3,40);assert(re.C.PlannerEqual(expected,re:preset()),'human rows removed on reload')
end)

test('role memory, alternate class and actual profile/new handlers refresh independent counters',function()
 local h,p=start();h:click(h:button(p,'Cancel'));local main=h.env.ShirsRaidBuilderMainFrame
 for _,r in ipairs({{class='warrior',label='Warrior',role='tank'},{class='priest',label='Priest',role='healer'},{class='mage',label='Mage',role='rdps'}})do
  local r=r
  h.env.UnitClass=function()return r.label,string.upper(r.class)end;h.env.ShirsRaidBuilderDB.characterRoles=h.env.ShirsRaidBuilderDB.characterRoles or {};h.env.ShirsRaidBuilderDB.characterRoles.alice=r.role;h:preset().entries[40]={kind='player',charName='Alice',class=r.class,role=r.role};h.env.RefreshComposition()
  assertFooter(h,'Tank 4   Healer 2   Melee 0   Range 3',1,10)
 end
 h:click(h:button(main,'New'));local prompt=h.env.ShirsRaidBuilderNamePrompt;prompt.input:SetText('Empty');h:click(h:button(prompt,'Save'));assertFooter(h,'Tank 0   Healer 0   Melee 0   Range 0',1,1)
 local picker;for _,w in ipairs(h.frames)do if w.parent==main and w.label and w.label:GetText()=='Empty'and w.options then picker=w end end;assert(picker,'profile picker missing');h:choose(picker,'Original');assertFooter(h,'Tank 4   Healer 2   Melee 0   Range 3',1,10)
end)
test('Sort retains its prior role and slot count contract',function()
 local h,p=start();h:click(h:button(p,'Cancel'));local main=h.env.ShirsRaidBuilderMainFrame
 h.env.ShirsRaidBuilderDB.uiMode='sort';h.env.RefreshComposition()
 local expected=h.C.CountRoles(h.C.ActivePreset(h.env.ShirsRaidBuilderDB,'sort').entries)
 assert(not string.find(main.roleText:GetText(),'Humans',1,true),'Hire-only human counter leaked into Sort')
 assert(main.roleText:GetHeight()==14 and main.roleText.point[5]==16,'Sort footer geometry changed')
 assert(main.roleText:GetText()=='Tank '..expected.tank..'   Healer '..expected.healer..'   Melee '..expected.mdps..'   Range '..expected.rdps,'Sort counting changed')
end)

print("Shir's Raid Builder hire footer tests: "..(fail==0 and 'PASS'or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0)
