-- server.lua (converted for RSG Core v2.0)
-- IMPORTANT: adjust RSGCore export call if your installation differs.

RSGCore = exports['rsg-core']:GetCoreObject() -- adjust if necessary
local melding = true
-- Provide a minimal webhook helper to mimic VORPcore.AddWebhook
-- If you don't want Discord logging, set Config.Webhook = nil in your config.
function AddWebhook(title, webhook, message)
    if not webhook or webhook == "" then return end
    local embed = {
        ["username"] = title or "Log",
        ["content"] = message or "",
    }
    PerformHttpRequest(webhook, function(err, text, headers) end, "POST", json.encode(embed), { ["Content-Type"] = "application/json" })
end

local locations = {}
local pendingGames = {}
local activeGames = {}

-- Initial set up of locations
Citizen.CreateThread(function()
    for k,v in pairs(Config.Locations) do
        local location = Location:New({
            id = k,
            state = LOCATION_STATES.EMPTY,
            tableCoords = v.Table.Coords,
            maxPlayers = v.MaxPlayers,
        })
        table.insert(locations, location)
    end
end)

-- SERVER EVENTS

RegisterServerEvent("rainbow_poker:Server:RequestCharacterName", function()
    local _source = source
    local name = nil
    local ok, player = pcall(function() return RSGCore.Functions.GetPlayer(_source) end)
    if ok and player then
        -- Try common fields (adjust if your rsg-core stores names elsewhere)
        if player.PlayerData and player.PlayerData.charinfo then
            name = player.PlayerData.charinfo.firstname or player.PlayerData.charinfo.first_name
        elseif player.PlayerData and player.PlayerData.name then
            name = player.PlayerData.name
        else
            -- fallback to server id string
            name = ("Player%d"):format(_source)
        end
    else
        name = ("Player%d"):format(_source)
    end

    TriggerClientEvent("rainbow_poker:Client:ReturnRequestCharacterName", _source, name)
end)

RegisterServerEvent("rainbow_poker:Server:RequestUpdatePokerTables", function()
    local _source = source
    TriggerClientEvent("rainbow_poker:Client:UpdatePokerTables", _source, locations)
end)

RegisterServerEvent("rainbow_poker:Server:StartNewPendingGame", function(player1sChosenName, anteAmount, tableLocationIndex)
    local _source = source
    if Config.DebugPrint then print("StartNewPendingGame", player1sChosenName, anteAmount, tableLocationIndex) end

    if not locations[tableLocationIndex] then return end
    if locations[tableLocationIndex]:getState() ~= LOCATION_STATES.EMPTY then return end

    -- Make sure this player isn't in pending or active game
    if findPendingGameByPlayerNetId(_source) ~= false then
        TriggerClientEvent('ox_lib:notify', _source, { title = "Poker", description = "Du er fortsatt i et ventende pokerspill.", type = 'error'})
        --TriggerClientEvent('RSGCore:Notify', _source, "You are still in a pending poker game.", 'error')
        return
    end
    if findActiveGameByPlayerNetId(_source) ~= false then
        TriggerClientEvent('ox_lib:notify', _source, { title = "Poker", description = "Du er fortsatt i et aktivt pokerspill.", type = 'error'})
        --TriggerClientEvent('RSGCore:Notify', _source, "Du er fortsatt i et aktivt pokerspill.", 'error')
        return
    end

    player1sChosenName = truncateString(player1sChosenName, 10)
    math.randomseed(os.time())
    local player1NetId = _source

    -- Create pending player object
    local pendingPlayer1 = Player:New({
        netId = player1NetId,
        name = player1sChosenName,
        order = 1,
    })

    local newPendingGame = PendingGame:New({
        initiatorNetId = _source,
        players = { pendingPlayer1 },
        ante = anteAmount,
    })

    locations[tableLocationIndex]:setPendingGame(newPendingGame)
    locations[tableLocationIndex]:setState(LOCATION_STATES.PENDING_GAME)

    TriggerClientEvent("rainbow_poker:Client:ReturnStartNewPendingGame", _source, tableLocationIndex, pendingPlayer1)
    TriggerClientEvent("rainbow_poker:Client:UpdatePokerTables", -1, locations)
    -- log to discord (use AddWebhook helper)
    AddWebhook("♥️ Poker - New Pending Game Started", Config.Webhook, string.format("Location: %s\nInitiator: %s\nAnte: %s", locations[tableLocationIndex]:getId(), player1sChosenName or "unknown", anteAmount or 0))
end)

