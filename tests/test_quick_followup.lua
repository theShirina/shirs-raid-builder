-- Exact Lua 5.0.3. Real constructors/registered handlers; native rendering and server QA remain separate.
local f=assert(io.open('test_quick_hire.lua','r')); local source=f:read('*a'); f:close()
local at=assert(string.find(source,"\ntest('Random Tank",1,true))
local helpers=assert(loadstring(string.sub(source,1,at-1)..'\nreturn {start=start,saved=saved,hidden=hidden}'))()
local start,saved,hidden=helpers.start,helpers.saved,helpers.hidden
local failures,passes=0,0
local function test(name,fn)
 local ok,err=pcall(fn)
 if ok then passes=passes+1; print('PASS '..name) else failures=failures+1; print('FAIL '..name..': '..tostring(err)) end
end
local function prepare(h,branch,role,class,index,deferTier)
 local q=h:quick(index or 9); h:choose(q.sourceButton,'Alice')
 h:click(h:button(q,branch or 'Class')); h:click(h:button(q,role or 'DPS'))
 if class then h:click(h:button(q,class)) end
 if not deferTier then h:choose(q.tierButton,'t1r') end
 return q
end
local function dump(value)
 if type(value)~='table' then return type(value)=='string' and string.format('%q',value) or tostring(value) end
 local keys,out={},{}; for k in pairs(value) do table.insert(keys,k) end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 for _,k in ipairs(keys) do table.insert(out,'['..dump(k)..']='..dump(value[k])) end
 return '{'..table.concat(out,',')..'}'
end
local function tick(h)
 for _,w in ipairs(h.frames) do if w:IsVisible() and w.scripts.OnUpdate then h:fire(w,'OnUpdate',0.1) end end
end
local function menusHidden(h)
 return hidden(h.env.ShirsRaidBuilderChoiceMenu) and hidden(h.env.ShirsRaidBuilderCharacterChoices)
end

test('shared normal character dropdown toggles, switches family and closes with owner',function()
 local h=start(); local n=h:normal()
 h:click(n.characterButton); assert(not hidden(h.env.ShirsRaidBuilderCharacterChoices))
 h:click(n.characterButton); assert(menusHidden(h),'second click left character menu open')
 h:click(n.characterButton); h:click(n.classButton)
 assert(hidden(h.env.ShirsRaidBuilderCharacterChoices) and not hidden(h.env.ShirsRaidBuilderChoiceMenu),'switching family left two menus')
 h:click(n.classButton); assert(menusHidden(h),'second click left ordinary menu open')
 h:click(n.classButton); n:Hide(); assert(menusHidden(h),'closing Add Normal left menu at UIParent')
 n=h:normal(); h:click(n.characterButton); n:Hide(); assert(menusHidden(h),'closing Add Normal left character list')
 n=h:normal(); h:choose(n.classButton,'Warrior'); assert(menusHidden(h),'selection leaves a menu')
 h:click(n.classButton); h.env.ShirsRaidBuilderEscaper:Hide(); assert(menusHidden(h) and n:IsVisible())
 h:click(n.classButton); h:click(h:button(n,'Cancel')); assert(menusHidden(h))
end)

test('registered shared callers clean up hidden triggers, Settings, setup and profile/mode switches',function()
 local h=start(); local n=h:normal(); h:click(n.roleButton); n.roleButton:Hide(); assert(menusHidden(h),'hidden trigger left dropdown')
 n=h:normal(); h:click(n.classButton); h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Deny Rules'))
 assert(menusHidden(h),'switching panels left Add Normal menu')
 local settings=h.env.ShirsRaidBuilderSettingsFrame
 local trigger
 for _,w in ipairs(h.frames) do if w.parent==settings and w.options then trigger=w; break end end
 assert(trigger,'Settings shared selector missing')
 h:click(trigger); h:click(trigger); assert(menusHidden(h),'Settings selector does not toggle')
 h:click(trigger); settings:Hide(); assert(menusHidden(h),'Settings close leaves menu')
 n=h:normal(); h:click(n.classButton); h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Sort Mode')); assert(menusHidden(h),'mode switch orphaned menu')
 h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Hire Mode'))
 n=h:normal(); h:click(n.characterButton); h.env.ShirsRaidBuilderMainFrame:Hide(); assert(menusHidden(h))
end)

test('Hire empty cell has bounded OVERLAY hover and leave cleanup without plan mutation',function()
 local h=start(); local row=h:empty(9); local before=dump(h:preset()); local children=table.getn(h.frames)
 assert(row.mouse and row:GetWidth()==100 and row:GetHeight()==28,'hit region is not native empty cell')
 h:fire(row,'OnEnter')
 assert(row.quickHighlight and row.quickHighlight.layer=='OVERLAY' and row.quickHighlight.allPoints==row and row.quickHighlight:IsShown(),'hover texture hidden under cell artwork')
 assert(row.fonts[1]:GetText()=='Quick hire','hover does not identify action')
 h:fire(row,'OnLeave'); assert(not row.quickHighlight:IsShown() and row.fonts[1]:GetText()=='empty')
 assert(dump(h:preset())==before and table.getn(h.frames)==children,'hover mutated plan or created mouse overlay')
 h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Sort Mode')); row=h:empty(9)
 if row.scripts.OnEnter then h:fire(row,'OnEnter') end
 assert(not row.quickHighlight or not row.quickHighlight:IsShown(),'Sort hover offers Hire')
end)

