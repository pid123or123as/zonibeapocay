local AutoAFK = {}

-- Сервисы
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Inventory = LocalPlayer:WaitForChild("Inventory")
local Toolbar = LocalPlayer:WaitForChild("Toolbar")
local Data = LocalPlayer:WaitForChild("Data")
local Items = ReplicatedStorage:WaitForChild("Items")
local Network = ReplicatedStorage:WaitForChild("Network")
local ItemsFolder = Network:WaitForChild("Items")
local MoveItem = ItemsFolder:WaitForChild("MoveItem")
local EquipItem = ItemsFolder:WaitForChild("EquipItem")
local SwapItems = ItemsFolder:WaitForChild("SwapItems")
local Consume = ItemsFolder:WaitForChild("Consume")

-- Конфигурация
local Config = {
    AutoEat = {
        Enabled = false,
        HungerThreshold = 50,
        ThirstThreshold = 50,
        CheckInterval = 2,
        Priority = "Both",
        UseBestItem = true,
        SwapWhenFull = true
    }
}

-- Кэш предметов
local ItemCache = {}
local FoodItems = {}
local notify = print

-- Получение конфигурации еды
local function getFoodConfig(itemName)
    if ItemCache[itemName] then
        return ItemCache[itemName]
    end
    
    local itemModel = Items:FindFirstChild(itemName)
    if not itemModel then
        ItemCache[itemName] = nil
        return nil
    end
    
    local configModule = itemModel:FindFirstChild("Config")
    if configModule and configModule:IsA("ModuleScript") then
        local success, configTable = pcall(require, configModule)
        if success and configTable and configTable.class == "consumable" then
            local foodConfigModule = itemModel:FindFirstChild("FoodConfig")
            if foodConfigModule and foodConfigModule:IsA("ModuleScript") then
                local success2, foodConfig = pcall(require, foodConfigModule)
                if success2 and foodConfig then
                    ItemCache[itemName] = {
                        class = "consumable",
                        foodConfig = foodConfig
                    }
                    return ItemCache[itemName]
                end
            end
        end
    end
    
    ItemCache[itemName] = nil
    return nil
end

-- Сбор информации о доступной еде
local function scanFoodItems()
    FoodItems = {}
    
    -- Сканируем инвентарь
    for _, itemFolder in ipairs(Inventory:GetChildren()) do
        local foodConfig = getFoodConfig(itemFolder.Name)
        if foodConfig then
            local countValue = itemFolder:FindFirstChild("Count")
            local count = countValue and countValue.Value or 1
            
            table.insert(FoodItems, {
                folder = itemFolder,
                name = itemFolder.Name,
                count = count,
                hunger = foodConfig.foodConfig.hunger or 0,
                thirst = foodConfig.foodConfig.thirst or 0,
                location = "Inventory",
                totalValue = (foodConfig.foodConfig.hunger or 0) + (foodConfig.foodConfig.thirst or 0)
            })
        end
    end
    
    -- Сканируем тулбар
    for _, itemFolder in ipairs(Toolbar:GetChildren()) do
        local foodConfig = getFoodConfig(itemFolder.Name)
        if foodConfig then
            local countValue = itemFolder:FindFirstChild("Count")
            local count = countValue and countValue.Value or 1
            local indexValue = itemFolder:FindFirstChild("Index")
            local slot = indexValue and indexValue.Value or nil
            
            table.insert(FoodItems, {
                folder = itemFolder,
                name = itemFolder.Name,
                count = count,
                hunger = foodConfig.foodConfig.hunger or 0,
                thirst = foodConfig.foodConfig.thirst or 0,
                location = "Toolbar",
                slot = slot,
                totalValue = (foodConfig.foodConfig.hunger or 0) + (foodConfig.foodConfig.thirst or 0)
            })
        end
    end
end

-- Поиск свободного слота в тулбаре
local function findFreeToolbarSlot()
    for slot = 1, 9 do
        local occupied = false
        for _, itemFolder in ipairs(Toolbar:GetChildren()) do
            local indexValue = itemFolder:FindFirstChild("Index")
            if indexValue and indexValue.Value == slot then
                occupied = true
                break
            end
        end
        if not occupied then
            return slot
        end
    end
    return nil
end

-- Найти предмет в слоте 9 (последний слот)
local function findItemInSlot9()
    for _, itemFolder in ipairs(Toolbar:GetChildren()) do
        local indexValue = itemFolder:FindFirstChild("Index")
        if indexValue and indexValue.Value == 9 then
            return itemFolder
        end
    end
    return nil
end

