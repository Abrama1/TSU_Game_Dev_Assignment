local Animation = {}
Animation.__index = Animation

-- image: sprite sheet
-- frameWidth, frameHeight: size of each frame (here 96x96 canvas)
-- frameCount: total frames in the animation
-- framesPerRow: how many frames are in each row of the sheet
-- fps: playback speed
-- loop: whether to loop or stop at last frame
function Animation:new(image, frameWidth, frameHeight, frameCount, framesPerRow, fps, loop)
    local anim = {
        image        = image,
        quads        = {},
        frameWidth   = frameWidth,
        frameHeight  = frameHeight,
        frameCount   = frameCount,
        framesPerRow = framesPerRow,
        fps          = fps or 10,
        loop         = loop ~= false,
        currentFrame = 1,
        timer        = 0
    }

    local imgW, imgH = image:getWidth(), image:getHeight()
    local frameIndex = 1
    local rows = math.ceil(frameCount / framesPerRow)

    for row = 0, rows - 1 do
        for col = 0, framesPerRow - 1 do
            if frameIndex > frameCount then
                break
            end

            local quad = love.graphics.newQuad(
                col * frameWidth,
                row * frameHeight,
                frameWidth,
                frameHeight,
                imgW,
                imgH
            )

            anim.quads[frameIndex] = quad
            frameIndex = frameIndex + 1
        end
    end

    return setmetatable(anim, Animation)
end

function Animation:update(dt)
    local frameDuration = 1 / self.fps
    self.timer = self.timer + dt

    while self.timer >= frameDuration do
        self.timer = self.timer - frameDuration
        self.currentFrame = self.currentFrame + 1

        if self.currentFrame > self.frameCount then
            if self.loop then
                self.currentFrame = 1
            else
                self.currentFrame = self.frameCount
            end
        end
    end
end

function Animation:reset()
    self.currentFrame = 1
    self.timer = 0
end

function Animation:draw(x, y, facing, scale)
    local quad = self.quads[self.currentFrame]
    if not quad then return end

    scale = scale or 1
    local sx = scale * (facing or 1)
    local sy = scale

    local ox = self.frameWidth / 2
    local oy = self.frameHeight / 2

    love.graphics.draw(
        self.image,
        quad,
        x, y,
        0,
        sx, sy,
        ox, oy
    )
end

return Animation
