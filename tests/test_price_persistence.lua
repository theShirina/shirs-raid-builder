-- Actual Build -> exact native quote/timer -> Create/overwrite. Synthetic transport only.
local f=assert(io.open('test_planner_linked_quotes.lua'));local src=f:read('*a');f:close()
local at=assert(string.find(src,"\ntest('mixed own",1,true));local fixture=assert(loadstring(string.sub(src,1,at-1)..'\nreturn fixture'))()
local pass,fail=0,0
local outputPrefix=arg and arg[1]
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n..': '..tostring(e))end end
local function dump(v)if type(v)~='table'then return type(v)=='string'and string.format('%q',v)or tostring(v)end;local p={};for k,x in pairs(v)do table.insert(p,'['..dump(k)..']='..dump(x))end;return '{'..table.concat(p,',')..'}'end
local function built()
 local a,b,c,pump,open,emit,state=fixture();local p=open(a,{Alice=true,Bob=true,Carol=true},3);a:click(p.buildButton);pump(8);assert(p.proposal,p.message:GetText())
 return a,b,c,pump,p,emit,state
end
local function counts(a,b,c)return table.getn(a.quoteReads)+table.getn(b.quoteReads)+table.getn(c.quoteReads)end
local function forbid(a)
 for _,name in ipairs({'PlannerBuild','PlannerUltraApply','PlannerUltraReassign','PlannerAllocate','PlannerGroup','PlannerQuoteStart','QuoteStartBatch'})do local key=name;a.C[name]=function()error('Save reran '..key)end end
end

test('registered Build, 31 second expiry timer and offline Create persist exact reviewed plan',function()
 local a,b,c,pump,p=built();local expected=a.C.PlannerCopy(p.proposal.plan);local n=counts(a,b,c);b.noReply=true;c.noReply=true;pump(31);a:fire(p,'OnUpdate',0.25)
 assert(p.proposal and p.applyButton:IsEnabled(),'expiry erased reviewed proposal')
 assert(string.find(p.previewText:GetText(),'Last checked estimate',1,true) and string.find(p.message:GetText(),'Create',1,true),'expired estimate is not clearly labelled savable')
 p.request.quotes=nil -- a discarded price cache is not a composition edit
 forbid(a);p.nameInput:SetText('Expired reviewed');a:click(p.applyButton)
 assert(a.env.ShirsRaidBuilderDB.currentPreset=='Expired reviewed' and a.C.PlannerEqual(expected,a:preset()),p.message:GetText())
 assert(counts(a,b,c)==n,'Create requested fresh prices')
 if outputPrefix then local out=assert(io.open(outputPrefix..'-create.lua','w'));out:write('return '..dump({db=a.env.ShirsRaidBuilderDB,expected=expected,actor='Alice',profile='Expired reviewed'})..'\n');out:close()end
 -- Fresh Core/UI, serialized data: no live table references or price authority survive.
 local file=assert(io.open('test_individual_editor.lua'));local text=file:read('*a');file:close();local at=assert(string.find(text,'\nlocal failures, passes=',1,true))
 local boot=assert(loadstring(string.sub(text,1,at-1)..'\nreturn boot'))();local re=boot(assert(loadstring('return '..dump(a.env.ShirsRaidBuilderDB)))(),'Alice')
 assert(re.C.PlannerEqual(expected,re:preset()),'fresh load changed reviewed composition')
end)

test('expiry inside overwrite warning keeps Cancel inert and Replace exact without queries',function()
 local a,b,c,pump,p=built();local db=a.env.ShirsRaidBuilderDB;local expected=a.C.PlannerCopy(p.proposal.plan);local original=a.C.PlannerCopy(a:preset());local n=counts(a,b,c)
 p.replaceCheck:SetChecked(1);a:fire(p.replaceCheck,'OnClick');a:click(p.applyButton);assert(p.confirmFrame:IsShown())
 pump(31);a:fire(p,'OnUpdate',0.25);forbid(a);a:click(a:button(p.confirmFrame,'Cancel'));assert(a.C.PlannerEqual(original,a:preset())and p.proposal,'Cancel altered data/draft')
 a:click(p.applyButton);a:click(a:button(p.confirmFrame,'Replace'));assert(db.currentPreset=='Default'and a.C.PlannerEqual(expected,a:preset()),p.message:GetText());assert(counts(a,b,c)==n)
 if outputPrefix then local out=assert(io.open(outputPrefix..'-overwrite.lua','w'));out:write('return '..dump({db=db,expected=expected,actor='Alice',profile='Default'})..'\n');out:close()end
end)