RegisterServerEvent("rainbow_poker:Server:JoinGame", function(playersChosenName, tableLocationIndex)
    local _source = source
    if Config.DebugPrint then print("JoinGame", playersChosenName, tableLocationIndex) end

    local pendingGame = locations[tableLocationIndex]:getPendingGame()

    if #pendingGame:getPlayers() >= locations[tableLocationIndex]:getMaxPlayers() then
        TriggerClientEvent('ox_lib:notify', _source, { title = "Poker", description = "Dette poker spillet er fullt.", type = 'error'})
        --TriggerClientEvent('RSGCore:Notify', _source, "This poker game is full.", 'error')
        return
    end

    if findPendingGameByPlayerNetId(_source) ~= false then
        TriggerClientEvent('ox_lib:notify', _source, { title = "Poker", description = "Du er fortsatt i et ventende pokerspill", type = 'error'})
        --TriggerClientEvent('RSGCore:Notify', _source, "Du er fortsatt i et ventende pokerspill.", 'error')
        return
    end

    if findActiveGameByPlayerNetId(_source) ~= false then
        TriggerClientEvent('ox_lib:notify', _source, { title = "Poker", description = "Du er fortsatt i et aktivt pokerspill", type = 'error'})
        --TriggerClientEvent('RSGCore:Notify', _source, "You are still in an active poker game.", 'error')
        return
    end

    playersChosenName = truncateString(playersChosenName, 12)
    local playerNetId = _source

    local pendingPlayer = Player:New({
        netId = playerNetId,
        name = playersChosenName,
        order = #pendingGame:getPlayers() + 1,
    })

    pendingGame:addPlayer(pendingPlayer)
    TriggerClientEvent("rainbow_poker:Client:ReturnJoinGame", _source, tableLocationIndex, pendingPlayer)
    TriggerClientEvent("rainbow_poker:Client:UpdatePokerTables", -1, locations)
    AddWebhook("♣️ Poker - Player Joined Pending Game", Config.Webhook, string.format("Location: %s\nPlayer: %s", locations[tableLocationIndex]:getId(), playersChosenName))
end)

RegisterServerEvent("rainbow_poker:Server:FinalizePendingGameAndBegin", function(tableLocationIndex)
    local _source = source
    if Config.DebugPrint then print("FinalizePendingGameAndBegin", tableLocationIndex) end

    local pendingGame = locations[tableLocationIndex]:getPendingGame()
    if #pendingGame:getPlayers() < 2 then
        if melding then
            TriggerClientEvent('ox_lib:notify', _source, { title = "Poker", description = "Du trenger minst 1 annen spiller for å bli med i pokerspillet ditt.", type = 'error'})
            melding = false
            Wait(1000)
            melding = true
        end
            --TriggerClientEvent('RSGCore:Notify', _source, "You need at least 1 other player to join your poker game.", 'error')
        return
    elseif #pendingGame:getPlayers() > 12 then
        if melding then
            TriggerClientEvent('ox_lib:notify', _source, { title = "Poker", description = "Du kan ikke ha mer enn 12 spillere i pokerspillet ditt.", type = 'error'})
            melding = false
            Wait(1000)
            melding = true
        end
        
            --TriggerClientEvent('RSGCore:Notify', _source, "Du kan ikke ha mer enn 12 spillere i pokerspillet ditt.", 'error')
        return
    end

    -- Ensure all players have enough money
    for k,v in pairs(pendingGame:getPlayers()) do
        if not hasMoney(v:getNetId(), pendingGame:getAnte()) then
            TriggerEvent("rainbow_poker:Server:CancelPendingGame", tableLocationIndex)
            TriggerClientEvent('ox_lib:notify',v:getNetId(), { title = "Poker", description = "Du har ikke penger.", type = 'error'})
            --TriggerClientEvent('RSGCore:Notify', v:getNetId(), "You don't have the ante money.", 'error')
            return
        end
    end

    -- Add players to active game and deduct antes
    local activeGamePlayers = {}
    for k,v in pairs(pendingGame:getPlayers()) do
        if takeMoney(v:getNetId(), pendingGame:getAnte()) then
            table.insert(activeGamePlayers, Player:New({
                netId = v:getNetId(),
                name = v:getName(),
                order = v:getOrder(),
                totalAmountBetInGame = pendingGame:getAnte(),
            }))
        else
            TriggerEvent("rainbow_poker:Server:CancelPendingGame", tableLocationIndex)
            return
        end
    end

    local newActiveGame = Game:New({
        locationIndex = tableLocationIndex,
        players = activeGamePlayers,
        ante = pendingGame:getAnte(),
        bettingPool = pendingGame:getAnte() * #pendingGame:getPlayers(),
    })

    newActiveGame:init()
    newActiveGame:moveToNextRound()

    activeGames[tableLocationIndex] = newActiveGame
    locations[tableLocationIndex]:setPendingGame(nil)
    locations[tableLocationIndex]:setState(LOCATION_STATES.GAME_IN_PROGRESS)

    TriggerClientEvent("rainbow_poker:Client:UpdatePokerTables", -1, locations)

    for k,player in pairs(newActiveGame:getPlayers()) do
        print(player:getNetId(),player:getOrder(),newActiveGame )
        TriggerClientEvent("rainbow_poker:Client:StartGame", player:getNetId(), newActiveGame, player:getOrder())
    end

    Wait(1000)
end)