test('source changes retain current class page and every still-valid visible choice',function()
 local db=saved(); db.inviteCharacters.Twin={name='Twin',level=60,raidLicense='t3r',dungeonLicense='t2d',faction='Alliance'}
 local h=start(db); local q=prepare(h,'Class','DPS','Mage',nil,true)
 h:choose(q.roleButton,'Ranged DPS'); h:choose(q.specButton,'Fire'); h:choose(q.raceButton,'Gnome'); h:choose(q.genderButton,'Female'); h:choose(q.tierButton,'t2d')
 h:click(q.raceButton); h:choose(q.sourceButton,'Twin')
 assert(q.mode=='class' and q.group=='dps' and q.pickedClass=='mage','source reset navigation')
 assert(q.roleButton.label:GetText()=='Ranged DPS' and q.specButton.label:GetText()=='Fire' and q.raceButton.label:GetText()=='Gnome' and q.genderButton.label:GetText()=='Female')
 assert(q.tierButton.label:GetText()=='t2d' and q.tierChosen and menusHidden(h),'valid tier choice lost')
 h:choose(q.sourceButton,'Hordealt')
 assert(q.mode=='class' and q.group=='dps' and q.pickedClass=='mage','cross-faction source reset valid class')
 assert(q.specButton.label:GetText()=='Fire' and q.genderButton.label:GetText()=='Female')
 assert(q.raceButton.label:GetText()=='Undead' and q.tierButton.label:GetText()=='(choose tier)' and not q.tierChosen,'invalid dependencies not refreshed safely')
 h:choose(q.tierButton,'t0d'); h:click(h:button(q,'Add'))
 assert(h:preset().entries[9].account=='Hordealt' and h:preset().entries[9].race=='undead' and h:preset().entries[9].tier=='t0d')
end)

test('unavailable faction class returns only to current class list, random branch keeps role and tier',function()
 local h=start(); local q=prepare(h,'Class','Healer','Paladin'); h:choose(q.sourceButton,'Hordealt')
 assert(q.mode=='class' and q.group=='healer' and not q.pickedClass,'invalid Paladin did not return to healer list')
 h:click(h:button(q,'Shaman')); assert(q.raceButton.label:GetText()=='Orc')
 h:click(h:button(q,'Cancel')); q=prepare(h,'Random','Tank'); h:choose(q.sourceButton,'Hordealt')
 assert(q.mode=='random' and q.group=='tank' and q.tierButton.label:GetText()=='t1r' and q.tierChosen,'Random source reset valid navigation/tier')
end)

test('repeated Add advances in board order, preserves choices, closes no completed entries',function()
 local h=start(); local p=h:preset(); p.entries[10]={kind='legacy',charName='Legacy',class='mage',role='rdps'}
 local q=prepare(h,'Class','DPS','Mage',nil,true); h:choose(q.specButton,'Fire'); h:choose(q.raceButton,'Gnome'); h:choose(q.genderButton,'Female'); h:choose(q.tierButton,'t1r')
 for _,slot in ipairs({9,11,12}) do
  assert(q.slot==slot and string.find(q.title:GetText(),tostring(slot),1,true),'next target not visible')
  h:click(h:button(q,'Add')); assert(q:IsVisible(),'Add closed repeated picker')
  assert(p.entries[slot].kind=='normal' and p.entries[slot].spec=='fire' and p.entries[slot].race=='gnome' and p.entries[slot].gender=='female')
  assert(q.pickedClass=='mage' and q.tierButton.label:GetText()=='t1r' and q.tierChosen,'Add reset selection')
 end
 local before=dump(p); h:click(h:button(q,'Cancel')); assert(hidden(q) and dump(p)==before and p.entries[10].kind=='legacy')
end)

test('full board and four-per-source leave useful panel open with disabled Add and clear status',function()
 local h=start(); local q=prepare(h,'Random','DPS')
 for count=1,4 do h:click(h:button(q,'Add')) end
 assert(q:IsVisible() and q.addButton and not q.addButton:IsEnabled(),'cap closes panel or leaves Add enabled')
 assert(string.find(q.note:GetText(),'four',1,true),'cap reason missing')
 h:choose(q.sourceButton,'Hordealt'); assert(q.addButton:IsEnabled(),'changing source cannot recover cap')
 h:click(h:button(q,'Cancel'))
 h=start(); local p=h:preset()
 for i=2,39 do p.entries[i]={kind='guest',companionName='Guest',class='mage',role='rdps'} end
 q=prepare(h,'Random','Healer',nil,40); h:click(h:button(q,'Add')); tick(h)
 assert(q:IsVisible() and not q.addButton:IsEnabled() and not q.slot and string.find(q.note:GetText(),'40',1,true),'full board not safely exhausted')
 local before=dump(p); h:fire(q.addButton,'OnClick'); assert(dump(p)==before,'disabled Add can overwrite')
 h:click(h:button(q,'Cancel')); assert(hidden(q) and dump(p)==before)
end)

