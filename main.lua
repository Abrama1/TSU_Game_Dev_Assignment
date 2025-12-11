local Player    = require("player")
local Enemy     = require("enemy")
local Coin      = require("coin")
local Wall      = require("wall")
local Animation = require("animation")
local Button    = require("button")

local WINDOW_WIDTH  = 800
local WINDOW_HEIGHT = 600

local TILE_SIZE           = 32   -- just for background grid
local PLAYER_FRAME_SIZE   = 96
local ENEMY_FRAME_SIZE    = 100

local ENEMY_RESPAWN_DELAY = 2.0  -- seconds after death before enemy respawns

-- game state
local gameState = "menu"  -- "menu" | "game"
local currentDifficulty = nil

-- difficulties config
local difficulties = {
    easy = {
        label = "Easy",
        baseEnemySpeed = 60,
        speedGainPerCoin = 1.015,
    },
    normal = {
        label = "Normal",
        baseEnemySpeed = 70,
        speedGainPerCoin = 1.02,
    },
    hard = {
        label = "Hard",
        baseEnemySpeed = 80,
        speedGainPerCoin = 1.03,
    }
}

-- per-difficulty best scores (in memory for now; persistence later)
local bestScores = {
    easy   = 0,
    normal = 0,
    hard   = 0,
}

local player
local enemy
local coin
local walls = {}
local score = 0
local gameOver = false

local playerAnims = {}
local enemyAnims  = {}
local enemyRespawnTimer = 0
local enemySpeedMultiplier = 1.0  -- increases per coin during a run

-- menu buttons
local menuButtons = {}

-- ==========================
-- Utility
-- ==========================
local function rectsOverlap(a, b)
    return a.x < b.x + b.w and
           a.x + a.w > b.x and
           a.y < b.y + b.h and
           a.y + a.h > b.y
end

local function circleRectOverlap(cx, cy, radius, rect)
    local closestX = math.max(rect.x, math.min(cx, rect.x + rect.w))
    local closestY = math.max(rect.y, math.min(cy, rect.y + rect.h))
    local dx = cx - closestX
    local dy = cy - closestY
    return dx * dx + dy * dy <= radius * radius
end

local function randomInRange(minv, maxv)
    return minv + math.random() * (maxv - minv)
end

-- middle box collision
local function coinIsInsideMiddleBox(x, y)
    return x > 360 and x < 360 + 80 and
           y > 260 and y < 260 + 80
end

local function spawnCoin()
    local x, y
    repeat
        x = randomInRange(180, WINDOW_WIDTH - 180)
        y = randomInRange(140, WINDOW_HEIGHT - 140)
    until not coinIsInsideMiddleBox(x, y)

    return Coin:new(x, y)
end

local function spawnEnemy()
    local cfg = difficulties[currentDifficulty]
    local e = Enemy:new(WINDOW_WIDTH * 0.75, WINDOW_HEIGHT * 0.5, enemyAnims)
    e.speed = cfg.baseEnemySpeed * enemySpeedMultiplier
    return e
end

local function startGame(difficultyKey)
    currentDifficulty = difficultyKey
    local cfg = difficulties[currentDifficulty]

    score = 0
    gameOver = false
    enemySpeedMultiplier = 1.0
    enemyRespawnTimer = 0

    player = Player:new(WINDOW_WIDTH * 0.25, WINDOW_HEIGHT * 0.5, playerAnims)
    enemy  = spawnEnemy()

    walls = {
        Wall:new(150, 100, 500, 20),
        Wall:new(150, 480, 500, 20),
        Wall:new(150, 100, 20, 400),
        Wall:new(630, 100, 20, 400),
        Wall:new(360, 260, 80, 80)  -- middle box
    }

    coin = spawnCoin()

    gameState = "game"
end