-- Замена предмета в слоте 9
local function swapWithSlot9(foodItem)
    if not foodItem then
        return false
    end
    
    local slot9Item = findItemInSlot9()
    if not slot9Item then
        return false
    end
    
    local args = {
        [1] = foodItem.folder,
        [2] = slot9Item
    }
    
    SwapItems:FireServer(unpack(args))
    return true
end

-- Интеллектуальный выбор лучшей еды для текущих потребностей
local function selectBestFoodForCurrentNeeds()
    local hunger = Data.Hunger.Value
    local thirst = Data.Thirst.Value
    
    local needHunger = hunger < Config.AutoEat.HungerThreshold
    local needThirst = thirst < Config.AutoEat.ThirstThreshold
    
    if not needHunger and not needThirst then
        return nil
    end
    
    local bestItem = nil
    local bestScore = -math.huge
    local hungerDeficit = Config.AutoEat.HungerThreshold - hunger
    local thirstDeficit = Config.AutoEat.ThirstThreshold - thirst
    
    for _, food in ipairs(FoodItems) do
        if food.count > 0 then
            local score = 0
            local hungerRestored = math.min(food.hunger, hungerDeficit)
            local thirstRestored = math.min(food.thirst, thirstDeficit)
            
            if Config.AutoEat.Priority == "Hunger" then
                if needHunger then
                    score = hungerRestored * 2
                    if needThirst then
                        score = score + thirstRestored * 0.5
                    end
                elseif needThirst then
                    score = thirstRestored
                end
            elseif Config.AutoEat.Priority == "Thirst" then
                if needThirst then
                    score = thirstRestored * 2
                    if needHunger then
                        score = score + hungerRestored * 0.5
                    end
                elseif needHunger then
                    score = hungerRestored
                end
            else -- "Both"
                if needHunger and needThirst then
                    local totalDeficit = hungerDeficit + thirstDeficit
                    local hungerWeight = totalDeficit > 0 and (hungerDeficit / totalDeficit) or 0.5
                    local thirstWeight = totalDeficit > 0 and (thirstDeficit / totalDeficit) or 0.5
                    
                    score = (hungerRestored * hungerWeight * 2) + 
                            (thirstRestored * thirstWeight * 2)
                elseif needHunger then
                    score = hungerRestored * 2
                elseif needThirst then
                    score = thirstRestored * 2
                end
            end
            
            -- Бонус за эффективность
            if hungerRestored >= hungerDeficit and needHunger then
                score = score + 5
            end
            if thirstRestored >= thirstDeficit and needThirst then
                score = score + 5
            end
            
            -- Бонус если уже в тулбаре
            if food.location == "Toolbar" then
                score = score * 1.2
            end
            
            if score > bestScore then
                bestScore = score
                bestItem = food
            end
        end
    end
    
    return bestItem
end

-- Использование еды
local function useFood(foodItem)
    if not foodItem then 
        return false 
    end
    
    if foodItem.location == "Inventory" then
        local freeSlot = findFreeToolbarSlot()
        
        if freeSlot then
            -- Перемещаем в свободный слот
            local args = {
                [1] = foodItem.folder,
                [2] = "Toolbar",
                [3] = freeSlot
            }
            
            MoveItem:FireServer(unpack(args))
            wait(0.2)
            
            -- Экипируем
            local equipArgs = {[1] = freeSlot}
            EquipItem:FireServer(unpack(equipArgs))
            wait(0.1)
            
            -- Используем
            Consume:FireServer()
            return true
        elseif Config.AutoEat.SwapWhenFull then
            -- Заменяем предмет в слоте 9
            if swapWithSlot9(foodItem) then
                wait(0.3)
                
                -- Экипируем новый предмет (всегда слот 9)
                local equipArgs = {[1] = 9}
                EquipItem:FireServer(unpack(equipArgs))
                wait(0.1)
                
                -- Используем
                Consume:FireServer()
                return true
            else
                return false
            end
        else
            return false
        end
    else -- Уже в тулбаре
        if foodItem.slot then
            -- Экипируем
            local equipArgs = {[1] = foodItem.slot}
            EquipItem:FireServer(unpack(equipArgs))
            wait(0.1)
            
            -- Используем
            Consume:FireServer()
            return true
        end
    end
    
    return false
end

-- Основная функция авто-питания
local function autoEat()
    if not Config.AutoEat.Enabled then return end
    if not LocalPlayer.Character then return end
    
    scanFoodItems()
    
    if #FoodItems == 0 then
        return
    end
    
    local bestFood = selectBestFoodForCurrentNeeds()
    
    if bestFood then
        local used = useFood(bestFood)
        if used then
            -- Без notify, так как это автоматическое действие
        end
    end
end

