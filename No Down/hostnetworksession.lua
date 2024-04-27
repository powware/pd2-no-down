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
            peer:send_after_load("set_member_ready", other_peer_id, other_peer:waiting_for_player_ready() and 1 or 0, 1,
                "")
        end
    end

    peer:send_after_load("set_member_ready", self._local_peer:id(),
        self._local_peer:waiting_for_player_ready() and 1 or 0, 1, "")

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
