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
local Consume = ItemsFolder:WaitForChild("Consume")

-- Конфигурация
local Config = {
    AutoEat = {
        Enabled = false,
        HungerThreshold = 50,  -- Порог голода (когда начинаем есть)
        ThirstThreshold = 50,  -- Порог жажды (когда начинаем пить)
        CheckInterval = 2,     -- Интервал проверки в секундах
        Priority = "Both",     -- Приоритет: "Hunger", "Thirst", "Both"
        UseBestItem = true     -- Использовать лучший предмет для текущей потребности
    }
}

-- Кэш предметов
local ItemCache = {}
local FoodItems = {}

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
    
    -- Проверяем, является ли предмет consumable
    local configModule = itemModel:FindFirstChild("Config")
    if configModule and configModule:IsA("ModuleScript") then
        local success, configTable = pcall(require, configModule)
        if success and configTable and configTable.class == "consumable" then
            -- Получаем FoodConfig
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
                health = foodConfig.foodConfig.health or 0,
                stamina = foodConfig.foodConfig.stamina or 0,
                location = "Inventory"
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
                health = foodConfig.foodConfig.health or 0,
                stamina = foodConfig.foodConfig.stamina or 0,
                location = "Toolbar",
                slot = slot
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

-- Выбор лучшей еды для текущих потребностей
local function selectBestFood()
    local hunger = Data.Hunger.Value
    local thirst = Data.Thirst.Value
    
    local needHunger = hunger < Config.AutoEat.HungerThreshold
    local needThirst = thirst < Config.AutoEat.ThirstThreshold
    
    if not needHunger and not needThirst then
        return nil
    end
    
    local bestItem = nil
    local bestScore = -math.huge
    
    for _, food in ipairs(FoodItems) do
        if food.count > 0 then
            local score = 0
            
            if Config.AutoEat.Priority == "Hunger" then
                score = food.hunger * (needHunger and 2 or 0) + food.thirst * (needThirst and 1 or 0)
            elseif Config.AutoEat.Priority == "Thirst" then
                score = food.thirst * (needThirst and 2 or 0) + food.hunger * (needHunger and 1 or 0)
            else -- "Both"
                if needHunger and needThirst then
                    score = (food.hunger + food.thirst) * 1.5
                elseif needHunger then
                    score = food.hunger * 2
                elseif needThirst then
                    score = food.thirst * 2
                end
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
    if not foodItem then return false end
    
    local success = false
    
    if foodItem.location == "Inventory" then
        -- Перемещаем в тулбар
        local freeSlot = findFreeToolbarSlot()
        if freeSlot then
            local args = {
                [1] = foodItem.folder,
                [2] = "Toolbar",
                [3] = freeSlot
            }
            
            MoveItem:FireServer(unpack(args))
            wait(0.2) -- Ждем перемещения
            
            -- Экипируем
            local equipArgs = {[1] = freeSlot}
            EquipItem:FireServer(unpack(equipArgs))
            wait(0.1)
            
            -- Используем
            Consume:FireServer()
            success = true
        end
    else -- Уже в тулбаре
        if foodItem.slot then
            -- Экипируем
            local equipArgs = {[1] = foodItem.slot}
            EquipItem:FireServer(unpack(equipArgs))
            wait(0.1)
            
            -- Используем
            Consume:FireServer()
            success = true
        end
    end
    
    return success
end

-- Основная функция авто-питания
local function autoEat()
    if not Config.AutoEat.Enabled then return end
    if not LocalPlayer.Character then return end
    
    -- Обновляем список еды
    scanFoodItems()
    
    -- Выбираем лучшую еду
    local bestFood = selectBestFood()
    
    if bestFood then
        local used = useFood(bestFood)
        if used then
            print("[AutoEat] Использован предмет: " .. bestFood.name)
            wait(1) -- Задержка после использования
        end
    end
end

