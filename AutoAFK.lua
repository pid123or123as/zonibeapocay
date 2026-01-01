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
    },
    AutoHeal = {
        Enabled = false,
        HealthThreshold = 70,
        CheckInterval = 0.5, -- Быстрая проверка здоровья
        UseBestItem = true,
        FastHeal = true, -- Быстрое лечение
        SwapWhenFull = true
    }
}

-- Кэш предметов и состояний
local ItemCache = {}
local FoodItems = {}
local HealItems = {}
local notify = print
local IsHealingInProgress = false
local LastEquippedSlot = nil

-- Получение конфигурации consumable предметов
local function getConsumableConfig(itemName)
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
            local foodConfig = nil
            if foodConfigModule and foodConfigModule:IsA("ModuleScript") then
                local success2, foodConfigTable = pcall(require, foodConfigModule)
                if success2 and foodConfigTable then
                    foodConfig = foodConfigTable
                end
            end
            
            local waterConfigModule = itemModel:FindFirstChild("WaterConfig")
            local waterConfig = nil
            if waterConfigModule and waterConfigModule:IsA("ModuleScript") then
                local success3, waterConfigTable = pcall(require, waterConfigModule)
                if success3 and waterConfigTable then
                    waterConfig = waterConfigTable
                end
            end
            
            local consumableConfig = {
                hunger = 0,
                thirst = 0,
                health = 0,
                stamina = 0
            }
            
            if foodConfig then
                consumableConfig.hunger = foodConfig.hunger or 0
                consumableConfig.thirst = foodConfig.thirst or 0
                consumableConfig.health = foodConfig.health or 0
                consumableConfig.stamina = foodConfig.stamina or 0
            end
            
            if waterConfig then
                consumableConfig.thirst = waterConfig.thirst or 0
            end
            
            ItemCache[itemName] = {
                class = "consumable",
                config = consumableConfig
            }
            return ItemCache[itemName]
        end
    end
    
    ItemCache[itemName] = nil
    return nil
end

-- Проверяем, восстанавливает ли предмет голод или жажду
local function isHungerOrThirstItem(consumableConfig)
    if not consumableConfig or not consumableConfig.config then
        return false
    end
    
    local config = consumableConfig.config
    return (config.hunger or 0) > 0 or (config.thirst or 0) > 0
end

-- Проверяем, восстанавливает ли предмет здоровье
local function isHealItem(consumableConfig)
    if not consumableConfig or not consumableConfig.config then
        return false
    end
    
    local config = consumableConfig.config
    return (config.health or 0) > 0
end

-- Сбор информации о доступной еде и воде
local function scanFoodItems()
    FoodItems = {}
    
    for _, itemFolder in ipairs(Inventory:GetChildren()) do
        local consumableConfig = getConsumableConfig(itemFolder.Name)
        if consumableConfig and isHungerOrThirstItem(consumableConfig) then
            local countValue = itemFolder:FindFirstChild("Count")
            local count = countValue and countValue.Value or 1
            
            table.insert(FoodItems, {
                folder = itemFolder,
                name = itemFolder.Name,
                count = count,
                hunger = consumableConfig.config.hunger or 0,
                thirst = consumableConfig.config.thirst or 0,
                location = "Inventory",
                totalValue = (consumableConfig.config.hunger or 0) + (consumableConfig.config.thirst or 0)
            })
        end
    end
    
    for _, itemFolder in ipairs(Toolbar:GetChildren()) do
        local consumableConfig = getConsumableConfig(itemFolder.Name)
        if consumableConfig and isHungerOrThirstItem(consumableConfig) then
            local countValue = itemFolder:FindFirstChild("Count")
            local count = countValue and countValue.Value or 1
            local indexValue = itemFolder:FindFirstChild("Index")
            local slot = indexValue and indexValue.Value or nil
            
            table.insert(FoodItems, {
                folder = itemFolder,
                name = itemFolder.Name,
                count = count,
                hunger = consumableConfig.config.hunger or 0,
                thirst = consumableConfig.config.thirst or 0,
                location = "Toolbar",
                slot = slot,
                totalValue = (consumableConfig.config.hunger or 0) + (consumableConfig.config.thirst or 0)
            })
        end
    end
