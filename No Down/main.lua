NoDown = NoDown or {}
NoDown.default_settings = {
    confirmed_peers = {},
    search_no_down_lobbies = 1,
    disable_uncustody = 1
}
NoDown.color = Color(1, 0.1, 1, 0.5)

NoDown._mod_path = ModPath
NoDown._options_menu_file = NoDown._mod_path .. "menu/options.json"
NoDown._save_path = SavePath
NoDown._save_file = NoDown._save_path .. "no_down.json"
NoDown.toggle_one_downs = {}
NoDown.toggle_no_downs = {}
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

    self.SetupHooks()
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

        peer:send_after_load(
            "send_chat_message",
            ChatManager.GAME,
            Global.game_settings.no_down and managers.localization:text("no_down_announcement_enabled") or
                managers.localization:text("no_down_announcement_disabled")
        )
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

function NoDown.RequestConfirmation(peer)
    if peer then
        if NoDown.IsConfirmed(peer) then
            return
        end

        peer:send_after_load("send_chat_message", ChatManager.GAME, managers.localization:text("no_down_description"))
        peer:send_after_load(
            "send_chat_message",
            ChatManager.GAME,
            managers.localization:text("no_down_confirmation_request")
        )

        managers.chat:_receive_message(
            ChatManager.GAME,
            managers.localization:to_upper_text("no_down_modifier_name"),
            peer:name() .. " was requested to confirm.",
            NoDown.color
        )
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

        DelayedCalls:Add(
            "NoDown_ConfirmationTimeoutFor" .. tostring(peer_id),
            30,
            function()
                local temp_peer = managers.network:session() and managers.network:session():peer(peer_id)
                if temp_peer and Global.game_settings.no_down and not NoDown.IsConfirmed(temp_peer) then
                    managers.chat:_receive_message(
                        ChatManager.GAME,
                        managers.localization:to_upper_text("no_down_modifier_name"),
                        temp_peer:name() .. " has timed out.",
                        NoDown.color
                    )
                    managers.network:session():remove_peer(temp_peer, temp_peer:id())
                end
            end
        )
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

function NoDown.RemindConfirmation(peer)
    peer:send_after_load("send_chat_message", ChatManager.GAME, managers.localization:text("no_down_description"))
    peer:send_after_load(
        "send_chat_message",
        ChatManager.GAME,
        managers.localization:text("no_down_confirmation_request")
    )
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
        peer:send_after_load(
            "send_chat_message",
            ChatManager.GAME,
            managers.localization:text("no_down_confirmation_confirmation")
        )

        managers.chat:_receive_message(
            ChatManager.GAME,
            managers.localization:to_upper_text("no_down_modifier_name"),
            peer:name() .. " has confirmed.",
            NoDown.color
        )
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

