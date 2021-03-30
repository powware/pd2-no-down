NoDown = NoDown or {}
NoDown.default_settings = {confirmed_peers = {}}
NoDown.description =
    "This lobby has the No Down modifier active. You won't bleed out and instead go to custody immediately. Nine lives aced does not help, so medbags will only heal. Uppers is enabled. Cloakers and Tasers will only incapacitate you."
NoDown.confirmation_request =
    'To confirm that you have read the above and want to play under these conditions type "confirm" in the chat. Otherwise you will be automatically kicked in 30s.'
NoDown.timeout_reason = "Timed out confirming No Down."
NoDown.confirmation_confirmation = "You confirmed to play with the No Down Modifier."
NoDown.confirmation_reminder = 'Type "confirm" to start playing with the No Down Modifier active.'

NoDown._mod_path = ModPath
NoDown._options_menu_file = NoDown._mod_path .. "menu/options.json"
NoDown._save_path = SavePath
NoDown._save_file = NoDown._save_path .. "no_down.json"

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

function NoDown.RequestConfirmation(peer)
    if NoDown.settings.confirmed_peers[peer._user_id] then
        return
    end

    local peer_id = peer:id()

    DelayedCalls:Add(
        "NoDown_AnnouncementFor" .. tostring(peer_id),
        2,
        function()
            local temp_peer = managers.network:session() and managers.network:session():peer(peer_id)
            if temp_peer then
                temp_peer:send("send_chat_message", ChatManager.GAME, NoDown.description)
                temp_peer:send("send_chat_message", ChatManager.GAME, NoDown.confirmation_request)
            end
        end
    )

    DelayedCalls:Add(
        "NoDown_ConfirmationTimeoutFor" .. tostring(peer_id),
        30,
        function()
            local temp_peer = managers.network:session() and managers.network:session():peer(peer_id)
            if temp_peer and not NoDown.settings.confirmed_peers[temp_peer._user_id] then
                managers.network:session():remove_peer(temp_peer, peer:id(), NoDown.timeout_reason)
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
                    attributes.no_down = true
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

        function PlayerDamage:on_incapacitated()
            self._incapacitated = true

            self:on_downed()
        end
    elseif RequiredScript == "lib/network/base/networkmanager" then
        Hooks:Add(
            "NetworkManagerOnPeerAdded",
            "NoDown_NetworkManagerOnPeerAdded",
            function(peer, peer_id)
                if Network:is_server() then
                    NoDown.RequestConfirmation(peer)
                end
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
                if not NoDown.settings.confirmed_peers[peer._user_id] then
                    NoDown.RequestConfirmation(peer)
                else
                    self:set_peer_loading_state_after_confirmation(peer)
                end
            end
        end

        function HostNetworkSession:set_peer_loading_state_after_confirmation(peer)
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
            "NoDown_ConnectionNetworkHandler_set_waiting",
            function(self, state)
                if Network:is_server() and not NoDown.settings.confirmed_peers[self._user_id] then
                    self:send("send_chat_message", ChatManager.GAME, NoDown.confirmation_reminder)
                end
            end
        )
    elseif RequiredScript == "lib/network/base/handlers/connectionnetworkhandler" then
        function ConnectionNetworkHandler:send_chat_message(channel_id, message, sender)
            local peer = self._verify_sender(sender)

            if not peer then
                return
            end

            if not NoDown.settings.confirmed_peers[peer._user_id] then
                if message == "confirm" or message == '"confirm"' then
                    NoDown.settings.confirmed_peers[peer._user_id] = true
                    NoDown:Save()

                    managers.chat:_receive_message(
                        1,
                        "SYSTEM",
                        peer:name() .. " confirmed to play.",
                        tweak_data.system_chat_color
                    )

                    peer:send("send_chat_message", ChatManager.GAME, NoDown.confirmation_confirmation)

                    managers.network:session():set_peer_loading_state_after_confirmation(peer)

                    return
                else
                    peer:send("send_chat_message", ChatManager.GAME, NoDown.confirmation_reminder)
                end
            end

            managers.chat:receive_message_by_peer(channel_id, peer, message)
        end
    end
end

NoDown:Setup()
