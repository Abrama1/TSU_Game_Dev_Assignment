local Player      = require("player")
local Enemy       = require("enemy")
local Coin        = require("coin")
local Wall        = require("wall")
local Animation   = require("animation")
local Button      = require("button")
local HeartPickup = require("heartpickup")
local HitEffect   = require("hiteffect")

local WINDOW_WIDTH  = 800
local WINDOW_HEIGHT = 600

local TILE_SIZE           = 32
local PLAYER_FRAME_SIZE   = 96
local ENEMY_FRAME_SIZE    = 100

local ENEMY_RESPAWN_DELAY = 2.0
local HEART_SPAWN_CHANCE  = 0.25
local ENEMY_SWING_INTERVAL = 0.6
local DANGER_MAX_MULT      = 2.0
local SECOND_ENEMY_SCORE_THRESHOLD = 30

local debugPath = false

local gameState = "menu"
local currentDifficulty = nil

local difficulties = {
    easy = { label = "Easy",   baseEnemySpeed = 60, speedGainPerCoin = 1.015 },
    normal = { label = "Normal", baseEnemySpeed = 70, speedGainPerCoin = 1.02 },
    hard = { label = "Hard",   baseEnemySpeed = 80, speedGainPerCoin = 1.03 },
}

local bestScores = { easy = 0, normal = 0, hard = 0 }

local player
local enemy
local enemy2
local enemy2Spawned = false

local coin
local walls = {}
local hearts = {}
local effects = {}
local score = 0
local gameOver = false

local playerAnims = {}
local enemyRespawnTimer = 0
local enemySpeedMultiplier = 1.0

local menuButtons = {}
local sounds = {}
local enemySwingTimer = 0

-- ✅ enemy images loaded once
local enemyImgs = { attack = nil, death = nil, summon = nil }

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

local function isInsideMiddleBox(x, y)
    return x > 360 and x < 360 + 80 and
           y > 260 and y < 260 + 80
end

local function spawnCoin()
    local x, y
    repeat
        x = randomInRange(180, WINDOW_WIDTH - 180)
        y = randomInRange(140, WINDOW_HEIGHT - 140)
    until not isInsideMiddleBox(x, y)

    return Coin:new(x, y)
end

local function spawnHeart()
    local x, y
    repeat
        x = randomInRange(180, WINDOW_WIDTH - 180)
        y = randomInRange(140, WINDOW_HEIGHT - 140)
    until not isInsideMiddleBox(x, y)

    return HeartPickup:new(x, y)
end

local function addEffectBurst(x, y, kind, count)
    count = count or 6
    for _ = 1, count do
        table.insert(effects, HitEffect:new(x, y, kind))
    end
end

local function tileToWorldCenter(tx, ty)
    local x = (tx - 0.5) * TILE_SIZE
    local y = (ty - 0.5) * TILE_SIZE
    return x, y
end

local function drawEnemyPath(e, r, g, b)
    if not e or not e.path or #e.path == 0 then
        return
    end

    r = r or 0
    g = g or 1
    b = b or 0

    love.graphics.setColor(r, g, b, 0.5)

    for i, node in ipairs(e.path) do
        local cx, cy = tileToWorldCenter(node.tx, node.ty)

        love.graphics.rectangle("line",
            cx - TILE_SIZE / 2,
            cy - TILE_SIZE / 2,
            TILE_SIZE,
            TILE_SIZE
        )

        if i < #e.path then
            local nx, ny = tileToWorldCenter(e.path[i + 1].tx, e.path[i + 1].ty)
            love.graphics.line(cx, cy, nx, ny)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- ✅ IMPORTANT: create fresh Animation objects per enemy (no shared state!)
local function makeEnemyAnims()
    return {
        attacking = Animation:new(enemyImgs.attack, ENEMY_FRAME_SIZE, ENEMY_FRAME_SIZE, 13, 6, 10, true),
        death     = Animation:new(enemyImgs.death,  ENEMY_FRAME_SIZE, ENEMY_FRAME_SIZE, 18, 10, 9, false),
        summon    = Animation:new(enemyImgs.summon, ENEMY_FRAME_SIZE, ENEMY_FRAME_SIZE, 5,  4,  8, false),
    }
end

