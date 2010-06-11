--I wanted a simple mod that allowed me to see the quests my party members or friends had without using the horrible
--built in system by Blizzard.  This mod will display a window with all the quests they have as well as provide QuestLinks.
--If you double click on a quest it will send a command to the friend or party member to share that quest with you.
--Derkyle (Creator of ItemSync and AuctionSync)

--Special thanks and credit to the creator of FuBar_FuXPFu and the creator of ag_UnitFrames for the bar graphic.
--Special thanks to the creator of the ChatThrottleLib, for this addon wouldn't be around without it.
--A very special thanks to the creators of Dongle, without them this addon wouldn't be possible.

QuestSync = {};
QuestSync.version = GetAddOnMetadata("QuestSync", "Version")

-- Function hooks
local originalQuestRewardCompleteButton_OnClick;
local originalAbandonQuest;

QuestSync.storeObjectiveInfo = {}

function QuestSync:Enable()

	self.defaults = {
		profile = {
			frame_positions = {
				["QuestSyncTrackFrame"] = {
					["point"] = "CENTER",
					["relativePoint"] = "CENTER",
					["xOfs"] = 0,
					["yOfs"] = 0,
				},
				["QuestSyncMainFrame"] = {
					["point"] = "CENTER",
					["relativePoint"] = "CENTER",
					["xOfs"] = 0,
					["yOfs"] = 0,
				},
			},
			guild = {
			},
			lock_windows = false,
			trackingPlayer = "",
			trackingColors = {0,0,0,1.0},
			totalGuild = 0,
			debug = false,
		},
	}
	
	--lets register the database
	self.db = self:InitializeDB("QuestSyncDB", self.defaults)

	--lets create the GUI
	self:DrawGUI();

	--lets register our slash commands
	self.cmd = self:InitializeSlashCommand("QuestSync Config", "QUESTSYNC", "qs", "qsync", "questsync");
	self.cmd:RegisterSlashHandler("show - Toggle Displaying of Menu Frame", "^show$", "ToggleShow");
	self.cmd:RegisterSlashHandler("lock - Lock window positions", "^lock$", "ToggleLock");
	self.cmd:RegisterSlashHandler("reset - Reset window positions", "^reset$", "FrameReset");
	self.cmd:RegisterSlashHandler("debug - Toggle Debug", "^debug$", "ToggleDebug");
	self.cmd:RegisterSlashHandler("tracking - Display player being tracked", "^tracking$", "ShowTracking");
	self.cmd:RegisterSlashHandler("stoptracking - Stop all tracking and hide the quest tracker", "^stoptracking$", "StopTracking");
	
	--check for debugger
	if self.db.profile.debug then
		self:EnableDebug(1)
	else
		self:EnableDebug()
	end
	
	--show loading notification
	self:Print("Version ["..QuestSync.version.."] loaded. /qs, /qsync");

	self:RegisterEvent("CHAT_MSG_CHANNEL");
	self:RegisterEvent("CHAT_MSG_ADDON");
	self:RegisterEvent("PLAYER_LEVEL_UP");
	self:RegisterEvent("QUEST_WATCH_UPDATE");
	self:RegisterEvent("QUEST_LOG_UPDATE");
	self:RegisterEvent("QUEST_COMPLETE");
	self:RegisterEvent("PLAYER_XP_UPDATE");
	self:RegisterEvent("GUILD_ROSTER_UPDATE");
	
	originalQuestRewardCompleteButton_OnClick = QuestRewardCompleteButton_OnClick;
	QuestRewardCompleteButton_OnClick = QuestSync.QuestComplete;
	
	originalAbandonQuest = AbandonQuest;
	AbandonQuest = QuestSync.QuestAbandon;
	
	--if you don't check, then they will always get a message stating they aren't
	--in a guild
	if IsInGuild() then
		GuildRoster(); --to update the guild list
	end
	
	--------------------------------------------
	--CHANNEL HANDLER
	--------------------------------------------
	--I'm using both SendAddonMessage and SendChatMessage
	--If the user is in a party,raid, guild we will use SendAddonMessage for their requests
	--Otherwise we can spam our Quest Updates and info into the Chat Channel.  That way we aren't
	--Spamming SendAddonMessage with party,raid,guild because we don't know whom is tracking us and on
	--what channel.
	--PLUS THIS WAY WE SPAM ONLY ONE CHANNEL INSTEAD OF THREE FOR QUEST DATA UPDATES
	self.QS_Global = "QuestSync"..UnitFactionGroup("player");
	
	--[[
	--		For CHAT_MSG types:
	--			arg1 - message
	--			arg2 - player
	--			arg3 - language (or nil)
	--			arg4 - fancy channel name (5. General - Stormwind City)
	--				   *Zone is always current zone even if not the same as the channel name
	--			arg5 - Second player name when two users are passed for a CHANNEL_NOTICE_USER (E.G. x kicked y)
	--			arg6 - AFK/DND "CHAT_FLAG_"..arg6 flags
	--			arg7 - zone ID
	--				1 (2^0) - General
	--				2 (2^1) - Trade
	--				2097152 (2^21) - LocalDefense
	--				8388608 (2^23) - LookingForGroup
	--				(these numbers are added bitwise)
	--			arg8 - channel number (5)
	--			arg9 - Full channel name (General - Stormwind City)
	--				   *Not from GetChannelList
	--]]
	
	local function filterOut_QuestSync(...)
	
		if (event and event == "CHAT_MSG_CHANNEL_NOTICE_USER") then
			if arg4 and string.find(arg4, QuestSync.QS_Global) then
				return true;
			end
		elseif (event and event == "CHAT_MSG_CHANNEL_LIST") then
			if arg4 and string.find(arg4, QuestSync.QS_Global) then
				return true;
			end
		else
			if (arg9 and arg9 == QuestSync.QS_Global) then
				return true;
			end
		end
		
	end

	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", filterOut_QuestSync)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_JOIN", filterOut_QuestSync)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_LEAVE", filterOut_QuestSync)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", filterOut_QuestSync)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_LIST", filterOut_QuestSync)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", filterOut_QuestSync)
	
	--------------------------------------------
	
end
	
function QuestSync:Disable()
	self:UnregisterAllEvents();
end

function QuestSync:OnUpdate(elapsed)

	--only do this update once... that's it
	if self.doOnce then
		QuestSyncTimer:Hide(); --hide the frame to stop the update process
		return
	end

	if not self.LastUpdate then
		self.LastUpdate = 0;
	end
	
	if not self.StoredQuestNum then
		self.StoredQuestNum = 0;
	end
  	
  	self.LastUpdate = self.LastUpdate + elapsed;
  	
  	if ( self.LastUpdate > 1) then
  		
  		if not self.loadUpQuest then
  		
			local numEntries, numQuests = GetNumQuestLogEntries();

			--make sure we are working with something other then zero
			--this routine will continue to loop the users quest log until
			--it's been populated by the Blizzard Server.  This doesn't always
			--happen immediately when the user logs in.
			if (numQuests and numQuests > 0) then
				--if we do have player quests then compare
				if (self.playerQuests) then
					if (self.StoredQuestNum == numQuests) then
						self.loadUpQuest = 1; --do the next phase of the timer
						self:Print("The addon is now fully loaded, you may begin utilizing it.");
						self:Debug(1, "Boolean for CheckPlayerQuests enabled");
					else
						self:InitialScan();
					end
				--we don't have any player quests to scan the questlog again
				elseif (numQuests and not self.playerQuests) then
					self:InitialScan();
				end
			end
		
		--once the quests have been filtered
		elseif self.loadUpQuest then
		
			--do the channel joining
			local chanlist = {GetChannelList()};
			
			if chanlist and self.QS_Global and table.getn(chanlist) > 0 then
				
				JoinTemporaryChannel(self.QS_Global);
				chanlist = {GetChannelList()};
				
				for i = 1, table.getn(chanlist) do
					id, channame = GetChannelName(i);

					if (channame and channame == self.QS_Global) then
						self.QS_GlobalNum = id;
						self.doOnce = 1;
						self:DebugC(1, "QuestSync Channel: %s Number: %s", self.QS_Global, self.QS_GlobalNum);
						break;
					end
				end
			
			end
		
		end
  	
  		self.LastUpdate = 0;
  	end
  	
end

function QuestSync:CheckSpam(usr, msg)
	
	local availSlot = 0;
	local sSwitch = -1;
	
	--sSwitch = 1 (false)
	--sSwitch = 2 (true)
	
	if (not self.spamMessages) then
		self.spamMessages = { };
		
		--lets start with 10 slots to work with (we can add more as we go)
		for i=1, 10 do
			self.spamMessages[i] = { };
		end
	end
	
	--lets try to find a match
	for i=1, table.getn(self.spamMessages) do
	
		--first check the name
		if (self.spamMessages[i].name) then
			
			--second check the names
			if (self.spamMessages[i].name == usr) then

				--we found an entry with the users name lets check for the same message
				if (self.spamMessages[i].message == msg) then

					--the message matches but lets see if it's a really old one
					if ( (GetTime() - self.spamMessages[i].time) > 5 ) then
						--what this means is that the local time minus the one stored has exceeded 5 seconds
						--so that means it's old, lets replace it with the new one and update the time
						self.spamMessages[i].time = GetTime();
						sSwitch = 1;
					else
						--it's within 5 seconds, so it's spam
						sSwitch = 2;
					end
				
				else
					--the messages doesn't match, it's not spam but something new instead so lets add it
					self.spamMessages[i].message = msg;
					self.spamMessages[i].time = GetTime();
					sSwitch = 1;
				end
		
			else
				--the name doesn't match, but lets check for elapse time
				if ( (GetTime() - self.spamMessages[i].time) > 5 ) then
					--what this means is that the local time minus the one stored has exceeded 5 seconds
					--so lets delete it to allow future events for that user
					self.spamMessages[i] = { };
					
					--store the available slot to store info if needed
					if (availSlot == 0) then
						availSlot = i;
					end
				end
			end
		else
			--store the available slot to store info if needed
			if (availSlot == 0) then
				availSlot = i;
			end
		end
		
	end
	
	--we do this so that the above for loop checks all the out of date messages
	--so it loops through all of them before we proceed.  This will free up slots for future messages
	--instead continously adding to an array before it reaches the end
	if sSwitch ~= -1 then
		if sSwitch == 1 then
			return false
		else
			return true
		end
	end
	
	--if nothing was found in the array then lets just add the user
	if (availSlot > 0) then
		--an available slot was found so lets use it
		self.spamMessages[availSlot].name = usr;
		self.spamMessages[availSlot].message = msg;
		self.spamMessages[availSlot].time = GetTime();
	else
		--no slot was found so were going to have to add 1 to the table
		availSlot = table.getn(self.spamMessages) + 1;
		self.spamMessages[availSlot].name = usr;
		self.spamMessages[availSlot].message = msg;
		self.spamMessages[availSlot].time = GetTime();
	end
	
	return false;
end

