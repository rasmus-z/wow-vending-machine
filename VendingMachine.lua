﻿local _VERSION = 10
local _GlobalName="VendingMachine"
if _G[_GlobalName] and _G[_GlobalName].version >= _VERSION then return end
local VM = {}
if not _G[_GlobalName] then _G[_GlobalName] = VM end

_G["VM"]=VM
VM.version = _VERSION
VM.UIVer=select(4,GetBuildInfo())
VM.LogLevel=1
local LT=LibThread

VM.StatusCode={
	none=0,
	
	keypress_preset=11,
	
	keypress_asc=21,
	keydown_asc=22,
	keyup_asc=23,
	
	keypress_vk=31,
	keydown_vk=32,
	keyup_vk=33,
	
	mouseclick=51,
	mousemove=52,
	mousesetpreset=53,
	mousemove_left=56,
	mousemove_right=57,
	mousemove_up=58,
	mousemove_down=59,
}

function VM:GetSafeLink(link)
	if not link then return end
	local _,link=GetItemInfo(link)
	if not link then
		if LT:IsThread(self) and self.externalLib==VM then
			self:WaitEvent(5,"GET_ITEM_INFO_RECEIVED")
			_,link=GetItemInfo(link)
		else
			return
		end
	end
	link = link and link:match("|H(.-):([-0-9]+):([0-9]+)|h")
	return link and link:gsub(":0:0:0:0:0:0", "")
end

function VM:GetItemID(link)
	if not link then return end
	if type(link)==number or tonumber(link) or link:find("item:(%d+)") then
		local reqlink=select(2,GetItemInfo(link))
		if reqlink then
			link=reqlink
		elseif LT:IsThread(self) and self.externalLib==VM then
			self:WaitEvent(5,"GET_ITEM_INFO_RECEIVED")
			link=select(2,GetItemInfo(link))
		else
			return
		end
	else
		link=select(2,GetItemInfo(link))
	end
	link=link and link:match("item:(%d+)")
	return tonumber(link)
end

function VM:FindContainerItem(itemID)
	local itemID=self:GetItemID(itemID)
	for bag=0,NUM_BAG_SLOTS do
		for slot=1,GetContainerNumSlots(bag) do
			if itemID==self:GetItemID(GetContainerItemLink(bag,slot)) then
				return bag,slot
			end
		end
	end
end

function VM:GetNumItemStacks(itemID)
	local itemID=self:GetItemID(itemID)
	local maxStack=select(8,GetItemInfo(itemID))
	if not maxStack then return 0 end
	local stackCount=0
	for bag=0,NUM_BAG_SLOTS do
		for slot=1,GetContainerNumSlots(bag) do
			if itemID==self:GetItemID(GetContainerItemLink(bag,slot)) then
				local _,count=GetContainerItemInfo(bag,slot)
				if count==maxStack then
					stackCount=stackCount+1
				end
			end
		end
	end
	return stackCount
end

function VM:WaitSteadyValue(minCount,minTime,func,...)
	local count=0
	local time=GetTime()
	local minCount=minCount or 0
	local minTime=minTime or 0
	local value=func(...)	--ignored possible errors, just trace back to previous call
	repeat
		self:YieldThread()
		local newvalue=func(...)
		if newvalue==value then
			count=count+1
		else
			count=0
			time=GetTime()
			value=newvalue
		end
	until value and count>minCount and GetTime()-time>minTime
	return value
end

function VM:WaitExp(timeOut,func,...)
	local startTime=GetTime()
	while (not timeOut) or (GetTime()-startTime<timeOut) do
		if func(...) then return true end
		self:YieldThread()
	end
	return false
end

function VM:SleepFrame(minCount,minTime)
	local startTime=GetTime()
	for index=1,minCount do
		self:YieldThread()
	end
	if minTime then
		local timeRemaining=minTime-(GetTime()-startTime)
		if timeRemaining>0 then self:Sleep(timeRemaining) end
	end
end

function VM:NewThread(func,prio)
	local prio=prio or 50
	local thread=LT:New(func,prio)
	thread.externalLib=VM
	return thread
end

local function ProcessorStart(self)
	if self.thread then
		VM:log(1,("%s already exists"):format(self.name))
	else
		VM.processors[self.name]=self
		self.thread=VM:NewThread(self.constructor,self.prio)
		VM:log(1,("%s started"):format(self.name))
	end
end

local function ProcessorStop(self)
	if VM.processors[self.name]==self and self.thread then
		self.thread:Dispose()
		self.destructor(self.thread)
		self.thread=nil
		VM:log(1,("%s stopped"):format(self.name))
	else
		VM:log(1,("%s doesn't exist"):format(self.name))
	end
end

function VM:NewProcessor(name,constructor,destructor,prio)
	if not name or not constructor then return end
	VM.processors=VM.processors or {}
	local obj={name=name,constructor=constructor,destructor=destructor,prio=prio,Start=ProcessorStart,Stop=ProcessorStop,}
	VM[name]=obj
end

function VM:callback(...)
	print("|cff00ff00callback",...)
end

function VM:yieldCallback(ret,...)
	if not ret then
		print("|cff0000ffyC error",self,...)
	end
end

function VM:log(level,...)
	if level<=VM.LogLevel then print(format(...)) end
end

local prevStatus,thisStatus
function VM:SetStatus(status,arg1,arg2)
	prevStatus=thisStatus
	local status=status or "none"
	if not VM.db.StatusEnabled then status="none" end
	local arg1=arg1 or 0
	local arg2=arg2 or 0
	status=VM.StatusCode[status] or status
	VM.StatusTexture:SetTexture(status/255,arg1/255,arg2/255,1)
	thisStatus=("%d-%d-%d"):format(status,arg1,arg2)
	return thisStatus==prevStatus
end

function VM:InputBox(prompt,keylist)
	return self:MsgBox(prompt,"ic",keylist)
end

function VM:MsgBox(prompt,map,keylist)
	local t,_,arg1,arg2={}
	local function callback(text)
		self:HardResume(t,text)
	end
	IGAS:MsgBox(prompt,map,callback,keylist)
	repeat
		_,_,arg1,arg2=self:Suspend()
	until arg1==t
	return arg2
end

VM.Init=VM:NewThread(function (self)
	VM.StatusFrame=CreateFrame("Frame","VendingMachineStatusFrame",nil)
	VM.StatusTexture=VM.StatusFrame:CreateTexture("$parentOverlay","OVERLAY")

	VM.StatusFrame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",0,0)
	VM.StatusFrame:SetWidth(5)
	VM.StatusFrame:SetHeight(5)
	VM.StatusTexture:SetAllPoints()
	VM.StatusFrame:SetFrameStrata("TOOLTIP")
	
	self:WaitEvent(2,"VARIABLES_LOADED")		--!!! This is a test condition !!!
	
	if not VendingMachineDB then VendingMachineDB={} end
	VM.db=VendingMachineDB
	VM.db.StatusEnabled=true
	self:SetStatus("none")
end)
VM.Init:HardResume()