local function spawnEnemy(x, y)
    local cfg = difficulties[currentDifficulty]
    local e = Enemy:new(x or WINDOW_WIDTH * 0.75, y or WINDOW_HEIGHT * 0.5, makeEnemyAnims())
    e.speed = cfg.baseEnemySpeed * enemySpeedMultiplier
    return e
end

local function startGame(difficultyKey)
    currentDifficulty = difficultyKey

    score = 0
    gameOver = false
    enemySpeedMultiplier = 1.0
    enemyRespawnTimer = 0
    enemySwingTimer = 0

    player = Player:new(WINDOW_WIDTH * 0.25, WINDOW_HEIGHT * 0.5, playerAnims)

    enemy  = spawnEnemy(WINDOW_WIDTH * 0.75, WINDOW_HEIGHT * 0.5)
    enemy2 = nil
    enemy2Spawned = false

    walls = {
        Wall:new(150, 100, 500, 20),
        Wall:new(150, 480, 500, 20),
        Wall:new(150, 100, 20, 400),
        Wall:new(630, 100, 20, 400),
        Wall:new(360, 260, 80, 80)
    }

    coin = spawnCoin()
    hearts = {}
    effects = {}

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

    local idleImg   = love.graphics.newImage("assets/idle.png")
    local runImg    = love.graphics.newImage("assets/run.png")
    local attackImg = love.graphics.newImage("assets/attack.png")
    local hurtImg   = love.graphics.newImage("assets/hurt.png")

    playerAnims.idle   = Animation:new(idleImg,   PLAYER_FRAME_SIZE, PLAYER_FRAME_SIZE, 10, 10, 8,  true)
    playerAnims.run    = Animation:new(runImg,    PLAYER_FRAME_SIZE, PLAYER_FRAME_SIZE, 16, 16, 14, true)
    playerAnims.attack = Animation:new(attackImg, PLAYER_FRAME_SIZE, PLAYER_FRAME_SIZE, 7,  7,  16, false)
    playerAnims.hurt   = Animation:new(hurtImg,   PLAYER_FRAME_SIZE, PLAYER_FRAME_SIZE, 4,  4,  10, false)

    -- ✅ load enemy images ONCE
    enemyImgs.attack = love.graphics.newImage("assets/attacking.png")
    enemyImgs.death  = love.graphics.newImage("assets/death.png")
    enemyImgs.summon = love.graphics.newImage("assets/summon.png")

    local btnW, btnH = 200, 50
    local startY = WINDOW_HEIGHT / 2 - 80
    local gap = 60
    local centerX = WINDOW_WIDTH / 2 - btnW / 2

    menuButtons = {
        Button:new(centerX, startY,         btnW, btnH, "Easy",   function() startGame("easy")   end),
        Button:new(centerX, startY + gap,   btnW, btnH, "Normal", function() startGame("normal") end),
        Button:new(centerX, startY + gap*2, btnW, btnH, "Hard",   function() startGame("hard")   end),
    }

    sounds.swordSwing   = love.audio.newSource("assets/sword_swing.wav", "static")
    sounds.enemySwing   = love.audio.newSource("assets/enemy_swing.wav", "static")
    sounds.coinPickup   = love.audio.newSource("assets/coin_pickup.wav", "static")
    sounds.heartPickup  = love.audio.newSource("assets/heart_pickup.wav", "static")
end