function QuestSync:CHAT_MSG_CHANNEL(event,msg,sender,channelName)
	
	--not channelName means we are sending it from CHAT_MSG_ADDON
	if (arg9 == self.QS_Global or not channelName) then
		
		--only display if we aren't coming from CHAT_MSG_ADDON
		if channelName then
			self:DebugC(1, "Event: %s Message: %s Sender: %s", event, msg, sender);
		end
		
		--to prevent spam
		if self:CheckSpam(sender, msg) then
			return;
		end

		local q = {self:_split(msg, ";")};
		
		if q then
			
			--Key
			--1 = User Check (someone is requesting if we have questsync, send that we do)
			--2 = Positive Check (someone returned that they have questsync as well)
			--3 = User Level Up
			--4 = User asking for quest list
			--5 = User is sending Quest List String in chunks
			--6 = User Finished Sending Quest String in Chunks, time to assemble it
			--7 = Tracked User picked up a quest
			--8 = Tracked User Completed or Failed a quest
			--9 = Tracked User Abandoned a Quest
			--10 = Tracked User Objective Update
			--11 = End Tracked User Objective Update
			--12 = User XP Update
			--13 = Objective request
			--14 = Objective recieved start
			--15 = Objective recieved end
			
			--USER CHECK
			if (tonumber(q[1]) == 1) then
				local sGet = self:CheckUser(sender, 4);
				
				if sGet then
					self:Send_Msg("2;"..sender..";"..sGet, sender);
					self:DebugC(1, "Positive Check: %s", sender);
				end
				sGet = nil;
			
			--POSITIVE CHECK
			elseif (tonumber(q[1]) == 2) then
				
				--only accept if we are the recipient of the incoming message
				--example: 2;Joe would return false if Joe wasn't our name
				if q[2] ~= UnitName("player") then
					return
				end
				
				if not self._buildindex then
					self._buildindex = { };
				end
				if not self._buildindex.party then
					self._buildindex.party = {};
				end
				if not self._buildindex.raid then
					self._buildindex.raid = {};
				end
				if not self._buildindex.guild then
					self._buildindex.guild = {};
				end
				if not self._buildindex.friends then
					self._buildindex.friends = {};
				end
				if not self._buildindex.totalParty then
					self._buildindex.totalParty = 0;
				end
				if not self._buildindex.totalRaid then
					self._buildindex.totalRaid = 0;
				end
				if not self._buildindex.totalGuild then
					self._buildindex.totalGuild = 0;
				end
				if not self._buildindex.totalFriends then
					self._buildindex.totalFriends = 0;
				end
				
				if q[3] == "PARTY" then
					self._buildindex.party[sender] = sender;
					self._buildindex.totalParty = self._buildindex.totalParty + 1;
				elseif q[3] == "RAID" then
					self._buildindex.raid[sender] = sender;
					self._buildindex.totalRaid = self._buildindex.totalRaid + 1;
				elseif q[3] == "GUILD" then
					self._buildindex.guild[sender] = sender;
					self._buildindex.totalGuild = self._buildindex.totalGuild + 1;
				elseif q[3] == "FRIENDS" then
					self._buildindex.friends[sender] = sender;
					self._buildindex.totalFriends = self._buildindex.totalFriends + 1;
				end
				
				self:DebugC(1, "Added User: %s To: %s", sender ,q[3]);
				
				self:ProcessUsers();
			
			--LEVEL UP
			elseif (tonumber(q[1]) == 3) then
				
				local sGet = self:CheckUser(sender, 4);
				if sGet then
					self:Print("Hurray! "..sender.." has reached level "..q[2]..".");
				end
				sGet = nil;
				
			--QUEST LIST REQUEST
			elseif (tonumber(q[1]) == 4) then
				
				--only accept if we are the recipient
				if q[2] ~= UnitName("player") then
					return
				end
				
				local sGet = self:CheckUser(sender, 4);
				
				if sGet then
					--first check to see if we have any quests
					if GetNumQuestLogEntries() <= 0 then
						self:Send_Msg("5;"..sender..";none", sender);
						return
					end
				
					--send them the quest list string in chunks
					local qString = self:Get_QuestString();

					if qString then
						local gtC = self:toChunks(qString, 150);

						for k, v in pairs(gtC) do
							self:Send_Msg("5;"..sender..";"..v, sender);
						end
						
						self:Send_Msg("6;"..sender..";"..UnitName("player"), sender);
						self:DebugC(1, "Sent Quest Chunks To: %s", sender);
						
						--only display the message if we requested it
						if q[4] and tonumber(q[4]) == 0 then
							self:Print("Player ["..self:AddColor("33FF66",sender).."] has requested your Quest Log information.");
						end
						
						gtC = nil;
					end
					qString = nil;
				end
				sGet = nil;
				
			--QUEST LIST RECIEVE
			elseif (tonumber(q[1]) == 5) then
				
				--only accept if we are the recipient
				if q[2] ~= UnitName("player") then
					return
				end
				
				--check for no quests
				if q[3] == "none" then
					self:Print("NOTE: Player ["..QuestSync:AddColor("33FF66",sender).."] has no quests.");
					return
				end
				
				--just add the recieved portion to the exsisting information that has been recieved
				if not self.recvQuestString then
					self.recvQuestString = q[3];
				else
					self.recvQuestString = self.recvQuestString..q[3];
				end
				
				self:DebugC(1, "Recieved Quest Chunk From: %s Chunk Data: %s Chunk Size: %s", sender , q[3], string.len(q[3]));
				
			--QUEST LIST RECIEVE FINISHED
			elseif (tonumber(q[1]) == 6) then
				
				--only accept if we are the recipient
				if q[2] ~= UnitName("player") then
					return
				end
				
				self.currentPlayer = sender; --store the person we clicked on
				
				self:ProcessQuests(self.recvQuestString);
				
				--empty the string for the next batch that comes, otherwise it will add to old data
				self.recvQuestString = nil;
				self:DebugC(1, "Finished Quest List Chunks From: %s", sender);


			--QUEST TRACK ADD
			elseif (tonumber(q[1]) == 7) then
			
				if q[2] then
				
					local p = {self:_split(q[2], "@")};
					
					if p then
						if p[1] and self.db.profile.trackingPlayer and self.db.profile.trackingPlayer == p[1] then
							--we are tracking this player
							DEFAULT_CHAT_FRAME:AddMessage(self:AddColor("FFCC33", "TRACKER")..": ["..self:AddColor("00FF66",self.db.profile.trackingPlayer).."] has accepted the quest '"..self:AddColor("33FFFF",p[2]).."'.");

							--update quest log if there
							if QuestSyncMainFrame:IsVisible() then
								self:Send_Msg("4;"..p[1]..";"..UnitName("player")..";1", sender); --must be 1 at end to avoid spam on chat
							end
						end
					end
					p = nil;
				end
				
			--QUEST TRACK COMPLETE/FAILED
			elseif (tonumber(q[1]) == 8) then
			
				if q[2] then
				
					local p = {self:_split(q[2], "@")};

					if p then
						if p[1] and self.db.profile.trackingPlayer and self.db.profile.trackingPlayer == p[1] then
							if p[2] and p[3] then
								if tonumber(p[2]) == 1 then
									DEFAULT_CHAT_FRAME:AddMessage(self:AddColor("FFCC33", "TRACKER")..": ["..self:AddColor("00FF66",self.db.profile.trackingPlayer).."] has ["..self:AddColor("00FF00","COMPLETED").."] the quest '"..self:AddColor("33FFFF",p[3]).."'.");
								else
									DEFAULT_CHAT_FRAME:AddMessage(self:AddColor("FFCC33", "TRACKER")..": ["..self:AddColor("00FF66",self.db.profile.trackingPlayer).."] has ["..self:AddColor("FF0000","FAILED").."] the quest '"..self:AddColor("33FFFF",p[3]).."'.");
								end
							end
						end
					end
					p = nil;
				end
				
			--QUEST TRACK ABANDONED
			elseif (tonumber(q[1]) == 9) then
			
				if q[2] then
				
					local p = {self:_split(q[2], "@")};

					if p then
						if p[1] and self.db.profile.trackingPlayer and self.db.profile.trackingPlayer == p[1] then
							if p[2] then
								DEFAULT_CHAT_FRAME:AddMessage(self:AddColor("FFCC33", "TRACKER")..": ["..self:AddColor("00FF66",self.db.profile.trackingPlayer).."] has ["..self:AddColor("FF9900","ABANDONED").."] the quest '"..self:AddColor("33FFFF",p[2]).."'.");
							
								--update quest log if there
								if QuestSyncMainFrame:IsVisible() then
									self:Send_Msg("4;"..p[1]..";"..UnitName("player")..";1", sender); --must be 1 at end to avoid spam on chat
								end
							end
						end
					end
					p = nil;
				end
				

			--OBJECTIVE TRACK UPDATE
			elseif (tonumber(q[1]) == 10) then

				if q[2] then
				
					local p = {self:_split(q[2], "@")};

					if p then
						if p[1] and self.db.profile.trackingPlayer and self.db.profile.trackingPlayer == p[1] then
							if p[2] then
								if not self.recvObjString then
									self.recvObjString = p[2];
								else
									self.recvObjString = self.recvObjString..p[2];
								end
							end
						end
					end
					p = nil;
				end
				
				
			--OBJECTIVE TRACK END
			elseif (tonumber(q[1]) == 11) then

				if q[2] then
				
					local p = {self:_split(q[2], "@")};

					if p then
						if p[1] and self.db.profile.trackingPlayer and self.db.profile.trackingPlayer == p[1] then
							if p[2] and p[3] then
								self:ProcessTracker(p[2], self.recvObjString, p[3]);
								self.recvObjString = nil;
							end
						end
					end
					p = nil;
				end
				
				
			--TRACKER XP UPDATE
			elseif (tonumber(q[1]) == 12) then

				if q[2] then
				
					local p = {self:_split(q[2], "@")};

					if p then
						if p[1] and self.db.profile.trackingPlayer and self.db.profile.trackingPlayer == p[1] then
							if p[2] then
								local currXP = tonumber(p[2]);
								local nextXP = tonumber(p[3]);
								local restXP = tonumber(p[4]);
								
								self.saveXPData = {};
								self.saveXPData.currXP = currXP;
								self.saveXPData.nextXP = nextXP;
								self.saveXPData.restXP = restXP;

								--fix the width of the xp bar
								self:FixXPBar();

								QuestSyncMainFrame.tracker.XPFrame.barXP:SetMinMaxValues(0,nextXP);
								QuestSyncMainFrame.tracker.XPFrame.barXP:SetValue(currXP);
								QuestSyncMainFrame.tracker.XPFrame.barXP:Show();
								
								if restXP > 0 then
									
									QuestSyncMainFrame.tracker.XPFrame.barREST:SetMinMaxValues(0,nextXP);
									
									if ( (restXP + currXP) > nextXP) then
										--the rest xp goes past the current xp bar. then highlight all
										QuestSyncMainFrame.tracker.XPFrame.barREST:SetValue(nextXP);
									else
										QuestSyncMainFrame.tracker.XPFrame.barREST:SetValue((restXP + currXP));
									end
									
									QuestSyncMainFrame.tracker.XPFrame.barREST:Show();
								
								else
									--hide the rest xp
									QuestSyncMainFrame.tracker.XPFrame.barREST:Hide();
								end

							end
						end
					end
					p = nil;
					
				end --if q[2] then (Tracker XP)
				
				
			--OBJECTIVE REQUEST
			elseif (tonumber(q[1]) == 13) then
				
				--only accept if we are the recipient
				if q[2] ~= UnitName("player") then
					return
				end
				
				local p = {self:_split(q[4], "@")};
				
				if p and p[1] and p[2] then
					local sGet = self:CheckUser(sender, 4);

					if sGet then

						--send them the quest list string in chunks
						local qString = self:Get_QuestObjectives(p[1], tonumber(p[2]), tonumber(p[3]));

						if qString then
							local gtC = self:toChunks(qString, 150);

							for k, v in pairs(gtC) do
								self:Send_Msg("14;"..sender..";"..v, sender);
							end
							
							self:Send_Msg("15;"..sender..";"..UnitName("player"), sender);
							self:DebugC(1, "Sent Objective Chunks To: %s", sender);

							gtC = nil;
						end
						qString = nil;

					end
					sGet = nil;
				end
				
				p = nil
				
				
			--OBJECTIVE RECIEVE START
			elseif (tonumber(q[1]) == 14) then

				--only accept if we are the recipient
				if q[2] ~= UnitName("player") then
					return
				end
				
				--just add the recieved portion to the exsisting information that has been recieved
				if not self.recvObjectiveReqString then
					self.recvObjectiveReqString = q[3];
				else
					self.recvObjectiveReqString = self.recvObjectiveReqString..q[3];
				end
				
				self:DebugC(1, "Recieved Objective Chunk From: %s Chunk Data: %s Chunk Size: %s", sender , q[3], string.len(q[3]));
				

			--OBJECTIVE RECIEVE END
			elseif (tonumber(q[1]) == 15) then

				--only accept if we are the recipient
				if q[2] ~= UnitName("player") then
					return
				end
				
				local p = {self:_split(self.recvObjectiveReqString, "@")};
				
				if p then
				
					local storeResults = {}
					storeResults.name = p[1]
					storeResults.questID = tonumber(p[2])
					storeResults.barID = tonumber(p[3])
					storeResults.objText = ""

					local y = {self:_split(p[4], "}")};

					--do objectives
					if y then

						for k, v in pairs(y) do

							local w = {self:_split(v, "{")};

							if w[1] and w[1] ~= "" then

								--completed or not completed
								if w[2] and tonumber(w[2])  == 0 then
									storeResults.objText = storeResults.objText..self:AddColor("FFFFFF",w[1]).."\n"
								elseif w[2] and tonumber(w[2])  == 1 then
									storeResults.objText = storeResults.objText..self:AddColor("A2D96F",w[1]).."\n"
								elseif w[2] and tonumber(w[2]) == 2 then
									--storeResults.objText = storeResults.objText..self:AddColor("FFFFFF",w[1]).."\n"
									--lets not store that right now, since we can modify the quest tooltip
									storeResults.objText = self:AddColor("FFFFFF","Currently has this objective. (En-Route)\n")
								end
							end
						end --for k, v in pairs(y) do
					end
					
					y = nil
					
					--store the info
					if not QuestSync.storeObjectiveInfo[storeResults.barID] then
						QuestSync.storeObjectiveInfo[storeResults.barID] = {}
					end

					QuestSync.storeObjectiveInfo[storeResults.barID].name = storeResults.name
					QuestSync.storeObjectiveInfo[storeResults.barID].questID = storeResults.questID
					QuestSync.storeObjectiveInfo[storeResults.barID].barID = storeResults.barID
					QuestSync.storeObjectiveInfo[storeResults.barID].objText = storeResults.objText
					
					--force the tooltip to show if not shown
					self:ShowObjective_Tooltip(storeResults.barID);

					storeResults = nil
				end
				
				p = nil
				self.recvObjectiveReqString = nil

				self:DebugC(1, "Recieved Objective End from: %s", sender);
			end
			
			q = nil;
			
		end --if q then
		
	end --if (arg9 == self.QS_Global) then
end

function QuestSync:CHAT_MSG_ADDON(event,prefix,msg,chan,sender)
	if (prefix == "QUESTSYNC") then
		self:DebugC(1, "Event: %s Prefix: %s Message: %s Channel: %s Sender: %s", event, prefix, msg, chan, sender);
		
		--send it to the Channel parser
		QuestSync:CHAT_MSG_CHANNEL("CHAT_MSG_CHANNEL",msg,sender,nil);
	end
end

function QuestSync:GUILD_ROSTER_UPDATE(event)

	if not IsInGuild() then
		self.db.profile.guild = { };
		return
	end
	
	if self.db.profile.totalGuild ~= GetNumGuildMembers(true) then
		self:Debug(1, "Updating Guild Members");
		self.db.profile.guild = {}; --reset it in case someone left guild or joined
		
		for i=1, GetNumGuildMembers(true) do
			local name, rank, rank_index, level, class, zone, note, officer_note, online, status = GetGuildRosterInfo(i);
			self.db.profile.guild[name] = true;
		end
		
		self.db.profile.totalGuild = GetNumGuildMembers(true);
	end
end

function QuestSync:PLAYER_LEVEL_UP(event, newlvl, ...)
	self:Send_Msg("3;"..newlvl);
	self:PLAYER_XP_UPDATE();
end

function QuestSync:PLAYER_XP_UPDATE(event, unit, ...)
	
	if (not unit or unit == "player") then
		local currXP = UnitXP("player");
		local nextXP = UnitXPMax("player");
		local restXP = GetXPExhaustion() or 0;

		--just a little spam protection, just in case (hey you never know)
		local chkmsg = "12;"..UnitName("player").."@"..currXP.."@"..nextXP.."@"..restXP;

		if (not self.lastxpmsg) then
			self.lastxpmsg = chkmsg;
		elseif (self.lastxpmsg == chkmsg) then
			return;
		else
			self.lastxpmsg = chkmsg;
		end

		self:Send_Msg(chkmsg);
	end
end

function QuestSync:QUEST_WATCH_UPDATE(event, questID, ...)
	SelectQuestLogEntry(questID);
	self.storeQuestName = GetQuestLogTitle(questID);
	self.storeQuestDB_ID = self:GetCurrentQuestID();
end

function QuestSync:QUEST_LOG_UPDATE(event, ...)
	self:CheckPlayerQuests(true);
end

