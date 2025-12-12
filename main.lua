local Player      = require("player")
local Enemy       = require("enemy")
local Coin        = require("coin")
local Wall        = require("wall")
local Animation   = require("animation")
local Button      = require("button")
local HeartPickup = require("heartpickup")
local HitEffect   = require("hiteffect")
local Highscores  = require("highscores")

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

-- game state
local gameState = "menu"   -- "menu" | "game"
local gamePaused = false

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
local enemy2RespawnTimer = 0
local enemySpeedMultiplier = 1.0

-- UI
local menuButtons = {}
local pauseButtons = {}

-- audio
local sounds = {}
local enemySwingTimer = 0

-- enemy images
local enemyImgs = { attack = nil, death = nil, summon = nil }

local ENEMY1_SPAWN_X, ENEMY1_SPAWN_Y = WINDOW_WIDTH * 0.75, WINDOW_HEIGHT * 0.50
local ENEMY2_SPAWN_X, ENEMY2_SPAWN_Y = WINDOW_WIDTH * 0.75, WINDOW_HEIGHT * 0.25

-- assets
local menuBg = nil
local fontDefault = nil
local fontPixel = nil

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
    if not e or not e.path or #e.path == 0 then return end
    r = r or 0; g = g or 1; b = b or 0

    love.graphics.setColor(r, g, b, 0.5)
    for i, node in ipairs(e.path) do
        local cx, cy = tileToWorldCenter(node.tx, node.ty)
        love.graphics.rectangle("line", cx - TILE_SIZE / 2, cy - TILE_SIZE / 2, TILE_SIZE, TILE_SIZE)
        if i < #e.path then
            local nx, ny = tileToWorldCenter(e.path[i + 1].tx, e.path[i + 1].ty)
            love.graphics.line(cx, cy, nx, ny)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

local function makeEnemyAnims()
    return {
        attacking = Animation:new(enemyImgs.attack, ENEMY_FRAME_SIZE, ENEMY_FRAME_SIZE, 13, 6, 10, true),
        death     = Animation:new(enemyImgs.death,  ENEMY_FRAME_SIZE, ENEMY_FRAME_SIZE, 18, 10, 9, false),
        summon    = Animation:new(enemyImgs.summon, ENEMY_FRAME_SIZE, ENEMY_FRAME_SIZE, 5,  4,  8, false),
    }
end

local function spawnEnemyAt(x, y)
    local cfg = difficulties[currentDifficulty]
    local e = Enemy:new(x, y, makeEnemyAnims())
    e.speed = cfg.baseEnemySpeed * enemySpeedMultiplier
    return e
end

local function commitBestIfNeeded()
    if not currentDifficulty then return end
    if score > (bestScores[currentDifficulty] or 0) then
        bestScores[currentDifficulty] = score
        Highscores.set(bestScores, currentDifficulty, score)
    end
end

local function stopEnemySwing()
    if sounds.enemySwing and sounds.enemySwing:isPlaying() then
        sounds.enemySwing:stop()
    end
    enemySwingTimer = 0
end

local function goToMenu()
    gameState = "menu"
    gamePaused = false
    gameOver = false
    stopEnemySwing()
end

