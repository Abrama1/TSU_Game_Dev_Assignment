local Coin = {}
Coin.__index = Coin

local COIN_RADIUS = 10

function Coin:new(x, y)
    local coin = {
        x = x,
        y = y,
        radius = COIN_RADIUS,
        bobTimer = 0
    }
    return setmetatable(coin, Coin)
end

function Coin:update(dt)
    self.bobTimer = self.bobTimer + dt * 3
end

function Coin:draw()
    local offset = math.sin(self.bobTimer) * 2
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.circle("fill", self.x, self.y + offset, self.radius)
    love.graphics.setColor(1, 0.95, 0.5)
    love.graphics.circle("line", self.x, self.y + offset, self.radius)
    love.graphics.setColor(1, 1, 1)
end

return Coin