function QuestSync:QUEST_COMPLETE()
	if (not self.playerQuests) then
		self.lastComptQuestName = nil;
		self.lastComptQuest_Orig_Name = nil;
		self.lastComptQuest_ID = nil;
		return
	end
	
	self.lastComptQuestName = nil; --reset
	self.lastComptQuest_Orig_Name = nil; --reset
	self.lastComptQuest_ID = nil;
	self:DebugC(1, "Checking QUEST_COMPLETE For: %s", strtrim(GetTitleText()));

	for k, v in pairs(self.playerQuests) do
		if v and v.origName then
			--do we have a quest with this title and have we sent any completed/failed messages yet
			if v.origName == strtrim(GetTitleText()) and not v.sentmsg then
				--we check for it so that we don't send the wrong quest (some quests share the same name)
				--obviously if we sent the previous one then that one is completed with quest set to sent
				self.lastComptQuestName = k;
				self.lastComptQuest_Orig_Name = v.origName;
				self.lastComptQuest_ID = v.QuestID;
				self:DebugC(1, "Found QUEST_COMPLETE Check For: %s DB_Name: %s", strtrim(GetTitleText()), k);
				break;
			end
		end
	end
end

function QuestSync:CheckUser(user, opt)
	if not user or not opt then
		return nil;
	end
	
	self:DebugC(1, "Checking User: %s", user );
	
	-----------------------
	------DEBUG
	--just for now debugging
	--otherwise we will send nil
	if user == UnitName("player") then
		--if IsInGuild() then
		--	return "GUILD";
		--else
		--	return "PARTY";
		--end
		return nil;
	end
	------DEBUG
	-----------------------

	--Party
	if ( opt > 0 and GetNumPartyMembers() > 0 ) then
		for i=1, GetNumPartyMembers() do
			local p="party"..i;
			if UnitName(p) == user then
				return "PARTY";
			end
		end
	end
	
	--Raid
	if ( opt > 1 and GetNumRaidMembers() > 0 ) then
		for i=1, GetNumRaidMembers() do
			local r="raid"..i;
			if UnitName(r) == user then
				return "RAID";
			end
		end
	end

	--Guild
	if (opt > 2 and IsInGuild()) then
		if self.db.profile.guild and self.db.profile.guild[user] then
			return "GUILD";
		end
	end
	
	--Friends
	if (opt > 3 and GetNumFriends() > 0) then
		local name, level, class
		for i = 1, GetNumFriends() do
			name, level, class = GetFriendInfo(i)
			if name == user then
				return "FRIENDS";
			end
		end
	end
	

	
	return nil;
end

function QuestSync:UserOnline(user)
	if not user then
		return nil;
	end
	self:DebugC(1, "Checking if user is online: %s", user);
	
	-----------------------
	------DEBUG
	--just for now debugging, return 1
	--otherwise return nil as default
	if user == UnitName("player") then
		--return 1;
		return nil;
	end
	------DEBUG
	-----------------------
	
	--First try to use the playername sometimes this works
	local success, exists = pcall(UnitIsConnected, p); --we have to use pcall in case of error return
	if success and exists then
		return 1;
	end
	
	--Party
	if ( GetNumPartyMembers() > 0 ) then
		for i=1, GetNumPartyMembers() do
			local p="party"..i;
			if UnitName(p) == user and UnitIsConnected(p) then
				return 1;
			end
		end
	end
	
	--Raid
	if ( GetNumRaidMembers() > 0 ) then
		for i=1, GetNumRaidMembers() do
			local r="raid"..i;
			if UnitName(r) == user and UnitIsConnected(r) then
				return 1;
			end
		end
	end

	--Guild
	if ( IsInGuild()) then
		for i=1, GetNumGuildMembers(true) do
			local name, rank, rank_index, level, class, zone, note, officer_note, online, status = GetGuildRosterInfo(i);
			if name == user and online then
				return 1;
			end
		end
	end
	
	--Friends
	if (GetNumFriends() > 0) then
		local name, level, class, area, connected, status, note
		for i = 1, GetNumFriends() do
			name, level, class, area, connected, status, note = GetFriendInfo(i)
			if name == user and connected then
				return 1;
			end
		end
	end
	
	return nil;
end

function QuestSync:GetGuildMembers()
	if not IsInGuild() then
		self.db.profile.guild = { };
		return
	end
	
	self:Debug(1, "Getting Guild Members");
	GuildRoster(); --fire it off

	if self.db.profile.totalGuild ~= GetNumGuildMembers(true) then
		self:Debug(1, "Updating Guild Members");
		self.db.profile.guild = {}; --reset it in case someone left guild or joined
		
		for i=1, GetNumGuildMembers(true) do
			local name, rank, rank_index, level, class, zone, note, officer_note, online, status = GetGuildRosterInfo(i);
			self.db.profile.guild[name] = true;
		end
		
		self.db.profile.totalGuild = GetNumGuildMembers(true);
	else
		self:Debug(1, "No Changes To Guild Members Required");
	end
end

function QuestSync:GetUsers()
	self.gettingUsers = 1;
	self:Debug(1, "Getting Users");
	self._buildindex = nil; --reset
	self:Send_Msg("1;"..UnitName("player"));
	self.gettingUsers = nil;
end

function QuestSync:QuestComplete(...)

	if (GetTitleText() and QuestSync.playerQuests) then
	
		--first check for QUEST_COMPLETE check
		if (QuestSync.lastComptQuestName) then
		
			QuestSync:DebugC(1, "Checking (lastComptQuestName) For : %s", QuestSync.lastComptQuestName);
		
			if (QuestSync.playerQuests[QuestSync.lastComptQuestName]) then
				if (not QuestSync.playerQuests[QuestSync.lastComptQuestName].completed) then
					--for some reason we didn't send a complete
					QuestSync:Send_Msg("8;"..UnitName("player").."@1@"..QuestSync.lastComptQuest_Orig_Name);
					QuestSync:DebugC(1, "Sent Quest Complete: %s", QuestSync.lastComptQuest_Orig_Name);
					QuestSync.playerQuests[QuestSync.lastComptQuestName].completed = 1;
					QuestSync.playerQuests[QuestSync.lastComptQuestName].sentmsg = 1;
					
					--send tracking information just in case
					QuestSync.storeQuestName = QuestSync.lastComptQuest_Orig_Name;
					QuestSync.storeQuestDB_ID = QuestSync.lastComptQuest_ID;
					QuestSync:CheckPlayerQuests(false, true);
				
				elseif (QuestSync.playerQuests[QuestSync.lastComptQuestName].completed) then
					
					--check to see if we already sent a msg if not then send it
					if (not QuestSync.playerQuests[QuestSync.lastComptQuestName].sentmsg) then
						--for some reason we didn't send a complete
						QuestSync:Send_Msg("8;"..UnitName("player").."@1@"..QuestSync.lastComptQuest_Orig_Name);
						QuestSync:DebugC(1, "Sent Quest Complete: %s", QuestSync.lastComptQuest_Orig_Name);
						QuestSync.playerQuests[QuestSync.lastComptQuestName].completed = 1;
						QuestSync.playerQuests[QuestSync.lastComptQuestName].sentmsg = 1;
						
						--send tracking information just in case
						QuestSync.storeQuestName = QuestSync.lastComptQuest_Orig_Name;
						QuestSync.storeQuestDB_ID = QuestSync.lastComptQuest_ID;
						QuestSync:CheckPlayerQuests(false, true);
					end
				end

			end
			
			QuestSync.lastComptQuestName = nil; --reset
			QuestSync.lastComptQuest_Orig_Name = nil; --reset
		
		else
			--This part is here just in case something went wrong with the QUEST_COMPLETE
		
			QuestSync:DebugC(1, "Checking (NO lastComptQuestName) For : %s", strtrim(GetTitleText()));

			if (QuestSync.playerQuests) then
				for k, v in pairs(QuestSync.playerQuests) do
					if v and v.origName then
						if v.origName == strtrim(GetTitleText()) then
							if (not v.completed) then
								--for some reason we didn't send a complete
								QuestSync:Send_Msg("8;"..UnitName("player").."@1@"..v.origName);
								QuestSync:DebugC(1, "Sent Quest Complete: %s", v.origName);
								QuestSync.playerQuests[k].completed = 1;
								QuestSync.playerQuests[k].sentmsg = 1;
								
								--send tracking information just in case
								QuestSync.storeQuestName = v.origName;
								QuestSync.storeQuestDB_ID = v.QuestID;
								QuestSync:CheckPlayerQuests(false, true);
								
								break;
								
							elseif (v.completed) then
								--check to see if we already sent a msg if not then send it
								if (not v.sentmsg) then
									--for some reason we didn't send a complete
									QuestSync:Send_Msg("8;"..UnitName("player").."@1@"..v.origName);
									QuestSync:DebugC(1, "Sent Quest Complete: %s", v.origName);
									QuestSync.playerQuests[k].completed = 1;
									QuestSync.playerQuests[k].sentmsg = 1;
									
									--send tracking information just in case
									QuestSync.storeQuestName = v.origName;
									QuestSync.storeQuestDB_ID = v.QuestID;
									QuestSync:CheckPlayerQuests(false, true);
								end
								
								break;
							else
								break;
							end
						end
					end--if v and v.origName then
				end--for k, v in pairs(QuestSync.playerQuests) do
			end--if (QuestSync.playerQuests) then
		end
		
	end
	originalQuestRewardCompleteButton_OnClick(...);
end
	
function QuestSync:QuestAbandon()
	if GetQuestLogSelection() and GetQuestLogTitle(GetQuestLogSelection()) then
		QuestSync:Debug(1, "Quest Abandon: "..GetQuestLogTitle(GetQuestLogSelection()));
		
		local qQuestID = QuestSync:GetCurrentQuestID(GetQuestLogSelection());
		local qTitle = GetQuestLogTitle(GetQuestLogSelection());
		
		if (qQuestID and qTitle and QuestSync.playerQuests[qTitle..":"..qQuestID]) then
			QuestSync.playerQuests[qTitle..":"..qQuestID] = nil;
			QuestSync:Send_Msg("9;"..UnitName("player").."@"..qTitle);
		end
	end
	originalAbandonQuest();
end

function QuestSync:InitialScan()
	
	if (self.runningQuestUpdate) then
		return;
	end
	
	if (self.doOnce) then
		return;
	end
	
	self.runningQuestUpdate = true; --start the spam trigger
	
	if not self.playerQuests then
		self.playerQuests = {};
	end
	
	if not self.StoredQuestNum then
		self.StoredQuestNum = 0;
	end
	
	self:Debug(1, "Performing Startup Quest Scan");
	
	local questSelected= GetQuestLogSelection();
	
		--I seriously wonder why blizzard hasn't updated their API for quests
		--it's horrible when it comes to getting quest names
		local collapsed = self:Store_CollaspedQuests();
		ExpandQuestHeader(0);

	for i = 1, GetNumQuestLogEntries() do
	
		local qTitle, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily = GetQuestLogTitle(i);

		if not isHeader then
		
			local qQuestID = self:GetCurrentQuestID(i);
			
			if qQuestID then
				if not self.playerQuests[qTitle..":"..qQuestID] then
					self.playerQuests[qTitle..":"..qQuestID] = {};
					self.playerQuests[qTitle..":"..qQuestID].completed = isComplete;
					self.playerQuests[qTitle..":"..qQuestID].QuestID = qQuestID;
					self.playerQuests[qTitle..":"..qQuestID].origName = qTitle;
					self:DebugC(1, "Initial Scan Quest Added: %s", qTitle..":"..qQuestID);
					
					self.StoredQuestNum = self.StoredQuestNum + 1;
				end
			
			end--if not qQuestID then
		end--if not isHeader then

	end--for i = 1, GetNumQuestLogEntries() do 
	
	
		--I seriously wonder why blizzard hasn't updated their API for quests
		--it's horrible when it comes to getting quest names
		self:Restore_CollaspedQuests(collapsed);
		
	if GetQuestLogSelection() ~= questSelected then
		SelectQuestLogEntry(questSelected); --reset old selection
	end

	self.runningQuestUpdate = false; --end the spam trigger
end

