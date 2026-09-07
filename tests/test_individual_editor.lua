-- Exact Lua 5.0.3, whole-module UI regression. No game input or real chat.
-- Widgets model visibility, legacy globals, enabled state and strata; they do
-- not prove native hit-testing, font geometry, or server delivery.
local function boot(saved)
    local env = {}; setmetatable(env, {__index=_G}); env._G=env
    local frames, messages = {}, {}
    local methods = {}
    local function dispatch(w, eventName, value)
        local previousThis, previousArg = env.this, env.arg1
        env.this=w; env.arg1=value
        local fn=w.scripts[eventName]
        if fn then fn() end -- Vanilla handlers receive global this / arg1.
        env.this=previousThis; env.arg1=previousArg
    end
    function methods:SetScript(k,v) self.scripts[k]=v end
    function methods:GetScript(k) return self.scripts[k] end
    function methods:SetWidth(v) self.width=v end
    function methods:GetWidth() return self.width or 100 end
    function methods:SetHeight(v) self.height=v end
    function methods:GetHeight() return self.height or 20 end
    function methods:SetPoint(...) self.point=arg end
    function methods:ClearAllPoints() self.point=nil end
    function methods:SetAllPoints(v) self.allPoints=v end
    function methods:SetParent(v) self.parent=v end
    function methods:GetParent() return self.parent end
    function methods:GetName() return self.name end
    function methods:SetFrameStrata(v) self.strata=v end
    function methods:GetFrameStrata() return self.strata or (self.parent and self.parent:GetFrameStrata()) or 'MEDIUM' end
    function methods:SetFrameLevel(v) self.level=v end
    function methods:GetFrameLevel() return self.level or (self.parent and self.parent:GetFrameLevel()+1) or 0 end
    function methods:SetToplevel(v) self.topLevel=v end
    function methods:SetText(v)
        local changed=self.text~=v; self.text=v
        if changed then dispatch(self,'OnTextChanged') end
    end
    function methods:GetText() return self.text or '' end
    function methods:IsShown() return self.shown and 1 or nil end
    function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) and 1 or nil end
    function methods:Show() local old=self.shown; self.shown=true; if not old then dispatch(self,'OnShow') end end
    function methods:Hide() local old=self.shown; self.shown=false; if old then dispatch(self,'OnHide') end end
    function methods:Enable() self.enabled=true end
    function methods:Disable() self.enabled=false end
    function methods:IsEnabled() return self.enabled and 1 or nil end
    function methods:SetChecked(v) self.checked=v and 1 or nil end
    function methods:GetChecked() return self.checked end
    function methods:SetFocus() self.focus=true; dispatch(self,'OnEditFocusGained') end
    function methods:ClearFocus() self.focus=false; dispatch(self,'OnEditFocusLost') end
    function methods:HasFocus() return self.focus and 1 or nil end
    function methods:GetEffectiveScale() return 1 end
    function methods:GetTop() return 600 end
    function methods:GetBottom() return 0 end
    function methods:GetLeft() return 0 end
    function methods:GetRight() return self:GetWidth() end
    function methods:RegisterEvent(v) self.events[v]=true end
    function methods:SetBackdropColor(...) self.backdropColor=arg end
    function methods:SetBackdrop(v) self.backdrop=v end
    local noop=function() end
    for _,name in ipairs({'SetBackdropBorderColor','SetTextColor','SetJustifyH','SetJustifyV','SetFontObject','SetFont','SetNonSpaceWrap','SetAutoFocus','SetMaxLetters','EnableMouse','EnableMouseWheel','SetMovable','RegisterForDrag','RegisterForClicks','StartMoving','StopMovingOrSizing','SetClampedToScreen','SetScale','SetAlpha','SetOwner','AddLine','AddDoubleLine','SetTexture','SetTexCoord','SetVertexColor','SetBlendMode','HighlightText','SetMultiLine','SetNumeric','SetNormalTexture','SetHighlightTexture','SetPushedTexture'}) do methods[name]=noop end
    local function widget(kind,name,parent)
        local w={kind=kind,name=name,parent=parent,shown=true,enabled=true,scripts={},events={},fonts={}}
        setmetatable(w,{__index=methods}); table.insert(frames,w)
        if name then env[name]=w end
        return w
    end
    function methods:CreateFontString(name) local f=widget('FontString',name,self); table.insert(self.fonts,f); return f end
    function methods:CreateTexture(name) return widget('Texture',name,self) end
    env.CreateFrame=widget; env.UIParent=widget('Frame','UIParent'); env.GameTooltip=widget('Tooltip','GameTooltip')
    env.SlashCmdList={}; env.UISpecialFrames={}
    env.GetAddOnMetadata=function() return '0.74' end
    env.GetTime=function() return 100 end; env.time=function() return 1800000000 end
    env.GetRealmName=function() return 'FixtureRealm' end
    env.UnitName=function(unit) if unit=='player' then return 'Tester' end end
    env.UnitClass=function() return 'Warrior','WARRIOR' end
    env.UnitFactionGroup=function() return 'Alliance' end
    env.UnitLevel=function() return 60 end
    env.GetNumRaidMembers=function() return 0 end; env.GetNumPartyMembers=function() return 0 end
    env.GetCursorPosition=function() return 100,100 end
    env.IsShiftKeyDown=function() return nil end; env.IsControlKeyDown=env.IsShiftKeyDown
    env.DEFAULT_CHAT_FRAME={AddMessage=function(_,text) table.insert(messages,text) end}
    env.SendChatMessage=function(...) error('UI regression must not send chat') end
    env.SendAddonMessage=function(...) error('UI regression must not query the server') end
    env.ShirsRaidBuilderDB=saved or {currentPreset='Default',presets={Default={entries={
        {kind='legacy',charName='Shirmag',class='mage',role='rdps',spec='frost',denyList={}},
        {kind='legacy',charName='Othermag',class='mage',role='rdps',spec='fire',denyList={}}
    },denyRules={},setupRules={}}}}
    for _,name in ipairs({'ShirsRaidBuilder_Core.lua','ShirsRaidBuilder_Abilities.lua','ShirsRaidBuilder.lua'}) do
        local fn=assert(loadfile('../addon/ShirsRaidBuilder/'..name)); setfenv(fn,env); fn()
    end
    env.SlashCmdList.SHIRSRAIDBUILDER('demo') -- Opens real main constructor without server requests.
    local h={env=env,C=env.ShirsRaidBuilderCore,frames=frames,messages=messages}
    function h:fire(w,eventName,value) assert(w and w.scripts[eventName],eventName..' handler missing'); dispatch(w,eventName,value) end
    function h:click(w) assert(w and w:IsVisible() and w:IsEnabled(),'cannot click hidden/disabled widget'); self:fire(w,'OnClick','LeftButton') end
    function h:button(parent,label)
        for _,w in ipairs(frames) do
            if w.parent==parent and w.kind=='Button' and w:IsVisible() and ((w.label and w.label:GetText()==label) or (w.fonts[1] and w.fonts[1]:GetText()==label)) then return w end
        end
        error('visible button missing: '..label)
    end
    function h:preset() return env.ShirsRaidBuilderDB.presets[env.ShirsRaidBuilderDB.currentPreset] end
    function h:entry(name) for _,e in ipairs(self:preset().entries) do if e.charName==name then return e end end; error('entry missing: '..name) end
    function h:open(name)
        local target=self.C.GetWhisperTarget(self:entry(name))
        local row
        for _,w in ipairs(frames) do
            if w.kind=='Button' and w:IsVisible() and w.scripts.OnMouseUp and w.fonts[1] and string.find(w.fonts[1]:GetText(),target,1,true) then row=w end
        end
        assert(row,'rendered companion row missing: '..target)
        self:fire(row,'OnMouseUp','RightButton')
        self:click(self:button(env.ShirsRaidBuilderContextFrame,'Individual commands'))
        return env.ShirsRaidBuilderDenyFrame
    end
    function h:setup(name)
        local d=self:open(name)
        self:click(self:button(d,'Other Commands'))
        return env.ShirsRaidBuilderSetupFrame,d
    end
    function h:choose(button,label)
        self:click(button); self:click(self:button(env.ShirsRaidBuilderChoiceMenu,label))
    end
    function h:addDrink()
        local s=self.env.ShirsRaidBuilderSetupFrame
        self:choose(s.drinkButton,'30%'); self:click(self:button(s,'Add Rule'))
    end
    return h
