-- client.lua (converted for RSG Core v2.0)
-- IMPORTANT: if your rsg-core exposes a different export name, adjust the GetCoreObject() call below.

-- ===== RSG Core init =====
RSGCore = exports['rsg-core']:GetCoreObject() -- adjust if your rsg-core uses another export name
-- RSG-compatible prompt system (replacement for VORPutils.Prompts)
RSGPrompts = {}
RSGPrompts.__index = RSGPrompts

function RSGPrompts:SetupPromptGroup()
    local group = {}
    group.id = GetRandomIntInRange(0, 0xffffff)
    group.prompts = {}

    function group:RegisterPrompt(label, keyHash, holdMode)
        local p = {}
        p.Prompt = PromptRegisterBegin()
        PromptSetControlAction(p.Prompt, keyHash)
        PromptSetText(p.Prompt, CreateVarString(10, "LITERAL_STRING", label))
        PromptSetEnabled(p.Prompt, true)
        PromptSetVisible(p.Prompt, true)
        PromptSetStandardMode(p.Prompt, not holdMode)
        if holdMode then
            PromptSetHoldMode(p.Prompt, true)
        end
        PromptSetGroup(p.Prompt, group.id)
        PromptRegisterEnd(p.Prompt)
        p.active = true

        function p:TogglePrompt(state)
            PromptSetEnabled(self.Prompt, state)
            PromptSetVisible(self.Prompt, state)
            self.active = state
        end

        function p:HasCompleted()
            return PromptHasStandardModeCompleted(self.Prompt) or PromptHasHoldModeCompleted(self.Prompt)
        end

        table.insert(group.prompts, p)
        return p
    end

    function group:ShowGroup(name)
        PromptSetActiveGroupThisFrame(group.id, CreateVarString(10, "LITERAL_STRING", name or "Poker Bord 1$"))
    end

    return group
end



-- ===== Prompt compatibility shim (replaces VORPutils.Prompts) =====
-- This exposes the same methods your script expects:
--    VORPutils.Prompts:SetupPromptGroup() -> returns group with :RegisterPrompt(...), :ShowGroup(name)
-- and prompts returned by RegisterPrompt support :TogglePrompt(bool) and :HasCompleted()

VORPutils = VORPutils or {}
VORPutils.Prompts = VORPutils.Prompts or {}

function VORPutils.Prompts:SetupPromptGroup(groupName)
    local groupObj = {}
    groupObj.group = GetRandomIntInRange(0, 0xffffff)
    groupObj.name = groupName or "Prompt Group"
    groupObj.registered = {}

    function groupObj:RegisterPrompt(label, key, a, b, enabled, mode, params)
        local promptHandle = PromptRegisterBegin()
        PromptSetControlAction(promptHandle, key)
        PromptSetText(promptHandle, CreateVarString(10, "LITERAL_STRING", label))
        PromptSetEnabled(promptHandle, enabled == nil and true or enabled)
        PromptSetVisible(promptHandle, false) -- start hidden
        if mode == "hold" then
            PromptSetHoldMode(promptHandle, true)
        else
            PromptSetStandardMode(promptHandle, true)
        end
        PromptSetGroup(promptHandle, groupObj.group)
        PromptRegisterEnd(promptHandle)

        local promptWrapper = { Prompt = promptHandle, _visible = false }

        function promptWrapper:TogglePrompt(shouldShow)
            self._visible = shouldShow and true or false
            PromptSetVisible(self.Prompt, self._visible)
            PromptSetEnabled(self.Prompt, self._visible)
        end

        function promptWrapper:HasCompleted()
            -- Try both standard and hold detection
            local ok = false
            -- PromptHasStandardModeCompleted works for standard prompts
            local successStandard = false
            local successHold = false
            pcall(function() successStandard = PromptHasStandardModeCompleted(self.Prompt) end)
            pcall(function() successHold = PromptHasHoldModeCompleted(self.Prompt) end)
            ok = successStandard or successHold
            return ok
        end

        table.insert(groupObj.registered, promptWrapper)
        return promptWrapper
    end

    function groupObj:ShowGroup(name)
        PromptSetActiveGroupThisFrame(groupObj.group, CreateVarString(10, "LITERAL_STRING", name or groupObj.name))
    end

    return groupObj
