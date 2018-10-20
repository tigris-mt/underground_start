local storage = minetest.get_mod_storage()

local m = {
    y = tonumber(minetest.settings:get("underground_start.y")) or -200,
    extent_x = tonumber(minetest.settings:get("underground_start.extent_x")) or 12,
    extent_y = tonumber(minetest.settings:get("underground_start.extent_y")) or 17,
    extent_z = tonumber(minetest.settings:get("underground_start.extent_z")) or 12,

    tunnel_height = tonumber(minetest.settings:get("underground_start.tunnel_height")) or 5,
    tunnel_width = tonumber(minetest.settings:get("underground_start.tunnel_width")) or 24,
    tunnel_length = tonumber(minetest.settings:get("underground_start.tunnel_length")) or 121,

    near = tonumber(minetest.settings:get("underground_start.near") or 150),

    done = false,

    nodes = {
        air = "air",

        wall = "default:obsidian_glass",
        floor = "default:obsidian_glass",
        pillar = "default:obsidian_glass",

        tunnel_floor = "default:wood",

        lighting = "default:meselamp",

        ladder = "default:ladder_steel",
        receptor = "default:goldblock",
    },
}
underground_start = m

function m.box()
    local origin = vector.new(0, m.y, 0)
    local extent = vector.new(m.extent_x, m.extent_y, m.extent_z)
    return origin, vector.subtract(origin, extent), vector.add(origin, extent)
end

local origin, boxmin, boxmax = m.box()

m.tunnels = {}
local tw, th, tl = m.tunnel_width, m.tunnel_height, m.tunnel_length
local function tunnel(min, max)
    table.insert(m.tunnels, {min = min, max = max})
end
tunnel(vector.new(origin.x, origin.y - 9, origin.z - tw / 2), vector.new(origin.x + tl, origin.y, origin.z + tw / 2))
tunnel(vector.new(origin.x - tl, origin.y - 9, origin.z - tw / 2), vector.new(origin.x, origin.y, origin.z + tw / 2))
tunnel(vector.new(origin.x - tw / 2, origin.y - 9, origin.z), vector.new(origin.x + tw / 2, origin.y, origin.z + tl))
tunnel(vector.new(origin.x - tw / 2, origin.y - 9, origin.z - tl), vector.new(origin.x + tw / 2, origin.y, origin.z))

local boxes = {{min = boxmin, max = boxmax}}
for _,v in ipairs(m.tunnels) do
    table.insert(boxes, v)
end

local function in_boxes(pos)
    local origin, boxmin, boxmax = m.box()
    for _,box in ipairs(boxes) do
        local boxmin, boxmax = box.min, box.max
        if pos.x >= boxmin.x and pos.y >= boxmin.y and pos.z >= boxmin.z and pos.x <= boxmax.x and pos.y <= boxmax.y and pos.z <= boxmax.z then
            return true
        end
    end
    return false
end

-- Spawn is a safe zone.
if minetest.get_modpath("tigris_base") then
    local old = tigris.check_pos_safe
    tigris.check_pos_safe = function(pos)
        return in_boxes(pos) or old(pos)
    end
end

-- Spawn is protected.
(function()
    local old = minetest.is_protected
    minetest.is_protected = function(pos, name)
        return in_boxes(pos) or old(pos, name)
    end
end)()

function m.check_pos_near(pos)
    if vector.distance(origin, pos) <= m.near then
        return true
    end
end

minetest.register_on_newplayer(function(player)
    player:setpos(origin)
end)

local enable_bed_respawn = minetest.get_modpath("beds") and minetest.settings:get_bool("enable_bed_respawn", true)
minetest.register_on_respawnplayer(function(player)
    if enable_bed_respawn and beds and beds.spawn[player:get_player_name()] then
        return
    end
    player:setpos(origin)
    return true
end)

function m.generation_callback()
    -- Override elsewhere.
end

if storage:get_int("run") == 1 then
    m.done = true
    return
end

