NoDown = NoDown or {}
NoDown.default_settings = {confirmed_peers = {}, enabled = false}
NoDown.description = "No Down modifier enabled: You won't bleed out and instead go to custody immediately."
NoDown.confirmation_request = 'Type "confirm" to start playing, you will automatically be kicked in 30s otherwise.'
NoDown.confirmation_reminder = 'Type "confirm" to start playing with the No Down Modifier enabled.'
NoDown.confirmation_confirmation = "You confirmed to play with the No Down Modifier."
NoDown.no_down_reminder = "No Down Modifier enabled."

NoDown._mod_path = ModPath
NoDown._options_menu_file = NoDown._mod_path .. "menu/options.json"
NoDown._save_path = SavePath
NoDown._save_file = NoDown._save_path .. "no_down.json"
NoDown.toggle_one_downs = {}
NoDown.toggle_no_downs = {}

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

function NoDown.SendAnnouncement(peer)
    local peer_id = peer:id()
    local confirmed = NoDown.settings.confirmed_peers[peer._user_id] ~= nil
    if confirmed then
        DelayedCalls:Add(
            "NoDown_AnnouncementFor" .. tostring(peer_id),
            3,
            function()
                local temp_peer = managers.network:session() and managers.network:session():peer(peer_id)
                if temp_peer then
                    temp_peer:send("send_chat_message", ChatManager.GAME, NoDown.no_down_reminder)
                end
            end
        )
    else
        DelayedCalls:Add(
            "NoDown_AnnouncementFor" .. tostring(peer_id),
            3,
            function()
                local temp_peer = managers.network:session() and managers.network:session():peer(peer_id)
                if temp_peer then
                    temp_peer:send("send_chat_message", ChatManager.GAME, NoDown.description)
                    temp_peer:send("send_chat_message", ChatManager.GAME, NoDown.confirmation_request)
                end
            end
        )

        NoDown.AddConfirmationTimeout(peer)
    end

    return confirmed
end

function NoDown.AddConfirmationTimeout(peer)
    local peer_id = peer:id()

    DelayedCalls:Add(
        "NoDown_ConfirmationTimeoutFor" .. tostring(peer_id),
        33,
        function()
            local temp_peer = managers.network:session() and managers.network:session():peer(peer_id)
            if temp_peer and not NoDown.settings.confirmed_peers[temp_peer._user_id] then
                managers.network:session():remove_peer(temp_peer, temp_peer:id())
            end
        end
    )
end

