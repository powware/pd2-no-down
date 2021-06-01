require("lib/managers/menu/WalletGuiObject")

CrimeNetManager = CrimeNetManager or class()

function CrimeNetManager:_find_online_games_win32(friends_only)
    -- Lines: 1070 to 1226
    local function f(info)
        managers.network.matchmake:search_lobby_done()

        local room_list = info.room_list
        local attribute_list = info.attribute_list
        local dead_list = {}

        for id, _ in pairs(self._active_server_jobs) do
            dead_list[id] = true
        end

        local friends_list = Steam:logged_on() and Steam:friends()
        local friend_ids = {}

        if friends_list then
            for i, friend in ipairs(friends_list) do
                friend_ids[friend:id()] = true
            end
        end

        for i, room in ipairs(room_list) do
            local name_str = tostring(room.owner_name)
            local attributes_numbers = attribute_list[i].numbers
            local attributes_mutators = attribute_list[i].mutators

            if managers.network.matchmake:is_server_ok(friends_only, room.owner_id, attribute_list[i], nil) then
                dead_list[room.room_id] = nil
                local host_name = name_str
                local level_id = tweak_data.levels:get_level_name_from_index(attributes_numbers[1] % 1000)
                local name_id = level_id and tweak_data.levels[level_id] and tweak_data.levels[level_id].name_id
                local level_name = name_id and managers.localization:text(name_id) or "LEVEL NAME ERROR"
                local difficulty_id = attributes_numbers[2]
                local difficulty = tweak_data:index_to_difficulty(difficulty_id)
                local job_id = tweak_data.narrative:get_job_name_from_index(math.floor(attributes_numbers[1] / 1000))
                local kick_option = attributes_numbers[8]
                local job_plan = attributes_numbers[10]
                local drop_in = attributes_numbers[6]
                local permission = attributes_numbers[3]
                local min_level = attributes_numbers[7]
                local state_string_id = tweak_data:index_to_server_state(attributes_numbers[4])
                local state_name =
                    state_string_id and managers.localization:text("menu_lobby_server_state_" .. state_string_id) or
                    "UNKNOWN"
                local state = attributes_numbers[4]
                local num_plrs = attributes_numbers[5]
                local is_friend = friend_ids[room.room_id] or false

                if attribute_list[i].no_down then
                    log(host_name)
                end

                if name_id then
                    if not self._active_server_jobs[room.room_id] then
                        if
                            table.size(self._active_jobs) + table.size(self._active_server_jobs) <
                                tweak_data.gui.crime_net.job_vars.total_active_jobs and
                                table.size(self._active_server_jobs) < self._max_active_server_jobs
                         then
                            self._active_server_jobs[room.room_id] = {
                                added = false,
                                alive_time = 0
                            }

                            managers.menu_component:add_crimenet_server_job(
                                {
                                    room_id = room.room_id,
                                    host_id = room.owner_id,
                                    id = room.room_id,
                                    level_id = level_id,
                                    difficulty = difficulty,
                                    difficulty_id = difficulty_id,
                                    num_plrs = num_plrs,
                                    host_name = host_name,
                                    state_name = state_name,
                                    state = state,
                                    level_name = level_name,
                                    job_id = job_id,
                                    is_friend = is_friend,
                                    kick_option = kick_option,
                                    job_plan = job_plan,
                                    mutators = attribute_list[i].mutators,
                                    is_crime_spree = attribute_list[i].crime_spree and
                                        attribute_list[i].crime_spree >= 0,
                                    crime_spree = attribute_list[i].crime_spree,
                                    crime_spree_mission = attribute_list[i].crime_spree_mission,
                                    drop_in = drop_in,
                                    permission = permission,
                                    min_level = min_level,
                                    mods = attribute_list[i].mods,
                                    one_down = attribute_list[i].one_down,
                                    no_down = attribute_list[i].no_down,
                                    is_skirmish = attribute_list[i].skirmish and attribute_list[i].skirmish > 0,
                                    skirmish = attribute_list[i].skirmish,
                                    skirmish_wave = attribute_list[i].skirmish_wave,
                                    skirmish_weekly_modifiers = attribute_list[i].skirmish_weekly_modifiers
                                }
                            )
                        end
                    else
                        managers.menu_component:update_crimenet_server_job(
                            {
                                room_id = room.room_id,
                                host_id = room.owner_id,
                                id = room.room_id,
                                level_id = level_id,
                                difficulty = difficulty,
                                difficulty_id = difficulty_id,
                                num_plrs = num_plrs,
                                host_name = host_name,
                                state_name = state_name,
                                state = state,
                                level_name = level_name,
                                job_id = job_id,
                                is_friend = is_friend,
                                kick_option = kick_option,
                                job_plan = job_plan,
                                mutators = attribute_list[i].mutators,
                                is_crime_spree = attribute_list[i].crime_spree and attribute_list[i].crime_spree >= 0,
                                crime_spree = attribute_list[i].crime_spree,
                                crime_spree_mission = attribute_list[i].crime_spree_mission,
                                drop_in = drop_in,
                                permission = permission,
                                min_level = min_level,
                                mods = attribute_list[i].mods,
                                one_down = attribute_list[i].one_down,
                                no_down = attribute_list[i].no_down,
                                is_skirmish = attribute_list[i].skirmish and attribute_list[i].skirmish > 0,
                                skirmish = attribute_list[i].skirmish,
                                skirmish_wave = attribute_list[i].skirmish_wave,
                                skirmish_weekly_modifiers = attribute_list[i].skirmish_weekly_modifiers
                            }
                        )
                    end
                end
            end
        end

        for id, _ in pairs(dead_list) do
            self._active_server_jobs[id] = nil

            managers.menu_component:remove_crimenet_gui_job(id)
        end
    end

    managers.network.matchmake:register_callback("search_lobby", f)
    managers.network.matchmake:search_lobby(friends_only)

    -- Lines: 1231 to 1235
    local function usrs_f(success, amount)
        if success then
            managers.menu_component:set_crimenet_players_online(amount)
        end
    end

    Steam:sa_handler():concurrent_users_callback(usrs_f)
    Steam:sa_handler():get_concurrent_users()
