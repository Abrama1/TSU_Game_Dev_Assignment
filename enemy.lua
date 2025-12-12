local Enemy = {}
Enemy.__index = Enemy

local ENEMY_FRAME_SIZE   = 100  -- sprite frame size
local SPRITE_SCALE       = 1

-- collision hitbox
local ENEMY_HITBOX_WIDTH  = 50
local ENEMY_HITBOX_HEIGHT = 60

local ENEMY_SPEED           = 70      -- base speed (will be overwritten by main via enemy.speed)
local ENEMY_MAX_HP          = 3
local ENEMY_ATTACK_COOLDOWN = 0.8     -- seconds between hits

-- Grid / pathfinding
local TILE_SIZE = 32
local MAP_WIDTH  = 800   -- keep in sync with main.lua
local MAP_HEIGHT = 600

local PATH_RECALC_INTERVAL = 0.4  -- seconds between A* recalculations

-- 4-directional neighbors
local NEIGHBORS = {
    { 1,  0},
    {-1,  0},
    { 0,  1},
    { 0, -1},
}

local function length(x, y)
    return math.sqrt(x * x + y * y)
end

local function normalize(x, y)
    local len = length(x, y)
    if len == 0 then return 0, 0 end
    return x / len, y / len
end

local function rectsOverlap(a, b)
    return a.x < b.x + b.w and
           a.x + a.w > b.x and
           a.y < b.y + b.h and
           a.y + a.h > b.y
end

local function worldToTile(x, y)
    local tx = math.floor(x / TILE_SIZE) + 1
    local ty = math.floor(y / TILE_SIZE) + 1
    return tx, ty
end

local function tileToWorldCenter(tx, ty)
    local x = (tx - 0.5) * TILE_SIZE
    local y = (ty - 0.5) * TILE_SIZE
    return x, y
end

local function inBounds(tx, ty, cols, rows)
    return tx >= 1 and tx <= cols and ty >= 1 and ty <= rows
end

local function isTileBlocked(tx, ty, walls)
    local x = (tx - 1) * TILE_SIZE
    local y = (ty - 1) * TILE_SIZE
    local tileRect = { x = x, y = y, w = TILE_SIZE, h = TILE_SIZE }

    for _, wall in ipairs(walls) do
        if rectsOverlap(tileRect, wall) then
            return true
        end
    end

    return false
end

local function heuristic(tx1, ty1, tx2, ty2)
    -- Manhattan heuristic works fine on grid, we could also use Euclidean
    local dx = math.abs(tx1 - tx2)
    local dy = math.abs(ty1 - ty2)
    return dx + dy
end

-- Basic A* pathfinding on walls grid
local function findPath(startTx, startTy, goalTx, goalTy, walls)
    local cols = math.floor(MAP_WIDTH / TILE_SIZE)
    local rows = math.floor(MAP_HEIGHT / TILE_SIZE)

    if not inBounds(startTx, startTy, cols, rows) then return nil end
    if not inBounds(goalTx,  goalTy,  cols, rows) then return nil end

    -- If goal is inside a wall, we can still path to the closest neighbors, but
    -- for simplicity we just early exit.
    if isTileBlocked(goalTx, goalTy, walls) then
        return nil
    end

    local openSet = {}
    local openSetMap = {}
    local cameFrom = {}

    local gScore = {}
    local fScore = {}

    local function key(tx, ty)
        return tx .. "," .. ty
    end

    local startKey = key(startTx, startTy)
    gScore[startKey] = 0
    fScore[startKey] = heuristic(startTx, startTy, goalTx, goalTy)

    table.insert(openSet, { tx = startTx, ty = startTy })
    openSetMap[startKey] = true

    while #openSet > 0 do
        -- find node in openSet with lowest fScore
        local bestIndex = 1
        local bestNode  = openSet[1]
        local bestKey   = key(bestNode.tx, bestNode.ty)
        local bestF     = fScore[bestKey] or math.huge

        for i = 2, #openSet do
            local n = openSet[i]
            local nk = key(n.tx, n.ty)
            local nf = fScore[nk] or math.huge
            if nf < bestF then
                bestF = nf
                bestIndex = i
                bestNode = n
                bestKey = nk
            end
        end

        local current = bestNode
        local curKey  = bestKey

        -- goal reached
        if current.tx == goalTx and current.ty == goalTy then
            -- reconstruct path
            local path = {}
            local pKey = curKey
            while pKey do
                local cx, cy = pKey:match("([^,]+),([^,]+)")
                cx, cy = tonumber(cx), tonumber(cy)
                table.insert(path, 1, { tx = cx, ty = cy })
                pKey = cameFrom[pKey]
            end
            return path
        end

        -- remove current from openSet
        table.remove(openSet, bestIndex)
        openSetMap[curKey] = nil

        local curG = gScore[curKey] or math.huge

        -- neighbor exploration
        for _, off in ipairs(NEIGHBORS) do
            local ntx = current.tx + off[1]
            local nty = current.ty + off[2]

            if inBounds(ntx, nty, cols, rows) and not isTileBlocked(ntx, nty, walls) then
                local nk = key(ntx, nty)
                local tentativeG = curG + 1

                if tentativeG < (gScore[nk] or math.huge) then
                    cameFrom[nk] = curKey
                    gScore[nk]   = tentativeG
                    fScore[nk]   = tentativeG + heuristic(ntx, nty, goalTx, goalTy)

                    if not openSetMap[nk] then
                        table.insert(openSet, { tx = ntx, ty = nty })
                        openSetMap[nk] = true
                    end
                end
            end
        end
    end

    -- no path
    return nil
