Hooks:PostHook(ConnectionNetworkHandler, "send_chat_message", "NoDown_ConnectionNetworkHandler_send_chat_message",
    function(self, channel_id, message, sender)
        local peer = self._verify_sender(sender)

        if not peer then
            return
        end

        if Network:is_server() and Global.game_settings.no_down and not NoDown.IsConfirmed(peer) then
            local lower = string.lower(message)
            local stripped = string.gsub(lower, " ", "")
            stripped = string.gsub(stripped, "'", "")

            if stripped == "confirm" then
                NoDown.Confirm(peer)
            end
        end
    end)

Hooks:PostHook(ConnectionNetworkHandler, "sync_game_settings", "NoDown_ConnectionNetworkHandler_sync_game_settings",
    function(self, job_index, level_id_index, difficulty_index, one_down, weekly_skirmish, sender)
        local peer = self._verify_sender(sender)

        if not peer then
            return
        end

        if not peer._has_no_down then
            Global.game_settings.no_down = false
        end
    end)

Hooks:PostHook(ConnectionNetworkHandler, "lobby_info", "NoDown_ConnectionNetworkHandler_lobby_info",
    function(self, level, rank, stinger_index, character, mask_set, sender)
        local peer = self._verify_sender(sender)

        if not peer then
            return
        end

        if Network:is_server() then
            if mask_set == "confirm" then
                NoDown.Confirm(peer, true)
                peer._has_no_down = true
            elseif Global.game_settings.no_down and not peer._notification_queued then
                local peer_id = peer:id()
                DelayedCalls:Add("NoDown_NotifyNoDown" .. tostring(peer_id), 2, function()
                    local temp_peer = managers.network:session() and managers.network:session():peer(peer_id)

                    if temp_peer and Global.game_settings.no_down then
                        NoDown.AnnounceNoDown(temp_peer)

                        if not NoDown.IsConfirmed(temp_peer) then
                            NoDown.RequestConfirmation(temp_peer)
                        end
                    end
                end)

                NoDown.AddConfirmationTimeout(peer)

                peer._notification_queued = true
            end
        elseif peer:is_host() and mask_set ~= "remove" then
            peer._has_no_down = true

            if mask_set == "true" then
                Global.game_settings.no_down = true

                NoDown.ApplyNoDown()
            elseif mask_set == "false" then
                Global.game_settings.no_down = false
            end
        end
    end)

Hooks:Add("NetworkReceivedData", "NoDown_sync_game_settings_no_down", function(peer_id, id, no_down)
    local peer = managers.network:session() and managers.network:session():peer(peer_id)
    if id == "sync_game_settings_no_down" and peer:is_host() then
        Global.game_settings.no_down = no_down == "true"

        NoDown.ApplyNoDown()
    end
end)
