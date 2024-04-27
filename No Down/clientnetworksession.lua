Hooks:PostHook(ClientNetworkSession, "on_join_request_reply", "NoDown_ClientNetworkSession_on_join_request_reply",
    function(self, reply, my_peer_id, my_character, level_index, difficulty_index, one_down, state_index,
        server_character, user_id, mission, job_id_index, job_stage, alternative_job_stage,
        interupt_job_stage_level_index, xuid, auth_ticket, sender)
        if reply == 1 then
            Global.game_settings.no_down = false

            NoDown.ApplyNoDown()
        end
    end)