function love.update(dt)
    if love.keyboard.isDown("escape") then
        love.event.quit()
    end

    if gameState ~= "game" or gameOver then
        if sounds.enemySwing and sounds.enemySwing:isPlaying() then
            sounds.enemySwing:stop()
        end
        enemySwingTimer = 0
    end

    if gameState ~= "game" then return end
    if gameOver then return end

    player:update(dt, walls)
    enemy:update(dt, player, walls)
    if enemy2 then enemy2:update(dt, player, walls) end

    coin:update(dt)
    for _, heart in ipairs(hearts) do heart:update(dt) end
    for _, eff in ipairs(effects) do eff:update(dt) end

    local i = 1
    while i <= #effects do
        if effects[i]:isDead() then
            table.remove(effects, i)
        else
            i = i + 1
        end
    end

    if enemy:isDead() then
        enemyRespawnTimer = enemyRespawnTimer + dt
        if enemyRespawnTimer >= ENEMY_RESPAWN_DELAY then
            enemyRespawnTimer = 0
            enemy = spawnEnemy(WINDOW_WIDTH * 0.75, WINDOW_HEIGHT * 0.5)
        end
    else
        enemyRespawnTimer = 0
    end

    local pBox = player:getHitbox()
    local eBox1 = enemy:getHitbox()
    local eBox2 = enemy2 and enemy2:getHitbox() or nil

    if player:isAttacking() and not enemy:isDead() then
        local atkBox = player:getAttackHitbox()
        if rectsOverlap(atkBox, eBox1) then
            local enemyWasDead = enemy:isDead()
            enemy:takeHit(1)

            local hitX = eBox1.x + eBox1.w / 2
            local hitY = eBox1.y + eBox1.h / 2
            if enemy:isDead() and not enemyWasDead then
                addEffectBurst(hitX, hitY, "death", 10)
            else
                addEffectBurst(hitX, hitY, "hit", 6)
            end
        end
    end

    if enemy2 and eBox2 and player:isAttacking() and not enemy2:isDead() then
        local atkBox = player:getAttackHitbox()
        if rectsOverlap(atkBox, eBox2) then
            local enemy2WasDead = enemy2:isDead()
            enemy2:takeHit(1)

            local hitX = eBox2.x + eBox2.w / 2
            local hitY = eBox2.y + eBox2.h / 2
            if enemy2:isDead() and not enemy2WasDead then
                addEffectBurst(hitX, hitY, "death", 10)
            else
                addEffectBurst(hitX, hitY, "hit", 6)
            end
        end
    end

    if enemy.state == "attacking"
        and enemy.attackCooldown <= 0
        and rectsOverlap(pBox, eBox1)
        and not player:isDead()
        and not enemy:isDead()
    then
        enemy.attackCooldown = 0.8
        player:takeHit()
    end

    if enemy2 and eBox2
        and enemy2.state == "attacking"
        and enemy2.attackCooldown <= 0
        and rectsOverlap(pBox, eBox2)
        and not player:isDead()
        and not enemy2:isDead()
    then
        enemy2.attackCooldown = 0.8
        player:takeHit()
    end

    if player:isDead() then
        if score > bestScores[currentDifficulty] then
            bestScores[currentDifficulty] = score
        end
        gameOver = true
        enemy:setState("death")
        if enemy2 and not enemy2:isDead() then
            enemy2:setState("death")
        end
        return
    end

    if circleRectOverlap(coin.x, coin.y, coin.radius, pBox) then
        score = score + 1

        if sounds.coinPickup then
            sounds.coinPickup:stop()
            sounds.coinPickup:play()
        end

        addEffectBurst(coin.x, coin.y, "coin", 8)

        local cfg = difficulties[currentDifficulty]
        enemySpeedMultiplier = enemySpeedMultiplier * cfg.speedGainPerCoin

        if not enemy:isDead() then
            enemy.speed = cfg.baseEnemySpeed * enemySpeedMultiplier
        end
        if enemy2 and not enemy2:isDead() then
            enemy2.speed = cfg.baseEnemySpeed * enemySpeedMultiplier
        end

        if player.hp < player:getMaxHp() and #hearts == 0 then
            if math.random() < HEART_SPAWN_CHANCE then
                table.insert(hearts, spawnHeart())
            end
        end

        coin = spawnCoin()

        if (not enemy2Spawned) and score >= SECOND_ENEMY_SCORE_THRESHOLD then
            enemy2Spawned = true
            enemy2 = spawnEnemy(WINDOW_WIDTH * 0.75, WINDOW_HEIGHT * 0.25)
        end
    end

    if player.hp < player:getMaxHp() and #hearts > 0 then
        local maxHp = player:getMaxHp()
        local j = 1
        while j <= #hearts do
            local heart = hearts[j]
            if circleRectOverlap(heart.x, heart.y, heart.radius, pBox) then
                player.hp = math.min(maxHp, player.hp + 1)

                if sounds.heartPickup then
                    sounds.heartPickup:stop()
                    sounds.heartPickup:play()
                elseif sounds.coinPickup then
                    sounds.coinPickup:stop()
                    sounds.coinPickup:play()
                end

                addEffectBurst(heart.x, heart.y, "heart", 8)
                table.remove(hearts, j)
            else
                j = j + 1
            end
        end
    end

    if sounds.enemySwing then
        if enemy:isDead() or enemy.state ~= "attacking" then
            if sounds.enemySwing:isPlaying() then
                sounds.enemySwing:stop()
            end
            enemySwingTimer = 0
        else
            enemySwingTimer = enemySwingTimer - dt
            if enemySwingTimer <= 0 then
                sounds.enemySwing:stop()
                sounds.enemySwing:play()
                enemySwingTimer = ENEMY_SWING_INTERVAL
            end
        end
    end