local function startGame(difficultyKey)
    currentDifficulty = difficultyKey

    score = 0
    gameOver = false
    gamePaused = false

    enemySpeedMultiplier = 1.0
    enemyRespawnTimer = 0
    enemy2RespawnTimer = 0
    enemySwingTimer = 0

    player = Player:new(WINDOW_WIDTH * 0.25, WINDOW_HEIGHT * 0.5, playerAnims)

    enemy  = spawnEnemyAt(ENEMY1_SPAWN_X, ENEMY1_SPAWN_Y)
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
-- HUD helpers
-- ==========================
local function drawHeartShape(cx, cy, size, filled, dimmed)
    local s = size or 10
    local r = s * 0.38

    if dimmed then
        love.graphics.setColor(0.28, 0.28, 0.30)
    else
        if filled then love.graphics.setColor(0.92, 0.18, 0.30)
        else love.graphics.setColor(0.35, 0.35, 0.38) end
    end

    local leftX  = cx - r
    local rightX = cx + r
    local topY   = cy - r * 0.2

    if filled and not dimmed then
        love.graphics.circle("fill", leftX, topY, r)
        love.graphics.circle("fill", rightX, topY, r)
        love.graphics.polygon("fill",
            cx - 2*r, topY,
            cx + 2*r, topY,
            cx,       cy + 2.4*r
        )
        love.graphics.setColor(0, 0, 0, 0.18)
        love.graphics.circle("line", leftX, topY, r)
        love.graphics.circle("line", rightX, topY, r)
        love.graphics.polygon("line",
            cx - 2*r, topY,
            cx + 2*r, topY,
            cx,       cy + 2.4*r
        )
    else
        love.graphics.circle("line", leftX, topY, r)
        love.graphics.circle("line", rightX, topY, r)
        love.graphics.polygon("line",
            cx - 2*r, topY,
            cx + 2*r, topY,
            cx,       cy + 2.4*r
        )
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function drawHud()
    local barH = 44

    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, barH)
    love.graphics.setColor(1, 1, 1, 0.18)
    love.graphics.rectangle("line", 0, 0, WINDOW_WIDTH, barH)
    love.graphics.setColor(1, 1, 1, 1)

    local font = love.graphics.getFont()

    -- LEFT: HP hearts
    local hpX = 14
    local hpY = 14
    local heartSize = 14
    for i = 1, player:getMaxHp() do
        local cx = hpX + (i - 1) * 26
        local cy = hpY + 10
        local filled = i <= player.hp
        drawHeartShape(cx, cy, heartSize, filled, not filled)
    end

    -- MIDDLE: Score + Best
    local bestForDiff = currentDifficulty and (bestScores[currentDifficulty] or 0) or 0
    local midText = "Score: " .. tostring(score) .. "    Best: " .. tostring(bestForDiff)
    local midW = font:getWidth(midText)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(midText, WINDOW_WIDTH / 2 - midW / 2, 12)

    -- RIGHT: Danger bar with label on left
    do
        local label = "Danger"
        local labelW = font:getWidth(label)

        local barW, barH2 = 170, 18
        local barX = WINDOW_WIDTH - 14 - barW
        local barY = 13

        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print(label, barX - labelW - 10, 12)

        love.graphics.setColor(0.12, 0.12, 0.17)
        love.graphics.rectangle("fill", barX, barY, barW, barH2)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.rectangle("line", barX, barY, barW, barH2)

        local level = (enemySpeedMultiplier - 1.0) / (DANGER_MAX_MULT - 1.0)
        if level < 0 then level = 0 end
        if level > 1 then level = 1 end

        if level > 0 then
            local fillW = barW * level
            local r = 0.2 + 0.8 * level
            local g = 0.9 - 0.7 * level
            local b = 0.2
            love.graphics.setColor(r, g, b)
            love.graphics.rectangle("fill", barX + 1, barY + 1, math.max(0, fillW - 2), barH2 - 2)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end
end

local function drawControlsBottom()
    local text = "Move: WASD / Arrows   Attack: Space   Restart: Enter   Pause: Esc   F1: Debug"
    local font = love.graphics.getFont()
    local tw = font:getWidth(text)

    local pad = 8
    local boxW = tw + 18
    local boxH = font:getHeight() + 14
    local x = WINDOW_WIDTH / 2 - boxW / 2
    local y = WINDOW_HEIGHT - boxH - pad

    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", x, y, boxW, boxH)
    love.graphics.setColor(1, 1, 1, 0.18)
    love.graphics.rectangle("line", x, y, boxW, boxH)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(text, x + 9, y + 7)
end