end

local failures, passes=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passes=passes+1; print('PASS '..name)
    else failures=failures+1; print('FAIL '..name..': '..tostring(err)) end
end
local function hidden(frame) return not frame or not frame:IsVisible() end
local function serialize(value)
    if type(value)=='table' then
        local parts={}; for k,v in pairs(value) do table.insert(parts,'['..serialize(k)..']='..serialize(v)) end
        return '{'..table.concat(parts,',')..'}'
    elseif type(value)=='string' then return string.format('%q',value)
    elseif type(value)=='number' or type(value)=='boolean' then return tostring(value) end
    error('unsupported SavedVariables fixture value')
end
local function reload(h)
    -- Real Lua table save/load boundary, then fresh Core/UI and real EnsureDB.
    local chunk=assert(loadstring('return '..serialize(h.env.ShirsRaidBuilderDB)))
    return boot(chunk())
end

test('fresh row open shows only the individual deny editor',function()
    local h=boot(); local d=h:open('Shirmag')
    assert(d:IsVisible() and d.entry==h:entry('Shirmag'))
    assert(hidden(h.env.ShirsRaidBuilderSetupFrame),'structured setup opens before explicit request')
    assert(hidden(h.env.ShirsRaidBuilderChoiceMenu),'structured dropdown opens before explicit request')
    assert(hidden(h.env.ShirsRaidBuilderAbilityMenu),'blank search must not open suggestions')
    assert(hidden(h.env.ShirsRaidBuilderContextFrame) and hidden(h.env.ShirsRaidBuilderContextShield))
    assert(d:GetFrameStrata()=='FULLSCREEN_DIALOG' and d.topLevel and d:GetFrameLevel()>=80)
end)

