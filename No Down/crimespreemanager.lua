Hooks:PostHook(CrimeSpreeManager, "_setup_global_from_mission_id",
    "NoDown_CrimeSpreeManager__setup_global_from_mission_id", function(self, mission_id)
        local mission_data = self:get_mission(mission_id)

        if mission_data then
            Global.game_settings.no_down = false
        end
    end)
