function HUDStatsScreen:apply_no_down()
	if not Global.game_settings.no_down then
		return
	end

	local difficulty_stars = managers.job:current_difficulty_stars()
	local difficulty = tweak_data.difficulties[difficulty_stars + 2] or 1
	local difficulty_string = managers.localization:to_upper_text(tweak_data.difficulty_name_ids[difficulty])
	local no_down_string = managers.localization:to_upper_text("no_down_modifier_name")

	for _, child in pairs(self._left:children()) do
		if child and child.text then
			local content = child:text()
			if type(content) == "string" then
				if string.find(content, managers.localization:to_upper_text("menu_one_down")) then
					child:set_text(difficulty_string .. " " .. no_down_string)
					child:set_range_color(#difficulty_string + 1, math.huge, NoDown.color)

					local _, _, tw, th = child:text_rect()

					child:set_size(tw, th)
					return
				end
			end
		end
	end
end

Hooks:PostHook(
	HUDStatsScreen,
	"recreate_left",
	"NoDown_HUDStatsScreen_recreate_left",
	function(self)
		self:apply_no_down()
	end
)