end

function Enemy:new(x, y, anims)
    local enemy = {
        x = x,
        y = y,

        -- use hitbox size for collisions
        w = ENEMY_HITBOX_WIDTH,
        h = ENEMY_HITBOX_HEIGHT,

        speed = ENEMY_SPEED, -- will be overwritten by main
        facing = 1,

        -- animation / state
        state = "summon",
        stateTimer = 0,
        animations = anims,
        currentAnim = anims.summon,

        -- combat
        hp = ENEMY_MAX_HP,
        attackCooldown = 0,

        -- pathfinding
        path = nil,          -- array of {tx, ty}
        pathIndex = 1,       -- which node we're moving towards
        pathRecalcTimer = 0, -- countdown
    }
    return setmetatable(enemy, Enemy)
end

function Enemy:setState(state)
    if self.state == state then return end
    self.state = state
    self.stateTimer = 0
    self.currentAnim = self.animations[state]
    if self.currentAnim then
        self.currentAnim:reset()
    end
end

function Enemy:isDead()
    return self.hp <= 0
end

function Enemy:takeHit(damage)
    if self.state == "death" then return end
    self.hp = math.max(0, self.hp - (damage or 1))
    if self.hp <= 0 then
        self:setState("death")
    end
end

function Enemy:update(dt, player, walls)
    self.stateTimer = self.stateTimer + dt
    if self.currentAnim then
        self.currentAnim:update(dt)
    end

    -- tick attack cooldown
    if self.attackCooldown > 0 then
        self.attackCooldown = math.max(0, self.attackCooldown - dt)
    end

    if self.state == "summon" then
        if self.stateTimer > 0.8 then
            self:setState("attacking")
        end
        return
    end

    if self.state == "death" then
        -- just play death animation, respawn handled outside
        return
    end

    -- ========== A* PATHFINDING ==========

    self.pathRecalcTimer = self.pathRecalcTimer - dt
    if self.pathRecalcTimer <= 0 then
        self.pathRecalcTimer = PATH_RECALC_INTERVAL

        local startTx, startTy = worldToTile(self.x, self.y)
        local goalTx,  goalTy  = worldToTile(player.x, player.y)

        local newPath = findPath(startTx, startTy, goalTx, goalTy, walls)
        if newPath and #newPath >= 2 then
            self.path = newPath
            self.pathIndex = 2  -- index 1 is our current tile, so move toward 2
        else
            -- no path found; clear
            self.path = nil
            self.pathIndex = 1
        end
    end

    local moveX, moveY = 0, 0

    if self.path and self.path[self.pathIndex] then
        local node = self.path[self.pathIndex]
        local targetX, targetY = tileToWorldCenter(node.tx, node.ty)

        local dx = targetX - self.x
        local dy = targetY - self.y
        local dist = length(dx, dy)

        if dist < 4 then
            -- reached this node, go to next
            self.pathIndex = self.pathIndex + 1
            if not self.path[self.pathIndex] then
                -- no more nodes; slightly step toward player directly
                local ddx = player.x - self.x
                local ddy = player.y - self.y
                local nx, ny = normalize(ddx, ddy)
                moveX = nx * self.speed * dt
                moveY = ny * self.speed * dt
            end
        else
            local nx, ny = normalize(dx, dy)
            moveX = nx * self.speed * dt
            moveY = ny * self.speed * dt
        end

        -- set facing based on horizontal direction to player (feels better visually)
        local fdx = player.x - self.x
        if fdx ~= 0 then
            self.facing = (fdx < 0) and -1 or 1
        end
    else
        -- fallback: straight chase if no path
        local dx = player.x - self.x
        local dy = player.y - self.y
        local nx, ny = normalize(dx, dy)
        moveX = nx * self.speed * dt
        moveY = ny * self.speed * dt

        if dx ~= 0 then
            self.facing = (dx < 0) and -1 or 1
        end
    end

    -- slide against walls (same style as before: move X then Y, with collision)
    self.x = self.x + moveX
    local box = self:getHitbox()
    for _, wall in ipairs(walls) do
        if rectsOverlap(box, wall) then
            self.x = self.x - moveX   -- undo X movement only
            break
        end
    end

    self.y = self.y + moveY
    box = self:getHitbox()
    for _, wall in ipairs(walls) do
        if rectsOverlap(box, wall) then
            self.y = self.y - moveY   -- undo Y movement only
            break
        end
    end
end

function Enemy:draw()
    if self.currentAnim then
        -- draw using full frame size (100x100)
        self.currentAnim:draw(self.x, self.y, self.facing, SPRITE_SCALE)
    else
        love.graphics.setColor(1, 0, 0)
        love.graphics.rectangle("fill", self.x - 16, self.y - 16, 32, 32)
        love.graphics.setColor(1, 1, 1)
    end

    --[[ -- Debug hitbox:
    -- local hb = self:getHitbox()
    -- love.graphics.setColor(1, 0, 0, 0.4)
    -- love.graphics.rectangle("line", hb.x, hb.y, hb.w, hb.h)
    -- love.graphics.setColor(1, 1, 1)
    --]]
end

function Enemy:getHitbox()
    local ENEMY_FRAME_SIZE = 100
    local bottomY = self.y + ENEMY_FRAME_SIZE / 2 - 10

    return {
        x = self.x - self.w / 2,
        y = bottomY - self.h,
        w = self.w,
        h = self.h
    }
end

return Enemy
