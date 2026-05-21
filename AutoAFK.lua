local AutoAFK = {}

-- Сервисы
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Inventory = LocalPlayer:WaitForChild("Inventory")
local Toolbar = LocalPlayer:WaitForChild("Toolbar")
local Data = LocalPlayer:WaitForChild("Data")
local Character = Data:WaitForChild("Character")
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
        HungerThreshold = 10,
        ThirstThreshold = 10,
        CheckInterval = 2,
        Priority = "Both",
        UseBestItem = true,
        SwapWhenFull = true
    },
    AutoHeal = {
        Enabled = false,
        HealthThreshold = 30,
        CheckInterval = 1,
        UseBestItem = true,
        FastHeal = true,
        SwapWhenFull = true
    }
}

local uiElements = {}
local ItemCache = {}
local FoodItems = {}
local HealItems = {}
local notify = print
local IsHealingInProgress = false

-- Получение конфига consumable предмета
local function getConsumableConfig(itemName)
    if ItemCache[itemName] ~= nil then
        return ItemCache[itemName] or nil
    end

    local itemModel = Items:FindFirstChild(itemName)
    if not itemModel then
        ItemCache[itemName] = false
        return nil
    end

    local configModule = itemModel:FindFirstChild("Config")
    if configModule and configModule:IsA("ModuleScript") then
        local ok, configTable = pcall(require, configModule)
        if ok and configTable and configTable.class == "consumable" then
            local foodConfig, waterConfig = nil, nil

            local fcm = itemModel:FindFirstChild("FoodConfig")
            if fcm and fcm:IsA("ModuleScript") then
                local ok2, fc = pcall(require, fcm)
                if ok2 and fc then foodConfig = fc end
            end

            local wcm = itemModel:FindFirstChild("WaterConfig")
            if wcm and wcm:IsA("ModuleScript") then
                local ok3, wc = pcall(require, wcm)
                if ok3 and wc then waterConfig = wc end
            end

            local cc = { hunger = 0, thirst = 0, health = 0, stamina = 0 }
            if foodConfig then
                cc.hunger  = foodConfig.hunger  or 0
                cc.thirst  = foodConfig.thirst  or 0
                cc.health  = foodConfig.health  or 0
                cc.stamina = foodConfig.stamina or 0
            end
            if waterConfig then
                cc.thirst = waterConfig.thirst or 0
            end

            ItemCache[itemName] = { class = "consumable", config = cc }
            return ItemCache[itemName]
        end
    end

    ItemCache[itemName] = false
    return nil
end

local function isHungerOrThirstItem(cc)
    if not cc or not cc.config then return false end
    return (cc.config.hunger or 0) > 0 or (cc.config.thirst or 0) > 0
end

local function isHealItem(cc)
    if not cc or not cc.config then return false end
    return (cc.config.health or 0) > 0
end

-- Сканирование еды
local function scanFoodItems()
    FoodItems = {}
    local function addFood(folder, location, slot)
        local cc = getConsumableConfig(folder.Name)
        if not cc or not isHungerOrThirstItem(cc) then return end
        local cv = folder:FindFirstChild("Count")
        table.insert(FoodItems, {
            folder     = folder,
            name       = folder.Name,
            count      = cv and cv.Value or 1,
            hunger     = cc.config.hunger or 0,
            thirst     = cc.config.thirst or 0,
            location   = location,
            slot       = slot,
            totalValue = (cc.config.hunger or 0) + (cc.config.thirst or 0)
        })
    end
    for _, f in ipairs(Inventory:GetChildren()) do addFood(f, "Inventory", nil) end
    for _, f in ipairs(Toolbar:GetChildren()) do
        local iv = f:FindFirstChild("Index")
        addFood(f, "Toolbar", iv and iv.Value or nil)
    end
end

-- Сканирование лечебных предметов
local function scanHealItems()
    HealItems = {}
    local function addHeal(folder, location, slot)
        local cc = getConsumableConfig(folder.Name)
        if not cc or not isHealItem(cc) then return end
        local cv = folder:FindFirstChild("Count")
        table.insert(HealItems, {
            folder    = folder,
            name      = folder.Name,
            count     = cv and cv.Value or 1,
            health    = cc.config.health or 0,
            location  = location,
            slot      = slot,
            healValue = cc.config.health or 0
        })
    end
    for _, f in ipairs(Inventory:GetChildren()) do addHeal(f, "Inventory", nil) end
    for _, f in ipairs(Toolbar:GetChildren()) do
        local iv = f:FindFirstChild("Index")
        addHeal(f, "Toolbar", iv and iv.Value or nil)
    end
