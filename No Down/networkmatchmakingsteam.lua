Hooks:PostHook(
    NetworkMatchMakingSTEAM,
    "set_attributes",
    "NoDown_NetworkMatchMakingSTEAM_set_attributes",
    function(self, settings)
        if not self.lobby_handler then
            return
        end

        if self._lobby_attributes then
            self._lobby_attributes.no_down = Global.game_settings.no_down and 1 or 0
            self.lobby_handler:set_lobby_data(self._lobby_attributes)
        end
    end
)

function NetworkMatchMakingSTEAM:search_lobby(friends_only, no_filters)
    self._search_friends_only = friends_only

    if not self:_has_callback("search_lobby") then
        return
    end

    local function validated_value(lobby, key)
        local value = lobby:key_value(key)

        if value ~= "value_missing" and value ~= "value_pending" then
            return value
        end

        return nil
    end

    if friends_only then
        self:get_friends_lobbies()
    else
        local function refresh_lobby()
            if not self.browser then
                return
            end

            local lobbies = self.browser:lobbies()
            local info = {
                room_list = {},
                attribute_list = {}
            }

            if lobbies then
                for _, lobby in ipairs(lobbies) do
                    if
                        (self._difficulty_filter == 0 or
                            self._difficulty_filter == tonumber(lobby:key_value("difficulty"))) and
                            (NoDown.settings.search_no_down_lobbies ~= 0 or tonumber(lobby:key_value("no_down")) ~= 1)
                     then
                        table.insert(
                            info.room_list,
                            {
                                owner_id = lobby:key_value("owner_id"),
                                owner_name = lobby:key_value("owner_name"),
                                room_id = lobby:id(),
                                owner_level = lobby:key_value("owner_level")
                            }
                        )

                        local attributes_data = {
                            numbers = self:_lobby_to_numbers(lobby),
                            mutators = self:_get_mutators_from_lobby(lobby),
                            crime_spree = tonumber(validated_value(lobby, "crime_spree")),
                            crime_spree_mission = validated_value(lobby, "crime_spree_mission"),
                            mods = validated_value(lobby, "mods"),
                            one_down = tonumber(validated_value(lobby, "one_down")),
                            no_down = tonumber(validated_value(lobby, "no_down")),
                            skirmish = tonumber(validated_value(lobby, "skirmish")),
                            skirmish_wave = tonumber(validated_value(lobby, "skirmish_wave")),
                            skirmish_weekly_modifiers = validated_value(lobby, "skirmish_weekly_modifiers")
                        }

                        table.insert(info.attribute_list, attributes_data)
                    end
                end
            end

            self:_call_callback("search_lobby", info)
        end

        self.browser =
            LobbyBrowser(
            refresh_lobby,
            function()
            end
        )
        local interest_keys = {
            "owner_id",
            "owner_name",
            "level",
            "difficulty",
            "permission",
            "state",
            "num_players",
            "drop_in",
            "min_level",
            "kick_option",
            "job_class_min",
            "job_class_max",
            "allow_mods"
        }

        if self._BUILD_SEARCH_INTEREST_KEY then
            table.insert(interest_keys, self._BUILD_SEARCH_INTEREST_KEY)
        end

        if NoDown.settings.search_no_down_lobbies == 2 then
            table.insert(interest_keys, "no_down")

            self.browser:set_lobby_filter("no_down", 1, "equal")
        end

        self.browser:set_interest_keys(interest_keys)
        self.browser:set_distance_filter(self._distance_filter)

        local use_filters = not no_filters

        if Global.game_settings.gamemode_filter ~= GamemodeStandard.id then
            use_filters = false
        end

        self.browser:set_lobby_filter(self._BUILD_SEARCH_INTEREST_KEY, "true", "equal")

        local filter_value, filter_type = self:get_modded_lobby_filter()

        self.browser:set_lobby_filter("mods", filter_value, filter_type)

        local filter_value, filter_type = self:get_allow_mods_filter()

        self.browser:set_lobby_filter("allow_mods", filter_value, filter_type)
        self.browser:set_lobby_filter(
            "one_down",
            Global.game_settings.search_one_down_lobbies and 1 or 0,
            "equalto_less_than"
        )

        if use_filters then
            self.browser:set_lobby_filter("min_level", managers.experience:current_level(), "equalto_less_than")

            if Global.game_settings.search_appropriate_jobs then
                local min_ply_jc = managers.job:get_min_jc_for_player()
                local max_ply_jc = managers.job:get_max_jc_for_player()

                self.browser:set_lobby_filter("job_class_min", min_ply_jc, "equalto_or_greater_than")
                self.browser:set_lobby_filter("job_class_max", max_ply_jc, "equalto_less_than")
            end
        end

        if not no_filters then
            if false then
                -- Nothing
            elseif Global.game_settings.gamemode_filter == GamemodeCrimeSpree.id then
                local min_level = 0

                if Global.game_settings.crime_spree_max_lobby_diff >= 0 then
                    min_level =
                        managers.crime_spree:spree_level() - (Global.game_settings.crime_spree_max_lobby_diff or 0)
                    min_level = math.max(min_level, 0)
                end

                self.browser:set_lobby_filter("crime_spree", min_level, "equalto_or_greater_than")
            elseif Global.game_settings.gamemode_filter == "skirmish" then
                local min = SkirmishManager.LOBBY_NORMAL

                self.browser:set_lobby_filter("skirmish", min, "equalto_or_greater_than")
                self.browser:set_lobby_filter(
                    "skirmish_wave",
                    Global.game_settings.skirmish_wave_filter or 99,
                    "equalto_less_than"
                )
            elseif Global.game_settings.gamemode_filter == GamemodeStandard.id then
                self.browser:set_lobby_filter("crime_spree", -1, "equalto_less_than")
                self.browser:set_lobby_filter("skirmish", 0, "equalto_less_than")
            end
        end

        if use_filters then
            for key, data in pairs(self._lobby_filters) do
                if data.value and data.value ~= -1 then
                    self.browser:set_lobby_filter(data.key, data.value, data.comparision_type)
                    print(data.key, data.value, data.comparision_type)
                end
            end
        end

        self.browser:set_max_lobby_return_count(self._lobby_return_count)

        if Global.game_settings.playing_lan then
            self.browser:refresh_lan()
        else
            self.browser:refresh()
        end
    end
