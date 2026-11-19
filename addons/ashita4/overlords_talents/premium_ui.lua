-- OverlordsXI Weapon Mastery: art-directed Ashita v4 talent interface.
-- Presentation only: no protocol, talent, persistence or server logic lives here.
local imgui = require('imgui')
local art = require('art')
local UI = {}
local C = {
    gold  = { 0.96, 0.79, 0.47, 1 },
    white = { 0.94, 0.93, 0.86, 1 },
    pale  = { 0.74, 0.76, 0.75, 1 },
    muted = { 0.53, 0.56, 0.59, 1 },
    aqua  = { 0.34, 0.81, 0.87, 1 },
    green = { 0.44, 0.89, 0.65, 1 },
    red   = { 0.97, 0.40, 0.39, 1 },
    dark  = { 0.045, 0.052, 0.078, 0.98 },
    panel = { 0.08, 0.094, 0.13, 0.97 },
    card  = { 0.11, 0.135, 0.18, 0.97 },
    edge  = { 0.26, 0.29, 0.32, 1 },
    black = { 0.02, 0.026, 0.045, 1 },
}
local function u(c)
    if imgui.ColorConvertFloat4ToU32 then return imgui.ColorConvertFloat4ToU32(c) end
    local bit = require('bit')
    local r,g,b,a = math.floor(c[1]*255),math.floor(c[2]*255),math.floor(c[3]*255),math.floor(c[4]*255)
    return bit.bor(bit.lshift(a,24),bit.lshift(b,16),bit.lshift(g,8),r)
end
local function xy(v, b)
    if type(v)=='table' then return v[1] or v.x or 0, v[2] or v.y or 0 end
    return v or 0,b or 0
end
local function txt(t,col)
    if col and imgui.PushStyleColor then imgui.PushStyleColor(ImGuiCol_Text or 0,col) end
    if imgui.TextUnformatted then imgui.TextUnformatted(tostring(t or '')) else imgui.Text((tostring(t or ''):gsub('%%','%%%%'))) end
    if col and imgui.PopStyleColor then imgui.PopStyleColor() end
end
local function at(x,y,t,col)
    imgui.SetCursorScreenPos({x,y})
    txt(t,col)
end
local function rect(dl,x,y,w,h,fill,border,r)
    dl:AddRectFilled({x,y},{x+w,y+h},u(fill),r or 6)
    if border then dl:AddRect({x,y},{x+w,y+h},u(border),r or 6,0,1.1) end
end
local function line(dl,x1,y1,x2,y2,col,thick)
    dl:AddLine({x1,y1},{x2,y2},u(col),thick or 1)
end
local function value(s)
    return tostring(s or ''):gsub('[\r\n]',' ')
end
local function trunc(s,n)
    s=value(s)
    if #s>n then return s:sub(1,n-2)..'..' end
    return s
