function ContractBoxGui:apply_no_down()
    if not Global.game_settings.no_down then
        return
    end

    local difficulty_stars = managers.job:current_difficulty_stars()
    local difficulty = tweak_data.difficulties[difficulty_stars + 2] or 1
    local difficulty_string_id = tweak_data.difficulty_name_ids[difficulty]
    local difficulty_string = managers.localization:to_upper_text(difficulty_string_id)
    local text_string = difficulty_string .. " " .. managers.localization:to_upper_text("no_down_modifier_name")

    local difficulty_text = self._contract_panel:children()[8]

    difficulty_text:set_text(text_string)
    difficulty_text:set_range_color(utf8.len(difficulty_string) + 1, utf8.len(text_string), NoDown.color)
end

Hooks:PostHook(
    ContractBoxGui,
    "create_contract_box",
    "NoDown_ContractBoxGui_create_contract_box",
    function(self, ws, node)
        self:apply_no_down()
    end
)
