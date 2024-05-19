Hooks:PostHook(NetworkPeer, "set_waiting_for_player_ready", "NoDown_NetworkPeer_set_waiting_for_player_ready",
    function(self, state)
        if Network:is_server() and Global.game_settings.no_down and not NoDown.IsConfirmed(self) and state then
            NoDown.SendDescription(self)
        end
    end)

function NetworkPeer:sync_lobby_data(peer)
    local level = managers.experience:current_level()
    local rank = managers.experience:current_rank()
    local join_stinger_index = managers.infamy:selected_join_stinger_index()
    local character = self:character()
    local progress = managers.upgrades:progress()
    local menu_state = managers.menu:get_peer_state(self:id())
    local menu_state_index = tweak_data:menu_sync_state_to_index(menu_state)

    peer:send_after_load("lobby_info", level, rank, join_stinger_index, character,
        Network:is_server() and (Global.game_settings.no_down and "true" or "false") or "confirm" -- sync no_down as a host / confirm as a client (THIS IS MINE NOW)
    )
    peer:send_after_load("sync_profile", level, rank)
    managers.network:session():check_send_outfit()

    if menu_state_index then
        peer:send_after_load("set_menu_sync_state_index", menu_state_index)
    end

    if Network:is_server() then
        peer:send_after_load("lobby_sync_update_level_id",
            tweak_data.levels:get_index_from_level_id(Global.game_settings.level_id))
        peer:send_after_load("lobby_sync_update_difficulty", Global.game_settings.difficulty)
    end

    self:sync_mods(peer)
    self:sync_is_vr(peer)
end
