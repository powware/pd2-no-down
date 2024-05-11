function MenuCallbackHandler:choice_crimenet_no_down(item)
    NoDown.settings.buy_no_down = item:value() == "on"
    managers.menu_component:set_crimenet_contract_no_down(NoDown.settings.buy_no_down)

    if NoDown.settings.buy_no_down then
        if LobbySettings then
            LobbySettings.settings.one_down = true
        end
    end

    NoDown:Save()
end

function MenuCallbackHandler:choice_no_down_filter(item)
    NoDown.settings.search_no_down_lobbies = item:value()

    if NoDown.settings.search_no_down_lobbies ~= 0 then
        NoDown.toggle_one_down_lobby:set_value("on")
        MenuCallbackHandler:chocie_one_down_filter(NoDown.toggle_one_down_lobby) -- typo in ovk code
    end

    NoDown:Save()
end

local original_modify_node = MenuCrimeNetContractInitiator.modify_node
function MenuCrimeNetContractInitiator:modify_node(original_node, data)
    if data.customize_contract then
        local toggle_no_down = original_node:item("toggle_no_down")
        toggle_no_down:set_value(NoDown.settings.buy_no_down and "on" or "off")
        data.no_down = NoDown.settings.buy_no_down

        if NoDown.settings.buy_no_down then
            data.one_down = true

            if LobbySettings then
                LobbySettings.settings.one_down = true
            end
        end
    end

    local node = original_modify_node(self, original_node, data)

    if data.customize_contract and NoDown.settings.buy_no_down then
        node:item("toggle_one_down"):set_value("on")
    end

    return node

end

Hooks:PostHook(MenuCrimeNetFiltersInitiator, "modify_node", "NoDown_MenuCrimeNetFiltersInitiator_modify_node",
    function(self, original_node, data)
        if MenuCallbackHandler:is_win32() then
            if NoDown.settings.search_no_down_lobbies ~= 0 then
                original_node:item("toggle_one_down_lobby"):set_value("on")
            end
            original_node:item("choice_no_down_lobby"):set_value(NoDown.settings.search_no_down_lobbies)
        end
    end)

function MenuCallbackHandler:choice_crimenet_one_down(item)
    log("MenuCallbackHandler:choice_crimenet_one_down " .. item:name())
    managers.menu_component:set_crimenet_contract_one_down(item:value() == "on")
end
