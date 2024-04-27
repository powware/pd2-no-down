local temp_no_down = NoDown
core:module("CoreMenuNode")
Hooks:PreHook(MenuNode, "add_item", "NoDown_MenuNode_add_item", function(self, item)
    local item_name = item:name()
    if (self._parameters.name == "crimenet_contract_host" or self._parameters.name == "crimenet_contract_singleplayer") then
        if item_name == "divider_test2" then
            local params = {
                callback = "choice_crimenet_no_down",
                name = "toggle_no_down",
                text_id = "no_down_modifier_name",
                type = "CoreMenuItemToggle.ItemToggle",
                visible_callback = "customize_contract"
            }
            local data_node = {
                {
                    w = "24",
                    y = "0",
                    h = "24",
                    s_y = "24",
                    value = "on",
                    s_w = "24",
                    s_h = "24",
                    s_x = "24",
                    _meta = "option",
                    icon = "guis/textures/menu_tickbox",
                    x = "24",
                    s_icon = "guis/textures/menu_tickbox"
                },
                {
                    w = "24",
                    y = "0",
                    h = "24",
                    s_y = "24",
                    value = "off",
                    s_w = "24",
                    s_h = "24",
                    s_x = "0",
                    _meta = "option",
                    icon = "guis/textures/menu_tickbox",
                    x = "0",
                    s_icon = "guis/textures/menu_tickbox"
                },
                type = "CoreMenuItemToggle.ItemToggle"
            }
            local toggle_no_down = self:create_item(data_node, params)

            toggle_no_down:set_value("off")
            toggle_no_down:set_enabled(true)

            self:add_item(toggle_no_down)
            temp_no_down.toggle_no_downs[self._parameters.name] = toggle_no_down
        elseif item_name == "toggle_one_down" then
            temp_no_down.toggle_one_downs[self._parameters.name] = item
        end
    elseif self._parameters.name == "crimenet_filters" then
        if item_name == "divider_crime_spree" then
            local params = {
                callback = "choice_no_down_filter",
                name = "choice_no_down_lobby",
                text_id = "no_down_choice_no_down_lobbies_filter",
                visible_callback = "is_multiplayer is_win32",
                filter = true
            }
            local data_node = {
                {
                    value = 0,
                    text_id = "no_down_choice_no_down_lobbies_hide",
                    _meta = "option"
                },
                {
                    value = 1,
                    text_id = "no_down_choice_no_down_lobbies_allow",
                    _meta = "option"
                },
                {
                    value = 2,
                    text_id = "no_down_choice_no_down_lobbies_only",
                    _meta = "option"
                },
                type = "MenuItemMultiChoice"
            }

            local multi_choice_no_down_lobbies = self:create_item(data_node, params)

            multi_choice_no_down_lobbies:set_value(temp_no_down.settings.search_no_down_lobbies)
            multi_choice_no_down_lobbies:set_enabled(true)

            self:add_item(multi_choice_no_down_lobbies)
        elseif item_name == "toggle_one_down_lobby" then
            temp_no_down.toggle_one_down_lobby = item
        end
    end
end)
