function IngameContractGui:apply_no_down()
    if not Global.game_settings.no_down then
        return
    end

    local one_down_warning_text = self._panel:children()[2]:child("one_down_warning_text")
    if not one_down_warning_text then
        return
    end

    one_down_warning_text:set_text(managers.localization:to_upper_text("no_down_modifier_name"))
    one_down_warning_text:set_color(NoDown.color)
    one_down_warning_text:set_left(10)
end

Hooks:PostHook(
    IngameContractGui,
    "init",
    "NoDown_IngameContractGui_init",
    function(self, ws, node)
        self:apply_no_down()
    end
)
