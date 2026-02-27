core.register_alias("pencil", "mtpaint:pencil")
core.register_alias("flood_fill", "mtpaint:flood_fill")
core.register_alias("bucket", "mtpaint:flood_fill")
core.register_alias("eraser", "mtpaint:eraser")
core.register_alias("gum", "mtpaint:eraser")
core.register_alias("picker", "mtpaint:picker")
core.register_alias("colorpicker", "mtpaint:picker")
core.register_alias("nodepicker", "mtpaint:picker")
core.register_alias("box_fill", "mtpaint:box_fill")
core.register_alias("box_outline", "mtpaint:box_outline")
core.register_alias("ellipsoid_fill", "mtpaint:ellipsoid_fill")
core.register_alias("line", "mtpaint:line")

local S = core.get_translator and core.get_translator("mtpaint") or function(s) return s end

local function get_replacer(user, slot)
    slot = slot or 1
    local inv = user:get_inventory()
    local name = inv:get_stack("main", slot):get_name()
    if name == "" or name == "ignore" then
        return "air"
    end
    return name
end

local function minmax_pos(c1, c2)
    return {
        x = math.min(c1.x, c2.x),
        y = math.min(c1.y, c2.y),
        z = math.min(c1.z, c2.z),
    },{
        x = math.max(c1.x, c2.x),
        y = math.max(c1.y, c2.y),
        z = math.max(c1.z, c2.z),
    }
end

local function can_replace(pos)
    local node = core.get_node(pos)
    local def = core.registered_nodes[node.name]
    return def and def.buildable_to
end

