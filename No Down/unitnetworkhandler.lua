Hooks:PostHook(UnitNetworkHandler, "sync_player_movement_state", "NoDown_UnitNetworkHandler_sync_player_movement_state",
    function(self, unit, state, down_time, unit_id_str, sender)
        if not self._verify_gamestate(self._gamestate_filter.any_ingame) then
            return
        end

        local peer = self._verify_sender(sender)

        if not peer or not alive(unit) then
            return
        end

        if not peer:is_host() and (not alive(peer:unit()) or peer:unit():key() ~= unit:key()) then
            return
        end

        local local_peer = managers.network:session():local_peer()

        if local_peer:unit() and unit:key() == local_peer:unit():key() then
            return
        end

        if Network:is_server() and Global.game_settings.no_down and state == "bleed_out" then
            local member_downed, member_dead, health, used_deployable, used_cable_ties, used_body_bags, hostages_killed,
                respawn_penalty, old_plr_entry = peer:_get_old_entry()

            peer:send_queued_sync("spawn_dropin_penalty", true, true, health, false, used_cable_ties, used_body_bags)
        end
    end)

Hooks:PostHook(UnitNetworkHandler, "set_revives", "NoDown_UnitNetworkHandler_set_revives",
    function(self, unit, revive_amount, is_max, sender)
        if not alive(unit) or not self._verify_gamestate(self._gamestate_filter.any_ingame) or
            not Global.game_settings.no_down then
            return
        end

        local peer = self._verify_sender(sender)

        if not peer then
            return
        end

        local peer_id = peer:id()
        local character_data = managers.criminals:character_data_by_peer_id(peer_id)

        if character_data and character_data.panel_id then
            managers.hud:set_teammate_revives(character_data.panel_id, 0)
        end
    end)