function NoDown.SetupHooks()
    if RequiredScript == "lib/network/handlers/unitnetworkhandler" then
        function UnitNetworkHandler:sync_player_movement_state(unit, state, down_time, unit_id_str, sender)
            if not self._verify_gamestate(self._gamestate_filter.any_ingame) then
                return
            end

            local peer = self._verify_sender(sender)

            if not peer then
                return
            end

            self:_chk_unit_too_early(
                unit,
                unit_id_str,
                "sync_player_movement_state",
                1,
                unit,
                state,
                down_time,
                unit_id_str,
                sender
            )

            if not alive(unit) then
                return
            end

            if not peer:is_host() and (not alive(peer:unit()) or peer:unit():key() ~= unit:key()) then
                Application:error(
                    "[UnitNetworkHandler:sync_player_movement_state] Client is trying to change someone else movement state",
                    peer:id(),
                    unit:key()
                )

                return
            end

            Application:trace(
                "[UnitNetworkHandler:sync_player_movement_state]: ",
                unit:movement():current_state_name(),
                "->",
                state
            )

            local local_peer = managers.network:session():local_peer()

            if local_peer:unit() and unit:key() == local_peer:unit():key() then
                local valid_transitions = {
                    standard = {
                        arrested = true,
                        incapacitated = true,
                        carry = true,
                        bleed_out = true,
                        tased = true
                    },
                    carry = {
                        arrested = true,
                        incapacitated = true,
                        standard = true,
                        bleed_out = true,
                        tased = true
                    },
                    mask_off = {
                        arrested = true,
                        carry = true,
                        standard = true
                    },
                    bleed_out = {
                        carry = true,
                        fatal = true,
                        standard = true
                    },
                    fatal = {
                        carry = true,
                        standard = true
                    },
                    arrested = {
                        carry = true,
                        standard = true
                    },
                    tased = {
                        incapacitated = true,
                        carry = true,
                        standard = true
                    },
                    incapacitated = {
                        carry = true,
                        standard = true
                    },
                    clean = {
                        arrested = true,
                        carry = true,
                        mask_off = true,
                        standard = true,
                        civilian = true
                    },
                    civilian = {
                        arrested = true,
                        carry = true,
                        clean = true,
                        standard = true,
                        mask_off = true
                    }
                }

                if unit:movement():current_state_name() == state then
                    return
                end

                if
                    unit:movement():current_state_name() and
                        valid_transitions[unit:movement():current_state_name()][state]
                 then
                    managers.player:set_player_state(state)
                else
                    debug_pause_unit(
                        unit,
                        "[UnitNetworkHandler:sync_player_movement_state] received invalid transition",
                        unit,
                        unit:movement():current_state_name(),
                        "->",
                        state
                    )
                end
            else
                unit:movement():sync_movement_state(state, down_time)

                if Network:is_server() and state == "bleed_out" then
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
        end
    elseif RequiredScript == "lib/network/matchmaking/NetworkMatchMakingSTEAM" then
        Hooks:PostHook(
            NetworkMatchMakingSTEAM,
            "set_attributes",
            "NoDown_NetworkMatchMakingSTEAM_set_attributes",
            function(self, settings)
                local attributes = managers.network.matchmake._lobby_attributes
                if attributes then
                    attributes.no_down = Global.game_settings.no_down and 1 or 0
                    managers.network.matchmake.lobby_handler:set_lobby_data(attributes)
                end
            end
        )
    elseif RequiredScript == "lib/units/beings/player/playerdamage" then
        Hooks:PreHook(
            PlayerDamage,
            "on_downed",
            "NoDown_PlayerDamage_on_downed",
            function(self)
                if not self._incapacitated then
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
                if Global.game_settings.no_down then
                    if not NoDown.SendAnnouncement(peer) then
                        return
                    end
                end

                self:_set_peer_loading_state(peer)
            end
        end

        function HostNetworkSession:_set_peer_loading_state(peer)
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
                if
                    Network:is_server() and Global.game_settings.no_down and
                        not NoDown.settings.confirmed_peers[self._user_id] and
                        not state
                 then
                    self:send("send_chat_message", ChatManager.GAME, NoDown.confirmation_reminder)
                end
            end
        )
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

                if
                    Network:is_server() and Global.game_settings.no_down and
                        not NoDown.settings.confirmed_peers[peer._user_id]
                 then
                    if message == "confirm" or message == '"confirm"' then
                        NoDown.settings.confirmed_peers[peer._user_id] = true
                        NoDown:Save()

                        peer:send("send_chat_message", ChatManager.GAME, NoDown.confirmation_confirmation)

                        managers.network:session():_set_peer_loading_state(peer)
                    end
                end
            end
        )
    elseif RequiredScript == "lib/managers/menu/crimenetcontractgui" then
        function CrimeNetContractGui:set_no_down(no_down)
            local job_data = self._node:parameters().menu_component_data
            job_data.no_down = no_down

            NoDown.settings.enabled = no_down
            NoDown:Save()
        end
    elseif RequiredScript == "lib/managers/menu/menucomponentmanager" then
        function MenuComponentManager:set_crimenet_contract_no_down(no_down)
            if self._crimenet_contract_gui then
                self._crimenet_contract_gui:set_no_down(no_down)
            end
        end
    elseif RequiredScript == "lib/managers/menumanager" then
        Hooks:PostHook(
            MenuCallbackHandler,
            "start_job",
            "NoDown_MenuCallbackHandler_start_job",
            function(job_data)
                Global.game_settings.no_down = job_data.no_down
            end
        )

        Hooks:PostHook(
            MenuCallbackHandler,
            "start_single_player_job",
            "NoDown_MenuCallbackHandler_start_single_player_job",
            function(job_data)
                Global.game_settings.no_down = job_data.no_down
            end
        )

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
    elseif RequiredScript == "core/lib/managers/menu/coremenunode" then
        local temp_no_down = NoDown
        core:module("CoreMenuNode")
        Hooks:PreHook(
            MenuNode,
            "add_item",
            "NoDown_MenuNode_add_item",
            function(self, item)
                if
                    (self._parameters.name == "crimenet_contract_host" or
                        self._parameters.name == "crimenet_contract_singleplayer")
                 then
                    if item:name() == "divider_test2" then
                        local params = {
                            callback = "choice_crimenet_no_down",
                            name = "toggle_no_down",
                            text_id = "menu_toggle_no_down",
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
                    elseif item:name() == "toggle_one_down" then
                        temp_no_down.toggle_one_downs[self._parameters.name] = item
                    end
                end
            end
        )
    elseif RequiredScript == "lib/managers/crimenetmanager" then
    end
end

NoDown:Setup()
