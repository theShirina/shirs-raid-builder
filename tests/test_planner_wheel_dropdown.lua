-- Source-row wheel wiring and shared dropdown option reuse. Exact Lua 5.0.3,
-- whole-module fixture with registered handlers and legacy global this/arg1.
-- Mocked widgets: not native pointer dispatch, pixels or memory measurement.
local f=assert(io.open('test_individual_editor.lua')); local text=f:read('*a'); f:close()
local at=assert(string.find(text,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(text,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(name,fn) local ok,e=pcall(fn); if ok then pass=pass+1; print('PASS '..name) else fail=fail+1; print('FAIL '..name..': '..tostring(e)) end end
local function dump(v)
    if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end
    local keys,out={},{}; for k in pairs(v) do table.insert(keys,k) end; table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do table.insert(out,'['..dump(k)..']='..dump(v[k])) end; return '{'..table.concat(out,',')..'}'
end
local function name(prefix,i) return prefix..string.char(65+math.floor((i-1)/26))..string.char(97+math.mod(i-1,26)) end
local function saved(n)
    local db={syncAccountId='5555555555555555',currentPreset='Default',presets={Default={entries={{kind='player',charName='Aaplayer',class='warrior',role='tank'}},denyRules={},setupRules={}}},inviteCharacters={},legacyCharacters={},legacyCharacterRoles={}}
    local names={'Aaplayer'}; for i=2,n do table.insert(names,name('Loc',i)) end
    for _,nm in ipairs(names) do
        db.inviteCharacters[nm]={name=nm,level=60,dungeonLicense='t5d',raidLicense='t5r',faction='Alliance'}
        db.legacyCharacters[string.lower(nm)]='shaman'; db.legacyCharacterRoles[string.lower(nm)]='healer'
    end
    return db
end
local optionStats
local function start(n)
    local h=boot(saved(n),'Aaplayer'); h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn)
    local p=h.C.plannerFrame; assert(p:IsVisible())
    local _,_,orphans=optionStats(h); h.bootOrphans=orphans -- parentless buttons that predate any dropdown
    return h,p
end
local function controls(row) return {row,row.normalCheck,row.tierButton,row.legacyCheck,row.roleButton} end
local function normal(color) return color and color[1]==0.92 and color[2]==0.95 and color[3]==1.0 end
local function menu(h) return h.env.ShirsRaidBuilderChoiceMenu end
local function hidden(w) return not w or not w:IsShown() end
-- Every Button ever parented to the menu (shown or not), plus detached orphans
-- beyond the parentless buttons present before any dropdown opened.
function optionStats(h)
    local m=menu(h); local pool,shown,orphans=0,0,0
    for _,w in ipairs(h.frames) do
        if w.kind=='Button' and w.parent==m then pool=pool+1; if w:IsShown() then shown=shown+1 end end
        if w.kind=='Button' and w.parent==nil and w~=h.env.UIParent then orphans=orphans+1 end
    end
    return pool,shown,orphans-(h.bootOrphans or 0)
end
local function visibleLabels(h)
    local out={}
    for _,w in ipairs(h.frames) do if w.kind=='Button' and w.parent==menu(h) and w:IsVisible() then table.insert(out,w.fonts[1]:GetText()) end end
    return out
end
local function staleOptions(h)
    local out={}
    for _,w in ipairs(h.frames) do if w.kind=='Button' and w.parent==menu(h) and not w:IsShown() and w.scripts.OnClick then table.insert(out,w) end end
    return out
end
local function globals(env) local n=0; for k,v in pairs(env) do if type(v)=='table' and v.kind then n=n+1 end end; return n end

-- W1: wheel over a source row or any of its four controls scrolls the list.
test('every source row and control forwards the wheel through the shared bounded callback',function()
    local h,p=start(42); assert(p.sourceMax>0)
    local shared=p.sourceScroll:GetScript('OnMouseWheel'); assert(shared)
    for index,row in ipairs(p.sourceRows) do
        for k,w in ipairs(controls(row)) do
            assert(w.wheel==true,'row '..index..' control '..k..' wheel not enabled')
            assert(w:GetScript('OnMouseWheel')==shared,'row '..index..' control '..k..' does not share the list wheel callback')
            p.sourceSlider:SetValue(0)
            h:fire(w,'OnMouseWheel',-1); assert(p.sourceScroll:GetVerticalScroll()==52,'wheel down over control '..k..' did not scroll')
            h:fire(w,'OnMouseWheel',1); assert(p.sourceScroll:GetVerticalScroll()==0,'wheel up over control '..k..' did not scroll back')
        end
    end
end)
test('row wheel clamps at both ends and leaves short lists still',function()
    local h,p=start(42); local w=p.sourceRows[5].tierButton
    for _=1,40 do h:fire(w,'OnMouseWheel',-1) end
    assert(p.sourceScroll:GetVerticalScroll()==p.sourceMax and p.sourceSlider:GetValue()==p.sourceMax,'bottom clamp')
    for _=1,40 do h:fire(w,'OnMouseWheel',1) end
    assert(p.sourceScroll:GetVerticalScroll()==0,'top clamp')
    h,p=start(10); assert(p.sourceMax==0)
    for _,c in ipairs(controls(p.sourceRows[3])) do h:fire(c,'OnMouseWheel',-1); assert(p.sourceScroll:GetVerticalScroll()==0,'no-overflow list moved') end
end)
test('29 sources: first overflowing band is reachable by row wheel and slider',function()
    local h,p=start(29); assert(p.sourceMax==30,'expected first-band overflow, got '..tostring(p.sourceMax))
    assert(p.sourceContent:GetHeight()==396 and p.sourceSlider:IsShown(),'edge extent/scrollbar')
    local last=p.sourceRows[29]; local y=-last.point[5]; assert(y+last:GetHeight()==396,'29th row bottom')
    assert(y+last:GetHeight()>p.sourceScroll:GetVerticalScroll()+p.sourceScroll:GetHeight(),'fixture must start clipped')
    h:fire(last.roleButton,'OnMouseWheel',-1)
    assert(p.sourceScroll:GetVerticalScroll()==30,'wheel did not reach the first-band edge')
    assert(y+last:GetHeight()<=p.sourceScroll:GetVerticalScroll()+p.sourceScroll:GetHeight(),'29th row still clipped')
    h:fire(last.normalCheck,'OnMouseWheel',1); assert(p.sourceScroll:GetVerticalScroll()==0)
    p.sourceSlider:SetValue(p.sourceMax); assert(p.sourceScroll:GetVerticalScroll()==30,'slider reaches the edge')
end)
test('wheel keeps dropdown cleanup, child clicks, hover and handlers intact across 100 repaints',function()
    local h,p=start(42); local row=p.sourceRows[2]; local key=row.source.key
    h:click(row.tierButton); assert(menu(h):IsShown())
    h:fire(row.legacyCheck,'OnMouseWheel',-1); assert(hidden(menu(h)),'row wheel left dropdown open'); p.sourceSlider:SetValue(0)
    h:fire(row.normalCheck,'OnEnter'); assert(h.env.GameTooltip:IsShown()); h:fire(row.normalCheck,'OnLeave'); assert(not h.env.GameTooltip:IsShown())
    h:fire(row,'OnEnter'); assert(h.env.GameTooltip:IsShown()); h:fire(row,'OnLeave')
    row.normalCheck:SetChecked(1); h:click(row.normalCheck); assert(p.request.sources[key].selected,'child click lost')
    local frames=table.getn(h.frames); local before={}
    for i,r in ipairs(p.sourceRows) do before[i]={} for k,w in ipairs(controls(r)) do before[i][k]={w:GetScript('OnMouseWheel'),w:GetScript('OnClick'),w:GetScript('OnEnter')} end end
    for _=1,100 do h.C.PlannerPaintSources() end
    assert(table.getn(h.frames)==frames,'repaint allocated widgets')
    for i,r in ipairs(p.sourceRows) do for k,w in ipairs(controls(r)) do
        assert(w.wheel==true and w:GetScript('OnMouseWheel')==before[i][k][1] and w:GetScript('OnClick')==before[i][k][2] and w:GetScript('OnEnter')==before[i][k][3],'repaint replaced handler')
    end end
end)

-- W2: shared SelectButton reuses one bounded option pool.
test('100 open/close cycles allocate no widgets and leave no orphan options',function()
    local h,p=start(42); local row=p.sourceRows[1]
    h:click(row.tierButton); local count=table.getn(row.tierButton.options); assert(count>1)
    local frames=table.getn(h.frames); local named=globals(h.env)
    local pool,shown,orphans=optionStats(h); assert(pool==count and shown==count and orphans==0,'first open pool '..pool..'/'..shown..'/'..orphans)
    h:click(row.tierButton); assert(hidden(menu(h)))
    for i=1,100 do
        h:click(row.tierButton); assert(menu(h):IsShown(),'reopen '..i)
        h:click(row.tierButton); assert(hidden(menu(h)),'second click close '..i)
    end
    assert(table.getn(h.frames)==frames,'repeated opens grew by '..(table.getn(h.frames)-frames)..' objects')
    pool,shown,orphans=optionStats(h); assert(pool==count and orphans==0,'pool grew or orphaned: '..pool..'/'..orphans)
    assert(globals(h.env)==named,'new global frames')
end)
test('varying menus rebind labels, values and owners; hidden pooled options are inert',function()
    local h,p=start(42); local a,b=p.sourceRows[1],p.sourceRows[2]
    local keyA,keyB=a.source.key,b.source.key
    local tiers=a.tierButton.options; local roles=b.roleButton.options; assert(table.getn(roles)<table.getn(tiers),'fixture needs a smaller menu')
    h:click(a.tierButton); assert(dump(visibleLabels(h))==dump(tiers),'tier labels')
    h:click(b.roleButton); assert(dump(visibleLabels(h))==dump(roles),'role labels after shrink: '..dump(visibleLabels(h)))
    local beforeA,beforeB=dump(p.request.sources[keyA]),dump(p.request.sources[keyB]); local plan=dump(h:preset())
    local stale=staleOptions(h); assert(table.getn(stale)==table.getn(tiers)-table.getn(roles),'hidden spare count')
    for _,w in ipairs(stale) do h:fire(w,'OnClick','LeftButton') end
    assert(menu(h):IsShown(),'stale option closed the live menu')
    assert(dump(p.request.sources[keyA])==beforeA and dump(p.request.sources[keyB])==beforeB and dump(h:preset())==plan,'stale hidden option changed state')
    local pick=roles[table.getn(roles)]; h:click(h:button(menu(h),pick))
    assert(p.request.sources[keyB].legacyRole==pick and b.roleButton.label:GetText()==pick,'role went to wrong owner')
    assert(dump(p.request.sources[keyA])==beforeA,'other row changed')
    assert(a.tierButton.label:GetText()==p.request.sources[keyA].tier,'tier label overwritten by role choice')
    h:click(a.tierButton); assert(dump(visibleLabels(h))==dump(tiers),'regrow labels')
    local pool=optionStats(h); assert(pool==table.getn(tiers),'pool exceeded largest menu')
    h:click(h:button(menu(h),'t2r')); assert(p.request.sources[keyA].tier=='t2r' and p.request.sources[keyB].tier~='t2r' or keyA==keyB)
    assert(p.request.sources[keyB].legacyRole==pick,'tier choice changed role')
end)
test('100 selection changes across rows hit the right source with constant widgets',function()
    local h,p=start(42); local rows={p.sourceRows[1],p.sourceRows[2],p.sourceRows[3]}
    h:click(rows[1].tierButton); h:click(rows[1].tierButton)
    local frames=table.getn(h.frames); local tiers=rows[1].tierButton.options; local expect={}
    for i=1,100 do
        local row=rows[math.mod(i,3)+1]; local value=tiers[math.mod(i*7,table.getn(tiers))+1]
        h:click(row.tierButton); h:click(h:button(menu(h),value)); assert(hidden(menu(h)),'selection left menu open')
        expect[row.source.key]=value
        assert(p.request.sources[row.source.key].tier==value and row.tierButton.label:GetText()==value,'cycle '..i..' wrong selection')
    end
    for _,row in ipairs(rows) do assert(p.request.sources[row.source.key].tier==expect[row.source.key]) end
    assert(table.getn(h.frames)==frames,'selection cycles allocated widgets')
    local _,_,orphans=optionStats(h); assert(orphans==0)
end)
test('scroll, tab, parent hide and Escape still close; stale options stay inert; hover and focus reset',function()
    local h,p=start(42); local row=p.sourceRows[21]; local key=row.source.key
    p.nameInput:SetFocus(); assert(p.nameInput:HasFocus())
    for cycle=1,100 do
        local path=math.mod(cycle,4)
        local focus=p.nameInput:HasFocus()
        h:click(row.tierButton); local m=menu(h); assert(m:IsShown())
        local first=h:button(m,row.tierButton.options[1]); h:fire(first,'OnEnter')
        if path==0 then p.sourceSlider:SetValue(p.sourceSlider:GetValue()==0 and 52 or 0)
        elseif path==1 then h:click(p.tabButtons.counts); h:click(p.tabButtons.sources)
        elseif path==2 then h.C.ClosePlanner(); h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn); assert(h.C.plannerFrame==p)
        else local e=h.env.ShirsRaidBuilderEscaper; e:Show(); e:Hide(); assert(p:IsVisible(),'Escape closed the planner before the dropdown') end
        assert(hidden(m),'close path '..path..' left dropdown open')
        if path==0 then assert(p.nameInput:HasFocus()==focus,'dropdown changed edit focus') end
        local before=dump(p.request.sources[key]); local label=row.tierButton.label:GetText()
        h:fire(first,'OnClick','LeftButton')
        assert(dump(p.request.sources[key])==before and row.tierButton.label:GetText()==label,'stale option after close path '..path)
        h:click(row.tierButton); assert(normal(first.fonts[1].textColor),'hover colour survived reopen')
        h:click(row.tierButton)
    end
    local pool,_,orphans=optionStats(h); assert(pool==table.getn(row.tierButton.options) and orphans==0)
    assert(p.request.sources[key].tier=='t5r','stale clicks changed default tier')
end)
test('other SelectButton owners share the pool without growth or cross-talk',function()
    local h,p=start(12); local row=p.sourceRows[1]
    h:click(row.tierButton); h:click(row.tierButton)
    local frames=table.getn(h.frames)
    for _=1,50 do
        h:click(row.tierButton); assert(dump(visibleLabels(h))==dump(row.tierButton.options))
        h:click(p.tabButtons.priority); assert(hidden(menu(h)),'tab switch left tier menu')
        h:click(p.priorityMode); assert(dump(visibleLabels(h))==dump({'Auto','Custom'}),'priority labels')
        h:click(p.tabButtons.sources); assert(hidden(menu(h)),'tab switch left priority menu')
    end
    assert(table.getn(h.frames)==frames,'mixed owners allocated widgets')
    local _,_,orphans=optionStats(h); assert(orphans==0)
    h:click(p.tabButtons.priority); h:click(p.priorityMode); h:click(h:button(menu(h),'Custom')); assert(p.request.priorityMode=='custom' and p.priorityMode.label:GetText()=='Custom')
    h:click(p.tabButtons.sources)
    assert(row.tierButton.label:GetText()=='t5r','priority choice leaked into tier label')
end)
test('pool grows to its largest menu and reuses every option through 100 empty/shrink/grow cycles',function()
    local h,p=start(12); local a,b=p.sourceRows[1],p.sourceRows[2]
    h:click(a.tierButton); h:click(a.tierButton)
    local largest={}; for _,v in ipairs(a.tierButton.options) do table.insert(largest,v) end
    -- Synthetic labels stress the shared selector only; they are never selected
    -- or passed to a planner setter as valid licence choices.
    for i=1,3 do table.insert(largest,'fixture option '..i) end
    local roles=b.roleButton.options; local before=dump(p.request.sources)
    a.tierButton.options=largest; h:click(a.tierButton)
    local pool,_,orphans=optionStats(h); assert(pool==table.getn(largest) and orphans==0,'growth did not extend one pool')
    local frames=table.getn(h.frames); local named=globals(h.env); local options,handlers={},{}
    for _,w in ipairs(h.frames) do if w.kind=='Button' and w.parent==menu(h) then
        table.insert(options,w); handlers[w]={w:GetScript('OnClick'),w:GetScript('OnEnter'),w:GetScript('OnLeave')}
    end end
    h:click(a.tierButton)
    for cycle=1,100 do
        b.roleButton.options={}; h:click(b.roleButton)
        assert(hidden(menu(h)),'empty menu opened')
        for _,w in ipairs(options) do h:fire(w,'OnClick','LeftButton') end
        assert(before==dump(p.request.sources),'empty menu retained a binding')
        b.roleButton.options=roles; h:click(b.roleButton)
        assert(dump(visibleLabels(h))==dump(roles),'smaller labels')
        for i,w in ipairs(options) do
            if i>table.getn(roles) then
                assert(not w:IsShown() and w.fonts[1]:GetText()=='','hidden spare retained a label')
                h:fire(w,'OnClick','LeftButton')
            else assert(w:GetWidth()==b.roleButton:GetWidth()-8,'smaller width') end
        end
        assert(menu(h):IsShown() and before==dump(p.request.sources),'spare changed owner state')
        h:click(a.tierButton); assert(dump(visibleLabels(h))==dump(largest),'largest labels')
        for _,w in ipairs(options) do
            assert(w:GetWidth()==a.tierButton:GetWidth()-8,'larger width')
            assert(w:GetScript('OnClick')==handlers[w][1] and w:GetScript('OnEnter')==handlers[w][2] and w:GetScript('OnLeave')==handlers[w][3],'reuse changed a handler')
        end
        h:click(a.tierButton)
    end
    pool,_,orphans=optionStats(h)
    assert(pool==table.getn(largest) and orphans==0 and table.getn(h.frames)==frames and globals(h.env)==named,'empty/shrink/grow leaked widgets')
end)
test('source trigger tooltips keep the current owner and options never inherit an old tooltip',function()
    local h,p=start(12); local a,b=p.sourceRows[1],p.sourceRows[2]
    local tt=h.env.GameTooltip
    tt.SetOwner=function(_,owner) tt.lastOwner=owner; tt.lines={} end
    tt.AddLine=function(_,line) table.insert(tt.lines,line) end
    for cycle=1,100 do
        for _,trigger in ipairs({a.tierButton,b.roleButton}) do
            h:fire(trigger,'OnEnter')
            assert(tt:IsShown() and tt.lastOwner==trigger,'tooltip retained another owner')
            assert(tt:GetText()==(trigger.tipTitle or 'Profile') and table.getn(tt.lines)==1 and tt.lines[1]==trigger.tip,'tooltip retained another title/body')
            h:click(trigger); h:fire(trigger,'OnLeave'); assert(not tt:IsShown(),'trigger tooltip did not close')
            for _,w in ipairs(h.frames) do if w.kind=='Button' and w.parent==menu(h) and w:IsVisible() then
                h:fire(w,'OnEnter'); assert(not tt:IsShown(),'pooled option exposed an old tooltip'); h:fire(w,'OnLeave')
            end end
            h:click(trigger)
        end
    end
end)
print("Shir's Raid Builder wheel and dropdown tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('wheel/dropdown regressions failed') end
