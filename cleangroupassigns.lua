--[[
World of Warcraft Classic Addon to automatically sort your raid based on your preset arrangements.
Author: Munchkin-Fairbanks <clean>
https://github.com/fjaros/cleangroupassigns
]]

cgaConfigDB = {
	welcome = false,
	filterCheck = false,
	filterRank = 1,
}
minimapButtonDB = {
	hide = false,
}
arrangementsDB = {}
playerBankDB = {}

local cleangroupassigns = LibStub("AceAddon-3.0"):NewAddon("cleangroupassigns", "AceComm-3.0", "AceEvent-3.0", "AceHook-3.0", "AceSerializer-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local LD = LibStub("LibDeflate")
local LSM = LibStub("LibSharedMedia-3.0")
local DEFAULT_FONT = LSM.MediaTable.font[LSM:GetDefault('font')]
local MIN_LEVEL = 70

local playerTable = {}
local labels = {}

local shouldPrint = false
local inSwap = false
local remoteInSwap = false
local swapCounter = 0

local isDraggingLabel = false
local shouldUpdatePlayerBank = false

local GLOBAL_PRINT = print
local print = function(message)
	message = "|cFFFF7D0A[cga]|r |cFF24A8FF" .. (tostring(message) or "nil") .. "|r"
	GLOBAL_PRINT(message)
end

local function charLength(str)
	local b = string.byte(str, 1)
	if b then
		if b >= 194 and b < 224 then
			return 2
		elseif b >= 224 and b < 240 then
			return 3
		elseif b >= 240 and b < 245 then
			return 4
		end
	end
	return 1
end

local function pairsByKeys(t, f)
    local a = {}
    for n in pairs(t) do table.insert(a, n) end
    table.sort(a, f)
    local i = 0
    local iter = function()
		i = i + 1
		if a[i] == nil then return nil
		else return a[i], t[a[i]]
		end
	end
	return iter
end

local function GetXY()
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	return x / scale, y / scale
end

local function PlayerMarkDeleted(name)
	-- pointless to store the entry if we don't know the player's class
	if playerTable[name].class then
		if not playerBankDB[name] then
			playerBankDB[name] = {}
		end
		playerBankDB[name].class = playerTable[name].class:upper()
		playerBankDB[name].isDeleted = true
	else
		playerBankDB[name] = nil
	end
	playerTable[name] = nil
end

local function FindClass(name)
	-- try to determine class from guild or group or playerBankDB
	for i = 1, GetNumGuildMembers() do
		local tmpName, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
		if tmpName then
			tmpName = strsplit("-", tmpName)
			if name == tmpName then
				return class
			end
		end
	end

	for i = 1, GetNumGroupMembers() do
		local tmpName, _, _, _, _, class = GetRaidRosterInfo(i)
		if tmpName then
			tmpName = strsplit("-", tmpName)
			if name == tmpName then
				return class
			end
		end
	end

	if playerBankDB[name] then
		return playerBankDB[name].class
	end
end

local function AddToPlayerTable(name, class, raidIndex, rankIndex)
	if not name then
		return
	end

	local cLen = charLength(name)
	name = string.sub(name, 1, cLen):upper() .. string.sub(name, cLen + 1):lower()

	if not playerTable[name] then
		playerTable[name] = {}
	end
	local addedExplicitly = not class
	if addedExplicitly then
		class = FindClass(name)
		if not playerBankDB[name] then
			playerBankDB[name] = {}
		end
	end

	if class then
		playerTable[name].class = class
		playerTable[name].classColor = RAID_CLASS_COLORS[class:upper()]
		if playerBankDB[name] then
			playerBankDB[name].class = class:upper()
		end
	else
		playerTable[name].classColor = {
			r = 0.0, g = 1.0, b = 0.0
		}
	end
	if raidIndex then
		playerTable[name].raidIndex = raidIndex
	end
	playerTable[name].rankIndex = rankIndex or 1
	if playerBankDB[name] and playerBankDB[name].isDeleted then
		playerBankDB[name].isDeleted = false
	end
	return name
end

local function GetRaidPlayers()
	local raidPlayers = {}
	local subGroups = {}
	for group = 1, 8 do
		table.insert(subGroups, {})
	end
	for index = 1, 40 do
		-- setting fileName as class, since it should be language agnostic
		local name, _, subgroup, _, _, class = GetRaidRosterInfo(index)
		if name then
			name = strsplit("-", name)
			table.insert(subGroups[subgroup], name)
			raidPlayers[name] = {}
			raidPlayers[name].index = index
			raidPlayers[name].subgroup = subgroup
			raidPlayers[name].subgroupPosition = #subGroups[subgroup]
			raidPlayers[name].class = class
			AddToPlayerTable(name, class, index)
		end
	end
	return raidPlayers, subGroups
end

local function IsRaidAssistant(player)
	if not player then
		player = "player"
	end
	return UnitIsGroupLeader(player) == true or UnitIsGroupAssistant(player) == true
end

function cleangroupassigns:SelectArrangement(labelIndex)
	local errorMessage = "Invalid index. Use /cga list to show available arrangements."
	if not labelIndex then
		return errorMessage
	end

	local arrangementLabel = self.arrangements.arrangementLabels[labelIndex]
	if not arrangementLabel then
		return errorMessage
	end

	local arrangement = arrangementLabel.arrangement
	if not arrangement then
		return errorMessage
	end

	self:ClearAllLabels()
	for row = 1, 8 do
		for col = 1, 5 do
			local entry = arrangement[row][col]
			AddToPlayerTable(entry.name, entry.class)
			self:SetLabel(labels[row][col], entry.name)
		end
	end
	self:FillPlayerBank()
	return self:CheckArrangable()
end

function cleangroupassigns:PopulateArrangements()
	local labelIndex = 0
	local arrangementLabels = self.arrangements.arrangementLabels
	local populate = function(index)
		labelIndex = labelIndex + 1
		local arrangement = arrangementsDB[index]
		local label
		if arrangementLabels[labelIndex] then
			label = arrangementLabels[labelIndex]
			label.frame:EnableMouse(true)
		else
			label = AceGUI:Create("InteractiveLabel")
			label:SetFont(DEFAULT_FONT, 12, "")
			label:SetHighlight("Interface\\Buttons\\UI-Listbox-Highlight")
			label:SetFullWidth(true)
			label.OnClick = function()
				if GetMouseButtonClicked() == "LeftButton" then
					self:SelectArrangement(label.labelIndex)
				elseif GetMouseButtonClicked() == "RightButton" then
					self.arrangementsDrowndownMenu.clickedEntry = label.dbIndex
					self.arrangementsDrowndownMenu:Show()
				end
			end
			label:SetCallback("OnClick", label.OnClick)
			self.arrangements:AddChild(label)
			table.insert(arrangementLabels, label)
		end

		label.dbIndex = index
		label.labelIndex = labelIndex
		label.arrangement = arrangement
		label:SetText(arrangement.name)
	end

	-- sort by name, but prefer yourself first
	local arrangementKeys = {}
	for index, arrangement in ipairs(arrangementsDB) do
		if not arrangement.owner then
			arrangementKeys[arrangement.name] = index
		end
	end

	for _, index in pairsByKeys(arrangementKeys) do
		populate(index)
	end

	local arrangementKeys = {}
	for index, arrangement in ipairs(arrangementsDB) do
		if arrangement.owner then
			arrangementKeys[arrangement.name] = index
		end
	end

	for _, index in pairsByKeys(arrangementKeys) do
		populate(index)
	end

	while labelIndex < #arrangementLabels do
		labelIndex = labelIndex + 1
		arrangementLabels[labelIndex].arrangement = nil
		arrangementLabels[labelIndex]:SetText(nil)
		arrangementLabels[labelIndex].frame:EnableMouse(false)
	end

	self.arrangements:DoLayout()
end

function cleangroupassigns:AddArrangement(receivedArrangement)
	for index, arrangement in ipairs(arrangementsDB) do
		if arrangement.name == receivedArrangement.name then
			arrangementsDB[index] = receivedArrangement
			return
		end
	end
	table.insert(arrangementsDB, receivedArrangement)
end

function cleangroupassigns:IsInLabels(name)
	for row = 1, 8 do
		for col = 1, 5 do
			if labels[row][col].name == name then
				return true
			end
		end
	end
	return false
end

function cleangroupassigns:RearrangeGroup(row)
	local raidIndexKeyGroup = {}
	local nonIndexedPlayers = {}
	for col = 1, 5 do
		local label = labels[row][col]
		if label.name then
			if playerTable[label.name].raidIndex then
				raidIndexKeyGroup[playerTable[label.name].raidIndex] = label.name
			else
				table.insert(nonIndexedPlayers, label.name)
			end
		end
	end

	local col = 1
	for _, name in pairsByKeys(raidIndexKeyGroup) do
		--print("REAR1: " .. playerTable[name].raidIndex .. " " .. name)
		self:SetLabel(labels[row][col], name)
		col = col + 1
	end
	for _, name in ipairs(nonIndexedPlayers) do
		--print("REAR2: " .. (playerTable[name].raidIndex or "nil") .. " " .. name)
		self:SetLabel(labels[row][col], name)
		col = col + 1
	end
	for tail = col, 5 do
		self:ClearLabel(labels[row][tail])
	end

	self:CheckArrangable()
end

function cleangroupassigns:MovedToSubgroup(label, toRow, toCol)
	local sourceName = label.name
	local destinationName = labels[toRow][toCol].name
	--print(toRow .. "," .. toCol .. ": " .. sourceName .. " MOVED TO " .. (destinationName or "Empty"))
	self:SetLabel(labels[toRow][toCol], sourceName)
	self:RearrangeGroup(toRow)

	self:SetLabel(label, destinationName)
	self:RearrangeGroup(label.row)
end

function cleangroupassigns:MovedToPlayerBank(label)
	self:ClearLabel(label)
	self:RearrangeGroup(label.row)
	self:FillPlayerBank()
end

function cleangroupassigns:SetLabel(label, name)
	if name then
		label.name = name
		label:SetText(name)
		if playerTable[name] then
			if playerTable[name].classColor then
				local classColor = playerTable[name].classColor
				label.label:SetTextColor(classColor.r, classColor.g, classColor.b)
			end
			label.frame:EnableMouse(true)
			label.frame:SetMovable(true)
		end
	else
		self:ClearLabel(label)
	end
end

function cleangroupassigns:LabelFunctionality(label)
	local anchorPoint, parentFrame, relativeTo, ptX, ptY
	label.frame:RegisterForDrag("LeftButton")
	label.frame:SetScript("OnDragStart", function(self)
		anchorPoint, parentFrame, relativeTo, ptX, ptY = self:GetPoint()
		self:SetFrameStrata("TOOLTIP")
		self:StartMoving()
	end)
	label.frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetFrameStrata("FULLSCREEN_DIALOG")
		local x, y = GetXY()
		local left, top, width, height = cleangroupassigns.playerBank.frame:GetRect()
		if x >= left and x <= left + width and y >= top and y <= y + height then
			cleangroupassigns:MovedToPlayerBank(label)
		else
			local putToGroup = function()
				for iRow = 1, 8 do
					if label.row ~= iRow then
						for iCol = 1, 5 do
							local cLeft, cTop, cWidth, cHeight = labels[iRow][iCol].frame:GetRect()
							if x >= cLeft - 4
							and x <= cLeft + cWidth + 4
							and y >= cTop - 5
							and y <= cTop + cHeight + 5 then
								cleangroupassigns:MovedToSubgroup(label, iRow, iCol)
								return
							end
						end
					end
				end
			end
			putToGroup()
		end
		label:ClearAllPoints()
		label:SetPoint(anchorPoint, parentFrame, relativeTo, ptX, ptY)
	end)
	label:SetCallback("OnClick", function(self, _, button)
		if button == "RightButton" then
			cleangroupassigns:MovedToPlayerBank(self)
		end
	end)
