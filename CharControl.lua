﻿local VM=VendingMachine
local Astrolabe = DongleStub("Astrolabe-1.0")

local pi=math.pi
local atan=math.atan
local cos=math.cos

local function sgn(n)
	return n>=0 and 1 or -1 
end

function VM:IsPlayerIdle()
	if LootFrame:IsShown() then return false end
	if UnitCastingInfo("player") then return false end
	if UnitChannelInfo("player") then return false end
	if GetUnitSpeed("player")~=0 then return false end
	if IsFalling("player") then return false end
	if UnitIsDeadOrGhost("player") then return false end
	return true
end

function VM:WaitStartMoving()
	local px,py
	local cx,cy=GetPlayerMapPosition("player")
	repeat
		self:YieldThread()
		px,py=cx,cy
		cx,cy=GetPlayerMapPosition("player")
	until cx~=px or cy~=py
end

function VM:WaitStopMoving()
	local px,py
	local cx,cy=GetPlayerMapPosition("player")
	repeat
		self:YieldThread()
		px,py=cx,cy
		cx,cy=GetPlayerMapPosition("player")
	until cx==px and cy==py
end

function VM:InteractUnit(unit)
	if unit=="target" then
		self:SetStatus("keypress_vk",0xDE,0)
		print(self:WaitSecureHook(10, "InteractUnit"))
		self:SetStatus("none")
	end
end

function VM:SendKeyDuration(ttm,vk)
	local ttm_ms=ttm*1000
	if ttm_ms<20 then
		return
	elseif ttm_ms>255*20 then
		self:SetStatus("keydown_vk",vk,0)
		self:Sleep(ttm)
		self:SetStatus("keyup_vk",vk,0)
	else
		local ret=self:SetStatus("keypress_vk",vk,ttm*50)
		if ret then		--If this status is the same with previous one, AHK driver will not execute it
			self:SetStatus("none")	--So we reset it and send again
			self:YieldThread()
			self:SetStatus("keypress_vk",vk,ttm*50)
		end
		self:Sleep(ttm)
	end
	return true
end

function VM:CalcPlayerFacing(direction)
	local speed=3.14
	local current=GetPlayerFacing()
	if current>direction then current=current-pi*2 end
	if direction-current<=pi then	--turn left
		return 0x25,(direction-current)/speed
	else
		return 0x27,(2*pi-direction+current)/speed
	end
end

function VM:SetPlayerFacing(direction,tolerance)
	local speed=3.14
	local tolerance=tolerance or 0.01
	local minttm=20
	local current=GetPlayerFacing()
	if current>direction then current=current-pi*2 end
	-- while (direction-current)/2/pi>tolerance and 1+(current-direction)/2/pi>tolerance do
	for index=1,10 do
		if (direction-current)/2/pi<tolerance or 1+(current-direction)/2/pi<tolerance then break end
		--print("new cycle started at",current)
		if direction-current<=pi then	--turn left
			if not self:SendKeyDuration((direction-current)/speed,0x25) then break end
		else
			if not self:SendKeyDuration((2*pi-direction+current)/speed,0x27) then break end
		end

		--print("Waiting for stop")
		
		current=self:WaitSteadyValue(1,nil,GetPlayerFacing)
		if current>direction then current=current-pi*2 end
	end
	self:SetStatus("none")
	return GetPlayerFacing()
end

function VM:MoveRoute(route,start)
	if type(route)~="table" or #route==0 then return end
	if not start or start<=0 or start>#route then
		start=1
		for index,node in ipairs(route) do
			local nx,ny,nt=unpack(node)
			nt=nt or route.defaultTolerance or self.charMoveTolerance or 1
			if self:CalcDistanceFromPlayer(nx,ny)<nt then
				start=index
				break
			end
		end
	end
	
	for index=start,#route do
		local nx,ny,nt=unpack(route[index])
		self:MoveToPos(nx,ny,nt or route.defaultTolerance)
	end
end

