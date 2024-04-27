function MenuComponentManager:set_crimenet_contract_no_down(no_down)
    if self._crimenet_contract_gui then
        self._crimenet_contract_gui:set_no_down(no_down)
    end
end