test('empty individual search stays empty on focus and text callbacks',function()
    local h=boot(); local d=h:open('Shirmag')
    d.input:SetFocus()
    assert(hidden(h.env.ShirsRaidBuilderAbilityMenu),'empty focus opens suggestions')
    assert(d.input:GetText()=='','empty focus autofills input')
    h:fire(d.input,'OnTextChanged')
    assert(hidden(h.env.ShirsRaidBuilderAbilityMenu),'empty text callback opens suggestions')
    d.input:SetText('frost')
    local menu=h.env.ShirsRaidBuilderAbilityMenu
    assert(menu and menu:IsVisible(),'typed filtering stopped working')
    d.input:SetText('')
    assert(hidden(menu),'clearing search leaves suggestions visible')
    d.input:SetText(' \t ')
    assert(hidden(menu),'whitespace search opens suggestions')
    h:click(h:button(d,'Cancel'))
    d=h:open('Othermag'); d.input:SetFocus()
    assert(d.input:GetText()=='' and hidden(menu),'reopened empty search shows suggestions')
    assert(table.getn(h:entry('Shirmag').denyList)==0 and table.getn(h:entry('Othermag').denyList)==0)
end)

test('warm row open closes previous setup and its dropdown',function()
    local h=boot(); local s=h:setup('Othermag'); h:click(s.drinkButton)
    assert(h.env.ShirsRaidBuilderChoiceMenu:IsVisible())
    h:open('Shirmag')
    assert(hidden(h.env.ShirsRaidBuilderChoiceMenu),'stale structured dropdown remains visible when individual opens')
    assert(hidden(s),'previous structured modal overlaps new individual editor')
end)

