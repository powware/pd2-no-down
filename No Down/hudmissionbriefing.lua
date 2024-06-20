function HUDMissionBriefing:apply_no_down()
    if not Global.game_settings.no_down then
        return
    end

    local pg_text = self._foreground_layer_one:child("pg_text")
    if not pg_text then
        return
    end

    local one_down_text = self._foreground_layer_one:child("one_down_text")
    if not one_down_text then
        return
    end

    one_down_text:set_text(managers.localization:to_upper_text("no_down_modifier_name"))
    one_down_text:set_color(NoDown.color)
    local _, _, w, h = one_down_text:text_rect()

    one_down_text:set_size(w, h)
    one_down_text:set_righttop(pg_text:left() - 10, pg_text:top())
end

Hooks:PostHook(HUDMissionBriefing, "init", "NoDown_HUDMissionBriefing_init", function(self, ws, node)
    if self.apply_no_down then
        self:apply_no_down()
    end
end)
