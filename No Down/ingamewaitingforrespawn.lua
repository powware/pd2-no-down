local IngameWaitingForRespawnState_request_player_spawn_original = IngameWaitingForRespawnState.request_player_spawn
function IngameWaitingForRespawnState.request_player_spawn(peer_to_spawn)
    if Global.game_settings.no_down or NoDown.settings.disable_uncustody == 2 then
        return
    end

    IngameWaitingForRespawnState_request_player_spawn_original(peer_to_spawn)
end