test('MCP Random UI preserves short command/unknown intent on save, Preview and real local Execute',function()
 for _,role in ipairs({'Tank','Healer','DPS'}) do
  local h=start(); local q=prepare(h,'Random',role); local sent={}
  h.env.math=setmetatable({random=function(n) assert(not n,'local class random roll is forbidden'); return 0.5 end},{__index=math})
  h:click(h:button(q,'Add')); local entry=h:preset().entries[9]
  local key=string.lower(role); local command='.z addi Alice t1r '..key
  assert(entry.class=='random' and entry.role==key and entry.spec==nil and entry.race==nil and entry.gender==nil,'random became concrete')
  assert(q:IsVisible() and string.find(q.note:GetText(),'server',1,true),'Random falsely promises local race/gender')
  assert(h.C.BuildNormalHireCommand(entry)==command)
  local reload=start(assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))())
  reload.env.SendChatMessage=function(text) table.insert(sent,text) end; reload.env.SendAddonMessage=function() end
  reload:click(reload:button(reload.env.ShirsRaidBuilderMainFrame,'Preview')); assert(table.getn(sent)==0)
  local printed=false; for _,text in ipairs(reload.messages) do if string.find(text,command,1,true) then printed=true end end
  assert(printed and reload:preset().entries[9].class=='random')
  reload:click(reload.env.ShirsRaidBuilderMainFrame.executeBtn)
  assert(table.getn(sent)==1 and sent[1]==command,'real Execute did not retain MCP role-only command')
 end
end)

test('random board shows unknown outcome and offers only supported random role settings',function()
 local h=start(); local q=prepare(h,'Random','DPS'); h:click(h:button(q,'Add')); h:click(h:button(q,'Cancel'))
 local row
 for _,w in ipairs(h.frames) do if w:IsVisible() and w.scripts.OnMouseUp and w.fonts[1] and w.fonts[1]:GetText()=='9 Alice' then row=w end end
 assert(row,'random board row missing'); local lines={}
 h.env.GameTooltip.AddLine=function(self,text) table.insert(lines,text) end; h:fire(row,'OnEnter')
 assert(string.find(table.concat(lines,' '),'unknown until',1,true),'random tooltip invents concrete outcome')
 h:fire(row,'OnMouseUp','RightButton'); local menu=h.env.ShirsRaidBuilderContextFrame
 for _,w in ipairs(h.frames) do
  if w.parent==menu and w:IsVisible() and w.label then
   local label=w.label:GetText()
   assert(not string.find(label,'Gender:',1,true) and not string.find(label,'Race:',1,true) and not string.find(label,'Spec:',1,true),'unsupported random options exposed')
  end
 end
 h:click(h:button(menu,'Role: DPS')); h:click(h:button(menu,'Tank'))
 assert(h:preset().entries[9].role=='tank' and h:preset().entries[9].class=='random')
end)

test('shared selectors across Add Normal, all setup classes, import and profile retain cleanup',function()
 local db=saved(); db.presets.Other={entries={},denyRules={},setupRules={}}
 local h=start(db); local main=h.env.ShirsRaidBuilderMainFrame; local tested=0
 local function audit(parent)
  for _,w in ipairs(h.frames) do
   if w.parent==parent and w.options and table.getn(w.options)>0 and w:IsVisible() and w:IsEnabled() then
    h:click(w); h:click(w); assert(menusHidden(h),'same-trigger toggle failed')
    h:click(w); parent:Hide(); assert(menusHidden(h),'parent close orphaned dropdown'); parent:Show()
    h:click(w); h.env.ShirsRaidBuilderEscaper:Hide(); assert(menusHidden(h) and parent:IsVisible(),'Escape did not dismiss choices')
    tested=tested+1
   end
  end
 end
 local normal=h:normal(); audit(normal); normal:Hide()
 h:click(h:button(main,'Other Commands')); local setup=h.env.ShirsRaidBuilderSetupFrame
 for _,class in ipairs({'Shaman','Paladin','Hunter','Warlock','Mage'}) do h:choose(setup.classButton,class); audit(setup) end
 setup:Hide(); h:click(h:button(main,'Import')); local import=h.env.ShirsRaidBuilderImport; audit(import); import:Hide()
 audit(main); assert(tested>=24,'actual selector-family coverage incomplete')
end)

if failures>0 then error(tostring(failures)..' quick followup regression(s) failed') end
print("Shir's Raid Builder quick followup tests: PASS ("..passes.." cases)")