end

-- ===== vorp_inputs replacement (simple onscreen keyboard) =====
-- Exposes exports.vorp_inputs:advancedInput(spec) like your script expects.
-- Replace VORP input with a simple standalone RSG-compatible function
function AdvancedInput(inputSpec)
    local header = ""
    local default = ""
    local pattern = nil
    if inputSpec and inputSpec.attributes then
        header = inputSpec.attributes.inputHeader or header
        default = inputSpec.attributes.value or default
        pattern = inputSpec.attributes.pattern or pattern
    end

    -- Onscreen keyboard for RSG Core (same as before)
    AddTextEntry("RPOKER_INPUT_PROMPT", header or "Input")
    DisplayOnscreenKeyboard(1, "RPOKER_INPUT_PROMPT", "", tostring(default or ""), "", "", "", 128)

    while true do
        local status = UpdateOnscreenKeyboard()
        if status == 1 then
            local result = GetOnscreenKeyboardResult()
            if pattern and result then
                local passed = true
                if string.find(pattern, "A%-Za%-z") or string.find(pattern, "A-Za-z") or string.find(pattern, "[A-Za-z]") then
                    if not string.match(result, "^[A-Za-z]+$") then passed = false end
                elseif string.find(pattern, "0%-9") or string.find(pattern, "[0-9]") then
                    if not string.match(result, "^[0-9]+$") then passed = false end
                end
                if not passed then
                    lib.notify({ title = 'Poker', description = inputSpec.attributes.title or "Ugyldig inndata", type = 'error' })
                    --TriggerEvent('RSGCore:Notify', inputSpec.attributes.title or "Invalid input", "error")
                    return nil
                end
            end
            return result
        elseif status == 2 then
            return nil
        end
        Wait(0)
    end
end


-- ===== Notification compatibility shim for client usage (if anything else calls VORPcore.NotifyRightTip clientside) =====
function NotifyClient(message, duration)
    -- Many RSG setups provide a client event; try a common one
    -- If your server uses a different notify event, change below.
    lib.notify({ title = 'Poker', description = message, type = 'success' })
    --TriggerEvent('RSGCore:Notify', message, 'success') -- or 'error' as needed
end

-- ===== Begin: Your original client code (framework calls adjusted) =====

local PromptGroupInGame
local PromptGroupInGameLeave
local PromptGroupTable
local PromptGroupFinalize
local PromptCall
local PromptRaise
local PromptCheck
local PromptFold
local PromptCycleAmount
local PromptStart
local PromptJoin
local PromptBegin
local PromptCancel
local PromptLeave

local characterName = false

isInGame = false
game = nil

local locations = {}
local isNearTable = false
local nearTableLocationIndex

local turnRaiseAmount = 1
local turnBaseRaiseAmount = 1
local isPlayerOccupied = false
local hasLeft = false


if Config.DebugCommands then
    RegisterCommand("pokerv", function(source, args, rawCommand)
        TriggerServerEvent("rainbow_poker:Server:Command:pokerv", args)
    end, false)

    RegisterCommand("debug:pokerDeck", function(source, args, rawCommand)
        TriggerServerEvent("rainbow_poker:Server:Command:Debug:PokerDeck", args)
    end, false)
end


-------- THREADS

-- Performance
Citizen.CreateThread(function()
    Citizen.Wait(1000)
    while true do
        local playerPedId = PlayerPedId()
        if playerPedId then

            isPlayerOccupied = false

        end
        Wait(200)
    end
end)

