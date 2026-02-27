local function ellipse_fill_additive(itemstack,user,pointed_thing,slot)
    if pointed_thing.type ~= "node" then return end
    local pname = user:get_player_name()
    ellipse_selections[pname] = ellipse_selections[pname] or {}
    local replacer = get_replacer(user,slot)
    local pos1 = pointed_thing.under

    if not ellipse_selections[pname].corner1 then
        ellipse_selections[pname].corner1 = pos1
        minetest.chat_send_player(pname,"Ellipse corner 1 set at "..pos1.x..","..pos1.y..","..pos1.z)
        return
    end

    local c1, c2 = ellipse_selections[pname].corner1, pos1
    ellipse_selections[pname].corner1 = nil

    local dx, dy, dz = pointed_thing.above.x-pos1.x, pointed_thing.above.y-pos1.y, pointed_thing.above.z-pos1.z
    local modifier = user:get_player_control().aux1
    local plane_axes, fixed_axis = {}, {}
    if dy ~= 0 then plane_axes = {"x","z"} fixed_axis.axis="y" fixed_axis.value=pos1.y
    elseif dx ~= 0 then plane_axes = {"y","z"} fixed_axis.axis="x" fixed_axis.value=pos1.x
    elseif dz ~= 0 then plane_axes = {"x","y"} fixed_axis.axis="z" fixed_axis.value=pos1.z end

    local minp, maxp = minmax_pos(c1, c2)

    local cx = (minp[plane_axes[1]]+maxp[plane_axes[1]])/2
    local cy = (minp[plane_axes[2]]+maxp[plane_axes[2]])/2
    local rx = (maxp[plane_axes[1]]-minp[plane_axes[1]])/2
    local ry = (maxp[plane_axes[2]]-minp[plane_axes[2]])/2

    for a=minp[plane_axes[1]],maxp[plane_axes[1]] do
        for b=minp[plane_axes[2]],maxp[plane_axes[2]] do
            local dxn, dyn = a-cx, b-cy
            if (dxn*dxn)/(rx*rx) + (dyn*dyn)/(ry*ry) <= 1 then
                local pos = {x=0,y=0,z=0}
                pos[plane_axes[1]] = a
                pos[plane_axes[2]] = b
                pos[fixed_axis.axis] = fixed_axis.value

                if not modifier then
                    local normal = fixed_axis.axis
                    while core.get_node(pos).name ~= "air" and pos[normal] < 31000 do
                        pos[normal] = pos[normal]+1
                    end
                end

                core.set_node(pos,{name=replacer})
            end
        end
    end

    minetest.chat_send_player(pname,"Ellipse filled with "..replacer)
end



local function rect_fill_additive(itemstack, user, pointed_thing, slot)
    if pointed_thing.type ~= "node" then return end
    local pname = user:get_player_name()
    rect_selections[pname] = rect_selections[pname] or {}
    local replacer = get_replacer(user, slot)
    local pos1 = pointed_thing.under

    if not rect_selections[pname].corner1 then
        rect_selections[pname].corner1 = pos1
        minetest.chat_send_player(pname,"Rectangle corner 1 set at "..pos1.x..","..pos1.y..","..pos1.z)
        return
    end

    local c1, c2 = rect_selections[pname].corner1, pos1
    rect_selections[pname].corner1 = nil

    local minp, maxp = minmax_pos(c1, c2)

    local modifier = user:get_player_control().aux1

    for x=minp.x,maxp.x do
        for y=minp.y,maxp.y do
            for z=minp.z,maxp.z do
                local pos = {x=x,y=y,z=z}
                if not modifier then
                    local normal = "y"
                    while core.get_node(pos).name ~= "air" and pos[normal] < 31000 do
                        pos[normal] = pos[normal]+1
                    end
                end
                core.set_node(pos,{name=replacer})
            end
        end
    end

    minetest.chat_send_player(pname,"Rectangle filled with "..replacer)
end
local function fill_on_use_additive(itemstack, user, pointed_thing, slot)
    if pointed_thing.type ~= "node" then return end
    local replacer = get_replacer(user, slot)

    local under = pointed_thing.under
    local clicked_node = core.get_node(under).name
    if clicked_node == replacer or clicked_node == "ignore" then return end

    local visited = {}
    local queue = {under}
    local to_replace = {}
    local radius = 10
    local full_plane = user:get_player_control().aux1

    local function pos_hash(pos)
        return pos.x..","..pos.y..","..pos.z
    end

    local function get_neighbors(pos)
        local offsets = {{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
        local neighbors = {}
        for _, off in ipairs(offsets) do
            local npos = {x=pos.x+off[1], y=pos.y+off[2], z=pos.z+off[3]}
            if full_plane or
               (math.abs(npos.x-under.x) <= radius and
                math.abs(npos.y-under.y) <= radius and
                math.abs(npos.z-under.z) <= radius) then
                table.insert(neighbors, npos)
            end
        end
        return neighbors
    end

    -- BFS: collect all nodes to replace
    while #queue > 0 do
        local pos = table.remove(queue, 1)
        local hash = pos_hash(pos)
        if not visited[hash] then
            visited[hash] = true
            if core.get_node(pos).name == clicked_node then
                table.insert(to_replace, pos)
                for _, npos in ipairs(get_neighbors(pos)) do
                    table.insert(queue, npos)
                end
            end
        end
    end

    -- Second pass: replace nodes
    local modifier = user:get_player_control().aux1
    for _, pos in ipairs(to_replace) do
        local target_pos = {x=pos.x, y=pos.y, z=pos.z}
        if modifier and replacer ~= "air" then
            -- aux1 = place on top of existing
            while core.get_node(target_pos).name ~= "air" and target_pos.y < 31000 do
                target_pos.y = target_pos.y + 1
            end
        end
        core.set_node(target_pos, {name=replacer})
    end
end
