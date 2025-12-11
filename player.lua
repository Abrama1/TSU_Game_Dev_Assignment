local Player = {}
Player.__index = Player

-- Visual frame size
local FRAME_SIZE     = 96
local SPRITE_SCALE   = 1

-- Collision hitbox size
local HITBOX_WIDTH   = 48
local HITBOX_HEIGHT  = 36

local PLAYER_SPEED    = 160
local ATTACK_DURATION = 0.45
local HURT_DURATION   = 0.35
local PLAYER_MAX_HP   = 3

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

function Player:new(x, y, anims)
    local player = {
        x = x,
        y = y,

        w = HITBOX_WIDTH,
        h = HITBOX_HEIGHT,

        speed = PLAYER_SPEED,
        facing = 1,
        state = "idle",
        attackTimer = 0,
        hurtTimer = 0,
        hp = PLAYER_MAX_HP,
        animations = anims,
        currentAnim = anims.idle
    }
    return setmetatable(player, Player)
end

function Player:setState(state)
    if self.state == state then return end
    self.state = state
    self.currentAnim = self.animations[state]
    if self.currentAnim then
        self.currentAnim:reset()
    end
end

function Player:startAttack()
    if self.state == "hurt" then return end
    self.attackTimer = ATTACK_DURATION
    self:setState("attack")
end

function Player:takeHit()
    if self.state == "hurt" then return end
    self.hp = math.max(0, self.hp - 1)
    self.hurtTimer = HURT_DURATION
    self.attackTimer = 0
    self:setState("hurt")
end

function Player:isDead()
    return self.hp <= 0
end

-- is the player currently in the attack state?
function Player:isAttacking()
    return self.state == "attack"
end

-- simple attack hitbox extending from the player's hitbox in facing direction
function Player:getAttackHitbox()
    local hb = self:getHitbox()
    local range = 30  -- sword reach

    if self.facing == 1 then
        -- attack to the right
        return {
            x = hb.x + hb.w,
            y = hb.y,
            w = range,
            h = hb.h
        }
    else
        -- attack to the left
        return {
            x = hb.x - range,
            y = hb.y,
            w = range,
            h = hb.h
        }
    end
end

function Player:update(dt, walls)
    local moveX, moveY = 0, 0

    if love.keyboard.isDown("a", "left") then
        moveX = moveX - 1
    end
    if love.keyboard.isDown("d", "right") then
        moveX = moveX + 1
    end
    if love.keyboard.isDown("w", "up") then
        moveY = moveY - 1
    end
    if love.keyboard.isDown("s", "down") then
        moveY = moveY + 1
    end

    -- timers
    if self.attackTimer > 0 then
        self.attackTimer = self.attackTimer - dt
        if self.attackTimer <= 0 and self.state == "attack" then
            self.attackTimer = 0
            self:setState("idle")
        end
    end

    if self.hurtTimer > 0 then
        self.hurtTimer = self.hurtTimer - dt
        if self.hurtTimer <= 0 and self.state == "hurt" then
            self.hurtTimer = 0
            self:setState("idle")
        end
    end

    local canMove = (self.state ~= "attack" and self.state ~= "hurt")
    if canMove then
        local nx, ny = normalize(moveX, moveY)

        if nx ~= 0 or ny ~= 0 then
            local moveDX = nx * self.speed * dt
            local moveDY = ny * self.speed * dt

            -- move X axis first (for sliding along walls)
            self.x = self.x + moveDX
            local box = self:getHitbox()
            for _, wall in ipairs(walls) do
                if rectsOverlap(box, wall) then
                    self.x = self.x - moveDX  -- undo X movement only
                    break
                end
            end

            -- then move Y axis
            self.y = self.y + moveDY
            box = self:getHitbox()
            for _, wall in ipairs(walls) do
                if rectsOverlap(box, wall) then
                    self.y = self.y - moveDY  -- undo Y movement only
                    break
                end
            end

            -- facing based on horizontal movement
            if nx < 0 then
                self.facing = -1
            elseif nx > 0 then
                self.facing = 1
            end

            if self.state ~= "attack" and self.state ~= "hurt" then
                self:setState("run")
            end
        else
            if self.state ~= "attack" and self.state ~= "hurt" then
                self:setState("idle")
            end
        end
    end

    if self.currentAnim then
        self.currentAnim:update(dt)
    end
end

function Player:draw()
    if self.currentAnim then
        -- draw sprite centered at (x, y), using 96x96 frames (FRAME_SIZE)
        self.currentAnim:draw(self.x, self.y, self.facing, SPRITE_SCALE)
    else
        love.graphics.setColor(0, 1, 0)
        love.graphics.rectangle("fill", self.x - 16, self.y - 16, 32, 32)
        love.graphics.setColor(1, 1, 1)
    end

    --[[ -- Debug: visualize hitbox
    love.graphics.setColor(0, 1, 0, 0.4)
    local hb = self:getHitbox()
    love.graphics.rectangle("line", hb.x, hb.y, hb.w, hb.h)
    love.graphics.setColor(1, 1, 1)
    --]]
end

function Player:getHitbox()
    -- Anchor hitbox to the feet
    local FRAME_SIZE = 96
    local bottomY = self.y + FRAME_SIZE / 2 - 12  -- slight offset to align with feet

    return {
        x = self.x - self.w / 2,
        y = bottomY - self.h,
        w = self.w,
        h = self.h
    }
end

function Player:resetPosition(x, y)
    self.x = x
    self.y = y
end

function Player:getMaxHp()
    return PLAYER_MAX_HP
end

return Player