end

-- Свободный слот тулбара
local function findFreeToolbarSlot()
    for slot = 1, 9 do
        local busy = false
        for _, f in ipairs(Toolbar:GetChildren()) do
            local iv = f:FindFirstChild("Index")
            if iv and iv.Value == slot then busy = true; break end
        end
        if not busy then return slot end
    end
    return nil
end

-- Свободный слот инвентаря
local function findFreeInventorySlot()
    local size = Data.InventorySize and Data.InventorySize.Value or 30
    for slot = 1, size do
        local busy = false
        for _, f in ipairs(Inventory:GetChildren()) do
            local iv = f:FindFirstChild("Index")
            if iv and iv.Value == slot then busy = true; break end
        end
        if not busy then return slot end
    end
    return nil
end

-- Предмет в слоте 9
local function findItemInSlot9()
    for _, f in ipairs(Toolbar:GetChildren()) do
        local iv = f:FindFirstChild("Index")
        if iv and iv.Value == 9 then return f end
    end
    return nil
end

-- Swap предмета из инвентаря со слотом 9
-- SwapItems ожидает два Instance (itemFolder1, itemFolder2)
local function swapWithSlot9(itemToUse)
    if not itemToUse then return false end
    local slot9Item = findItemInSlot9()
    if not slot9Item then return false end
    SwapItems:FireServer(itemToUse.folder, slot9Item)
    return true
end

-- Вернуть предмет в инвентарь
local function moveToInventory(itemFolder)
    if not itemFolder then return false end
    local freeSlot = findFreeInventorySlot()
    if not freeSlot then return false end
    MoveItem:FireServer(itemFolder, "Inventory", freeSlot)
    return true
end

-- Выбор лучшей еды/воды
local function selectBestFoodForCurrentNeeds()
    local hunger = Character.Hunger.Value
    local thirst = Character.Thirst.Value

    local needH = hunger < Config.AutoEat.HungerThreshold
    local needT = thirst < Config.AutoEat.ThirstThreshold
    if not needH and not needT then return nil end

    local best, bestScore = nil, -math.huge
    local hd = math.max(0, Config.AutoEat.HungerThreshold - hunger)
    local td = math.max(0, Config.AutoEat.ThirstThreshold - thirst)

    for _, food in ipairs(FoodItems) do
        if food.count > 0 and (food.hunger > 0 or food.thirst > 0) then
            local hr = math.min(food.hunger, hd)
            local tr = math.min(food.thirst, td)
            local score = 0

            if Config.AutoEat.Priority == "Hunger" then
                if needH then score = hr * 2 + (needT and tr * 0.5 or 0)
                elseif needT then score = tr end
            elseif Config.AutoEat.Priority == "Thirst" then
                if needT then score = tr * 2 + (needH and hr * 0.5 or 0)
                elseif needH then score = hr end
            else
                if needH and needT then
                    local total = hd + td
                    local hw = total > 0 and (hd / total) or 0.5
                    local tw = total > 0 and (td / total) or 0.5
                    score = (hr * hw * 2) + (tr * tw * 2)
                elseif needH then score = hr * 2
                elseif needT then score = tr * 2 end
            end

            if hr >= hd and needH and hd > 0 then score = score + 5 end
            if tr >= td and needT and td > 0 then score = score + 5 end
            if food.location == "Toolbar" then score = score * 1.2 end
            if food.count == 1 then score = score * 0.9 end

            if score > bestScore then bestScore = score; best = food end
        end
    end

    return best
end

-- Выбор лучшего лечебного предмета
local function selectBestHealItem()
    local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end

    local curHp = humanoid.Health
    local maxHp = humanoid.MaxHealth
    if curHp >= maxHp * (Config.AutoHeal.HealthThreshold / 100) then return nil end

    local deficit = math.max(0, maxHp * (Config.AutoHeal.HealthThreshold / 100) - curHp)
    local best, bestScore = nil, -math.huge

    for _, item in ipairs(HealItems) do
        if item.count > 0 and item.health > 0 then
            local restored = math.min(item.health, deficit)
            local score = restored * 2
            if item.location == "Toolbar" then score = score * 2 end
            if restored >= deficit and deficit > 0 then score = score + 20 end
            if score > bestScore then bestScore = score; best = item end
        end
    end

    return best