end

function love.keypressed(key)
    if key == "f1" then
        debugPath = not debugPath
    end

    if gameState == "game" then
        if key == "space" and not gameOver then
            if sounds.swordSwing then
                sounds.swordSwing:stop()
                sounds.swordSwing:play()
            end
            player:startAttack()
        end

        if key == "return" and gameOver then
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
        local title = "Reaper Game"
        local font = love.graphics.getFont()
        local tw = font:getWidth(title)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(title, WINDOW_WIDTH / 2 - tw / 2, 120)

        local infoY = 160
        love.graphics.print(
            string.format("Best (Easy): %d   Best (Normal): %d   Best (Hard): %d",
                bestScores.easy, bestScores.normal, bestScores.hard),
            WINDOW_WIDTH / 2 - 220,
            infoY
        )

        for _, btn in ipairs(menuButtons) do
            btn:draw()
        end

        love.graphics.setColor(1, 1, 1)
        love.graphics.print("F1: Toggle Path Debug (in game)", 10, WINDOW_HEIGHT - 30)
        return
    end

    love.graphics.setColor(0.12, 0.15, 0.19)
    for x = 0, WINDOW_WIDTH, TILE_SIZE * 2 do
        for y = 0, WINDOW_HEIGHT, TILE_SIZE * 2 do
            love.graphics.rectangle("line", x, y, TILE_SIZE * 2, TILE_SIZE * 2)
        end
    end
    love.graphics.setColor(1, 1, 1)

    love.graphics.setColor(0.2, 0.25, 0.3)
    love.graphics.rectangle("line", 150, 100, 500, 400)
    love.graphics.setColor(1, 1, 1)

    for _, wall in ipairs(walls) do
        wall:draw()
    end

    coin:draw()
    for _, heart in ipairs(hearts) do
        heart:draw()
    end

    enemy:draw()
    if enemy2 then enemy2:draw() end
    player:draw()

    for _, eff in ipairs(effects) do
        eff:draw()
    end

    if debugPath then
        drawEnemyPath(enemy, 0, 1, 0)
        if enemy2 then
            drawEnemyPath(enemy2, 0, 1, 1)
        end
    end

    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, 40)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", 0, 0, WINDOW_WIDTH, 40)

    love.graphics.print("Score: " .. tostring(score), 10, 10)

    local bestForDiff = currentDifficulty and bestScores[currentDifficulty] or 0
    love.graphics.print("Best: " .. tostring(bestForDiff), 120, 10)

    if currentDifficulty then
        local label = "Difficulty: " .. difficulties[currentDifficulty].label
        love.graphics.print(label, 220, 10)
    end

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

    do
        local barX, barY, barW, barH = 580, 10, 200, 20

        love.graphics.setColor(0.12, 0.12, 0.17)
        love.graphics.rectangle("fill", barX, barY, barW, barH)
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("line", barX, barY, barW, barH)

        local level = (enemySpeedMultiplier - 1.0) / (DANGER_MAX_MULT - 1.0)
        if level < 0 then level = 0 end
        if level > 1 then level = 1 end

        if level > 0 then
            local fillW = barW * level
            local r = 0.2 + 0.8 * level
            local g = 0.9 - 0.7 * level
            local b = 0.2
            love.graphics.setColor(r, g, b)
            love.graphics.rectangle("fill", barX + 1, barY + 1, math.max(0, fillW - 2), barH - 2)
            love.graphics.setColor(1, 1, 1)
        end

        love.graphics.print("Danger", barX, barY - 12)
    end

    love.graphics.print(
        "Move: WASD / Arrows   Attack: Space   Restart: Enter (after death)   F1: Toggle Path Debug",
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