RegisterServerEvent("rainbow_poker:Server:CancelPendingGame", function(tableLocationIndex)
    local _source = source
    if Config.DebugPrint then print("CancelPendingGame", tableLocationIndex) end

    for k,v in pairs(locations[tableLocationIndex]:getPendingGame():getPlayers()) do
        TriggerClientEvent("rainbow_poker:Client:CancelPendingGame", v:getNetId(), tableLocationIndex)
        TriggerClientEvent('ox_lib:notify', v:getNetId(), { title = "Poker", description = "Det ventende pokerspillet er kansellert.", type = 'error'})
        --TriggerClientEvent('RSGCore:Notify', v:getNetId(), "Det ventende pokerspillet er kansellert.", 'error')
    end

    locations[tableLocationIndex]:setPendingGame(nil)
    locations[tableLocationIndex]:setState(LOCATION_STATES.EMPTY)
    TriggerClientEvent("rainbow_poker:Client:UpdatePokerTables", -1, locations)
    AddWebhook("❌ Poker - Pending Game Canceled", Config.Webhook, "Cancel at location: " .. tostring(tableLocationIndex))
end)

RegisterServerEvent("rainbow_poker:Server:PlayerActionCheck", function(tableLocationIndex)
    local _source = source
    if Config.DebugPrint then print("rainbow_poker:Server:PlayerActionCheck", _source, tableLocationIndex) end

    local game = findActiveGameByPlayerNetId(_source)
    game:stopTurnTimer()
    game:onPlayerDidActionCheck(_source)
    if not game:advanceTurn() then
        checkForWinCondition(game)
    end
    TriggerUpdate(game)
end)

RegisterServerEvent("rainbow_poker:Server:PlayerActionRaise", function(amountToRaise)
    local _source = source
    if Config.DebugPrint then print("rainbow_poker:Server:PlayerActionRaise - _source, amountToRaise:", _source, amountToRaise) end

    local game = findActiveGameByPlayerNetId(_source)
    game:stopTurnTimer()

    if not takeMoney(_source, amountToRaise) then
        TriggerClientEvent('ox_lib:notify', _source, { title = "Poker", description = "Du blir tvunget til å kaste deg.", type = 'error'})
        --TriggerClientEvent('RSGCore:Notify', _source, "You are forced to fold.", 'error')
        fold(_source)
        return
    end

    game:onPlayerDidActionRaise(_source, amountToRaise)
    if not game:advanceTurn() then
        checkForWinCondition(game)
    end
    TriggerUpdate(game)
end)

RegisterServerEvent("rainbow_poker:Server:PlayerActionCall", function()
    local _source = source
    if Config.DebugPrint then print("rainbow_poker:Server:PlayerActionCall", _source) end

    local game = findActiveGameByPlayerNetId(_source)
    game:stopTurnTimer()
    local player = game:findPlayerByNetId(_source)
    local amount = game:getRoundsHighestBet() - player:getAmountBetInRound()

    if not takeMoney(_source, amount) then
        TriggerClientEvent('ox_lib:notify', _source, { title = "Poker", description = "Du blir tvunget til å kaste deg.", type = 'error'})
        --TriggerClientEvent('RSGCore:Notify', _source, "You are forced to fold.", 'error')
        fold(_source)
        return
    end

    game:onPlayerDidActionCall(_source)
    if not game:advanceTurn() then
        checkForWinCondition(game)
    end
    TriggerUpdate(game)
end)

RegisterServerEvent("rainbow_poker:Server:PlayerActionFold", function()
    local _source = source
    if Config.DebugPrint then print("rainbow_poker:Server:PlayerActionFold", _source) end
    fold(_source)
end)

