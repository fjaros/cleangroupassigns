--[[
World of Warcraft Classic Addon to automatically sort your raid based on your preset arrangements.
Author: Munchkin-Fairbanks <clean>
https://github.com/fjaros/cleangroupassigns
]]

cgaConfigDB = {
	filterCheck = false
}
minimapButtonDB = {
	hide = false
}
arrangementsDB = {}

local cleangroupassigns = LibStub("AceAddon-3.0"):NewAddon("cleangroupassigns", "AceComm-3.0", "AceEvent-3.0", "AceHook-3.0", "AceSerializer-3.0")
local libCompress = LibStub("LibCompress")
local libCompressET = libCompress:GetAddonEncodeTable()
local AceGUI = LibStub("AceGUI-3.0")

local playerTable = {}
local labels = {}

local inSwap = false
local remoteInSwap = false
local swapCounter = 0

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
	playerTable[name].classColor = RAID_CLASS_COLORS[class]
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

function cleangroupassigns:PopulateArrangements()
	self.arrangements:ReleaseChildren()
	
	local populate = function(index)
		local arrangement = arrangementsDB[index]
		local label = AceGUI:Create("InteractiveLabel")
		label:SetFont("Fonts\\FRIZQT__.ttf", 12)
		label:SetText(arrangement.name)
		label:SetHighlight("Interface\\Buttons\\UI-Listbox-Highlight")
		label:SetFullWidth(true)
		label:SetCallback("OnClick", function()
			if GetMouseButtonClicked() == "LeftButton" then
				cleangroupassigns:ClearAllLabels()
				for row = 1, 8 do
					for col = 1, 5 do
						local entry = arrangement[row][col]
						AddToPlayerTable(entry.name, entry.class)
						cleangroupassigns:SetLabel(labels[row][col], entry.name)
					end
				end
				self:FillPlayerBank()
				self:CheckArrangable()
			elseif GetMouseButtonClicked() == "RightButton" then
				cleangroupassigns.arrangementsDrowndownMenu.clickedEntry = index
				cleangroupassigns.arrangementsDrowndownMenu:Show()
			end
		end)
		self.arrangements:AddChild(label)
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
	self.playerBank:ReleaseChildren()
	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")

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

	for _, name in ipairs(playerTableNames) do
		if not cgaConfigDB.filterCheck or raidPlayers[name] then
			local playerLabel = AceGUI:Create("InteractiveLabel")
			playerLabel:SetFont("Fonts\\FRIZQT__.ttf", 12)
			playerLabel.name = name
			playerLabel:SetText(name)
			local classColor = playerTable[name].classColor
			playerLabel.label:SetTextColor(classColor.r, classColor.g, classColor.b)
			
			playerLabel:SetHighlight("Interface\\BUTTONS\\UI-Listbox-Highlight.blp")
			playerLabel:SetFullWidth(true)
			
			local anchorPoint, parentFrame, relativeTo, ptX, ptY
			playerLabel.frame:EnableMouse(true)
			playerLabel.frame:SetMovable(true)
			playerLabel.frame:RegisterForDrag("LeftButton")
			playerLabel.frame:SetScript("OnDragStart", function(self)
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
								cleangroupassigns:SetLabel(labels[row][col], name)
								cleangroupassigns:RearrangeGroup(row)
								return true
							end
						end
					end
					return false
				end
				
				if putToGroup() then
					cleangroupassigns:FillPlayerBank()
				else
					playerLabel:ClearAllPoints()
					playerLabel:SetPoint(anchorPoint, parentFrame, relativeTo, ptX, ptY)
					playerLabel.frame:SetFrameStrata("TOOLTIP")
				end
			end)
			
			scroll:AddChild(playerLabel)
		end
	end
	
	self.playerBank:AddChild(scroll)
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

function cleangroupassigns:CheckArrangable()
	if not IsInRaid() then
		self.fetchArrangements:SetDisabled(true)
		self.fetchArrangements.frame:EnableMouse(false)
		self.fetchArrangements.text:SetTextColor(0.35, 0.35, 0.35)
		self.currentRaid:SetDisabled(true)
		self.currentRaid.frame:EnableMouse(false)
		self.currentRaid.text:SetTextColor(0.35, 0.35, 0.35)
		self:SetUnarrangable("CANNOT REARRANGE - NOT IN A RAID GROUP")
		return
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
					self:SetUnarrangable("CANNOT REARRANGE - " .. name .. " IS NOT IN THE RAID")
					labels[row][col].text:SetTextColor(RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
					shouldExit = true
				end
				labelPlayers[name] = true
			end
		end
	end
	if shouldExit then
		return
	end
	
	for name, _ in pairs(raidPlayers) do
		if not labelPlayers[name] then
			self:SetUnarrangable("CANNOT REARRANGE - " .. name .. " IS NOT IN THE SETUP")
			return
		end
	end
	
	if not IsRaidAssistant() then
		self:SetUnarrangable("CANNOT REARRANGE - NOT A RAID LEADER OR ASSISTANT")
		return
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
			tooltip:SetText("clean group assigns")
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
	self.raidViews:AddChild(self.arrangements)
	
	self.playerBank = AceGUI:Create("InlineGroup")
	self.playerBank:SetWidth(200)
	self.playerBank:SetTitle("Player Bank")
	self.playerBank:SetLayout("Fill")
	
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
		local editBox = AceGUI:Create("EditBox")
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
				table.insert(arrangementsDB, newEntry)
			end
			inEditingState = false
			cleangroupassigns:PopulateArrangements()
		end)
		inEditingState = true
		cleangroupassigns.arrangements:AddChild(editBox)
	end)
	
	self.rearrangeRaid = AceGUI:Create("Button")
	self.rearrangeRaid:SetText("REARRANGE RAID")
	self.rearrangeRaid.textColor = {}
	self.rearrangeRaid.textColor.r = r
	self.rearrangeRaid.textColor.g = g
	self.rearrangeRaid.textColor.b = b
	self.rearrangeRaid:SetCallback("OnClick", function()
		inSwap = true
		swapCounter = 0
		self:DoSwap()
	end)
	
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
	self:RegisterComm("cgassigns")
end
