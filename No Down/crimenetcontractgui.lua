function CrimeNetContractGui:apply_no_down()
    local one_down_warning_text = self._contract_panel:child("one_down_warning_text")
    one_down_warning_text:set_text(managers.localization:to_upper_text("no_down_modifier_name"))
    one_down_warning_text:set_color(NoDown.color)
end

Hooks:PostHook(
    CrimeNetContractGui,
    "init",
    "NoDown_CrimeNetContractGui_init",
    function(self, ws, fullscreen_ws, node)
        local job_data = self._node:parameters().menu_component_data

        if job_data.no_down then
            self:apply_no_down()
        end
    end
)
