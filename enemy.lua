local Enemy = {}
Enemy.__index = Enemy

local ENEMY_FRAME_SIZE   = 100  -- sprite frame size
local SPRITE_SCALE       = 1

-- collision hitbox
local ENEMY_HITBOX_WIDTH  = 50
local ENEMY_HITBOX_HEIGHT = 60

local ENEMY_SPEED           = 70      -- base speed
local ENEMY_MAX_HP          = 3
local ENEMY_ATTACK_COOLDOWN = 0.8     -- seconds between hits

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

function Enemy:new(x, y, anims)
    local enemy = {
        x = x,
        y = y,

        -- use hitbox size for collisions
        w = ENEMY_HITBOX_WIDTH,
        h = ENEMY_HITBOX_HEIGHT,

        speed = ENEMY_SPEED,
        facing = 1,
        state = "summon",
        stateTimer = 0,
        animations = anims,
        currentAnim = anims.summon,

        hp = ENEMY_MAX_HP,
        attackCooldown = 0
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
        -- just play death animation, respawn handled in main.lua
        return
    end

    -- chase player
    local dx = player.x - self.x
    local dy = player.y - self.y
    local nx, ny = normalize(dx, dy)

    local moveX = nx * self.speed * dt
    local moveY = ny * self.speed * dt

    -- move X axis first (for sliding along walls)
    self.x = self.x + moveX
    local box = self:getHitbox()
    for _, wall in ipairs(walls) do
        if rectsOverlap(box, wall) then
            self.x = self.x - moveX   -- undo X movement only
            break
        end
    end

    -- then move Y axis
    self.y = self.y + moveY
    box = self:getHitbox()
    for _, wall in ipairs(walls) do
        if rectsOverlap(box, wall) then
            self.y = self.y - moveY   -- undo Y movement only
            break
        end
    end

    self.facing = (dx < 0) and -1 or 1
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
    local hb = self:getHitbox()
    love.graphics.setColor(1, 0, 0, 0.4)
    love.graphics.rectangle("line", hb.x, hb.y, hb.w, hb.h)
    love.graphics.setColor(1, 1, 1)
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
