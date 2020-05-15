--[[
World of Warcraft Classic Addon to automatically sort your raid based on your preset arrangements.
Author: Munchkin-Fairbanks <clean>
https://github.com/fjaros/cleangroupassigns
]]

cgaConfigDB = {
	welcome = false,
	filterCheck = false,
}
minimapButtonDB = {
	hide = false,
}
arrangementsDB = {}

local cleangroupassigns = LibStub("AceAddon-3.0"):NewAddon("cleangroupassigns", "AceComm-3.0", "AceEvent-3.0", "AceHook-3.0", "AceSerializer-3.0")
local libCompress = LibStub("LibCompress")
local libCompressET = libCompress:GetAddonEncodeTable()
local AceGUI = LibStub("AceGUI-3.0")

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

local function strSplit(str, sep)
   local sep, fields = sep, {}
   local pattern = string.format("([^%s]+)", sep)
   str:gsub(pattern, function(c) fields[#fields + 1] = c end)
   return fields
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

local function AddToPlayerTable(name, class, raidIndex)
	if not name then
		return
	end

	if not playerTable[name] then
		playerTable[name] = {}
	end
	playerTable[name].class = class
	playerTable[name].classColor = RAID_CLASS_COLORS[class:upper()]
	if raidIndex then
		playerTable[name].raidIndex = raidIndex
	end
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
			name = strSplit(name, "-")[1]
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
			label:SetFont("Fonts\\FRIZQT__.ttf", 12)
			label:SetHighlight("Interface\\Buttons\\UI-Listbox-Highlight")
			label:SetFullWidth(true)
			label.OnClick = function()
				if GetMouseButtonClicked() == "LeftButton" then
					self:SelectArrangement(label.labelIndex)
				elseif GetMouseButtonClicked() == "RightButton" then
					cleangroupassigns.arrangementsDrowndownMenu.clickedEntry = label.dbIndex
					cleangroupassigns.arrangementsDrowndownMenu:Show()
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
		local classColor = playerTable[name].classColor
		label.text:SetTextColor(classColor.r, classColor.g, classColor.b)
		label.frame:EnableMouse(true)
		label.frame:SetMovable(true)
	else
		self:ClearLabel(label)
	end
end

function cleangroupassigns:LabelFunctionality(label)
	local anchorPoint, parentFrame, relativeTo, ptX, ptY
	label.frame:SetScript("OnMouseDown", function(self)
		-- No Op. Just a hack to keep the button in an unclicked state since SetButtonState in OnDragStart does not work
	end)

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
							if x >= cLeft and x <= cLeft + cWidth and y >= cTop and y <= cTop + cHeight then
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
	label.text:SetTextColor(0.35, 0.35, 0.35)
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

function cleangroupassigns:FillPlayerBank()
	if isDraggingLabel then
		shouldUpdatePlayerBank = true
		return
	end

	-- Grab >= level 58 from guild roster
	local numGuildMembers = GetNumGuildMembers()
	for i = 1, numGuildMembers do
		local name, _, _, level, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
		name = strSplit(name, "-")[1]
		if level >= 58 then
			AddToPlayerTable(name, class)
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
	local playerLabels = self.playerBank.scroll.playerLabels
	for _, name in ipairs(playerTableNames) do
		if not cgaConfigDB.filterCheck or raidPlayers[name] then
			index = index + 1
			local playerLabel
			if playerLabels[index] then
				playerLabel = playerLabels[index]
				playerLabel.frame:EnableMouse(true)
			else
				playerLabel = AceGUI:Create("InteractiveLabel")
				playerLabel:SetFont("Fonts\\FRIZQT__.ttf", 12)
				playerLabel:SetHighlight("Interface\\BUTTONS\\UI-Listbox-Highlight.blp")
				playerLabel:SetFullWidth(true)

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
								local cLeft, cTop, cWidth, cHeight = labels[row][col].SavedRect
								if x >= label.savedRect.left and x <= label.savedRect.left + label.savedRect.width and y >= label.savedRect.top and y <= label.savedRect.top + label.savedRect.height then
									cleangroupassigns:SetLabel(labels[row][col], playerLabel.name)
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

	self.playerBank.scroll:DoLayout()
end

function cleangroupassigns:DoSwap()
	if swapCounter > 40 then
		print("|cFFFF0000Something went wrong, we are still stuck rearranging after 40 swaps. Terminating...|r")
		self:StopSwap()
		return
	end

	self:SetUnarrangable("REARRANGING...")
	self:SendInProgress()

	local raidPlayers, subGroups = GetRaidPlayers()
	for row = 1, 8 do
		for col = 1, 5 do
			local targetName = labels[row][col].name
			if targetName and raidPlayers[targetName].subgroup ~= row then
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

	if inSwap then
		self:DoSwap()
	else
		self:CheckArrangable()
	end
end

function cleangroupassigns:CheckArrangable(enteredCombat)
	local errorMessage
	if not IsInRaid() then
		self.fetchArrangements:SetDisabled(true)
		self.fetchArrangements.frame:EnableMouse(false)
		self.fetchArrangements.text:SetTextColor(0.35, 0.35, 0.35)
		self.currentRaid:SetDisabled(true)
		self.currentRaid.frame:EnableMouse(false)
		self.currentRaid.text:SetTextColor(0.35, 0.35, 0.35)
		errorMessage = "CANNOT REARRANGE - NOT IN A RAID GROUP"
		self:SetUnarrangable(errorMessage)
		return errorMessage
	end

	self.fetchArrangements:SetDisabled(false)
	self.fetchArrangements.frame:EnableMouse(true)
	self.fetchArrangements.text:SetTextColor(self.fetchArrangements.textColor.r, self.fetchArrangements.textColor.g, self.fetchArrangements.textColor.b)
	self.currentRaid:SetDisabled(false)
	self.currentRaid.frame:EnableMouse(true)
	self.currentRaid.text:SetTextColor(self.currentRaid.textColor.r, self.currentRaid.textColor.g, self.currentRaid.textColor.b)

	local raidPlayers = GetRaidPlayers()
	local labelPlayers = {}
	local shouldExit = false
	for row = 1, 8 do
		for col = 1, 5 do
			local name = labels[row][col].name
			if name then
				if not raidPlayers[name] then
					errorMessage = "CANNOT REARRANGE - " .. name .. " IS NOT IN THE RAID"
					self:SetUnarrangable(errorMessage)
					labels[row][col].text:SetTextColor(RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
					shouldExit = true
				end
				labelPlayers[name] = true
			end
		end
	end
	if shouldExit then
		return errorMessage
	end

	for name, _ in pairs(raidPlayers) do
		if not labelPlayers[name] then
			errorMessage = "CANNOT REARRANGE - " .. name .. " IS NOT IN THE SETUP"
			self:SetUnarrangable(errorMessage)
			return errorMessage
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

	self.rearrangeRaid:SetText("REARRANGE RAID")
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
	local messageSerialized = libCompressET:Encode(libCompress:Compress(self:Serialize(message)))
	self:SendCommMessage("cgassigns", messageSerialized, "RAID")
end

function cleangroupassigns:OnCommReceived(prefix, message, distribution, sender)
	if prefix ~= "cgassigns" or sender == UnitName("player") or not message then
		return
	end

	local decoded = libCompressET:Decode(message)
	local decompressed, err = libCompress:Decompress(decoded)
	if not decompressed then
		print("Failed to decompress message: " .. err)
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
		for _, arrangement in ipairs(arrangementsDB) do
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

	if key == "ARRANGEMENTS" and message["asker"] == UnitName("player") and IsRaidAssistant(sender) and message["value"] then
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
	if not cgaConfigDB["welcome"] then
		print("Welcome to cleangroupassigns. Use the minimap button or /cga show to open.")
		cgaConfigDB["welcome"] = true
	end
	self.f = AceGUI:Create("Window")
	self.f:Hide()
	self.f:SetTitle("<clean> group assignments")
	self.f:SetLayout("Flow")
	self.f:SetWidth(764)
	self.f:SetHeight(572)
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
		cleangroupassigns:PopulateArrangements()
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
			labels[row][col] = AceGUI:Create("Button")
			local label = labels[row][col]
			label.row = row
			label.col = col
			label:SetWidth(161)
			label:SetHeight(20)
			label:SetText("Empty")
			label.text:SetTextColor(0.35, 0.35, 0.35)
			self:LabelFunctionality(label)
			raidGroup:AddChild(label)
		end
		AceGUI:RegisterLayout("RaidGroupLayout" .. row, function()
			for col = 1, 5 do
				local label = labels[row][col]
				label:ClearAllPoints()
				label:SetPoint("TOPLEFT", raidGroup.frame, "TOPLEFT", -1, -1 * ((col - 1) * label.frame:GetHeight() + raidGroup.titletext:GetHeight() - 2))
			end
			raidGroup:SetHeight(labels[row][1].frame:GetHeight() * 5 + raidGroups[row].titletext:GetHeight())
		end)
		raidGroup:SetLayout("RaidGroupLayout" .. row)
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

	self.rearrangeRaid = AceGUI:Create("Button")
	self.rearrangeRaid:SetText("REARRANGE RAID")
	self.rearrangeRaid.textColor = {}
	self.rearrangeRaid.textColor.r = r
	self.rearrangeRaid.textColor.g = g
	self.rearrangeRaid.textColor.b = b
	self.rearrangeRaid:SetCallback("OnClick", function() self:RearrangeRaid() end)

	AceGUI:RegisterLayout("MainLayout", function()
		self.raidViews:SetHeight(496 - self.filterCheck.frame:GetHeight())
		self.raidViews:SetPoint("TOPLEFT", self.f.frame, "TOPLEFT", 10, -28)
		self.fetchArrangements:SetPoint("TOPLEFT", self.raidViews.frame, "BOTTOMLEFT", 0, -6)
		self.playerBank:SetHeight(self.raidViews.frame:GetHeight())
		self.playerBank:SetPoint("TOPLEFT", self.raidViews.frame, "TOPRIGHT", 2, 0)
		self.filterCheck:SetPoint("TOPLEFT", self.playerBank.frame, "BOTTOMLEFT", 0, -6)

		self.f:SetWidth(764)
		self.f:SetHeight(572)
		raidGroups[1]:SetPoint("TOPLEFT", self.playerBank.frame, "TOPRIGHT", 2, 0)
		raidGroups[2]:SetPoint("TOPLEFT", raidGroups[1].frame, "TOPRIGHT", 2, 0)
		raidGroups[3]:SetPoint("TOPLEFT", raidGroups[1].frame, "BOTTOMLEFT", 0, 0)
		raidGroups[4]:SetPoint("TOPLEFT", raidGroups[3].frame, "TOPRIGHT", 2, 0)
		raidGroups[5]:SetPoint("TOPLEFT", raidGroups[3].frame, "BOTTOMLEFT", 0, 0)
		raidGroups[6]:SetPoint("TOPLEFT", raidGroups[5].frame, "TOPRIGHT", 2, 0)
		raidGroups[7]:SetPoint("TOPLEFT", raidGroups[5].frame, "BOTTOMLEFT", 0, 0)
		raidGroups[8]:SetPoint("TOPLEFT", raidGroups[7].frame, "TOPRIGHT", 2, 0)

		self.currentRaid:SetPoint("TOPLEFT", raidGroups[7].frame, "BOTTOMLEFT", 0, -8)
		self.currentRaid:SetWidth(raidGroups[7].frame:GetWidth())
		saveRaid:SetPoint("TOPLEFT", raidGroups[8].frame, "BOTTOMLEFT", 0, -8)
		saveRaid:SetWidth(raidGroups[8].frame:GetWidth())

		self.rearrangeRaid:SetPoint("TOPLEFT", self.currentRaid.frame, "BOTTOMLEFT", 0, -2)
		self.rearrangeRaid:SetWidth(self.currentRaid.frame:GetWidth() * 2 + 2)
	end)

	self:PopulateArrangements()
	self.f:AddChild(self.raidViews)
	self.f:AddChild(self.playerBank)
	self.f:AddChild(self.fetchArrangements)
	self.f:AddChild(self.filterCheck)
	self.f:AddChild(self.currentRaid)
	self.f:AddChild(saveRaid)
	self.f:AddChild(self.rearrangeRaid)

	self.f:SetLayout("MainLayout")

	self:OnRosterUpdate()
	self:HookScript(self.f.frame, "OnShow", function() self:FillCurrentRaid() end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function() self:OnRosterUpdate() end)
	self:RegisterEvent("GUILD_ROSTER_UPDATE", function() self:FillPlayerBank() end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() self:CheckArrangable(true) end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() self:CheckArrangable(false) end)
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