test('Other Commands switch has one interactive modal',function()
    local h=boot(); local s,d=h:setup('Shirmag')
    assert(s:IsVisible() and s.entry==h:entry('Shirmag'))
    assert(hidden(d),'deny and structured modal overlap at the same frame strata/level')
    assert(s:GetFrameStrata()=='FULLSCREEN_DIALOG' and s.topLevel and s:GetFrameLevel()>=80)
end)

test('structured panel and dropdown retain explicit stacking',function()
    local h=boot(); local s=h:setup('Shirmag')
    assert(s:GetFrameStrata()=='FULLSCREEN_DIALOG' and s.topLevel and s:GetFrameLevel()>=80)
    h:click(s.drinkButton); local menu=h.env.ShirsRaidBuilderChoiceMenu
    assert(menu:IsVisible() and menu:GetFrameStrata()=='TOOLTIP' and menu.topLevel)
    assert(menu:GetFrameLevel()>s:GetFrameLevel())
end)

test('individual open also closes an existing general setup panel',function()
    local h=boot(); h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Other Commands'))
    local s=h.env.ShirsRaidBuilderSetupFrame; assert(s.entry==nil and s:IsVisible())
    h:open('Shirmag')
    assert(hidden(s),'general setup remains visible behind the individual editor')
end)

test('individual Apply to control identifies the companion',function()
    local h=boot(); local s=h:setup('Shirmag')
    assert(s.applyButton.label:GetText()=='Shirmag-lite','individual Apply to reads '..s.applyButton.label:GetText())
    assert(not s.applyButton:IsEnabled() and not s.classButton:IsEnabled())
end)

test('saved individual rule summary identifies the companion',function()
    local h=boot(); local s=h:setup('Shirmag'); h:addDrink()
    local summary=s.listScroll.rows[1].text:GetText()
    assert(string.find(summary,'Shirmag-lite',1,true),'saved individual summary reads '..summary)
    assert(not string.find(summary,'All Mage',1,true))
end)

test('individual command retains target through construction and save/load',function()
    local h=boot(); h:setup('Shirmag'); h:addDrink(); h=reload(h)
    local p=h:preset(); local e=h:entry('Shirmag')
    assert(table.getn(p.setupRules)==0,'individual rule leaked into general rules')
    assert(table.getn(e.setupRules)==1 and not h:entry('Othermag').setupRules)
    for _,queue in ipairs({h.C.BuildQueue(p),h.C.BuildWhisperQueue(p)}) do
        local count=0
        for _,item in ipairs(queue) do
            if item.command=='set drink 30' then
                count=count+1
                assert(item.target=='Shirmag-lite' and item.phase=='legacy-setup' and item.chatType=='WHISPER','individual drink became a group command')
                assert(p.entries[item.sourceEntryIndex]==e,'queue lost source entry identity')
            end
        end
        assert(count==1,'expected exactly one individual drink command')
    end
end)

test('search remains class filtered and preserves pending denies across switch',function()
    local h=boot(); local d=h:open('Shirmag'); d.input:SetText('frost')
    local menu=h.env.ShirsRaidBuilderAbilityMenu
    assert(menu and menu:IsVisible(),'Mage search did not show suggestions')
    assert(menu:GetFrameStrata()=='TOOLTIP' and menu:GetFrameLevel()>d:GetFrameLevel())
    local allowed={}; for _,v in ipairs(h.C.AbilitiesForClassRole(h.env.ShirsRaidBuilderAbilities,'mage','all')) do allowed[v]=true end
    local option
    for _,w in ipairs(h.frames) do if w.parent==menu and w:IsVisible() and w.kind=='Button' then assert(allowed[w.fonts[1]:GetText()],'cross-class suggestion'); option=w end end
    assert(option); local ability=option.fonts[1]:GetText(); h:click(option); h:click(h:button(d,'Add'))
    assert(d.listScroll.items[1]==ability)
    h:click(h:button(d,'Other Commands')); local s=h.env.ShirsRaidBuilderSetupFrame
    assert(hidden(menu),'search dropdown survives structured switch')
    h:click(h:button(s,'Close'))
    assert(d:IsVisible(),'Close must return to the individual deny editor')
    assert(d.listScroll.items[1]==ability,'switch discarded unsaved deny selection')
    h:click(h:button(d,'Save')); h=reload(h)
    assert(h:entry('Shirmag').denyList[1]==ability)
end)