-- Check if near table
CreateThread(function()
    TriggerServerEvent("rainbow_poker:Server:RequestUpdatePokerTables")
    while true do
        local sleep = 1000
        if not isInGame and not isPlayerOccupied then
            local playerPedId = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPedId)
            local isCurrentlyNearTable = false
            for k,location in pairs(locations) do
                if #(playerCoords - location.tableCoords) < Config.TableDistance then
                    sleep = 250
                    isCurrentlyNearTable = true
                    nearTableLocationIndex = k
                end
            end
            isNearTable = isCurrentlyNearTable
        end
        Wait(sleep)
    end
end)

-- Join game prompts
CreateThread(function()
    PromptGroupTable = RSGPrompts:SetupPromptGroup()
    PromptStart = PromptGroupTable:RegisterPrompt("Start Pokerspill 1$", GetHashKey(Config.Keys.StartGame), 1, 1, true, "hold", {timedeventhash = "MEDIUM_TIMED_EVENT"})
    PromptJoin = PromptGroupTable:RegisterPrompt("Bli med på poker 1$", GetHashKey(Config.Keys.JoinGame), 1, 1, true, "hold", {timedeventhash = "MEDIUM_TIMED_EVENT"})

    while true do
        local sleep = 1000

        PromptJoin:TogglePrompt(false)
        PromptStart:TogglePrompt(false)

        if not isInGame and isNearTable and nearTableLocationIndex and not isPlayerOccupied then
            if characterName == false then
                characterName = ""
                TriggerServerEvent("rainbow_poker:Server:RequestCharacterName")
            end

            local location = locations[nearTableLocationIndex]
            if location.state ~= LOCATION_STATES.GAME_IN_PROGRESS then
                sleep = 1

                -- Join
                if location.state == LOCATION_STATES.PENDING_GAME and location.pendingGame.initiatorNetId ~= GetPlayerServerId(PlayerId()) then
                    local hasPlayerAlreadyJoined = false
                    for k,v in pairs(location.pendingGame.players) do
                        if v.netId == GetPlayerServerId(PlayerId()) then
                            hasPlayerAlreadyJoined = true
                        end
                    end

                    if not hasPlayerAlreadyJoined then
                        PromptJoin:TogglePrompt(true)
                        if location.pendingGame and location.pendingGame.ante then
                            PromptSetText(PromptJoin.Prompt, CreateVarString(10, "LITERAL_STRING", "Bli med i spill  |  Sats: ~o~$"..location.pendingGame.ante.." ", "Title"))
                        end
                    end

                -- Start
                elseif location.state == LOCATION_STATES.EMPTY then
                    PromptStart:TogglePrompt(true)
                end

                PromptGroupTable:ShowGroup("Poker bord")

                -- START
                if PromptStart:HasCompleted() then
                    local playersChosenName
                    if Config.DebugOptions.SkipStartGameOptions then
                        playersChosenName = "foo"
                    else
                        local playersChosenNameInput = {
                            type = "enableinput",
                            inputType = "input",
                            button = "Confirm",
                            placeholder = "",
                            style = "block",
                            attributes = {
                                inputHeader = "Ditt navn",
                                type = "text",
                                pattern = "[A-Za-z]+",
                                title = "Letters only (no spaces or quotes)",
                                style = "border-radius: 10px; background-color: ; border:none;",
                                value = characterName,
                            }
                        }
                        playersChosenName = AdvancedInput(playersChosenNameInput)
                        TriggerServerEvent("grabpokerdaler")
                    end

                    if not playersChosenName or playersChosenName=="" then
                        lib.notify({ title = 'Poker', description = "Du må skrive inn et navn.", type = 'error' })
                        --TriggerEvent('RSGCore:Notify', "You must enter a name.", 'error')
                    elseif string.len(playersChosenName) < 3 then
                        lib.notify({ title = 'Poker', description = "Navnet ditt må være minst 3 bokstaver langt.", type = 'error' })
                        --TriggerEvent('RSGCore:Notify', "Your name must be at least 3 letters long.", 'error')
                    else
                        Wait(100)
                        local anteAmount
                        if Config.DebugOptions.SkipStartGameOptions then
                            anteAmount = 5
                        else
                            local anteAmountInput = {
                                type = "enableinput",
                                inputType = "input",
                                button = "Confirm",
                                placeholder = "5",
                                style = "block",
                                attributes = {
                                    inputHeader = "Sats",
                                    type = "text",
                                    pattern = "[0-9]+",
                                    title = "Numbers only",
                                    style = "border-radius: 10px; background-color: ; border:none;"
                                }
                            }
                            anteAmount = AdvancedInput(anteAmountInput)
                        end

                        if not anteAmount or anteAmount=="" then
                            lib.notify({ title = 'Poker', description = "Du må angi et annet beløp", type = 'error' })
                            --TriggerEvent('RSGCore:Notify', "Du må angi et antebeløp.", 'error')
                        elseif tonumber(anteAmount) < 1 then
                            lib.notify({ title = 'Poker', description = "Du må angi et antebeløp mins $1", type = 'error' })
                            --TriggerEvent('RSGCore:Notify', "The ante amount must be at least $1.", 'error')
                        else
                            TriggerServerEvent("rainbow_poker:Server:StartNewPendingGame", playersChosenName, anteAmount, nearTableLocationIndex)
                        end
                    end

                    Wait(3 * 1000)
                end

                -- JOIN
                if PromptJoin:HasCompleted() then
                    local playersChosenNameInput = {
                        type = "enableinput",
                        inputType = "input",
                        button = "Confirm",
                        placeholder = "",
                        style = "block",
                        attributes = {
                            inputHeader = "Ditt navn",
                            type = "text",
                            pattern = "[A-Za-z]+",
                            title = "Letters only",
                            style = "border-radius: 10px; background-color: ; border:none;",
                            value = characterName,
                        }
                    }
                    playersChosenName = AdvancedInput(playersChosenNameInput)

                    TriggerServerEvent("rainbow_poker:Server:JoinGame", playersChosenName, nearTableLocationIndex)
                    TriggerServerEvent("grabpokerdaler")
                    Wait(3 * 1000)
                end
            end
        end
        Wait(sleep)
    end
end)