end

-- Использование еды
local function useFood(foodItem)
    if not foodItem then return false end

    if foodItem.location == "Inventory" then
        local freeSlot = findFreeToolbarSlot()
        if freeSlot then
            MoveItem:FireServer(foodItem.folder, "Toolbar", freeSlot)
            task.wait(0.1)
            EquipItem:FireServer(freeSlot)
            task.wait(0.05)
            Consume:FireServer()
            task.wait(0.05)
            EquipItem:FireServer(0)
            return true
        elseif Config.AutoEat.SwapWhenFull then
            if swapWithSlot9(foodItem) then
                task.wait(0.2)
                EquipItem:FireServer(9)
                task.wait(0.05)
                Consume:FireServer()
                task.wait(0.05)
                EquipItem:FireServer(0)
                return true
            end
        end
    else
        if foodItem.slot then
            EquipItem:FireServer(foodItem.slot)
            task.wait(0.05)
            Consume:FireServer()
            task.wait(0.05)
            EquipItem:FireServer(0)
            return true
        end
    end

    return false
end

-- Использование лечебного предмета
local function useHealItem(healItem)
    if not healItem or IsHealingInProgress then return false end
    IsHealingInProgress = true
    local success = false

    if healItem.location == "Inventory" then
        if Config.AutoHeal.FastHeal then
            local freeSlot = findFreeToolbarSlot()
            if freeSlot then
                MoveItem:FireServer(healItem.folder, "Toolbar", freeSlot)
                task.wait(0.1)
                EquipItem:FireServer(freeSlot)
                task.wait(0.05)
                Consume:FireServer()
                task.wait(0.05)
                EquipItem:FireServer(0)
                task.spawn(function()
                    task.wait(0.3)
                    moveToInventory(healItem.folder)
                end)
                success = true
            elseif Config.AutoHeal.SwapWhenFull then
                if swapWithSlot9(healItem) then
                    task.wait(0.2)
                    EquipItem:FireServer(9)
                    task.wait(0.05)
                    Consume:FireServer()
                    task.wait(0.05)
                    EquipItem:FireServer(0)
                    task.spawn(function()
                        task.wait(0.3)
                        moveToInventory(healItem.folder)
                    end)
                    success = true
                end
            end
        end
    else
        if healItem.slot then
            EquipItem:FireServer(healItem.slot)
            task.wait(0.05)
            Consume:FireServer()
            task.wait(0.05)
            EquipItem:FireServer(0)
            success = true
        end
    end

    IsHealingInProgress = false
    return success
end

-- Optimize
local function cleanDroppedItems()
    local workspaceItems = game:GetService("Workspace"):FindFirstChild("Items")
    if workspaceItems then
        local count = 0
        for _, item in ipairs(workspaceItems:GetChildren()) do
            item:Destroy()
            count = count + 1
        end
        notify("Optimize", "Cleaned " .. count .. " dropped items", true)
    else
        notify("Optimize", "No Items folder found in Workspace", false)
    end
end

local function removeZombies()
    local enemies = game:GetService("Workspace"):FindFirstChild("Enemies")
    if enemies then
        local count = 0
        for _, enemy in ipairs(enemies:GetChildren()) do
            enemy:Destroy()
            count = count + 1
        end
        notify("Optimize", "Removed " .. count .. " zombies/enemies", true)
    else
        notify("Optimize", "No Enemies folder found in Workspace", false)
    end
end

-- Тест еды
local function testEat()
    scanFoodItems()
    if #FoodItems == 0 then
        notify("AutoEat", "No food or water in inventory!", false)
        return
    end
    local used = useFood(FoodItems[1])
    notify("AutoEat", used and ("Test: used " .. FoodItems[1].name) or "Test: failed to use item", false)
end

-- Тест лечения
local function testHeal()
    scanHealItems()
    if #HealItems == 0 then
        notify("AutoHeal", "No healing items in inventory!", false)
        return
    end
    local used = useHealItem(HealItems[1])
    notify("AutoHeal", used and ("Test: used " .. HealItems[1].name) or "Test: failed to use healing item", false)