minetest.after(0, function()
    local begin_time = os.time()

    local nodes = {}
    for k,v in pairs(m.nodes) do
        nodes[k] = minetest.get_content_id(v)
    end

    local origin, boxmin, boxmax = m.box()

    local function generate()
        minetest.log("Generating spawn...")

        -- Generate large tunnels of air.
        local function tunnel(boxmin, boxmax)
            local vm = minetest.get_voxel_manip()
            local emin, emax = vm:read_from_map(boxmin, boxmax)
            local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
            local data = vm:get_data()

            for i in area:iter(boxmin.x, boxmin.y, boxmin.z, boxmax.x, boxmax.y, boxmax.z) do
                local pos = area:position(i)
                data[i] = nodes.air

                if pos.y == boxmin.y then
                    data[i] = (pos.x % 7 == 0 or pos.z % 7 == 0) and nodes.lighting or nodes.tunnel_floor
                end
            end

            vm:set_data(data)
            vm:write_to_map()
        end

        for _,v in ipairs(m.tunnels) do
            tunnel(v.min, v.max)
        end

        local vm = minetest.get_voxel_manip()
        local emin, emax = vm:read_from_map(boxmin, boxmax)
        local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
        local data = vm:get_data()
        local p2data = vm:get_param2_data()

        -- Inner air.
        for i in area:iter(boxmin.x, boxmin.y, boxmin.z, boxmax.x, boxmax.y, boxmax.z) do
            local pos = area:position(i)
            -- Check for pillar every 7 x/z.
            if pos.x % 7 == 0 and pos.z % 7 == 0 and (pos.x ~= origin.x or pos.z ~= origin.z) then
                -- Lighting.
                data[i] = (pos.y % 4 == 0) and nodes.lighting or nodes.pillar
            else
                -- Air.
                data[i] = nodes.air
            end

            local ladder_pos = (pos.x == origin.x and pos.z == origin.z + 6) and pos.y ~= boxmin.y

            -- Check for floor every 8 y.
            if (pos.y + 1) % 8 == 0 and not ladder_pos then
                data[i] = nodes.floor
            end

            if ladder_pos then
                data[i] = nodes.ladder
                p2data[i] = 4
            end

            if (pos.y >= (origin.y - 1) and pos.y <= (origin.y + 7)) and (pos.x == boxmin.x or pos.x == boxmax.x or pos.z == boxmin.z or pos.z == boxmax.z) then
                data[i] = nodes.wall
            end
        end

        -- Receptor pad.
        data[area:index(origin.x, origin.y - 1, origin.z)] = nodes.receptor
        data[area:index(origin.x, origin.y - 1, origin.z - 1)] = nodes.receptor
        data[area:index(origin.x - 1, origin.y - 1, origin.z)] = nodes.receptor
        data[area:index(origin.x + 1, origin.y - 1, origin.z)] = nodes.receptor
        data[area:index(origin.x, origin.y, origin.z - 1)] = nodes.receptor
        data[area:index(origin.x - 1, origin.y, origin.z)] = nodes.receptor
        data[area:index(origin.x + 1, origin.y, origin.z)] = nodes.receptor

        vm:set_data(data)
        vm:set_param2_data(p2data)
        vm:write_to_map()

        m.generation_callback()

        m.done = true
        storage:set_int("run", 1)
        minetest.log("Generated spawn in " .. (os.time() - begin_time) .. " seconds.")

        for _,player in ipairs(minetest.get_connected_players()) do
            player:setpos(origin)
            player:set_look_horizontal(0)
        end
    end

    local waiting = #boxes
    local function check()
        waiting = waiting - 1
        if waiting <= 0 then
            generate()
        else
            minetest.chat_send_all("Generated " .. (#boxes - waiting) .. "/" .. #boxes .. " segments.")
        end
    end

    minetest.log("Emerging spawn area...")

    local r = vector.new(16, 16, 16)
    for _,box in ipairs(boxes) do
        minetest.emerge_area(vector.subtract(box.min, r), vector.add(box.max, r), function(_, _, remain)
            if remain == 0 then
                check()
            end
        end)
    end
end)

minetest.register_on_joinplayer(function(player)
    if not m.done then
        minetest.chat_send_player(player:get_player_name(), "The spawn is generating. This shouldn't take very long.")
    end
end)