-- ==========================
-- LOVE callbacks
-- ==========================
function love.load()
    love.window.setMode(WINDOW_WIDTH, WINDOW_HEIGHT)
    love.window.setTitle("Sprite Sheet Game")
    love.graphics.setDefaultFilter("nearest", "nearest")
    math.randomseed(os.time())

    bestScores = Highscores.load()

    fontDefault = love.graphics.getFont()
    if love.filesystem.getInfo("assets/Ithaca.ttf") then
        fontPixel = love.graphics.newFont("assets/Ithaca.ttf", 18)
        fontPixel:setFilter("nearest", "nearest")
    end

    if love.filesystem.getInfo("assets/background.png") then
        menuBg = love.graphics.newImage("assets/background.png")
        menuBg:setFilter("nearest", "nearest")
    end

    -- PLAYER
    local idleImg   = love.graphics.newImage("assets/idle.png")
    local runImg    = love.graphics.newImage("assets/run.png")
    local attackImg = love.graphics.newImage("assets/attack.png")
    local hurtImg   = love.graphics.newImage("assets/hurt.png")

    playerAnims.idle   = Animation:new(idleImg,   PLAYER_FRAME_SIZE, PLAYER_FRAME_SIZE, 10, 10, 8,  true)
    playerAnims.run    = Animation:new(runImg,    PLAYER_FRAME_SIZE, PLAYER_FRAME_SIZE, 16, 16, 14, true)
    playerAnims.attack = Animation:new(attackImg, PLAYER_FRAME_SIZE, PLAYER_FRAME_SIZE, 7,  7,  16, false)
    playerAnims.hurt   = Animation:new(hurtImg,   PLAYER_FRAME_SIZE, PLAYER_FRAME_SIZE, 4,  4,  10, false)

    -- ENEMY IMGS (shared)
    enemyImgs.attack = love.graphics.newImage("assets/attacking.png")
    enemyImgs.death  = love.graphics.newImage("assets/death.png")
    enemyImgs.summon = love.graphics.newImage("assets/summon.png")

    -- MENU BUTTONS
    local btnW, btnH = 200, 50
    local startY = WINDOW_HEIGHT / 2 - 100
    local gap = 60
    local centerX = WINDOW_WIDTH / 2 - btnW / 2

    menuButtons = {
        Button:new(centerX, startY,         btnW, btnH, "Easy",   function() startGame("easy")   end),
        Button:new(centerX, startY + gap,   btnW, btnH, "Normal", function() startGame("normal") end),
        Button:new(centerX, startY + gap*2, btnW, btnH, "Hard",   function() startGame("hard")   end),
        Button:new(centerX, startY + gap*3, btnW, btnH, "Quit",   function() love.event.quit()   end),
    }

    -- PAUSE BUTTONS
    local pW, pH = 240, 50
    local pStartY = WINDOW_HEIGHT / 2 - 60
    local pGap = 60
    local pX = WINDOW_WIDTH / 2 - pW / 2

    pauseButtons = {
        Button:new(pX, pStartY,         pW, pH, "Resume",    function() gamePaused = false end),
        Button:new(pX, pStartY + pGap,  pW, pH, "Main Menu", function() goToMenu() end),
        Button:new(pX, pStartY + pGap*2,pW, pH, "Quit",      function() love.event.quit() end),
    }

    -- SOUNDS
    sounds.swordSwing   = love.audio.newSource("assets/sword_swing.wav", "static")
    sounds.enemySwing   = love.audio.newSource("assets/enemy_swing.wav", "static")
    sounds.coinPickup   = love.audio.newSource("assets/coin_pickup.wav", "static")
    sounds.heartPickup  = love.audio.newSource("assets/heart_pickup.wav", "static")
end