end

Hooks:PostHook(
    CrimeNetGui,
    "update_job_gui",
    "NoDown_CrimeNetGui_update_job_gui",
    function(self, job)
        local data = job.server_data
        job.no_down = data.no_down
        if data.no_down == 1 then
            local one_down_label = job.side_panel:child("one_down_label")
            one_down_label:set_text(managers.localization:to_upper_text("no_down_modifier_name"))
            one_down_label:set_color(NoDown.color)

            local one_down_icon = job.icon_panel:child("one_down_icon")
            one_down_icon:set_color(NoDown.color)
        end
    end
)

Hooks:PostHook(
    CrimeNetGui,
    "update_server_job",
    "NoDown_CrimeNetGui_update_server_job",
    function(self, data, i)
        local job_index = data.id or i
        local job = self._jobs[job_index]

        if not job then
            return
        end

        if self:_update_job_variable(job_index, "no_down", data.no_down) then
            local is_server = job.server
            local x = job.job_x
            local y = job.job_y
            local location = job.location

            self:remove_job(job_index, true)

            local gui_data = self:_create_job_gui(data, is_server and "server" or "contract", x, y, location)
            gui_data.server = is_server
            self._jobs[job_index] = gui_data
        end
    end
)

function CrimeNetGui:check_job_pressed(x, y)
    for id, job in pairs(self._jobs) do
        if job.mouse_over == 1 then
            job.expanded = not job.expanded
            local job_data = tweak_data.narrative:job_data(job.job_id)
            local data = {
                difficulty = job.difficulty,
                difficulty_id = job.difficulty_id,
                one_down = job.one_down,
                no_down = job.no_down,
                job_id = job.job_id,
                level_id = job.level_id,
                id = id,
                room_id = job.room_id,
                server = job.server or false,
                num_plrs = job.num_plrs or 0,
                state = job.state,
                host_name = job.host_name,
                host_id = job.host_id,
                special_node = job.special_node,
                dlc = job.dlc,
                contract_visuals = job_data and job_data.contract_visuals,
                info = job.info,
                mutators = job.mutators,
                is_crime_spree = job.crime_spree and job.crime_spree >= 0,
                crime_spree = job.crime_spree,
                crime_spree_mission = job.crime_spree_mission,
                server_data = job.server_data,
                mods = job.mods,
                skirmish = job.skirmish,
                skirmish_wave = job.skirmish_wave,
                skirmish_weekly_modifiers = job.skirmish_weekly_modifiers
            }

            managers.menu_component:post_event("menu_enter")

            if not data.dlc or managers.dlc:is_dlc_unlocked(data.dlc) then
                local node = job.special_node

                if not node then
                    if Global.game_settings.single_player then
                        node = "crimenet_contract_singleplayer"
                    elseif job.server then
                        node = "crimenet_contract_join"

                        if job.is_crime_spree then
                            node = "crimenet_contract_crime_spree_join"
                        end

                        if job.is_skirmish then
                            node = "skirmish_contract_join"
                        end
                    else
                        node = "crimenet_contract_host"
                    end
                end

                managers.menu:open_node(
                    node,
                    {
                        data
                    }
                )
            elseif is_win32 then
                local dlc_data = Global.dlc_manager.all_dlc_data[data.dlc]
                local app_id = dlc_data and dlc_data.app_id

                if app_id and SystemInfo:distribution() == Idstring("STEAM") then
                    Steam:overlay_activate("store", app_id)
                end
            end

            if job.expanded then
                for id2, job2 in pairs(self._jobs) do
                    if job2 ~= job then
                        job2.expanded = false
                    end
                end
            end

            return true
        end
    end
end