function QuestSync:CheckPlayerQuests(sendmsg, skipToWatch)
	
	if (not self.doOnce) then
		--don't allow it to go through until the addon is finally loaded
		return;
	elseif (self.runningQuestUpdate) then
		return;
	end

	self.runningQuestUpdate = true; --start the spam trigger
	
	if not self.playerQuests then
		self.playerQuests = {};
	end
	
	self:Debug(1, "Getting Player Quests");
	
	local questSelected= GetQuestLogSelection();
	
		--I seriously wonder why blizzard hasn't updated their API for quests
		--it's horrible when it comes to getting quest names
		local collapsed = self:Store_CollaspedQuests();
		ExpandQuestHeader(0);

	--only do this part if we aren't skipping it
	if not skipToWatch then
		for i = 1, GetNumQuestLogEntries() do

			local qTitle, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily = GetQuestLogTitle(i);

			--isComplete = -1 if quest is (FAILED), +1 if quest is (COMPLETED), nil otherwise.

			if not isHeader then
				local qQuestID = self:GetCurrentQuestID(i);

				if qQuestID then

					if not self.playerQuests[qTitle..":"..qQuestID] then
						self.playerQuests[qTitle..":"..qQuestID] = {};
						self.playerQuests[qTitle..":"..qQuestID].completed = isComplete;
						self.playerQuests[qTitle..":"..qQuestID].QuestID = qQuestID;
						self.playerQuests[qTitle..":"..qQuestID].origName = qTitle;
						self:DebugC(1, "New Quest Added: %s", qTitle..":"..qQuestID);


						if sendmsg then
							self:Send_Msg("7;"..UnitName("player").."@"..qTitle);
							self:DebugC(1, "New Quest Sent: %s", qTitle);
						end

					--if we have isComplete that means they either completed or failed a quest (nil means nothing happened)
					elseif self.playerQuests[qTitle..":"..qQuestID] and isComplete and not self.playerQuests[qTitle..":"..qQuestID].completed then

						if sendmsg then
							if isComplete > 0 then --quest is complete
								self.playerQuests[qTitle..":"..qQuestID].completed = isComplete;
								self.playerQuests[qTitle..":"..qQuestID].sentmsg = 1;
								self:Send_Msg("8;"..UnitName("player").."@1@"..qTitle);
								self:DebugC(1, "Sent Quest Complete: %s", qTitle);
								
								--send tracking information just in case
								self.storeQuestName = qTitle;
								self.storeQuestDB_ID = qQuestID;
								
							else --quest failed
								self.playerQuests[qTitle..":"..qQuestID].completed = isComplete;
								self.playerQuests[qTitle..":"..qQuestID].sentmsg = 1;
								self:Send_Msg("8;"..UnitName("player").."@0@"..qTitle);
								self:DebugC(1, "Sent Quest Failed: %s", qTitle);
								
								--send tracking information just in case
								self.storeQuestName = qTitle;
								self.storeQuestDB_ID = qQuestID;
							end
						end

					--check if the status of the quest changed
					elseif self.playerQuests[qTitle..":"..qQuestID] and self.playerQuests[qTitle..":"..qQuestID].completed then

						if self.playerQuests[qTitle..":"..qQuestID].completed ~= isComplete then
							--something went wrong somewhere, where they lost and item for something stupid, failed the quest, or who knows what

							if sendmsg then
								if not isComplete then
									self.playerQuests[qTitle..":"..qQuestID].completed = nil;
									self.playerQuests[qTitle..":"..qQuestID].sentmsg = nil;
								elseif isComplete > 0 then --quest is complete
									self.playerQuests[qTitle..":"..qQuestID].completed = isComplete;
									self.playerQuests[qTitle..":"..qQuestID].sentmsg = 1;
									self:Send_Msg("8;"..UnitName("player").."@1@"..qTitle);
									self:DebugC(1, "Sent Quest Complete: %s", qTitle);
									--send tracking information just in case
									self.storeQuestName = qTitle;
									self.storeQuestDB_ID = qQuestID;
								elseif isComplete < 0 then --quest failed
									self.playerQuests[qTitle..":"..qQuestID].completed = isComplete;
									self.playerQuests[qTitle..":"..qQuestID].sentmsg = 1;
									self:Send_Msg("8;"..UnitName("player").."@0@"..qTitle);
									self:DebugC(1, "Sent Quest Failed: %s", qTitle);
									--send tracking information just in case
									self.storeQuestName = qTitle;
									self.storeQuestDB_ID = qQuestID;
								end
							end
						end
					end

				end--if not qQuestID then
			end--if not isHeader then

		end--for i = 1, GetNumQuestLogEntries() do 
	end--if not skipToWatch then

	--check for item updates (only when we have too)
	if (self.storeQuestDB_ID and self.storeQuestName) then
	
		--self.storeQuestName
		--self.storeQuestDB_ID
		
		local storeLeaderBoard = "";
	
		for i = 1, GetNumQuestLogEntries() do

			local qTitle, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily = GetQuestLogTitle(i);

			if not isHeader then
				local qQuestID = self:GetCurrentQuestID(i);
				
				if qQuestID then
				
					--now check
					if (qQuestID == self.storeQuestDB_ID and qTitle == self.storeQuestName) then

						local leadB = GetNumQuestLeaderBoards(i);
						
						--sometimes there aren't any objectives but just text
						--so return the text as incomplete
						if leadB <= 0 then
							local questDescription, questObjectives = GetQuestLogQuestText();
							storeLeaderBoard = storeLeaderBoard..questObjectives.."~0{";
						else
							for z = 1, leadB do
								local iText, iType, iFinished = GetQuestLogLeaderBoard(z, i);
								if not iFinished then
									storeLeaderBoard = storeLeaderBoard..iText.."~0{";
								else
									storeLeaderBoard = storeLeaderBoard..iText.."~1{";
								end
							end
						end
				
						--send our updated objectives in case someone is tracking us
						if storeLeaderBoard then
							local gtC = self:toChunks(storeLeaderBoard, 150);

							for k, v in pairs(gtC) do
								self:Send_Msg("10;"..UnitName("player").."@"..v);
							end
							
							if isComplete then
								self:Send_Msg("11;"..UnitName("player").."@"..qTitle.."@"..isComplete);
							else
								self:Send_Msg("11;"..UnitName("player").."@"..qTitle.."@0");
							end

							gtC = nil;
							
							self:DebugC(1, "Sent Objective Update: %s", storeLeaderBoard);

						end
						
						storeLeaderBoard = nil;
						
						--no need to continue the loop
						break;

					end
					
				end --if qQuestID then
			end --if not isHeader then
		end
		
		self.storeQuestName = nil;
		self.storeQuestDB_ID = nil;
            
	end--if not self.storeQuestDB_ID then
	
		--I seriously wonder why blizzard hasn't updated their API for quests
		--it's horrible when it comes to getting quest names
		self:Restore_CollaspedQuests(collapsed);
		
	if GetQuestLogSelection() ~= questSelected then
		SelectQuestLogEntry(questSelected); --reset old selection
	end

	self.runningQuestUpdate = false; --end the spam trigger
end

function QuestSync:ProcessQuests(questInfo)
	if not questInfo then
		return;
	end

	local q = {self:_split(questInfo, "~")};
	local sInfo = { };
	local f = 1;
	local questCount = 0;
	
	--do the real fetch
	if q then
	
		for k, v in pairs(q) do
			
			local w = {self:_split(v, "@")};
			
			if w then
				
				--check if it's a header
				if w[1] == "H" then
					sInfo[f] = { };
					sInfo[f].name = w[2];
					sInfo[f].header = true;
					sInfo[f].isQuest = true;
					f = f + 1;
				else
					sInfo[f] = { };
					sInfo[f].level = w[1];
					
					if w[3] then
						sInfo[f].name = w[3];
					else
						sInfo[f].name = "Unknown";
					end
					
					sInfo[f].questID = w[2];
					sInfo[f].header = false;
					sInfo[f].isQuest = true;
					
					--store that we have this quest in common
					if w[3] and w[2] and self.playerQuests and self.playerQuests[w[3]..":"..w[2]] then
						if self.playerQuests[w[3]..":"..w[2]].completed then
							sInfo[f].compQuest = true;
						else
							sInfo[f].onQuest = true;
						end
					end
					
					f = f + 1;
					questCount = questCount + 1;
				end
				
			end
			
			w = nil;
		end
		
		q= nil;
	end
	
	self.sInfo = sInfo;		
	sInfo = nil;
	self.isItQuests = 1;
	self.isItUsers = nil;
	self.totalQuestsDL = questCount;
	
	if not QuestSyncMainFrame:IsVisible() then
		--the QuestSyncMainFrame.doNotRefresh variable has to be set so that the
		--main list doesn't get wiped from the GetUser() function. Also when using ctrl+leftclick
		QuestSyncMainFrame.doNotRefresh = 1
		QuestSyncMainFrame:Show();
	else
		--update list
		FauxScrollFrame_SetOffset(QuestSyncMainScrollFrame, 0);
		getglobal("QuestSyncMainScrollFrameScrollBar"):SetValue(0);
		self:UpdateScroll(QuestSyncMainScrollFrame);
	end
	
	self:DebugC(1, "Processed Quest Info: %s Total Count: %s",questInfo, table.getn(self.sInfo));
	
	
end

function QuestSync:ProcessUsers()
	if not self._buildindex then
		return
	end

	self.sInfo = nil;

	local sInfo = { };
	local f = 1;

	--PARTY
	if self._buildindex.totalParty and self._buildindex.totalParty > 0 then

		--do header
		sInfo[f] = { };
		sInfo[f].name = "PARTY";
		sInfo[f].header = true;
		sInfo[f].isQuest = false;
		f = f + 1;

		for k, v in pairs(self._buildindex.party) do
			sInfo[f] = { };
			sInfo[f].name = k;
			sInfo[f].header = false;
			sInfo[f].isQuest = false;
			sInfo[f].comm = "PARTY";
			f = f + 1;
		end

	end

	--RAID
	if self._buildindex.totalRaid and self._buildindex.totalRaid > 0 then

		--do header
		sInfo[f] = { };
		sInfo[f].name = "RAID";
		sInfo[f].header = true;
		sInfo[f].isQuest = false;
		f = f + 1;

		for k, v in pairs(self._buildindex.raid) do
			sInfo[f] = { };
			sInfo[f].name = k;
			sInfo[f].header = false;
			sInfo[f].isQuest = false;
			sInfo[f].comm = "RAID";
			f = f + 1;
		end

	end

	--GUILD
	if self._buildindex.totalGuild and self._buildindex.totalGuild > 0 then

		--do header
		sInfo[f] = { };
		sInfo[f].name = "GUILD";
		sInfo[f].header = true;
		sInfo[f].isQuest = false;
		f = f + 1;

		for k, v in pairs(self._buildindex.guild) do
			sInfo[f] = { };
			sInfo[f].name = k;
			sInfo[f].header = false;
			sInfo[f].isQuest = false;
			sInfo[f].comm = "GUILD";
			f = f + 1;
		end

	end

	--FRIENDS
	if self._buildindex.totalFriends and self._buildindex.totalFriends > 0 then

		--do header
		sInfo[f] = { };
		sInfo[f].name = "FRIENDS";
		sInfo[f].header = true;
		sInfo[f].isQuest = false;
		f = f + 1;

		for k, v in pairs(self._buildindex.friends) do
			sInfo[f] = { };
			sInfo[f].name = k;
			sInfo[f].header = false;
			sInfo[f].isQuest = false;
			sInfo[f].comm = "FRIENDS";
			f = f + 1;
		end

	end
	
	self.sInfo = sInfo;
	sInfo = nil;
	self.isItQuests = nil;
	self.isItUsers = 1;
	
	self:DebugC(1, "<Processed User Info> Total Count: %s", table.getn(self.sInfo));
	
	--update list
	FauxScrollFrame_SetOffset(QuestSyncMainScrollFrame, 0);
	getglobal("QuestSyncMainScrollFrameScrollBar"):SetValue(0);
	self:UpdateScroll(QuestSyncMainScrollFrame);

end