-- Begin game prompt
CreateThread(function()
    PromptGroupFinalize = RSGPrompts:SetupPromptGroup()
    PromptBegin = PromptGroupFinalize:RegisterPrompt("Start Poker", GetHashKey(Config.Keys.BeginGame), 1, 1, true, "hold", {timedeventhash = "MEDIUM_TIMED_EVENT"})
    PromptCancel = PromptGroupFinalize:RegisterPrompt("Avbryt", GetHashKey(Config.Keys.CancelGame), 1, 1, true, "hold", {timedeventhash = "MEDIUM_TIMED_EVENT"})

    while true do
        local sleep = 1000
        if not isInGame and isNearTable and nearTableLocationIndex and locations[nearTableLocationIndex] and not isPlayerOccupied then
            sleep = 1
            local location = locations[nearTableLocationIndex]

            if location.state == LOCATION_STATES.PENDING_GAME and location.pendingGame.initiatorNetId == GetPlayerServerId(PlayerId()) then
                PromptSetText(PromptBegin.Prompt, CreateVarString(10, "LITERAL_STRING", "Start spillet  |  Spillere: ~o~" .. #location.pendingGame.players .. " ", "Title"))
                PromptSetPriority(PromptBegin.Prompt, 3)
                PromptGroupFinalize:ShowGroup("Poker Bord")

                -- BEGIN (FINALIZED)
                if PromptBegin:HasCompleted() then
                    TriggerServerEvent("rainbow_poker:Server:FinalizePendingGameAndBegin", nearTableLocationIndex)
                end

                -- CANCEL
                if PromptCancel:HasCompleted() then
                    TriggerServerEvent("rainbow_poker:Server:CancelPendingGame", nearTableLocationIndex)
                end
            end
        end
        Wait(sleep)
    end
end)

-- In-game prompts
CreateThread(function()
    PromptGroupInGame = RSGPrompts:SetupPromptGroup()
    PromptCall = PromptGroupInGame:RegisterPrompt("Call (Match)", GetHashKey(Config.Keys.ActionCall), 1, 1, true, "click", {})
    PromptRaise = PromptGroupInGame:RegisterPrompt("Øk med $1", GetHashKey(Config.Keys.ActionRaise), 1, 1, true, "click", {})
    PromptCheck = PromptGroupInGame:RegisterPrompt("Check", GetHashKey(Config.Keys.ActionCheck), 1, 1, true, "click", {})
    PromptFold = PromptGroupInGame:RegisterPrompt("Kast deg", GetHashKey(Config.Keys.ActionFold), 1, 1, true, "hold", {timedeventhash = "MEDIUM_TIMED_EVENT"})
    PromptCycleAmount = PromptGroupInGame:RegisterPrompt("Endre beløp", GetHashKey(Config.Keys.SubactionCycleAmount), 1, 1, true, "click", {})

    PromptGroupInGameLeave = RSGPrompts:SetupPromptGroup()
    PromptLeave = PromptGroupInGameLeave:RegisterPrompt("Forlat spillet", GetHashKey(Config.Keys.LeaveGame), 1, 1, true, "hold", {timedeventhash = "MEDIUM_TIMED_EVENT"})

    while true do
        local sleep = 1000
        if isInGame and game and game.step ~= ROUNDS.PENDING and game.step ~= ROUNDS.SHOWDOWN then
            sleep = 0

            -- Block inputs
            DisableAllControlActions(0)
            EnableControlAction(0, GetHashKey(Config.Keys.ActionCall))
            EnableControlAction(0, GetHashKey(Config.Keys.ActionRaise))
            EnableControlAction(0, GetHashKey(Config.Keys.ActionCheck))
            EnableControlAction(0, GetHashKey(Config.Keys.ActionFold))
            EnableControlAction(0, GetHashKey(Config.Keys.SubactionCycleAmount))
            EnableControlAction(0, GetHashKey(Config.Keys.LeaveGame))
            EnableControlAction(0, 0x4BC9DABB, true) -- Enable push-to-talk
            EnableControlAction(0, 0xF3830D8E, true) -- Enable J for jugular
            EnableControlAction(0, `INPUT_LOOK_UD`, true)
            EnableControlAction(0, `INPUT_LOOK_LR`, true)
            EnableControlAction(0, `INPUT_CREATOR_RT`, true)

            -- Check if it's their turn
            local thisPlayer = findThisPlayerFromGameTable(game)

            if game["currentTurn"] == thisPlayer["order"] then
                if not thisPlayer.hasFolded then
                    PromptSetText(PromptRaise.Prompt, CreateVarString(10, "LITERAL_STRING", string.format("Høyne sats $%d | (~o~$%d~s~)", turnRaiseAmount, game.currentGoingBet + turnRaiseAmount), "Title"))
                    PromptSetText(PromptCall.Prompt, CreateVarString(10, "LITERAL_STRING", string.format("Call | (~o~$%d~s~)", (game.roundsHighestBet - thisPlayer.amountBetInRound)), "Title"))

                    if game.roundsHighestBet and game.roundsHighestBet > 0 then
                        PromptCheck:TogglePrompt(false)
                        PromptSetEnabled(PromptCheck.Prompt, false)
                        PromptCall:TogglePrompt(true)
                        PromptSetEnabled(PromptCall.Prompt, true)
                    else
                        PromptCheck:TogglePrompt(true)
                        PromptSetEnabled(PromptCheck.Prompt, true)
                        PromptCall:TogglePrompt(false)
                        PromptSetEnabled(PromptCall.Prompt, false)
                    end

                    PromptGroupInGame:ShowGroup("Poker Spill")

                    if PromptCall:HasCompleted() then
                        if Config.DebugPrint then print("PromptCall") end
                        TriggerServerEvent("rainbow_poker:Server:PlayerActionCall")
                        TriggerEvent("rainbow_core:PlayAudioFile", Config.Audio.ChipDrop, Config.AudioVolume)
                        PlayAnimation("Bet")
                    end

                    if PromptRaise:HasCompleted() then
                        if Config.DebugPrint then print("PromptRaise") end
                        TriggerServerEvent("rainbow_poker:Server:PlayerActionRaise", turnRaiseAmount)
                        TriggerEvent("rainbow_core:PlayAudioFile", Config.Audio.ChipDrop, Config.AudioVolume)
                        PlayAnimation("Bet")
                    end

                    if PromptCheck:HasCompleted() then
                        if Config.DebugPrint then print("PromptCheck") end
                        TriggerServerEvent("rainbow_poker:Server:PlayerActionCheck")
                        PlayAnimation("Check")
                    end

                    if PromptFold:HasCompleted() then
                        if Config.DebugPrint then print("PromptFold") end
                        TriggerServerEvent("rainbow_poker:Server:PlayerActionFold")
                        PlayAnimation("Fold")
                        PlayAnimation("NoCards")
                    end

                    if PromptCycleAmount:HasCompleted() then
                        if Config.DebugPrint then print("PromptCycleAmount") end
                        if turnRaiseAmount == turnBaseRaiseAmount then
                            turnRaiseAmount = turnBaseRaiseAmount * 2
                        elseif turnRaiseAmount == turnBaseRaiseAmount * 2 then
                            turnRaiseAmount = turnBaseRaiseAmount * 4
                        elseif turnRaiseAmount == turnBaseRaiseAmount * 4 then
                            turnRaiseAmount = turnBaseRaiseAmount * 8
                        elseif turnRaiseAmount == turnBaseRaiseAmount * 8 then
                            turnRaiseAmount = turnBaseRaiseAmount
                        end
                        TriggerEvent("rainbow_core:PlayAudioFile", Config.Audio.ChipTap, Config.AudioVolume)
                    end
                end
            else
                -- It's not their turn
                if thisPlayer.hasFolded then
                    PromptSetEnabled(PromptLeave.Prompt, true)
                    PromptLeave:TogglePrompt(true)

                    PromptGroupInGameLeave:ShowGroup("Poker Spill")

                    if PromptLeave:HasCompleted() then
                        if Config.DebugPrint then print("PromptLeave") end
                        TriggerServerEvent("rainbow_poker:Server:PlayerLeave")
                        Wait(1000)
                    end
                end
            end
        elseif isInGame and game and game.step == ROUNDS.SHOWDOWN then
            sleep = 0
            PromptSetEnabled(PromptLeave.Prompt, true)
            PromptLeave:TogglePrompt(true)
            PromptGroupInGameLeave:ShowGroup("Poker Spill")

            if PromptLeave:HasCompleted() then
                if Config.DebugPrint then print("PromptLeave") end
                TriggerServerEvent("rainbow_poker:Server:PlayerLeave")
                Wait(1000)
            end
        end
        Wait(sleep)
    end
end)

-- Check for deaths (or other "occupying" things)
CreateThread(function()
    while true do
        local sleep = 1000
        if isInGame and game and isPlayerOccupied then
            if Config.DebugPrint then print("became occupied mid-game") end
            TriggerServerEvent("rainbow_poker:Server:PlayerActionFold")
            turnRaiseAmount = 1
            Wait(200)
            TriggerServerEvent("rainbow_poker:Server:PlayerLeave")
            sleep = 10 * 1000
        end
        Wait(sleep)
    end
end)


-------- EVENTS

RegisterNetEvent("rainbow_poker:Client:ReturnRequestCharacterName")
AddEventHandler("rainbow_poker:Client:ReturnRequestCharacterName", function(_name)
    if Config.DebugPrint then print("rainbow_poker:Client:ReturnRequestCharacterName", _name) end
    characterName = _name
end)

RegisterNetEvent("rainbow_poker:Client:ReturnJoinGame")
AddEventHandler("rainbow_poker:Client:ReturnJoinGame", function(locationIndex, player)
    if Config.DebugPrint then print("rainbow_poker:Client:ReturnJoinGame", locationIndex, player) end
    local locationId = locations[locationIndex].id
    startChairScenario(locationId, player.order)
end)

RegisterNetEvent("rainbow_poker:Client:ReturnStartNewPendingGame")
AddEventHandler("rainbow_poker:Client:ReturnStartNewPendingGame", function(locationIndex, player)
    if Config.DebugPrint then print("rainbow_poker:Client:ReturnStartNewPendingGame", locationIndex, player) end
    local locationId = locations[locationIndex].id
    startChairScenario(locationId, player.order)
end)

RegisterNetEvent("rainbow_poker:Client:CancelPendingGame")
AddEventHandler("rainbow_poker:Client:CancelPendingGame", function(locationIndex)
    if Config.DebugPrint then print("rainbow_poker:Client:CancelPendingGame", locationIndex) end
    clearPedTaskAndUnfreeze(true)
end)

RegisterNetEvent("rainbow_poker:Client:StartGame")
AddEventHandler("rainbow_poker:Client:StartGame", function(_game, playerSeatOrder)
    if Config.DebugPrint then print("rainbow_poker:Client:StartGame", _game, playerSeatOrder) end
    game = _game
    UI:StartGame(game)
    isInGame = true
    local locationId = locations[nearTableLocationIndex].id
    startChairScenario(locationId, playerSeatOrder)
    TriggerEvent("rainbow_core:PlayAudioFile", Config.Audio.CardsDeal, Config.AudioVolume)
    PlayAnimation("HoldCards")
end)

RegisterNetEvent("rainbow_poker:Client:UpdatePokerTables")
AddEventHandler("rainbow_poker:Client:UpdatePokerTables", function(_locations)
    if Config.DebugPrint then print("rainbow_poker:Client:UpdatePokerTables", _locations) end
    locations = _locations
end)

RegisterNetEvent("rainbow_poker:Client:TriggerUpdate")
AddEventHandler("rainbow_poker:Client:TriggerUpdate", function(_game)
    if Config.DebugPrintUnsafe then print("rainbow_poker:Client:TriggerUpdate", _game) end
    UI:UpdateGame(_game)
    game = _game
    if _game.currentGoingBet and _game.currentGoingBet > 1 then
        turnBaseRaiseAmount = _game.currentGoingBet
    else
        turnBaseRaiseAmount = 1
    end
    turnRaiseAmount = turnBaseRaiseAmount
end)

RegisterNetEvent("rainbow_poker:Client:ReturnPlayerLeave")
AddEventHandler("rainbow_poker:Client:ReturnPlayerLeave", function(locationIndex, player)
    if Config.DebugPrint then print("rainbow_poker:Client:ReturnPlayerLeave") end
    hasLeft = true
    UI:CloseAll()
    clearPedTaskAndUnfreeze(true)
end)

RegisterNetEvent("rainbow_poker:Client:WarnTurnTimer")
AddEventHandler("rainbow_poker:Client:WarnTurnTimer", function(locationIndex, player)
    if Config.DebugPrint then print("rainbow_poker:Client:WarnTurnTimer") end
    local timeRemaining = Config.TurnTimeoutWarningInSeconds
    lib.notify({ title = 'Poker', description = "ADVARSEL: Ta handling nå. Mindre enn %d sekunder igjen. "..timeRemaining, type = 'error' })
    --TriggerEvent('RSGCore:Notify', string.format("WARNING: Take action now. Less than %d seconds remaining.", timeRemaining), 'error')
    TriggerEvent("rainbow_core:PlayAudioFile", Config.Audio.TurnTimerWarn, Config.AudioVolume)
end)

RegisterNetEvent("rainbow_poker:Client:AlertWin")
AddEventHandler("rainbow_poker:Client:AlertWin", function(_winScenario)
    if Config.DebugPrint then print("rainbow_poker:Client:AlertWin", _winScenario) end
    if hasLeft == false then
        UI:AlertWinScenario(_winScenario)
    end
end)

RegisterNetEvent("rainbow_poker:Client:CleanupFinishedGame")
AddEventHandler("rainbow_poker:Client:CleanupFinishedGame", function()
    if Config.DebugPrint then print("rainbow_poker:Client:CleanupFinishedGame") end
    UI:CloseAll()
    if hasLeft == false then
        clearPedTaskAndUnfreeze(true)
    end
    game = nil
    isInGame = false
    hasLeft = false
end)


-------- FUNCTIONS

function PlayAnimation(animationId)
    if hasLeft then return end
    math.randomseed(GetGameTimer())
    local animationArray = Config.Animations[animationId]
    local randomAnimationIndex = math.random(1, #animationArray)
    local animation = animationArray[randomAnimationIndex]
    if Config.DebugPrint then print("PlayAnimation - animation", animation) end
    RequestAnimDict(animation.Dict)
    while not HasAnimDictLoaded(animation.Dict) do
        Wait(100)
    end
    local playerPedId = PlayerPedId()
    local length = 0
    if animation.isIdle then
        length = -1
    elseif animation.Length then
        length = animation.Length
    else
        length = 4000
    end
    local blendIn = 8.0
    local blendOut = 1.0
    if animation.isIdle then
        blendIn = 1.0
        blendOut = 1.0
    end
    FreezeEntityPosition(playerPedId, true)
    TaskPlayAnim(playerPedId, animation.Dict, animation.Name, blendIn, blendOut, length, 25, 1.0, true, 0, false, 0, false)
    if length and length > 0 then
        Wait(length)
        PlayBestIdleAnimation()
    end
end

function PlayBestIdleAnimation()
    if Config.DebugPrint then print("PlayBestIdleAnimation") end
    local player
    for k,v in pairs(game.players) do
        if v.netId == GetPlayerServerId(PlayerId()) then
            player = v
            break
        end
    end
    if game.step == ROUNDS.SHOWDOWN or (player and player.hasFolded) then
        PlayAnimation("NoCards")
    else
        PlayAnimation("HoldCards")
    end
end

function startChairScenario(locationId, chairNumber)
    if Config.DebugPrint then print("startChairScenario", locationId, chairNumber) end
    local configTable = Config.Locations[locationId]
    local chairVector = configTable.Chairs[chairNumber].Coords
    if Config.DebugPrint then print("startChairScenario - chairVector", chairVector) end
    ClearPedTasksImmediately(PlayerPedId())
    FreezeEntityPosition(PlayerPedId(), true)
    TaskStartScenarioAtPosition(PlayerPedId(), GetHashKey("GENERIC_SEAT_CHAIR_TABLE_SCENARIO"), chairVector.x, chairVector.y, chairVector.z, chairVector.w, -1, false, true)
end

function findThisPlayerFromGameTable(_game)
    for k,playerTable in pairs(_game.players) do
        if playerTable.netId == GetPlayerServerId(PlayerId()) then
            return playerTable
        end
    end
end

function clearPedTaskAndUnfreeze(isSmooth)
    local playerPedId = PlayerPedId()
    FreezeEntityPosition(playerPedId, false)
    ClearPedTasksImmediately(playerPedId)
end

RegisterNetEvent("rainbow_core:PlayAudioFile")
AddEventHandler("rainbow_core:PlayAudioFile", function(audioFileName, volume)
	local volume = volume or 0.3
	SendNUIMessage({
		type= "playAudio",
		audioFileName = audioFileName,
		volume = volume,
	})
end)

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() == resourceName then
        isInGame = false
        game = nil
        isNearTable = false
        nearTableLocationIndex = nil
        locations = {}
        hasLeft = false
        clearPedTaskAndUnfreeze(false)
    end
end)