-- Тестовая функция (для кнопки)
local function testEat()
    scanFoodItems()
    
    if #FoodItems == 0 then
        notify("AutoAFK", "No food in inventory!", false)
        return
    end
    
    local testFood = FoodItems[1]
    local used = useFood(testFood)
    
    if used then
        notify("AutoAFK", "Test: used " .. testFood.name, false)
    else
        notify("AutoAFK", "Test: failed to use item", false)
    end
end

-- Основной цикл
local function mainLoop()
    while true do
        if Config.AutoEat.Enabled then
            autoEat()
        end
        wait(Config.AutoEat.CheckInterval)
    end
end

-- Инициализация UI
local function initializeUI(UI)
    if UI.Tabs and UI.Tabs.Main then
        local afkSection = UI.Tabs.Main:Section({Name = "AutoAFK", Side = "Left"})
        
        afkSection:Header({Name = "AutoEat"})
        
        local infoLabel = afkSection:SubLabel({Text = "Loading data..."})
        
        -- Toggle с notify
        afkSection:Toggle({
            Name = "Enabled",
            Default = Config.AutoEat.Enabled,
            Callback = function(value)
                Config.AutoEat.Enabled = value
                notify("AutoAFK", "AutoEat " .. (value and "Enabled" or "Disabled"), true)
            end
        })
        
        -- Slider без notify при изменении
        afkSection:Slider({
            Name = "Hunger Threshold",
            Minimum = 0,
            Maximum = 100,
            DisplayMethod = 'Percent',
            Default = Config.AutoEat.HungerThreshold,
            Precision = 0,
            Callback = function(value)
                Config.AutoEat.HungerThreshold = value
            end
        })
        
        afkSection:Slider({
            Name = "Thirst Threshold",
            Minimum = 0,
            Maximum = 100,
            DisplayMethod = 'Percent',
            Default = Config.AutoEat.ThirstThreshold,
            Precision = 0,
            Callback = function(value)
                Config.AutoEat.ThirstThreshold = value
            end
        })
        
        afkSection:Slider({
            Name = "Check Interval (sec)",
            Minimum = 1,
            Maximum = 10,
            Default = Config.AutoEat.CheckInterval,
            Precision = 1,
            Callback = function(value)
                Config.AutoEat.CheckInterval = value
            end
        })
        
        afkSection:Dropdown({
            Name = "Priority",
            Default = Config.AutoEat.Priority,
            Options = {"Both", "Hunger", "Thirst"},
            Callback = function(value)
                Config.AutoEat.Priority = value
            end
        })
        
        -- Toggle с notify
        afkSection:Toggle({
            Name = "Use Best Item",
            Default = Config.AutoEat.UseBestItem,
            Callback = function(value)
                Config.AutoEat.UseBestItem = value
                notify("AutoAFK", "Best item selection " .. (value and "Enabled" or "Disabled"), true)
            end
        })
        
        -- Toggle с notify
        afkSection:Toggle({
            Name = "Swap When Toolbar Full",
            Default = Config.AutoEat.SwapWhenFull,
            Callback = function(value)
                Config.AutoEat.SwapWhenFull = value
                notify("AutoAFK", "Toolbar swap " .. (value and "Enabled" or "Disabled"), true)
            end
        })
        
        afkSection:Divider()
        
        afkSection:Button({
            Name = "Test Button",
            Callback = testEat
        })
        afkSection:SubLabel({Text = "Test food consumption"})
        
        -- Обновление информации
        local function updateInfo()
            if Data and Data.Hunger and Data.Thirst then
                local hungerStatus = Data.Hunger.Value < Config.AutoEat.HungerThreshold and "Low" or "OK"
                local thirstStatus = Data.Thirst.Value < Config.AutoEat.ThirstThreshold and "Low" or "OK"
                
                infoLabel:UpdateName(string.format("Hunger: %d/%d (%s) | Thirst: %d/%d (%s) | Food: %d", 
                    Data.Hunger.Value, Config.AutoEat.HungerThreshold, hungerStatus,
                    Data.Thirst.Value, Config.AutoEat.ThirstThreshold, thirstStatus,
                    #FoodItems))
            end
        end
        
        task.spawn(function()
            while true do
                updateInfo()
                wait(2)
            end
        end)
    end
end

-- Инициализация модуля
function AutoAFK.Init(UI, core, notifyFunc)
    notify = notifyFunc or print
    
    task.spawn(mainLoop)
    
    if UI then
        initializeUI(UI)
    end
    
    Inventory.ChildAdded:Connect(scanFoodItems)
    Inventory.ChildRemoved:Connect(scanFoodItems)
    Toolbar.ChildAdded:Connect(scanFoodItems)
    Toolbar.ChildRemoved:Connect(scanFoodItems)
    
    scanFoodItems()
    
    return AutoAFK
end

return AutoAFK