for _,mutation in ipairs({'remove','replace','class','preset','reorder'}) do
    local change=mutation
    test('stale-target guard: '..change,function()
        local h=boot(); local s=h:setup('Shirmag'); local p=h:preset(); local e=h:entry('Shirmag')
        h:choose(s.drinkButton,'30%')
        local index; for i,v in ipairs(p.entries) do if v==e then index=i end end
        if change=='remove' then table.remove(p.entries,index)
        elseif change=='replace' then p.entries[index]={kind='legacy',charName='Replacement',class='mage',role='rdps'}
        elseif change=='class' then e.class='warlock'
        elseif change=='preset' then h.env.ShirsRaidBuilderDB.presets.Other={entries={},denyRules={},setupRules={}}; h.env.ShirsRaidBuilderDB.currentPreset='Other'
        else local v=table.remove(p.entries,index); table.insert(p.entries,v) end
        h:click(h:button(s,'Add Rule'))
        if change=='reorder' then assert(e.setupRules and table.getn(e.setupRules)==1,'reorder must retain object target')
        else assert(not e.setupRules or table.getn(e.setupRules)==0,'stale editor wrote a command') end
        assert(table.getn(p.setupRules)==0 and table.getn(h:preset().setupRules)==0)
    end)
end

-- Each setup-capable class uses its real dropdown and Add Rule handler.
for _,probe in ipairs({{'mage','drink','30%'},{'shaman','earth'}, {'paladin','aura'}, {'hunter','aspect'}, {'warlock','pet'}}) do
    local class,field,value=unpack(probe)
    test('individual structured handler and target: '..class,function()
        local saved={currentPreset='Default',presets={Default={entries={
            {kind='legacy',charName='Shirmag',class=class,role=class=='paladin' and 'healer' or 'rdps',denyList={}},
            {kind='legacy',charName='Othermag',class=class,role=class=='paladin' and 'healer' or 'rdps',denyList={}}
        },setupRules={},denyRules={}}}}
        local h=boot(saved); local s=h:setup('Shirmag')
        assert(s[field..'Button']:IsVisible(),'missing structured class control')
        local button=s[field..'Button']; h:choose(button,value or button.options[2])
        assert(h.env.ShirsRaidBuilderChoiceMenu:GetFrameStrata()=='TOOLTIP')
        h:click(h:button(s,'Add Rule')); h=reload(h)
        local e=h:entry('Shirmag'); local p=h:preset()
        assert(e.setupRules and table.getn(e.setupRules)==1 and table.getn(p.setupRules)==0)
        local expected=h.C.BuildClassSetupPlan(e.setupRules)
        assert(table.getn(expected)>0,'saved structured selection produced no command')
        local actual={}
        for _,q in ipairs(h.C.BuildWhisperQueue(p)) do
            if q.phase=='legacy-setup' then
                assert(q.target=='Shirmag-lite' and q.class==class)
                table.insert(actual,q.command)
            end
        end
        assert(table.getn(actual)==table.getn(expected))
        for i,q in ipairs(expected) do assert(actual[i]==q.command) end
    end)
end

