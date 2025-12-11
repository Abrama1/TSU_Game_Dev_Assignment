-- hiteffect.lua
local HitEffect = {}
HitEffect.__index = HitEffect

local function randRange(minv, maxv)
    return minv + math.random() * (maxv - minv)
end

function HitEffect:new(x, y, kind)
    local effect = {
        x = x,
        y = y,
        vx = randRange(-60, 60),
        vy = randRange(-80, -20),
        life = 0,
        maxLife = 0.35,
        kind = kind or "hit",
    }

    if effect.kind == "death" then
        effect.maxLife = 0.6
    elseif effect.kind == "coin" or effect.kind == "heart" then
        effect.maxLife = 0.4
    end

    return setmetatable(effect, HitEffect)
end

function HitEffect:update(dt)
    self.life = self.life + dt
    self.x = self.x + self.vx * dt
    self.y = self.y + self.vy * dt
    -- simple gravity
    self.vy = self.vy + 200 * dt
end

function HitEffect:isDead()
    return self.life >= self.maxLife
end

function HitEffect:draw()
    local t = self.life / self.maxLife
    local alpha = 1 - t
    local size = 4 * (1 - t * 0.5)

    if self.kind == "hit" then
        love.graphics.setColor(1, 0.9, 0.3, alpha)
    elseif self.kind == "death" then
        love.graphics.setColor(0.4, 0.1, 0.5, alpha)
    elseif self.kind == "coin" then
        love.graphics.setColor(1, 0.9, 0.2, alpha)
    elseif self.kind == "heart" then
        love.graphics.setColor(0.9, 0.2, 0.3, alpha)
    else
        love.graphics.setColor(1, 1, 1, alpha)
    end

    love.graphics.circle("fill", self.x, self.y, size)
    love.graphics.setColor(1, 1, 1, 1)
end

return HitEffect