end

function NetworkMatchMakingSTEAM:get_friends_lobbies()
    local lobbies = {}
    local num_updated_lobbies = 0

    local function is_key_valid(key)
        return key ~= "value_missing" and key ~= "value_pending"
    end

    local function empty()
    end

    local function f(updated_lobby)
        updated_lobby:setup_callback(empty)
        print("NetworkMatchMakingSTEAM:get_friends_lobbies f")

        num_updated_lobbies = num_updated_lobbies + 1

        if num_updated_lobbies >= #lobbies then
            local info = {
                room_list = {},
                attribute_list = {}
            }

            for _, lobby in ipairs(lobbies) do
                if NetworkMatchMakingSTEAM._BUILD_SEARCH_INTEREST_KEY then
                    local ikey = lobby:key_value(NetworkMatchMakingSTEAM._BUILD_SEARCH_INTEREST_KEY)

                    if ikey ~= "value_missing" and ikey ~= "value_pending" then
                        table.insert(
                            info.room_list,
                            {
                                owner_id = lobby:key_value("owner_id"),
                                owner_name = lobby:key_value("owner_name"),
                                room_id = lobby:id()
                            }
                        )

                        local attributes_data = {
                            numbers = self:_lobby_to_numbers(lobby),
                            mutators = self:_get_mutators_from_lobby(lobby)
                        }
                        local crime_spree_key = lobby:key_value("crime_spree")

                        if is_key_valid(crime_spree_key) then
                            attributes_data.crime_spree = tonumber(crime_spree_key)
                            attributes_data.crime_spree_mission = lobby:key_value("crime_spree_mission")
                        end

                        local mods_key = lobby:key_value("mods")

                        if is_key_valid(mods_key) then
                            attributes_data.mods = mods_key
                        end

                        local lobby_one_down = lobby:key_value("one_down")

                        if is_key_valid(lobby_one_down) then
                            attributes_data.one_down = tonumber(lobby_one_down)
                        end

                        local lobby_no_down = lobby:key_value("no_down")

                        if is_key_valid(lobby_no_down) then
                            attributes_data.no_down = tonumber(lobby_no_down)
                        end

                        local skirmish_key = lobby:key_value("skirmish")

                        if is_key_valid(skirmish_key) then
                            attributes_data.skirmish = tonumber(skirmish_key)
                            attributes_data.skirmish_wave = lobby:key_value("skirmish_wave")
                        end

                        table.insert(info.attribute_list, attributes_data)
                    end
                end
            end

            self:_call_callback("search_lobby", info)
        end
    end

    if Steam:logged_on() and Steam:friends() then
        for _, friend in ipairs(Steam:friends()) do
            local lobby = friend:lobby()

            if lobby then
                table.insert(lobbies, lobby)
            end
        end
    end

    if #lobbies == 0 then
        local info = {
            room_list = {},
            attribute_list = {}
        }

        self:_call_callback("search_lobby", info)
    else
        for _, lobby in ipairs(lobbies) do
            lobby:setup_callback(f)

            if lobby:key_value("state") == "value_pending" then
                print("NetworkMatchMakingSTEAM:get_friends_lobbies value_pending")
                lobby:request_data()
            else
                f(lobby)
            end
        end
    end
end