test('real pending-group dispatch does not fan out an individual drink',function()
    local h=boot(); h:setup('Shirmag'); h:addDrink(); h=reload(h)
    local file=assert(io.open('../addon/ShirsRaidBuilder/ShirsRaidBuilder.lua','rb'))
    local source=file:read('*a'); file:close()
    local first=assert(string.find(source,'local function ExpandPendingGroupDenies()',1,true))
    local last=assert(string.find(source,'if not grinfoFrame then',first,true))
    local body=string.sub(source,first,last-1)
    body=string.gsub(body,'local function ExpandPendingGroupDenies','function ExpandPendingGroupDenies',1)
    local p=h:preset()
    local env={C=h.C,executeQueue=h.C.BuildWhisperQueue(p),executeIndex=1,
        executeCompanionList={{name='Shirmag-lite',class='mage',role='rdps'},{name='Othermag-lite',class='mage',role='rdps'}},
        SnapshotGroup=function() return {['Shirmag-lite']=true,['Othermag-lite']=true} end,
        EnsureDB=function() return p end,UnitName=function() return 'Tester' end,Chat=function() end}
    setmetatable(env,{__index=_G})
    local chunk=assert(loadstring(body,'pending-group dispatch')); setfenv(chunk,env); chunk()
    env.ExpandPendingGroupDenies()
    assert(table.getn(env.executeQueue)==1,'individual setup fanned out to same-class companions')
    assert(env.executeQueue[1].target=='Shirmag-lite' and env.executeQueue[1].command=='set drink 30')
end)

test('general Other Commands handler resets individual scope',function()
    local h=boot(); local s=h:setup('Shirmag'); h:addDrink(); h:click(h:button(s,'Close'))
    h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Other Commands'))
    assert(s.entry==nil and s.classButton:IsEnabled() and s.applyButton:IsEnabled())
    h:choose(s.classButton,'Mage'); h:addDrink()
    assert(table.getn(h:preset().setupRules)==1 and table.getn(h:entry('Shirmag').setupRules)==1)
    local group=h.C.BuildClassSetupPlan(h:preset().setupRules)
    local expanded=h.C.ExpandClassSetup(group,{{name='First',class='mage',role='rdps'},{name='Second',class='mage',role='rdps'}},{})
    assert(table.getn(expanded)==2,'general All Mage must still fan out')
end)

for _,className in ipairs({'warrior','paladin','hunter','warlock','priest','druid','shaman','rogue','mage'}) do
    local class=className
    test('searchable individual deny handler: '..class,function()
        local saved={currentPreset='Default',presets={Default={entries={
            {kind='legacy',charName='Shirmag',class=class,role='rdps',denyList={}}
        },denyRules={},setupRules={}}}}
        local h=boot(saved); local d=h:open('Shirmag')
        local catalog=h.C.AbilitiesForClassRole(h.env.ShirsRaidBuilderAbilities,class,'all')
        assert(table.getn(catalog)>0,'class deny catalogue empty')
        local wanted=catalog[1]; d.input:SetText(string.sub(wanted,1,3))
        local menu=h.env.ShirsRaidBuilderAbilityMenu
        assert(menu and menu:IsVisible(),'class search unavailable')
        local allowed={}; for _,v in ipairs(catalog) do allowed[v]=true end
        for _,w in ipairs(h.frames) do
            if w.parent==menu and w.kind=='Button' and w:IsVisible() then assert(allowed[w.fonts[1]:GetText()],'wrong class suggestion') end
        end
        d.input:SetText(wanted); h:fire(d.input,'OnEnterPressed'); h:click(h:button(d,'Save'))
        h=reload(h); assert(h:entry('Shirmag').denyList[1]==wanted)
        assert(table.getn(h:preset().denyRules)==0,'individual deny leaked to general rules')
        local found=0
        for _,q in ipairs(h.C.BuildWhisperQueue(h:preset())) do
            if q.phase=='legacy-custom' then assert(q.target=='Shirmag-lite' and q.command=='deny add '..wanted); found=found+1 end
        end
        assert(found==1)
    end)
end

