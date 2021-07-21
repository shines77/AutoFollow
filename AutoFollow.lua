
local ADDON, Addon = ...

-- Lua String functions
local string_find, string_sub, string_gsub, string_match, string_gmatch = string.find, string.sub, string.gsub, string.match, string.gmatch
local string_byte, string_char, string_len = string.byte, string.char, string.len
local string_format = string.format

-- Lua APIs
local table_concat, tostring, select = table.concat, tostring, select
local type, pairs, error = type, pairs, error
local math_max = math.max

-- WoW APIs
local _G = _G

local AutoFollow = CreateFrame("frame", nil, UIParent)

AutoFollow.Enabled = true
AutoFollow.NotifyByWhisper = false

AutoFollow.COMMAND = {
    On = 'on',
    Off = 'off',
    Follow = 'follow',
    Start = 'start',
    Stop = 'stop',
    Switch = 'switch',
    Status = 'status',
    Whisper = 'whisper',
    Party = 'party',
}

AutoFollow.FOLLOW_COMMAND = {
    Follow = '[Follow]',
    Start = '[Follow Start]',
    Stop = '[Follow Stop]',
}

---- LOCAL
local COMMAND = AutoFollow.COMMAND
local COMMAND_KEYS = tInvert{ COMMAND.On, COMMAND.Off, COMMAND.Follow, COMMAND.Start, COMMAND.Stop, COMMAND.Switch, COMMAND.Status, COMMAND.Whisper, COMMAND.Party }

local FOLLOW_COMMAND = AutoFollow.FOLLOW_COMMAND
local FOLLOW_COMMAND_KEYS = tInvert{ FOLLOW_COMMAND.Follow, FOLLOW_COMMAND.Start, FOLLOW_COMMAND.Stop }

local function nils(n, ...)
    if n > 1 then
        return nil, nils(n - 1, ...)
    elseif n == 1 then
        return nil, ...
    else
        return ...
    end
end