function love.update(dt)
    if love.keyboard.isDown("escape") then
        -- handled in keypressed to avoid repeating every frame
    end

    if gameState ~= "game" or gameOver or gamePaused then
        stopEnemySwing()
    end

    if gameState ~= "game" then return end
    if gameOver then return end
    if gamePaused then return end

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

    -- respawn main enemy
    if enemy:isDead() then
        enemyRespawnTimer = enemyRespawnTimer + dt
        if enemyRespawnTimer >= ENEMY_RESPAWN_DELAY then
            enemyRespawnTimer = 0
            enemy = spawnEnemyAt(ENEMY1_SPAWN_X, ENEMY1_SPAWN_Y)
        end
    else
        enemyRespawnTimer = 0
    end

    -- respawn second enemy after it has been introduced
    if enemy2Spawned then
        if enemy2 == nil then
            enemy2RespawnTimer = enemy2RespawnTimer + dt
            if enemy2RespawnTimer >= ENEMY_RESPAWN_DELAY then
                enemy2RespawnTimer = 0
                enemy2 = spawnEnemyAt(ENEMY2_SPAWN_X, ENEMY2_SPAWN_Y)
            end
        else
            if enemy2:isDead() then
                enemy2RespawnTimer = enemy2RespawnTimer + dt
                if enemy2RespawnTimer >= ENEMY_RESPAWN_DELAY then
                    enemy2RespawnTimer = 0
                    enemy2 = spawnEnemyAt(ENEMY2_SPAWN_X, ENEMY2_SPAWN_Y)
                end
            else
                enemy2RespawnTimer = 0
            end
        end
    end

    local pBox = player:getHitbox()
    local eBox1 = enemy:getHitbox()
    local eBox2 = enemy2 and enemy2:getHitbox() or nil

    -- player hits enemies
    if player:isAttacking() and not enemy:isDead() then
        local atkBox = player:getAttackHitbox()
        if rectsOverlap(atkBox, eBox1) then
            enemy:takeHit(1)
            addEffectBurst(eBox1.x + eBox1.w / 2, eBox1.y + eBox1.h / 2, "hit", 6)
        end
    end

    if enemy2 and eBox2 and player:isAttacking() and not enemy2:isDead() then
        local atkBox = player:getAttackHitbox()
        if rectsOverlap(atkBox, eBox2) then
            enemy2:takeHit(1)
            addEffectBurst(eBox2.x + eBox2.w / 2, eBox2.y + eBox2.h / 2, "hit", 6)
        end
    end

    -- enemies hit player
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
        commitBestIfNeeded()
        gameOver = true
        enemy:setState("death")
        if enemy2 and not enemy2:isDead() then enemy2:setState("death") end
        return
    end

    -- player picks coin
    if circleRectOverlap(coin.x, coin.y, coin.radius, pBox) then
        score = score + 1

        if sounds.coinPickup then
            sounds.coinPickup:stop()
            sounds.coinPickup:play()
        end

        addEffectBurst(coin.x, coin.y, "coin", 8)

        local cfg = difficulties[currentDifficulty]
        enemySpeedMultiplier = enemySpeedMultiplier * cfg.speedGainPerCoin

        if not enemy:isDead() then enemy.speed = cfg.baseEnemySpeed * enemySpeedMultiplier end
        if enemy2 and not enemy2:isDead() then enemy2.speed = cfg.baseEnemySpeed * enemySpeedMultiplier end

        if player.hp < player:getMaxHp() and #hearts == 0 then
            if math.random() < HEART_SPAWN_CHANCE then
                table.insert(hearts, spawnHeart())
            end
        end

        coin = spawnCoin()

        if (not enemy2Spawned) and score >= SECOND_ENEMY_SCORE_THRESHOLD then
            enemy2Spawned = true
            enemy2RespawnTimer = 0
            enemy2 = spawnEnemyAt(ENEMY2_SPAWN_X, ENEMY2_SPAWN_Y)
        end
    end

    -- player picks heart
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

    -- enemy swing sound (if any enemy attacking)
    if sounds.enemySwing then
        local e1Attacking = enemy and (not enemy:isDead()) and enemy.state == "attacking"
        local e2Attacking = enemy2 and (not enemy2:isDead()) and enemy2.state == "attacking"

        if not (e1Attacking or e2Attacking) then
            stopEnemySwing()
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

    if key == "escape" then
        if gameState == "game" and not gameOver then
            gamePaused = not gamePaused
        end
        return
    end

    if gameState == "game" then
        if key == "space" and not gameOver and not gamePaused then
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

    if gameState == "menu" then
        for _, btn in ipairs(menuButtons) do
            if btn:containsPoint(x, y) then
                btn:click()
                break
            end
        end
        return
    end

    if gameState == "game" and gamePaused then
        for _, btn in ipairs(pauseButtons) do
            if btn:containsPoint(x, y) then
                btn:click()
                break
            end
        end
        return
    end
