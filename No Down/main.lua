NoDown = NoDown or {}
NoDown.default_settings = {confirmed_peers = {}, enabled = false}
NoDown.description = "No Down modifier enabled: You won't bleed out and instead go to custody immediately."
NoDown.confirmation_request = 'Type "confirm" to start playing, you will automatically be kicked in 30s otherwise.'
NoDown.confirmation_reminder = 'Type "confirm" to start playing with the No Down Modifier enabled.'
NoDown.confirmation_confirmation = "You confirmed to play with the No Down Modifier."
NoDown.no_down_reminder = "No Down Modifier enabled."
NoDown.color = Color(1, 0.1, 1, 0.5)

NoDown._mod_path = ModPath
NoDown._options_menu_file = NoDown._mod_path .. "menu/options.json"
NoDown._save_path = SavePath
NoDown._save_file = NoDown._save_path .. "no_down.json"
NoDown.toggle_one_downs = {}
NoDown.toggle_no_downs = {}

local function deep_copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deep_copy(orig_key)] = deep_copy(orig_value)
        end
        setmetatable(copy, deep_copy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function NoDown:Setup()
    if not self.settings then
        self:Load()
    end

    self.SetupHooks()
end

-- load settings from file
function NoDown:Load()
    self.settings = deep_copy(self.default_settings)
    local file = io.open(self._save_file, "r")
    if file then
        local data = file:read("*a")
        if data then
            local decoded_data = json.decode(data)

            if decoded_data then
                for key, value in pairs(self.settings) do
                    if decoded_data[key] ~= nil then
                        self.settings[key] = deep_copy(decoded_data[key])
                    end
                end
            end
        end
        file:close()
    end
end

-- save settings to file
function NoDown:Save()
    local file = io.open(self._save_file, "w+")
    if file then
        file:write(json.encode(self.settings))
        file:close()
    end
end

function NoDown.SendAnnouncement(peer)
    local peer_id = peer:id()
    local confirmed = NoDown.settings.confirmed_peers[peer._user_id] ~= nil
    if confirmed then
        DelayedCalls:Add(
            "NoDown_AnnouncementFor" .. tostring(peer_id),
            3,
            function()
                local temp_peer = managers.network:session() and managers.network:session():peer(peer_id)
                if temp_peer then
                    temp_peer:send("send_chat_message", ChatManager.GAME, NoDown.no_down_reminder)
                end
            end
        )
    else
        DelayedCalls:Add(
            "NoDown_AnnouncementFor" .. tostring(peer_id),
            3,
            function()
                local temp_peer = managers.network:session() and managers.network:session():peer(peer_id)
                if temp_peer then
                    temp_peer:send("send_chat_message", ChatManager.GAME, NoDown.description)
                    temp_peer:send("send_chat_message", ChatManager.GAME, NoDown.confirmation_request)
                end
            end
        )

        NoDown.AddConfirmationTimeout(peer)
    end

    return confirmed
end

function NoDown.AddConfirmationTimeout(peer)
    local peer_id = peer:id()

    DelayedCalls:Add(
        "NoDown_ConfirmationTimeoutFor" .. tostring(peer_id),
        33,
        function()
            local temp_peer = managers.network:session() and managers.network:session():peer(peer_id)
            if temp_peer and not NoDown.settings.confirmed_peers[temp_peer._user_id] then
                managers.network:session():remove_peer(temp_peer, temp_peer:id())
            end
        end
    )
end

function NoDown.SetupHooks()
    if RequiredScript == "lib/network/handlers/unitnetworkhandler" then
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

                if
                    unit:movement():current_state_name() and
                        valid_transitions[unit:movement():current_state_name()][state]
                 then
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

                if Network:is_server() and state == "bleed_out" then
                    local member_downed,
                        member_dead,
                        health,
                        used_deployable,
                        used_cable_ties,
                        used_body_bags,
                        hostages_killed,
                        respawn_penalty,
                        old_plr_entry = peer:_get_old_entry()
                    peer:send_queued_sync(
                        "spawn_dropin_penalty",
                        true,
                        true,
                        health,
                        false,
                        used_cable_ties,
                        used_body_bags
                    )
                end
            end
        end
    elseif RequiredScript == "lib/network/matchmaking/NetworkMatchMakingSTEAM" then
        Hooks:PostHook(
            NetworkMatchMakingSTEAM,
            "set_attributes",
            "NoDown_NetworkMatchMakingSTEAM_set_attributes",
            function(self, settings)
                local attributes = managers.network.matchmake._lobby_attributes
                if attributes then
                    attributes.no_down = Global.game_settings.no_down and 1 or 0
                    managers.network.matchmake.lobby_handler:set_lobby_data(attributes)
                end
            end
        )
    elseif RequiredScript == "lib/units/beings/player/playerdamage" then
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

        Hooks:PreHook(
            PlayerDamage,
            "on_incapacitated",
            "NoDown_PlayerDamage_on_incapacitated",
            function(self)
                self._incapacitated = true
            end
        )
    elseif RequiredScript == "lib/network/base/hostnetworksession" then
        function HostNetworkSession:set_peer_loading_state(peer, state, load_counter)
            print("[HostNetworkSession:set_peer_loading_state]", peer:id(), state, load_counter)

            if load_counter ~= self._load_counter then
                Application:error("wrong load counter", self._load_counter)

                if not state then
                    if Global.load_start_menu_lobby then
                        self:send_ok_to_load_lobby()
                    else
                        self:send_ok_to_load_level()
                    end
                end

                return
            end

            HostNetworkSession.super.set_peer_loading_state(self, peer, state)
            peer:set_loading(state)

            if not state then
                if Global.game_settings.no_down then
                    if not NoDown.SendAnnouncement(peer) then
                        return
                    end
                end

                self:_set_peer_loading_state(peer)
            end
        end

        function HostNetworkSession:_set_peer_loading_state(peer)
            for other_peer_id, other_peer in pairs(self._peers) do
                if other_peer ~= peer and peer:handshakes()[other_peer_id] == true then
                    peer:send_after_load(
                        "set_member_ready",
                        other_peer_id,
                        other_peer:waiting_for_player_ready() and 1 or 0,
                        1,
                        ""
                    )
                end
            end

            peer:send_after_load(
                "set_member_ready",
                self._local_peer:id(),
                self._local_peer:waiting_for_player_ready() and 1 or 0,
                1,
                ""
            )

            if self._local_peer:is_outfit_loaded() then
                peer:send_after_load("set_member_ready", self._local_peer:id(), 100, 2, "")
            end

            self:chk_request_peer_outfit_load_status()

            if self._local_peer:loaded() and NetworkManager.DROPIN_ENABLED then
                if self._state.on_peer_finished_loading then
                    self._state:on_peer_finished_loading(self._state_data, peer)
                end

                peer:set_expecting_pause_sequence(true)

                local dropin_pause_ok = self:chk_initiate_dropin_pause(peer)

                if dropin_pause_ok then
                    self:chk_drop_in_peer(peer)
                else
                    print(" setting set_expecting_pause_sequence", peer:id())
                end
            end
        end
    elseif RequiredScript == "lib/network/base/networkpeer" then
        Hooks:PostHook(
            NetworkPeer,
            "set_waiting_for_player_ready",
            "NoDown_NetworkPeer_set_waiting_for_player_ready",
            function(self, state)
                if
                    Network:is_server() and Global.game_settings.no_down and
                        not NoDown.settings.confirmed_peers[self._user_id] and
                        not state
                 then
                    self:send("send_chat_message", ChatManager.GAME, NoDown.confirmation_reminder)
                end
            end
        )
    elseif RequiredScript == "lib/network/base/handlers/connectionnetworkhandler" then
        Hooks:PostHook(
            ConnectionNetworkHandler,
            "send_chat_message",
            "NoDown_ConnectionNetworkHandler_send_chat_message",
            function(self, channel_id, message, sender)
                local peer = self._verify_sender(sender)

                if not peer then
                    return
                end

                if
                    Network:is_server() and Global.game_settings.no_down and
                        not NoDown.settings.confirmed_peers[peer._user_id]
                 then
                    if message == "confirm" or message == '"confirm"' then
                        NoDown.settings.confirmed_peers[peer._user_id] = true
                        NoDown:Save()

                        peer:send("send_chat_message", ChatManager.GAME, NoDown.confirmation_confirmation)

                        managers.network:session():_set_peer_loading_state(peer)
                    end
                end
            end
        )
    elseif RequiredScript == "lib/managers/menu/crimenetcontractgui" then
        function CrimeNetContractGui:set_no_down(no_down)
            local job_data = self._node:parameters().menu_component_data
            job_data.no_down = no_down

            NoDown.settings.enabled = no_down
            NoDown:Save()
        end
    elseif RequiredScript == "lib/managers/menu/menucomponentmanager" then
        function MenuComponentManager:set_crimenet_contract_no_down(no_down)
            if self._crimenet_contract_gui then
                self._crimenet_contract_gui:set_no_down(no_down)
            end
        end
    elseif RequiredScript == "lib/managers/menumanager" then
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
    elseif RequiredScript == "lib/managers/menumanagerpd2" then
        Hooks:PostHook(
            MenuCallbackHandler,
            "start_job",
            "NoDown_MenuCallbackHandler_start_job",
            function(self, job_data)
                Global.game_settings.no_down = job_data.no_down
            end
        )

        Hooks:PostHook(
            MenuCallbackHandler,
            "start_single_player_job",
            "NoDown_MenuCallbackHandler_start_single_player_job",
            function(self, job_data)
                Global.game_settings.no_down = job_data.no_down
            end
        )
    elseif RequiredScript == "core/lib/managers/menu/coremenunode" then
        local temp_no_down = NoDown
        core:module("CoreMenuNode")
        Hooks:PreHook(
            MenuNode,
            "add_item",
            "NoDown_MenuNode_add_item",
            function(self, item)
                if
                    (self._parameters.name == "crimenet_contract_host" or
                        self._parameters.name == "crimenet_contract_singleplayer")
                 then
                    if item:name() == "divider_test2" then
                        local params = {
                            callback = "choice_crimenet_no_down",
                            name = "toggle_no_down",
                            text_id = "menu_toggle_no_down",
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
                    elseif item:name() == "toggle_one_down" then
                        temp_no_down.toggle_one_downs[self._parameters.name] = item
                    end
                end
            end
        )
    elseif RequiredScript == "lib/managers/menu/contractboxgui" then
        function ContractBoxGui:create_contract_box()
            if not managers.network:session() then
                return
            end

            if self._contract_panel and alive(self._contract_panel) then
                self._panel:remove(self._contract_panel)
            end

            if self._contract_text_header and alive(self._contract_text_header) then
                self._panel:remove(self._contract_text_header)
            end

            if alive(self._panel:child("pro_text")) then
                self._panel:remove(self._panel:child("pro_text"))
            end

            self._contract_panel = nil
            self._contract_text_header = nil
            local contact_data = managers.job:current_contact_data()
            local job_data = managers.job:current_job_data()
            local job_chain = managers.job:current_job_chain_data()
            local job_id = managers.job:current_job_id()
            local job_tweak = tweak_data.levels[job_id]
            self._contract_panel =
                self._panel:panel(
                {
                    name = "contract_box_panel",
                    h = 100,
                    layer = 0,
                    w = self._panel:w() * 0.35
                }
            )

            self._contract_panel:rect(
                {
                    halign = "grow",
                    valign = "grow",
                    layer = -1,
                    color = Color(0.5, 0, 0, 0)
                }
            )

            local font = tweak_data.menu.pd2_small_font
            local font_size = tweak_data.menu.pd2_small_font_size

            if contact_data then
                self._contract_text_header =
                    self._panel:text(
                    {
                        blend_mode = "add",
                        text = utf8.to_upper(
                            managers.localization:text(contact_data.name_id) ..
                                ": " .. managers.localization:text(job_data.name_id)
                        ),
                        h = tweak_data.menu.pd2_medium_font_size,
                        font_size = tweak_data.menu.pd2_medium_font_size,
                        font = tweak_data.menu.pd2_medium_font,
                        color = tweak_data.screen_colors.text
                    }
                )
                local length_text_header =
                    self._contract_panel:text(
                    {
                        text = managers.localization:to_upper_text("cn_menu_contract_length_header"),
                        font_size = font_size,
                        font = font,
                        color = tweak_data.screen_colors.text
                    }
                )
                local risk_text_header =
                    self._contract_panel:text(
                    {
                        text = managers.localization:to_upper_text("menu_lobby_difficulty_title"),
                        font_size = font_size,
                        font = font,
                        color = tweak_data.screen_colors.text
                    }
                )
                local exp_text_header =
                    self._contract_panel:text(
                    {
                        text = managers.localization:to_upper_text("menu_experience"),
                        font_size = font_size,
                        font = font,
                        color = tweak_data.screen_colors.text
                    }
                )
                local payout_text_header =
                    self._contract_panel:text(
                    {
                        text = managers.localization:to_upper_text("cn_menu_contract_jobpay_header"),
                        font_size = font_size,
                        font = font,
                        color = tweak_data.screen_colors.text
                    }
                )
                local _, _, tw, th = self._contract_text_header:text_rect()

                self._contract_text_header:set_size(tw, th)

                local w = 0
                local _, _, tw, th = length_text_header:text_rect()
                w = math.max(w, tw)

                length_text_header:set_size(tw, th)

                local _, _, tw, th = risk_text_header:text_rect()
                w = math.max(w, tw)

                risk_text_header:set_size(tw, th)

                local _, _, tw, th = exp_text_header:text_rect()
                w = math.max(w, tw)

                exp_text_header:set_size(tw, th)

                local _, _, tw, th = payout_text_header:text_rect()
                w = math.max(w, tw)

                payout_text_header:set_size(tw, th)

                w = w + 10

                length_text_header:set_right(w)
                risk_text_header:set_right(w)
                exp_text_header:set_right(w)
                payout_text_header:set_right(w)
                risk_text_header:set_top(10)
                length_text_header:set_top(risk_text_header:bottom())
                exp_text_header:set_top(length_text_header:bottom())
                payout_text_header:set_top(exp_text_header:bottom())

                local length_text =
                    self._contract_panel:text(
                    {
                        vertical = "top",
                        align = "left",
                        text = managers.localization:to_upper_text(
                            "cn_menu_contract_length",
                            {
                                stages = #job_chain
                            }
                        ),
                        font_size = font_size,
                        font = font,
                        color = tweak_data.screen_colors.text
                    }
                )

                length_text:set_position(length_text_header:right() + 5, length_text_header:top())

                local _, _, tw, th = length_text:text_rect()
                w = math.max(w, tw)

                length_text:set_size(tw, th)

                if managers.job:is_job_ghostable(managers.job:current_job_id()) then
                    local ghost_icon =
                        self._contract_panel:bitmap(
                        {
                            blend_mode = "add",
                            texture = "guis/textures/pd2/cn_minighost",
                            h = 16,
                            w = 16,
                            color = tweak_data.screen_colors.ghost_color
                        }
                    )

                    ghost_icon:set_center_y(length_text:center_y())
                    ghost_icon:set_left(length_text:right())
                end

                local filled_star_rect = {
                    0,
                    32,
                    32,
                    32
                }
                local empty_star_rect = {
                    32,
                    32,
                    32,
                    32
                }
                local job_stars = managers.job:current_job_stars()
                local job_and_difficulty_stars = managers.job:current_job_and_difficulty_stars()
                local difficulty_stars = managers.job:current_difficulty_stars()
                local risk_color = tweak_data.screen_colors.risk
                local cy = risk_text_header:center_y()
                local sx = risk_text_header:right() + 5
                local difficulty = tweak_data.difficulties[difficulty_stars + 2] or 1
                local difficulty_string_id = tweak_data.difficulty_name_ids[difficulty]
                local difficulty_string = managers.localization:to_upper_text(difficulty_string_id)
                local difficulty_text =
                    self._contract_panel:text(
                    {
                        font = font,
                        font_size = font_size,
                        text = difficulty_string,
                        color = tweak_data.screen_colors.text
                    }
                )

                if Global.game_settings.one_down then
                    local one_down_string =
                        not Global.game_settings.no_down and managers.localization:to_upper_text("menu_one_down") or
                        "NO DOWN"
                    local text_string = difficulty_string .. " " .. one_down_string

                    difficulty_text:set_text(text_string)
                    difficulty_text:set_range_color(
                        utf8.len(difficulty_string) + 1,
                        utf8.len(text_string),
                        not Global.game_settings.no_down and tweak_data.screen_colors.one_down or NoDown.color
                    )
                end

                local _, _, tw, th = difficulty_text:text_rect()

                difficulty_text:set_size(tw, th)
                difficulty_text:set_x(math.round(sx))
                difficulty_text:set_center_y(cy)
                difficulty_text:set_y(math.round(difficulty_text:y()))

                if difficulty_stars > 0 then
                    difficulty_text:set_color(risk_color)
                end

                local plvl = managers.experience:current_level()
                local player_stars = math.max(math.ceil(plvl / 10), 1)
                local contract_visuals = job_data.contract_visuals or {}
                local xp_min =
                    contract_visuals.min_mission_xp and
                    (type(contract_visuals.min_mission_xp) == "table" and
                        contract_visuals.min_mission_xp[difficulty_stars + 1] or
                        contract_visuals.min_mission_xp) or
                    0
                local xp_max =
                    contract_visuals.max_mission_xp and
                    (type(contract_visuals.max_mission_xp) == "table" and
                        contract_visuals.max_mission_xp[difficulty_stars + 1] or
                        contract_visuals.max_mission_xp) or
                    0
                local total_xp_min, _ =
                    managers.experience:get_contract_xp_by_stars(
                    job_id,
                    job_stars,
                    difficulty_stars,
                    job_data.professional,
                    #job_chain,
                    {
                        mission_xp = xp_min
                    }
                )
                local total_xp_max, _ =
                    managers.experience:get_contract_xp_by_stars(
                    job_id,
                    job_stars,
                    difficulty_stars,
                    job_data.professional,
                    #job_chain,
                    {
                        mission_xp = xp_max
                    }
                )
                local xp_text_min = managers.money:add_decimal_marks_to_string(tostring(math.round(total_xp_min)))
                local xp_text_max = managers.money:add_decimal_marks_to_string(tostring(math.round(total_xp_max)))
                local job_xp_text =
                    total_xp_min < total_xp_max and
                    managers.localization:text(
                        "menu_number_range",
                        {
                            min = xp_text_min,
                            max = xp_text_max
                        }
                    ) or
                    xp_text_min
                local job_xp =
                    self._contract_panel:text(
                    {
                        font = font,
                        font_size = font_size,
                        text = job_xp_text,
                        color = tweak_data.screen_colors.text
                    }
                )
                local _, _, tw, th = job_xp:text_rect()

                job_xp:set_size(tw, th)
                job_xp:set_position(math.round(exp_text_header:right() + 5), math.round(exp_text_header:top()))

                local risk_xp =
                    self._contract_panel:text(
                    {
                        font = font,
                        font_size = font_size,
                        text = " +" .. tostring(math.round(0)),
                        color = risk_color
                    }
                )
                local _, _, tw, th = risk_xp:text_rect()

                risk_xp:set_size(tw, th)
                risk_xp:set_position(math.round(job_xp:right()), job_xp:top())
                risk_xp:hide()

                local job_ghost_mul = managers.job:get_ghost_bonus() or 0
                local ghost_xp_text = nil

                if job_ghost_mul ~= 0 then
                    local job_ghost = math.round(job_ghost_mul * 100)
                    local job_ghost_string = tostring(math.abs(job_ghost))
                    local ghost_color = tweak_data.screen_colors.ghost_color

                    if job_ghost == 0 and job_ghost_mul ~= 0 then
                        job_ghost_string = string.format("%0.2f", math.abs(job_ghost_mul * 100))
                    end

                    local text_prefix = job_ghost_mul < 0 and "-" or "+"
                    local text_string = " (" .. text_prefix .. job_ghost_string .. "%)"
                    ghost_xp_text =
                        self._contract_panel:text(
                        {
                            blend_mode = "add",
                            font = font,
                            font_size = font_size,
                            text = text_string,
                            color = ghost_color
                        }
                    )
                    local _, _, tw, th = ghost_xp_text:text_rect()

                    ghost_xp_text:set_size(tw, th)
                    ghost_xp_text:set_position(
                        math.round(risk_xp:visible() and risk_xp:right() or job_xp:right()),
                        job_xp:top()
                    )
                end

                local job_heat = managers.job:current_job_heat() or 0
                local job_heat_mul = managers.job:heat_to_experience_multiplier(job_heat) - 1
                local heat_xp_text = nil

                if job_heat_mul ~= 0 then
                    job_heat = math.round(job_heat_mul * 100)
                    local job_heat_string = tostring(math.abs(job_heat))
                    local heat_color = managers.job:current_job_heat_color()

                    if job_heat == 0 and job_heat_mul ~= 0 then
                        job_heat_string = string.format("%0.2f", math.abs(job_heat_mul * 100))
                    end

                    local text_prefix = job_heat_mul < 0 and "-" or "+"
                    local text_string = " (" .. text_prefix .. job_heat_string .. "%)"
                    heat_xp_text =
                        self._contract_panel:text(
                        {
                            blend_mode = "add",
                            font = font,
                            font_size = font_size,
                            text = text_string,
                            color = heat_color
                        }
                    )
                    local _, _, tw, th = heat_xp_text:text_rect()

                    heat_xp_text:set_size(tw, th)
                    heat_xp_text:set_position(
                        math.round(
                            ghost_xp_text and ghost_xp_text:right() or risk_xp:visible() and risk_xp:right() or
                                job_xp:right()
                        ),
                        job_xp:top()
                    )
                end

                local total_payout_min, base_payout_min, risk_payout_min =
                    managers.money:get_contract_money_by_stars(
                    job_stars,
                    difficulty_stars,
                    #job_chain,
                    managers.job:current_job_id(),
                    managers.job:current_level_id()
                )
                local total_payout_max, base_payout_max, risk_payout_max =
                    managers.money:get_contract_money_by_stars(
                    job_stars,
                    difficulty_stars,
                    #job_chain,
                    managers.job:current_job_id(),
                    managers.job:current_level_id(),
                    {
                        mandatory_bags_value = contract_visuals.mandatory_bags_value and
                            contract_visuals.mandatory_bags_value[difficulty_stars + 1],
                        bonus_bags_value = contract_visuals.bonus_bags_value and
                            contract_visuals.bonus_bags_value[difficulty_stars + 1],
                        small_value = contract_visuals.small_value and
                            contract_visuals.small_value[difficulty_stars + 1],
                        vehicle_value = contract_visuals.vehicle_value and
                            contract_visuals.vehicle_value[difficulty_stars + 1]
                    }
                )
                local payout_text_min = managers.experience:cash_string(math.round(total_payout_min))
                local payout_text_max = managers.experience:cash_string(math.round(total_payout_max))
                local total_payout_text =
                    total_payout_min < total_payout_max and
                    managers.localization:text(
                        "menu_number_range",
                        {
                            min = payout_text_min,
                            max = payout_text_max
                        }
                    ) or
                    payout_text_min
                local job_money =
                    self._contract_panel:text(
                    {
                        font = font,
                        font_size = font_size,
                        text = total_payout_text,
                        color = tweak_data.screen_colors.text
                    }
                )
                local _, _, tw, th = job_money:text_rect()

                job_money:set_size(tw, th)
                job_money:set_position(math.round(payout_text_header:right() + 5), math.round(payout_text_header:top()))

                local risk_money =
                    self._contract_panel:text(
                    {
                        font = font,
                        font_size = font_size,
                        text = " +" .. managers.experience:cash_string(math.round(risk_payout_min)),
                        color = risk_color
                    }
                )
                local _, _, tw, th = risk_money:text_rect()

                risk_money:set_size(tw, th)
                risk_money:set_position(math.round(job_money:right()), job_money:top())
                risk_money:hide()
                self._contract_panel:set_h(payout_text_header:bottom() + 10)

                if
                    managers.mutators:are_mutators_enabled() and
                        managers.mutators:allow_mutators_in_level(job_chain and job_chain[1] and job_chain[1].level_id)
                 then
                    local mutators_text_header =
                        self._contract_panel:text(
                        {
                            name = "mutators_text_header",
                            text = managers.localization:to_upper_text("cn_menu_contract_mutators_header"),
                            font_size = font_size,
                            font = font,
                            color = tweak_data.screen_colors.text
                        }
                    )
                    local _, _, tw, th = mutators_text_header:text_rect()
                    w = math.max(w, tw)

                    mutators_text_header:set_size(tw, th)
                    mutators_text_header:set_right(w)
                    mutators_text_header:set_top(payout_text_header:bottom())

                    local mutators_text =
                        self._contract_panel:text(
                        {
                            name = "mutators_text",
                            font = font,
                            font_size = font_size,
                            text = managers.localization:to_upper_text("cn_menu_contract_mutators_active"),
                            color = tweak_data.screen_colors.mutators_color_text
                        }
                    )
                    local _, _, tw, th = mutators_text:text_rect()

                    mutators_text:set_size(tw, th)
                    mutators_text:set_position(
                        math.round(mutators_text_header:right() + 5),
                        math.round(mutators_text_header:top())
                    )
                    self._contract_panel:set_h(mutators_text:bottom() + 10)
                end
            elseif managers.menu:debug_menu_enabled() then
                local debug_start =
                    self._contract_panel:text(
                    {
                        text = "Use DEBUG START to start your level",
                        y = 10,
                        wrap = true,
                        x = 10,
                        word_wrap = true,
                        font_size = font_size,
                        font = font,
                        color = tweak_data.screen_colors.text
                    }
                )

                debug_start:grow(-debug_start:x() - 10, debug_start:y() - 10)
            end

            self._contract_panel:set_rightbottom(self._panel:w() - 0, self._panel:h() - 60)

            if self._contract_text_header then
                self._contract_text_header:set_bottom(self._contract_panel:top())
                self._contract_text_header:set_left(self._contract_panel:left())

                local wfs_text = self._panel:child("wfs")

                if wfs_text and not managers.menu:is_pc_controller() then
                    wfs_text:set_rightbottom(self._panel:w() - 20, self._contract_text_header:top())
                end
            end

            local wfs = self._panel:child("wfs")

            if wfs then
                self._contract_panel:grow(0, wfs:h() + 5)
                self._contract_panel:move(0, -(wfs:h() + 5))

                if self._contract_text_header then
                    self._contract_text_header:move(0, -(wfs:h() + 5))
                end

                wfs:set_world_rightbottom(self._contract_panel:world_right() - 5, self._contract_panel:world_bottom())
            end

            if job_tweak and job_tweak.is_safehouse and not job_tweak.is_safehouse_combat then
                self._contract_text_header:set_bottom(self._contract_panel:bottom())
                self._contract_panel:set_h(0)
            end

            BoxGuiObject:new(
                self._contract_panel,
                {
                    sides = {
                        1,
                        1,
                        1,
                        1
                    }
                }
            )

            for i = 1, tweak_data.max_players do
                local peer = managers.network:session():peer(i)

                if peer then
                    local peer_pos = managers.menu_scene:character_screen_position(i)
                    local peer_name = peer:name()

                    if peer_pos then
                        self:create_character_text(i, peer_pos.x, peer_pos.y, peer_name)
                    end
                end
            end

            self._enabled = true
        end
    elseif RequiredScript == "lib/managers/menu/crimenetcontractgui" then
        function CrimeNetContractGui:init(ws, fullscreen_ws, node)
            self._ws = ws
            self._fullscreen_ws = fullscreen_ws
            self._panel =
                self._ws:panel():panel(
                {
                    layer = 51
                }
            )
            self._fullscreen_panel =
                self._fullscreen_ws:panel():panel(
                {
                    layer = 50
                }
            )

            self._fullscreen_panel:rect(
                {
                    alpha = 0.75,
                    layer = 0,
                    color = Color.black
                }
            )

            self._node = node
            local job_data = self._node:parameters().menu_component_data
            self._customizable = job_data.customize_contract or false
            self._smart_matchmaking = job_data.smart_matchmaking or false
            local font_size = tweak_data.menu.pd2_small_font_size
            local font = tweak_data.menu.pd2_small_font
            local risk_color = tweak_data.screen_colors.risk
            local padding = tweak_data.gui.crime_net.contract_gui.padding
            local half_padding = 0.5 * padding
            local double_padding = 2 * padding
            local width = tweak_data.gui.crime_net.contract_gui.width
            local height = tweak_data.gui.crime_net.contract_gui.height
            local text_w = tweak_data.gui.crime_net.contract_gui.text_width
            local contact_w = tweak_data.gui.crime_net.contract_gui.contact_width
            local contact_h = contact_w / 1.7777777777777777
            local blur =
                self._fullscreen_panel:bitmap(
                {
                    texture = "guis/textures/test_blur_df",
                    render_template = "VertexColorTexturedBlur3D",
                    layer = 1,
                    w = self._fullscreen_ws:panel():w(),
                    h = self._fullscreen_ws:panel():h()
                }
            )

            local function func(o)
                local start_blur = 0

                over(
                    0.6,
                    function(p)
                        o:set_alpha(math.lerp(start_blur, 1, p))
                    end
                )
            end

            blur:animate(func)

            self._contact_text_header =
                self._panel:text(
                {
                    text = " ",
                    vertical = "top",
                    align = "left",
                    layer = 1,
                    font_size = tweak_data.menu.pd2_large_font_size,
                    font = tweak_data.menu.pd2_large_font,
                    color = tweak_data.screen_colors.text
                }
            )
            local x, y, w, h = self._contact_text_header:text_rect()

            self._contact_text_header:set_size(width, h)
            self._contact_text_header:set_center_x(self._panel:w() * 0.5)

            self._contract_panel =
                self._panel:panel(
                {
                    layer = 5,
                    h = height,
                    w = width,
                    x = self._contact_text_header:x(),
                    y = self._contact_text_header:bottom()
                }
            )

            self._contract_panel:set_center_y(self._panel:h() * 0.5)
            self._contact_text_header:set_bottom(self._contract_panel:top())

            if self._contact_text_header:y() < 0 then
                local y_offset = -self._contact_text_header:y()

                self._contact_text_header:move(0, y_offset)
                self._contract_panel:move(0, y_offset)
            end

            if not job_data.job_id then
                local bottom = self._contract_panel:bottom()

                self._contract_panel:set_h(160)
                self._contract_panel:set_bottom(bottom)
                self._contact_text_header:set_bottom(self._contract_panel:top())

                local host_name = job_data.host_name or ""
                local num_players = job_data.num_plrs or 1
                local server_text = managers.localization:to_upper_text("menu_lobby_server_title") .. " " .. host_name
                local players_text =
                    managers.localization:to_upper_text(
                    "menu_players_online",
                    {
                        COUNT = tostring(num_players)
                    }
                )

                self._contact_text_header:set_text(server_text .. "\n" .. players_text)
                self._contact_text_header:set_font(tweak_data.menu.pd2_medium_font_id)
                self._contact_text_header:set_font_size(tweak_data.menu.pd2_medium_font_size)

                local x, y, w, h = self._contact_text_header:text_rect()

                self._contact_text_header:set_size(width, h)
                self._contact_text_header:set_top(self._contract_panel:top())
                self._contact_text_header:move(padding, padding)
                BoxGuiObject:new(
                    self._contract_panel,
                    {
                        sides = {
                            1,
                            1,
                            1,
                            1
                        }
                    }
                )

                self._step = 1
                self._steps = {}

                return
            end

            BoxGuiObject:new(
                self._contract_panel,
                {
                    sides = {
                        1,
                        1,
                        1,
                        1
                    }
                }
            )

            job_data.job_id = job_data.job_id or "ukrainian_job"
            local narrative = tweak_data.narrative:job_data(job_data.job_id)
            local narrative_chains = tweak_data.narrative:job_chain(job_data.job_id)

            self._contact_text_header:set_text(
                managers.localization:to_upper_text(
                    "menu_cn_contract_title",
                    {
                        job = managers.localization:text(narrative.name_id)
                    }
                )
            )

            local last_bottom = 0
            local contract_text =
                self._contract_panel:text(
                {
                    vertical = "top",
                    wrap = true,
                    align = "left",
                    wrap_word = true,
                    text = managers.localization:text(narrative.briefing_id),
                    w = text_w,
                    font_size = font_size,
                    font = font,
                    color = tweak_data.screen_colors.text,
                    x = padding,
                    y = padding
                }
            )
            local _, _, _, h = contract_text:text_rect()
            local scale = 1

            if h + contract_text:top() > math.round(self._contract_panel:h() * 0.5) - font_size then
                scale = (math.round(self._contract_panel:h() * 0.5) - font_size) / (h + contract_text:top())
            end

            contract_text:set_font_size(font_size * scale)
            self:make_fine_text(contract_text)

            last_bottom = contract_text:bottom()
            local is_job_ghostable = managers.job:is_job_ghostable(job_data.job_id)

            if is_job_ghostable then
                local min_ghost_bonus, max_ghost_bonus = managers.job:get_job_ghost_bonus(job_data.job_id)
                local min_ghost = math.round(min_ghost_bonus * 100)
                local max_ghost = math.round(max_ghost_bonus * 100)
                local min_string, max_string = nil

                if min_ghost == 0 and min_ghost_bonus ~= 0 then
                    min_string = string.format("%0.2f", math.abs(min_ghost_bonus * 100))
                else
                    min_string = tostring(math.abs(min_ghost))
                end

                if max_ghost == 0 and max_ghost_bonus ~= 0 then
                    max_string = string.format("%0.2f", math.abs(max_ghost_bonus * 100))
                else
                    max_string = tostring(math.abs(max_ghost))
                end

                local ghost_bonus_string =
                    min_ghost_bonus == max_ghost_bonus and min_string or min_string .. "-" .. max_string
                local ghostable_text =
                    self._contract_panel:text(
                    {
                        vertical = "top",
                        wrap = true,
                        align = "left",
                        wrap_word = true,
                        blend_mode = "add",
                        text = managers.localization:to_upper_text(
                            "menu_ghostable_job",
                            {
                                bonus = ghost_bonus_string
                            }
                        ),
                        w = text_w,
                        font_size = font_size,
                        font = font,
                        color = tweak_data.screen_colors.ghost_color
                    }
                )

                ghostable_text:set_position(contract_text:x(), last_bottom + padding)
                self:make_fine_text(ghostable_text)

                last_bottom = ghostable_text:bottom()
            end

            if tweak_data.narrative:is_job_locked(job_data.job_id) then
                local locked_text =
                    self._contract_panel:text(
                    {
                        font = tweak_data.menu.pd2_small_font,
                        font_size = font_size,
                        text = managers.localization:to_upper_text("bm_menu_vr_locked"),
                        color = tweak_data.screen_colors.important_1
                    }
                )

                self:make_fine_text(locked_text)
                locked_text:set_position(contract_text:x(), last_bottom + padding)
            end

            local contact_panel =
                self._contract_panel:panel(
                {
                    w = contact_w,
                    h = contact_h,
                    x = text_w + double_padding,
                    y = padding
                }
            )
            local contact_image =
                contact_panel:rect(
                {
                    color = Color(0.3, 0, 0, 0)
                }
            )
            local crimenet_videos = narrative.crimenet_videos

            if crimenet_videos then
                local variant = math.random(#crimenet_videos)

                contact_panel:video(
                    {
                        blend_mode = "add",
                        loop = true,
                        video = "movies/" .. crimenet_videos[variant],
                        width = contact_panel:w(),
                        height = contact_panel:h(),
                        color = tweak_data.screen_colors.button_stage_2
                    }
                )
            end

            local contact_text =
                self._contract_panel:text(
                {
                    text = managers.localization:to_upper_text(tweak_data.narrative.contacts[narrative.contact].name_id),
                    font_size = font_size,
                    font = font,
                    color = tweak_data.screen_colors.text
                }
            )
            local x, y, w, h = contact_text:text_rect()

            contact_text:set_size(w, h)
            contact_text:set_position(contact_panel:left(), contact_panel:bottom() + half_padding)
            BoxGuiObject:new(
                contact_panel,
                {
                    sides = {
                        1,
                        1,
                        1,
                        1
                    }
                }
            )

            local modifiers_text =
                self._contract_panel:text(
                {
                    name = "modifiers_text",
                    vertical = "top",
                    align = "left",
                    text = managers.localization:to_upper_text("menu_cn_modifiers"),
                    font = font,
                    font_size = font_size,
                    x = padding,
                    color = tweak_data.screen_colors.text,
                    w = text_w
                }
            )

            self:make_fine_text(modifiers_text)
            modifiers_text:set_bottom(math.round(self._contract_panel:h() * 0.5 - font_size))

            local next_top = modifiers_text:bottom()
            local one_down_active = job_data.one_down == 1

            if one_down_active then
                local one_down_warning_text =
                    self._contract_panel:text(
                    {
                        name = "one_down_warning_text",
                        text = managers.localization:to_upper_text("menu_one_down"),
                        font = font,
                        font_size = font_size,
                        color = tweak_data.screen_colors.one_down
                    }
                )

                self:make_fine_text(one_down_warning_text)
                one_down_warning_text:set_top(next_top)
                one_down_warning_text:set_left(double_padding)

                next_top = one_down_warning_text:bottom()

                if job_data.no_down == 1 then
                    one_down_warning_text:set_text("NO DOWN")
                    one_down_warning_text:set_color(NoDown.color)
                end
            end

            local ghost_bonus_mul = managers.job:get_ghost_bonus()
            local skill_bonus = managers.player:get_skill_exp_multiplier()
            local infamy_bonus = managers.player:get_infamy_exp_multiplier()
            local limited_bonus = managers.player:get_limited_exp_multiplier(job_data.job_id, nil)
            local job_ghost = math.round(ghost_bonus_mul * 100)
            local job_ghost_string = tostring(math.abs(job_ghost))
            local has_ghost_bonus = ghost_bonus_mul > 0

            if job_ghost == 0 and ghost_bonus_mul ~= 0 then
                job_ghost_string = string.format("%0.2f", math.abs(ghost_bonus_mul * 100))
            end

            local ghost_color = tweak_data.screen_colors.ghost_color
            local ghost_warning_text =
                self._contract_panel:text(
                {
                    name = "ghost_color_warning_text",
                    vertical = "top",
                    word_wrap = true,
                    wrap = true,
                    align = "left",
                    blend_mode = "normal",
                    text = managers.localization:to_upper_text(
                        "menu_ghost_bonus",
                        {
                            exp_bonus = job_ghost_string
                        }
                    ),
                    font = font,
                    font_size = font_size,
                    color = ghost_color,
                    w = text_w
                }
            )

            self:make_fine_text(ghost_warning_text)
            ghost_warning_text:set_top(next_top)
            ghost_warning_text:set_left(double_padding)
            ghost_warning_text:set_visible(has_ghost_bonus)

            if ghost_warning_text:visible() then
                next_top = ghost_warning_text:bottom()
            end

            local job_heat_value = managers.job:get_job_heat(job_data.job_id)
            local ignore_heat = job_heat_value > 0 and self._customizable
            local job_heat_mul = ignore_heat and 0 or managers.job:get_job_heat_multipliers(job_data.job_id) - 1
            local job_heat = math.round(job_heat_mul * 100)
            local job_heat_string = tostring(math.abs(job_heat))
            local is_job_heated = job_heat ~= 0 or job_heat_mul ~= 0

            if job_heat == 0 and job_heat_mul ~= 0 then
                job_heat_string = string.format("%0.2f", math.abs(job_heat_mul * 100))
            end

            self._is_job_heated = is_job_heated
            local heat_color = managers.job:get_job_heat_color(job_data.job_id)
            local heat_text_id = "menu_heat_" .. (job_heat_mul > 0 and "warm" or job_heat_mul < 0 and "cold" or "ok")
            local heat_warning_text =
                self._contract_panel:text(
                {
                    name = "heat_warning_text",
                    vertical = "top",
                    word_wrap = true,
                    wrap = true,
                    align = "left",
                    blend_mode = "normal",
                    text = managers.localization:to_upper_text(
                        heat_text_id,
                        {
                            job_heat = job_heat_string
                        }
                    ),
                    font = font,
                    font_size = font_size,
                    color = heat_color,
                    w = text_w
                }
            )

            self:make_fine_text(heat_warning_text)
            heat_warning_text:set_top(next_top)
            heat_warning_text:set_left(double_padding)
            heat_warning_text:set_visible(is_job_heated)

            self._heat_color = heat_color

            if heat_warning_text:visible() then
                next_top = heat_warning_text:bottom()
            end

            local pro_warning_text =
                self._contract_panel:text(
                {
                    name = "pro_warning_text",
                    vertical = "top",
                    word_wrap = true,
                    wrap = true,
                    align = "left",
                    blend_mode = "normal",
                    text = managers.localization:to_upper_text("menu_pro_warning"),
                    font = font,
                    font_size = font_size,
                    color = tweak_data.screen_colors.pro_color,
                    w = text_w
                }
            )

            self:make_fine_text(pro_warning_text)
            pro_warning_text:set_h(pro_warning_text:h())
            pro_warning_text:set_left(double_padding)
            pro_warning_text:set_top(next_top)
            pro_warning_text:set_visible(narrative.professional)

            if pro_warning_text:visible() then
                next_top = pro_warning_text:bottom()
            end

            local is_christmas_job = managers.job:is_christmas_job(job_data.job_id)

            if is_christmas_job then
                local holiday_potential_bonus = managers.job:get_job_christmas_bonus(job_data.job_id)
                local holiday_bonus_percentage = math.round(holiday_potential_bonus * 100)

                if holiday_bonus_percentage ~= 0 then
                    local holiday_string = tostring(holiday_bonus_percentage)
                    local holiday_text =
                        self._contract_panel:text(
                        {
                            vertical = "top",
                            wrap = true,
                            align = "left",
                            wrap_word = true,
                            blend_mode = "normal",
                            text = managers.localization:to_upper_text(
                                "holiday_warning_text",
                                {
                                    event_icon = managers.localization:get_default_macro("BTN_XMAS"),
                                    bonus = holiday_string
                                }
                            ),
                            w = text_w,
                            font_size = font_size,
                            font = font,
                            color = tweak_data.screen_colors.event_color
                        }
                    )

                    holiday_text:set_position(double_padding, next_top)
                    self:make_fine_text(holiday_text)

                    next_top = holiday_text:bottom()
                end
            end

            modifiers_text:set_visible(
                heat_warning_text:visible() or one_down_active or pro_warning_text:visible() or
                    ghost_warning_text:visible()
            )

            local risk_title =
                self._contract_panel:text(
                {
                    font = font,
                    font_size = font_size,
                    text = managers.localization:to_upper_text("menu_risk"),
                    color = risk_color,
                    x = padding
                }
            )

            self:make_fine_text(risk_title)
            risk_title:set_top(next_top)

            next_top = next_top + half_padding
            local menu_risk_id = "menu_risk_pd"

            if job_data.difficulty == "hard" then
                menu_risk_id = "menu_risk_swat"
            elseif job_data.difficulty == "overkill" then
                menu_risk_id = "menu_risk_fbi"
            elseif job_data.difficulty == "overkill_145" then
                menu_risk_id = "menu_risk_special"
            elseif job_data.difficulty == "easy_wish" then
                menu_risk_id = "menu_risk_easy_wish"
            elseif job_data.difficulty == "overkill_290" then
                menu_risk_id = "menu_risk_elite"
            elseif job_data.difficulty == "sm_wish" then
                menu_risk_id = "menu_risk_sm_wish"
            end

            local risk_stats_panel =
                self._contract_panel:panel(
                {
                    name = "risk_stats_panel",
                    w = text_w,
                    x = padding
                }
            )

            risk_stats_panel:set_h(risk_title:h() + half_padding)

            local plvl = managers.experience:current_level()
            local player_stars = math.max(math.ceil(plvl / 10), 1)
            local job_stars = math.ceil(narrative.jc / 10)
            local difficulty_stars = job_data.difficulty_id - 2
            local job_and_difficulty_stars = job_stars + difficulty_stars
            local rsx = 15
            local risks = {
                "risk_pd",
                "risk_swat",
                "risk_fbi",
                "risk_death_squad",
                "risk_easy_wish"
            }

            if not Global.SKIP_OVERKILL_290 then
                table.insert(risks, "risk_murder_squad")
                table.insert(risks, "risk_sm_wish")
            end

            local max_x = 0
            local max_y = 0

            for i, name in ipairs(risks) do
                if i ~= 1 then
                    local texture, rect = tweak_data.hud_icons:get_icon_data(name)
                    local active = false
                    local color = active and i ~= 1 and risk_color or Color.white
                    local alpha = active and 1 or 0.25
                    local risk =
                        self._contract_panel:bitmap(
                        {
                            y = 0,
                            x = 0,
                            name = name,
                            texture = texture,
                            texture_rect = rect,
                            alpha = alpha,
                            color = color
                        }
                    )

                    risk:set_x(rsx)
                    risk:set_top(math.round(risk_title:bottom()))

                    rsx = rsx + risk:w() + 2
                    local stat =
                        managers.statistics:completed_job(job_data.job_id, tweak_data:index_to_difficulty(i + 1))
                    local risk_stat =
                        risk_stats_panel:text(
                        {
                            align = "center",
                            name = name,
                            font = font,
                            font_size = font_size,
                            text = tostring(stat)
                        }
                    )

                    self:make_fine_text(risk_stat)
                    risk_stat:set_world_center_x(risk:world_center_x() - 1)
                    risk_stat:set_x(math.round(risk_stat:x()))

                    local this_difficulty = i == difficulty_stars + 1
                    active = i <= difficulty_stars + 1
                    color = Color.white
                    alpha = 0.5

                    risk_stat:set_color(color)
                    risk_stat:set_alpha(alpha)

                    max_y = math.max(max_y, risk:bottom())
                    max_x = math.max(max_x, risk:right() + half_padding)
                    max_x = math.max(max_x, risk_stat:right() + risk_stats_panel:left() + padding)
                end
            end

            risk_stats_panel:set_top(math.round(max_y + 2))

            local stat =
                managers.statistics:completed_job(job_data.job_id, tweak_data:index_to_difficulty(difficulty_stars + 2))
            local risk_text =
                self._contract_panel:text(
                {
                    vertical = "top",
                    name = "risk_text",
                    wrap = true,
                    align = "left",
                    word_wrap = true,
                    w = text_w - max_x,
                    text = managers.localization:to_upper_text(menu_risk_id) ..
                        " " ..
                            managers.localization:to_upper_text(
                                "menu_stat_job_completed",
                                {
                                    stat = tostring(stat)
                                }
                            ) ..
                                " ",
                    font = font,
                    font_size = font_size,
                    color = risk_color,
                    x = max_x
                }
            )

            risk_text:set_top(math.round(risk_title:bottom()))
            risk_text:set_h(risk_stats_panel:bottom() - risk_text:top())
            risk_text:hide()

            local potential_rewards_title =
                self._contract_panel:text(
                {
                    blend_mode = "add",
                    font = font,
                    font_size = font_size,
                    text = managers.localization:to_upper_text(
                        self._customizable and "menu_potential_rewards_min" or "menu_potential_rewards",
                        {
                            BTN_Y = managers.localization:btn_macro("menu_modify_item")
                        }
                    ),
                    color = managers.menu:is_pc_controller() and self._customizable and
                        tweak_data.screen_colors.button_stage_3 or
                        tweak_data.screen_colors.text,
                    x = padding
                }
            )

            self:make_fine_text(potential_rewards_title)
            potential_rewards_title:set_top(math.round(risk_stats_panel:bottom() + 4))

            local jobpay_title =
                self._contract_panel:text(
                {
                    x = 20,
                    font = font,
                    font_size = font_size,
                    text = managers.localization:to_upper_text("cn_menu_contract_jobpay_header"),
                    color = tweak_data.screen_colors.text
                }
            )

            self:make_fine_text(jobpay_title)
            jobpay_title:set_top(math.round(potential_rewards_title:bottom()))

            self._potential_rewards_title = potential_rewards_title
            local experience_title =
                self._contract_panel:text(
                {
                    x = 20,
                    font = font,
                    font_size = font_size,
                    text = managers.localization:to_upper_text("menu_experience"),
                    color = tweak_data.screen_colors.text
                }
            )

            self:make_fine_text(experience_title)
            experience_title:set_top(math.round(jobpay_title:bottom()))

            local sx = math.max(jobpay_title:right(), experience_title:right())
            sx = sx + 8
            local filled_star_rect = {
                0,
                32,
                32,
                32
            }
            local empty_star_rect = {
                32,
                32,
                32,
                32
            }
            local contract_visuals = job_data.contract_visuals or {}
            local cy = experience_title:center_y()
            local xp_min =
                contract_visuals.min_mission_xp and
                (type(contract_visuals.min_mission_xp) == "table" and
                    contract_visuals.min_mission_xp[difficulty_stars + 1] or
                    contract_visuals.min_mission_xp) or
                0
            local total_xp, dissected_xp =
                managers.experience:get_contract_xp_by_stars(
                job_data.job_id,
                job_stars,
                difficulty_stars,
                narrative.professional,
                #narrative_chains,
                {
                    ignore_heat = job_heat_value > 0 and self._customizable,
                    mission_xp = xp_min
                }
            )
            local base_xp, risk_xp, heat_base_xp, heat_risk_xp, ghost_base_xp, ghost_risk_xp = unpack(dissected_xp)
            local job_xp, add_xp, heat_add_xp, ghost_add_xp = self:_create_xp_appendices(sx, cy)
            cy = jobpay_title:center_y()
            local total_payout, base_payout, risk_payout =
                managers.money:get_contract_money_by_stars(
                job_stars,
                difficulty_stars,
                #narrative_chains,
                job_data.job_id
            )
            local job_cash =
                self._contract_panel:text(
                {
                    name = "job_cash",
                    font = font,
                    font_size = font_size,
                    text = managers.experience:cash_string(0),
                    color = tweak_data.screen_colors.text
                }
            )

            self:make_fine_text(job_cash)
            job_cash:set_x(sx)
            job_cash:set_center_y(math.round(cy))

            local add_cash =
                self._contract_panel:text(
                {
                    text = "",
                    name = "job_add_cash",
                    font = font,
                    font_size = font_size,
                    color = risk_color
                }
            )

            add_cash:set_text(" +" .. managers.experience:cash_string(math.round(0)))
            self:make_fine_text(add_cash)
            add_cash:set_x(math.round(job_cash:right()))
            add_cash:set_center_y(math.round(cy))

            local payday_money = math.round(total_payout)
            local payday_text =
                self._contract_panel:text(
                {
                    name = "payday_text",
                    font = tweak_data.menu.pd2_large_font,
                    font_size = tweak_data.menu.pd2_large_font_size,
                    text = managers.localization:to_upper_text(
                        "menu_payday",
                        {
                            MONEY = managers.experience:cash_string(0)
                        }
                    ),
                    color = tweak_data.screen_colors.text,
                    x = padding
                }
            )

            self:make_fine_text(payday_text)
            payday_text:set_bottom(self._contract_panel:h() - padding)

            self._briefing_event = narrative.briefing_event

            if self._briefing_event then
                self._briefing_len_panel =
                    self._contract_panel:panel(
                    {
                        w = contact_image:w(),
                        h = 2 * (font_size + padding)
                    }
                )

                self._briefing_len_panel:rect(
                    {
                        blend_mode = "add",
                        name = "duration",
                        w = 0,
                        halign = "grow",
                        alpha = 0.6,
                        valign = "grow",
                        color = tweak_data.screen_colors.button_stage_3:with_alpha(0.2)
                    }
                )
                self._briefing_len_panel:text(
                    {
                        blend_mode = "add",
                        name = "text",
                        text = "",
                        layer = 1,
                        font = font,
                        font_size = font_size,
                        color = tweak_data.screen_colors.text,
                        x = padding,
                        y = padding
                    }
                )

                local button_text =
                    self._briefing_len_panel:text(
                    {
                        blend_mode = "add",
                        name = "button_text",
                        text = " ",
                        layer = 1,
                        font = font,
                        font_size = font_size,
                        color = tweak_data.screen_colors.text,
                        x = padding,
                        y = padding
                    }
                )
                local _, _, _, h = button_text:text_rect()

                self._briefing_len_panel:set_h(2 * (h + padding))

                if managers.menu:is_pc_controller() then
                    button_text:set_color(tweak_data.screen_colors.button_stage_3)
                end

                BoxGuiObject:new(
                    self._briefing_len_panel,
                    {
                        sides = {
                            1,
                            1,
                            1,
                            1
                        }
                    }
                )
                self._briefing_len_panel:set_position(contact_text:left(), contact_text:bottom() + padding)
            end

            self._tabs = {}
            self._pages = {}
            self._active_page = nil
            local tabs_panel =
                self._contract_panel:panel(
                {
                    y = 10,
                    w = contact_w,
                    h = contact_h,
                    x = text_w + 20
                }
            )

            tabs_panel:set_top(
                (self._briefing_len_panel and self._briefing_len_panel:bottom() or contact_text:bottom()) + 10
            )
            tabs_panel:set_visible(false)

            local pages_panel = self._contract_panel:panel({})

            pages_panel:set_visible(false)

            local function add_tab(text_id)
                local prev_tab = self._tabs[#self._tabs]
                local tab_item = MenuGuiSmallTabItem:new(#self._tabs + 1, text_id, nil, self, 0, tabs_panel)

                table.insert(self._tabs, tab_item)

                if prev_tab then
                    tab_item._page_panel:set_left(prev_tab:next_page_position())
                end

                if #self._tabs == 1 then
                    tab_item:set_active(true)

                    self._active_page = 1

                    tabs_panel:set_visible(true)
                    pages_panel:set_visible(true)
                    tabs_panel:set_h(tab_item._page_panel:bottom())
                    pages_panel:set_size(contact_w, contact_h - tabs_panel:h())
                    pages_panel:set_lefttop(tabs_panel:left(), tabs_panel:bottom() - 2)
                    BoxGuiObject:new(
                        pages_panel,
                        {
                            sides = {
                                1,
                                1,
                                2,
                                1
                            }
                        }
                    )
                    managers.menu:active_menu().input:set_force_input(true)
                end

                local page_panel = pages_panel:panel({})

                page_panel:set_visible(tab_item:is_active())
                table.insert(self._pages, page_panel)

                return page_panel
            end

            if job_data.mutators then
                managers.mutators:set_crimenet_lobby_data(job_data.mutators)

                local mutators_panel = add_tab("menu_cn_mutators_active")
                self._mutators_scroll =
                    ScrollablePanel:new(
                    mutators_panel,
                    "mutators_scroll",
                    {
                        padding = 0
                    }
                )
                local _y = half_padding
                local mutators_list = {}
                local last_item = nil

                for mutator_id, mutator_data in pairs(job_data.mutators) do
                    local mutator = managers.mutators:get_mutator_from_id(mutator_id)

                    if mutator then
                        table.insert(mutators_list, mutator)
                    end
                end

                table.sort(
                    mutators_list,
                    function(a, b)
                        return a:name() < b:name()
                    end
                )

                for i, mutator in ipairs(mutators_list) do
                    local mutator_text =
                        self._mutators_scroll:canvas():text(
                        {
                            name = "mutator_text_" .. tostring(i),
                            font = tweak_data.menu.pd2_small_font,
                            font_size = tweak_data.menu.pd2_small_font_size,
                            text = mutator:name(),
                            x = padding,
                            y = _y,
                            h = tweak_data.menu.pd2_small_font_size
                        }
                    )
                    _y = mutator_text:bottom() + 2
                    last_item = mutator_text
                end

                last_item:set_h(last_item:h() + padding)
                self._mutators_scroll:update_canvas_size()
                managers.mutators:set_crimenet_lobby_data(nil)
            end

            if job_data.server == true then
                local content_panel = add_tab("menu_cn_game_settings")
                local _y = 7
                local add_back = true

                local function add_line(left_text, right_text)
                    if right_text == nil or left_text == nil then
                        return
                    end

                    if add_back then
                        content_panel:rect(
                            {
                                x = 8,
                                layer = -1,
                                y = _y,
                                h = tweak_data.menu.pd2_small_font_size,
                                w = content_panel:w() - 18,
                                color = Color.black:with_alpha(0.7)
                            }
                        )
                    end

                    add_back = not add_back
                    left_text = managers.localization:to_upper_text(left_text)
                    right_text =
                        type(right_text) == "number" and tostring(right_text) or
                        managers.localization:to_upper_text(right_text)
                    local left =
                        content_panel:text(
                        {
                            align = "left",
                            font = tweak_data.menu.pd2_small_font,
                            font_size = tweak_data.menu.pd2_small_font_size,
                            text = left_text,
                            x = padding,
                            y = _y,
                            h = tweak_data.menu.pd2_small_font_size,
                            w = content_panel:w() - double_padding,
                            color = Color(0.8, 0.8, 0.8)
                        }
                    )
                    local right =
                        content_panel:text(
                        {
                            align = "right",
                            font = tweak_data.menu.pd2_small_font,
                            font_size = tweak_data.menu.pd2_small_font_size,
                            text = right_text .. " ",
                            x = padding,
                            y = _y,
                            h = tweak_data.menu.pd2_small_font_size,
                            w = content_panel:w() - 20,
                            color = Color(0.5, 0.5, 0.5)
                        }
                    )
                    _y = math.max(left:bottom(), right:bottom()) + 2
                end

                local server_data = job_data.server_data
                local tactics = {
                    "menu_plan_loud",
                    "menu_plan_stealth",
                    [-1.0] = "menu_any"
                }
                local kick = {
                    [0] = "menu_kick_disabled",
                    "menu_kick_server",
                    "menu_kick_vote"
                }
                local drop_in = {
                    [0] = "menu_off",
                    "menu_drop_in_on",
                    "menu_drop_in_prompt",
                    "menu_drop_in_stealth_prompt"
                }
                local permission = {
                    "menu_public_game",
                    "menu_friends_only_game",
                    "menu_private_game"
                }

                add_line("menu_preferred_plan", tactics[server_data.job_plan])
                add_line("menu_kicking_allowed_option", kick[server_data.kick_option])
                add_line("menu_permission", permission[server_data.permission])
                add_line("menu_reputation_permission", server_data.min_level or 0)
                add_line("menu_toggle_drop_in", drop_in[server_data.drop_in])
            end

            if job_data.mods then
                local mods_presence = job_data.mods

                if mods_presence and mods_presence ~= "" and mods_presence ~= "1" then
                    local content_panel = add_tab("menu_cn_game_mods")
                    self._mods_tab = self._tabs[#self._tabs]
                    self._mods_scroll =
                        ScrollablePanel:new(
                        content_panel,
                        "mods_scroll",
                        {
                            padding = 0
                        }
                    )
                    self._mod_items = {}
                    local _y = 7
                    local add_back = true

                    local function add_line(id, text, ignore_back)
                        local canvas = self._mods_scroll:canvas()

                        if add_back and not ignore_back then
                            canvas:rect(
                                {
                                    x = 8,
                                    layer = -1,
                                    y = _y,
                                    h = tweak_data.menu.pd2_small_font_size,
                                    w = canvas:w() - 18,
                                    color = Color.black:with_alpha(0.7)
                                }
                            )
                        end

                        add_back = not add_back
                        text = string.upper(text)
                        local left_text =
                            canvas:text(
                            {
                                align = "left",
                                name = id,
                                font = tweak_data.menu.pd2_small_font,
                                font_size = tweak_data.menu.pd2_small_font_size,
                                text = text,
                                x = padding,
                                y = _y,
                                h = tweak_data.menu.pd2_small_font_size,
                                w = canvas:w() - double_padding,
                                color = Color(0.8, 0.8, 0.8)
                            }
                        )
                        local highlight_text =
                            canvas:text(
                            {
                                blend_mode = "add",
                                align = "left",
                                visible = false,
                                name = id,
                                font = tweak_data.menu.pd2_small_font,
                                font_size = tweak_data.menu.pd2_small_font_size,
                                text = text,
                                x = padding,
                                y = _y,
                                h = tweak_data.menu.pd2_small_font_size,
                                w = canvas:w() - double_padding,
                                color = tweak_data.screen_colors.button_stage_2
                            }
                        )
                        _y = left_text:bottom() + 2

                        return left_text, highlight_text
                    end

                    local splits = string.split(mods_presence, "|")

                    for i = 1, #splits, 2 do
                        local text, highlight = add_line(splits[i + 1] or "", splits[i] or "")

                        table.insert(
                            self._mod_items,
                            {
                                text,
                                highlight
                            }
                        )
                    end

                    add_line("spacer", "", true)
                    self._mods_scroll:update_canvas_size()
                end
            end

            local days_multiplier = 0

            for i = 1, #narrative_chains do
                local day_mul =
                    narrative.professional and tweak_data:get_value("experience_manager", "pro_day_multiplier", i) or
                    tweak_data:get_value("experience_manager", "day_multiplier", i)
                days_multiplier = days_multiplier + day_mul - 1
            end

            days_multiplier = 1 + days_multiplier / #narrative_chains
            local last_day_mul =
                narrative.professional and
                tweak_data:get_value("experience_manager", "pro_day_multiplier", #narrative_chains) or
                tweak_data:get_value("experience_manager", "day_multiplier", #narrative_chains)
            self._data = {
                job_cash = base_payout,
                add_job_cash = risk_payout,
                experience = base_xp,
                add_experience = risk_xp,
                heat_experience = heat_base_xp,
                heat_add_experience = heat_risk_xp,
                ghost_experience = ghost_base_xp,
                ghost_add_experience = ghost_risk_xp,
                num_stages_string = tostring(#narrative_chains) .. " x ",
                payday_money = payday_money,
                counted_job_cash = 0,
                counted_job_xp = 0,
                counted_risk_cash = 0,
                counted_risk_xp = 0,
                counted_heat_xp = 0,
                counted_ghost_xp = 0,
                counted_payday_money = 0,
                stars = {
                    job_and_difficulty_stars = job_and_difficulty_stars,
                    job_stars = job_stars,
                    difficulty_stars = difficulty_stars
                },
                gui_objects = {}
            }
            self._data.gui_objects.risk_stats_panel = risk_stats_panel
            self._data.gui_objects.risk_text = risk_text
            self._data.gui_objects.payday_text = payday_text
            self._data.gui_objects.job_cash = job_cash
            self._data.gui_objects.job_add_cash = add_cash
            self._data.gui_objects.heat_add_xp = heat_add_xp
            self._data.gui_objects.ghost_add_xp = ghost_add_xp
            self._data.gui_objects.add_xp = add_xp
            self._data.gui_objects.job_xp = job_xp
            self._data.gui_objects.risks = {
                "risk_pd",
                "risk_swat",
                "risk_fbi",
                "risk_death_squad",
                "risk_easy_wish"
            }

            if not Global.SKIP_OVERKILL_290 then
                table.insert(self._data.gui_objects.risks, "risk_murder_squad")
                table.insert(self._data.gui_objects.risks, "risk_sm_wish")
            end

            self._data.gui_objects.num_stars = 10
            self._wait_t = 0
            local reached_level_cap = managers.experience:reached_level_cap()
            local levelup_text =
                reached_level_cap and managers.localization:to_upper_text("menu_reached_level_cap") or
                managers.localization:to_upper_text(
                    "menu_levelup",
                    {
                        levels = string.format("%0.1d%%", 0)
                    }
                )
            local potential_level_up_text =
                self._contract_panel:text(
                {
                    blend_mode = "normal",
                    name = "potential_level_up_text",
                    visible = true,
                    layer = 3,
                    text = levelup_text,
                    font_size = tweak_data.menu.pd2_small_font_size,
                    font = tweak_data.menu.pd2_small_font,
                    color = tweak_data.hud_stats.potential_xp_color
                }
            )

            self:make_fine_text(potential_level_up_text)
            potential_level_up_text:set_top(math.round(heat_add_xp:top()))
            self:_update_xp_appendices()

            self._data.gui_objects.potential_level_up_text = potential_level_up_text
            self._step = 1
            self._steps = {
                "set_time",
                "start_sound",
                "start_counter",
                "count_job_base",
                "end_counter",
                "count_difficulty_stars",
                "start_counter",
                "count_job_payday",
                "end_counter",
                "free_memory"
            }

            if self._customizable then
                if self._briefing_len_panel then
                    self._briefing_len_panel:hide()
                end

                local premium_text =
                    self._contract_panel:text(
                    {
                        text = "  ",
                        name = "premium_text",
                        wrap = true,
                        blend_mode = "add",
                        word_wrap = true,
                        font_size = font_size,
                        font = font,
                        color = tweak_data.screen_colors.button_stage_3
                    }
                )

                premium_text:set_top(contact_text:bottom() + padding)
                premium_text:set_left(contact_text:left())
                premium_text:set_w(contact_image:w())
                self._contact_text_header:set_text(
                    managers.localization:to_upper_text("menu_cn_premium_buy_desc") ..
                        ": " .. managers.localization:to_upper_text(narrative.name_id)
                )

                self._step = 1
                self._steps = {
                    "start_sound",
                    "set_all",
                    "free_memory"
                }
            elseif self._smart_matchmaking then
                self._contact_text_header:set_text(
                    managers.localization:to_upper_text("menu_smm_search_job") ..
                        ": " .. managers.localization:to_upper_text(narrative.name_id)
                )

                self._step = 1
                self._steps = {
                    "set_time",
                    "start_sound",
                    "set_all",
                    "free_memory"
                }
            end

            self._current_job_star = 0
            self._current_difficulty_star = 0
            self._post_event_params = {
                show_subtitle = false,
                listener = {
                    end_of_event = true,
                    duration = true,
                    clbk = callback(self, self, "sound_event_callback")
                }
            }

            if not managers.menu:is_pc_controller() then
                managers.menu:active_menu().input:deactivate_controller_mouse()
            end

            self:_rec_round_object(self._panel)

            self._potential_show_max = false
        end
    elseif RequiredScript == "lib/managers/hud/hudmissionbriefing" then
        function HUDMissionBriefing:init(hud, workspace)
            self._backdrop = MenuBackdropGUI:new(workspace)

            if not _G.IS_VR then
                self._backdrop:create_black_borders()
            end

            self._hud = hud
            self._workspace = workspace
            self._singleplayer = Global.game_settings.single_player
            local bg_font = tweak_data.menu.pd2_massive_font
            local title_font = tweak_data.menu.pd2_large_font
            local content_font = tweak_data.menu.pd2_medium_font
            local text_font = tweak_data.menu.pd2_small_font
            local bg_font_size = tweak_data.menu.pd2_massive_font_size
            local title_font_size = tweak_data.menu.pd2_large_font_size
            local content_font_size = tweak_data.menu.pd2_medium_font_size
            local text_font_size = tweak_data.menu.pd2_small_font_size
            local interupt_stage = managers.job:interupt_stage()
            self._background_layer_one = self._backdrop:get_new_background_layer()
            self._background_layer_two = self._backdrop:get_new_background_layer()
            self._background_layer_three = self._backdrop:get_new_background_layer()
            self._foreground_layer_one = self._backdrop:get_new_foreground_layer()

            self._backdrop:set_panel_to_saferect(self._background_layer_one)
            self._backdrop:set_panel_to_saferect(self._foreground_layer_one)

            self._ready_slot_panel =
                self._foreground_layer_one:panel(
                {
                    name = "player_slot_panel",
                    w = self._foreground_layer_one:w() / 2,
                    h = text_font_size * 4 + 20
                }
            )

            self._ready_slot_panel:set_bottom(self._foreground_layer_one:h() - 70)
            self._ready_slot_panel:set_right(self._foreground_layer_one:w())

            if not self._singleplayer then
                local voice_icon, voice_texture_rect = tweak_data.hud_icons:get_icon_data("mugshot_talk")

                for i = 1, tweak_data.max_players do
                    local color_id = i
                    local color = tweak_data.chat_colors[color_id] or tweak_data.chat_colors[#tweak_data.chat_colors]
                    local slot_panel =
                        self._ready_slot_panel:panel(
                        {
                            x = 10,
                            name = "slot_" .. tostring(i),
                            h = text_font_size,
                            y = (i - 1) * text_font_size + 10,
                            w = self._ready_slot_panel:w() - 20
                        }
                    )
                    local criminal =
                        slot_panel:text(
                        {
                            name = "criminal",
                            align = "left",
                            blend_mode = "add",
                            vertical = "center",
                            font_size = text_font_size,
                            font = text_font,
                            color = color,
                            text = tweak_data.gui.LONGEST_CHAR_NAME
                        }
                    )
                    local voice =
                        slot_panel:bitmap(
                        {
                            name = "voice",
                            visible = false,
                            x = 10,
                            layer = 2,
                            texture = voice_icon,
                            texture_rect = voice_texture_rect,
                            w = voice_texture_rect[3],
                            h = voice_texture_rect[4],
                            color = color
                        }
                    )
                    local name =
                        slot_panel:text(
                        {
                            vertical = "center",
                            name = "name",
                            w = 256,
                            align = "left",
                            blend_mode = "add",
                            rotation = 360,
                            layer = 1,
                            text = managers.localization:text("menu_lobby_player_slot_available") .. "  ",
                            font = text_font,
                            font_size = text_font_size,
                            color = color:with_alpha(0.5),
                            h = text_font_size
                        }
                    )
                    local status =
                        slot_panel:text(
                        {
                            vertical = "center",
                            name = "status",
                            w = 256,
                            align = "right",
                            blend_mode = "add",
                            text = "  ",
                            visible = false,
                            layer = 1,
                            font = text_font,
                            font_size = text_font_size,
                            h = text_font_size,
                            color = tweak_data.screen_colors.text:with_alpha(0.5)
                        }
                    )
                    local infamy =
                        slot_panel:bitmap(
                        {
                            w = 16,
                            name = "infamy",
                            h = 16,
                            visible = false,
                            y = 1,
                            layer = 2,
                            color = color
                        }
                    )
                    local detection =
                        slot_panel:panel(
                        {
                            name = "detection",
                            visible = false,
                            layer = 2,
                            w = slot_panel:h(),
                            h = slot_panel:h()
                        }
                    )
                    local detection_ring_left_bg =
                        detection:bitmap(
                        {
                            blend_mode = "add",
                            name = "detection_left_bg",
                            alpha = 0.2,
                            texture = "guis/textures/pd2/mission_briefing/inv_detection_meter",
                            w = detection:w(),
                            h = detection:h()
                        }
                    )
                    local detection_ring_right_bg =
                        detection:bitmap(
                        {
                            blend_mode = "add",
                            name = "detection_right_bg",
                            alpha = 0.2,
                            texture = "guis/textures/pd2/mission_briefing/inv_detection_meter",
                            w = detection:w(),
                            h = detection:h()
                        }
                    )

                    detection_ring_right_bg:set_texture_rect(
                        detection_ring_right_bg:texture_width(),
                        0,
                        -detection_ring_right_bg:texture_width(),
                        detection_ring_right_bg:texture_height()
                    )

                    local detection_ring_left =
                        detection:bitmap(
                        {
                            blend_mode = "add",
                            name = "detection_left",
                            texture = "guis/textures/pd2/mission_briefing/inv_detection_meter",
                            render_template = "VertexColorTexturedRadial",
                            layer = 1,
                            w = detection:w(),
                            h = detection:h()
                        }
                    )
                    local detection_ring_right =
                        detection:bitmap(
                        {
                            blend_mode = "add",
                            name = "detection_right",
                            texture = "guis/textures/pd2/mission_briefing/inv_detection_meter",
                            render_template = "VertexColorTexturedRadial",
                            layer = 1,
                            w = detection:w(),
                            h = detection:h()
                        }
                    )

                    detection_ring_right:set_texture_rect(
                        detection_ring_right:texture_width(),
                        0,
                        -detection_ring_right:texture_width(),
                        detection_ring_right:texture_height()
                    )

                    local detection_value =
                        slot_panel:text(
                        {
                            text = " ",
                            name = "detection_value",
                            align = "left",
                            blend_mode = "add",
                            vertical = "center",
                            font_size = text_font_size,
                            font = text_font,
                            color = color
                        }
                    )

                    detection:set_left(slot_panel:w() * 0.65)
                    detection_value:set_left(detection:right() + 2)
                    detection_value:set_visible(detection:visible())

                    local _, _, w, _ = criminal:text_rect()

                    voice:set_left(w + 2)
                    criminal:set_w(w)
                    criminal:set_align("right")
                    criminal:set_text("")
                    name:set_left(voice:right() + 2)
                    status:set_right(slot_panel:w())
                    infamy:set_left(name:x())
                end

                BoxGuiObject:new(
                    self._ready_slot_panel,
                    {
                        sides = {
                            1,
                            1,
                            1,
                            1
                        }
                    }
                )
            end

            if not managers.job:has_active_job() then
                return
            end

            self._current_contact_data = managers.job:current_contact_data()
            self._current_level_data = managers.job:current_level_data()
            self._current_stage_data = managers.job:current_stage_data()
            self._current_job_data = managers.job:current_job_data()
            self._current_job_chain = managers.job:current_job_chain_data()
            self._job_class = self._current_job_data and self._current_job_data.jc or 0
            local show_contact_gui = true

            if managers.crime_spree:is_active() then
                self._backdrop:set_pattern("guis/textures/pd2/mission_briefing/bain/bd_pattern", 0.1, "add")

                show_contact_gui = false
            end

            if show_contact_gui then
                local contact_gui = self._background_layer_two:gui(self._current_contact_data.assets_gui, {})
                local contact_pattern = contact_gui:has_script() and contact_gui:script().pattern

                if contact_pattern then
                    self._backdrop:set_pattern(contact_pattern, 0.1, "add")
                end
            end

            local padding_y = 60
            self._paygrade_panel =
                self._background_layer_one:panel(
                {
                    w = 210,
                    h = 70,
                    y = padding_y
                }
            )
            local pg_text =
                self._foreground_layer_one:text(
                {
                    name = "pg_text",
                    vertical = "center",
                    h = 32,
                    align = "right",
                    text = utf8.to_upper(managers.localization:text("menu_risk")),
                    y = padding_y,
                    font_size = content_font_size,
                    font = content_font,
                    color = tweak_data.screen_colors.text
                }
            )
            local _, _, w, h = pg_text:text_rect()

            pg_text:set_size(w, h)

            self._paygrade_text = pg_text
            local job_stars = managers.job:current_job_stars()
            local job_and_difficulty_stars = managers.job:current_job_and_difficulty_stars()
            local difficulty_stars = managers.job:current_difficulty_stars()
            local filled_star_rect = {
                0,
                32,
                32,
                32
            }
            local empty_star_rect = {
                32,
                32,
                32,
                32
            }
            local num_stars = 0
            local x = 0
            local y = 0
            local star_size = 18
            local panel_w = 0
            local panel_h = 0
            local risk_color = tweak_data.screen_colors.risk
            local risks = {
                "risk_swat",
                "risk_fbi",
                "risk_death_squad",
                "risk_easy_wish"
            }

            if not Global.SKIP_OVERKILL_290 then
                table.insert(risks, "risk_murder_squad")
                table.insert(risks, "risk_sm_wish")
            end

            for i, name in ipairs(risks) do
                local texture, rect = tweak_data.hud_icons:get_icon_data(name)
                local active = i <= difficulty_stars
                local color = active and risk_color or tweak_data.screen_colors.text
                local alpha = active and 1 or 0.25
                local risk =
                    self._paygrade_panel:bitmap(
                    {
                        y = 0,
                        x = 0,
                        name = name,
                        texture = texture,
                        texture_rect = rect,
                        alpha = alpha,
                        color = color
                    }
                )

                risk:set_position(x, y)

                x = x + risk:w() + 0
                panel_w = math.max(panel_w, risk:right())
                panel_h = math.max(panel_h, risk:h())
            end

            pg_text:set_color(risk_color)
            self._paygrade_panel:set_h(panel_h)
            self._paygrade_panel:set_w(panel_w)
            self._paygrade_panel:set_right(self._background_layer_one:w())
            pg_text:set_right(self._paygrade_panel:left())

            if Global.game_settings.one_down then
                local one_down_text =
                    self._foreground_layer_one:text(
                    {
                        name = "one_down_text",
                        text = managers.localization:to_upper_text("menu_one_down"),
                        font = content_font,
                        font_size = content_font_size,
                        color = tweak_data.screen_colors.one_down
                    }
                )
                local _, _, w, h = one_down_text:text_rect()

                one_down_text:set_size(w, h)
                one_down_text:set_righttop(pg_text:left() - 10, pg_text:top())

                one_down_text:set_text("NO DOWN")
                one_down_text:set_color(NoDown.color)
            end

            if managers.skirmish:is_skirmish() then
                self._paygrade_panel:set_visible(false)
                pg_text:set_visible(false)

                local min, max = managers.skirmish:wave_range()
                local wave_range_text =
                    self._foreground_layer_one:text(
                    {
                        name = "wave_range",
                        vertical = "center",
                        h = 32,
                        align = "right",
                        text = managers.localization:to_upper_text(
                            "menu_skirmish_wave_range",
                            {
                                min = min,
                                max = max
                            }
                        ),
                        y = padding_y,
                        font_size = content_font_size,
                        font = content_font,
                        color = tweak_data.screen_colors.skirmish_color
                    }
                )

                managers.hud:make_fine_text(wave_range_text)
                wave_range_text:set_right(self._background_layer_one:w())
            end

            self._job_schedule_panel =
                self._background_layer_one:panel(
                {
                    h = 70,
                    w = self._background_layer_one:w() / 2
                }
            )

            self._job_schedule_panel:set_right(self._foreground_layer_one:w())
            self._job_schedule_panel:set_top(padding_y + content_font_size + 15)

            if interupt_stage then
                self._job_schedule_panel:set_alpha(0.2)

                if not tweak_data.levels[interupt_stage].bonus_escape then
                    self._interupt_panel =
                        self._background_layer_one:panel(
                        {
                            h = 125,
                            w = self._background_layer_one:w() / 2
                        }
                    )
                    local interupt_text =
                        self._interupt_panel:text(
                        {
                            name = "job_text",
                            vertical = "top",
                            h = 80,
                            font_size = 70,
                            align = "left",
                            layer = 5,
                            text = utf8.to_upper(managers.localization:text("menu_escape")),
                            font = bg_font,
                            color = tweak_data.screen_colors.important_1
                        }
                    )
                    local _, _, w, h = interupt_text:text_rect()

                    interupt_text:set_size(w, h)
                    interupt_text:rotate(-15)
                    interupt_text:set_center(self._interupt_panel:w() / 2, self._interupt_panel:h() / 2)
                    self._interupt_panel:set_shape(self._job_schedule_panel:shape())
                end
            end

            local num_stages = self._current_job_chain and #self._current_job_chain or 0
            local day_color = tweak_data.screen_colors.item_stage_1
            local chain = self._current_job_chain and self._current_job_chain or {}
            local js_w = self._job_schedule_panel:w() / 7
            local js_h = self._job_schedule_panel:h()

            for i = 1, 7 do
                local day_font = text_font
                local day_font_size = text_font_size
                day_color = tweak_data.screen_colors.item_stage_1

                if num_stages < i then
                    day_color = tweak_data.screen_colors.item_stage_3
                elseif i == managers.job:current_stage() then
                    day_font = content_font
                    day_font_size = content_font_size
                end

                local day_text =
                    self._job_schedule_panel:text(
                    {
                        vertical = "center",
                        align = "center",
                        blend_mode = "add",
                        name = "day_" .. tostring(i),
                        text = utf8.to_upper(
                            managers.localization:text(
                                "menu_day_short",
                                {
                                    day = tostring(i)
                                }
                            )
                        ),
                        font_size = day_font_size,
                        font = day_font,
                        w = js_w,
                        h = js_h,
                        color = day_color
                    }
                )

                day_text:set_left(i == 1 and 0 or self._job_schedule_panel:child("day_" .. tostring(i - 1)):right())

                local ghost =
                    self._job_schedule_panel:bitmap(
                    {
                        texture = "guis/textures/pd2/cn_minighost",
                        h = 16,
                        blend_mode = "add",
                        w = 16,
                        name = "ghost_" .. tostring(i),
                        color = tweak_data.screen_colors.ghost_color
                    }
                )

                ghost:set_center(day_text:center_x(), day_text:center_y() + day_text:h() * 0.25)

                local ghost_visible =
                    i <= num_stages and managers.job:is_job_stage_ghostable(managers.job:current_real_job_id(), i)

                ghost:set_visible(ghost_visible)

                if ghost_visible then
                    self:_apply_ghost_color(ghost, i, not Network:is_server())
                end
            end

            local stage_crossed_icon = {
                texture = "guis/textures/pd2/mission_briefing/calendar_xo",
                texture_rect = {
                    0,
                    0,
                    80,
                    64
                }
            }
            local stage_circled_icon = {
                texture = "guis/textures/pd2/mission_briefing/calendar_xo",
                texture_rect = {
                    80,
                    0,
                    80,
                    64
                }
            }

            for i = 1, managers.job:current_stage() or 0 do
                local icon = i == managers.job:current_stage() and stage_circled_icon or stage_crossed_icon
                local stage_marker =
                    self._job_schedule_panel:bitmap(
                    {
                        h = 64,
                        layer = 1,
                        w = 80,
                        name = "stage_done_" .. tostring(i),
                        texture = icon.texture,
                        texture_rect = icon.texture_rect,
                        rotation = math.rand(-10, 10)
                    }
                )

                stage_marker:set_center(self._job_schedule_panel:child("day_" .. tostring(i)):center())
                stage_marker:move(math.random(4) - 2, math.random(4) - 2)
            end

            if managers.job:has_active_job() then
                local payday_stamp =
                    self._job_schedule_panel:bitmap(
                    {
                        texture = "guis/textures/pd2/mission_briefing/calendar_xo",
                        name = "payday_stamp",
                        h = 64,
                        layer = 2,
                        w = 96,
                        texture_rect = {
                            160,
                            0,
                            96,
                            64
                        },
                        rotation = math.rand(-5, 5)
                    }
                )

                payday_stamp:set_center(self._job_schedule_panel:child("day_" .. tostring(num_stages)):center())
                payday_stamp:move(math.random(4) - 2 - 7, math.random(4) - 2 + 8)

                if payday_stamp:rotation() == 0 then
                    payday_stamp:set_rotation(1)
                end
            end

            local job_overview_text =
                self._foreground_layer_one:text(
                {
                    name = "job_overview_text",
                    vertical = "bpttom",
                    align = "left",
                    text = utf8.to_upper(managers.localization:text("menu_job_overview")),
                    h = content_font_size,
                    font_size = content_font_size,
                    font = content_font,
                    color = tweak_data.screen_colors.text
                }
            )
            local _, _, w, h = job_overview_text:text_rect()

            job_overview_text:set_size(w, h)
            job_overview_text:set_leftbottom(self._job_schedule_panel:left(), pg_text:bottom())
            job_overview_text:set_y(math.round(job_overview_text:y()))

            self._job_overview_text = job_overview_text

            self._paygrade_panel:set_center_y(job_overview_text:center_y())
            pg_text:set_center_y(job_overview_text:center_y())
            pg_text:set_y(math.round(pg_text:y()))

            if pg_text:left() <= job_overview_text:right() + 15 then
                pg_text:move(0, -pg_text:h())
                self._paygrade_panel:move(0, -pg_text:h())
            end

            local text =
                utf8.to_upper(
                managers.localization:text(self._current_contact_data.name_id) ..
                    ": " .. managers.localization:text(self._current_job_data.name_id)
            )
            local text_align, text_len = nil

            if managers.crime_spree:is_active() then
                local level_id = Global.game_settings.level_id
                local name_id = level_id and tweak_data.levels[level_id] and tweak_data.levels[level_id].name_id
                local mission = managers.crime_spree:get_mission()
                text = managers.localization:to_upper_text(name_id) .. ": "
                text_len = utf8.len(text)
                text =
                    text ..
                    "+" ..
                        managers.localization:text(
                            "menu_cs_level",
                            {
                                level = mission and mission.add or 0
                            }
                        )
                text_align = "right"
            end

            if managers.skirmish:is_skirmish() then
                if managers.skirmish:is_weekly_skirmish() then
                    text = managers.localization:to_upper_text("menu_weekly_skirmish")
                else
                    text = managers.localization:to_upper_text("menu_skirmish")
                end
            end

            local job_text =
                self._foreground_layer_one:text(
                {
                    vertical = "top",
                    name = "job_text",
                    text = text,
                    align = text_align or "left",
                    font_size = title_font_size,
                    font = title_font,
                    color = tweak_data.screen_colors.text
                }
            )

            if managers.crime_spree:is_active() then
                job_text:set_range_color(text_len, utf8.len(text), tweak_data.screen_colors.crime_spree_risk)
            end

            if not text_align then
                local big_text =
                    self._background_layer_three:text(
                    {
                        vertical = "top",
                        name = "job_text",
                        alpha = 0.4,
                        text = text,
                        align = text_align or "left",
                        font_size = bg_font_size,
                        font = bg_font,
                        color = tweak_data.screen_colors.button_stage_1
                    }
                )

                big_text:set_world_center_y(self._foreground_layer_one:child("job_text"):world_center_y())
                big_text:set_world_x(self._foreground_layer_one:child("job_text"):world_x())
                big_text:move(-13, 9)
                self._backdrop:animate_bg_text(big_text)
            end

            if managers.job:current_job_data().name_id == "heist_rvd" then
                local day_1_text = self._job_schedule_panel:child("day_1")
                local day_1_sticker =
                    self._job_schedule_panel:bitmap(
                    {
                        texture = "guis/dlcs/rvd/textures/pd2/mission_briefing/day2",
                        h = 48,
                        w = 96,
                        rotation = 360,
                        layer = 2
                    }
                )

                day_1_sticker:set_center(day_1_text:center())
                day_1_sticker:move(math.random(4) - 2, math.random(4) - 2)

                local day_2_text = self._job_schedule_panel:child("day_2")
                local day_2_sticker =
                    self._job_schedule_panel:bitmap(
                    {
                        texture = "guis/dlcs/rvd/textures/pd2/mission_briefing/day1",
                        h = 48,
                        w = 96,
                        rotation = 360,
                        layer = 2
                    }
                )

                day_2_sticker:set_center(day_2_text:center())
                day_2_sticker:move(math.random(4) - 2, math.random(4) - 2)
            end

            if managers.crime_spree:is_active() then
                self._paygrade_panel:set_visible(false)
                self._job_schedule_panel:set_visible(false)
                self._paygrade_text:set_visible(false)
                self._job_overview_text:set_visible(false)
            end

            if managers.skirmish:is_skirmish() then
                self._job_schedule_panel:set_visible(false)

                self._skirmish_progress =
                    SkirmishBriefingProgress:new(
                    self._background_layer_one,
                    {
                        x = self._job_schedule_panel:x(),
                        y = self._job_schedule_panel:y(),
                        w = self._job_schedule_panel:width(),
                        h = self._job_schedule_panel:height()
                    }
                )
            end
        end
    elseif RequiredScript == "lib/managers/menu/ingamecontractgui" then
        function IngameContractGui:init(ws, node)
            local padding = SystemInfo:platform() == Idstring("WIN32") and 10 or 5
            self._panel =
                ws:panel():panel(
                {
                    w = math.round(ws:panel():w() * 0.6),
                    h = math.round(ws:panel():h() * 1)
                }
            )

            self._panel:set_y(math.max(tweak_data.menu.pd2_medium_font_size, CoreMenuRenderer.Renderer.border_height))
            self._panel:grow(0, -(self._panel:y() + tweak_data.menu.pd2_medium_font_size))

            self._node = node
            local job_data = managers.job:current_job_data()
            local job_chain = managers.job:current_job_chain_data()

            if
                job_data and managers.job:current_job_id() == "safehouse" and
                    Global.mission_manager.saved_job_values.playedSafeHouseBefore or
                    managers.job:current_job_id() == "chill"
             then
                self._panel:set_visible(false)
            end

            local contract_text =
                self._panel:text(
                {
                    text = "",
                    vertical = "bottom",
                    rotation = 360,
                    layer = 1,
                    font = tweak_data.menu.pd2_large_font,
                    font_size = tweak_data.menu.pd2_large_font_size,
                    color = tweak_data.screen_colors.text
                }
            )

            contract_text:set_text(
                self:get_text("cn_menu_contract_header") .. " " .. (job_data and self:get_text(job_data.name_id) or "")
            )
            contract_text:set_bottom(5)

            local text_panel =
                self._panel:panel(
                {
                    layer = 1,
                    w = self._panel:w() - padding * 2,
                    h = self._panel:h() - padding * 2
                }
            )

            text_panel:set_left(padding)
            text_panel:set_top(padding)

            local briefing_title =
                text_panel:text(
                {
                    text = "",
                    font = tweak_data.menu.pd2_medium_font,
                    font_size = tweak_data.menu.pd2_medium_font_size,
                    color = tweak_data.screen_colors.text
                }
            )

            briefing_title:set_text(self:get_text("menu_briefing"))
            managers.hud:make_fine_text(briefing_title)

            local font_size = tweak_data.menu.pd2_small_font_size
            local text = job_data and managers.localization:text(job_data.briefing_id) or ""
            local briefing_description =
                text_panel:text(
                {
                    name = "briefing_description",
                    vertical = "top",
                    h = 128,
                    wrap = true,
                    align = "left",
                    word_wrap = true,
                    text = text,
                    font = tweak_data.menu.pd2_small_font,
                    font_size = font_size,
                    color = tweak_data.screen_colors.text
                }
            )
            local _, _, _, h = briefing_description:text_rect()

            briefing_description:set_h(h)
            briefing_description:set_top(briefing_title:bottom())

            local is_job_ghostable = managers.job:is_job_ghostable(managers.job:current_job_id())
            local ghostable_text = nil

            if is_job_ghostable then
                local min_ghost_bonus, max_ghost_bonus = managers.job:get_job_ghost_bonus(managers.job:current_job_id())
                local min_ghost = math.round(min_ghost_bonus * 100)
                local max_ghost = math.round(max_ghost_bonus * 100)
                local min_string, max_string = nil

                if min_ghost == 0 and min_ghost_bonus ~= 0 then
                    min_string = string.format("%0.2f", math.abs(min_ghost_bonus * 100))
                else
                    min_string = tostring(math.abs(min_ghost))
                end

                if max_ghost == 0 and max_ghost_bonus ~= 0 then
                    max_string = string.format("%0.2f", math.abs(max_ghost_bonus * 100))
                else
                    max_string = tostring(math.abs(max_ghost))
                end

                local ghost_bonus_string =
                    min_ghost_bonus == max_ghost_bonus and min_string or min_string .. "-" .. max_string
                ghostable_text =
                    text_panel:text(
                    {
                        blend_mode = "add",
                        vertical = "top",
                        wrap = true,
                        align = "left",
                        wrap_word = true,
                        text = managers.localization:to_upper_text(
                            "menu_ghostable_job",
                            {
                                bonus = ghost_bonus_string
                            }
                        ),
                        font_size = tweak_data.menu.pd2_small_font_size,
                        font = tweak_data.menu.pd2_small_font,
                        color = tweak_data.screen_colors.ghost_color
                    }
                )

                ghostable_text:set_position(briefing_description:x(), briefing_description:bottom() + padding)
                managers.hud:make_fine_text(ghostable_text)
            end

            local modifiers_text =
                text_panel:text(
                {
                    name = "modifiers_text",
                    align = "left",
                    vertical = "top",
                    text = managers.localization:to_upper_text("menu_cn_modifiers"),
                    font = tweak_data.menu.pd2_small_font,
                    font_size = font_size,
                    color = tweak_data.screen_colors.text
                }
            )

            managers.hud:make_fine_text(modifiers_text)
            modifiers_text:set_bottom(text_panel:h() * 0.5 - tweak_data.menu.pd2_small_font_size)

            local next_top = modifiers_text:bottom()
            local one_down_warning_text = nil

            if Global.game_settings.one_down then
                one_down_warning_text =
                    text_panel:text(
                    {
                        name = "one_down_warning_text",
                        text = managers.localization:to_upper_text("menu_one_down"),
                        font = tweak_data.menu.pd2_small_font,
                        font_size = tweak_data.menu.pd2_small_font_size,
                        color = tweak_data.screen_colors.one_down
                    }
                )
                one_down_warning_text:set_text("NO DOWN")
                one_down_warning_text:set_color(NoDown.color)

                managers.hud:make_fine_text(one_down_warning_text)
                one_down_warning_text:set_top(next_top)
                one_down_warning_text:set_left(10)

                next_top = one_down_warning_text:bottom()

                if Global.game_settings.no_down then
                    one_down_warning_text:set_text("NO DOWN")
                    one_down_warning_text:set_color(NoDown.color)
                end
            end

            local job_heat_mul = managers.job:get_job_heat_multipliers(managers.job:current_job_id()) - 1
            local job_heat = math.round(job_heat_mul * 100)
            local job_heat_string = tostring(math.abs(job_heat))
            local is_job_heated = job_heat ~= 0 or job_heat_mul ~= 0

            if job_heat == 0 and job_heat_mul ~= 0 then
                job_heat_string = string.format("%0.2f", math.abs(job_heat_mul * 100))
            end

            local ghost_bonus_mul = managers.job:get_ghost_bonus()
            local job_ghost = math.round(ghost_bonus_mul * 100)
            local job_ghost_string = tostring(math.abs(job_ghost))
            local has_ghost_bonus = managers.job:has_ghost_bonus()

            if job_ghost == 0 and ghost_bonus_mul ~= 0 then
                job_ghost_string = string.format("%0.2f", math.abs(ghost_bonus_mul * 100))
            end

            local ghost_warning_text = nil

            if has_ghost_bonus then
                local ghost_color = tweak_data.screen_colors.ghost_color
                ghost_warning_text =
                    text_panel:text(
                    {
                        name = "ghost_color_warning_text",
                        vertical = "top",
                        word_wrap = true,
                        wrap = true,
                        align = "left",
                        blend_mode = "normal",
                        text = managers.localization:to_upper_text(
                            "menu_ghost_bonus",
                            {
                                exp_bonus = job_ghost_string
                            }
                        ),
                        font = tweak_data.menu.pd2_small_font,
                        font_size = tweak_data.menu.pd2_small_font_size,
                        color = ghost_color
                    }
                )

                managers.hud:make_fine_text(ghost_warning_text)
                ghost_warning_text:set_top(next_top)
                ghost_warning_text:set_left(10)

                next_top = ghost_warning_text:bottom()
            end

            local heat_warning_text = nil
            local heat_color = managers.job:get_job_heat_color(managers.job:current_job_id())

            if is_job_heated then
                local job_heat_text_id =
                    "menu_heat_" .. (job_heat_mul > 0 and "warm" or job_heat_mul < 0 and "cold" or "ok")
                heat_warning_text =
                    text_panel:text(
                    {
                        name = "heat_warning_text",
                        vertical = "top",
                        word_wrap = true,
                        wrap = true,
                        align = "left",
                        text = managers.localization:to_upper_text(
                            job_heat_text_id,
                            {
                                job_heat = job_heat_string
                            }
                        ),
                        font = tweak_data.menu.pd2_small_font,
                        font_size = font_size,
                        color = heat_color
                    }
                )

                managers.hud:make_fine_text(heat_warning_text)
                heat_warning_text:set_top(next_top)
                heat_warning_text:set_left(10)

                next_top = heat_warning_text:bottom()
            end

            local pro_warning_text = nil

            if managers.job:is_current_job_professional() then
                pro_warning_text =
                    text_panel:text(
                    {
                        name = "pro_warning_text",
                        vertical = "top",
                        h = 128,
                        wrap = true,
                        align = "left",
                        word_wrap = true,
                        text = self:get_text("menu_pro_warning"),
                        font = tweak_data.menu.pd2_small_font,
                        font_size = font_size,
                        color = tweak_data.screen_colors.pro_color
                    }
                )

                managers.hud:make_fine_text(pro_warning_text)
                pro_warning_text:set_h(pro_warning_text:h())
                pro_warning_text:set_top(next_top)
                pro_warning_text:set_left(10)

                next_top = pro_warning_text:bottom()
            end

            local is_christmas_job = managers.job:is_christmas_job(managers.job:current_job_id())

            if is_christmas_job then
                local holiday_potential_bonus = managers.job:get_job_christmas_bonus(managers.job:current_job_id())
                local holiday_bonus_percentage = math.round(holiday_potential_bonus * 100)

                if holiday_bonus_percentage ~= 0 then
                    local holiday_string = tostring(holiday_bonus_percentage)
                    local holiday_text =
                        text_panel:text(
                        {
                            vertical = "top",
                            wrap = true,
                            align = "left",
                            wrap_word = true,
                            text = managers.localization:to_upper_text(
                                "holiday_warning_text",
                                {
                                    event_icon = managers.localization:get_default_macro("BTN_XMAS"),
                                    bonus = holiday_string
                                }
                            ),
                            font_size = tweak_data.menu.pd2_small_font_size,
                            font = tweak_data.menu.pd2_small_font,
                            color = tweak_data.screen_colors.event_color
                        }
                    )

                    holiday_text:set_position(10, next_top)
                    managers.hud:make_fine_text(holiday_text)

                    next_top = holiday_text:bottom()
                end
            end

            next_top = next_top + 5

            modifiers_text:set_visible(
                heat_warning_text or pro_warning_text or ghost_warning_text or one_down_warning_text
            )

            local risk_color = tweak_data.screen_colors.risk
            local risk_title =
                text_panel:text(
                {
                    font = tweak_data.menu.pd2_small_font,
                    font_size = font_size,
                    text = self:get_text("menu_risk"),
                    color = risk_color
                }
            )

            managers.hud:make_fine_text(risk_title)
            risk_title:set_top(next_top)
            risk_title:set_visible(job_data and true or false)

            local menu_risk_id = "menu_risk_pd"

            if Global.game_settings.difficulty == "hard" then
                menu_risk_id = "menu_risk_swat"
            elseif Global.game_settings.difficulty == "overkill" then
                menu_risk_id = "menu_risk_fbi"
            elseif Global.game_settings.difficulty == "overkill_145" then
                menu_risk_id = "menu_risk_special"
            elseif Global.game_settings.difficulty == "easy_wish" then
                menu_risk_id = "menu_risk_easy_wish"
            elseif Global.game_settings.difficulty == "overkill_290" then
                menu_risk_id = "menu_risk_elite"
            elseif Global.game_settings.difficulty == "sm_wish" then
                menu_risk_id = "menu_risk_sm_wish"
            end

            local risk_stats_panel =
                text_panel:panel(
                {
                    name = "risk_stats_panel"
                }
            )

            risk_stats_panel:set_h(risk_title:h() + 5)

            if job_data then
                local job_stars = managers.job:current_job_stars()
                local job_and_difficulty_stars = managers.job:current_job_and_difficulty_stars()
                local difficulty_stars = managers.job:current_difficulty_stars()
                local job_id = managers.job:current_job_id()
                local rsx = 15
                local risks = {
                    "risk_pd",
                    "risk_swat",
                    "risk_fbi",
                    "risk_death_squad",
                    "risk_easy_wish"
                }

                if not Global.SKIP_OVERKILL_290 then
                    table.insert(risks, "risk_murder_squad")
                    table.insert(risks, "risk_sm_wish")
                end

                local max_y = 0
                local max_x = 0

                for i, name in ipairs(risks) do
                    if i ~= 1 then
                        local texture, rect = tweak_data.hud_icons:get_icon_data(name)
                        local active = i <= difficulty_stars + 1
                        local color = active and i ~= 1 and risk_color or tweak_data.screen_colors.text
                        local alpha = active and 1 or 0.25
                        local risk =
                            text_panel:bitmap(
                            {
                                y = 0,
                                x = 0,
                                texture = texture,
                                texture_rect = rect,
                                alpha = alpha,
                                color = color
                            }
                        )

                        risk:set_x(rsx)
                        risk:set_top(math.round(risk_title:bottom()))

                        rsx = rsx + risk:w() + 2
                        local stat = managers.statistics:completed_job(job_id, tweak_data:index_to_difficulty(i + 1))
                        local risk_stat =
                            risk_stats_panel:text(
                            {
                                align = "center",
                                name = name,
                                font = tweak_data.menu.pd2_small_font,
                                font_size = font_size,
                                text = tostring(stat)
                            }
                        )

                        managers.hud:make_fine_text(risk_stat)
                        risk_stat:set_world_center_x(risk:world_center_x())

                        local this_difficulty = i == difficulty_stars + 1
                        active = i <= difficulty_stars + 1
                        color = active and risk_color or Color.white

                        if this_difficulty then
                            alpha = 1
                        elseif active then
                            alpha = 0.5
                        else
                            alpha = 0.25
                        end

                        risk_stat:set_color(color)
                        risk_stat:set_alpha(alpha)

                        max_y = math.max(max_y, risk:bottom())
                        max_x = math.max(max_x, risk:right() + 5)
                        max_x = math.max(max_x, risk_stat:right() + risk_stats_panel:left() + 10)
                    end
                end

                risk_stats_panel:set_top(math.round(max_y + 2))

                local stat =
                    managers.statistics:completed_job(job_id, tweak_data:index_to_difficulty(difficulty_stars + 2))
                local risk_text =
                    text_panel:text(
                    {
                        name = "risk_text",
                        wrap = true,
                        align = "left",
                        vertical = "top",
                        word_wrap = true,
                        x = max_x,
                        w = text_panel:w() - max_x,
                        h = text_panel:h(),
                        text = self:get_text(menu_risk_id) ..
                            " " ..
                                managers.localization:to_upper_text(
                                    "menu_stat_job_completed",
                                    {
                                        stat = tostring(stat)
                                    }
                                ) ..
                                    " ",
                        font = tweak_data.hud_stats.objective_desc_font,
                        font_size = font_size,
                        color = risk_color
                    }
                )

                risk_text:set_top(math.round(risk_title:bottom() + 4))
                risk_text:set_h(risk_stats_panel:bottom() - risk_text:top())

                local show_max = self._node and self._node:parameters().show_potential_max or false
                local potential_rewards_title =
                    text_panel:text(
                    {
                        blend_mode = "add",
                        font = tweak_data.menu.pd2_small_font,
                        font_size = font_size,
                        text = self:get_text(
                            show_max and "menu_potential_rewards_max" or "menu_potential_rewards_min",
                            {
                                BTN_Y = managers.localization:btn_macro("menu_modify_item")
                            }
                        ),
                        color = managers.menu:is_pc_controller() and tweak_data.screen_colors.button_stage_3 or
                            tweak_data.screen_colors.text
                    }
                )

                managers.hud:make_fine_text(potential_rewards_title)
                potential_rewards_title:set_top(risk_stats_panel:bottom() + 4)

                local jobpay_title =
                    text_panel:text(
                    {
                        x = 10,
                        font = tweak_data.menu.pd2_small_font,
                        font_size = font_size,
                        text = managers.localization:to_upper_text("cn_menu_contract_jobpay_header"),
                        color = tweak_data.screen_colors.text
                    }
                )

                managers.hud:make_fine_text(jobpay_title)
                jobpay_title:set_top(math.round(potential_rewards_title:bottom()))

                local experience_title =
                    text_panel:text(
                    {
                        x = 10,
                        font = tweak_data.menu.pd2_small_font,
                        font_size = font_size,
                        text = self:get_text("menu_experience"),
                        color = tweak_data.screen_colors.text
                    }
                )

                managers.hud:make_fine_text(experience_title)
                experience_title:set_top(math.round(jobpay_title:bottom()))

                self._potential_rewards_title = potential_rewards_title
                self._jobpay_title = jobpay_title
                self._experience_title = experience_title
                self._text_panel = text_panel
                self._rewards_panel =
                    text_panel:panel(
                    {
                        name = "rewards_panel"
                    }
                )
                self._potential_show_max = show_max

                self:set_potential_rewards(show_max)
            end

            self:_rec_round_object(self._panel)

            self._sides =
                BoxGuiObject:new(
                self._panel,
                {
                    sides = {
                        1,
                        1,
                        1,
                        1
                    }
                }
            )
        end
    end
end

NoDown:Setup()