-- ==========================
-- LOVE callbacks
-- ==========================
function love.load()
    love.window.setMode(WINDOW_WIDTH, WINDOW_HEIGHT)
    love.window.setTitle("Sprite Sheet Game")
    love.graphics.setDefaultFilter("nearest", "nearest")
    math.randomseed(os.time())

    -- PLAYER SPRITES (1 row each, 96x96 frames)
    local idleImg   = love.graphics.newImage("assets/idle.png")
    local runImg    = love.graphics.newImage("assets/run.png")
    local attackImg = love.graphics.newImage("assets/attack.png")
    local hurtImg   = love.graphics.newImage("assets/hurt.png")

    playerAnims.idle   = Animation:new(idleImg,   PLAYER_FRAME_SIZE, PLAYER_FRAME_SIZE, 10, 10, 8,  true)
    playerAnims.run    = Animation:new(runImg,    PLAYER_FRAME_SIZE, PLAYER_FRAME_SIZE, 16, 16, 14, true)
    playerAnims.attack = Animation:new(attackImg, PLAYER_FRAME_SIZE, PLAYER_FRAME_SIZE, 7,  7,  16, false)
    playerAnims.hurt   = Animation:new(hurtImg,   PLAYER_FRAME_SIZE, PLAYER_FRAME_SIZE, 4,  4,  10, false)

    -- ENEMY SPRITES (100x100 frames)
    local enemyAttackImg = love.graphics.newImage("assets/attacking.png")
    local enemyDeathImg  = love.graphics.newImage("assets/death.png")
    local enemySummonImg = love.graphics.newImage("assets/summon.png")

    -- attacking.png: 13 frames, 3 rows (6,6,1) framesPerRow = 6
    enemyAnims.attacking = Animation:new(
        enemyAttackImg,
        ENEMY_FRAME_SIZE, ENEMY_FRAME_SIZE,
        13,
        6,
        10,
        true
    )

    -- death.png: 18 frames (10 in row1, 8 in row2), 100x100 each
    enemyAnims.death = Animation:new(
        enemyDeathImg,
        ENEMY_FRAME_SIZE, ENEMY_FRAME_SIZE,
        18,
        10,
        9,
        false
    )

    -- summon.png: 5 frames (4 row1, 1 row2) framesPerRow = 4
    enemyAnims.summon = Animation:new(
        enemySummonImg,
        ENEMY_FRAME_SIZE, ENEMY_FRAME_SIZE,
        5,
        4,
        8,
        false
    )

    -- create menu buttons
    local btnW, btnH = 200, 50
    local startY = WINDOW_HEIGHT / 2 - 80
    local gap = 60
    local centerX = WINDOW_WIDTH / 2 - btnW / 2

    menuButtons = {
        require("button"):new(centerX, startY, btnW, btnH, "Easy", function()
            startGame("easy")
        end),
        require("button"):new(centerX, startY + gap, btnW, btnH, "Normal", function()
            startGame("normal")
        end),
        require("button"):new(centerX, startY + gap * 2, btnW, btnH, "Hard", function()
            startGame("hard")
        end),
    }
end

function love.update(dt)
    if love.keyboard.isDown("escape") then
        love.event.quit()
    end

    if gameState ~= "game" then
        return
    end

    if gameOver then return end

    player:update(dt, walls)
    enemy:update(dt, player, walls)
    coin:update(dt)

    -- Enemy respawn logic (keeping speed multiplier)
    if enemy:isDead() then
        enemyRespawnTimer = enemyRespawnTimer + dt
        if enemyRespawnTimer >= ENEMY_RESPAWN_DELAY then
            enemyRespawnTimer = 0
            enemy = spawnEnemy()
        end
    else
        enemyRespawnTimer = 0
    end

    -- player vs enemy
    local pBox = player:getHitbox()
    local eBox = enemy:getHitbox()

    -- 1) Player hitting enemy (only while attacking)
    if player:isAttacking() and not enemy:isDead() then
        local atkBox = player:getAttackHitbox()
        if rectsOverlap(atkBox, eBox) then
            enemy:takeHit(1)
        end
    end

    -- 2) Enemy hitting player (only while attacking, with cooldown)
    if enemy.state == "attacking"
        and enemy.attackCooldown <= 0
        and rectsOverlap(pBox, eBox)
        and not player:isDead()
        and not enemy:isDead()
    then
        enemy.attackCooldown = 0.8
        player:takeHit()
        if player:isDead() then
            -- update best score when the run ends (per difficulty)
            if score > bestScores[currentDifficulty] then
                bestScores[currentDifficulty] = score
            end
            gameOver = true
            enemy:setState("death")
        end
    end

    -- player vs coin
    if circleRectOverlap(coin.x, coin.y, coin.radius, pBox) then
        score = score + 1

        -- enemy moves faster per coin during this run (difficulty-based)
        local cfg = difficulties[currentDifficulty]
        enemySpeedMultiplier = enemySpeedMultiplier * cfg.speedGainPerCoin
        if not enemy:isDead() then
            enemy.speed = cfg.baseEnemySpeed * enemySpeedMultiplier
        end

        coin = spawnCoin()
    end
