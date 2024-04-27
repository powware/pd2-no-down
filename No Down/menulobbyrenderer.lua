function MenuLobbyRenderer:on_request_lobby_slot_reply()
    local local_peer = managers.network:session():local_peer()
    local local_peer_id = local_peer:id()
    local level = managers.experience:current_level()
    local rank = managers.experience:current_rank()
    local join_stinger_index = managers.infamy:selected_join_stinger_index()
    local character = local_peer:character()
    local progress = managers.upgrades:progress()

    self:_set_player_slot(local_peer_id, {
        name = local_peer:name(),
        peer_id = local_peer_id,
        level = level,
        rank = rank,
        join_stinger_index = join_stinger_index,
        character = character,
        progress = progress
    })
    managers.network:session():send_to_peers_loaded("lobby_info", level, rank, join_stinger_index, character,
        Network:is_server() and (Global.game_settings.no_down and "true" or "false") or "confirm" -- sync no_down as a host / confirm as a client (THIS IS MINE NOW)
    )
    managers.network:session():send_to_peers_loaded("sync_profile", level, rank)
    managers.network:session():check_send_outfit()
end