end

-- Сбор информации о лечебных предметах
local function scanHealItems()
    HealItems = {}
    
    for _, itemFolder in ipairs(Inventory:GetChildren()) do
        local consumableConfig = getConsumableConfig(itemFolder.Name)
        if consumableConfig and isHealItem(consumableConfig) then
            local countValue = itemFolder:FindFirstChild("Count")
            local count = countValue and countValue.Value or 1
            
            table.insert(HealItems, {
                folder = itemFolder,
                name = itemFolder.Name,
                count = count,
                health = consumableConfig.config.health or 0,
                location = "Inventory",
                healValue = consumableConfig.config.health or 0
            })
        end
    end
    
    for _, itemFolder in ipairs(Toolbar:GetChildren()) do
        local consumableConfig = getConsumableConfig(itemFolder.Name)
        if consumableConfig and isHealItem(consumableConfig) then
            local countValue = itemFolder:FindFirstChild("Count")
            local count = countValue and countValue.Value or 1
            local indexValue = itemFolder:FindFirstChild("Index")
            local slot = indexValue and indexValue.Value or nil
            
            table.insert(HealItems, {
                folder = itemFolder,
                name = itemFolder.Name,
                count = count,
                health = consumableConfig.config.health or 0,
                location = "Toolbar",
                slot = slot,
                healValue = consumableConfig.config.health or 0
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

-- Поиск свободного слота в инвентаре
local function findFreeInventorySlot()
    local inventorySize = Data.InventorySize and Data.InventorySize.Value or 30
    for slot = 1, inventorySize do
        local occupied = false
        for _, itemFolder in ipairs(Inventory:GetChildren()) do
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
local function swapWithSlot9(itemToUse)
    if not itemToUse then
        return false
    end
    
    local slot9Item = findItemInSlot9()
    if not slot9Item then
        return false
    end
    
    local args = {
        [1] = itemToUse.folder,
        [2] = slot9Item
    }
    
    SwapItems:FireServer(unpack(args))
    return true
end

-- Переместить предмет из тулбара в инвентарь
local function moveToInventory(itemFolder)
    if not itemFolder then
        return false
    end
    
    local freeSlot = findFreeInventorySlot()
    if not freeSlot then
        return false
    end
    
    local args = {
        [1] = itemFolder,
        [2] = "Inventory",
        [3] = freeSlot
    }
    
    MoveItem:FireServer(unpack(args))
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
    local hungerDeficit = math.max(0, Config.AutoEat.HungerThreshold - hunger)
    local thirstDeficit = math.max(0, Config.AutoEat.ThirstThreshold - thirst)
    
    for _, food in ipairs(FoodItems) do
        if food.count > 0 and (food.hunger > 0 or food.thirst > 0) then
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
            
            if hungerRestored >= hungerDeficit and needHunger and hungerDeficit > 0 then
                score = score + 5
            end
            if thirstRestored >= thirstDeficit and needThirst and thirstDeficit > 0 then
                score = score + 5
            end
            
            if food.location == "Toolbar" then
                score = score * 1.2
            end
            
            if food.count == 1 then
                score = score * 0.9
            end
            
            if score > bestScore then
                bestScore = score
                bestItem = food
            end
        end
    end
    
    return bestItem
end

-- Интеллектуальный выбор лучшего лечебного предмета (быстрый)
local function selectBestHealItem()
    local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return nil
    end
    
    local currentHealth = humanoid.Health
    local maxHealth = humanoid.MaxHealth
    
    if currentHealth >= maxHealth * (Config.AutoHeal.HealthThreshold / 100) then
        return nil
    end
    
    local healthDeficit = math.max(0, maxHealth * (Config.AutoHeal.HealthThreshold / 100) - currentHealth)
    
    local bestItem = nil
    local bestScore = -math.huge
    
    for _, healItem in ipairs(HealItems) do
        if healItem.count > 0 and healItem.health > 0 then
            local healthRestored = math.min(healItem.health, healthDeficit)
            local score = healthRestored * 2
            
            -- Приоритет для предметов в тулбаре для быстрого лечения
            if healItem.location == "Toolbar" then
                score = score * 2
            end
            
            -- Приоритет для предметов с большим лечением
            if healthRestored >= healthDeficit and healthDeficit > 0 then
                score = score + 20
            end
            
            if score > bestScore then
                bestScore = score
                bestItem = healItem
            end
        end
    end
    
    return bestItem
end

-- Использование еды/воды
local function useFood(foodItem)
    if not foodItem then 
        return false 
    end
    
    if foodItem.location == "Inventory" then
        local freeSlot = findFreeToolbarSlot()
        
        if freeSlot then
            local args = {
                [1] = foodItem.folder,
                [2] = "Toolbar",
                [3] = freeSlot
            }
            
            MoveItem:FireServer(unpack(args))
            wait(0.1)
            
            EquipItem:FireServer(freeSlot)
            wait(0.05)
            
            Consume:FireServer()
            wait(0.05)
            
            -- Возвращаем пустой слот
            EquipItem:FireServer(0)
            return true
        elseif Config.AutoEat.SwapWhenFull then
            if swapWithSlot9(foodItem) then
                wait(0.2)
                
                EquipItem:FireServer(9)
                wait(0.05)
                
                Consume:FireServer()
                wait(0.05)
                
                EquipItem:FireServer(0)
                return true
            else
                return false
            end
        else
            return false
        end
    else
        if foodItem.slot then
            EquipItem:FireServer(foodItem.slot)
            wait(0.05)
            
            Consume:FireServer()
            wait(0.05)
            
            EquipItem:FireServer(0)
            return true
        end
    end
    
    return false
end

-- Использование лечебного предмета (быстрое)
local function useHealItem(healItem)
    if not healItem or IsHealingInProgress then
        return false
    end
    
    IsHealingInProgress = true
    local success = false
    
    if healItem.location == "Inventory" then
        if Config.AutoHeal.FastHeal then
            -- Быстрое лечение: используем из инвентаря без перемещения в тулбар
            local freeSlot = findFreeToolbarSlot()
            
            if freeSlot then
                local args = {
                    [1] = healItem.folder,
                    [2] = "Toolbar",
                    [3] = freeSlot
                }
                
                MoveItem:FireServer(unpack(args))
                wait(0.1)
                
                EquipItem:FireServer(freeSlot)
                wait(0.05)
                
                Consume:FireServer()
                wait(0.05)
                
                -- Возвращаем пустой слот
                EquipItem:FireServer(0)
                
                -- Возвращаем предмет в инвентарь
                task.spawn(function()
                    wait(0.3)
                    moveToInventory(healItem.folder)
                end)
                
                success = true
            elseif Config.AutoHeal.SwapWhenFull then
                if swapWithSlot9(healItem) then
                    wait(0.2)
                    
                    EquipItem:FireServer(9)
                    wait(0.05)
                    
                    Consume:FireServer()
                    wait(0.05)
                    
                    EquipItem:FireServer(0)
                    
                    task.spawn(function()
                        wait(0.3)
                        moveToInventory(healItem.folder)
                    end)
                    
                    success = true
                end
            end
        end
    else
        if healItem.slot then
            EquipItem:FireServer(healItem.slot)
            wait(0.05)
            
            Consume:FireServer()
            wait(0.05)
            
            EquipItem:FireServer(0)
            success = true
        end
    end
    
    IsHealingInProgress = false
    return success
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
        useFood(bestFood)
    end
end

-- Основная функция авто-лечения (быстрая)
local function autoHeal()
    if not Config.AutoHeal.Enabled then return end
    if not LocalPlayer.Character then return end
    if IsHealingInProgress then return end
    
    local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    -- Быстрая проверка здоровья
    local currentHealth = humanoid.Health
    local maxHealth = humanoid.MaxHealth
    
    if currentHealth >= maxHealth * (Config.AutoHeal.HealthThreshold / 100) then
        return
    end
    
    -- Быстро сканируем предметы
    scanHealItems()
    
    if #HealItems == 0 then
        return
    end
    
    local bestHealItem = selectBestHealItem()
    
    if bestHealItem then
        useHealItem(bestHealItem)
    end
end

-- Тестовая функция для AutoEat
local function testEat()
    scanFoodItems()
    
    if #FoodItems == 0 then
        notify("AutoAFK", "No food or water in inventory!", false)
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

-- Тестовая функция для AutoHeal
local function testHeal()
    scanHealItems()
    
    if #HealItems == 0 then
        notify("AutoAFK", "No healing items in inventory!", false)
        return
    end
    
    local testHeal = HealItems[1]
    local used = useHealItem(testHeal)
    
    if used then
        notify("AutoAFK", "Test: used " .. testHeal.name, false)
    else
        notify("AutoAFK", "Test: failed to use healing item", false)
    end
end

-- Основной цикл
local function mainLoop()
    while true do
        if Config.AutoEat.Enabled then
            autoEat()
        end
        
        if Config.AutoHeal.Enabled then
            autoHeal()
        end
        
        wait(math.min(Config.AutoEat.CheckInterval, Config.AutoHeal.CheckInterval))
    end
end

-- Инициализация UI с отдельными секциями
local function initializeUI(UI)
    if UI.Tabs and UI.Tabs.Main then
        -- Секция AutoEat (левая сторона)
        local eatSection = UI.Tabs.Main:Section({Name = "AutoEat", Side = "Left"})
        
        local eatInfoLabel = eatSection:SubLabel({Text = "Loading food data..."})
        
        eatSection:Toggle({
            Name = "Enabled",
            Default = Config.AutoEat.Enabled,
            Callback = function(value)
                Config.AutoEat.Enabled = value
                notify("AutoAFK", "AutoEat " .. (value and "Enabled" or "Disabled"), true)
            end
        })
        
        eatSection:Slider({
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
        
        eatSection:Slider({
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
        
        eatSection:Slider({
            Name = "Check Interval (sec)",
            Minimum = 1,
            Maximum = 10,
            Default = Config.AutoEat.CheckInterval,
            Precision = 1,
            Callback = function(value)
                Config.AutoEat.CheckInterval = value
            end
        })
        
        eatSection:Dropdown({
            Name = "Priority",
            Default = Config.AutoEat.Priority,
            Options = {"Both", "Hunger", "Thirst"},
            Callback = function(value)
                Config.AutoEat.Priority = value
            end
        })
        
        eatSection:Toggle({
            Name = "Use Best Item",
            Default = Config.AutoEat.UseBestItem,
            Callback = function(value)
                Config.AutoEat.UseBestItem = value
                notify("AutoAFK", "Best item selection " .. (value and "Enabled" or "Disabled"), true)
            end
        })
        
        eatSection:Toggle({
            Name = "Swap When Toolbar Full",
            Default = Config.AutoEat.SwapWhenFull,
            Callback = function(value)
                Config.AutoEat.SwapWhenFull = value
                notify("AutoAFK", "Toolbar swap " .. (value and "Enabled" or "Disabled"), true)
            end
        })
        
        eatSection:Divider()
        eatSection:Button({
            Name = "Test Eat",
            Callback = testEat
        })
        
        -- Секция AutoHeal (левая сторона)
        local healSection = UI.Tabs.Main:Section({Name = "AutoHeal", Side = "Left"})
        
        local healInfoLabel = healSection:SubLabel({Text = "Loading health data..."})
        
        healSection:Toggle({
            Name = "Enabled",
            Default = Config.AutoHeal.Enabled,
            Callback = function(value)
                Config.AutoHeal.Enabled = value
                notify("AutoAFK", "AutoHeal " .. (value and "Enabled" or "Disabled"), true)
            end
        })
        
        healSection:Slider({
            Name = "Health Threshold",
            Minimum = 0,
            Maximum = 100,
            DisplayMethod = 'Percent',
            Default = Config.AutoHeal.HealthThreshold,
            Precision = 0,
            Callback = function(value)
                Config.AutoHeal.HealthThreshold = value
            end
        })
        
        healSection:Slider({
            Name = "Check Interval (sec)",
            Minimum = 0.1,
            Maximum = 2,
            Default = Config.AutoHeal.CheckInterval,
            Precision = 1,
            Callback = function(value)
                Config.AutoHeal.CheckInterval = value
            end
        })
        
        healSection:Toggle({
            Name = "Use Best Item",
            Default = Config.AutoHeal.UseBestItem,
            Callback = function(value)
                Config.AutoHeal.UseBestItem = value
                notify("AutoAFK", "Best heal selection " .. (value and "Enabled" or "Disabled"), true)
            end
        })
        
        healSection:Toggle({
            Name = "Fast Heal",
            Default = Config.AutoHeal.FastHeal,
            Callback = function(value)
                Config.AutoHeal.FastHeal = value
                notify("AutoAFK", "Fast heal " .. (value and "Enabled" or "Disabled"), true)
            end
        })
        
        healSection:Toggle({
            Name = "Swap When Toolbar Full",
            Default = Config.AutoHeal.SwapWhenFull,
            Callback = function(value)
                Config.AutoHeal.SwapWhenFull = value
                notify("AutoAFK", "Toolbar swap " .. (value and "Enabled" or "Disabled"), true)
            end
        })
        
        healSection:Divider()
        healSection:Button({
            Name = "Test Heal",
            Callback = testHeal
        })
        
        -- Обновление информации
        local function updateInfo()
            if Data and Data.Hunger and Data.Thirst then
                local hungerStatus = Data.Hunger.Value < Config.AutoEat.HungerThreshold and "⚠ Low" or "✓ OK"
                local thirstStatus = Data.Thirst.Value < Config.AutoEat.ThirstThreshold and "⚠ Low" or "✓ OK"
                local validFoodCount = 0
                
                for _, food in ipairs(FoodItems) do
                    if food.hunger > 0 or food.thirst > 0 then
                        validFoodCount = validFoodCount + 1
                    end
                end
                
                eatInfoLabel:UpdateName(string.format("Hunger: %d/%d (%s) | Thirst: %d/%d (%s) | Items: %d", 
                    Data.Hunger.Value, Config.AutoEat.HungerThreshold, hungerStatus,
                    Data.Thirst.Value, Config.AutoEat.ThirstThreshold, thirstStatus,
                    validFoodCount))
            end
            
            if LocalPlayer.Character then
                local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    local healthPercent = math.floor((humanoid.Health / humanoid.MaxHealth) * 100)
                    local healthStatus = healthPercent < Config.AutoHeal.HealthThreshold and "⚠ Low" or "✓ OK"
                    local validHealCount = 0
                    
                    for _, heal in ipairs(HealItems) do
                        if heal.health > 0 then
                            validHealCount = validHealCount + 1
                        end
                    end
                    
                    healInfoLabel:UpdateName(string.format("Health: %d/%d (%d%%, %s) | Heal Items: %d", 
                        math.floor(humanoid.Health), math.floor(humanoid.MaxHealth), 
                        healthPercent, healthStatus, validHealCount))
                end
            end
        end
        
        task.spawn(function()
            while true do
                updateInfo()
                wait(1)
            end
        end)
    end
end

-- Инициализация модуля
function AutoAFK.Init(UI, core, notifyFunc)
    notify = notifyFunc or print
    
    -- Запускаем основной цикл
    task.spawn(mainLoop)
    
    -- Инициализируем UI если он передан
    if UI then
        initializeUI(UI)
    end
    
    -- Подписываемся на изменения инвентаря
    Inventory.ChildAdded:Connect(function()
        scanFoodItems()
        scanHealItems()
    end)
    
    Inventory.ChildRemoved:Connect(function()
        scanFoodItems()
        scanHealItems()
    end)
    
    Toolbar.ChildAdded:Connect(function()
        scanFoodItems()
        scanHealItems()
    end)
    
    Toolbar.ChildRemoved:Connect(function()
        scanFoodItems()
        scanHealItems()
    end)
    
    -- Первоначальное сканирование
    scanFoodItems()
    scanHealItems()
    
    return AutoAFK
end

return AutoAFK
