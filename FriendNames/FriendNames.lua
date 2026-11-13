-- FriendNames: show your own nicknames for friends on raid/party frames, in chat
-- (guild, party, raid, say, whispers) and on the guild roster.
-- Nicknames attach to a Battle.net account (all of that friend's characters) or to
-- a single character. Display only: nobody else sees them and nothing you send changes.

local ADDON = ...
local PREFIX = "|cff33ccff[FriendNames]|r "

local db
local guidCache = {}   -- guid -> nickname (found only)
local missCache = {}   -- guid -> time of last failed lookup (retried after 10s)
local nameToGuid = {}  -- "Name-Realm" -> guid, learned from chat events

local function Print(msg) print(PREFIX .. msg) end
local function IsSecret(v) return issecretvalue and issecretvalue(v) end

local function Sanitize(text)
    text = text:gsub("|", ""):gsub("%c", "")
    text = text:match("^%s*(.-)%s*$")
    return text:sub(1, 24)
end

local function NormKey(name)
    if not name or IsSecret(name) then return nil end
    if not name:find("-", 1, true) then
        local realm = GetNormalizedRealmName and GetNormalizedRealmName()
        if realm and realm ~= "" then name = name .. "-" .. realm end
    end
    return name
end

local function ShortName(name)
    return (name:gsub("%-.*$", ""))
end

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------

local function Resolve(guid, key)
    local g = (guid and not IsSecret(guid)) and guid or nil
    if g and guidCache[g] then return guidCache[g] end
    if g and missCache[g] and GetTime() - missCache[g] < 10 then return nil end

    local nick
    if g and C_BattleNet and C_BattleNet.GetAccountInfoByGUID then
        local ok, info = pcall(C_BattleNet.GetAccountInfoByGUID, g)
        if ok and info and info.battleTag then nick = db.bnet[info.battleTag] end
    end
    if not nick and key then nick = db.chars[key] end

    if nick then
        nick = Sanitize(nick)
        if nick == "" then nick = nil end
    end
    if g then
        if nick then guidCache[g] = nick else missCache[g] = GetTime() end
    end
    return nick
end

local function CharKey(unit)
    local name, realm = UnitFullName(unit)
    if not name or IsSecret(name) then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return NormKey(name)
end

local function BattleTag(unit)
    local guid = UnitGUID(unit)
    if not guid or IsSecret(guid) then return nil end
    if not (C_BattleNet and C_BattleNet.GetAccountInfoByGUID) then return nil end
    local ok, info = pcall(C_BattleNet.GetAccountInfoByGUID, guid)
    return ok and info and info.battleTag or nil
end

local function GetNickname(unit)
    if not unit or not UnitIsPlayer(unit) then return nil end
    return Resolve(UnitGUID(unit), CharKey(unit))
end

-- Text shown in chat / guild roster. showChar adds the real character name.
local function Display(nick, name)
    if db.showChar and name then return nick .. " (" .. ShortName(name) .. ")" end
    return nick
end

---------------------------------------------------------------------------
-- Raid / party frames
---------------------------------------------------------------------------

local hooked = false

local function Apply(frame)
    if not db or not frame or frame:IsForbidden() or not frame.name then return end
    local unit = frame.unit or frame.displayedUnit
    if not unit then return end
    local nick = GetNickname(unit)
    if nick then
        frame.name:SetText(nick)
    elseif frame.fnApplied then
        local n = UnitName(unit)
        if n and not IsSecret(n) then frame.name:SetText(n) end
    end
    frame.fnApplied = nick and true or nil
end

if type(CompactUnitFrame_UpdateName) == "function" then
    hooksecurefunc("CompactUnitFrame_UpdateName", Apply)
    hooked = true
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------

local CHAT_EVENTS = {
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
}

-- Learns which GUID belongs to a sender, without touching the message.
local function ChatFilter(_, _, ...)
    local author, guid = select(2, ...), select(12, ...)
    if type(author) == "string" and not IsSecret(author) and guid and not IsSecret(guid) and guid ~= "" then
        local key = NormKey(author)
        if key then nameToGuid[key] = guid end
    end
    return false
end

local function RewriteChat(msg)
    if not db or type(msg) ~= "string" or IsSecret(msg) then return msg end
    local out = msg:gsub("(|Hplayer:([^:|]+)[^|]*|h)%[([^%]]*)%]|h", function(prefix, who, shown)
        local key = NormKey(who)
        local nick = key and Resolve(nameToGuid[key], key)
        if not nick then return nil end -- leave unchanged
        local display = Display(nick, who)
        local short = ShortName(who)
        local pattern = short:gsub("%p", "%%%0")
        local newShown, n = shown:gsub(pattern, function() return display end, 1)
        if n == 0 then newShown = display end
        return prefix .. "[" .. newShown .. "]|h"
    end)
    return out
end

local function WrapChatFrame(cf)
    if not cf or cf.fnWrapped or not cf.AddMessage then return end
    cf.fnWrapped = true
    local orig = cf.AddMessage
    cf.AddMessage = function(self, msg, ...)
        return orig(self, RewriteChat(msg), ...)
    end
end

local function WrapAllChatFrames()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        WrapChatFrame(_G["ChatFrame" .. i])
    end
end

---------------------------------------------------------------------------
-- Guild roster (classic-style GuildFrame; best effort)
---------------------------------------------------------------------------

local guildHooked = false

local function GuildApply()
    if not db or not GetGuildRosterInfo then return end
    for i = 1, (GUILDMEMBERS_TO_DISPLAY or 13) do
        local button = _G["GuildFrameButton" .. i]
        local label = _G["GuildFrameButton" .. i .. "Name"]
        if button and label and button:IsShown() and button.guildIndex then
            local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(button.guildIndex)
            if name and not IsSecret(name) then
                local nick = Resolve(guid, NormKey(name))
                if nick then label:SetText(Display(nick, name)) end
            end
        end
    end
end

if type(GuildStatus_Update) == "function" then
    hooksecurefunc("GuildStatus_Update", GuildApply)
    guildHooked = true
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function RefreshAll()
    wipe(guidCache)
    wipe(missCache)
    if hooked then
        local f = EnumerateFrames()
        while f do
            if not f:IsForbidden() and f.name and f.unit and f.GetName then
                local n = f:GetName()
                if n and n:find("^Compact") then Apply(f) end
            end
            f = EnumerateFrames(f)
        end
    end
    if guildHooked then GuildApply() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("BN_FRIEND_INFO_CHANGED")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        FriendNamesDB = FriendNamesDB or {}
        db = FriendNamesDB
        db.bnet  = db.bnet  or {}
        db.chars = db.chars or {}

        for _, e in ipairs(CHAT_EVENTS) do ChatFrame_AddMessageEventFilter(e, ChatFilter) end
        WrapAllChatFrames()
        if type(FCF_OpenTemporaryWindow) == "function" then
            hooksecurefunc("FCF_OpenTemporaryWindow", WrapAllChatFrames)
        end
        if type(FCF_OpenNewWindow) == "function" then
            hooksecurefunc("FCF_OpenNewWindow", WrapAllChatFrames)
        end
    elseif db then
        C_Timer.After(0.5, RefreshAll)
    end
end)

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------