--- Retreive one or more space-separated arguments from a string.
-- Treats quoted strings and itemlinks as non-spaced.
-- @param str The raw argument string
-- @param numArgs How many arguments to get (default 1)
-- @param startPos Where in the string to start scanning (default  1)
-- @return Returns arg1, arg2, ..., nextposition\\
-- Missing arguments will be returned as nils. 'nextposition' is returned as 1e9 at the end of the string.
function AutoFollow:GetArgs(str, numArgs, startPos)
    numArgs = numArgs or 1
    startPos = math_max(startPos or 1, 1)

    local pos = startPos

    -- find start of new arg
    pos = string_find(str, "[^ ]", pos)
    if not pos then -- whoops, end of string
        return nils(numArgs, 1e9)
    end

    if numArgs < 1 then
        return pos
    end

    -- quoted or space separated? find out which pattern to use
    local delim_or_pipe
    local ch = string_sub(str, pos, pos)
    if ch == '"' then
        pos = pos + 1
        delim_or_pipe = '([|"])'
    elseif ch == "'" then
        pos = pos + 1
        delim_or_pipe = "([|'])"
    else
        delim_or_pipe = "([| ])"
    end

    startPos = pos

    while true do
        -- find delimiter or hyperlink
        local ch, _
        pos, _, ch = string_find(str, delim_or_pipe, pos)

        if not pos then break end

        if ch == "|" then
            -- some kind of escape
            if string_sub(str, pos, pos + 1) == "|H" then
                -- It's a |H....|hhyper link!|h
                pos = string_find(str, "|h", pos + 2)   -- first |h
                if not pos then break end

                pos = string_find(str, "|h", pos + 2)   -- second |h
                if not pos then break end
            elseif string_sub(str, pos, pos + 1) == "|T" then
                -- It's a |T....|t  texture
                pos = string_find(str, "|t", pos + 2)
                if not pos then break end
            end

            pos = pos + 2 -- skip past this escape (last |h if it was a hyperlink)

        else
            -- found delimiter, done with this arg
            return string_sub(str, startPos, pos - 1), AutoFollow:GetArgs(str, numArgs - 1, pos + 1)
        end

    end

    -- search aborted, we hit end of string. return it all as one argument. (yes, even if it's an unterminated quote or hyperlink)
    return string_sub(str, startPos), nils(numArgs - 1, 1e9)
end

function AutoFollow:ParseArgs(...)
    local command
    local opts = {}

    for i = 1, select('#', ...) do
        local cmd = tostring(select(i, ...)):lower()
        if COMMAND_KEYS[cmd] then
            command = cmd
            break
        end
    end

    local isUnknownCmd = false
    local needDisplay = true
    
    if not command then
        AutoFollow.Enabled = not AutoFollow.Enabled
    else
        if command == COMMAND.On then
            AutoFollow.Enabled = true
        elseif command == COMMAND.Off then
            AutoFollow.Enabled = false
        elseif command == COMMAND.Follow then
            AutoFollow:SendChatMessage(FOLLOW_COMMAND.Follow)
            needDisplay = false
        elseif command == COMMAND.Start then
            AutoFollow:SendChatMessage(FOLLOW_COMMAND.Start)
            needDisplay = false
        elseif command == COMMAND.Stop then
            AutoFollow:SendChatMessage(FOLLOW_COMMAND.Stop)
            needDisplay = false
        elseif command == COMMAND.Switch then
            AutoFollow.Enabled = not AutoFollow.Enabled
        elseif command == COMMAND.Status then
            -- Display current status
        elseif command == COMMAND.Whisper then
            AutoFollow.NotifyByWhisper = true
        elseif command == COMMAND.Party then
            AutoFollow.NotifyByWhisper = false
        else
            -- Unkown command
            isUnknownCmd = true
        end
    end

    if needDisplay then
        AutoFollow:DisplayStatus(command, isUnknownCmd)
    end

    AutoFollowDB.Enabled = AutoFollow.Enabled
    AutoFollowDB.NotifyByWhisper = AutoFollow.NotifyByWhisper

    return opts
end

function AutoFollow:OnChatSlash(text)
    local args = {}
    local cmd, offset
    while true do
        cmd, offset = self:GetArgs(text, nil, offset)
        if not cmd then
            break
        end

        tinsert(args, cmd)
    end

    AutoFollow:ParseArgs(unpack(args))
end

-- set default variable
function AutoFollow:LoadSettings()
    -- Set a flag as event will repeat
    if AutoFollowDB == nil then
        AutoFollowDB = AutoFollowDB or {}
        AutoFollowDB.Enabled = AutoFollow.Enabled
        AutoFollowDB.NotifyByWhisper = AutoFollow.NotifyByWhisper
    else
        if AutoFollowDB.Enabled then
            AutoFollow.Enabled = AutoFollowDB.Enabled
        else
            AutoFollowDB.Enabled = AutoFollow.Enabled
        end
        if AutoFollowDB.NotifyByWhisper then
            AutoFollow.NotifyByWhisper = AutoFollowDB.NotifyByWhisper
        else
            AutoFollowDB.NotifyByWhisper = AutoFollow.NotifyByWhisper
        end
    end
end

function AutoFollow:DisplayStatus(command, isUnknownCmd)
    if not isUnknownCmd then
        local switch, whisper, text
        if AutoFollow.Enabled then
            switch = "启用"
        else
            switch = "禁用"
        end
        if AutoFollow.NotifyByWhisper then
            whisper = "启用"
        else
            whisper = "禁用"
        end
        text = string_format("自动跟随，当前状态：%s，密语通知：%s", switch, whisper)
        DEFAULT_CHAT_FRAME:AddMessage(text)
    else
        DEFAULT_CHAT_FRAME:AddMessage("自动跟随，未知命令：" .. command)
    end
end

function AutoFollow:SendChatMessage(text, player)
    if player ~= nil then
        SendChatMessage(text, "WHISPER", nil, player)
    else
        if UnitInRaid("player") then
            SendChatMessage(text, "RAID", nil)
        elseif UnitInParty("player") then
            SendChatMessage(text, "PARTY", nil)
        else
            SendChatMessage(text, "SAY", nil)
        end
    end
end

-- To prevent multipul loading
function AutoFollow:OnEvent(event, arg1, _, _, _, arg5, _, _, _, _, _, _, _, _)
    if event == "ADDON_LOADED" then
        -- Init
        AutoFollow:LoadSettings()
        -- UnregisterEvent
        AutoFollow:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- Init
        AutoFollow:LoadSettings()
    else
        if AutoFollow.Enabled then
            if event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" or event == "CHAT_MSG_SAY" or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_YELL" then
                if arg1 == FOLLOW_COMMAND.Follow or arg1 == FOLLOW_COMMAND.Start then
                    if UnitIsUnit(arg5, "player") then
                        print("|cff22ff22其他人开始跟随我 ...|r")
                        FollowUnit("player")
                        --RunMacroText("/use 条纹霜刃豹缰绳")
                    else
                        print("|cff22ff22开始跟随：|r" .. arg5 .." |cff22ff22...|r")
                        if AutoFollow.NotifyByWhisper or (not UnitInRaid("player") and not UnitInParty("player")) then
                            AutoFollow:SendChatMessage("我正在跟随你.", arg5)
                        else
                            AutoFollow:SendChatMessage("开始跟随：" .. arg5)
                        end
                        FollowUnit(arg5)
                    end
                elseif arg1 == FOLLOW_COMMAND.Stop then
                    if UnitIsUnit(arg5, "player") then
                        print("|cffff2222停止其他人跟随我 ...|r")
                    else
                        print("|cffff2222停止跟随 ...|r")
                        if AutoFollow.NotifyByWhisper or (not UnitInRaid("player") and not UnitInParty("player"))  then
                            AutoFollow:SendChatMessage("我已停止跟随你.", arg5)
                        else
                            AutoFollow:SendChatMessage("停止跟随：" .. arg5)
                        end
                    end
                    FollowUnit("player")
                end
            end
        end
    end
end

-- Registe event and set script
AutoFollow:RegisterEvent("ADDON_LOADED")
AutoFollow:RegisterEvent("PLAYER_LOGIN")
AutoFollow:RegisterEvent("CHAT_MSG_SAY")
AutoFollow:RegisterEvent("CHAT_MSG_YELL")
AutoFollow:RegisterEvent("CHAT_MSG_PARTY")
AutoFollow:RegisterEvent("CHAT_MSG_PARTY_LEADER")
AutoFollow:RegisterEvent("CHAT_MSG_RAID")
AutoFollow:RegisterEvent("CHAT_MSG_RAID_LEADER")

AutoFollow:SetScript("OnEvent", AutoFollow.OnEvent)

SLASH_AUTOFOLLOW1 = "/autofollow"
SLASH_AUTOFOLLOW2 = "/af"
SlashCmdList["AUTOFOLLOW"] = function(text)
    AutoFollow:OnChatSlash(text)
    --InterfaceOptionsFrame_OpenToCategory("AutoFollow")
end