function QuestSync:DrawGUI()
	
	--check if it already exists duh
	if QuestSyncMainFrame then
		return
	end

	----CREATE MAIN FRAME----
	local qsyncFrame = CreateFrame("Frame", "QuestSyncMainFrame", UIParent);

	qsyncFrame:SetWidth(360);
	qsyncFrame:SetHeight(495);
	qsyncFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
	

	local backdrop = {bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile=1, tileSize=32, edgeSize = 32,
			insets = {left = 11, right = 12, top = 12, bottom = 11}};


	qsyncFrame:SetBackdrop(backdrop);
	qsyncFrame:SetBackdropColor(0, 0, 0, 1.0);
	qsyncFrame:SetBackdropBorderColor(0.75, 0.75, 0.75, 1.0);
	qsyncFrame:SetFrameStrata("DIALOG");
	qsyncFrame:SetToplevel(true);
	qsyncFrame:EnableMouse(true);
	qsyncFrame:SetMovable(true);
	qsyncFrame:SetClampedToScreen(true);

	qsyncFrame.txtHeader = qsyncFrame:CreateFontString("$parentText", nil, "GameFontNormal");
	qsyncFrame.txtHeader:SetPoint("CENTER", qsyncFrame, "TOP", 0, -30);
	qsyncFrame.txtHeader:SetText(nil);
	
	--add dragging
	qsyncFrame:SetScript("OnMouseDown", function(frame)
			if not QuestSync.db.profile.lock_windows then
				frame.isMoving = true
				frame:StartMoving();
			end
		end)
		
	qsyncFrame:SetScript("OnMouseUp", function(frame) 

			if( frame.isMoving and not QuestSync.db.profile.lock_windows ) then
		
				frame.isMoving = nil
				frame:StopMovingOrSizing()
				
				self:SaveLayout(frame:GetName());

			end
	
		end)
		

		
	qsyncFrame.getUsers = CreateFrame("Button", "QuestSyncGetUsers", qsyncFrame, "OptionsButtonTemplate");
	qsyncFrame.getUsers:SetPoint("BOTTOMLEFT", qsyncFrame, "BOTTOMLEFT", 20, 30);
	qsyncFrame.getUsers:SetWidth(115);
	qsyncFrame.getUsers:SetText("Get Player List");
		qsyncFrame.getUsers:SetScript("OnClick", function(self)
				QuestSync:Refresh();
			end)

	
	qsyncFrame.trackUser = CreateFrame("CheckButton", "QuestSyncTrackUser", qsyncFrame, "OptionsCheckButtonTemplate");
	qsyncFrame.trackUser.text = qsyncFrame.trackUser:CreateFontString("$parentText", nil, "GameFontNormalSmall");
	qsyncFrame.trackUser.text:SetPoint("LEFT", qsyncFrame.trackUser, "RIGHT", -1, 0);
	qsyncFrame.trackUser.text:SetText("Track Player");
	qsyncFrame.trackUser:SetWidth(20);
	qsyncFrame.trackUser:SetHeight(20);
	qsyncFrame.trackUser:SetPoint("TOPLEFT", qsyncFrame, "TOPLEFT", 20, -50);
	
		qsyncFrame.trackUser:SetScript("OnShow", function(self)
			if QuestSync.db.profile.trackingPlayer and QuestSync.db.profile.trackingPlayer ~= "" then
				if QuestSync.db.profile.trackingPlayer == QuestSync.currentPlayer then
					self:SetChecked(true);
				else
					self:SetChecked(false);
				end

			else
				self:SetChecked(false); 
			end

		end)

		qsyncFrame.trackUser:SetScript("OnClick", function(self)
			if (self:GetChecked() and QuestSync.currentPlayer) then
				QuestSyncTrackFrame:Hide();
				GameTooltip:Hide();
				QuestSync.db.profile.trackingPlayer = QuestSync.currentPlayer;
				QuestSync:Print("ALERT: You are now tracking player ["..QuestSync:AddColor("00FF66",QuestSync.currentPlayer).."].");
				QuestSyncTrackFrame:Show();
			else
				QuestSync.db.profile.trackingPlayer = "";
				QuestSync:Print("ALERT: You are no longer tracking any player.");
				GameTooltip:Hide();
				QuestSyncTrackFrame:Hide();
			end
		end)
  
  		
  		--Help Button
		local Help_qsyncFrame = CreateFrame("Button", nil, qsyncFrame);
		Help_qsyncFrame:SetWidth(20);
		Help_qsyncFrame:SetHeight(20);
		Help_qsyncFrame:SetPoint("TOPRIGHT", qsyncFrame, "TOPRIGHT", -30, -20);

		Help_qsyncFrame:SetHighlightFontObject(GameFontHighlight)
		Help_qsyncFrame:SetNormalFontObject(GameFontNormal)

		Help_qsyncFrame.text = Help_qsyncFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		Help_qsyncFrame.text:SetText("[?]")
		Help_qsyncFrame.text:SetPoint("RIGHT", Help_qsyncFrame, 0, 0)
		Help_qsyncFrame.text:SetJustifyH("LEFT")

 			
			Help_qsyncFrame:SetScript("OnEnter", function(self)
				if (self:IsVisible()) then
					GameTooltip:ClearLines();
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
					GameTooltip:SetText("[QuestSync Help]\n"..
					"Green Plus = Have Quest\n"..
					"Red Square = Completed Quest\n\n"..
					"You can hold SHIFT, while moving your mouse\n"..
					"over a quest title to see the current users\n"..
					"objectives.\n\n"..
					"NOTE: To prevent SPAM, you can only request\n"..
					"objectives once every 15 seconds per quest.");
					GameTooltip:Show();	
				end
			end)

			Help_qsyncFrame:SetScript("OnLeave",function(self)
				
			   	GameTooltip:Hide()
			end)
			
	----CREATE HEADER FRAME----
	local qsyncFrame_Header = CreateFrame("Frame", "QuestSyncMainFrame_Header", qsyncFrame, "OptionsBoxTemplate");

	qsyncFrame_Header:SetWidth(338);
	qsyncFrame_Header:SetHeight(30);
	qsyncFrame_Header:SetPoint("LEFT", qsyncFrame, "LEFT", 0, 255);
	qsyncFrame_Header:EnableMouse(true);
	qsyncFrame_Header:SetMovable(true);
	
		local backdrop_header = {bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile=1, tileSize=16, edgeSize = 16,
				insets = {left = 5, right = 5, top = 5, bottom = 5}};


		qsyncFrame_Header:SetBackdrop(backdrop_header);
		qsyncFrame_Header:SetBackdropBorderColor(0.4, 0.4, 0.4);
		qsyncFrame_Header:SetBackdropColor(148/255, 191/255, 226/255, 0.7);
	
		--add dragging
		qsyncFrame_Header:SetScript("OnMouseDown", function(frame)
				if not QuestSync.db.profile.lock_windows then
					frame:GetParent().isMoving = true
					frame:GetParent():StartMoving();
				end
			end)

		qsyncFrame_Header:SetScript("OnMouseUp", function(frame) 

				if( frame:GetParent().isMoving and not QuestSync.db.profile.lock_windows) then

					frame:GetParent().isMoving = nil
					frame:GetParent():StopMovingOrSizing()

					self:SaveLayout(frame:GetParent():GetName());

				end

			end)
		
		local headerInfo = qsyncFrame_Header:CreateFontString("$parentText","BACKGROUND","GameFontNormal");
		headerInfo:SetPoint("CENTER", 9, 0);
		headerInfo:SetText("QuestSync: Version ["..QuestSync.version.."]");

			qsyncFrame_Header.headerInfo = headerInfo;
		
		local closeButton = CreateFrame("Button", nil, qsyncFrame_Header, "UIPanelCloseButton");
		closeButton:SetPoint("CENTER", qsyncFrame_Header, "RIGHT", 9, 0);

		closeButton:SetScript("OnClick", function() 
				HideUIPanel(qsyncFrame)
		end)
		
			qsyncFrame_Header.closeButton = closeButton;
		
	----END HEADER FRAME----
	
	

	----CREATE SCROLL FRAME----
	local qsyncFrame_Scroll = CreateFrame("ScrollFrame", "QuestSyncMainScrollFrame", qsyncFrame, "FauxScrollFrameTemplate");
	
	qsyncFrame_Scroll:SetWidth(296);
	qsyncFrame_Scroll:SetHeight(354);
	qsyncFrame_Scroll:SetPoint("TOPLEFT", qsyncFrame, 19, -75);
	
	qsyncFrame_Scroll.BarFrames = {};

		--lets make the individual bars
		for i=1, 23 do
			
			qsyncFrame_Scroll.BarFrames[i] = CreateFrame("Button", "QuestSyncScrollBar"..i, qsyncFrame_Scroll);
			qsyncFrame_Scroll.BarFrames[i]:SetWidth(300);
			qsyncFrame_Scroll.BarFrames[i]:SetHeight(16);
			qsyncFrame_Scroll.BarFrames[i].lineID = i;
			
			if i == 1 then
				qsyncFrame_Scroll.BarFrames[i]:SetPoint("TOPLEFT", qsyncFrame_Scroll, 0, 0);		
			else
				qsyncFrame_Scroll.BarFrames[i]:SetPoint("TOPLEFT", qsyncFrame_Scroll.BarFrames[i-1], "BOTTOMLEFT", 0, 1);
			end

			qsyncFrame_Scroll.BarFrames[i].text = qsyncFrame_Scroll.BarFrames[i]:CreateFontString("$parentText","ARTWORK","GameFontNormal");
			qsyncFrame_Scroll.BarFrames[i].text:SetJustifyH("LEFT");
			qsyncFrame_Scroll.BarFrames[i].text:SetWidth(275);
			qsyncFrame_Scroll.BarFrames[i].text:SetHeight(12);
			qsyncFrame_Scroll.BarFrames[i].text:SetPoint("LEFT",20,0);
			qsyncFrame_Scroll.BarFrames[i].text:SetText("Bar: "..i);
			qsyncFrame_Scroll.BarFrames[i].text:Hide();

			qsyncFrame_Scroll.BarFrames[i].texture = qsyncFrame_Scroll.BarFrames[i]:CreateTexture(nil, "ARTWORK");
			qsyncFrame_Scroll.BarFrames[i].texture:SetTexture("Interface\\AddOns\\QuestSync\\Shared");
			qsyncFrame_Scroll.BarFrames[i].texture:SetWidth(16);
			qsyncFrame_Scroll.BarFrames[i].texture:SetHeight(16);
			qsyncFrame_Scroll.BarFrames[i].texture:SetPoint("LEFT", 5, 0);
			qsyncFrame_Scroll.BarFrames[i].texture:Hide();

			qsyncFrame_Scroll.BarFrames[i]:RegisterForClicks("LeftButtonUp", "RightButtonUp");
			qsyncFrame_Scroll.BarFrames[i]:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight");
			
			qsyncFrame_Scroll.BarFrames[i]:SetScript("OnClick", function(self)
				if (self:IsVisible()) then
					if self.sInfo then
						if not self.sInfo.header then
							if not self.sInfo.isQuest then
								local sGet = QuestSync:CheckUser(self.sInfo.name, 4);
								if sGet then
									if QuestSync:UserOnline(self.sInfo.name) then
										QuestSync:Send_Msg("4;"..self.sInfo.name..";"..UnitName("player")..";0", self.sInfo.name);
										QuestSync:DebugC(1, "Sent Quest List Request To: %s", self.sInfo.name);
										QuestSync:Print("Sending quest list request to: ["..QuestSync:AddColor("33FF66",self.sInfo.name).."]...please wait!");									
									else
										QuestSync:Print("ERROR! Player ["..QuestSync:AddColor("33FF66",self.sInfo.name).."] is not online.");
									end
								else
									QuestSync:Print("ERROR! Player ["..QuestSync:AddColor("33FF66",self.sInfo.name).."] is not in friends list, party, raid, or guild.");
								end
								
								QuestSync:DebugC(1, "User Clicked: %s", self.lineID);
							elseif self.sInfo.isQuest then
								QuestSync:DebugC(1, "Quest Clicked: %s", self.lineID);
							end
						end
					end
				end
			end)

			qsyncFrame_Scroll.BarFrames[i]:SetScript("OnEnter", function(self)
				if (self:IsVisible()) then
					if self.sInfo then
						if not self.sInfo.header then
							if not self.sInfo.isQuest and not self.sInfo.header then
								GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
								GameTooltip:SetText("Player: "..self.sInfo.name);
								GameTooltip:Show();
							elseif self.sInfo.isQuest then
								if self.sInfo.questID and not IsShiftKeyDown() then
									GameTooltip:ClearLines();
									GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
									GameTooltip:SetHyperlink("quest:"..self.sInfo.questID)
									GameTooltip:Show();								
								elseif self.sInfo.questID and IsShiftKeyDown() then
									
									local sChkf = 0
									
									if not QuestSync.storeObjectiveInfo[self.lineID] then
										QuestSync.storeObjectiveInfo[self.lineID] = {}
									end

									--check for spam stuff
									if QuestSync.storeObjectiveInfo[self.lineID].timer then
										if (GetTime() - QuestSync.storeObjectiveInfo[self.lineID].timer) >= 15 then
											QuestSync.storeObjectiveInfo[self.lineID].timer = GetTime()
											sChkf = 1
										end
									else
										QuestSync.storeObjectiveInfo[self.lineID].timer = GetTime()
										sChkf = 1
									end
									
									--send a request
									if sChkf == 1 then
										local sGet = QuestSync:CheckUser(self.currentPlayer, 4);
										if sGet then
											if QuestSync:UserOnline(self.currentPlayer) then
												QuestSync:Send_Msg("13;"..self.currentPlayer..";"..UnitName("player")..";"..self.sInfo.name.."@"..self.sInfo.questID.."@"..self.lineID, self.currentPlayer);
											else
												QuestSync:Print("ERROR! Player ["..QuestSync:AddColor("33FF66",self.currentPlayer).."] is not online.");
											end
										else
											QuestSync:Print("ERROR! Player ["..QuestSync:AddColor("33FF66",self.currentPlayer).."] is not in friends list, party, raid, or guild.");
										end
										
										sChkf = 0
									end
									
									--display tooltip stored
									QuestSync:ShowObjective_Tooltip(self.lineID);
								
								else
									GameTooltip:ClearLines();
									GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
									GameTooltip:SetText("Unknown");
									GameTooltip:Show();								
								end
							end
						end
					end
				end
				
			end)

			qsyncFrame_Scroll.BarFrames[i]:SetScript("OnLeave",function(self)
				
			   	GameTooltip:Hide()
			end)
				
			--hide at start
			qsyncFrame_Scroll.BarFrames[i]:Hide();

		end	

		qsyncFrame_Scroll.Update = function(self)
			QuestSync:UpdateScroll(QuestSyncMainScrollFrame);
		end
	
		qsyncFrame_Scroll:SetScript("OnVerticalScroll", function (self, offset)
			FauxScrollFrame_OnVerticalScroll(self, offset, 16, qsyncFrame_Scroll.Update) 
		end)

		qsyncFrame_Scroll:SetScript("OnShow", function(self)
			--do nothing for now
		end)
	
	----END SCROLL FRAME----
	
	----CREATE TRACKER FRAME----
	qsyncTrackFrame = CreateFrame("Frame", "QuestSyncTrackFrame", UIParent, "GameTooltipTemplate");
	qsyncTrackFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
	qsyncTrackFrame:EnableMouse(true);
	qsyncTrackFrame:SetToplevel(true);
	qsyncTrackFrame:SetMovable(true);
	qsyncTrackFrame:SetFrameStrata("LOW");
	qsyncTrackFrame:SetWidth(200);
	qsyncTrackFrame:SetHeight(100);
	
		if self.db.profile.trackingColors then
			qsyncTrackFrame:SetBackdropColor(self.db.profile.trackingColors[1], self.db.profile.trackingColors[2], self.db.profile.trackingColors[3], self.db.profile.trackingColors[4]);
		end

			local closeButton_qsyncTrackFrame = CreateFrame("Button", nil, qsyncTrackFrame, "UIPanelCloseButton");
			closeButton_qsyncTrackFrame:SetPoint("TOPRIGHT", qsyncTrackFrame, "TOPRIGHT", 1, 0);

			closeButton_qsyncTrackFrame:SetScript("OnClick", function() 
					HideUIPanel(QuestSyncTrackFrame)
			end)

			qsyncTrackFrame.closeButton = closeButton_qsyncTrackFrame;


			local colorButton_qsyncTrackFrame = CreateFrame("Button", nil, qsyncTrackFrame, "OptionsButtonTemplate");
			colorButton_qsyncTrackFrame:SetWidth(20);
			colorButton_qsyncTrackFrame:SetHeight(20);
			colorButton_qsyncTrackFrame:SetPoint("TOPRIGHT", qsyncTrackFrame, "TOPRIGHT", -30, -6);
			colorButton_qsyncTrackFrame:SetText("C");

			colorButton_qsyncTrackFrame:SetScript("OnClick", function() 

				if not QuestSync.db.profile.trackingColors then
					QuestSync.db.profile.trackingColors = {0,0,0,1.0};
				end
				
				QuestSync.SaveColor = QuestSync.db.profile.trackingColors;
				
				ColorPickerFrame.hasOpacity = true;
				ColorPickerFrame.opacity = QuestSync.db.profile.trackingColors[4];
				ColorPickerFrame.previousValues = {QuestSync.db.profile.trackingColors[1], QuestSync.db.profile.trackingColors[2], QuestSync.db.profile.trackingColors[3]};
				ColorPickerFrame:SetColorRGB(QuestSync.db.profile.trackingColors[1], QuestSync.db.profile.trackingColors[2], QuestSync.db.profile.trackingColors[3]);
				
				ColorPickerFrame.func = function()
					local A = OpacitySliderFrame:GetValue();
					local R,G,B = ColorPickerFrame:GetColorRGB();
					QuestSync.db.profile.trackingColors = {R,G,B,A};
					QuestSyncTrackFrame:SetBackdropColor(R,G,B,A);
					QuestSyncTrackFrame_XPFrame:SetBackdropColor(R,G,B,A);
				end
				ColorPickerFrame.cancelFunc = function()
					QuestSyncTrackFrame:SetBackdropColor(QuestSync.SaveColor[1], QuestSync.SaveColor[2], QuestSync.SaveColor[3], QuestSync.SaveColor[4]);
					QuestSyncTrackFrame_XPFrame:SetBackdropColor(QuestSync.SaveColor[1], QuestSync.SaveColor[2], QuestSync.SaveColor[3], QuestSync.SaveColor[4]);
					QuestSync.db.profile.trackingColors = QuestSync.SaveColor;
					QuestSync.SaveColor = nil;
				end

				ColorPickerFrame:Show();
				

			end)

			qsyncTrackFrame.colorButton = colorButton_qsyncTrackFrame;
			

		--we have to add the remaining bars because the template for the tooltip only goes to 9
		qsyncTrackFrame.extraBars = {};
		for i=9, 30 do
			qsyncTrackFrame.extraBars[i] = {};
			qsyncTrackFrame.extraBars[i].textL = qsyncTrackFrame:CreateFontString("$parentTextLeft"..i, "ARTWORK", "GameTooltipText");
			qsyncTrackFrame.extraBars[i].textL:SetPoint("TOPLEFT", "QuestSyncTrackFrameTextLeft"..(i-1), "BOTTOMLEFT", 0, -2);
			qsyncTrackFrame.extraBars[i].textL:Hide();
			
			qsyncTrackFrame.extraBars[i].textR = qsyncTrackFrame:CreateFontString("$parentTextRight"..i, "ARTWORK", "GameTooltipText");
			qsyncTrackFrame.extraBars[i].textR:SetPoint("RIGHT", "QuestSyncTrackFrameTextLeft"..i, "LEFT", 40, 0);
			qsyncTrackFrame.extraBars[i].textR:Hide();
			
		end

		qsyncTrackFrame:SetScript("OnLoad", function()
				GameTooltip_OnLoad();
				QuestSyncTrackFrame:SetPadding(16);
				QuestSync:ClearTracker();
			end)
			
		qsyncTrackFrame:SetScript("OnShow", function()
		
				QuestSync:ClearTracker();
				
				QuestSyncTrackFrameTextLeft2:SetText("QuestSync Tracker");
				QuestSyncTrackFrameTextLeft2:Show();

				QuestSyncTrackFrameTextLeft3:SetText("Tracking Player: "..QuestSync.db.profile.trackingPlayer); --empty space
				QuestSyncTrackFrameTextLeft3:SetTextColor(255/255, 255/255, 153/255);
				QuestSyncTrackFrameTextLeft3:Show(); --empty space


				QuestSyncTrackFrameTextLeft4:SetText(" "); --empty space
				QuestSyncTrackFrameTextLeft4:Show(); --empty space

				if QuestSync.db.profile.trackingColors then
					QuestSyncTrackFrame:SetBackdropColor(QuestSync.db.profile.trackingColors[1], QuestSync.db.profile.trackingColors[2], QuestSync.db.profile.trackingColors[3], QuestSync.db.profile.trackingColors[4]);
				end
				
				QuestSync:FixTracker();
				
			end)
		
		--add dragging
		qsyncTrackFrame:SetScript("OnMouseDown", function(frame) 
				if not IsControlKeyDown() and not QuestSync.db.profile.lock_windows then
					frame.isMoving = true
					frame:StartMoving();
				
				elseif (IsControlKeyDown() and IsMouseButtonDown("LeftButton")) then
				
					local sGet = QuestSync:CheckUser(self.db.profile.trackingPlayer, 4);
					if sGet then
						if QuestSync:UserOnline(self.db.profile.trackingPlayer) then
							--we attach a one at the end, to toggle off the alert message to the user that their history has been requested
							QuestSync:Send_Msg("4;"..self.db.profile.trackingPlayer..";"..UnitName("player")..";1", self.db.profile.trackingPlayer);
						else
							QuestSync:Print("ERROR! Player ["..QuestSync:AddColor("33FF66",self.db.profile.trackingPlayer).."] is not online.");
						end
					else
						QuestSync:Print("ERROR! Player ["..QuestSync:AddColor("33FF66",self.db.profile.trackingPlayer).."] is not in friends list, party, raid, or guild.");
					end
					
				end
			end)

		qsyncTrackFrame:SetScript("OnMouseUp", function(frame, arg1) 

				if( frame.isMoving and not IsControlKeyDown() and not QuestSync.db.profile.lock_windows) then

					frame.isMoving = nil
					frame:StopMovingOrSizing()

					self:SaveLayout(frame:GetName());
				end

			end)
			
		
		qsyncTrackFrame:SetScript("OnEnter", function(self)
				if (self:IsVisible()) then
					GameTooltip:ClearLines();
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
					GameTooltip:SetText("Press CTRL + Left Click\nfor user Quest Log.");
					GameTooltip:Show();								
				end

			end)
	
		qsyncTrackFrame:SetScript("OnLeave", function(self)
					GameTooltip:Hide();
			end)
			
			
		---------------------------
		--MAKE THE XP BAR

		qsyncTrackFrame.XPFrame = CreateFrame("Frame", "QuestSyncTrackFrame_XPFrame", qsyncTrackFrame, "GameTooltipTemplate");
		qsyncTrackFrame.XPFrame:SetPoint("BOTTOMLEFT", qsyncTrackFrame, "BOTTOMLEFT", 0, -28);
		qsyncTrackFrame.XPFrame:EnableMouse(true);
		qsyncTrackFrame.XPFrame:SetToplevel(true);
		qsyncTrackFrame.XPFrame:SetMovable(true);
		qsyncTrackFrame.XPFrame:SetFrameStrata("LOW");
		qsyncTrackFrame.XPFrame:SetWidth(200);
		qsyncTrackFrame.XPFrame:SetHeight(30);

		qsyncTrackFrame.XPFrame:SetScript("OnShow", function()
				QuestSyncTrackFrame_XPFrame:SetWidth(QuestSyncTrackFrame:GetWidth());

				if QuestSync.db.profile.trackingColors then
					QuestSyncTrackFrame_XPFrame:SetBackdropColor(QuestSync.db.profile.trackingColors[1], QuestSync.db.profile.trackingColors[2], QuestSync.db.profile.trackingColors[3], QuestSync.db.profile.trackingColors[4]);
				end
				
			end)
			
		qsyncTrackFrame.XPFrame:SetScript("OnMouseDown", function(frame)
				if not QuestSync.db.profile.lock_windows then
					QuestSyncTrackFrame.isMoving = true
					QuestSyncTrackFrame:StartMoving();
				end
			end)

		qsyncTrackFrame.XPFrame:SetScript("OnMouseUp", function(frame) 

				if( QuestSyncTrackFrame.isMoving and not QuestSync.db.profile.lock_windows) then

					QuestSyncTrackFrame.isMoving = nil
					QuestSyncTrackFrame:StopMovingOrSizing()

					self:SaveLayout("QuestSyncTrackFrame");

				end

			end)
			
		qsyncTrackFrame.XPFrame:SetScript("OnEnter", function(self)
			if (self:IsVisible()) then
				QuestSync:ShowXPTooltip();
			end
		end)

		qsyncTrackFrame.XPFrame:SetScript("OnLeave",function(self)
			GameTooltip:Hide()
		end)
			
			
		qsyncTrackFrame.XPFrame.barXP = CreateFrame("StatusBar", "QuestSyncTrackFrame_XPFrame_XPBar", qsyncTrackFrame.XPFrame);
		qsyncTrackFrame.XPFrame.barXP:SetFrameLevel(2);
		qsyncTrackFrame.XPFrame.barXP:ClearAllPoints();
		qsyncTrackFrame.XPFrame.barXP:SetHeight(10);
		qsyncTrackFrame.XPFrame.barXP:SetWidth(QuestSyncTrackFrame:GetWidth() - 20);
		qsyncTrackFrame.XPFrame.barXP:SetPoint("CENTER", qsyncTrackFrame.XPFrame, "CENTER", 0, 0);
		qsyncTrackFrame.XPFrame.barXP:SetStatusBarTexture("Interface\\AddOns\\QuestSync\\images\\AceBarFrames");
		qsyncTrackFrame.XPFrame.barXP:SetStatusBarColor(0, 1, 0, 0.5);
		qsyncTrackFrame.XPFrame.barXP:SetMinMaxValues(0,100);
		qsyncTrackFrame.XPFrame.barXP:SetValue(0);
		qsyncTrackFrame.XPFrame.barXP:EnableMouse(true);
		
				
		qsyncTrackFrame.XPFrame.barREST = CreateFrame("StatusBar", "QuestSyncTrackFrame_XPFrame_RestXPBar", qsyncTrackFrame.XPFrame);
		qsyncTrackFrame.XPFrame.barREST:SetFrameLevel(qsyncTrackFrame.XPFrame.barXP:GetFrameLevel() - 1);
		qsyncTrackFrame.XPFrame.barREST:ClearAllPoints();
		qsyncTrackFrame.XPFrame.barREST:SetHeight(10);
		qsyncTrackFrame.XPFrame.barREST:SetWidth(QuestSyncTrackFrame:GetWidth() - 20);
		qsyncTrackFrame.XPFrame.barREST:SetPoint("CENTER", qsyncTrackFrame.XPFrame, "CENTER", 0, 0);
		qsyncTrackFrame.XPFrame.barREST:SetStatusBarTexture("Interface\\AddOns\\QuestSync\\images\\AceBarFrames");
		qsyncTrackFrame.XPFrame.barREST:SetStatusBarColor(1, 0.2, 1, 0.5);
		qsyncTrackFrame.XPFrame.barREST:SetMinMaxValues(0,100);
		qsyncTrackFrame.XPFrame.barREST:SetValue(0);
		qsyncTrackFrame.XPFrame.barREST:EnableMouse(true);
		
				
		--Bar Background
		qsyncTrackFrame.XPFrame.barBG = CreateFrame("StatusBar", "QuestSyncTrackFrame_XPFrame_BarBG", qsyncTrackFrame.XPFrame);
		qsyncTrackFrame.XPFrame.barBG:SetFrameLevel(qsyncTrackFrame.XPFrame.barREST:GetFrameLevel() - 1);
		qsyncTrackFrame.XPFrame.barBG:ClearAllPoints();
		qsyncTrackFrame.XPFrame.barBG:SetHeight(10);
		qsyncTrackFrame.XPFrame.barBG:SetWidth(QuestSyncTrackFrame:GetWidth() - 20);
		qsyncTrackFrame.XPFrame.barBG:SetPoint("CENTER", qsyncTrackFrame.XPFrame, "CENTER", 0, 0);
		qsyncTrackFrame.XPFrame.barBG:SetStatusBarTexture("Interface\\AddOns\\QuestSync\\images\\AceBarFrames");
		qsyncTrackFrame.XPFrame.barBG:SetStatusBarColor(100/255, 100/255, 100/255, 0.5);
		qsyncTrackFrame.XPFrame.barBG:SetMinMaxValues(0,100);
		qsyncTrackFrame.XPFrame.barBG:SetValue(100);
		qsyncTrackFrame.XPFrame.barBG:EnableMouse(true);
		
			
		qsyncTrackFrame.XPFrame:Show();
	
		--END THE XP BAR
		---------------------------
			
			
	----END TRACKER FRAME----

	qsyncFrame:SetScript("OnShow", function()
		QuestSync:Debug(1, "Frame Shown");
		--PlaySound("igMainMenuOpen");
		QuestSync:Refresh();
		end)

	qsyncFrame:SetScript("OnHide", function() 
		end)
		
	--In case you get confused qsyncFrame actually equals 
	--QuestSyncMainFrame since we created that frame in qsyncFrame variable.
	--I have no idea why some people get confused with that.
	qsyncFrame.header = qsyncFrame_Header;
	qsyncFrame.scroll = qsyncFrame_Scroll;
	qsyncFrame.tooltip = qsyncFrame_Tooltip;
	qsyncFrame.tracker = qsyncTrackFrame;
	
	--don't show unless the player asks it too
	qsyncFrame:Hide();
	
	local createFrameTimer = CreateFrame("Frame", "QuestSyncTimer");
	createFrameTimer:SetScript("OnUpdate", function(self, elapsed)
		QuestSync:OnUpdate(elapsed);
	end)


	--restore saved layout
	self:RestoreLayout("QuestSyncMainFrame");
	self:RestoreLayout("QuestSyncTrackFrame");