end

function love.draw()
    love.graphics.clear(0.08, 0.09, 0.12)

    if fontPixel then
        love.graphics.setFont(fontPixel)
    else
        love.graphics.setFont(fontDefault)
    end

    if gameState == "menu" then
        if menuBg then
            local sx = WINDOW_WIDTH / menuBg:getWidth()
            local sy = WINDOW_HEIGHT / menuBg:getHeight()
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(menuBg, 0, 0, 0, sx, sy)
            love.graphics.setColor(0, 0, 0, 0.45)
            love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
            love.graphics.setColor(1, 1, 1, 1)
        end

        local title = "Reaper Game"
        local font = love.graphics.getFont()
        local tw = font:getWidth(title)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(title, WINDOW_WIDTH / 2 - tw / 2, 110)

        local bestLine = string.format(
            "Best (Easy): %d   Best (Normal): %d   Best (Hard): %d",
            bestScores.easy or 0, bestScores.normal or 0, bestScores.hard or 0
        )
        local bw = font:getWidth(bestLine)
        love.graphics.print(bestLine, WINDOW_WIDTH / 2 - bw / 2, 160)

        for _, btn in ipairs(menuButtons) do
            btn:draw()
        end

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Click a difficulty to start", 10, WINDOW_HEIGHT - 30)
        return
    end

    -- === GAMEPLAY DRAW ===

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

    for _, wall in ipairs(walls) do wall:draw() end

    coin:draw()
    for _, heart in ipairs(hearts) do heart:draw() end

    enemy:draw()
    if enemy2 then enemy2:draw() end
    player:draw()

    for _, eff in ipairs(effects) do eff:draw() end

    if debugPath then
        drawEnemyPath(enemy, 0, 1, 0)
        if enemy2 then drawEnemyPath(enemy2, 0, 1, 1) end
    end

    -- HUD + controls
    -- (same functions as before, kept inline minimal)
    local function drawHeartShape(cx, cy, size, filled, dimmed)
        local s = size or 10
        local r = s * 0.38
        if dimmed then
            love.graphics.setColor(0.28, 0.28, 0.30)
        else
            if filled then love.graphics.setColor(0.92, 0.18, 0.30)
            else love.graphics.setColor(0.35, 0.35, 0.38) end
        end
        local leftX  = cx - r
        local rightX = cx + r
        local topY   = cy - r * 0.2
        if filled and not dimmed then
            -- draw triangle FIRST (behind)
            love.graphics.polygon("fill",
                cx - 2*r, topY,
                cx + 2*r, topY,
                cx,       cy + 2.4*r
            )

            -- then circles ON TOP
            love.graphics.circle("fill", leftX, topY, r)
            love.graphics.circle("fill", rightX, topY, r)

            -- outline
            love.graphics.setColor(0, 0, 0, 0.18)
            love.graphics.polygon("line",
                cx - 2*r, topY,
                cx + 2*r, topY,
                cx,       cy + 2.4*r
            )
            love.graphics.circle("line", leftX, topY, r)
            love.graphics.circle("line", rightX, topY, r)
        else
            love.graphics.circle("line", leftX, topY, r)
            love.graphics.circle("line", rightX, topY, r)
            love.graphics.polygon("line",
                cx - 2*r, topY,
                cx + 2*r, topY,
                cx,       cy + 2.4*r
            )
        end
        love.graphics.setColor(1, 1, 1, 1)
    end

    local function drawHud()
        local barH = 44
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, barH)
        love.graphics.setColor(1, 1, 1, 0.18)
        love.graphics.rectangle("line", 0, 0, WINDOW_WIDTH, barH)
        love.graphics.setColor(1, 1, 1, 1)

        local font = love.graphics.getFont()

        local hpX = 14
        local hpY = 14
        local heartSize = 14
        for i = 1, player:getMaxHp() do
            local cx = hpX + (i - 1) * 26
            local cy = hpY + 10
            local filled = i <= player.hp
            drawHeartShape(cx, cy, heartSize, filled, not filled)
        end

        local bestForDiff = currentDifficulty and (bestScores[currentDifficulty] or 0) or 0
        local midText = "Score: " .. tostring(score) .. "    Best: " .. tostring(bestForDiff)
        local midW = font:getWidth(midText)
        love.graphics.print(midText, WINDOW_WIDTH / 2 - midW / 2, 12)

        local label = "Danger"
        local labelW = font:getWidth(label)
        local barW, barH2 = 170, 18
        local barX = WINDOW_WIDTH - 14 - barW
        local barY = 13

        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print(label, barX - labelW - 10, 12)

        love.graphics.setColor(0.12, 0.12, 0.17)
        love.graphics.rectangle("fill", barX, barY, barW, barH2)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.rectangle("line", barX, barY, barW, barH2)

        local level = (enemySpeedMultiplier - 1.0) / (DANGER_MAX_MULT - 1.0)
        if level < 0 then level = 0 end
        if level > 1 then level = 1 end

        if level > 0 then
            local fillW = barW * level
            local r = 0.2 + 0.8 * level
            local g = 0.9 - 0.7 * level
            local b = 0.2
            love.graphics.setColor(r, g, b)
            love.graphics.rectangle("fill", barX + 1, barY + 1, math.max(0, fillW - 2), barH2 - 2)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    local function drawControlsBottom()
        local text = "Move: WASD / Arrows   Attack: Space   Restart: Enter   Pause: Esc   F1: Debug"
        local font = love.graphics.getFont()
        local tw = font:getWidth(text)

        local pad = 8
        local boxW = tw + 18
        local boxH = font:getHeight() + 14
        local x = WINDOW_WIDTH / 2 - boxW / 2
        local y = WINDOW_HEIGHT - boxH - pad

        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", x, y, boxW, boxH)
        love.graphics.setColor(1, 1, 1, 0.18)
        love.graphics.rectangle("line", x, y, boxW, boxH)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(text, x + 9, y + 7)
    end

    drawHud()
    drawControlsBottom()

    if gamePaused then
        local overlayW, overlayH = 360, 260
        local ox = WINDOW_WIDTH / 2 - overlayW / 2
        local oy = WINDOW_HEIGHT / 2 - overlayH / 2

        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", ox, oy, overlayW, overlayH)
        love.graphics.setColor(1, 1, 1, 0.18)
        love.graphics.rectangle("line", ox, oy, overlayW, overlayH)
        love.graphics.setColor(1, 1, 1, 1)

        local title = "PAUSED"
        local font = love.graphics.getFont()
        local tw = font:getWidth(title)
        love.graphics.print(title, WINDOW_WIDTH / 2 - tw / 2, oy + 20)

        for _, btn in ipairs(pauseButtons) do
            btn:draw()
        end
    end

    if gameOver then
        local text = "You Died! Score: " .. tostring(score)
        if currentDifficulty then
            text = text .. "  Best (" .. difficulties[currentDifficulty].label .. "): "
                .. tostring(bestScores[currentDifficulty] or 0)
        end
        text = text .. "  -  Press Enter"

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