-- Тестовая функция (для кнопки)
local function testEat()
    scanFoodItems()
    
    if #FoodItems == 0 then
        print("[AutoEat] В инвентаре нет еды!")
        return
    end
    
    -- Используем первый попавшийся предмет
    local testFood = FoodItems[1]
    local used = useFood(testFood)
    
    if used then
        print("[AutoEat] Тест: использован " .. testFood.name)
    else
        print("[AutoEat] Тест: не удалось использовать предмет")
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
        
        -- Заголовок AutoEat
        afkSection:Header({Name = "AutoEat"})
        afkSection:SubLabel({Text = "Автоматически ест и пьет при низких показателях"})
        
        -- Включение/выключение
        afkSection:Toggle({
            Name = "Включить AutoEat",
            Default = Config.AutoEat.Enabled,
            Callback = function(value)
                Config.AutoEat.Enabled = value
                print("[AutoEat] " .. (value and "Включен" or "Выключен"))
            end
        })
        
        -- Порог голода
        afkSection:Slider({
            Name = "Порог голода",
            Minimum = 0,
            Maximum = 100,
            Default = Config.AutoEat.HungerThreshold,
            Precision = 0,
            Callback = function(value)
                Config.AutoEat.HungerThreshold = value
                print("[AutoEat] Порог голода: " .. value)
            end
        })
        
        -- Порог жажды
        afkSection:Slider({
            Name = "Порог жажды",
            Minimum = 0,
            Maximum = 100,
            Default = Config.AutoEat.ThirstThreshold,
            Precision = 0,
            Callback = function(value)
                Config.AutoEat.ThirstThreshold = value
                print("[AutoEat] Порог жажды: " .. value)
            end
        })
        
        -- Интервал проверки
        afkSection:Slider({
            Name = "Интервал проверки (сек)",
            Minimum = 1,
            Maximum = 10,
            Default = Config.AutoEat.CheckInterval,
            Precision = 1,
            Callback = function(value)
                Config.AutoEat.CheckInterval = value
                print("[AutoEat] Интервал: " .. value .. " сек")
            end
        })
        
        -- Приоритет
        afkSection:Dropdown({
            Name = "Приоритет",
            Default = Config.AutoEat.Priority,
            Options = {"Both", "Hunger", "Thirst"},
            Callback = function(value)
                Config.AutoEat.Priority = value
                print("[AutoEat] Приоритет: " .. value)
            end
        })
        
        -- Использовать лучший предмет
        afkSection:Toggle({
            Name = "Использовать лучший предмет",
            Default = Config.AutoEat.UseBestItem,
            Callback = function(value)
                Config.AutoEat.UseBestItem = value
                print("[AutoEat] Лучший предмет: " .. (value and "Да" or "Нет"))
            end
        })
        
        -- Разделитель
        afkSection:Divider()
        
        -- Тестовая кнопка
        afkSection:Button({
            Name = "Test Button",
            Callback = testEat
        })
        afkSection:SubLabel({Text = "Протестировать использование еды"})
        
        -- Информация о текущих показателях
        local infoLabel = afkSection:SubLabel({Text = "Загрузка данных..."})
        
        -- Обновление информации о показателях
        local function updateInfo()
            if Data and Data.Hunger and Data.Thirst then
                infoLabel.Text = string.format("Голод: %d/100 | Жажда: %d/100", 
                    Data.Hunger.Value, Data.Thirst.Value)
            end
        end
        
        -- Периодическое обновление
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
    local notify = notifyFunc or print
    
    -- Запускаем основной цикл
    task.spawn(mainLoop)
    
    -- Инициализируем UI если он передан
    if UI then
        initializeUI(UI)
        notify("[AutoAFK] Модуль AutoEat инициализирован")
    end
    
    -- Подписываемся на изменения инвентаря
    Inventory.ChildAdded:Connect(function()
        scanFoodItems()
    end)
    
    Inventory.ChildRemoved:Connect(function()
        scanFoodItems()
    end)
    
    Toolbar.ChildAdded:Connect(function()
        scanFoodItems()
    end)
    
    Toolbar.ChildRemoved:Connect(function()
        scanFoodItems()
    end)
    
    -- Первоначальное сканирование
    scanFoodItems()
    notify("[AutoAFK] Просканировано предметов: " .. #FoodItems)
    
    return AutoAFK
end

return AutoAFK