end

function QuestSync:ClearTracker()
	if not QuestSyncTrackFrame then
		return
	end
	
	for i = 1, 30 do

		if getglobal("QuestSyncTrackFrameTextLeft"..i) then
			getglobal("QuestSyncTrackFrameTextLeft"..i):SetText(nil);
			if i > 1 then
				getglobal("QuestSyncTrackFrameTextLeft"..i):SetFont( ( GameFontNormalSmall:GetFont() ), 10);
				getglobal("QuestSyncTrackFrameTextLeft"..i):SetHeight(1);
				getglobal("QuestSyncTrackFrameTextLeft"..i):SetWidth(250);
			end
			getglobal("QuestSyncTrackFrameTextLeft"..i):Hide();
		end
		if getglobal("QuestSyncTrackFrameTextRight"..i) then
			getglobal("QuestSyncTrackFrameTextRight"..i):SetText(nil);
			if i > 1 then
				getglobal("QuestSyncTrackFrameTextRight"..i):SetFont( ( GameFontNormalSmall:GetFont() ), 10);
				getglobal("QuestSyncTrackFrameTextRight"..i):SetHeight(1);
				getglobal("QuestSyncTrackFrameTextRight"..i):SetWidth(250);
			end
			getglobal("QuestSyncTrackFrameTextRight"..i):Hide();
		end
	end
end

