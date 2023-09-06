loti.debug = {}

--This was pasted from Wesnoth lua pack and is crazy useful

function wesnoth.dbms(lua_var, clear, name, onscreen, wrap, only_return)
	if type(clear) ~= "boolean" then clear = true end
	if type(name) ~= "string" then name = "lua_var" end
	if type(onscreen) ~= "boolean" then onscreen = true end

	local function dump_userdata(data)
		local metatable = getmetatable(data)
		if metatable == "side" then return data.__cfg, true end
		if metatable == "unit" then return data.__cfg, true end
		local data_to_string = tostring(data)
		if metatable == "translatable string" then return data_to_string, false end
		if metatable == "wml object" then return data.__literal, false end
		return data_to_string, true
	end

	local is_wml_table = true
	local result
	local wml_table_error
	local base_indent = "    "
	local function table_to_string(arg_table, indent, introduces_subtag, indices)
		local is_filled = false

		local function check_subtag()
			local one, two = arg_table[1], arg_table[2]
			if type(two) == "userdata" then
				local invalidate_wml_table
				two, invalidate_wml_table = dump_userdata(two)
				if invalidate_wml_table then return false end
			end
			if type(one) ~= "string" or type(two) ~= "table" then return false end
			return true
		end
		if is_wml_table and introduces_subtag then
			if not check_subtag() then
				wml_table_error = string.format("table introducing subtag at %s is not of the form {\"tag_name\", {}}", indices)
				is_wml_table = false
			end
		end

		local index = 1
		for current_key, current_value in pairs(arg_table) do
			is_filled = true

			local current_key_type = type(current_key)
			local current_key_to_string = tostring(current_key)
			local current_type = type(current_value)
			local function no_wml_table(expected, index2, type)
				if not index2 then index2 = current_key_to_string end
				if not type then type = current_type end
				wml_table_error = string.format("value at %s[%s]: %s expected, got %s", indices, index2, expected, type)
				is_wml_table = false
			end

			if current_type == "userdata" then
				local  invalidate_wml_table
				current_value, invalidate_wml_table = dump_userdata(current_value)
				current_type = type(current_value)
				if is_wml_table and invalidate_wml_table then
					wml_table_error = string.format("userdata at %s[%s]", indices, current_key_to_string)
					is_wml_table = false
				end
			end

			if is_wml_table and not introduces_subtag then
				if current_key_type == "string" and (current_type == "table" or current_type == "function" or current_type == "thread") then
					no_wml_table("nil, boolean, number or string")
				elseif current_key_type == "number" then
					if current_type ~= "table" then
						no_wml_table("table")
					elseif current_key ~= index then
						no_wml_table("value", tostring(index), "nil or fields traversed out-of-order")
					end
					index = index + 1
				end
			end

			local length = 9
			local left_bracket, right_bracket = "[", "]"
			if current_key_type == "string" then
				left_bracket, right_bracket = "", ""; length = length - 2
			end
			if current_type == "table" then
				result = string.format("%s%s%s%s%s = {\n", result, indent, left_bracket, current_key_to_string, right_bracket)
				table_to_string(current_value, string.format("%s%s%s", base_indent, indent, string.rep(" ", string.len(current_key_to_string) + length)),
					not introduces_subtag, string.format("%s[%s]", indices, current_key_to_string))
				result = string.format("%s%s%s},\n", result, indent, string.rep(" ", string.len(current_key_to_string) + length))
			else
				local quote = ""; if current_type == "string" then quote = "\"" end
				result = string.format("%s%s%s%s%s = %s%s%s,\n", result, indent, left_bracket, current_key_to_string, right_bracket, quote, tostring(current_value), quote)
			end
		end
		if is_filled then result = string.sub(result, 1, string.len(result) - 2) .. "\n" end
	end

	local engine_is_wml_table
	if wesnoth then
		engine_is_wml_table = pcall(wesnoth.set_variable, "LUA_debug_msg", lua_var); wesnoth.set_variable("LUA_debug_msg")
	end

	local var_type, var_value = type(lua_var), tostring(lua_var)
	is_wml_table = var_type == "table"
	local invalidate_wml_table
	local metatable = getmetatable(lua_var)
	if var_type == "userdata" then
		lua_var, invalidate_wml_table= dump_userdata(lua_var)
		is_wml_table = not invalidate_wml_table
	end
	local new_var_type = type(lua_var)

	local format_string = "%s is of type %s, value %s"
	local format_string_length = format_string .. ", length %u"
	local format_string_length_newline = format_string_length .. ":\n%s"

	if new_var_type == "table" then
		local var_length = #lua_var
		result = "{\n"
		table_to_string(lua_var, base_indent, false, "")
		result = result .. "}"

		if is_wml_table then
			result = string.format(format_string_length_newline, name, "WML table", var_value, var_length, result)
		elseif wml_table_error then
			result = string.format(format_string_length .. ", but no WML table: %s:\n%s", name, "table", var_value, var_length, wml_table_error, result)
		else
			result = string.format(format_string_length_newline, name, var_type, var_value, var_length, result)
		end
	elseif new_var_type == "string" then
		result = string.format(format_string_length, name, var_type, var_value, #lua_var)
	else
		result = string.format(format_string, name, var_type, var_value)
	end

	if metatable then result = string.format("%s\nwith a metatable:\n", result) end

	if wesnoth and is_wml_table ~= engine_is_wml_table  and (var_type == "table" or var_type == "userdata" or var_type == "function" or var_type == "thread") then
		result = string.format("warning: WML table inconsistently predicted, script says %s , engine %s \n%s", tostring(is_wml_table), tostring(engine_is_wml_table), result)
	end

	if clear and wesnoth then wesnoth.interface.clear_chat_messages() end
	if not only_return then
		if wesnoth then wesnoth.interface.add_chat_message("dbms", result) end; print(result)
	end
	local continue = true
	if onscreen and wesnoth and not only_return then
		if wrap then wesnoth.wml_actions.message({ speaker = "narrator", image = "wesnoth-icon.png", message = result })
		else
			local wlp_utils = wesnoth.require "~add-ons/Wesnoth_Lua_Pack/wlp_utils.lua"
			local ret = wlp_utils.message({ caption = "dbms", message = result })
			if ret == -2 then continue = false end
		end
	end
	if metatable and continue then
		result = result .. wesnoth.dbms(metatable, false, string.format("The metatable %s", tostring(metatable)), onscreen, wrap, only_return)
	end
	return result
end

local loop_check = 0
function wesnoth.loop_guard(reaction, arg)
	if not arg then
		arg = 10000
	end
	loop_check = loop_check + 1
	if loop_check > arg then
		reaction()
	end
end

-- Run the automated testsuite.
-- Locates all .test.lua files in tests/lua/ directory and runs them.
-- Each .test.lua file must return a Lua array { test_name_1 => function_to_call, test_name_2 => ... }
-- (see unitdata.test.lua for example) to get detailed PASS/FAIL report.
-- Test functions should throw an exception via error() or assert() to report test failures.
loti.testsuite = function()
	local passed_count = 0
	local failed_count = 0

	-- Find the tests.
	local testdir = "~/add-ons/LotI_Era/tests/lua"
	for _, filename in ipairs(filesystem.read_file(testdir)) do
		if filename:match("%.test%.lua$") then
			print("Testsuite: running " .. filename)

			local checks = wesnoth.require(testdir .. "/" .. filename)
			for description, method in pairs(checks) do
				local is_ok, error_message = pcall(method)
				if is_ok then
					print("PASS\t" .. description)
					passed_count = passed_count + 1
				else
					print("FAIL\t" .. description .. ": " .. error_message)
					failed_count = failed_count + 1
				end
			end
		end
	end

	print("Test results: passed: " .. passed_count .. ", failed: " .. failed_count .. ".")
end

-- Double-check the chances of certain items being dropped.
-- See loti.item.on_the_ground.generate() for description of parameters.
--
-- Sample usage:
-- loti.debug.check_drop_distribution("gem")
-- loti.debug.check_drop_distribution("drop", {"sword", "spear"})
function loti.debug.check_drop_distribution(group, item_types, repetitions)
	repetitions = repetitions or 1000
	group = group or "gem"

	local stats = {} -- { item_name1 = number_of_times_dropped, ... }
	local sorted_names = {} -- { item_name1, item_name2, ... }

	for _ = 1,repetitions do
		local name = loti.item.type[loti.item.on_the_ground.generate(group, item_types)].name
		if not stats[name] then
			stats[name] = 0
			table.insert(sorted_names, name)
		end

		stats[name] = stats[name] + 1
	end

	-- Sort items by frequency of them being dropped
	table.sort(sorted_names, function(a, b) return stats[b] < stats[a] end)

	for _, name in ipairs(sorted_names) do
		print(string.format('%s: %.2f %%', name, 100 * stats[name] / repetitions))
	end
end
