Hooks:PreHook(PlayerDamage, "on_downed", "NoDown_PlayerDamage_on_downed", function(self)
    if Global.game_settings.no_down and not self._incapacitated then
        self._down_time = 0
    end
end)

Hooks:PreHook(PlayerDamage, "on_incapacitated", "NoDown_PlayerDamage_on_incapacitated", function(self)
    self._incapacitated = true
end)

function PlayerDamage:_send_set_revives(is_max)
    local revives = Application:digest_value(self._revives, false)

    if Global.game_settings.no_down then
        revives = 1
        is_max = false
    end

    managers.hud:set_teammate_revives(HUDManager.PLAYER_PANEL, revives)

    local net_ext = self._unit:network()

    if net_ext then
        net_ext:send("set_revives", revives, is_max or false)
    end
end
