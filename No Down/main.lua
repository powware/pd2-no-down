NoDown = NoDown or {}
NoDown.default_settings = {
    buy_no_down = false,
    confirmed_peers = {},
    search_no_down_lobbies = 1,
    disable_uncustody = 1,
    timeout = 45
}
NoDown.color = Color(1, 0.1, 1, 0.5)

NoDown._mod_path = ModPath
NoDown._options_menu_file = NoDown._mod_path .. "menu/options.json"
NoDown._save_path = SavePath
NoDown._save_file = NoDown._save_path .. "no_down.json"
NoDown.toggle_one_down_lobby = nil

local function deep_copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deep_copy(orig_key)] = deep_copy(orig_value)
        end
        setmetatable(copy, deep_copy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function NoDown:Setup()
    if not self.settings then
        self:Load()
    end
end

-- load settings from file
function NoDown:Load()
    self.settings = deep_copy(self.default_settings)
    local file = io.open(self._save_file, "r")
    if file then
        local data = file:read("*a")
        if data then
            local decoded_data = json.decode(data)

            if decoded_data then
                for key, value in pairs(self.settings) do
                    if decoded_data[key] ~= nil then
                        self.settings[key] = deep_copy(decoded_data[key])
                    end
                end
            end
        end
        file:close()
    end
end

-- save settings to file
function NoDown:Save()
    local file = io.open(self._save_file, "w+")
    if file then
        file:write(json.encode(self.settings))
        file:close()
    end
end

function NoDown.SyncGameSettingsNoDown()
    local data = Global.game_settings.no_down and "true" or "false"
    _G.LuaNetworking:SendToPeers("sync_game_settings_no_down", data)
end

function NoDown.AnnounceNoDown(peer)
    if peer then
        if peer._has_no_down then
            return
        end

        peer:send_after_load("send_chat_message", ChatManager.GAME,
            Global.game_settings.no_down and managers.localization:text("no_down_announcement_enabled") or
                managers.localization:text("no_down_announcement_disabled"))
    else
        local peers = managers.network:session() and managers.network:session():peers()
        if not peers then
            return
        end

        for _, peer in pairs(peers) do
            if peer and not peer:is_host() then
                NoDown.AnnounceNoDown(peer)
            end
        end
    end
end

function NoDown.SendDescription(peer)
    peer:send_after_load("send_chat_message", ChatManager.GAME, managers.localization:text("no_down_description"))
    peer:send_after_load("send_chat_message", ChatManager.GAME,
        managers.localization:text("no_down_confirmation_request_1") .. NoDown.settings.timeout ..
            managers.localization:text("no_down_confirmation_request_2"))
end

function NoDown.RequestConfirmation(peer)
    if peer then
        if NoDown.IsConfirmed(peer) then
            return
        end

        NoDown.SendDescription(peer)

        managers.chat:_receive_message(ChatManager.GAME, managers.localization:to_upper_text("no_down_modifier_name"),
            peer:name() .. " was requested to confirm.", NoDown.color)
    else
        local peers = managers.network:session() and managers.network:session():peers()
        if not peers then
            return
        end

        for _, peer in pairs(peers) do
            if peer and not peer:is_host() then
                NoDown.RequestConfirmation(peer)
            end
        end
    end
end

function NoDown.AddConfirmationTimeout(peer)
    if peer then
        if NoDown.IsConfirmed(peer) then
            return
        end

        local peer_id = peer:id()

        DelayedCalls:Add("NoDown_ConfirmationTimeoutFor" .. tostring(peer_id), NoDown.settings.timeout, function()
            local temp_peer = managers.network:session() and managers.network:session():peer(peer_id)
            if temp_peer and Global.game_settings.no_down and not NoDown.IsConfirmed(temp_peer) then
                managers.chat:_receive_message(ChatManager.GAME,
                    managers.localization:to_upper_text("no_down_modifier_name"), temp_peer:name() .. " has timed out.",
                    NoDown.color)
                managers.network:session():remove_peer(temp_peer, temp_peer:id(), "auth_fail")
            end
        end)
    else
        local peers = managers.network:session() and managers.network:session():peers()
        if not peers then
            return
        end

        for _, peer in pairs(peers) do
            if peer and not peer:is_host() then
                NoDown.AddConfirmationTimeout(peer)
            end
        end
    end
end

function NoDown.IsConfirmed(peer)
    return NoDown.settings.confirmed_peers[peer:user_id()] ~= nil
end

function NoDown.Confirm(peer, has_no_down)
    if NoDown.IsConfirmed(peer) then
        return
    end

    NoDown.settings.confirmed_peers[peer:user_id()] = true
    NoDown:Save()

    if not has_no_down then
        peer:send_after_load("send_chat_message", ChatManager.GAME,
            managers.localization:text("no_down_confirmation_confirmation"))

        managers.chat:_receive_message(ChatManager.GAME, managers.localization:to_upper_text("no_down_modifier_name"),
            peer:name() .. " has confirmed.", NoDown.color)
    end

    if peer._loading_halted then
        managers.network:session():finish_set_peer_loading_state(peer)
    end
end

function NoDown.ApplyNoDown()
    if managers.hud and managers.hud._hud_mission_briefing then
        managers.hud._hud_mission_briefing:apply_no_down()
    end

    if managers.hud and managers.hud._hud_statsscreen then
        managers.hud._hud_statsscreen:apply_no_down()
    end

    if managers.menu_component then
        if managers.menu_component._ingame_contract_gui then
            managers.menu_component._ingame_contract_gui:apply_no_down()
        end
        if managers.menu_component._contract_gui then
            managers.menu_component._contract_gui:apply_no_down()
        end
    end
end

Hooks:Add("LocalizationManagerPostInit", "NoDown_LocalizationManagerPostInit", function(loc)
    for _, filename in pairs(file.GetFiles(NoDown._mod_path .. "loc")) do
        local language = filename:match("^(.*).txt$")
        if language and Idstring(language) and Idstring(language):key() == SystemInfo:language():key() then
            loc:load_localization_file(NoDown._mod_path .. "loc/" .. filename)
            return
        end
    end

    loc:load_localization_file(NoDown._mod_path .. "loc/english.txt")
end)

NoDown:Setup()
