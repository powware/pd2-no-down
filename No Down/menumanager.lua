function MenuCallbackHandler:choice_crimenet_no_down(item)
    local no_down = item:value() == "on"

    if no_down then
        for _, toggle_one_down in pairs(NoDown.toggle_one_downs) do
            toggle_one_down:set_value("on")
            MenuCallbackHandler:choice_crimenet_one_down(toggle_one_down)
        end
    end

    managers.menu_component:set_crimenet_contract_no_down(no_down)
end

function MenuCallbackHandler:choice_no_down_filter(item)
    NoDown.settings.search_no_down_lobbies = item:value()
    if NoDown.settings.search_no_down_lobbies ~= 0 then
        NoDown.toggle_one_down_lobby:set_value("on")
        MenuCallbackHandler:chocie_one_down_filter(NoDown.toggle_one_down_lobby)
    end
    NoDown:Save()
end

Hooks:PostHook(MenuCrimeNetFiltersInitiator, "modify_node", "NoDown_MenuCrimeNetFiltersInitiator_modify_node",
    function(self, original_node, data)
        if MenuCallbackHandler:is_win32() then
            original_node:item("choice_no_down_lobby"):set_value(NoDown.settings.search_no_down_lobbies)
        end
    end)
