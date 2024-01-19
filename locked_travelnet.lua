-- contains the node definition for a general travelnet that can be used by anyone
--	further travelnets can only be installed by the owner or by people with the travelnet_attach priv
--	digging of such a travelnet is limited to the owner and to people with the travelnet_remove priv (useful for admins to clean up)
-- (this can be overrided in config.lua)
-- Autor: Sokomine
local S = minetest.get_translator("travelnet")

local locked_forms = {}
local function on_interact(pos, _, player)
	if not locks:lock_allow_use( pos, player ) then
		return false
	end
	locked_forms[player:get_player_name()] = true

	local meta = minetest.get_meta(pos)
	local legacy_formspec = meta:get_string("formspec")
	if not travelnet.is_falsey_string(legacy_formspec) then
		meta:set_string("formspec", "")
	end

	local player_name = player:get_player_name()
	travelnet.show_current_formspec(pos, meta, player_name)
end

local original_end_input = travelnet.actions.end_input
function travelnet.actions.end_input(_, _, player)
	locked_forms[player:get_player_name()] = nil
	return original_end_input(_, _, player)
end

local original_primary_formspec = travelnet.formspecs.primary
function travelnet.formspecs.primary(options, player_name)
	if locked_forms[player_name] then
		options.height = 11.5
		return original_primary_formspec(options, player_name)..
			"field[0.3,11;6,0.7;locks_sent_lock_command;"..S("Locked travelnet. Type /help for help:")..";]"..
			locks.get_authorize_button(10,10.5)..
			locks.get_config_button(11,10.5)
	else
		return original_primary_formspec(options, player_name)
	end
end

local original_edit_formspec = travelnet.formspecs.edit_travelnet
function travelnet.formspecs.edit_travelnet(options, player_name)
	if locked_forms[player_name] then
		return ([[
			size[12,10]
			field[0.3,5.6;6,0.7;station_name;%s:;%s]
			field[0.3,6.6;6,0.7;station_network;%s;%s]
			field[0.3,7.6;6,0.7;owner;%s;%s]
			button[8.0,0.0;2.2,0.7;station_dig;%s]
			field[0.3,3.0;6,0.7;locks_sent_lock_command;%s;]
			button[6.3,3.2;1.7,0.7;station_set;%s]
		]]):format(
			S("Name of this station"),
			minetest.formspec_escape(options.station_name or ""),
			S("Assign to Network:"),
			travelnet.is_falsey_string(options.station_network)
				and "net1"
				or options.station_network,
			S("Owned by:"),
			minetest.formspec_escape(options.owner_name or ""),
			S("Remove station"),
			S("Locked travelnet. Type /help for help:"),
			S("Save")
		)..
		locks.get_authorize_button(6, 0)..
		locks.get_config_button(7, 0)
	else
		return original_edit_formspec(options, player_name)
	end
end

local original_on_receive_fields = travelnet.on_receive_fields
function travelnet.on_receive_fields(pos, formname, fields, player)
	local player_name = player:get_player_name()
	if locked_forms[player_name] then
		if not travelnet.is_falsey_string(fields.locks_sent_lock_command) or fields.locks_config or fields.locks_authorize then
			locked_forms[player_name] = nil
			return locks:lock_handle_input( pos, formname, fields, player )
		elseif locks:lock_allow_use( pos, player ) then
			return original_on_receive_fields( pos, formname, fields, player )
		end
	else
		return original_on_receive_fields( pos, formname, fields, player )
	end
end

minetest.register_node("locked_travelnet:travelnet", {

	description = "Shared locked travelnet box",

	drawtype = "nodebox",
	sunlight_propagates = true,
	paramtype = 'light',
	paramtype2 = "facedir",

	selection_box = {
		type = "fixed",
		fixed = { -0.5, -0.5, -0.5, 0.5, 1.5, 0.5 }
	},

	node_box = {
		type = "fixed",
		fixed = {
			{ 0.45, -0.5,-0.5,  0.5,  1.45, 0.5},
			{-0.5 , -0.5, 0.45, 0.45, 1.45, 0.5},
			{-0.5,  -0.5,-0.5 ,-0.45, 1.45, 0.5},

			--groundplate to stand on
			{ -0.5,-0.5,-0.5,0.5,-0.45, 0.5},
			--roof
			{ -0.5, 1.45,-0.5,0.5, 1.5, 0.5},
		},
	},

	tiles = {
		"default_clay.png",  -- view from top
		"default_clay.png",  -- view from bottom
		"locked_travelnet_travelnet_side_lock.png", -- left side
		"locked_travelnet_travelnet_side_lock.png", -- right side
		"locked_travelnet_travelnet_back_lock.png", -- front view
		"locked_travelnet_travelnet_front_lock.png",  -- backward view
	},
	inventory_image = "locked_travelnet_lock_inv.png",

	groups = {travelnet=1},

	light_source = 10,

	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		--- prepare the lock of the travelnet
		locks:lock_init( pos, "" )
		meta:set_string("formspec", "")
	end,

	after_place_node  = function(pos, placer, itemstack)
		local meta = minetest.get_meta(pos);
		meta:set_string("infotext",        "Travelnet-box (unconfigured)");
		meta:set_string("station_name",    "");
		meta:set_string("station_network", "");
		meta:set_string("owner",           placer:get_player_name() );
		-- request initinal data
		locks:lock_set_owner( pos, placer, "Shared locked travelnet" );
		local top_pos = vector.add({x=0,y=1,z=0}, pos)
		minetest.set_node(top_pos, {name="travelnet:hidden_top"})
	end,

	on_receive_fields = travelnet.on_receive_fields,

	on_punch       = on_interact,
	on_rightclick  = on_interact,

	can_dig = function( pos, player )
		if not locks:lock_allow_dig( pos, player ) then
			return false
		end

		return travelnet.can_dig( pos, player, 'travelnet box' )
	end,

	after_dig_node = function (pos, oldnode, oldmetadata, digger)
		travelnet.remove_box( pos, oldnode, oldmetadata, digger )
	end,

	on_destruct = function (pos)
		minetest.remove_node({x=pos.x, y=pos.y+1, z=pos.z})
	end,

	-- taken from VanessaEs homedecor fridge
	on_place = function (itemstack, placer, pointed_thing)
		local pos = pointed_thing.above;
		local node = minetest.get_node({x=pos.x, y=pos.y+1, z=pos.z})
		local def = minetest.registered_nodes[node.name]
		if (not def or not def.buildable_to) and node.name ~= "travelnet:hidden_top" then
			minetest.chat_send_player( placer:get_player_name(), 'Not enough vertical space to place the travelnet box!' )
			return
		end
		return minetest.item_place(itemstack, placer, pointed_thing);
	end,
})


minetest.register_craft({
	output = 'locked_travelnet:travelnet',
	recipe = {
		{ 'travelnet:travelnet', 'locks:lock' },
	},
})

if minetest.global_exists("mesecon") and mesecon.register_mvps_stopper then
	mesecon.register_mvps_stopper('locked_travelnet:travelnet')
end

print( "[Mod] locked_travelnet: loading locked_travelnet:travelnet");