function QuestSync:FixTracker()
	if not QuestSyncTrackFrame then
		return
	end
		
	local gHeight = 0;
	local gWidth = 0;
	local storeBar = 0;
		
	--adjusts the height of the tracker for the bars
	for i = 1, 30 do
		if getglobal("QuestSyncTrackFrameTextLeft"..i) then
			if getglobal("QuestSyncTrackFrameTextLeft"..i):GetText() then
				if getglobal("QuestSyncTrackFrameTextLeft"..i):IsVisible() then
					getglobal("QuestSyncTrackFrameTextLeft"..i):SetHeight(10);
				else
					getglobal("QuestSyncTrackFrameTextLeft"..i):SetHeight(1);
					getglobal("QuestSyncTrackFrameTextLeft"..i):SetWidth(0);
				end
				
				storeBar = i; --store the last bar used
				gHeight = gHeight + getglobal("QuestSyncTrackFrameTextLeft"..i):GetHeight();
			else
				getglobal("QuestSyncTrackFrameTextLeft"..i):SetHeight(1);
				getglobal("QuestSyncTrackFrameTextLeft"..i):SetWidth(0);
			end
			
			--since we originally set the width to 250 each time we clear
			--that gives us a better understanding of how big the string is if less then 250 in size
			
			if getglobal("QuestSyncTrackFrameTextLeft"..i):GetStringWidth() < 250 then
				getglobal("QuestSyncTrackFrameTextLeft"..i):SetWidth(getglobal("QuestSyncTrackFrameTextLeft"..i):GetStringWidth());
			else
				getglobal("QuestSyncTrackFrameTextLeft"..i):SetWidth(250);
			end
			
			if (getglobal("QuestSyncTrackFrameTextLeft"..i):GetWidth() > gWidth) then
				gWidth = getglobal("QuestSyncTrackFrameTextLeft"..i):GetWidth();
			end
			
		end
		if getglobal("QuestSyncTrackFrameTextRight"..i) then
			if getglobal("QuestSyncTrackFrameTextRight"..i):GetText() then
				if getglobal("QuestSyncTrackFrameTextRight"..i):IsVisible() then
					getglobal("QuestSyncTrackFrameTextRight"..i):SetHeight(10);
				else
					getglobal("QuestSyncTrackFrameTextRight"..i):SetHeight(1);
					getglobal("QuestSyncTrackFrameTextRight"..i):SetWidth(0);
				end
				
				storeBar = i; --store the last bar used
				gHeight = gHeight + getglobal("QuestSyncTrackFrameTextRight"..i):GetHeight();
			else
				getglobal("QuestSyncTrackFrameTextRight"..i):SetHeight(1);
				getglobal("QuestSyncTrackFrameTextRight"..i):SetWidth(0);
			end
			
			--since we originally set the width to 250 each time we clear
			--that gives us a better understanding of how big the string is if less then 250 in size
			
			if getglobal("QuestSyncTrackFrameTextRight"..i):GetStringWidth() < 250 then
				getglobal("QuestSyncTrackFrameTextRight"..i):SetWidth(getglobal("QuestSyncTrackFrameTextRight"..i):GetStringWidth());
			else
				getglobal("QuestSyncTrackFrameTextRight"..i):SetWidth(250);
			end
			
			if (getglobal("QuestSyncTrackFrameTextRight"..i):GetWidth() > gWidth) then
				gWidth = getglobal("QuestSyncTrackFrameTextRight"..i):GetWidth();
			end
		end
	end--for i = 1, 30 do
	
	local newHeight = (storeBar * 12.5) + 15;
	
	if newHeight < 80 then
		QuestSyncTrackFrame:SetHeight(80);
	else
		QuestSyncTrackFrame:SetHeight(newHeight);
	end
	
	if (gWidth > 170 and gWidth < 280) then
		QuestSyncTrackFrame:SetWidth(gWidth + 30);
		QuestSyncTrackFrame_XPFrame:SetWidth(gWidth + 30);
	elseif (gWidth >= 280) then
		QuestSyncTrackFrame:SetWidth(280);
		QuestSyncTrackFrame_XPFrame:SetWidth(280);
	elseif (gWidth < 170) then
		QuestSyncTrackFrame:SetWidth(200);
		QuestSyncTrackFrame_XPFrame:SetWidth(200);
	end
	
	self:FixXPBar()
	
	self:RestoreLayout("QuestSyncTrackFrame");
	
end

function QuestSync:FixXPBar()

	local total = QuestSyncMainFrame.tracker:GetWidth() - 20;

	QuestSyncMainFrame.tracker.XPFrame.barBG:SetWidth(total);
	QuestSyncMainFrame.tracker.XPFrame.barBG:ClearAllPoints();
	QuestSyncMainFrame.tracker.XPFrame.barBG:SetPoint("CENTER", QuestSyncMainFrame.tracker.XPFrame, "CENTER", 0, 0);

	QuestSyncMainFrame.tracker.XPFrame.barXP:SetWidth(total);
	QuestSyncMainFrame.tracker.XPFrame.barXP:ClearAllPoints();
	QuestSyncMainFrame.tracker.XPFrame.barXP:SetPoint("CENTER", QuestSyncMainFrame.tracker.XPFrame, "CENTER", 0, 0);

	QuestSyncMainFrame.tracker.XPFrame.barREST:SetWidth(total);
	QuestSyncMainFrame.tracker.XPFrame.barREST:ClearAllPoints();
	QuestSyncMainFrame.tracker.XPFrame.barREST:SetPoint("CENTER", QuestSyncMainFrame.tracker.XPFrame, "CENTER", 0, 0);

end

function QuestSync:ShowXPTooltip()

	if not self.saveXPData then
		GameTooltip:ClearLines();
		GameTooltip:SetOwner(QuestSyncTrackFrame_XPFrame, "ANCHOR_LEFT");
		GameTooltip:SetText("Unknown");
		GameTooltip:Show();
		return;
	end

	local toLevelXP = self.saveXPData.nextXP - self.saveXPData.currXP;
	local toLevelXPPercent = math.floor((self.saveXPData.currXP / self.saveXPData.nextXP) * 100)

		GameTooltip:ClearLines();
		GameTooltip:SetOwner(QuestSyncTrackFrame_XPFrame, "ANCHOR_LEFT");
		
		GameTooltip:AddLine(" "); --empty line
		
		if self.saveXPData.restXP > 0 then
			local xpExPercent
			
			if self.saveXPData.restXP - toLevelXP > 0 then
				xpExPercent = math.floor(((self.saveXPData.restXP - toLevelXP) / self.saveXPData.nextXP) * 100)
			else
				xpExPercent = math.floor((self.saveXPData.restXP / self.saveXPData.nextXP) * 100)
			end
			
			if self.saveXPData.restXP - toLevelXP > 0 then
				xpExPercent = "100% + "..xpExPercent
			end
			
			GameTooltip:AddDoubleLine("|cffffffffRested XP|r", "|cffffff66"..self.saveXPData.restXP.."|r |cffA2D96F("..xpExPercent.."%)|r");
		end
		
	
		GameTooltip:AddDoubleLine("|cffffffffCurrent XP|r", "|cffffff66"..self.saveXPData.currXP.."/"..self.saveXPData.nextXP.."|r |cffA2D96F("..toLevelXPPercent.."%)|r");
		GameTooltip:AddDoubleLine("|cffffffffTo Level|r", "|cffffff66"..toLevelXP.."|r |cffA2D96F("..math.floor((self.saveXPData.nextXP - self.saveXPData.currXP) / self.saveXPData.nextXP * 100).."%)|r");
		GameTooltip:AddLine(" ");
		GameTooltip:AddDoubleLine("|cffffffffPercent To Level|r", "|cffA2D96F"..math.floor((self.saveXPData.nextXP - self.saveXPData.currXP) / self.saveXPData.nextXP * 100).."%|r");
		
		GameTooltip:AddLine(" "); --empty line
            
	GameTooltip:Show();
end

function QuestSync:ShowObjective_Tooltip(barLineID)
	if not barLineID then return end
	if not QuestSync.storeObjectiveInfo[barLineID] then return end
	if not QuestSync.storeObjectiveInfo[barLineID].objText then return end
	
	if QuestSyncMainFrame:IsVisible() and getglobal("QuestSyncScrollBar"..barLineID):IsVisible() then
		GameTooltip:ClearLines();
		GameTooltip:SetOwner(getglobal("QuestSyncScrollBar"..barLineID), "ANCHOR_LEFT");
		
		
		GameTooltip:SetHyperlink("quest:"..QuestSync.storeObjectiveInfo[barLineID].questID)
		GameTooltip:AddLine("----------");
		GameTooltip:AddLine(QuestSync:AddColor("33FF99","QuestSync:").." ["..QuestSync:AddColor("FC5252",self.currentPlayer).."]");
		GameTooltip:AddLine(QuestSync.storeObjectiveInfo[barLineID].objText.."\n\nNext Update: ".. (15 - math.floor(GetTime() - QuestSync.storeObjectiveInfo[barLineID].timer)).. " secs");
		GameTooltip:Show();
									
		--GameTooltip:SetText(QuestSync.storeObjectiveInfo[barLineID].name.."\n"..QuestSync.storeObjectiveInfo[barLineID].objText.."\n\nNext Update: ".. (15 - math.floor(GetTime() - QuestSync.storeObjectiveInfo[barLineID].timer)).. " secs");
		--GameTooltip:Show();
	end
end

function QuestSync:UpdateScroll(frame)
	if self.gettingUsers then
		return
	end
	
	if not self.sInfo then
		return
	end
	
	if not QuestSyncTrackUser:IsVisible() then
		if not self.isItUsers then
			QuestSyncTrackUser:Show();
		end
	else
		if self.isItUsers then
			GameTooltip:Hide();
			QuestSyncTrackUser:Hide();
		end
	end
	
	if self.totalQuestsDL and not self.isItUsers then
		QuestSyncMainFrameText:SetText("["..QuestSync:AddColor("FC5252",self.currentPlayer).."] Quest Log: "..QuestSync:AddColor("A2D96F", (self.totalQuestsDL.."/25") ));
		QuestSyncMainFrameText:Show();
	else
		QuestSyncMainFrameText:Hide();
	end
	
	self:DebugC(1, "Scroll Update: %s Table Count: %s", frame:GetName(), table.getn(self.sInfo));

	local QSYNC_MAX_ENTRIES		= table.getn(self.sInfo);
	local QSYNC_LINE_HEIGHT 	= 16;
	local QSYNC_LINES_SHOWN 	= 23;

	local lineIndex; -- 1 through QSYNC_MAX_ENTRIES of our window to scroll
	local linePlus_Offset; -- an index into our data calculated from the scroll offset
	
	-- 50 is max entries, 5 is number of lines, 16 is pixel height of each line
	FauxScrollFrame_Update(frame, QSYNC_MAX_ENTRIES, QSYNC_LINES_SHOWN, QSYNC_LINE_HEIGHT);

	for lineIndex=1, QSYNC_LINES_SHOWN do

		linePlus_Offset = lineIndex + FauxScrollFrame_GetOffset(frame);

		if linePlus_Offset <= QSYNC_MAX_ENTRIES then

			frame.BarFrames[lineIndex].sInfo = self.sInfo[linePlus_Offset];
			frame.BarFrames[lineIndex].currentPlayer = self.currentPlayer

			if self.sInfo[linePlus_Offset].header then
				frame.BarFrames[lineIndex].text:SetText(self.sInfo[linePlus_Offset].name);
				frame.BarFrames[lineIndex].text:SetTextColor(255/255, 255/255, 255/255);
			elseif not self.sInfo[linePlus_Offset].isQuest then
				frame.BarFrames[lineIndex].text:SetText("  "..self.sInfo[linePlus_Offset].name);
				frame.BarFrames[lineIndex].text:SetTextColor(255/255, 255/255, 128/255);
			else

				if self.sInfo[linePlus_Offset].level then
					frame.BarFrames[lineIndex].text:SetText("  ["..self.sInfo[linePlus_Offset].level.."] "..self.sInfo[linePlus_Offset].name);
					local color = GetQuestDifficultyColor(tonumber(self.sInfo[linePlus_Offset].level));
					frame.BarFrames[lineIndex].text:SetTextColor(color.r, color.g, color.b);
				else
					frame.BarFrames[lineIndex].text:SetText("  "..self.sInfo[linePlus_Offset].name);
					frame.BarFrames[lineIndex].text:SetTextColor(255/255, 255/255, 128/255);
				end
			end
			frame.BarFrames[lineIndex].text:Show();

			if self.sInfo[linePlus_Offset].onQuest then
				frame.BarFrames[lineIndex].texture:SetTexture("Interface\\AddOns\\QuestSync\\images\\Shared");
				frame.BarFrames[lineIndex].texture:Show();
			elseif self.sInfo[linePlus_Offset].compQuest then
				frame.BarFrames[lineIndex].texture:SetTexture("Interface\\AddOns\\QuestSync\\images\\Completed");
				frame.BarFrames[lineIndex].texture:Show();
			else
				frame.BarFrames[lineIndex].texture:Hide();
			end

			frame.BarFrames[lineIndex]:Show();
			
		else
			if frame.BarFrames[lineIndex].sInfo then
				frame.BarFrames[lineIndex].sInfo = nil;
			end
			frame.BarFrames[lineIndex].text:SetText(nil);
			frame.BarFrames[lineIndex].text:Hide();
			frame.BarFrames[lineIndex].texture:Hide();
			frame.BarFrames[lineIndex]:Hide();
		end
	end
	
	--for some reason sometimes the scrollframe dissapears
	if not QuestSyncMainScrollFrame:IsVisible() then
		QuestSyncMainScrollFrame:Show()
	end

	self:Debug(1, "Scroll Update Finished");
end


function QuestSync:Refresh()
	QuestSync:Debug(1, "Main Refresh");
	FauxScrollFrame_SetOffset(QuestSyncMainScrollFrame, 0);
	getglobal("QuestSyncMainScrollFrameScrollBar"):SetValue(0);
	GameTooltip:Hide();
	QuestSyncTrackUser:Hide();
	QuestSyncMainFrameText:Hide();
	
	if not QuestSyncMainFrame.doNotRefresh then
		self:GetUsers();
	else
		--empty it
		QuestSyncMainFrame.doNotRefresh = nil
	end
	self:UpdateScroll(QuestSyncMainScrollFrame);
end

