local Wall = {}
Wall.__index = Wall

function Wall:new(x, y, w, h)
    local wall = {
        x = x,
        y = y,
        w = w,
        h = h
    }
    return setmetatable(wall, Wall)
end

function Wall:draw()
    love.graphics.setColor(0.3, 0.3, 0.35)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
    love.graphics.setColor(0.15, 0.15, 0.18)
    love.graphics.rectangle("line", self.x, self.y, self.w, self.h)
    love.graphics.setColor(1, 1, 1)
end

return Wall