-- Shared fill helper
local function perform_fill(set_node, pointed_thing, user, opts)
    opts = opts or {}
    local under = pointed_thing.under
    local above = pointed_thing.above
    local modifier = user:get_player_control().aux1
    local clicked = core.get_node(under).name
    if not clicked or clicked == "ignore" then return end

    -- aux1 replace_component: handled by the BFS below (connected component),
    -- avoid scanning the entire world with find_nodes_in_area.

    local offsets
    local normal
    if opts.plane_only then
        normal = { x = above.x - under.x, y = above.y - under.y, z = above.z - under.z }
        if normal.y ~= 0 then
            offsets = {{1,0,0},{-1,0,0},{0,0,1},{0,0,-1}}
        elseif normal.x ~= 0 then
            offsets = {{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
        elseif normal.z ~= 0 then
            offsets = {{1,0,0},{-1,0,0},{0,1,0},{0,-1,0}}
        else
            return
        end
    else
        offsets = {{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
    end

    local visited = {}
    local queue = {vector.new(under)}
    local to_replace = {}

    local function hash(p) return p.x..","..p.y..","..p.z end

    while #queue > 0 do
        local pos = table.remove(queue, 1)
        local h = hash(pos)
        if not visited[h] then
            visited[h] = true
            local ok = true
            if opts.predicate then
                ok = opts.predicate(pos, normal)
            end
            if core.get_node(pos).name == clicked and ok then
                table.insert(to_replace, pos)
                for _, off in ipairs(offsets) do
                    table.insert(queue, { x = pos.x + off[1], y = pos.y + off[2], z = pos.z + off[3] })
                end
            end
        end
    end

    if opts.aux1_mode == "replace_component" and modifier then
        -- surround the connected component instead of replacing nodes
        local comp_set = {}
        for _, p in ipairs(to_replace) do
            comp_set[p.x..","..p.y..","..p.z] = true
        end
        local surround_offsets = {{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
        local placed = {}
        for _, pos in ipairs(to_replace) do
            for _, off in ipairs(surround_offsets) do
                local t = { x = pos.x + off[1], y = pos.y + off[2], z = pos.z + off[3] }
                local h = t.x..","..t.y..","..t.z
                if not comp_set[h] and not placed[h] and can_replace(t) then
                    set_node(t)
                    placed[h] = true
                end
            end
        end
    else
        for _, pos in ipairs(to_replace) do
            if opts.aux1_mode == "place_face" and modifier and normal then
                set_node({ x = pos.x + normal.x, y = pos.y + normal.y, z = pos.z + normal.z })
            else
                set_node(pos)
            end
        end
    end
end

local function register_mtpaint_range_tool(def)
    local function wrapper(itemstack, user, pointed_thing, slot)
        if pointed_thing.type ~= "node" then return end

        local modifier = user:get_player_control().aux1
        local pos = modifier and pointed_thing.above or pointed_thing.under
        local node = get_replacer(user, slot)

        local function set_node(p)
            core.set_node(p, {name=node})
        end

        local meta = itemstack:get_meta()
        local corner1 = meta:get_string("mtpaint:corner")

        if corner1 == "" then
            meta:set_string("mtpaint:corner", minetest.serialize(pos))
            return itemstack
        end

        local c1 = minetest.deserialize(corner1)
        meta:set_string("mtpaint:corner", "")
        local minp, maxp = minmax_pos(c1, pos)

        def.action(set_node, minp, maxp)
        return itemstack
    end

    core.register_tool("mtpaint:"..def.name, {
        description = S(def.description or def.name),
        inventory_image = def.inventory_image,
        on_use = function(itemstack, user, pointed_thing)
            return wrapper(itemstack, user, pointed_thing, 1)
        end,
        on_place = function(itemstack, user, pointed_thing)
            return wrapper(itemstack, user, pointed_thing, 2)
        end,
    })
end

local function register_mtpaint_point_tool(def)
    local function wrapper(_, user, pointed_thing, right_click, slot)
        if pointed_thing.type ~= "node" then return end

        local node = get_replacer(user, slot)
        local function set_node(p)
            core.set_node(p, {name=node})
        end
        def.action(set_node, pointed_thing, user, right_click)

    end
    core.register_tool("mtpaint:"..def.name, {
        description = S(def.description or def.name),
        inventory_image = def.inventory_image or "",
        on_use = function(itemstack, user, pointed_thing)
            return wrapper(itemstack, user, pointed_thing, false, 1)
        end,
        on_place = function(itemstack, user, pointed_thing)
            return wrapper(itemstack, user, pointed_thing, true, 2)
        end,

    })
end

-- Point tools

register_mtpaint_point_tool({
    name = "eraser",
    description = "Eraser",
    inventory_image = "paint_eraser.png",
    action = function(_, pointed_thing)
        core.remove_node(pointed_thing.under)
    end
})

-- 3D Flood Fill (additive): aux1 = global replace; otherwise 6-neighbor connected fill
register_mtpaint_point_tool({
    name = "additive_fill",
    description = "3D Flood Fill",
    inventory_image = "paint_additive_fill.png",
    action = function(set_node, pointed_thing, user, right_click)
        -- aux1 now replaces the entire connected component instead of scanning the whole world
        perform_fill(set_node, pointed_thing, user, { plane_only = false, aux1_mode = "replace_component" })
    end
})

register_mtpaint_point_tool({
    name = "pencil",
    description = "Pencil",
    inventory_image = "paint_pencil.png",
    action = function(set_node, pointed_thing, user)
        local modifier = user:get_player_control().aux1
        local pos = modifier and pointed_thing.above or pointed_thing.under
        set_node(pos)
    end
})

register_mtpaint_point_tool({
    name = "picker",
    description = "Picker",
    inventory_image = "paint_picker.png",
    action = function(_, pointed_thing, user, right_click)
        local slot = right_click and 2 or 1
        local node = core.get_node(pointed_thing.under).name
        if not node or node == "ignore" then return end

        local inv = user:get_inventory()
        local oldnode = inv:get_stack("main", slot):get_name()
        inv:set_stack("main", slot, node)

        if oldnode ~= "" and
           not inv:contains_item("main", oldnode) and
           inv:room_for_item("main", ItemStack(oldnode)) then
            inv:add_item("main", oldnode.." 1")
        end
    end
})

register_mtpaint_point_tool({
    name = "flood_fill",
    description = "Flood Fill",
    inventory_image = "paint_fill.png",
    action = function(set_node, pointed_thing, user)
        local predicate = function(pos, normal)
            if not normal then return false end
            local neighbor = { x = pos.x + normal.x, y = pos.y + normal.y, z = pos.z + normal.z }
            return can_replace(neighbor)
        end
        perform_fill(set_node, pointed_thing, user, {
            plane_only = true,
            predicate = predicate,
            aux1_mode = "place_face"
        })
    end
})

-- Range tools

register_mtpaint_range_tool({
    name = "box_fill",
    description = "Filled Box",
    inventory_image = "mtpaint_box_fill.png",
    action = function(set_node, minp, maxp)
        for x=minp.x,maxp.x do
            for y=minp.y,maxp.y do
                for z=minp.z,maxp.z do
                    set_node({x=x,y=y,z=z})
                end
            end
        end
    end
})

register_mtpaint_range_tool({
    name = "ellipsoid_fill",
    description = "Filled Ellipsoid",
    inventory_image = "mtpaint_ellipsoid_fill.png",
    action = function(set_node, minp, maxp)
        local cx = (minp.x+maxp.x)/2
        local cy = (minp.y+maxp.y)/2
        local cz = (minp.z+maxp.z)/2

        local rx = math.max((maxp.x-minp.x)/2, 0.5)
        local ry = math.max((maxp.y-minp.y)/2, 0.5)
        local rz = math.max((maxp.z-minp.z)/2, 0.5)

        for x=minp.x,maxp.x do
            for y=minp.y,maxp.y do
                for z=minp.z,maxp.z do
                    local dx=(x-cx)/rx
                    local dy=(y-cy)/ry
                    local dz=(z-cz)/rz
                    if dx*dx+dy*dy+dz*dz <= 1 then
                        set_node({x=x,y=y,z=z})
                    end
                end
            end
        end
    end
})

local function draw_line(a,b)
    local points={}
    local dx,dy,dz=math.abs(b.x-a.x),math.abs(b.y-a.y),math.abs(b.z-a.z)
    local sx=(a.x<b.x) and 1 or -1
    local sy=(a.y<b.y) and 1 or -1
    local sz=(a.z<b.z) and 1 or -1
    local ax,ay,az=dx*2,dy*2,dz*2
    local x,y,z=a.x,a.y,a.z

    if dx>=dy and dx>=dz then
        local yd,zd=ay-dx,az-dx
        while true do
            table.insert(points,{x=x,y=y,z=z})
            if x==b.x then break end
            if yd>=0 then y=y+sy yd=yd-ax end
            if zd>=0 then z=z+sz zd=zd-ax end
            x=x+sx yd=yd+ay zd=zd+az
        end
    elseif dy>=dx and dy>=dz then
        local xd,zd=ax-dy,az-dy
        while true do
            table.insert(points,{x=x,y=y,z=z})
            if y==b.y then break end
            if xd>=0 then x=x+sx xd=xd-ay end
            if zd>=0 then z=z+sz zd=zd-ay end
            y=y+sy xd=xd+ax zd=zd+az
        end
    else
        local xd,yd=ax-dz,ay-dz
        while true do
            table.insert(points,{x=x,y=y,z=z})
            if z==b.z then break end
            if xd>=0 then x=x+sx xd=xd-az end
            if yd>=0 then y=y+sy yd=yd-az end
            z=z+sz xd=xd+ax yd=yd+ay
        end
    end
    return points
end

register_mtpaint_range_tool{
    name="line",
    description="Line",
    inventory_image="mtpaint_line.png",
    action=function(set_node,minp,maxp)
        for _,p in ipairs(draw_line(minp,maxp)) do
            set_node(p)
        end
    end
}

register_mtpaint_range_tool({
    name = "box_outline",
    description = "Box Outline",
    inventory_image = "mtpaint_box_outline.png",
    action = function(set_node, minp, maxp)
        local corners = {
            {x=minp.x,y=minp.y,z=minp.z},{x=maxp.x,y=minp.y,z=minp.z},
            {x=minp.x,y=maxp.y,z=minp.z},{x=maxp.x,y=maxp.y,z=minp.z},
            {x=minp.x,y=minp.y,z=maxp.z},{x=maxp.x,y=minp.y,z=maxp.z},
            {x=minp.x,y=maxp.y,z=maxp.z},{x=maxp.x,y=maxp.y,z=maxp.z},
        }

        local edges={
            {1,2},{3,4},{5,6},{7,8},
            {1,3},{2,4},{5,7},{6,8},
            {1,5},{2,6},{3,7},{4,8},
        }

        for _,e in ipairs(edges) do
            for _,p in ipairs(draw_line(corners[e[1]],corners[e[2]])) do
                set_node(p)
            end
        end
    end
})
