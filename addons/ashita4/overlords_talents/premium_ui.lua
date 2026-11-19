-- OverlordsXI Weapon Mastery: art-directed Ashita v4 talent interface.
-- Presentation only: no protocol, talent, persistence or server logic lives here.
local imgui = require('imgui')
local art = require('art')
local UI = {}
local C = {
    gold    = { 0.96, 0.79, 0.47, 1 },
    bronze  = { 0.74, 0.56, 0.34, 1 },
    white   = { 0.94, 0.93, 0.86, 1 },
    pale    = { 0.76, 0.78, 0.77, 1 },
    muted   = { 0.53, 0.56, 0.59, 1 },
    aqua    = { 0.34, 0.81, 0.87, 1 },
    green   = { 0.44, 0.89, 0.65, 1 },
    red     = { 0.97, 0.40, 0.39, 1 },
    crimson = { 0.52, 0.14, 0.16, 1 },
    dark    = { 0.045, 0.052, 0.078, 0.98 },
    panel   = { 0.08, 0.094, 0.13, 0.97 },
    card    = { 0.11, 0.135, 0.18, 0.97 },
    edge    = { 0.26, 0.29, 0.32, 1 },
    black   = { 0.02, 0.026, 0.045, 1 },
    scrim   = { 0.03, 0.035, 0.055, 0.66 },
    dimTint = { 0.46, 0.48, 0.52, 0.90 },
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
    if not art.draw(dl,asset,x,y,w,h) then
        rect(dl,x,y,w,h,fill or C.panel,border or C.edge,5)
    end
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
    local avail=(not active) and (not otherChosen) and node.canLearn
    local locked=(not active) and (not avail)
    local isCapstone=(evo(state.wsDetail) and stage==5) or ((not evo(state.wsDetail)) and stage==4)
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

    local inspected=(state.inspectedNodeKey==node.key)
    local border=active and C.gold or (avail and (over and C.gold or C.bronze) or ((over or inspected) and C.aqua or C.edge))
    local bg=active and {0.18,0.15,0.11,0.98} or (locked and {0.07,0.08,0.11,0.95} or C.card)
    local artTint=locked and u(C.dimTint) or 0xFFFFFFFF

    if not art.draw(dl,'card_frame',x,y,w,h,artTint) then
        rect(dl,x,y,w,h,bg,border,7)
        if active then rect(dl,x+4,y+4,4,h-8,C.gold,nil,1) end
    else
        if avail then
            dl:AddRect({x+2,y+2},{x+w-2,y+h-2},u(over and C.gold or C.bronze),3,0,over and 1.6 or 1.1)
        elseif (over or inspected) and not active then
            dl:AddRect({x+1,y+1},{x+w-1,y+h-1},u(C.aqua),3,0,1.4)
        elseif isCapstone and not active then
            dl:AddRect({x+2,y+2},{x+w-2,y+h-2},u({0.58,0.44,0.22,0.55}),3,0,1.0)
        end
    end
    if active then
        if not art.draw(dl,'card_selected',x,y,w,h) then
            rect(dl,x+4,y+4,4,h-8,C.gold,nil,1)
        end
    end
    local icon=74
    rect(dl,x+14,y+14,icon,icon,C.black,active and C.gold or border,5)
    local custom=art.draw(dl,'node_'..node.key,x+17,y+17,icon-6,icon-6,artTint)
    if not custom then
        custom=art.draw(dl,'ws_'..tostring(state.wsDetail.id),x+18,y+18,icon-8,icon-8,artTint)
    end
    if not custom then
        local cx,cy=x+51,y+51
        dl:AddCircle({cx,cy},25,u(border),32,2.2)
        dl:AddCircleFilled({cx,cy},8,u(border),24)
        line(dl,cx-15,cy+12,cx+15,cy-13,border,2)
    end
    local nameCol=active and C.gold or (locked and C.muted or C.white)
    local descCol=locked and C.muted or C.pale
    at(x+101,y+13,trunc(node.name,math.max(18,math.floor((w-132)/7))),nameCol)
    local badgeText=isCapstone and (active and 'MASTERED' or status) or status
    at(x+101,y+38,badgeText,tone)
    local phrase=paragraphs(node.desc,math.max(26,math.floor((w-119)/7)))
    at(x+101,y+61,trunc(phrase[1] or '',49),descCol)
    if h>121 then at(x+101,y+79,trunc(phrase[2] or '',49),C.muted) end
    if h>128 then
        pill(dl,x+w-100,y+h-31,87,active and 'MASTERED' or (avail and 'UNLOCK' or 'INSPECT'),tone)
    end
end

local function drawBrowser(state,action,w)
    local dl=imgui.GetWindowDrawList()
    local x,y=xy(imgui.GetCursorScreenPos())
    artPanel(dl,'panel_browser',x,y,w,790,C.panel,C.edge)
    imgui.SetCursorScreenPos({x+18,y+18})
    txt('ARSENAL',C.gold)
    imgui.SetCursorScreenPos({x+18,y+48})
    imgui.PushItemWidth(w-36)
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
    imgui.SetCursorScreenPos({x+18,y+82})
    imgui.InputText('##wm_search',state.searchBuf,64)
    imgui.PopItemWidth()
    imgui.SetCursorScreenPos({x+18,y+115})
    imgui.Checkbox('Invested only',state.investedOnly)
    imgui.SetCursorScreenPos({x+18,y+146})
    line(dl,x+18,y+146,x+w-18,y+146,C.edge,1)
    imgui.SetCursorScreenPos({x+16,y+154})
    if imgui.BeginChild('##wm_browser_list',{w-32,618},ImGuiChildFlags_None or 0) then
        local rows=action.filtered()
        dl=imgui.GetWindowDrawList()
        for _,ws in ipairs(rows) do
            local rx,ry=xy(imgui.GetCursorScreenPos())
            local rw=w-48
            imgui.InvisibleButton('##wm_ws_'..ws.id,{rw,55})
            local over=imgui.IsItemHovered()
            local selected=(state.selectedWsId==ws.id)
            if imgui.IsItemClicked(0) then
                state.inspectedNodeKey=nil
                action.requestWS(ws.id)
            end
            rect(dl,rx,ry,rw,51,selected and {0.17,0.14,0.09,0.98} or (over and C.card or C.panel),
                selected and C.gold or (over and C.aqua or C.edge),4)
            if selected then rect(dl,rx+1,ry+4,3,43,C.gold,nil,1) end
            rect(dl,rx+7,ry+6,39,39,C.black,selected and C.gold or C.edge,3)
            local icon=art.draw(dl,'ws_'..ws.id,rx+8,ry+7,37,37)
            if not icon then
                local icx,icy=rx+26,ry+25
                dl:AddQuadFilled({icx,icy-8},{icx+8,icy},{icx,icy+8},{icx-8,icy},u(selected and C.gold or C.bronze))
                dl:AddQuad({icx,icy-12},{icx+12,icy},{icx,icy+12},{icx-12,icy},u(selected and C.gold or C.edge),1.2)
            end
            at(rx+54,ry+7,trunc(ws.name,21),selected and C.gold or C.white)
            local pts=state.spentByWs[ws.id] or 0
            local isEvoWs=(ws.id==1 or ws.id==47)
            local progText=isEvoWs and string.format('EVOLUTION  %d / 5',pts) or string.format('MASTERY  %d PTS',pts)
            at(rx+54,ry+29,progText,pts>0 and C.aqua or C.muted)
            imgui.SetCursorScreenPos({rx,ry+57})
        end
    end
    imgui.EndChild()
end

local function drawHero(state,dl,x,y,w)
    local d=state.wsDetail
    artPanel(dl,'hero_frame',x,y,w,166,C.panel,C.edge)
    if d then
        local hasHero=art.draw(dl,'hero_'..d.id,x+10,y+10,w-20,146)
        if hasHero then
            rect(dl,x+150,y+16,math.max(120,w-168),134,C.scrim,nil,5)
        end
        rect(dl,x+22,y+21,120,124,C.black,C.gold,5)
        if not art.draw(dl,'ws_'..d.id,x+26,y+25,112,116) then
            local cx,cy=x+82,y+83
            dl:AddQuadFilled({cx,cy-18},{cx+18,cy},{cx,cy+18},{cx-18,cy},u(C.bronze))
            dl:AddQuad({cx,cy-28},{cx+28,cy},{cx,cy+28},{cx-28,cy},u(C.gold),1.6)
        end
        at(x+162,y+24,evo(d) and 'EVOLUTION MASTERY' or 'WEAPON MASTERY',C.gold)
        at(x+162,y+52,trunc(d.name,34),C.white)
        at(x+162,y+82,trunc(d.skillName,22)..'  /  '..trunc(state.specName,25),C.pale)
        local total=evo(d) and 5 or 56
        at(x+162,y+110,string.format('%d / %d INVESTED',d.spent or 0,total),C.aqua)
        local barW=math.max(100,w-194)
        rect(dl,x+162,y+137,barW,8,C.black,C.bronze,3)
        local progress=math.max(0,math.min(1,(d.spent or 0)/total))
        if progress>0 then rect(dl,x+163,y+138,math.max(4,(barW-2)*progress),6,C.gold,nil,2) end
    else
        at(x+28,y+58,'SELECT A WEAPON SKILL',C.gold)
        at(x+28,y+90,'Choose a weapon skill from your arsenal to begin.',C.pale)
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
            local prevChosen=false
            for tier=1,tiers do
                local arr=nodesByTier[tier] or {}
                table.sort(arr,function(a,b) return a.col<b.col end)
                local bx,by=xy(imgui.GetCursorScreenPos())
                local rowH=40 + math.ceil(#arr/2)*164
                if isEvo then rowH=212 end
                if tier>1 then
                    local sx=bx+math.floor((w-16)/2)
                    local spineCol=prevChosen and C.gold or C.edge
                    line(dl,sx,by-12,sx,by+2,spineCol,2.2)
                    dl:AddQuadFilled({sx,by-9},{sx+4,by-5},{sx,by-1},{sx-4,by-5},u(spineCol))
                end
                artPanel(dl,'tier_panel',bx,by,w-16,rowH,C.panel,C.edge)
                local ornW=math.max(120,w-380)
                art.draw(dl,'stage_'..tier,bx+math.floor((w-16-ornW)/2),by+6,ornW,28)
                at(bx+18,by+10,string.format('CHAPTER %02d  /  %s',tier,
                    isEvo and stages[tier] or ('TIER '..tier)),C.gold)
                local chosen=false
                for _,n in ipairs(arr) do if n.rank>0 then chosen=true end end
                if isEvo then
                    at(bx+w-110,by+10,chosen and 'ACTIVATED' or 'UNCLAIMED',chosen and C.gold or C.muted)
                end
                local cardW=math.floor((w-56)/2)
                for i,n in ipairs(arr) do
                    local col=(i-1)%2
                    local rr=math.floor((i-1)/2)
                    local nx=bx+14+col*(cardW+12)
                    local ny=by+44+rr*164
                    renderNodeCard(dl,nx,ny,cardW,151,n,tier,chosen and n.rank==0,state,action)
                end
                if isEvo and #arr==2 then
                    local mx=bx+14+cardW+6
                    local my=by+44+75
                    local linkCol=chosen and C.gold or C.bronze
                    line(dl,mx-6,my,mx+6,my,linkCol,1.5)
                    dl:AddQuadFilled({mx,my-5},{mx+5,my},{mx,my+5},{mx-5,my},u(C.black))
                    dl:AddQuad({mx,my-5},{mx+5,my},{mx,my+5},{mx-5,my},u(linkCol),1.3)
                end
                prevChosen=chosen
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
    eyebrow(dl,x+24,y+20,'TECHNIQUE DETAILS')
    if d then
        local n=d.byKey and d.byKey[state.inspectedNodeKey]
        if not n then
            for _,test in ipairs(d.nodes or {}) do
                if not tostring(test.key):match('^evsc_t') then n=test;break end
            end
        end
        if n then
            at(x+24,y+58,trunc(n.name,30),n.rank>0 and C.gold or C.white)
            at(x+24,y+86,'STAGE '..(n.tier or 1)..'   /   '..(n.rank>0 and 'LEARNED' or (n.canLearn and 'AVAILABLE' or 'LOCKED')),
                n.rank>0 and C.gold or (n.canLearn and C.aqua or C.muted))
            artPanel(dl,'detail_art',x+24,y+119,w-48,136,C.black,C.edge)
            local px=x+math.floor(w/2)-57
            local py=y+130
            rect(dl,px-2,py-2,118,118,C.black,n.rank>0 and C.gold or C.bronze,4)
            if not art.draw(dl,'node_'..n.key,px,py,114,114) then
                if not art.draw(dl,'ws_'..d.id,px,py,114,114) then
                    local icx,icy=px+57,py+57
                    dl:AddQuad({icx,icy-24},{icx+24,icy},{icx,icy+24},{icx-24,icy},u(C.bronze),1.6)
                end
            end
            eyebrow(dl,x+24,y+270,'COMBAT EFFECT')
            local lines=paragraphs(n.desc,math.max(25,math.floor((w-52)/7)))
            for i=1,math.min(#lines,5) do
                at(x+24,y+304+(i-1)*19,lines[i],C.pale)
            end
            local reqY=y+410
            local lvlReq=n.reqLevel or 1
            local lvlOk=(state.jobLevel or 1)>=lvlReq
            at(x+24,reqY,string.format('%s Level %d+  (Now %d)',lvlOk and '[OK]' or '[REQ]',lvlReq,state.jobLevel or 1),lvlOk and C.green or C.red)
            reqY=reqY+19
            if (n.reqWsPoints or 0)>0 then
                local ptsOk=(d.spent or 0)>=n.reqWsPoints
                at(x+24,reqY,string.format('%s %d+ WS Points  (Now %d)',ptsOk and '[OK]' or '[REQ]',n.reqWsPoints,d.spent or 0),ptsOk and C.green or C.red)
                reqY=reqY+19
            end
            if n.reqKey and d.byKey[n.reqKey] then
                local pNode=d.byKey[n.reqKey]
                local pOk=(pNode.rank or 0)>=(n.reqRank or 1)
                at(x+24,reqY,string.format('%s %s',pOk and '[OK]' or '[REQ]',trunc(pNode.name,24)),pOk and C.green or C.red)
            end
            imgui.SetCursorScreenPos({x+24,y+476})
            if n.rank>0 then
                local pushed=0
                if imgui.PushStyleColor and ImGuiCol_Button then
                    imgui.PushStyleColor(ImGuiCol_Button,C.crimson)
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered,{0.68,0.20,0.22,1})
                    pushed=2
                end
                if imgui.Button('REFUND TECHNIQUE##wm_refund',{w-48,34}) then chooseNode(state,action,n,true) end
                if pushed>0 then imgui.PopStyleColor(pushed) end
            elseif n.canLearn then
                local pushed=0
                if imgui.PushStyleColor and ImGuiCol_Button then
                    imgui.PushStyleColor(ImGuiCol_Button,{0.36,0.26,0.12,1})
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered,{0.52,0.38,0.17,1})
                    pushed=2
                end
                if imgui.Button('AWAKEN TECHNIQUE##wm_invest',{w-48,34}) then chooseNode(state,action,n,false) end
                if pushed>0 then imgui.PopStyleColor(pushed) end
            else
                rect(dl,x+24,y+476,w-48,34,C.black,C.edge,4)
                at(x+34,y+485,'Locked - check stage or path',C.muted)
            end
        end
        line(dl,x+24,y+528,x+w-24,y+528,C.bronze,1)
        eyebrow(dl,x+24,y+538,'SKILLCHAIN FORGING')
        at(x+24,y+568,'Select properties or leave any slot OFF.',C.muted)
        local count=0
        for tier=1,4 do
            local sc=d.byKey and (d.byKey[(evo(d) and 'evsc_t' or 'sc_t')..tier])
            if sc then
                count=count+1
                local sy=y+594+(tier-1)*42
                local activeSc=(sc.scId or 0)>0
                rect(dl,x+24,sy-4,w-48,32,C.black,activeSc and C.gold or C.edge,4)
                at(x+32,sy+3,string.format('SLOT %d',tier),C.pale)
                local display=activeSc and (sc.scName or 'OFF') or 'OFF'
                at(x+94,sy+3,trunc(display,12),activeSc and C.gold or C.muted)
                imgui.SetCursorScreenPos({x+w-80,sy+1})
                if imgui.SmallButton('<##wm_scprev_'..tier) then action.send(6,d.id,tier,2) end
                imgui.SameLine()
                if imgui.SmallButton('>##wm_scnext_'..tier) then action.send(6,d.id,tier,1) end
            end
        end
        if count==0 then at(x+24,y+609,'No skillchain tuning available.',C.muted) end
    else
        at(x+24,y+68,'Select a weapon skill to inspect.',C.pale)
    end
end

function UI.draw(state,action)
    local dl=imgui.GetWindowDrawList()
    local availW=select(1,xy(imgui.GetContentRegionAvail()))
    local width=math.max(1120,availW-4)
    local browserW=248
    local inspectorW=309
    local gap=12
    local padX=12
    local centerW=width-browserW-inspectorW-2*gap-2*padX
    local x,y=xy(imgui.GetCursorScreenPos())
    local height=884

    artPanel(dl,'background_main',x,y,width,height,C.dark,C.edge)
    local headerDrawn=art.draw(dl,'header_ornament',x+20,y+10,width-40,62)
    local titleX=headerDrawn and (x+108) or (x+27)
    at(titleX,y+20,'OVERLORDS XI',C.gold)
    at(titleX,y+43,'WEAPON MASTERY',C.white)
    at(x+310,y+31,state.jobKey..'   /   '..trunc(state.specName,25)..'   /   Lv.'..state.jobLevel,C.pale)
    at(x+670,y+31,string.format('%d AVAILABLE   /   %d SPENT',state.avail or 0,state.spent or 0),C.aqua)
    local btnX=headerDrawn and (x+width-248) or (x+width-184)
    imgui.SetCursorScreenPos({btnX,y+24})
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
    if not headerDrawn then
        line(dl,x+18,y+74,x+width-18,y+74,C.gold,1.4)
    end
    imgui.SetCursorScreenPos({x+padX,y+82})
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