end

-- Основной цикл
local function mainLoop()
    while true do
        if Config.AutoEat.Enabled and LocalPlayer.Character then
            scanFoodItems()
            if #FoodItems > 0 then
                local best = selectBestFoodForCurrentNeeds()
                if best then useFood(best) end
            end
        end
        if Config.AutoHeal.Enabled and LocalPlayer.Character and not IsHealingInProgress then
            local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health < humanoid.MaxHealth * (Config.AutoHeal.HealthThreshold / 100) then
                scanHealItems()
                if #HealItems > 0 then
                    local best = selectBestHealItem()
                    if best then useHealItem(best) end
                end
            end
        end
        task.wait(math.min(Config.AutoEat.CheckInterval, Config.AutoHeal.CheckInterval))
    end
end

-- UI
local function initializeUI(UI)
    if UI.Tabs and UI.Tabs.Main then
        -- AutoEat
        local eatSection = UI.Tabs.Main:Section({Name = "AutoEat", Side = "Left"})
        eatSection:Header({Name = "AutoEat"})
        local eatInfoLabel = eatSection:SubLabel({Text = "Loading food data..."})

        uiElements.EnabledAutoEat = eatSection:Toggle({
            Name = "Enabled", Default = Config.AutoEat.Enabled,
            Callback = function(v) Config.AutoEat.Enabled = v; notify("AutoAFK", "AutoEat " .. (v and "Enabled" or "Disabled"), true) end
        }, "EnabledEat")

        uiElements.HungerThresh = eatSection:Slider({
            Name = "Hunger Threshold", Minimum = 0, Maximum = 100,
            DisplayMethod = "Percent", Default = Config.AutoEat.HungerThreshold, Precision = 0,
            Callback = function(v) Config.AutoEat.HungerThreshold = v end
        }, "HungerThres")

        uiElements.ThirstThresh = eatSection:Slider({
            Name = "Thirst Threshold", Minimum = 0, Maximum = 100,
            DisplayMethod = "Percent", Default = Config.AutoEat.ThirstThreshold, Precision = 0,
            Callback = function(v) Config.AutoEat.ThirstThreshold = v end
        }, "ThirstThres")

        uiElements.CheckIntervalEat = eatSection:Slider({
            Name = "Check Interval", Minimum = 1, Maximum = 10,
            Default = Config.AutoEat.CheckInterval, Precision = 0,
            Callback = function(v) Config.AutoEat.CheckInterval = v end
        }, "CheckInterEat")

        uiElements.PriorityEat = eatSection:Dropdown({
            Name = "Priority", Default = Config.AutoEat.Priority,
            Options = {"Both", "Hunger", "Thirst"},
            Callback = function(v) Config.AutoEat.Priority = v end
        }, "PriorityEat")

        uiElements.UseBestItemEat = eatSection:Toggle({
            Name = "Use Best Item", Default = Config.AutoEat.UseBestItem,
            Callback = function(v) Config.AutoEat.UseBestItem = v end
        }, "BestAutoEat")

        uiElements.SwapWhenFullEat = eatSection:Toggle({
            Name = "Swap When Toolbar Full", Default = Config.AutoEat.SwapWhenFull,
            Callback = function(v) Config.AutoEat.SwapWhenFull = v end
        }, "SwapAutoEat")

        eatSection:Divider()
        eatSection:Button({Name = "Test Eat", Callback = testEat})

        -- AutoHeal
        local healSection = UI.Tabs.Main:Section({Name = "AutoHeal", Side = "Right"})
        healSection:Header({Name = "AutoHeal"})
        local healInfoLabel = healSection:SubLabel({Text = "Loading health data..."})

        uiElements.EnabledAutoHeal = healSection:Toggle({
            Name = "Enabled", Default = Config.AutoHeal.Enabled,
            Callback = function(v) Config.AutoHeal.Enabled = v; notify("AutoAFK", "AutoHeal " .. (v and "Enabled" or "Disabled"), true) end
        }, "EnabledHeal")

        uiElements.HealThreshold = healSection:Slider({
            Name = "Health Threshold", Minimum = 0, Maximum = 100,
            DisplayMethod = "Percent", Default = Config.AutoHeal.HealthThreshold, Precision = 0,
            Callback = function(v) Config.AutoHeal.HealthThreshold = v end
        }, "HealThres")

        uiElements.CheckIntervalHeal = healSection:Slider({
            Name = "Check Interval", Minimum = 0, Maximum = 5,
            Default = Config.AutoHeal.CheckInterval, Precision = 0,
            Callback = function(v) Config.AutoHeal.CheckInterval = v end
        }, "CheckInterHeal")

        uiElements.UseBestItemHeal = healSection:Toggle({
            Name = "Use Best Item", Default = Config.AutoHeal.UseBestItem,
            Callback = function(v) Config.AutoHeal.UseBestItem = v end
        }, "UseBestHeal")

        uiElements.FastHeal = healSection:Toggle({
            Name = "Fast Heal", Default = Config.AutoHeal.FastHeal,
            Callback = function(v) Config.AutoHeal.FastHeal = v end
        }, "FastHeal")

        uiElements.SwapWhenFullHeal = healSection:Toggle({
            Name = "Swap When Toolbar Full", Default = Config.AutoHeal.SwapWhenFull,
            Callback = function(v) Config.AutoHeal.SwapWhenFull = v end
        }, "SwapHeal")

        healSection:Divider()
        healSection:Button({Name = "Test Heal", Callback = testHeal})

        -- Обновление info-label (Hunger/Thirst из Data.Character)
        task.spawn(function()
            while true do
                pcall(function()
                    if Character:FindFirstChild("Hunger") and Character:FindFirstChild("Thirst") then
                        local hv = Character.Hunger.Value
                        local tv = Character.Thirst.Value
                        local hs = hv < Config.AutoEat.HungerThreshold and "⚠ Low" or "✓ OK"
                        local ts = tv < Config.AutoEat.ThirstThreshold and "⚠ Low" or "✓ OK"
                        local fc = 0
                        for _, food in ipairs(FoodItems) do
                            if food.hunger > 0 or food.thirst > 0 then fc = fc + 1 end
                        end
                        eatInfoLabel:UpdateName(string.format(
                            "Hunger: %d/%d (%s) | Thirst: %d/%d (%s) | Items: %d",
                            hv, Config.AutoEat.HungerThreshold, hs,
                            tv, Config.AutoEat.ThirstThreshold, ts, fc
                        ))
                    end
                end)

                pcall(function()
                    if LocalPlayer.Character then
                        local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                        if hum then
                            local pct = math.floor((hum.Health / hum.MaxHealth) * 100)
                            local hst = pct < Config.AutoHeal.HealthThreshold and "⚠ Low" or "✓ OK"
                            local hc = 0
                            for _, h in ipairs(HealItems) do
                                if h.health > 0 then hc = hc + 1 end
                            end
                            healInfoLabel:UpdateName(string.format(
                                "Health: %d/%d (%d%%, %s) | Heal Items: %d",
                                math.floor(hum.Health), math.floor(hum.MaxHealth), pct, hst, hc
                            ))
                        end
                    end
                end)

                task.wait(1)
            end
        end)
    end

    if UI.Tabs and UI.Tabs.Misc then
        local optSection = UI.Tabs.Misc:Section({Name = "Optimize", Side = "Left"})
        optSection:Header({Name = "Performance Optimization"})
        optSection:Button({Name = "Clean Dropped Items", Callback = cleanDroppedItems})
        optSection:Button({Name = "Remove Zombies",      Callback = removeZombies})
        optSection:SubLabel({Text = "Removes dropped items and enemies to improve performance"})
    end
end

-- Init
function AutoAFK.Init(UI, core, notifyFunc)
    notify = notifyFunc or print

    task.spawn(mainLoop)

    if UI then initializeUI(UI) end

    Inventory.ChildAdded:Connect(function()   scanFoodItems(); scanHealItems() end)
    Inventory.ChildRemoved:Connect(function() scanFoodItems(); scanHealItems() end)
    Toolbar.ChildAdded:Connect(function()     scanFoodItems(); scanHealItems() end)
    Toolbar.ChildRemoved:Connect(function()   scanFoodItems(); scanHealItems() end)

    scanFoodItems()
    scanHealItems()

    return AutoAFK
end

return AutoAFK
