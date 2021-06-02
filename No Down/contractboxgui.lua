function ContractBoxGui:apply_no_down()
    if not Global.game_settings.no_down then
        return
    end

    local difficulty_stars = managers.job:current_difficulty_stars()
    local difficulty = tweak_data.difficulties[difficulty_stars + 2] or 1
    local difficulty_string_id = tweak_data.difficulty_name_ids[difficulty]
    local difficulty_string = managers.localization:to_upper_text(difficulty_string_id)
    local text_string = difficulty_string .. " " .. managers.localization:to_upper_text("no_down_modifier_name")

    for _, child in pairs(self._contract_panel:children()) do
        if child and child.text then
            local content = child:text()
            if type(content) == "string" then
                if string.find(content, managers.localization:to_upper_text("menu_one_down")) then
                    child:set_text(text_string)
                    child:set_range_color(utf8.len(difficulty_string) + 1, utf8.len(text_string), NoDown.color)
                    return
                end
            end
        end
    end
end

Hooks:PostHook(
    ContractBoxGui,
    "create_contract_box",
    "NoDown_ContractBoxGui_create_contract_box",
    function(self, ws, node)
        self:apply_no_down()
    end
)
