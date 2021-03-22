NoDown = NoDown or {}
NoDown.apply_to_clients = true

Hooks:PostHook(
    NetworkMatchMakingSTEAM,
    "set_attributes",
    "NoDown_NetworkMatchMakingSTEAM_set_attributes",
    function(self, settings)
        local attributes = managers.network.matchmake._lobby_attributes
        if attributes then
            attributes.no_down = true
            managers.network.matchmake.lobby_handler:set_lobby_data(attributes)
        end
    end
)

Hooks:PreHook(
    PlayerDamage,
    "on_downed",
    "NoDown_PlayerDamage_on_downed",
    function(self)
        if not self._incapacitated then
            self._down_time = 0
        end
    end
)

function UnitNetworkHandler:sync_player_movement_state(unit, state, down_time, unit_id_str, sender)
    if not self._verify_gamestate(self._gamestate_filter.any_ingame) then
        return
    end

    local peer = self._verify_sender(sender)

    if not peer then
        return
    end

    self:_chk_unit_too_early(
        unit,
        unit_id_str,
        "sync_player_movement_state",
        1,
        unit,
        state,
        down_time,
        unit_id_str,
        sender
    )

    if not alive(unit) then
        return
    end

    if not peer:is_host() and (not alive(peer:unit()) or peer:unit():key() ~= unit:key()) then
        Application:error(
            "[UnitNetworkHandler:sync_player_movement_state] Client is trying to change someone else movement state",
            peer:id(),
            unit:key()
        )

        return
    end

    Application:trace(
        "[UnitNetworkHandler:sync_player_movement_state]: ",
        unit:movement():current_state_name(),
        "->",
        state
    )

    local local_peer = managers.network:session():local_peer()

    if local_peer:unit() and unit:key() == local_peer:unit():key() then
        local valid_transitions = {
            standard = {
                arrested = true,
                incapacitated = true,
                carry = true,
                bleed_out = true,
                tased = true
            },
            carry = {
                arrested = true,
                incapacitated = true,
                standard = true,
                bleed_out = true,
                tased = true
            },
            mask_off = {
                arrested = true,
                carry = true,
                standard = true
            },
            bleed_out = {
                carry = true,
                fatal = true,
                standard = true
            },
            fatal = {
                carry = true,
                standard = true
            },
            arrested = {
                carry = true,
                standard = true
            },
            tased = {
                incapacitated = true,
                carry = true,
                standard = true
            },
            incapacitated = {
                carry = true,
                standard = true
            },
            clean = {
                arrested = true,
                carry = true,
                mask_off = true,
                standard = true,
                civilian = true
            },
            civilian = {
                arrested = true,
                carry = true,
                clean = true,
                standard = true,
                mask_off = true
            }
        }

        if unit:movement():current_state_name() == state then
            return
        end

        if unit:movement():current_state_name() and valid_transitions[unit:movement():current_state_name()][state] then
            managers.player:set_player_state(state)
        else
            debug_pause_unit(
                unit,
                "[UnitNetworkHandler:sync_player_movement_state] received invalid transition",
                unit,
                unit:movement():current_state_name(),
                "->",
                state
            )
        end
    else
        unit:movement():sync_movement_state(state, down_time)

        if Network:is_server() and NoDown.apply_to_clients and state == "bleed_out" then
            local member_downed,
                member_dead,
                health,
                used_deployable,
                used_cable_ties,
                used_body_bags,
                hostages_killed,
                respawn_penalty,
                old_plr_entry = peer:_get_old_entry()
            peer:send_queued_sync("spawn_dropin_penalty", true, true, health, false, used_cable_ties, used_body_bags)
        end
    end
end

Hooks:Add(
    "NetworkManagerOnPeerAdded",
    "NoDown_NetworkManagerOnPeerAdded",
    function(peer, peer_id)
        if Network:is_server() and NoDown.apply_to_clients then
            DelayedCalls:Add(
                "NoDown_AnnouncementFor" .. tostring(peer_id),
                2,
                function()
                    local temp_peer = managers.network:session() and managers.network:session():peer(peer_id)
                    if temp_peer then
                        local message =
                            "This lobby has the No Down modifier active. You won't bleed out and instead go to custody immediately. Nine lives aced does NOT help, so medbags will only heal. Uppers is enabled. Cloakers and Tasers will only incapacitate you."
                        local message2 =
                            "Please confirm in the chat that you are aware of this, so that the host does not have to ask before dropping you in."
                        temp_peer:send("send_chat_message", ChatManager.GAME, message)
                        temp_peer:send("send_chat_message", ChatManager.GAME, message2)
                    end
                end
            )
        end
    end
)
