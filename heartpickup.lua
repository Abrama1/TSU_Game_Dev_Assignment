local HeartPickup = {}
HeartPickup.__index = HeartPickup

local HEART_RADIUS = 10

function HeartPickup:new(x, y)
    local heart = {
        x = x,
        y = y,
        radius = HEART_RADIUS,
        bobTimer = 0,
    }
    return setmetatable(heart, HeartPickup)
end

function HeartPickup:update(dt)
    self.bobTimer = self.bobTimer + dt * 3
end

local function drawHeartShape(x, y, size)
    -- simple heart made from two circles + a triangle
    local half = size / 2

    -- top circles
    love.graphics.circle("fill", x - half / 1.2, y, half)
    love.graphics.circle("fill", x + half / 1.2, y, half)

    -- bottom triangle
    love.graphics.polygon(
        "fill",
        x - size, y,
        x + size, y,
        x,       y + size
    )
end

function HeartPickup:draw()
    local offset = math.sin(self.bobTimer) * 2

    love.graphics.setColor(0.9, 0.2, 0.3)
    drawHeartShape(self.x, self.y + offset, self.radius * 1.2)

    love.graphics.setColor(1, 1, 1)
end

return HeartPickup