local function Debug()
    Print("Interface/build: " .. tostring(select(4, GetBuildInfo())))
    Print("Raid frame hook: " .. tostring(hooked))
    Print("Guild roster hook (GuildStatus_Update): " .. tostring(guildHooked))
    Print("GuildFrameButton1Name exists: " .. tostring(_G.GuildFrameButton1Name ~= nil))
    Print("CommunitiesFrame exists (not handled yet): " .. tostring(_G.CommunitiesFrame ~= nil))
    Print("ChatFrame1 wrapped: " .. tostring(ChatFrame1 and ChatFrame1.fnWrapped or false))
    Print("Battle.net lookup: " .. tostring(C_BattleNet and C_BattleNet.GetAccountInfoByGUID ~= nil))
    Print("Show character name beside nickname: " .. tostring(db.showChar and true or false))
    if UnitExists("target") then
        Print("Target char key: " .. tostring(CharKey("target")))
        Print("Target BattleTag: " .. tostring(BattleTag("target")))
    end
    local count = 0
    local ok, err = pcall(function()
        local f = EnumerateFrames()
        while f do
            local n = not f:IsForbidden() and f.GetName and f:GetName()
            if n and n:find("^Compact") and f.unit then count = count + 1 end
            f = EnumerateFrames(f)
        end
    end)
    if not ok then Print("Frame scan error: " .. tostring(err)) end
    Print("Compact unit frames found: " .. count)
    Print("In group: " .. tostring(IsInGroup()) .. ", raid: " .. tostring(IsInRaid()))
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function Help()
    Print("/fn set <nickname>   - nickname your target (BattleTag if a BNet friend, else character)")
    Print("/fn char <nickname>  - character-only nickname for your target")
    Print("/fn clear            - remove nickname from your target")
    Print("/fn alts             - toggle showing the character name beside the nickname in chat/guild")
    Print("/fn list | refresh | debug")
end

SLASH_FRIENDNAMES1 = "/fn"
SLASH_FRIENDNAMES2 = "/friendnames"
SlashCmdList.FRIENDNAMES = function(input)
    if not db then return end
    local cmd, rest = input:match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()

    if cmd == "set" or cmd == "char" then
        rest = Sanitize(rest)
        if rest == "" then return Help() end
        if not UnitExists("target") or not UnitIsPlayer("target") then
            return Print("Target a player first.")
        end
        local tag = (cmd == "set") and BattleTag("target")
        if tag then
            db.bnet[tag] = rest
            Print(("Saved %s -> %s (all their characters)."):format(tag, rest))
        else
            local key = CharKey("target")
            if not key then return Print("Couldn't read that character's name.") end
            db.chars[key] = rest
            Print(("Saved %s -> %s (this character only)."):format(key, rest))
        end
        RefreshAll()

    elseif cmd == "clear" then
        if not UnitExists("target") then return Print("Target a player first.") end
        local tag, key = BattleTag("target"), CharKey("target")
        if tag then db.bnet[tag] = nil end
        if key then db.chars[key] = nil end
        Print("Cleared.")
        RefreshAll()

    elseif cmd == "alts" then
        db.showChar = not db.showChar
        Print("Character name beside nickname: " .. (db.showChar and "ON" or "OFF"))
        RefreshAll()

    elseif cmd == "list" then
        for k, v in pairs(db.bnet)  do Print(k .. " -> " .. v .. " (BNet)") end
        for k, v in pairs(db.chars) do Print(k .. " -> " .. v) end

    elseif cmd == "refresh" then
        RefreshAll()

    elseif cmd == "debug" then
        Debug()

    else
        Help()
    end
end