function VM:MoveToPos(x,y,tolerance)
	local tolerance=tolerance or self.charMoveTolerance or 1
	local dist=self:CalcDistanceFromPlayer(x,y)
	-- print("Moving from",cx,cy,"to",x,y,"in map",cmap,cfloor,"dist",dist)
	while dist>tolerance do
		local direction=self:CalcDirectionFromPlayer(x,y)			--calc direction
		self:SetPlayerFacing(direction)
		-- print("direction",direction)
		
		local ttm=dist/self:GetExpectedSpeed()*0.9				--time to move
		if not self:SendKeyDuration(ttm,0x26) then break end	--send up arrow keypress
		
		self:WaitSteadyValue(1,nil,function()
			local px,py=GetPlayerMapPosition("player")
			return px..","..py
		end)
		-- print("waiting for stop")
		-- local px,py												--Wait until moving stops
		-- repeat
			-- px,py=GetPlayerMapPosition("player")
			-- self:YieldThread()
		-- until px==GetPlayerMapPosition("player") and py==select(2,GetPlayerMapPosition("player"))
		
		dist=self:CalcDistanceFromPlayer(x,y)
		-- print("Moving from",cx,cy,"to",x,y,"in map",cmap,cfloor,"dist",dist)
	end
	self:SetStatus("none")
	return GetPlayerMapPosition("player")
end

-- function VM:MoveToPos(x,y,tolerance)
	-- local tolerance=tolerance or self.charMoveTolerance or 1
	-- repeat
		
	-- until dist<=tolerance
-- end

function VM:CalcDistance(fromX,fromY,toX,toY,fromMap,fromFloor,toMap,toFloor)
	if not (fromMap and fromFloor) then fromMap,fromFloor=self:GetPlayerPos() end
	if not (toMap and toFloor) then toMap, toFloor=fromMap, fromFloor end
	return Astrolabe:ComputeDistance(fromMap,fromFloor,fromX,fromY,toMap,toFloor,toX,toY)
end

function VM:CalcDistanceFromPlayer(toX,toY)
	local map,floor,x,y=self:GetPlayerPos()
	return self:CalcDistance(x,y,toX,toY,map,floor)
end

function VM:CalcDistanceToSegment(X1, Y1, XA, YA, XB, YB, map, floor)
	if not (map and floor) then map,floor=self:GetPlayerPos() end
	local seg=self:CalcDistance(XA, YA, XB, YB, map, floor, map, floor)
	local distA=self:CalcDistance(X1, Y1, XA, YA, map, floor, map, floor)
	local distB=self:CalcDistance(X1, Y1, XB, YB, map, floor, map, floor)
	local threshold=0.001
	
	if seg<threshold then
		return min(distA+distB)
	elseif distA<threshold then
		return distA
	elseif distB<threshold then
		return distB
	elseif distB*distB>(distA*distA+seg*seg) then
		return distA
	elseif distA*distA>(distB*distB+seg*seg) then
		return distB
	else
		local l=(distA+distB+seg)/2
		local s=sqrt(l*(l-distA)*(l-distB)*(1-seg))
		return 2*s/seg
	end
end

function VM:CalcDirection(fromX,fromY,toX,toY,map,floor)
	if not (map and floor) then map,floor=self:GetPlayerPos() end
	local sgnX,sgnY=sgn(toX-fromX),sgn(toY-fromY)
	local xoffset=self:CalcDistance(fromX,fromY,toX,fromY,map,floor)
	local yoffset=self:CalcDistance(fromX,fromY,fromX,toY,map,floor)
	--print(xoffset,yoffset)
	local ang=atan(yoffset/xoffset)
	return (1+0.5*sgnX)*pi-ang*sgnX*sgnY
end

function VM:CalcDirectionFromPlayer(toX,toY)
	local map,floor,x,y=self:GetPlayerPos()
	return self:CalcDirection(x,y,toX,toY,map,floor)
end

function VM:GetPlayerPos()
	return Astrolabe:GetCurrentPlayerPosition()