end

function cleangroupassigns:ClearAllLabels()
	for row = 1, 8 do
		for col = 1, 5 do
			self:ClearLabel(labels[row][col])
		end
	end
end

function cleangroupassigns:ClearLabel(label)
	label.name = nil
	label:SetText("Empty")
	label.label:SetTextColor(0.35, 0.35, 0.35)
	label.frame:EnableMouse(false)
	label.frame:SetMovable(false)
end

function cleangroupassigns:FillCurrentRaid()
	self:ClearAllLabels()

	local raidPlayers = GetRaidPlayers()
	for name, player in pairs(raidPlayers) do
		local label = labels[player.subgroup][player.subgroupPosition]
		self:SetLabel(label, name)
	end

	self:FillPlayerBank()
	self:CheckArrangable()
end

function cleangroupassigns:GetFirstEmpty()
	for row = 1, 8 do
		for col = 1, 5 do
			if not labels[row][col].name then
				return row, col
			end
		end
	end
end

function cleangroupassigns:FillPlayerBank(newlyAddedName)
	if isDraggingLabel then
		shouldUpdatePlayerBank = true
		return
	end

	local guildRanks = { "All Ranks" }
	local shouldUpdate = false
	for i = 1, GuildControlGetNumRanks() do
		local rank = GuildControlGetRankName(i)
		if rank ~= self.filterRank.list[i + 1] then
			shouldUpdate = true
		end
		table.insert(guildRanks, rank)
	end

	if shouldUpdate then
		self.filterRank:SetList(guildRanks)
		self.filterRank:SetValue(cgaConfigDB.filterRank)
		self.filterRank.list = guildRanks
	end

	-- Grab >= level 58 from guild roster
	local numGuildMembers = GetNumGuildMembers()
	for i = 1, numGuildMembers do
		local name, _, rankIndex, level, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
		if name then
			name = strsplit("-", name)
			if level >= MIN_LEVEL then
				-- Don't add if is deleted
				if not playerBankDB[name] or not playerBankDB[name].isDeleted then
					AddToPlayerTable(name, class, nil, rankIndex + 1)
				end
			end
		end
	end

	for name, tbl in pairs(playerBankDB) do
		if not tbl.isDeleted then
			AddToPlayerTable(name, tbl.class)
		end
	end

	local playerTableNames = {}
	for name, _ in pairs(playerTable) do
		if not self:IsInLabels(name) then
			table.insert(playerTableNames, name)
		end
	end
	table.sort(playerTableNames)

	local raidPlayers = GetRaidPlayers()

	local index = 0
	local newlyAddedNameIndex
	local playerLabels = self.playerBank.scroll.playerLabels
	local filterText = self.playerBar:GetText()
	for _, name in ipairs(playerTableNames) do
		if (not filterText or string.find(name:upper(), filterText:upper())) and (not cgaConfigDB.filterCheck or raidPlayers[name]) and (cgaConfigDB.filterRank == 1 or (playerTable[name].rankIndex and cgaConfigDB.filterRank > playerTable[name].rankIndex)) then
			if name == newlyAddedName then
				newlyAddedNameIndex = index
			end
			index = index + 1
			local playerLabel
			if playerLabels[index] then
				playerLabel = playerLabels[index]
				playerLabel.frame:EnableMouse(true)
			else
				playerLabel = AceGUI:Create("InteractiveLabel")
				playerLabel:SetFont(DEFAULT_FONT, 12, "")
				playerLabel:SetHighlight("Interface\\BUTTONS\\UI-Listbox-Highlight.blp")
				playerLabel:SetFullWidth(true)
				playerLabel.lastClicked = 0
				local tmpIndex = index
				playerLabel:SetCallback("OnClick", function(self)
					if GetMouseButtonClicked() == "LeftButton" then
						if GetTime() - self.lastClicked < 0.5 then
							local row, col = cleangroupassigns:GetFirstEmpty()
							if row and col then
								cleangroupassigns:SetLabel(labels[row][col], self.name)
								cleangroupassigns:RearrangeGroup(row)
								cleangroupassigns:FillPlayerBank()
							end
						end
						self.lastClicked = GetTime()
					elseif GetMouseButtonClicked() == "RightButton" then
						cleangroupassigns.playerBank.dropdownMenu.clickedEntry = tmpIndex
						cleangroupassigns.playerBank.dropdownMenu:Show()
					end
				end)

				local anchorPoint, parentFrame, relativeTo, ptX, ptY
				playerLabel.frame:EnableMouse(true)
				playerLabel.frame:SetMovable(true)
				playerLabel.frame:RegisterForDrag("LeftButton")
				playerLabel.frame:SetScript("OnDragStart", function(self)
					isDraggingLabel = true
					for row = 1, 8 do
						for col = 1, 5 do
							local label = labels[row][col]
							local left, top, width, height = label.frame:GetRect()
							label.savedRect = {}
							label.savedRect.left = left
							label.savedRect.top = top
							label.savedRect.width = width
							label.savedRect.height = height
						end
					end
					anchorPoint, parentFrame, relativeTo, ptX, ptY = self:GetPoint()
					self:SetParent(UIParent)
					self:SetFrameStrata("TOOLTIP")
					self:StartMoving()
				end)

				playerLabel.frame:SetScript("OnDragStop", function(self)
					self:StopMovingOrSizing()
					local x, y = GetXY()
					local putToGroup = function()
						for row = 1, 8 do
							for col = 1, 5 do
								local label = labels[row][col]
								if x >= label.savedRect.left - 4
								and x <= label.savedRect.left + label.savedRect.width + 4
								and y >= label.savedRect.top - 5
								and y <= label.savedRect.top + label.savedRect.height + 5 then
									cleangroupassigns:SetLabel(label, playerLabel.name)
									cleangroupassigns:RearrangeGroup(row)
									return true
								end
							end
						end
						return false
					end

					self:SetParent(parentFrame)
					playerLabel:ClearAllPoints()
					playerLabel:SetPoint(anchorPoint, parentFrame, relativeTo, ptX, ptY)
					playerLabel.frame:SetFrameStrata("TOOLTIP")
					isDraggingLabel = false
					if putToGroup() or shouldUpdatePlayerBank then
						shouldUpdatePlayerBank = false
						cleangroupassigns:FillPlayerBank()
					end
				end)

				self.playerBank.scroll:AddChild(playerLabel)
				table.insert(playerLabels, playerLabel)
			end

			playerLabel.name = name
			playerLabel:SetText(name)
			local classColor = playerTable[name].classColor
			playerLabel.label:SetTextColor(classColor.r, classColor.g, classColor.b)
		end
	end

	while index < #playerLabels do
		index = index + 1
		playerLabels[index].name = nil
		playerLabels[index]:SetText(nil)
		playerLabels[index].frame:EnableMouse(false)
	end

	if newlyAddedNameIndex then
		self.playerBank.scroll:SetScroll(newlyAddedNameIndex / (#playerTableNames - 1) * 1000)
	end
	self.playerBank.scroll:DoLayout()
end

function cleangroupassigns:InviteRosterToRaid()
	if self.inviteToRaid.inviteState == 0 then
		return
	end

	if IsInGroup() and not IsInRaid() then
		ConvertToRaid()
		return
	end

	local onlinePlayers = {}
	local numGuildMembers = GetNumGuildMembers()
	for i = 1, numGuildMembers do
		local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
		if name then
			name = strsplit("-", name)
			onlinePlayers[name] = online
		end
	end

	local playersToInvite = {}
	for row = 1, 8 do
		for col = 1, 5 do
			local name = labels[row][col].name
			if name and onlinePlayers[name] ~= false and not self.inviteToRaid.pendingInvites[name] and not UnitInRaid(name) and not UnitInParty(name) and name ~= UnitName("player") then
				playersToInvite[name] = true
			end
		end
	end

	if IsInRaid() then
		for name, _ in pairs(playersToInvite) do
			InviteUnit(name)
		end
		self.inviteToRaid.inviteState = 0
		self.inviteToRaid.pendingInvites = {}
	else
		-- Invite up to four people, then convert to raid once one joins
		local numInvited = 0
		for name, _ in pairs(playersToInvite) do
			InviteUnit(name)
			self.inviteToRaid.pendingInvites[name] = true
			numInvited = numInvited + 1
			if numInvited >= 4 then
				break
			end
		end
	end
end

function cleangroupassigns:DoSwap()
	if swapCounter > 40 then
		print("|cFFFF0000ERROR: Something went wrong, we are still stuck rearranging after 40 swaps. Terminating...|r")
		self:StopSwap()
		return
	end

	local errorMessage = self:CheckArrangable()
	if errorMessage then
		print("|cFFFF0000ERROR: " .. errorMessage .. "|r")
		self:StopSwap()
		return
	end

	self:SetUnarrangable("REARRANGING...")
	self:SendInProgress()

	local raidPlayers, subGroups = GetRaidPlayers()
	for row = 1, 8 do
		for col = 1, 5 do
			local targetName = labels[row][col].name
			if targetName and raidPlayers[targetName] and raidPlayers[targetName].subgroup ~= row then
				if #subGroups[row] == 5 then
					-- which name is not supposed to be in this subgroup?
					local nameToSwap
					for gCol = 1, 5 do
						local isSupposedToBe = false
						for hCol = 1, 5 do
							if labels[row][hCol].name == subGroups[row][gCol] then
								isSupposedToBe = true
								break
							end
						end
						if not isSupposedToBe then
							nameToSwap = subGroups[row][gCol]
							break
						end
					end

					--print("SwapRaidSubgroup(" .. targetName .. ", " .. (nameToSwap or "nil") .. ") " .. #subGroups[row])
					SwapRaidSubgroup(raidPlayers[targetName].index, raidPlayers[nameToSwap].index)
				else
					--print("SetRaidSubgroup(" .. targetName .. ", " .. row .. ") " .. #subGroups[row])
					SetRaidSubgroup(raidPlayers[targetName].index, row)
				end
				swapCounter = swapCounter + 1
				return
			end
		end
	end
	self:StopSwap()
end

function cleangroupassigns:StopSwap()
	inSwap = false
	swapCounter = 0
	self:SendEndProgress()
	for row = 1, 8 do
		self:RearrangeGroup(row)
	end
	if shouldPrint then
		print("DONE!")
		shouldPrint = false
	end
end

function cleangroupassigns:OnRosterUpdate()
	if remoteInSwap then
		return
	end

	if self.inviteToRaid.inviteState > 0 then
		self:InviteRosterToRaid()
		return
	end

	if inSwap then
		self:DoSwap()
	else
		self:CheckArrangable()
	end
end

function cleangroupassigns:CheckArrangable(enteredCombat)
	local rearrangeRaidText = "REARRANGE RAID"
	local canInviteToRaid
	for row = 1, 8 do
		for col = 1, 5 do
			local name = labels[row][col].name
			if name and not UnitInParty(name) and not UnitInRaid(name) and name ~= UnitName("player") then
				canInviteToRaid = true
				break
			end
		end
		if canInviteToRaid then
			self.inviteToRaid:SetDisabled(false)
			self.inviteToRaid.frame:EnableMouse(true)
			self.inviteToRaid.text:SetTextColor(self.inviteToRaid.textColor.r, self.inviteToRaid.textColor.g, self.inviteToRaid.textColor.b)
			break
		end
	end
	if not canInviteToRaid then
		self.inviteToRaid:SetDisabled(true)
		self.inviteToRaid.frame:EnableMouse(false)
		self.inviteToRaid.text:SetTextColor(0.35, 0.35, 0.35)
	end

	local errorMessage
	if not IsInRaid() then
		self.fetchArrangements:SetDisabled(true)
		self.fetchArrangements.frame:EnableMouse(false)
		self.fetchArrangements.text:SetTextColor(0.35, 0.35, 0.35)
		self.filterCheck:SetDisabled(true)
		if self.filterCheck:GetValue() then
			cgaConfigDB.filterCheck = false
			self.filterCheck:SetValue(false)
			self:FillPlayerBank()
		end
		errorMessage = "CANNOT REARRANGE - NOT IN A RAID GROUP"
		self:SetUnarrangable(errorMessage)
		return errorMessage
	end

	self.filterCheck:SetDisabled(false)
	self.fetchArrangements:SetDisabled(false)
	self.fetchArrangements.frame:EnableMouse(true)
	self.fetchArrangements.text:SetTextColor(self.fetchArrangements.textColor.r, self.fetchArrangements.textColor.g, self.fetchArrangements.textColor.b)
	self.currentRaid.text:SetTextColor(self.currentRaid.textColor.r, self.currentRaid.textColor.g, self.currentRaid.textColor.b)

	local duplicatePlayers = {}
	for row = 1, 8 do
		for col = 1, 5 do
			local name = labels[row][col].name
			if name then
				if duplicatePlayers[name] then
					errorMessage = "CANNOT REARRANGE - " .. name .. " IS IN THE ROSTER TWICE"
					self:SetUnarrangable(errorMessage)
					return errorMessage
				end
				duplicatePlayers[name] = true
			end
		end
	end

	local raidPlayers = GetRaidPlayers()
	local labelPlayers = {}
	for row = 1, 8 do
		for col = 1, 5 do
			local name = labels[row][col].name
			if name then
				if not raidPlayers[name] then
					if rearrangeRaidText == "REARRANGE RAID" then
						rearrangeRaidText = "REARRANGE RAID (" .. name .. " IS NOT IN THE RAID)"
					end
					labels[row][col].label:SetTextColor(RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
				end
				labelPlayers[name] = true
			end
		end
	end

	for name, _ in pairs(raidPlayers) do
		if not labelPlayers[name] then
			rearrangeRaidText = "REARRANGE RAID (" .. name .. " IS NOT IN THE SETUP)"
			break
		end
	end

	if not IsRaidAssistant() then
		errorMessage = "CANNOT REARRANGE - NOT A RAID LEADER OR ASSISTANT"
		self:SetUnarrangable(errorMessage)
		return errorMessage
	end

	if enteredCombat or InCombatLockdown() then
		errorMessage = "CANNOT REARRANGE - IN COMBAT"
		self:SetUnarrangable(errorMessage)
		return errorMessage
	end

	self.rearrangeRaid:SetText(rearrangeRaidText)
	self.rearrangeRaid:SetDisabled(false)
	self.rearrangeRaid.frame:EnableMouse(true)
	self.rearrangeRaid.text:SetTextColor(self.rearrangeRaid.textColor.r, self.rearrangeRaid.textColor.g, self.rearrangeRaid.textColor.b)
end

function cleangroupassigns:SetUnarrangable(text)
	self.rearrangeRaid:SetText(text)
	self.rearrangeRaid:SetDisabled(true)
	self.rearrangeRaid.frame:EnableMouse(false)
	self.rearrangeRaid.text:SetTextColor(0.35, 0.35, 0.35)
end

function cleangroupassigns:RearrangeRaid()
	inSwap = true
	swapCounter = 0
	self:DoSwap()
end

function cleangroupassigns:ImportArrangement(importDialog, name, text)
	if name == "" then
		importDialog:SetStatusText("Choose a roster name!")
		return
	end
	if text == "" then
		importDialog:SetStatusText("Paste players into the roster!")
		return
	end

	local group = 1
	local slot = 1
	local importPlayers = {}
	local newRoster = {}
	newRoster.name = name

	--[[First try to parse the roster as it will be displayed in the main frame like
		G1: p1 G2: p6
			p2     p7
			p3     p8
			p4     p9
			p5     p10

		If the pasted content does not match the above, fall back to importing player 1 - 40 via the usage of any separator
	]]

	local isGroupOrderedImport = true
	for line in string.gmatch(text .. "\n", "(.-)\n") do
		local trimmedLine = string.gsub(strtrim(line, " ,\t\r"), " +", " ")
		if trimmedLine ~= "" then
			local importedPlayers = 0
			for _, player in ipairs({ strsplit(" ,\t", trimmedLine) }) do
				if player ~= "" then
					table.insert(importPlayers, player)
					importedPlayers = importedPlayers + 1
				end
			end
			if importedPlayers > 2 then
				isGroupOrderedImport = false
			end
		end
	end

	for row = 1, 8 do
		newRoster[row] = {}
		for col = 1, 5 do
			newRoster[row][col] = {}
			local playerName
			if isGroupOrderedImport then
				playerName = importPlayers[math.floor((row - 1) / 2) * 10 + (col * 2 - (row % 2))]
			else
				playerName = importPlayers[(row - 1) * 5 + col]
			end
			if playerName and playerName ~= "" then
				local cLen = charLength(playerName)
				playerName = string.sub(playerName, 1, cLen):upper() .. string.sub(playerName, cLen + 1):lower()

				newRoster[row][col].name = playerName
				AddToPlayerTable(playerName)
			end
		end
	end

	local found = false
	for index, arrangement in ipairs(arrangementsDB) do
		if arrangement.name:upper() == newRoster.name:upper() then
			arrangementsDB[index] = newRoster
			found = true
			break
		end
	end
	if not found then
		table.insert(arrangementsDB, newRoster)
	end
end

function cleangroupassigns:SendInProgress()
	local message = {
		key = "SWAP_IN_PROGRESS",
	}
	self:SendComm(message)
end

function cleangroupassigns:SendEndProgress()
	local message = {
		key = "SWAP_END",
	}
	self:SendComm(message)
end

function cleangroupassigns:AskForArrangements()
	local message = {
		key = "ASK_ARRANGEMENTS",
	}
	self:SendComm(message)
end

function cleangroupassigns:SendComm(message)
	local messageSerialized = LD:EncodeForWoWAddonChannel(LD:CompressDeflate(self:Serialize(message)))
	self:SendCommMessage("cgassigns", messageSerialized, "RAID")
end

function cleangroupassigns:OnCommReceived(prefix, message, distribution, sender)
	if prefix ~= "cgassigns" or sender == UnitName("player") or not message then
		return
	end

	local decoded = LD:DecodeForWoWAddonChannel(message)
	if not decoded then
		print("Could not decode addon message. Sender needs to update to the latest version of cleangroupassigns!")
		return
	end
	local decompressed = LD:DecompressDeflate(decoded)
	if not decompressed then
		print("Failed to decompress addon message. Sender needs to update to the latest version of cleangroupassigns!")
		return
	end

	local didDeserialize, message = self:Deserialize(decompressed)
	if not didDeserialize then
		print("Failed to deserialize sync: " .. message)
		return
	end

	local key = message["key"]
	if not key then
		print("Failed to parse deserialized comm.")
		return
	end

	if key == "SWAP_IN_PROGRESS" then
		remoteInSwap = true
		self:SetUnarrangable("REARRANGEMENT IN PROGRESS BY " .. sender)
		return
	end

	if key == "SWAP_END" then
		remoteInSwap = false
		self:CheckArrangable()
		return
	end

	if key == "ASK_ARRANGEMENTS" then
		local filteredArrangements = {}
		for i, arrangement in ipairs(arrangementsDB) do
			if not arrangement.owner then
				table.insert(filteredArrangements, arrangement)
			end
		end
		local response = {
			key = "ARRANGEMENTS",
			asker = sender,
			value = filteredArrangements,
		}
		self:SendComm(response)
		return
	end

	if key == "ARRANGEMENTS" and message["asker"] == UnitName("player") and message["value"] then
		for _, arrangement in ipairs(message["value"]) do
			arrangement.owner = sender
			arrangement.name = sender .. "-" .. arrangement.name
			self:AddArrangement(arrangement)
		end
		self:PopulateArrangements()
		return
	end
end

function cleangroupassigns:OnEnable()
	if not cgaConfigDB.welcome then
		print("Welcome to cleangroupassigns. Use the minimap button or /cga show to open.")
		cgaConfigDB.welcome = true
	end
	self.f = AceGUI:Create("Window")
	self.f:Hide()
	self.f:EnableResize(false)
	self.f:SetTitle("<clean> group assignments")
	self.f:SetLayout("Flow")
	_G["cleangroupassignsFrame"] = self.f.frame
	table.insert(UISpecialFrames, "cleangroupassignsFrame")

	local iconDataBroker = LibStub("LibDataBroker-1.1"):NewDataObject("cleangroupassignsMinimapIcon", {
		type = "data source",
		text = "clean group assigns",
		label = "clean group assigns",
		icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
		OnClick = function()
			if self.f:IsVisible() then
				self.f:Hide()
			else
				self.f:Show()
			end
		end,
	    OnTooltipShow = function(tooltip)
			tooltip:SetText("|cFFFF7D0Aclean group assigns|r\n|cFFFF7D0A/cga list|r|cFF24A8FF: Print current arrangements|r\n|cFFFF7D0A/cga go [index]|r|cFF24A8FF: Sort raid group|r")
			tooltip:Show()
		end,
	})
	local minimapIcon = LibStub("LibDBIcon-1.0")
	minimapIcon:Register("cleangroupassignsMinimapIcon", iconDataBroker, minimapButtonDB)
	minimapIcon:Show()

	self.raidViews = AceGUI:Create("InlineGroup")
	self.raidViews:SetWidth(200)
	self.raidViews:SetTitle("Raid Arrangements")
	self.raidViews:SetLayout("Fill")

	self.fetchArrangements = AceGUI:Create("Button")
	self.fetchArrangements:SetWidth(self.raidViews.frame:GetWidth())
	self.fetchArrangements:SetText("Fetch Arrangements")
	self.fetchArrangements:SetCallback("OnClick", function() self:AskForArrangements() end)
	local r, g, b = self.fetchArrangements.text:GetTextColor()
	self.fetchArrangements.textColor = {}
	self.fetchArrangements.textColor.r = r
	self.fetchArrangements.textColor.g = g
	self.fetchArrangements.textColor.b = b

	self.arrangementsDrowndownMenu = _G["cleangroupassignsDropdownMenu"]:New()
	self.arrangementsDrowndownMenu:AddItem("Delete", function()
		table.remove(arrangementsDB, self.arrangementsDrowndownMenu.clickedEntry)
		self:PopulateArrangements()
	end)
	self.arrangements = AceGUI:Create("ScrollFrame")
	self.arrangements:SetLayout("Flow")
	self.arrangements.arrangementLabels = {}
	self.raidViews:AddChild(self.arrangements)

	self.playerBank = AceGUI:Create("InlineGroup")
	self.playerBank:SetWidth(200)
	self.playerBank:SetTitle("Player Bank")
	self.playerBank:SetLayout("Fill")
	self.playerBank.scroll = AceGUI:Create("ScrollFrame")
	self.playerBank.scroll:SetLayout("Flow")
	self.playerBank.scroll.playerLabels = {}
	self.playerBank:AddChild(self.playerBank.scroll)
	self.playerBank.dropdownMenu = _G["cleangroupassignsDropdownMenu"]:New()
	self.playerBank.dropdownMenu:AddItem("Delete", function()
		PlayerMarkDeleted(self.playerBank.scroll.playerLabels[self.playerBank.dropdownMenu.clickedEntry].name)
		self:FillPlayerBank()
	end)

	self.playerBar = AceGUI:Create("EditBox")
	self.playerBar:SetMaxLetters(12)
	self.playerBar:SetWidth(self.playerBank.frame:GetWidth())
	self.playerBar:SetLabel("Search/Add Player")
	self.playerBar.button:SetText("Add")
	self.playerBar:SetCallback("OnTextChanged", function(self, _, value)
		self:DisableButton(value == "")
		cleangroupassigns:FillPlayerBank()
		cleangroupassigns.playerBank.scroll:SetScroll(0)
	end)
	self.playerBar:SetCallback("OnEnterPressed", function(self, _, value)
		self:SetText("")
		local name = AddToPlayerTable(value)
		cleangroupassigns:FillPlayerBank(name)
	end)

	self.filterRank = AceGUI:Create("Dropdown")
	self.filterRank:SetWidth(self.playerBar.frame:GetWidth())
	self.filterRank:SetLabel("Rank filter")
	self.filterRank.list = {}
	if not cgaConfigDB.filterRank then
		cgaConfigDB.filterRank = 1
	end
	self.filterRank:SetCallback("OnValueChanged", function(_, _, value)
		cgaConfigDB.filterRank = value
		self:FillPlayerBank()
	end)

	self.filterCheck = AceGUI:Create("CheckBox")
	self.filterCheck:SetWidth(self.playerBank.frame:GetWidth())
	self.filterCheck:SetValue(cgaConfigDB.filterCheck)
	self.filterCheck:SetLabel("Show Only Players In Raid")
	self.filterCheck:SetCallback("OnValueChanged", function(_, _, value)
		cgaConfigDB.filterCheck = value
		self:FillPlayerBank()
	end)

	local raidGroups = {}
	for row = 1, 8 do
		local raidGroup = AceGUI:Create("InlineGroup")
		raidGroup:SetWidth(160)
		raidGroup:SetTitle("Group " .. row)
		raidGroup.titletext:SetJustifyH("CENTER")
		labels[row] = {}
		for col = 1, 5 do
			labels[row][col] = AceGUI:Create("InteractiveLabel")
			local label = labels[row][col]
			label:SetFont(DEFAULT_FONT, 12, "")
			label:SetJustifyH("CENTER")
			label.row = row
			label.col = col
			label:SetWidth(161)
			label:SetHeight(20)
			label:SetText("Empty")
			label.label:SetTextColor(0.35, 0.35, 0.35)
			self:LabelFunctionality(label)
			raidGroup:AddChild(label)
		end
		AceGUI:RegisterLayout("RaidGroupLayout" .. row, function()
			for col = 1, 5 do
				local label = labels[row][col]
				label:ClearAllPoints()
				label:SetPoint("TOPLEFT", raidGroup.frame, "TOPLEFT", 0, -1 * ((col - 1) * label.frame:GetHeight() + raidGroup.titletext:GetHeight() + 5 * (col - 1) + 4))
			end
			raidGroup:SetHeight(labels[row][1].frame:GetHeight() * 5 + raidGroup.titletext:GetHeight() + 34)
		end)
		raidGroup:SetLayout("RaidGroupLayout" .. row)
		raidGroup:DoLayout()
		self.raidViews:AddChild(raidGroup)
		table.insert(raidGroups, raidGroup)
	end

	self.currentRaid = AceGUI:Create("Button")
	self.currentRaid:SetText("Copy Current Raid")
	self.currentRaid:SetCallback("OnClick", function() self:FillCurrentRaid() end)
	local r, g, b = self.currentRaid.text:GetTextColor()
	self.currentRaid.textColor = {}
	self.currentRaid.textColor.r = r
	self.currentRaid.textColor.g = g
	self.currentRaid.textColor.b = b

	local saveRaid = AceGUI:Create("Button")
	saveRaid:SetText("Save Arrangement")

	local inEditingState = false
	saveRaid:SetCallback("OnClick", function()
		if inEditingState then
			return
		end
		local editBox
		if self.raidViews.editBox then
			editBox = self.raidViews.editBox
			editBox.frame:Show()
		else
			editBox = AceGUI:Create("EditBox")
			editBox:SetLabel("Name")
			editBox:SetFocus()
			editBox:SetCallback("OnEnterPressed", function()
				local newEntry = {}
				newEntry.name = editBox:GetText()
				if newEntry.name and newEntry.name ~= "" then
					for row = 1, 8 do
						newEntry[row] = {}
						for col = 1, 5 do
							newEntry[row][col] = {}
							local playerName = labels[row][col].name
							if playerName then
								newEntry[row][col].name = playerName
								newEntry[row][col].class = playerTable[playerName].class
							end
						end
					end
					local found = false
					for index, arrangement in ipairs(arrangementsDB) do
						if arrangement.name:upper() == newEntry.name:upper() then
							arrangementsDB[index] = newEntry
							found = true
							break
						end
					end
					if not found then
						table.insert(arrangementsDB, newEntry)
					end
				end
				inEditingState = false
				editBox.frame:Hide()
				self:PopulateArrangements()
			end)
			local arrangementLabels = self.arrangements.arrangementLabels
			if #arrangementLabels > 0 then
				editBox:SetPoint("TOPLEFT", arrangementLabels[#arrangementLabels].frame, "BOTTOMLEFT", 0, -2)
			else
				editBox:SetPoint("TOPLEFT", self.arrangements.frame, "TOPLEFT", 0, -2)
			end
			editBox:SetWidth(self.arrangements.frame:GetWidth())
			self.raidViews:AddChild(editBox)
		end
		inEditingState = true
	end)

	self.inviteToRaid = AceGUI:Create("Button")
	self.inviteToRaid.inviteState = 0
	self.inviteToRaid.pendingInvites = {}
	self.inviteToRaid:SetText("Invite Roster To Raid")
	self.inviteToRaid.textColor = {}
	self.inviteToRaid.textColor.r = r
	self.inviteToRaid.textColor.g = g
	self.inviteToRaid.textColor.b = b
	self.inviteToRaid:SetDisabled(true)
	self.inviteToRaid.frame:EnableMouse(false)
	self.inviteToRaid.text:SetTextColor(0.35, 0.35, 0.35)
	self.inviteToRaid:SetCallback("OnClick", function()
		self.inviteToRaid.inviteState = 1
		self:InviteRosterToRaid()
	end)

	self.importRaid = AceGUI:Create("Button")
	self.importRaid:SetText("Import Roster")
	self.importRaid.textColor = {}
	self.importRaid.textColor.r = r
	self.importRaid.textColor.g = g
	self.importRaid.textColor.b = b
	self.importRaid:SetCallback("OnClick", function()
		if self.importDialog and self.importDialog:IsVisible() then
			self.importDialog:Show()
			return
		end
		self.importDialog = AceGUI:Create("Frame")
		self.importDialog:SetWidth(450)
		self.importDialog:SetHeight(400)
		self.importDialog:SetPoint("CENTER", self.f.frame)
		self.importDialog:SetTitle("Import Roster")
		self.importDialog:SetCallback("OnClose", function(widget)
			AceGUI:Release(widget)
			self.importDialog = nil
		end)
		self.importDialog.frame:SetFrameStrata("TOOLTIP")
		self.importDialog:SetLayout("List")
		_G["cleangroupassignsImportArrangementDialog"] = self.importDialog.frame
		table.insert(UISpecialFrames, "cleangroupassignsImportArrangementDialog")

		local rosterNameLabel = AceGUI:Create("EditBox")
		rosterNameLabel:SetLabel("Roster Name:")
		rosterNameLabel:SetFullWidth(true)
		rosterNameLabel:DisableButton(true)
		self.importDialog:AddChild(rosterNameLabel)

		local importedRoster = AceGUI:Create("MultiLineEditBox")
		importedRoster:SetLabel("Player List:")
		importedRoster:SetFullWidth(true)
		importedRoster:DisableButton(true)
		self.importDialog:AddChild(importedRoster)

		rosterNameLabel:SetCallback("OnEnterPressed", function()
			importedRoster:SetFocus()
		end)
		rosterNameLabel.editbox:SetScript("OnTabPressed", function() -- AceGUI does not support OnTabPressed callback
			importedRoster:SetFocus()
		end)

		local buttonImport = AceGUI:Create("Button")
		buttonImport:SetText("Import")
		buttonImport:SetWidth(200)
		buttonImport:SetCallback("OnClick", function()
			self:ImportArrangement(self.importDialog, rosterNameLabel:GetText(), importedRoster:GetText())
			self:PopulateArrangements()
			AceGUI:Release(self.importDialog)
			self.importDialog = nil
		end)

		AceGUI:RegisterLayout("ImportArrangementLayout", function()
			if self.importDialog.frame:GetWidth() < 450 then
				self.importDialog:SetWidth(450)
			end
			if self.importDialog.frame:GetHeight() < 400 then
				self.importDialog:SetHeight(400)
			end
			rosterNameLabel:SetHeight(42)
			importedRoster:SetHeight(270)
		end)

		self.importDialog:AddChild(buttonImport)
		self.importDialog:SetLayout("ImportArrangementLayout")
		self.importDialog:DoLayout()
	end)

	self.rearrangeRaid = AceGUI:Create("Button")
	self.rearrangeRaid:SetText("REARRANGE RAID")
	self.rearrangeRaid.textColor = {}
	self.rearrangeRaid.textColor.r = r
	self.rearrangeRaid.textColor.g = g
	self.rearrangeRaid.textColor.b = b
	self.rearrangeRaid:SetCallback("OnClick", function() self:RearrangeRaid() end)

	AceGUI:RegisterLayout("MainLayout", function()
		self.raidViews:SetPoint("TOPLEFT", self.f.frame, "TOPLEFT", 10, -28)
		self.fetchArrangements:SetPoint("TOPLEFT", self.raidViews.frame, "BOTTOMLEFT", 0, -14)
		self.playerBar:SetHeight(42)
		self.playerBank:SetPoint("TOPLEFT", self.raidViews.frame, "TOPRIGHT", 2, 0)
		self.playerBank:SetHeight(self.raidViews.frame:GetHeight())
		self.playerBar:SetPoint("TOPLEFT", self.fetchArrangements.frame, "TOPRIGHT", 2, 19)
		self.filterRank:SetPoint("TOPLEFT", self.playerBar.frame, "BOTTOMLEFT", 0, -2)
		self.filterCheck:SetPoint("TOPLEFT", self.filterRank.frame, "BOTTOMLEFT", 0, -2)

		self.f:SetWidth(744)
		self.f:SetHeight(590)
		raidGroups[1]:SetPoint("TOPLEFT", self.playerBank.frame, "TOPRIGHT", 2, 0)
		raidGroups[2]:SetPoint("TOPLEFT", raidGroups[1].frame, "TOPRIGHT", 2, 0)
		raidGroups[3]:SetPoint("TOPLEFT", raidGroups[1].frame, "BOTTOMLEFT", 0, 0)
		raidGroups[4]:SetPoint("TOPLEFT", raidGroups[3].frame, "TOPRIGHT", 2, 0)
		raidGroups[5]:SetPoint("TOPLEFT", raidGroups[3].frame, "BOTTOMLEFT", 0, 0)
		raidGroups[6]:SetPoint("TOPLEFT", raidGroups[5].frame, "TOPRIGHT", 2, 0)
		raidGroups[7]:SetPoint("TOPLEFT", raidGroups[5].frame, "BOTTOMLEFT", 0, 0)
		raidGroups[8]:SetPoint("TOPLEFT", raidGroups[7].frame, "TOPRIGHT", 2, 0)

		self.currentRaid:SetPoint("TOPLEFT", raidGroups[7].frame, "BOTTOMLEFT", 0, -14)
		self.currentRaid:SetWidth(raidGroups[7].frame:GetWidth())
		saveRaid:SetPoint("TOPLEFT", raidGroups[8].frame, "BOTTOMLEFT", 0, -14)
		saveRaid:SetWidth(raidGroups[8].frame:GetWidth())

		self.inviteToRaid:SetPoint("TOPLEFT", self.currentRaid.frame, "BOTTOMLEFT", 0, -2)
		self.inviteToRaid:SetWidth(self.currentRaid.frame:GetWidth())

		self.importRaid:SetPoint("TOPLEFT", raidGroups[8].frame, "BOTTOMLEFT", 0, -40)
		self.importRaid:SetWidth(raidGroups[8].frame:GetWidth())

		self.rearrangeRaid:SetPoint("TOPLEFT", self.inviteToRaid.frame, "BOTTOMLEFT", 0, -2)
		self.rearrangeRaid:SetWidth(self.currentRaid.frame:GetWidth() * 2 + 2)

		self.raidViews:SetHeight(raidGroups[1].frame:GetHeight() * 4)
		self.playerBank:SetHeight(self.raidViews.frame:GetHeight())
	end)

	self:PopulateArrangements()
	self.f:AddChild(self.raidViews)
	self.f:AddChild(self.fetchArrangements)
	self.f:AddChild(self.playerBar)
	self.f:AddChild(self.playerBank)
	self.f:AddChild(self.filterRank)
	self.f:AddChild(self.filterCheck)
	self.f:AddChild(self.currentRaid)
	self.f:AddChild(saveRaid)
	self.f:AddChild(self.inviteToRaid)
	self.f:AddChild(self.importRaid)
	self.f:AddChild(self.rearrangeRaid)

	self.f:SetLayout("MainLayout")
	self.f:DoLayout()

	self:OnRosterUpdate()
	self:HookScript(self.f.frame, "OnShow", function() self:FillCurrentRaid() end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function() self:OnRosterUpdate() end)
	self:RegisterEvent("GUILD_ROSTER_UPDATE", function() self:FillPlayerBank() end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() self:CheckArrangable(true) end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() self:CheckArrangable(false) end)
	local tlen = 0
	self:RegisterEvent("CHAT_MSG_ADDON", function(event, prefix, text, channel, sender, target)
		--if prefix == "cgassigns" then
			--tlen = tlen + string.len(text)
			--print(event .. "," .. prefix .. "," .. sender .. "," .. string.len(text))
		--end
	end)
	self:RegisterComm("cgassigns")
end


-- Slash Commands Functions
local SLASH_CMD_FUNCTIONS = {
	["GO"] = function(args)
		local labelIndex = tonumber(args)
		local errorMessage = cleangroupassigns:SelectArrangement(labelIndex)
		if errorMessage then
			print(errorMessage)
		else
			if inSwap then
				print("Wait for current rearrangement to complete.")
			else
				shouldPrint = true
				print("REARRANGING...")
				cleangroupassigns:RearrangeRaid()
			end
		end
	end,
	["LIST"] = function(args)
		local arrangementLabels = cleangroupassigns.arrangements.arrangementLabels
		local atLeastOne = false
		if #arrangementLabels > 0 then
			for index, arrangementLabel in ipairs(arrangementLabels) do
				if not arrangementLabel.arrangement then
					if not atLeastOne then
						print("You have no arrangements to list!")
					end
					break
				end
				atLeastOne = true
				print(index .. ": " .. arrangementLabel.arrangement.name)
			end
		else
			print("You have no arrangements to list!")
		end
	end,
	["HELP"] = function(args)
		print("Use /cga list to show arrangements or /cga go [index] to sort the raid.")
	end,
	["HIDE"] = function(args)
		cleangroupassigns.f:Hide()
	end,
	["SHOW"] = function(args)
		cleangroupassigns.f:Show()
	end,
}

SLASH_CGA1 = "/cleangroupassignments"
SLASH_CGA2 = "/cleangroupassigns"
SLASH_CGA3 = "/cga"
SlashCmdList["CGA"] = function(message)
	local _, _, cmd, args = string.find(message:upper(), "%s?(%w+)%s?(.*)")
	if not SLASH_CMD_FUNCTIONS[cmd] then
		cmd = "HELP"
	end
	SLASH_CMD_FUNCTIONS[cmd](args)
end