function QuestSync:ProcessTracker(qTitle, objString, qCompleted)
	if not qTitle or not objString or not qCompleted then
		return
	end
	
	local sBarCount = 6; --because we use 5 to setup the top so the next bar is 6
	
	objString = strsub(objString, 1, string.len(objString) - 1); --take away one at the end
	
	self:ClearTracker();
	
	QuestSyncTrackFrameTextLeft2:SetText("QuestSync Tracker");
	QuestSyncTrackFrameTextLeft2:Show();
	
	QuestSyncTrackFrameTextLeft3:SetText("Tracking Player: "..self.db.profile.trackingPlayer); --empty space
	QuestSyncTrackFrameTextLeft3:SetTextColor(255/255, 255/255, 153/255);
	QuestSyncTrackFrameTextLeft3:Show();

	QuestSyncTrackFrameTextLeft4:SetText(" "); --empty space
	QuestSyncTrackFrameTextLeft4:Show();

	--title
	QuestSyncTrackFrameTextLeft5:SetText(qTitle);
	QuestSyncTrackFrameTextLeft5:Show();
	QuestSyncTrackFrameTextLeft5:SetText(self:AddColor("FF9900",qTitle)); --add color

	local q = {self:_split(objString, "{")};

	--do objectives
	if q then
	
		QuestSyncTrackFrame:SetHeight((table.getn(q) * 10) * 2); --generic
	
		for k, v in pairs(q) do
		
			local w = {self:_split(v, "~")};
		
			if w[1] and w[1] ~= "" and sBarCount <= 30 then --tooltip only has 30 bars
				
				if w[2] and tonumber(w[2]) == 0 then --not finished
					
					if getglobal("QuestSyncTrackFrameTextLeft"..sBarCount) then
						getglobal("QuestSyncTrackFrameTextLeft"..sBarCount):SetText("-"..w[1]);
						getglobal("QuestSyncTrackFrameTextLeft"..sBarCount):SetTextColor(1, 1, 1);
						getglobal("QuestSyncTrackFrameTextLeft"..sBarCount):Show();
					end
					
				elseif w[2] and tonumber(w[2]) == 1 then --completed
				
					if getglobal("QuestSyncTrackFrameTextLeft"..sBarCount) then
						getglobal("QuestSyncTrackFrameTextLeft"..sBarCount):SetText("-"..w[1]);
						getglobal("QuestSyncTrackFrameTextLeft"..sBarCount):SetTextColor(162/255, 217/255, 111/255);
						getglobal("QuestSyncTrackFrameTextLeft"..sBarCount):Show();
					end
				end
				
				sBarCount = sBarCount + 1;
			end
		end
		
		--show completed or failed if given
		if tonumber(qCompleted) and tonumber(qCompleted) ~= 0 and sBarCount <= 30 then
			
			if tonumber(qCompleted) > 0 then
				--completed
				if getglobal("QuestSyncTrackFrameTextLeft"..sBarCount) then
					getglobal("QuestSyncTrackFrameTextLeft"..sBarCount):SetText("-=Completed=-");
					getglobal("QuestSyncTrackFrameTextLeft"..sBarCount):SetTextColor(128/255, 1, 0);
					getglobal("QuestSyncTrackFrameTextLeft"..sBarCount):Show();
				end
			else
				--failed
				if getglobal("QuestSyncTrackFrameTextLeft"..sBarCount) then
					getglobal("QuestSyncTrackFrameTextLeft"..sBarCount):SetText("-=Failed=-");
					getglobal("QuestSyncTrackFrameTextLeft"..sBarCount):SetTextColor(1, 72/255, 72/255);
					getglobal("QuestSyncTrackFrameTextLeft"..sBarCount):Show();
				end
			end
		
			sBarCount = sBarCount + 1;
		end
		
	end
	
	self:FixTracker();
	
	--fix the xp bars
	local total = QuestSyncTrackFrame:GetWidth() - 20;

	QuestSyncMainFrame.tracker.XPFrame.barBG:SetWidth(total);
	QuestSyncMainFrame.tracker.XPFrame.barBG:ClearAllPoints();
	QuestSyncMainFrame.tracker.XPFrame.barBG:SetPoint("CENTER", QuestSyncMainFrame.tracker.XPFrame, "CENTER", 0, 0);

	QuestSyncMainFrame.tracker.XPFrame.barXP:SetWidth(total);
	QuestSyncMainFrame.tracker.XPFrame.barXP:ClearAllPoints();
	QuestSyncMainFrame.tracker.XPFrame.barXP:SetPoint("CENTER", QuestSyncMainFrame.tracker.XPFrame, "CENTER", 0, 0);

	QuestSyncMainFrame.tracker.XPFrame.barREST:SetWidth(total);
	QuestSyncMainFrame.tracker.XPFrame.barREST:ClearAllPoints();
	QuestSyncMainFrame.tracker.XPFrame.barREST:SetPoint("CENTER", QuestSyncMainFrame.tracker.XPFrame, "CENTER", 0, 0);

	if not QuestSyncTrackFrame:IsVisible() then
		QuestSyncTrackFrame:Show();
	end
			
end

function QuestSync:Send_Msg(msg, sender)
	if not msg then
		return
	end
	
	if not sender then
		sender = UnitName("player");
	else
		--lets try to use SendAddonMessage (we don't want to check for Friends since SendAddonMessage
		--since it only accepts, party, raid, and guild
		local sGet = self:CheckUser(sender, 3);

		if sGet then
			ChatThrottleLib:SendAddonMessage("NORMAL", "QUESTSYNC", msg, sGet);
			--return cause we used SendAddonMessage
			sGet = nil;
			return true;
		end
		sGet = nil;
	end

	id, name = GetChannelName(self.QS_Global);
	if (id > 0 and name ~= nil) then
		ChatThrottleLib:SendChatMessage("NORMAL", "QUESTSYNC", msg, "CHANNEL", nil, id)
	end
	
end

function QuestSync:GetCurrentQuestID(sIndex)

	if (not sIndex) then
		local index = GetQuestLogSelection();
		if not index then return nil; end

		local link = GetQuestLink(index);
		if not link then return nil; end

		return tonumber(link:match(":(%d+):"))
	else
		if GetQuestLogSelection() ~= sIndex then
			--you never know ;) Lots of mods manipulate quest material
			SelectQuestLogEntry(sIndex);
		end
		
		local link = GetQuestLink(sIndex);
		if not link then return nil; end
		return tonumber(link:match(":(%d+):"))
	end

end

function QuestSync:Get_QuestString()
	if (self.runningQuestUpdate) then
		return
	end
	
	self.runningQuestUpdate = true; --start the spam trigger
	
	local sString = "";
	local questSelected= GetQuestLogSelection();

		local collapsed = self:Store_CollaspedQuests();
		ExpandQuestHeader(0);

	for i = 1, GetNumQuestLogEntries() do 

		local qTitle, qLevel, qTag, group, isHeader = GetQuestLogTitle(i); 

		if isHeader then
			sString = sString.."H@"..qTitle.."~";
		else
			local sQuid = self:GetCurrentQuestID(i);
			
			sString = sString..qLevel.."@"..sQuid.."@"..qTitle.."~";
		end
	
	end
	
		self:Restore_CollaspedQuests(collapsed);
		SelectQuestLogEntry(questSelected); --reset old selection

		self.runningQuestUpdate = false; --end the spam trigger
	
	if sString == "" then
		return nil;
	else
		--fix the string to remove last pipe
		sString = strsub(sString, 1, string.len(sString) - 1);
		
		return sString;
	end
end

function QuestSync:Get_QuestObjectives(questName, questID, barLineID)
	if not questName then return end
	if not questID then return end
	if not barLineID then return end
	
	if (self.runningQuestUpdate) then
		return
	end
	
	self.runningQuestUpdate = true; --start the spam trigger
	
	local sString = "";
	local questSelected= GetQuestLogSelection();

		local collapsed = self:Store_CollaspedQuests();
		ExpandQuestHeader(0);

	for i = 1, GetNumQuestLogEntries() do 

		local qTitle, qLevel, qTag, group, isHeader = GetQuestLogTitle(i); 

		if not isHeader then
		
			local sQuid = self:GetCurrentQuestID(i);
			
			--check for same quest
			if sQuid == questID and qTitle == questName then
				
				--start with title
				sString = qTitle.."@"..questID.."@"..barLineID.."@";
			
				local leadB = GetNumQuestLeaderBoards(i);
				local doOnceOkay = 0

				--sometimes there aren't any objectives but just text
				--so return the text as 2 for text
				if leadB <= 0 then
					local questDescription, questObjectives = GetQuestLogQuestText();
					sString = sString..questObjectives.."{2";
				else

					for z = 1, leadB do
						local iText, iType, iFinished = GetQuestLogLeaderBoard(z, i);
						if not iFinished then
							if doOnceOkay == 0 then
								sString = sString..iText.."{0";
								doOnceOkay = 1
							else
								sString = sString.."}"..iText.."{0";
							end
						else
							if doOnceOkay == 0 then
								sString = sString..iText.."{1";
								doOnceOkay = 1
							else
								sString = sString.."}"..iText.."{1";
							end
						end
					end
				end
			
				--no need to continue the loop
				break;
			
			end
			
		end
	
	end
	
		self:Restore_CollaspedQuests(collapsed);
		SelectQuestLogEntry(questSelected); --reset old selection

		self.runningQuestUpdate = false; --end the spam trigger
	
	if sString == "" then
		return nil;
	else
		return sString;
	end
end

function QuestSync:Store_CollaspedQuests()
	local collapsed = {};
	for i=1, MAX_QUESTLOG_QUESTS do
		local qTitle, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily = GetQuestLogTitle(i);
		if ( isCollapsed ) then
			table.insert(collapsed, qTitle);
		end
	end

	return collapsed;
end

function QuestSync:Restore_CollaspedQuests(collaspedList)
	if not collaspedList then
		return
	end
	for i=1, MAX_QUESTLOG_QUESTS do
		local qTitle, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily = GetQuestLogTitle(i);
		
		for k, v in pairs(collaspedList) do
			if v == qTitle then
				CollapseQuestHeader(i);
			end
		end
	end

	return collapsed;
end

function QuestSync:SaveLayout(frame)

	local opt = self.db.profile.frame_positions[frame];

	if not opt then 
		self.db.profile.frame_positions[frame] = self.defaults.profile.frame_positions[frame];
		opt = self.db.profile.frame_positions[frame];
	end

	local point,relativeTo,relativePoint,xOfs,yOfs = getglobal(frame):GetPoint()
	opt.point = point
	opt.relativePoint = relativePoint
	opt.xOfs = xOfs
	opt.yOfs = yOfs
end

function QuestSync:RestoreLayout(frame)

	local f = getglobal(frame);
	
	local opt = self.db.profile.frame_positions[frame];
	
	if not opt then 
		self.db.profile.frame_positions[frame] = self.defaults.profile.frame_positions[frame];
		opt = self.db.profile.frame_positions[frame];
	end

	f:ClearAllPoints()
	f:SetPoint( opt.point, UIParent, opt.relativePoint, opt.xOfs, opt.yOfs )
	
	if self.db.profile.trackingPlayer and self.db.profile.trackingPlayer ~= "" then
		if not QuestSyncTrackFrame:IsVisible() then
			QuestSyncTrackFrame:Show();
		end
	end
end

function QuestSync:_split(s,p,n)
	if (type(s) ~= "string") then return nil; end
	    local l,sp,ep = {},0
	    while(sp) do
		sp,ep=strfind(s,p)
		if(sp) then
		    tinsert(l,strsub(s,1,sp-1))
		    s=strsub(s,ep+1)
		else
		    tinsert(l,s)
		    break
		end
		if(n) then n=n-1 end
		if(n and (n==0)) then tinsert(l,s) break end
	    end
	    return unpack(l)
end

function QuestSync:toChunks(text, chunkSize)	
	local list = {};
	local pos = 0;
	local lastPos;
	local currentPos;


	for i=1, string.len(text), 1 do
		if(pos > chunkSize) then
			pos = 0;
			tinsert(list, string.sub(text, lastPos, i));
			lastPos = i+1; --add to last position
		else
			pos = pos + 1;
		end

		if(lastPos == nil or lastPos == 0) then
			lastPos = i;
		end
	end

	--if some chance the list did not finish to imput the end lets add it
	if(pos ~= 0 or pos > 0 and pos < chunkSize) then
		--from lastpos to end
		if(string.len(string.sub(text, lastPos)) < chunkSize) then
			tinsert(list, string.sub(text, lastPos));
		end
	end
	
	return list
end

function QuestSync:AddColor(hexColor, text)
	if not text then text = "nil" end
	return "|cff" .. tostring(hexColor or 'ffffff') .. tostring(text) .. "|r"
end

function QuestSync:DebugC(level, ...)
	local arg = { ... }
	for i,v in ipairs(arg) do
		if i > 1 then
			--we are doing this so we don't colorize the message prefix
			arg[i] = self:AddColor("A2D96F",v);
		end
	end
	--now that we colorized everything send it to the original debug format from Dongle by unpacking
	self:DebugF(level, unpack(arg));
end

function QuestSync:FrameReset()
	QuestSyncMainFrame:ClearAllPoints()
	QuestSyncMainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	QuestSyncMainFrame:Show()
	
	QuestSyncTrackFrame:ClearAllPoints()
	QuestSyncTrackFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	QuestSyncTrackFrame:Show()
end

function QuestSync:ToggleShow()
	if QuestSyncMainFrame:IsVisible() then
		QuestSyncMainFrame:Hide();
	else
		QuestSyncMainFrame:Show();
	end
end

function QuestSync:ToggleLock()
	if self.db.profile.lock_windows then
		self.db.profile.lock_windows = false
		self:Print("Windows are now unlocked.")
	else
		self.db.profile.lock_windows = true
		self:Print("Windows are now locked.")
	end
end

function QuestSync:ToggleDebug()
	local level
	if self.db.profile.debug then
		self:Print("Debug messages have been disabled.")
	else
		self:Print("Debug messages have been enabled.")
		level = 1		
	end

	self.db.profile.debug = not self.db.profile.debug 
	self:EnableDebug(level)
end

function QuestSync:ShowTracking()
	if self.db.profile.trackingPlayer and self.db.profile.trackingPlayer ~= "" then
		self:Print("Tracking player ["..QuestSync:AddColor("00FF66",self.db.profile.trackingPlayer).."].");
	else
		self:Print("You are not tracking any player.");
	end
end

function QuestSync:StopTracking()
	if self.db.profile.trackingPlayer and self.db.profile.trackingPlayer ~= "" then
		self.db.profile.trackingPlayer = "";
		QuestSyncTrackFrame:Hide();
		GameTooltip:Hide();
		self:Print("You are no longer tracking any players.");
	else
		self:Print("You are not tracking any player.");
	end
end

QuestSync = DongleStub("Dongle-1.1"):New("QuestSync", QuestSync)