RegisterServerEvent("rainbow_poker:Server:PlayerLeave", function()
    local _source = source
    if Config.DebugPrint then print("rainbow_poker:Server:PlayerLeave", _source) end

    local game = findActiveGameByPlayerNetId(_source)
    local player = game:findPlayerByNetId(_source)
    if game:getStep() ~= ROUNDS.SHOWDOWN and player:getHasFolded() == false then
        print("WARNING: Player trying to leave game pre-showdown when they haven't folded yet.", _source)
        return
    end

    TriggerClientEvent("rainbow_poker:Client:ReturnPlayerLeave", _source)
end)

-- core helper functions (money, finders, win checks, etc.)

function checkForWinCondition(game)
    if Config.DebugPrint then print("checkForWinCondition()") end
    local isWinCondition = false

    if game:getStep() == ROUNDS.RIVER then
        if Config.DebugPrint then print("checkForWinCondition() - true - due to River") end
        isWinCondition = true
        game:moveToNextRound()
    end

    local numPlayersFolded = 0
    for k,player in pairs(game:getPlayers()) do
        if player:getHasFolded() then
            numPlayersFolded = numPlayersFolded + 1
        end
    end
    if numPlayersFolded >= #game:getPlayers()-1 then
        if Config.DebugPrint then print("checkForWinCondition() - true - due to folds") end
        isWinCondition = true
    end

    if isWinCondition then
        game:stopTurnTimer()
        local winScenario = getWinScenarioFromSetOfPlayers(game:getPlayers(), game:getBoard(), game:getStep())
        if Config.DebugPrint then print("checkForWinCondition() - WIN - winScenario:", winScenario) end

        if not winScenario:getIsTrueTie() then
            giveMoney(winScenario:getWinningHand():getPlayerNetId(), game:getBettingPool())
        else
            local splitAmount = game:getBettingPool() / #winScenario:getTiedHands()
            for k,tiedHand in pairs(winScenario:getTiedHands()) do
                giveMoney(tiedHand:getPlayerNetId(), splitAmount)
            end
        end

        for k,player in pairs(game:getPlayers()) do
            TriggerClientEvent("rainbow_poker:Client:AlertWin", player:getNetId(), winScenario)
        end

        Citizen.SetTimeout(30 * 1000, function()
            endAndCleanupGame(game)
        end)

        AddWebhook("♦️ Poker - Finished", Config.Webhook, "Location: " .. tostring(game:getLocationIndex()))
    else
        game:moveToNextRound()
    end
end

function endAndCleanupGame(game)
    local locationIndex = game:getLocationIndex()
    if Config.DebugPrint then print("endAndCleanupGame - locationIndex:", locationIndex) end

    for k,player in pairs(game:getPlayers()) do
        TriggerClientEvent("rainbow_poker:Client:CleanupFinishedGame", player:getNetId())
    end

    locations[locationIndex]:setState(LOCATION_STATES.EMPTY)
    activeGames[locationIndex] = nil
    game = nil
    TriggerClientEvent("rainbow_poker:Client:UpdatePokerTables", -1, locations)
end

function fold(targetNetId)
    local game = findActiveGameByPlayerNetId(targetNetId)
    game:stopTurnTimer()
    game:onPlayerDidActionFold(targetNetId)

    local numNotFolded = 0
    for k,player in pairs(game:getPlayers()) do
        if not player:getHasFolded() then
            numNotFolded = numNotFolded + 1
        end
    end

    if numNotFolded > 1 then
        if not game:advanceTurn() then
            checkForWinCondition(game)
        end
        TriggerUpdate(game)
    else
        game:setStep(ROUNDS.SHOWDOWN)
        checkForWinCondition(game)
        TriggerUpdate(game)
    end
end

function hasMoney(targetNetId, amount)
    local ok, player = pcall(function() return RSGCore.Functions.GetPlayer(targetNetId) end)
    if not ok or not player then return false end

    local cash = 0
    if player.Functions and player.Functions.GetMoney then
        cash = player.Functions.GetMoney('cash') or 0
    elseif player.PlayerData and player.PlayerData.money and player.PlayerData.money['cash'] then
        cash = player.PlayerData.money['cash']
    end

    amount = tonumber(amount)
    if tonumber(cash) < tonumber(amount) then
        return false
    end
    return true
end

