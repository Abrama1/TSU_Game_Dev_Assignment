local Highscores = {}

local FILE_NAME = "highscores.txt"
local VALID_KEYS = { easy = true, normal = true, hard = true }

local function parse(content)
    local scores = { easy = 0, normal = 0, hard = 0 }
    if not content or content == "" then
        return scores
    end

    for line in content:gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*(%w+)%s*=%s*(%d+)%s*$")
        if k and v and VALID_KEYS[k] then
            scores[k] = tonumber(v) or 0
        end
    end

    return scores
end

local function serialize(scores)
    scores = scores or {}
    local e = tonumber(scores.easy) or 0
    local n = tonumber(scores.normal) or 0
    local h = tonumber(scores.hard) or 0
    return ("easy=%d\nnormal=%d\nhard=%d\n"):format(e, n, h)
end

function Highscores.load()
    local content
    if love.filesystem.getInfo(FILE_NAME) then
        content = love.filesystem.read(FILE_NAME)
    end
    return parse(content)
end

function Highscores.save(scores)
    local data = serialize(scores)
    love.filesystem.write(FILE_NAME, data)
end

function Highscores.set(scores, key, value)
    if not VALID_KEYS[key] then return end
    local v = tonumber(value) or 0
    if v < 0 then v = 0 end
    scores[key] = v
    Highscores.save(scores)
end

return Highscores