for _,mutation in ipairs({'remove','replace','class','preset'}) do
    local change=mutation
    test('stale-target deny Save guard: '..change,function()
        local h=boot(); local d=h:open('Shirmag'); local p=h:preset(); local e=h:entry('Shirmag')
        d.input:SetText('Frostbolt'); h:fire(d.input,'OnEnterPressed')
        local index; for i,v in ipairs(p.entries) do if v==e then index=i end end
        if change=='remove' then table.remove(p.entries,index)
        elseif change=='replace' then p.entries[index]={kind='legacy',charName='Replacement',class='mage',role='rdps',denyList={}}
        elseif change=='class' then e.class='warlock'
        else h.env.ShirsRaidBuilderDB.presets.Other={entries={},denyRules={},setupRules={}}; h.env.ShirsRaidBuilderDB.currentPreset='Other' end
        h:click(h:button(d,'Save'))
        assert(table.getn(e.denyList)==0 and table.getn(p.denyRules)==0)
        assert(d:IsVisible(),'stale Save must not silently succeed')
    end)
end

test('reopening after structured close does not expose its dropdown',function()
    local h=boot(); local s=h:setup('Shirmag'); h:click(s.drinkButton)
    -- Close callback is invoked directly because the dropdown may cover it in game.
    h:fire(h:button(s,'Close'),'OnClick','LeftButton')
    assert(hidden(h.env.ShirsRaidBuilderChoiceMenu))
    h:open('Othermag')
    assert(hidden(s) and hidden(h.env.ShirsRaidBuilderChoiceMenu))
end)

-- Transition guards for the one-panel return path (Close, X, native hide).
for _,closeMode in ipairs({'X','native hide','main hide'}) do
    local mode=closeMode
    test('structured return and menu cleanup: '..mode,function()
        local h=boot(); local s,d=h:setup('Shirmag'); h:click(s.drinkButton)
        if mode=='X' then h:fire(h:button(s,'X'),'OnClick','LeftButton')
        elseif mode=='native hide' then s:Hide()
        else h.env.ShirsRaidBuilderMainFrame:Hide() end
        assert(hidden(s) and hidden(h.env.ShirsRaidBuilderChoiceMenu))
        if mode=='main hide' then assert(hidden(d),'closing main resurrected individual panel')
        else assert(d:IsVisible() and d.entry==h:entry('Shirmag')) end
    end)
end

test('general switch hides individual panel and retains group summary',function()
    local h=boot(); local d=h:open('Shirmag'); d.input:SetText('frost')
    h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Other Commands'))
    local s=h.env.ShirsRaidBuilderSetupFrame
    assert(hidden(d) and hidden(h.env.ShirsRaidBuilderAbilityMenu))
    assert(s.entry==nil and s.applyButton.label:GetText()=='All')
    h:choose(s.classButton,'Mage'); h:addDrink()
    assert(s.listScroll.rows[1].text:GetText()=='All Mage: Drink 30%')
    h:click(h:button(s,'Close')); assert(hidden(d),'general Close restored unrelated individual')
end)

test('individual rule stores builder role independently of target label',function()
    local h=boot(); local s=h:setup('Shirmag'); h:addDrink()
    assert(h:entry('Shirmag').setupRules[1].role=='all')
    assert(table.getn(s.applyButton.options)==1 and s.applyButton.options[1]=='Shirmag-lite')
    h:click(h:button(s,'Close')); s=h:setup('Othermag'); h:addDrink()
    assert(s.listScroll.rows[1].text:GetText()=='Otherma-lite: Drink 30%')
    assert(table.getn(h:entry('Shirmag').setupRules)==1)
end)

test('stale structured close does not restore invalid individual editor',function()
    local h=boot(); local s,d=h:setup('Shirmag')
    h:entry('Shirmag').class='warlock'
    h:click(h:button(s,'Close'))
    assert(hidden(s) and hidden(d))
end)

print('Individual editor regressions: '..passes..' PASS, '..failures..' FAIL')
if failures>0 then error('individual editor regressions failed') end
print("Shir's Raid Builder individual editor tests: PASS")
