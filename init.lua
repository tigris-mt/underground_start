local storage = minetest.get_mod_storage()

local m = {
    y = tonumber(minetest.settings:get("underground_start.y")) or -1000,
    extent_x = tonumber(minetest.settings:get("underground_start.extent_x")) or 33,
    extent_y = tonumber(minetest.settings:get("underground_start.extent_y")) or 17,
    extent_z = tonumber(minetest.settings:get("underground_start.extent_z")) or 33,
    static_spawn = minetest.settings:get_bool("underground_start.static_spawn", true),

    padding = 2,

    nodes = {
        air = "air",

        wall = "default:steelblock",
        floor = "default:steelblock",
        pillar = "default:steelblock",

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

-- Spawn is a safe zone.
if minetest.get_modpath("tigris_base") then
    local origin, boxmin, boxmax = m.box()
    local old = tigris.check_pos_safe
    tigris.check_pos_safe = function(pos)
        local s = (pos.x >= boxmin.x and pos.y >= boxmin.y and pos.z >= boxmin.z and pos.x <= boxmax.x and pos.y <= boxmax.y and pos.z <= boxmax.z)
        return s or old(pos)
    end
end

-- Spawn is protected.
(function()
    local origin, boxmin, boxmax = m.box()
    local old = minetest.is_protected
    minetest.is_protected = function(pos, name)
        local s = (pos.x >= boxmin.x and pos.y >= boxmin.y and pos.z >= boxmin.z and pos.x <= boxmax.x and pos.y <= boxmax.y and pos.z <= boxmax.z)
        return s or old(pos, name)
    end
end)()

if m.static_spawn then
    minetest.settings:set("static_spawnpoint", minetest.pos_to_string(({m.box()})[1]))
end

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

            local ladder_pos = (pos.x == origin.x and pos.z == origin.z + 6)

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
    end

    local waiting = 1
    local function check()
        waiting = waiting - 1
        if waiting == 0 then
            generate()
        end
    end

    minetest.log("Emerging spawn area...")

    minetest.emerge_area(vector.multiply(boxmin, 1.15), vector.multiply(boxmax, 1.15), function(_, _, remain)
        if remain % 10 == 0 then
            minetest.log(remain .. " blocks left to emerge for spawn.")
        end
        if remain == 0 then
            check()
        end
    end)
end)

minetest.register_on_joinplayer(function(player)
    if not m.done then
        minetest.chat_send_player(player:get_player_name(), "The spawn is generating. This shouldn't take very long.")
    end
end)