function NoDown.SetupHooks()
    if RequiredScript == "lib/network/handlers/unitnetworkhandler" then
        Hooks:PostHook(
            UnitNetworkHandler,
            "sync_player_movement_state",
            "NoDown_UnitNetworkHandler_sync_player_movement_state",
            function(self, unit, state, down_time, unit_id_str, sender)
                if not self._verify_gamestate(self._gamestate_filter.any_ingame) then
                    return
                end

                local peer = self._verify_sender(sender)

                if not peer or not alive(unit) then
                    return
                end

                if not peer:is_host() and (not alive(peer:unit()) or peer:unit():key() ~= unit:key()) then
                    return
                end

                local local_peer = managers.network:session():local_peer()

                if local_peer:unit() and unit:key() == local_peer:unit():key() then
                    return
                end

                if Network:is_server() and Global.game_settings.no_down and state == "bleed_out" then
                    local member_downed,
                        member_dead,
                        health,
                        used_deployable,
                        used_cable_ties,
                        used_body_bags,
                        hostages_killed,
                        respawn_penalty,
                        old_plr_entry = peer:_get_old_entry()

                    peer:send_queued_sync(
                        "spawn_dropin_penalty",
                        true,
                        true,
                        health,
                        false,
                        used_cable_ties,
                        used_body_bags
                    )
                end
            end
        )
    elseif RequiredScript == "lib/units/beings/player/playerdamage" then
        Hooks:PreHook(
            PlayerDamage,
            "on_downed",
            "NoDown_PlayerDamage_on_downed",
            function(self)
                if Global.game_settings.no_down and not self._incapacitated then
                    self._down_time = 0
                end
            end
        )

        Hooks:PreHook(
            PlayerDamage,
            "on_incapacitated",
            "NoDown_PlayerDamage_on_incapacitated",
            function(self)
                self._incapacitated = true
            end
        )
    elseif RequiredScript == "lib/network/base/hostnetworksession" then
        function HostNetworkSession:set_peer_loading_state(peer, state, load_counter)
            print("[HostNetworkSession:set_peer_loading_state]", peer:id(), state, load_counter)

            if load_counter ~= self._load_counter then
                Application:error("wrong load counter", self._load_counter)

                if not state then
                    if Global.load_start_menu_lobby then
                        self:send_ok_to_load_lobby()
                    else
                        self:send_ok_to_load_level()
                    end
                end

                return
            end

            HostNetworkSession.super.set_peer_loading_state(self, peer, state)
            peer:set_loading(state)

            if not state then
                if Global.game_settings.no_down and not NoDown.IsConfirmed(peer) then
                    peer._loading_halted = true

                    return
                end

                self:finish_set_peer_loading_state(peer)
            end
        end

        function HostNetworkSession:finish_set_peer_loading_state(peer)
            peer._loading_halted = false

            for other_peer_id, other_peer in pairs(self._peers) do
                if other_peer ~= peer and peer:handshakes()[other_peer_id] == true then
                    peer:send_after_load(
                        "set_member_ready",
                        other_peer_id,
                        other_peer:waiting_for_player_ready() and 1 or 0,
                        1,
                        ""
                    )
                end
            end

            peer:send_after_load(
                "set_member_ready",
                self._local_peer:id(),
                self._local_peer:waiting_for_player_ready() and 1 or 0,
                1,
                ""
            )

            if self._local_peer:is_outfit_loaded() then
                peer:send_after_load("set_member_ready", self._local_peer:id(), 100, 2, "")
            end

            self:chk_request_peer_outfit_load_status()

            if self._local_peer:loaded() and NetworkManager.DROPIN_ENABLED then
                if self._state.on_peer_finished_loading then
                    self._state:on_peer_finished_loading(self._state_data, peer)
                end

                peer:set_expecting_pause_sequence(true)

                local dropin_pause_ok = self:chk_initiate_dropin_pause(peer)

                if dropin_pause_ok then
                    self:chk_drop_in_peer(peer)
                else
                    print(" setting set_expecting_pause_sequence", peer:id())
                end
            end
        end
    elseif RequiredScript == "lib/network/base/networkpeer" then
        Hooks:PostHook(
            NetworkPeer,
            "set_waiting_for_player_ready",
            "NoDown_NetworkPeer_set_waiting_for_player_ready",
            function(self, state)
                if Network:is_server() and Global.game_settings.no_down and not NoDown.IsConfirmed(self) and state then
                    NoDown.RemindConfirmation(self)
                end
            end
        )

        function NetworkPeer:sync_lobby_data(peer)
            local level = managers.experience:current_level()
            local rank = managers.experience:current_rank()
            local join_stinger_index = managers.infamy:selected_join_stinger_index()
            local character = self:character()
            local progress = managers.upgrades:progress()
            local menu_state = managers.menu:get_peer_state(self:id())
            local menu_state_index = tweak_data:menu_sync_state_to_index(menu_state)

            peer:send_after_load(
                "lobby_info",
                level,
                rank,
                join_stinger_index,
                character,
                Network:is_server() and (Global.game_settings.no_down and "true" or "false") or "confirm" -- sync no_down as a host / confirm as a client (THIS IS MINE NOW)
            )
            peer:send_after_load("sync_profile", level, rank)
            managers.network:session():check_send_outfit()

            if menu_state_index then
                peer:send_after_load("set_menu_sync_state_index", menu_state_index)
            end

            if Network:is_server() then
                peer:send_after_load(
                    "lobby_sync_update_level_id",
                    tweak_data.levels:get_index_from_level_id(Global.game_settings.level_id)
                )
                peer:send_after_load("lobby_sync_update_difficulty", Global.game_settings.difficulty)
            end

            self:sync_mods(peer)
            self:sync_is_vr(peer)
        end
    elseif RequiredScript == "lib/managers/menu/menulobbyrenderer" then
        function MenuLobbyRenderer:on_request_lobby_slot_reply()
            local local_peer = managers.network:session():local_peer()
            local local_peer_id = local_peer:id()
            local level = managers.experience:current_level()
            local rank = managers.experience:current_rank()
            local join_stinger_index = managers.infamy:selected_join_stinger_index()
            local character = local_peer:character()
            local progress = managers.upgrades:progress()

            self:_set_player_slot(
                local_peer_id,
                {
                    name = local_peer:name(),
                    peer_id = local_peer_id,
                    level = level,
                    rank = rank,
                    join_stinger_index = join_stinger_index,
                    character = character,
                    progress = progress
                }
            )
            managers.network:session():send_to_peers_loaded(
                "lobby_info",
                level,
                rank,
                join_stinger_index,
                character,
                Network:is_server() and (Global.game_settings.no_down and "true" or "false") or "confirm" -- sync no_down as a host / confirm as a client (THIS IS MINE NOW)
            )
            managers.network:session():send_to_peers_loaded("sync_profile", level, rank)
            managers.network:session():check_send_outfit()
        end
    elseif RequiredScript == "lib/network/base/handlers/connectionnetworkhandler" then
        Hooks:PostHook(
            ConnectionNetworkHandler,
            "send_chat_message",
            "NoDown_ConnectionNetworkHandler_send_chat_message",
            function(self, channel_id, message, sender)
                local peer = self._verify_sender(sender)

                if not peer then
                    return
                end

                if Network:is_server() and Global.game_settings.no_down and not NoDown.IsConfirmed(peer) then
                    local lower = string.lower(message)
                    local stripped = string.gsub(lower, " ", "")
                    stripped = string.gsub(stripped, "'", "")

                    if stripped == "confirm" then
                        NoDown.Confirm(peer)
                    end
                end
            end
        )

        Hooks:PostHook(
            ConnectionNetworkHandler,
            "sync_game_settings",
            "NoDown_ConnectionNetworkHandler_sync_game_settings",
            function(self, job_index, level_id_index, difficulty_index, one_down, weekly_skirmish, sender)
                local peer = self._verify_sender(sender)

                if not peer then
                    return
                end

                if not peer._has_no_down then
                    Global.game_settings.no_down = false
                end
            end
        )

        Hooks:PostHook(
            ConnectionNetworkHandler,
            "lobby_info",
            "NoDown_ConnectionNetworkHandler_lobby_info",
            function(self, level, rank, stinger_index, character, mask_set, sender)
                local peer = self._verify_sender(sender)

                if not peer then
                    return
                end

                if Network:is_server() then
                    if mask_set == "confirm" then
                        NoDown.Confirm(peer, true)
                        peer._has_no_down = true
                    elseif Global.game_settings.no_down and not peer._notification_queued then
                        local peer_id = peer:id()
                        DelayedCalls:Add(
                            "NoDown_NotifyNoDown" .. tostring(peer_id),
                            2,
                            function()
                                local temp_peer =
                                    managers.network:session() and managers.network:session():peer(peer_id)

                                if temp_peer and Global.game_settings.no_down then
                                    NoDown.AnnounceNoDown(temp_peer)

                                    if not NoDown.IsConfirmed(temp_peer) then
                                        NoDown.RequestConfirmation(temp_peer)
                                    end
                                end
                            end
                        )

                        NoDown.AddConfirmationTimeout(peer)

                        peer._notification_queued = true
                    end
                elseif peer:is_host() and mask_set ~= "remove" then
                    peer._has_no_down = true

                    if mask_set == "true" then
                        Global.game_settings.no_down = true

                        NoDown.ApplyNoDown()
                    elseif mask_set == "false" then
                        Global.game_settings.no_down = false
                    end
                end
            end
        )

        Hooks:Add(
            "NetworkReceivedData",
            "NoDown_sync_game_settings_no_down",
            function(peer_id, id, no_down)
                local peer = managers.network:session() and managers.network:session():peer(peer_id)
                if id == "sync_game_settings_no_down" and peer:is_host() then
                    Global.game_settings.no_down = no_down == "true"

                    NoDown.ApplyNoDown()
                end
            end
        )
    elseif RequiredScript == "lib/states/ingamewaitingforrespawn" then
        local IngameWaitingForRespawnState_request_player_spawn_original =
            IngameWaitingForRespawnState.request_player_spawn
        function IngameWaitingForRespawnState.request_player_spawn(peer_to_spawn)
            if
                (Global.game_settings.no_down and NoDown.settings.disable_uncustody == 1) or
                    NoDown.settings.disable_uncustody == 2
             then
                return
            end

            IngameWaitingForRespawnState_request_player_spawn_original(peer_to_spawn)
        end
    elseif RequiredScript == "lib/managers/menu/crimenetcontractgui" then
        function CrimeNetContractGui:set_no_down(no_down)
            local job_data = self._node:parameters().menu_component_data
            job_data.no_down = no_down
        end
    elseif RequiredScript == "lib/managers/menu/menucomponentmanager" then
        function MenuComponentManager:set_crimenet_contract_no_down(no_down)
            if self._crimenet_contract_gui then
                self._crimenet_contract_gui:set_no_down(no_down)
            end
        end
    elseif RequiredScript == "lib/managers/menumanager" then
        function MenuCallbackHandler:choice_crimenet_no_down(item)
            local no_down = item:value() == "on"

            if no_down then
                for _, toggle_one_down in pairs(NoDown.toggle_one_downs) do
                    toggle_one_down:set_value("on")
                    MenuCallbackHandler:choice_crimenet_one_down(toggle_one_down)
                end
            end

            managers.menu_component:set_crimenet_contract_no_down(no_down)
        end

        function MenuCallbackHandler:choice_no_down_filter(item)
            NoDown.settings.search_no_down_lobbies = item:value()
            if NoDown.settings.search_no_down_lobbies ~= 0 then
                NoDown.toggle_one_down_lobby:set_value("on")
                MenuCallbackHandler:chocie_one_down_filter(NoDown.toggle_one_down_lobby)
            end
            NoDown:Save()
        end

        Hooks:PostHook(
            MenuCrimeNetFiltersInitiator,
            "modify_node",
            "NoDown_MenuCrimeNetFiltersInitiator_modify_node",
            function(self, original_node, data)
                if MenuCallbackHandler:is_win32() then
                    original_node:item("choice_no_down_lobby"):set_value(NoDown.settings.search_no_down_lobbies)
                end
            end
        )

        Hooks:Add(
            "LocalizationManagerPostInit",
            "NoDown_LocalizationManagerPostInit",
            function(loc)
                loc:load_localization_file(NoDown._mod_path .. "loc/english.txt")
            end
        )
    elseif RequiredScript == "lib/managers/menumanagerpd2" then
        Hooks:PreHook(
            MenuCallbackHandler,
            "start_job",
            "NoDown_MenuCallbackHandler_start_job_pre",
            function(self, job_data)
                local changed = Global.game_settings.no_down ~= job_data.no_down

                Global.game_settings.no_down = job_data.no_down

                if Global.game_settings.no_down then
                    job_data.one_down = true

                    NoDown.AnnounceNoDown()
                    NoDown.RequestConfirmation()
                    NoDown.AddConfirmationTimeout()
                elseif changed then
                    NoDown.AnnounceNoDown()
                end
            end
        )

        Hooks:PostHook(
            MenuCallbackHandler,
            "start_job",
            "NoDown_MenuCallbackHandler_start_job_post",
            function(self, job_data)
                if Network:is_server() then
                    NoDown.SyncGameSettingsNoDown()
                end
            end
        )

        Hooks:PreHook(
            MenuCallbackHandler,
            "start_single_player_job",
            "NoDown_MenuCallbackHandler_start_single_player_job",
            function(self, job_data)
                Global.game_settings.no_down = job_data.no_down
            end
        )
    elseif RequiredScript == "lib/managers/crimespreemanager" then
        Hooks:PostHook(
            CrimeSpreeManager,
            "_setup_global_from_mission_id",
            "NoDown_CrimeSpreeManager__setup_global_from_mission_id",
            function(self, mission_id)
                local mission_data = self:get_mission(mission_id)

                if mission_data then
                    Global.game_settings.no_down = false
                end
            end
        )
    elseif RequiredScript == "lib/network/base/clientnetworksession" then
        Hooks:PostHook(
            ClientNetworkSession,
            "on_join_request_reply",
            "NoDown_ClientNetworkSession_on_join_request_reply",
            function(
                self,
                reply,
                my_peer_id,
                my_character,
                level_index,
                difficulty_index,
                one_down,
                state_index,
                server_character,
                user_id,
                mission,
                job_id_index,
                job_stage,
                alternative_job_stage,
                interupt_job_stage_level_index,
                xuid,
                auth_ticket,
                sender)
                if reply == 1 then
                    Global.game_settings.no_down = false

                    NoDown.ApplyNoDown()
                end
            end
        )
    elseif RequiredScript == "core/lib/managers/menu/coremenunode" then
        local temp_no_down = NoDown
        core:module("CoreMenuNode")
        Hooks:PreHook(
            MenuNode,
            "add_item",
            "NoDown_MenuNode_add_item",
            function(self, item)
                local item_name = item:name()
                if
                    (self._parameters.name == "crimenet_contract_host" or
                        self._parameters.name == "crimenet_contract_singleplayer")
                 then
                    if item_name == "divider_test2" then
                        local params = {
                            callback = "choice_crimenet_no_down",
                            name = "toggle_no_down",
                            text_id = "no_down_modifier_name",
                            type = "CoreMenuItemToggle.ItemToggle",
                            visible_callback = "customize_contract"
                        }
                        local data_node = {
                            {
                                w = "24",
                                y = "0",
                                h = "24",
                                s_y = "24",
                                value = "on",
                                s_w = "24",
                                s_h = "24",
                                s_x = "24",
                                _meta = "option",
                                icon = "guis/textures/menu_tickbox",
                                x = "24",
                                s_icon = "guis/textures/menu_tickbox"
                            },
                            {
                                w = "24",
                                y = "0",
                                h = "24",
                                s_y = "24",
                                value = "off",
                                s_w = "24",
                                s_h = "24",
                                s_x = "0",
                                _meta = "option",
                                icon = "guis/textures/menu_tickbox",
                                x = "0",
                                s_icon = "guis/textures/menu_tickbox"
                            },
                            type = "CoreMenuItemToggle.ItemToggle"
                        }
                        local toggle_no_down = self:create_item(data_node, params)

                        toggle_no_down:set_value("off")
                        toggle_no_down:set_enabled(true)

                        self:add_item(toggle_no_down)
                        temp_no_down.toggle_no_downs[self._parameters.name] = toggle_no_down
                    elseif item_name == "toggle_one_down" then
                        temp_no_down.toggle_one_downs[self._parameters.name] = item
                    end
                elseif self._parameters.name == "crimenet_filters" then
                    if item_name == "divider_crime_spree" then
                        local params = {
                            callback = "choice_no_down_filter",
                            name = "choice_no_down_lobby",
                            text_id = "no_down_choice_no_down_lobbies_filter",
                            visible_callback = "is_multiplayer is_win32",
                            filter = true
                        }
                        local data_node = {
                            {
                                value = 0,
                                text_id = "no_down_choice_no_down_lobbies_hide",
                                _meta = "option"
                            },
                            {
                                value = 1,
                                text_id = "no_down_choice_no_down_lobbies_allow",
                                _meta = "option"
                            },
                            {
                                value = 2,
                                text_id = "no_down_choice_no_down_lobbies_only",
                                _meta = "option"
                            },
                            type = "MenuItemMultiChoice"
                        }

                        local multi_choice_no_down_lobbies = self:create_item(data_node, params)

                        multi_choice_no_down_lobbies:set_value(temp_no_down.settings.search_no_down_lobbies)
                        multi_choice_no_down_lobbies:set_enabled(true)

                        self:add_item(multi_choice_no_down_lobbies)
                    elseif item_name == "toggle_one_down_lobby" then
                        temp_no_down.toggle_one_down_lobby = item
                    end
                end
            end
        )
    end
end

NoDown:Setup()