end

function love.keypressed(key)
    if gameState == "game" then
        if key == "space" and not gameOver then
            player:startAttack()
        end

        if key == "return" and gameOver then
            -- reset current run, keep bestScores
            startGame(currentDifficulty)
        end
    end
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    if gameState ~= "menu" then return end

    for _, btn in ipairs(menuButtons) do
        if btn:containsPoint(x, y) then
            btn:click()
            break
        end
    end
end

function love.draw()
    love.graphics.clear(0.08, 0.09, 0.12)

    if gameState == "menu" then
        -- main menu
        local title = "Reaper Game"
        local font = love.graphics.getFont()
        local tw = font:getWidth(title)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(title, WINDOW_WIDTH / 2 - tw / 2, 120)

        -- show best scores for each difficulty
        local infoY = 160
        love.graphics.print(
            string.format("Easy: %d   Normal: %d   Hard: %d",
                bestScores.easy, bestScores.normal, bestScores.hard),
            WINDOW_WIDTH / 2 - 90,
            infoY
        )

        for _, btn in ipairs(menuButtons) do
            btn:draw()
        end

        love.graphics.setColor(1, 1, 1)
        return
    end

    -- === GAMEPLAY DRAW ===

    -- simple grid background
    love.graphics.setColor(0.12, 0.15, 0.19)
    for x = 0, WINDOW_WIDTH, TILE_SIZE * 2 do
        for y = 0, WINDOW_HEIGHT, TILE_SIZE * 2 do
            love.graphics.rectangle("line", x, y, TILE_SIZE * 2, TILE_SIZE * 2)
        end
    end
    love.graphics.setColor(1, 1, 1)

    -- arena border
    love.graphics.setColor(0.2, 0.25, 0.3)
    love.graphics.rectangle("line", 150, 100, 500, 400)
    love.graphics.setColor(1, 1, 1)

    -- walls
    for _, wall in ipairs(walls) do
        wall:draw()
    end

    coin:draw()
    enemy:draw()
    player:draw()

    -- UI bar
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, 40)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", 0, 0, WINDOW_WIDTH, 40)

    -- score + best score (for current difficulty)
    love.graphics.print("Score: " .. tostring(score), 10, 10)

    local bestForDiff = currentDifficulty and bestScores[currentDifficulty] or 0
    love.graphics.print("Best: "  .. tostring(bestForDiff), 120, 10)

    -- difficulty label
    if currentDifficulty then
        local label = "Difficulty: " .. difficulties[currentDifficulty].label
        love.graphics.print(label, 220, 10)
    end

    -- HP hearts
    local hpText = "HP: "
    local hpTextX = 400
    love.graphics.print(hpText, hpTextX, 10)
    local offsetX = hpTextX + love.graphics.getFont():getWidth(hpText) + 10
    for i = 1, player:getMaxHp() do
        if i <= player.hp then
            love.graphics.setColor(0.9, 0.2, 0.3)
        else
            love.graphics.setColor(0.3, 0.3, 0.3)
        end
        love.graphics.circle("fill", offsetX + (i - 1) * 20, 20, 7)
    end
    love.graphics.setColor(1, 1, 1)

    love.graphics.print(
        "Move: WASD / Arrows   Attack: Space   Restart: Enter (after death)",
        350, 10
    )

    if gameOver then
        local text = "You Died! Score: " .. tostring(score)
        if currentDifficulty then
            text = text .. "  Best (" .. difficulties[currentDifficulty].label .. "): "
                .. tostring(bestScores[currentDifficulty])
        end
        text = text .. "  -  Press Enter to Restart"

        local font = love.graphics.getFont()
        local tw = font:getWidth(text)
        local th = font:getHeight()

        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill",
            WINDOW_WIDTH / 2 - tw / 2 - 10,
            WINDOW_HEIGHT / 2 - th / 2 - 10,
            tw + 20, th + 20
        )
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(text, WINDOW_WIDTH / 2 - tw / 2, WINDOW_HEIGHT / 2 - th / 2)
    end
end