function takeMoney(targetNetId, amount)
    local ok, player = pcall(function() return RSGCore.Functions.GetPlayer(targetNetId) end)
    if not ok or not player then
        return false
    end

    amount = tonumber(amount)
    -- Try to remove money using standard RSGCore functions
    local success = false
    if player.Functions and player.Functions.RemoveMoney then
        success = player.Functions.RemoveMoney('cash', amount, "poker-bet")
    elseif player.RemoveMoney then
        success = player.RemoveMoney('cash', amount)
    else
        -- Fallback: attempt to access PlayerData.money and fail gracefully
        local cash = 0
        if player.PlayerData and player.PlayerData.money and player.PlayerData.money['cash'] then
            cash = player.PlayerData.money['cash']
            if cash >= amount then
                player.PlayerData.money['cash'] = cash - amount
                success = true
            else
                success = false
            end
        end
    end

    if not success then
        TriggerClientEvent('ox_lib:notify', targetNetId, { title = "Poker", description = string.format("Du har ikke $%.2f!", amount), type = 'error'})
        --TriggerClientEvent('RSGCore:Notify', targetNetId, string.format("You don't have $%.2f!", amount), 'error')
        return false
    end
    TriggerClientEvent('ox_lib:notify', targetNetId, { title = "Poker", description = string.format("Du har satset $%.2f.", amount), type = 'success'})
    --TriggerClientEvent('RSGCore:Notify', targetNetId, string.format("You have bet $%.2f.", amount), 'success')
    return true
end

function giveMoney(targetNetId, amount)
    amount = tonumber(amount)
    local ok, player = pcall(function() return RSGCore.Functions.GetPlayer(targetNetId) end)
    if not ok or not player then
        return false
    end

    local success = false
    if player.Functions and player.Functions.AddMoney then
        success = player.Functions.AddMoney('cash', amount, "poker-win")
    elseif player.AddMoney then
        success = player.AddMoney('cash', amount)
    else
        if player.PlayerData and player.PlayerData.money and player.PlayerData.money['cash'] then
            player.PlayerData.money['cash'] = player.PlayerData.money['cash'] + amount
            success = true
        end
    end

    if success then
        TriggerClientEvent('ox_lib:notify', targetNetId, { title = "Poker", description = string.format("Du har vunnet $%.2f.", amount), type = 'error'})
        --TriggerClientEvent('RSGCore:Notify', targetNetId, string.format("You have won $%.2f.", amount), 'success')
    end

    return success
end

function truncateString(str, max)
    if string.len(str) > max then
        return string.sub(str, 1, max) .. "…"
    else
        return str
    end
end

-- Trigger updates to all the clients of the players of this game.
function TriggerUpdate(game)
    for k,player in pairs(game:getPlayers()) do
        TriggerClientEvent("rainbow_poker:Client:TriggerUpdate", player:getNetId(), game)
    end
end

-- Discord helpers (lightweight)
function logFinishedGameToDiscord(game, winScenario)
    local str = ""
    local locationName = locations[game:getLocationIndex()]:getId()
    str = str .. string.format("**Location:** %s\n", locationName)
    str = str .. string.format("**Board Cards:** `%s`\n", game:getBoard():getString())
    str = str .. string.format("**Ante:** %s\n", game:getAnte())
    str = str .. string.format("**Final Betting Pool:** $%s\n", game:getBettingPool())
    -- Additional details omitted for brevity in this helper demo
    AddWebhook("♦️ Poker - Finished", Config.Webhook, str)
end

function logPendingGameToDiscord(tableLocationIndex, newPendingGame, pendingPlayer1)
    AddWebhook("♥️ Poker - New Pending Game Started", Config.Webhook, string.format("Location: %s\nPlayer NetId: %d", locations[tableLocationIndex]:getId(), pendingPlayer1:getNetId()))
end

function logJoinToDiscord(tableLocationIndex, pendingGame, pendingPlayer)
    AddWebhook("♣️ Poker - Player Joined Pending Game", Config.Webhook, string.format("Location: %s\nPlayer NetId: %d", locations[tableLocationIndex]:getId(), pendingPlayer:getNetId()))
end

function logPendingGameCancelToDiscord(tableLocationIndex, playerNetId)
    AddWebhook("❌ Poker - Pending Game Canceled", Config.Webhook, string.format("Location: %s\nCanceled By: %d", locations[tableLocationIndex]:getId(), playerNetId))
end

function findActiveGameByPlayerNetId(playerNetId)
    for k,v in pairs(activeGames) do
        for k2,v2 in pairs(v:getPlayers()) do
            if v2:getNetId() == playerNetId then
                return v
            end
        end
    end
    return false
end

function findPendingGameByPlayerNetId(playerNetId)
    for k,v in pairs(pendingGames) do
        for k2,v2 in pairs(v:getPlayers()) do
            if v2:getNetId() == playerNetId then
                return v
            end
        end
    end
    return false
end

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() == resourceName then
        locations = {}
        pendingGames = {}
        activeGames = {}
    end
end)

RegisterNetEvent("grabpokerdaler",function()
    local src = source
    local player = RSGCore.Functions.GetPlayer(src)
    player.Functions.RemoveMoney("cash", Config.grabmoney)
end)