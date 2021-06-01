function HUDMissionBriefing:apply_no_down()
    if not Global.game_settings.no_down then
        return
    end

    local one_down_text = self._foreground_layer_one:child("one_down_text")
    one_down_text:set_text(managers.localization:to_upper_text("no_down_modifier_name"))
    one_down_text:set_color(NoDown.color)
end

Hooks:PostHook(
    HUDMissionBriefing,
    "init",
    "NoDown_HUDMissionBriefing_init",
    function(self, ws, node)
        self:apply_no_down()
    end
)