end

function VM:GetPlayerSpeed()
	return self.SpeedTracker.playerSpeed or 0
end

function VM:GetExpectedSpeed()
	local speed,groundSpeed,flightSpeed,swimSpeed = GetUnitSpeed("player")
	return IsFlying() and flightSpeed*cos(GetUnitPitch("player")) or groundSpeed
end

-- if VM.SecureRangeChecker then VM.SecureRangeChecker:Dispose() end
-- VM.SecureRangeChecker=VM:NewThread(function (self)
	-- while true do
		-- if not self:IsInLegalPath() then
			-- self.SecureRangeChecker
		-- self:Sleep(self.freq)
	-- end
-- end)

VM:NewProcessor("NPCScan",function(self)
	route={
		{0.57606160640717,0.82229042053223,10},
		{0.38872981071472,0.6744556427002 ,10},
		{0.45376074314117,0.49914526939392,10},
		{0.65845191478729,0.43288856744766,10},
	}
	
	while true do
		local startTime=time()
		for index,node in ipairs(route) do
			self:MoveToPos(unpack(node))
		end
		print("NPCScan route finished in",time()-startTime,"s")
		self:YieldThread()
	end
end,function (self) self:SetStatus("none") end)

--[[
VM:NewThread("RouteTracker", function(self)
	VM.db.Routes=VM.db.Routes or {}
	if self:MsgBox("Do you really want to create a route now?","n") then
		local name=self:InputBox("Name for new route:")
		
	end
end)
--]]
--[[
VM:NewThread(function(self)

	local route={ -- _G["VMroute"]
		[1] = { -- table: 281A7D00
			0.40096336603165,
			0.50513219833374
		}, -- table: 281A7D00,
		[2] = { -- table: 3174F2F0
			0.41736966371536,
			0.52359253168106
		}, -- table: 3174F2F0,
		[3] = { -- table: 3174F340
			0.43310236930847,
			0.54129576683044
		}, -- table: 3174F340,
		[4] = { -- table: 3174F3B8
			0.44491440057755,
			0.55203574895859
		}, -- table: 3174F3B8,
		[5] = { -- table: 3174F408
			0.45907610654831,
			0.54002064466476
		}, -- table: 3174F408,
		[6] = { -- table: 31752658
			0.47012668848038,
			0.51841008663177
		}, -- table: 31752658,
		[7] = { -- table: 3EF75130
			0.48081177473068,
			0.50264286994934
		}, -- table: 3EF75130,
		[8] = { -- table: 3EF753B0
			0.49686342477798,
			0.48793196678162
		}, -- table: 3EF753B0,
		[9] = { -- table: 3EF75810
			0.51402831077576,
			0.49427568912506
		}, -- table: 3EF75810,
		[10] = { -- table: 3EF75B80
			0.52809464931488,
			0.50957429409027
		}, -- table: 3EF75B80,
		[11] = { -- table: 3EF76350
			0.53849357366562,
			0.52240478992462
		}, -- table: 3EF76350,
		[12] = { -- table: 3EF769B8
			0.55236232280731,
			0.53745454549789
		}, -- table: 3EF769B8,
		[13] = { -- table: 3EF76EE0
			0.56580471992493,
			0.51972663402557
		}, -- table: 3EF76EE0,
		defaultTolerance = 2
	} -- _G["VMroute"]

	self:Sleep(1)
	-- local x1,y1=0.39446449279785, 0.42342627048492
	-- local x2,y2=0.39884746074677, 0.42509853839874
	-- local x3,y3=0.39717638492584, 0.43521428108215
	local x1,y1=0.38750076293945, 0.25654846429825
	local x2,y2=0.40259879827499, 0.32153469324112
	-- local dir=self:CalcDirection(x1,y1,x2,y2)
	-- print("turning",dir)
	-- self:SetPlayerFacing(dir)
	-- print("finished")
	self:MoveToPos(x1,y1)
	-- self:MoveRoute(route)
end)
--]]
