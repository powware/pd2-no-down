Hooks:PreHook(MenuCallbackHandler, "start_job", "NoDown_MenuCallbackHandler_start_job_pre", function(self, job_data)
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
end)

Hooks:PostHook(MenuCallbackHandler, "start_job", "NoDown_MenuCallbackHandler_start_job_post", function(self, job_data)
    if Network:is_server() then
        NoDown.SyncGameSettingsNoDown()
    end
end)

Hooks:PreHook(MenuCallbackHandler, "start_single_player_job", "NoDown_MenuCallbackHandler_start_single_player_job",
    function(self, job_data)
        Global.game_settings.no_down = job_data.no_down
    end)
