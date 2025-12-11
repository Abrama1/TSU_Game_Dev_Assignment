local Button = {}
Button.__index = Button

function Button:new(x, y, w, h, label, onClick)
    local btn = {
        x = x,
        y = y,
        w = w,
        h = h,
        label = label or "",
        onClick = onClick,
    }
    return setmetatable(btn, Button)
end

function Button:containsPoint(px, py)
    return px >= self.x and px <= self.x + self.w and
           py >= self.y and py <= self.y + self.h
end

function Button:draw()
    local mx, my = love.mouse.getPosition()
    local hovered = self:containsPoint(mx, my)

    if hovered then
        love.graphics.setColor(0.2, 0.6, 0.9)
    else
        love.graphics.setColor(0.15, 0.15, 0.2)
    end
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 6, 6)

    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", self.x, self.y, self.w, self.h, 6, 6)

    local font = love.graphics.getFont()
    local tw = font:getWidth(self.label)
    local th = font:getHeight()
    love.graphics.print(
        self.label,
        self.x + (self.w - tw) / 2,
        self.y + (self.h - th) / 2
    )

    love.graphics.setColor(1, 1, 1)
end

function Button:click()
    if self.onClick then
        self.onClick()
    end
end

return Button
