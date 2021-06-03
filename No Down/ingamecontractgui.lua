function IngameContractGui:apply_no_down()
    if not Global.game_settings.no_down then
        return
    end

    for _, child in pairs(self._panel:children()) do
        if child and child.child then
            local one_down_warning_text = child:child("one_down_warning_text")
            if one_down_warning_text then
                one_down_warning_text:set_text(managers.localization:to_upper_text("no_down_modifier_name"))
                one_down_warning_text:set_color(NoDown.color)
                managers.hud:make_fine_text(one_down_warning_text)
                one_down_warning_text:set_left(10)
            end
        end
    end
end

Hooks:PostHook(
    IngameContractGui,
    "init",
    "NoDown_IngameContractGui_init",
    function(self, ws, node)
        self:apply_no_down()
    end
)