for _,cache in ipairs({'empty','partial'})do local cache=cache
 test('discarded '..cache..' price cache is not a composition change',function()
  local a,b,c,pump,p=built();local expected=a.C.PlannerCopy(p.proposal.plan);local n=counts(a,b,c)
  if cache=='empty'then p.request.quotes={}else p.request.quotes['own:alice']=nil end
  p.request.quoteNow=a.now+99;a:fire(p,'OnUpdate',0.25);assert(p.proposal and p.applyButton:IsEnabled()and string.find(p.previewText:GetText(),'Last checked estimate',1,true))
  forbid(a);p.nameInput:SetText('Cache evicted');a:click(p.applyButton);assert(a.C.PlannerEqual(expected,a:preset())and counts(a,b,c)==n)
 end)
end

test('a later visible-plan price timeout cannot erase a successfully built proposal',function()
 local a,b,c,pump,open=fixture();local base=a:preset();base.entries[1]={kind='normal',account='Alice',tier='t3r',class='mage',role='rdps',spec='fire',race='gnome',gender='female'};a.env.RefreshComposition()
 local p=open(a,{Alice=true},1);a:click(p.buildButton);pump(3);local expected=a.C.PlannerCopy(assert(p.proposal).plan)
 a.noReply=true;a:click(a.env.ShirsRaidBuilderMainFrame.syncButton)
 for i=1,200 do pump(0.25);if a.C.plannerQuoteFlight then break end end
 assert(a.C.plannerQuoteFlight,'later native price flight never started');pump(16);a:fire(p,'OnUpdate',0.25)
 assert(a.C.plannerQuoteFlight and a.C.plannerQuoteFlight.drain and p.proposal and p.applyButton:IsEnabled(),'later timeout: flight='..tostring(a.C.plannerQuoteFlight)..' drain='..tostring(a.C.plannerQuoteFlight and a.C.plannerQuoteFlight.drain)..' proposal='..tostring(p.proposal)..' session='..tostring(p.session)..' message='..p.message:GetText()..' reason='..tostring(a.C.visiblePriceWhy))
 local n=counts(a,b,c);forbid(a);p.nameInput:SetText('After timeout');a:click(p.applyButton)
 assert(a.env.ShirsRaidBuilderDB.currentPreset=='After timeout'and a.C.PlannerEqual(expected,a:preset())and counts(a,b,c)==n,'Save after timeout required fresh prices')
end)

test('an initial native quote timeout never invents an Ultra proposal',function()
 local a,b,c,pump,open=fixture();b.noReply=true;local p=open(a,{Bob=true},3);p.request.ultraGold=true;a:click(p.buildButton);pump(24)
 assert(not p.proposal and not p.applyButton:IsEnabled()and counts(a,b,c)==1,'initial unquoted allocation was invented')
 assert(b.C.plannerQuoteFlight and b.C.plannerQuoteFlight.drain,'timeout bypassed unresolved flight')
end)

test('expired price does not allow an in-place composition edit to Save',function()
 local a,b,c,pump,p=built();local db=a.C.PlannerCopy(a.env.ShirsRaidBuilderDB);pump(31);p.request.counts['mage:rdps']=4;forbid(a);p.nameInput:SetText('Unsafe');a:click(p.applyButton)
 assert(a.C.PlannerEqual(db,a.env.ShirsRaidBuilderDB)and not p.proposal,'changed composition saved')
end)

test('missing or partial estimate stays honestly unknown after expiry',function()
 local a,b,c,pump,p=built();local r=a.C.PlannerCopy(p.proposal);r.estimate={complete=false,known=1,unknown=2,totalCopper=1234};r.estimateStale=true
 local text=a.C.PlannerPreviewText(r);assert(string.find(text,'unknown (2 hires unpriced)',1,true)and string.find(text,'Estimated subtotal:',1,true)and string.find(text,'Last checked estimate',1,true),'unknown estimate became zero/fresh total')
end)

print("Shir's Raid Builder price persistence tests: "..(fail==0 and 'PASS'or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0)