end
local function paragraphs(s,n)
    local words={} for w in value(s):gmatch('%S+') do words[#words+1]=w end
    local lines,current={},''
    for _,word in ipairs(words) do
        if current=='' then current=word
        elseif #current+#word+1<=n then current=current..' '..word
        else lines[#lines+1]=current;current=word end
    end
    if current~='' then lines[#lines+1]=current end
    return lines
end
local function eyebrow(dl,x,y,label)
    at(x,y,label,C.gold)
    line(dl,x,y+23,x+150,y+23,C.edge,1)
end
local function artPanel(dl,asset,x,y,w,h,fill,border)
    rect(dl,x,y,w,h,fill or C.panel,border or C.edge,5)
    art.draw(dl,asset,x,y,w,h)
end
local function pill(dl,x,y,w,t,col)
    rect(dl,x,y,w,23,C.black,col,12)
    at(x+9,y+3,t,col)
end

local stages={ 'AWAKENING','REFINEMENT','SYNERGY','HYBRIDIZATION','MASTERY' }
local function evo(detail)
    return detail and (detail.id==1 or detail.id==47)
end
local function nodeStatus(n,otherChosen)
    if n.rank>0 then return 'CHOSEN',C.gold end
    if otherChosen then return 'OTHER PATH',C.muted end
    if n.canLearn then return 'AVAILABLE',C.aqua end
    return 'LOCKED',C.muted
end
local function chooseNode(state,action,node,refund)
    state.inspectedNodeKey=node.key
    action.send(refund and 5 or 4,state.wsDetail.id,node.idx or 0,0)
end
local function renderNodeCard(dl,x,y,w,h,node,stage,otherChosen,state,action)
    local active=node.rank>0
    local status,tone=nodeStatus(node,otherChosen)
    local over=false
    imgui.SetCursorScreenPos({x,y})
    imgui.InvisibleButton('##wm_'..node.key,{w,h})
    over=imgui.IsItemHovered()
    if imgui.IsItemClicked(0) then
        state.inspectedNodeKey=node.key
    end
    if imgui.IsItemClicked(1) and active then chooseNode(state,action,node,true) end
    if over then state.inspectedNodeKey=node.key end

    local border=active and C.gold or ((over or state.inspectedNodeKey==node.key) and C.aqua or C.edge)
    local bg=active and {0.18,0.15,0.11,0.98} or C.card
    rect(dl,x,y,w,h,bg,border,7)
    if active then rect(dl,x+4,y+4,4,h-8,C.gold,nil,1) end
    art.draw(dl,'card_frame',x,y,w,h)
    if active then art.draw(dl,'card_selected',x,y,w,h) end
    local icon=74
    rect(dl,x+14,y+14,icon,icon,C.black,border,5)
    local custom=art.draw(dl,'node_'..node.key,x+17,y+17,icon-6,icon-6)
    if not custom then
        custom=art.draw(dl,'ws_'..tostring(state.wsDetail.id),x+18,y+18,icon-8,icon-8)
    end
    if not custom then
        local cx,cy=x+51,y+51
        dl:AddCircle({cx,cy},25,u(border),32,2.2)
        dl:AddCircleFilled({cx,cy},8,u(border),24)
        line(dl,cx-15,cy+12,cx+15,cy-13,border,2)
    end
    at(x+101,y+13,trunc(node.name,math.max(18,math.floor((w-132)/7))),C.white)
    at(x+101,y+38,status,tone)
    local phrase=paragraphs(node.desc,math.max(26,math.floor((w-119)/7)))
    at(x+101,y+61,trunc(phrase[1] or '',49),C.pale)
    if h>121 then at(x+101,y+79,trunc(phrase[2] or '',49),C.muted) end
    if h>128 then
        pill(dl,x+w-100,y+h-31,87,active and 'SELECTED' or (node.canLearn and 'UNLOCK' or 'INSPECT'),tone)
    end
end

local function drawBrowser(state,action,w)
    local dl=imgui.GetWindowDrawList()
    local x,y=xy(imgui.GetCursorScreenPos())
    artPanel(dl,'panel_browser',x,y,w,790,C.panel,C.edge)
    imgui.SetCursorScreenPos({x+17,y+15})
    txt('ARSENAL',C.gold)
    imgui.SetCursorScreenPos({x+17,y+46})
    imgui.PushItemWidth(w-34)
    local skill='Equipped'
    for _,sk in ipairs(action.skills) do if sk.id==state.selectedSkill then skill=sk.name end end
    if imgui.BeginCombo('##wm_filter',skill) then
        for _,sk in ipairs(action.skills) do
            if imgui.Selectable(sk.name,sk.id==state.selectedSkill) then
                state.selectedSkill=sk.id
            end
        end
        imgui.EndCombo()
    end
    imgui.SetCursorScreenPos({x+17,y+80})
    imgui.InputText('##wm_search',state.searchBuf,64)
    imgui.PopItemWidth()
    imgui.SetCursorScreenPos({x+16,y+113})
    imgui.Checkbox('Invested only',state.investedOnly)
    imgui.SetCursorScreenPos({x+16,y+145})
    line(dl,x+16,y+145,x+w-16,y+145,C.edge,1)
    imgui.SetCursorScreenPos({x+10,y+153})
    if imgui.BeginChild('##wm_browser_list',{w-20,625},ImGuiChildFlags_None or 0) then
        local rows=action.filtered()
        dl=imgui.GetWindowDrawList()
        for _,ws in ipairs(rows) do
            local rx,ry=xy(imgui.GetCursorScreenPos())
            local rw=w-35
            imgui.InvisibleButton('##wm_ws_'..ws.id,{rw,55})
            local over=imgui.IsItemHovered()
            local selected=(state.selectedWsId==ws.id)
            if imgui.IsItemClicked(0) then
                state.inspectedNodeKey=nil
                action.requestWS(ws.id)
            end
            rect(dl,rx,ry,rw,51,selected and {0.19,0.17,0.12,1} or (over and C.card or C.panel),
                selected and C.gold or (over and C.aqua or C.edge),4)
            local icon=art.draw(dl,'ws_'..ws.id,rx+7,ry+6,39,39)
            if not icon then
                rect(dl,rx+7,ry+6,39,39,C.black,C.edge,3)
                at(rx+19,ry+14,'*',C.gold)
            end
            at(rx+54,ry+7,trunc(ws.name,23),selected and C.gold or C.white)
            local pts=state.spentByWs[ws.id] or 0
            at(rx+54,ry+29,'TALENT POINTS  /  '..pts,C.muted)
            imgui.SetCursorScreenPos({rx,ry+57})
        end
    end
    imgui.EndChild()
end

local function drawHero(state,dl,x,y,w)
    local d=state.wsDetail
    artPanel(dl,'hero_frame',x,y,w,166,C.panel,C.edge)
    if d then
        art.draw(dl,'hero_'..d.id,x,y,w,166)
        rect(dl,x+18,y+19,120,124,C.black,C.edge,5)
        if not art.draw(dl,'ws_'..d.id,x+22,y+23,112,116) then
            at(x+47,y+59,'WS',C.gold)
        end
        at(x+158,y+26,'WEAPON MASTERY',C.gold)
        at(x+158,y+56,trunc(d.name,34),C.white)
        at(x+158,y+86,trunc(d.skillName,22)..' / '..trunc(state.specName,25),C.pale)
        local total=evo(d) and 5 or 56
        at(x+158,y+113,string.format('%d / %d INVESTED',d.spent or 0,total),C.aqua)
        rect(dl,x+158,y+140,math.max(100,w-188),6,C.black,C.edge,2)
        local progress=math.max(0,math.min(1,(d.spent or 0)/total))
        if progress>0 then rect(dl,x+158,y+140,math.max(2,(w-188)*progress),6,C.gold,nil,2) end
    else
        at(x+26,y+58,'SELECT A WEAPON SKILL',C.gold)
        at(x+26,y+90,'Choose a weapon skill from your arsenal to begin.',C.pale)
    end
end
local function drawMastery(state,action,w)
    local dl=imgui.GetWindowDrawList()
    local x,y=xy(imgui.GetCursorScreenPos())
    local d=state.wsDetail
    drawHero(state,dl,x,y,w)
    imgui.SetCursorScreenPos({x,y+179})
    if imgui.BeginChild('##wm_mastery_scroll',{w,592},ImGuiChildFlags_None or 0) then
        dl=imgui.GetWindowDrawList()
        if not d then
            txt('YOUR WEAPON, YOUR TECHNIQUE',C.gold)
            txt('Select a weapon skill to inspect its mastery tree.',C.pale)
        else
            local isEvo=evo(d)
            local nodesByTier={}
            for _,n in ipairs(d.nodes or {}) do
                if not (isEvo and tostring(n.key):match('^evsc_t')) then
                    nodesByTier[n.tier]=nodesByTier[n.tier] or {}
                    table.insert(nodesByTier[n.tier],n)
                end
            end
            local tiers=isEvo and 5 or 4
            for tier=1,tiers do
                local arr=nodesByTier[tier] or {}
                table.sort(arr,function(a,b) return a.col<b.col end)
                local bx,by=xy(imgui.GetCursorScreenPos())
                local rowH=40 + math.ceil(#arr/(isEvo and 2 or 2))*164
                if isEvo then rowH=212 end
                artPanel(dl,'tier_panel',bx,by,w-16,rowH,C.panel,C.edge)
                art.draw(dl,'stage_'..tier,bx+4,by+4,w-24,33)
                at(bx+17,by+8,string.format('CHAPTER %02d  /  %s',tier,
                    isEvo and stages[tier] or ('TIER '..tier)),C.gold)
                local chosen=false
                for _,n in ipairs(arr) do if n.rank>0 then chosen=true end end
                if isEvo then
                    at(bx+w-105,by+8,chosen and 'ACTIVATED' or 'UNCLAIMED',chosen and C.gold or C.muted)
                end
                local cardW=math.floor((w-48)/2)
                for i,n in ipairs(arr) do
                    local col=(i-1)%2
                    local rr=math.floor((i-1)/2)
                    local nx=bx+12+col*(cardW+8)
                    local ny=by+43+rr*164
                    renderNodeCard(dl,nx,ny,cardW,151,n,tier,chosen and n.rank==0,state,action)
                end
                imgui.SetCursorScreenPos({bx,by+rowH+12})
                imgui.Dummy({w-16,1})
            end
        end
    end
    imgui.EndChild()
end

local function drawInspector(state,action,w)
    local dl=imgui.GetWindowDrawList()
    local x,y=xy(imgui.GetCursorScreenPos())
    local d=state.wsDetail
    artPanel(dl,'panel_inspector',x,y,w,790,C.panel,C.edge)
    eyebrow(dl,x+18,y+17,'TECHNIQUE DETAILS')
    if d then
        local n=d.byKey and d.byKey[state.inspectedNodeKey]
        if not n then
            for _,test in ipairs(d.nodes or {}) do
                if not tostring(test.key):match('^evsc_t') then n=test;break end
            end
        end
        if n then
            at(x+19,y+58,trunc(n.name,32),C.white)
            at(x+19,y+86,'STAGE '..(n.tier or 1)..'   /   '..(n.rank>0 and 'LEARNED' or 'NOT LEARNED'),n.rank>0 and C.gold or C.aqua)
            artPanel(dl,'detail_art',x+18,y+119,w-36,136,C.black,C.edge)
            if not art.draw(dl,'node_'..n.key,x+21,y+122,w-42,130) then
                art.draw(dl,'ws_'..d.id,x+math.floor(w/2)-57,y+125,114,114)
            end
            eyebrow(dl,x+19,y+272,'COMBAT EFFECT')
            local lines=paragraphs(n.desc,math.max(27,math.floor((w-41)/7)))
            for i=1,math.min(#lines,6) do
                at(x+19,y+308+(i-1)*19,lines[i],C.pale)
            end
            if n.reqLevel and (state.jobLevel or 1)<n.reqLevel then
                at(x+19,y+431,'Requires level '..n.reqLevel,C.red)
            end
            if n.reqKey and d.byKey[n.reqKey] then
                at(x+19,y+451,'Requires '..trunc(d.byKey[n.reqKey].name,25),C.muted)
            end
            imgui.SetCursorScreenPos({x+19,y+479})
            if n.rank>0 then
                if imgui.Button('REFUND TECHNIQUE##wm_refund',{w-38,33}) then chooseNode(state,action,n,true) end
            elseif n.canLearn then
                if imgui.Button('AWAKEN TECHNIQUE##wm_invest',{w-38,33}) then chooseNode(state,action,n,false) end
            else
                txt('Unavailable - prerequisites or path choice',C.muted)
            end
        end
        line(dl,x+17,y+535,x+w-17,y+535,C.edge,1)
        eyebrow(dl,x+19,y+542,'SKILLCHAIN FORGING')
        at(x+19,y+572,'Every property can remain OFF.',C.muted)
        local count=0
        for tier=1,4 do
            local sc=d.byKey and (d.byKey[(evo(d) and 'evsc_t' or 'sc_t')..tier])
            if sc then
                count=count+1
                local sy=y+598+(tier-1)*40
                at(x+18,sy,string.format('SLOT %d',tier),C.pale)
                local display=(sc.scId or 0)==0 and 'OFF' or (sc.scName or 'OFF')
                at(x+85,sy,trunc(display,12),(sc.scId or 0)>0 and C.gold or C.muted)
                imgui.SetCursorScreenPos({x+w-74,sy-2})
                if imgui.SmallButton('<##wm_scprev_'..tier) then action.send(6,d.id,tier,2) end
                imgui.SameLine()
                if imgui.SmallButton('>##wm_scnext_'..tier) then action.send(6,d.id,tier,1) end
            end
        end
        if count==0 then at(x+19,y+609,'No skillchain tuning available.',C.muted) end
    else
        at(x+19,y+68,'Select a weapon skill to inspect.',C.pale)
    end
end

function UI.draw(state,action)
    local dl=imgui.GetWindowDrawList()
    local availW=select(1,xy(imgui.GetContentRegionAvail()))
    local width=math.max(1120,availW-4)
    local browserW=248
    local inspectorW=309
    local gap=12
    local centerW=width-browserW-inspectorW-2*gap
    local x,y=xy(imgui.GetCursorScreenPos())
    local height=875

    artPanel(dl,'background_main',x,y,width,height,C.dark,C.edge)
    art.draw(dl,'header_ornament',x+16,y+10,width-32,58)
    at(x+27,y+17,'OVERLORDS XI',C.gold)
    at(x+27,y+42,'WEAPON MASTERY',C.white)
    at(x+330,y+29,state.jobKey..'   /   '..trunc(state.specName,25)..'   /   Lv.'..state.jobLevel,C.pale)
    at(x+725,y+29,string.format('%d AVAILABLE   /   %d SPENT',state.avail or 0,state.spent or 0),C.aqua)
    imgui.SetCursorScreenPos({x+width-184,y+17})
    if imgui.Button('SYNC##wm_sync',{74,30}) then action.sync() end
    imgui.SameLine()
    if not state.confirmResetAll then
        if imgui.Button('RESET##wm_all',{74,30}) then
            state.confirmResetAll=true
            state.confirmResetAt=os.clock()
        end
    elseif os.clock()-(state.confirmResetAt or 0)>5 then
        state.confirmResetAll=false
    else
        if imgui.Button('CONFIRM##wm_reset_confirm',{74,30}) then
            state.confirmResetAll=false
            action.send(8,0,0,0)
        end
    end
    line(dl,x+18,y+69,x+width-18,y+69,C.gold,1.4)
    imgui.SetCursorScreenPos({x+12,y+82})
    if imgui.BeginChild('##wm_browser',{browserW,790},ImGuiChildFlags_None or 0) then
        drawBrowser(state,action,browserW)
    end
    imgui.EndChild()
    imgui.SameLine(0,gap)
    if imgui.BeginChild('##wm_mastery',{centerW,790},ImGuiChildFlags_None or 0) then
        drawMastery(state,action,centerW)
    end
    imgui.EndChild()
    imgui.SameLine(0,gap)
    if imgui.BeginChild('##wm_inspector',{inspectorW,790},ImGuiChildFlags_None or 0) then
        drawInspector(state,action,inspectorW)
    end
    imgui.EndChild()
    if state.statusText and os.clock()-(state.statusTime or 0)<5 then
        at(x+20,y+842,trunc(state.statusText,145),C.aqua)
    end
    if state.renderError then at(x+20,y+818,trunc(state.renderError,140),C.red) end
    imgui.SetCursorScreenPos({x+1,y+height+3})
    imgui.Dummy({width,2})
end

function UI.unload()
    art.clear()
end

return UI
