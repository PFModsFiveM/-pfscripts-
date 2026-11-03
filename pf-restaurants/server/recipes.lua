-- Recipe management
--
-- Custom recipes belong to one restaurant: only its staff read them (getRecipes / getRecipe), and
-- who made or changed one is kept as a citizen id on the server only (never sent to a client).
-- Labels and categories are plain text, like menu text (a recipe's label is the default menu name).

local OFF_SHIFT = { offDuty = true }

local function cidOf(src)
    local P = QBCore.Functions.GetPlayer(src)
    return P and P.PlayerData.citizenid or nil
end

-- what a client may see of a recipe: everything but who made or changed it
local function publicRecipe(recipe)
    local out = {}
    for k, v in pairs(recipe) do
        if k ~= 'createdBy' and k ~= 'updatedBy' then out[k] = v end
    end
    return out
end

-- a custom recipe is visible to its restaurant's staff (on or off shift); config recipes to everyone
local function canSee(source, recipe)
    if type(recipe) ~= 'table' then return false end
    if recipe.businessId == nil then return true end
    return RoleOf(source, recipe.businessId, OFF_SHIFT) ~= nil
end

-- Create new recipe
RegisterNetEvent('pf-restaurants:server:createRecipe', function(businessId, recipeData)
    local src = source
    
    if not HasPermission(src, businessId, 'recipe.create') then
        NotifyPlayer(src, 'No permission to create recipes', 'error')
        return
    end
    
    -- a recipe may only combine restaurant items into a restaurant item (a client could otherwise
    -- turn anything into anything), and may not replace a built-in recipe
    if type(recipeData) ~= 'table' or type(recipeData.components) ~= 'table' or type(recipeData.output) ~= 'table' then
        NotifyPlayer(src, 'Invalid recipe', 'error')
        return
    end
    local known = function(item) return type(item) == 'string' and (Config.Items[item] ~= nil or QBCore.Shared.Items[item] ~= nil) end
    if not known(recipeData.output.item) or #recipeData.components == 0 or #recipeData.components > 20 then
        NotifyPlayer(src, 'Invalid recipe', 'error')
        return
    end
    for _, c in ipairs(recipeData.components) do
        local qty = type(c) == 'table' and tonumber(c.qty) or nil
        if not (type(c) == 'table' and known(c.item) and qty and qty >= 1 and qty <= 20 and qty == math.floor(qty)) then
            NotifyPlayer(src, 'Invalid recipe component', 'error')
            return
        end
    end
    local label, badLabel = PlainText(recipeData.label, 60)
    local category, badCategory = PlainText(recipeData.category, 40)
    if badLabel or badCategory then
        NotifyPlayer(src, 'Recipe names cannot contain < > " or `', 'error')
        return
    end
    local recipeId = ('custom_%s_%d_%d'):format(businessId, os.time(), math.random(100, 999))
    recipeData.label = (label and label ~= '') and label or 'Custom recipe'
    local components = {}
    for i, c in ipairs(recipeData.components) do components[i] = { item = c.item, qty = math.floor(tonumber(c.qty)) } end

    RestaurantData.recipes[recipeId] = {
        recipeId = recipeId,
        businessId = businessId,
        label = recipeData.label,
        category = category,
        components = components,
        output = recipeData.output,
        baseHunger = math.max(0, math.min(100, tonumber(recipeData.baseHunger) or 0)),
        baseThirst = math.max(0, math.min(100, tonumber(recipeData.baseThirst) or 0)),
        allowedMods = {},
        requiresOven = recipeData.requiresOven == true,
        createdBy = cidOf(src),      -- server-only (publicRecipe leaves it out)
        createdAt = os.time()
    }
    RestaurantData.recipes[recipeId].output = { item = recipeData.output.item, qty = 1 }
    RestaurantDB.SaveRecipe(RestaurantData.recipes[recipeId])

    LogAction('recipe_create', {
        businessId = businessId,
        recipeId = recipeId,
        label = recipeData.label,
        by = cidOf(src)
    })

    -- (no broadcast: no client listens for recipe changes, and a recipe is its restaurant's own)
    NotifyPlayer(src, 'Recipe created: ' .. recipeData.label, 'success')
end)

-- Update recipe
RegisterNetEvent('pf-restaurants:server:updateRecipe', function(recipeId, recipeData)
    local src = source
    
    local recipe = RestaurantData.recipes[recipeId]
    if not recipe then
        NotifyPlayer(src, 'Recipe not found', 'error')
        return
    end
    
    local businessId = recipe.businessId
    if not HasPermission(src, businessId, 'recipe.edit') then
        NotifyPlayer(src, 'No permission to edit recipes', 'error')
        return
    end
    if type(recipeData) ~= 'table' then return end

    -- same rules as creating one: restaurant items, bounded amounts and text
    local components = nil
    if recipeData.components ~= nil then
        if type(recipeData.components) ~= 'table' or #recipeData.components == 0 or #recipeData.components > 20 then
            return NotifyPlayer(src, 'Invalid recipe', 'error')
        end
        components = {}
        for i, c in ipairs(recipeData.components) do
            local qty = type(c) == 'table' and tonumber(c.qty) or nil
            local known = type(c) == 'table' and type(c.item) == 'string' and (Config.Items[c.item] ~= nil or QBCore.Shared.Items[c.item] ~= nil)
            if not (known and qty and qty >= 1 and qty <= 20 and qty == math.floor(qty)) then
                return NotifyPlayer(src, 'Invalid recipe component', 'error')
            end
            components[i] = { item = c.item, qty = qty }
        end
    end

    local label, badLabel = PlainText(recipeData.label, 60)
    local category, badCategory = PlainText(recipeData.category, 40)
    if badLabel or badCategory then
        return NotifyPlayer(src, 'Recipe names cannot contain < > " or `', 'error')
    end

    -- Update fields
    recipe.label = (label and label ~= '') and label or recipe.label
    recipe.category = category or recipe.category
    recipe.components = components or recipe.components
    recipe.baseHunger = tonumber(recipeData.baseHunger) and math.max(0, math.min(100, tonumber(recipeData.baseHunger))) or recipe.baseHunger
    recipe.baseThirst = tonumber(recipeData.baseThirst) and math.max(0, math.min(100, tonumber(recipeData.baseThirst))) or recipe.baseThirst
    recipe.updatedBy = cidOf(src)    -- server-only
    recipe.updatedAt = os.time()
    RestaurantDB.SaveRecipe(recipe)

    LogAction('recipe_edit', {
        businessId = businessId,
        recipeId = recipeId,
        by = cidOf(src)
    })

    NotifyPlayer(src, 'Recipe updated', 'success')
end)

-- Delete recipe
RegisterNetEvent('pf-restaurants:server:deleteRecipe', function(recipeId)
    local src = source
    
    local recipe = RestaurantData.recipes[recipeId]
    if not recipe then
        NotifyPlayer(src, 'Recipe not found', 'error')
        return
    end
    
    local businessId = recipe.businessId
    if not HasPermission(src, businessId, 'recipe.delete') then
        NotifyPlayer(src, 'No permission to delete recipes', 'error')
        return
    end
    
    LogAction('recipe_delete', {
        businessId = businessId,
        recipeId = recipeId,
        by = cidOf(src)
    })

    RestaurantData.recipes[recipeId] = nil
    RestaurantDB.DeleteRecipe(recipeId)

    NotifyPlayer(src, 'Recipe deleted', 'success')
end)

-- All recipes a restaurant can use: the built-in ones, plus its own custom ones for its staff
QBCore.Functions.CreateCallback('pf-restaurants:server:getRecipes', function(source, cb, businessId)
    local recipes = {}
    for recipeId, recipe in pairs(Config.Recipes) do
        recipes[recipeId] = recipe
    end
    if type(businessId) == 'string' and RoleOf(source, businessId, OFF_SHIFT) then
        for recipeId, recipe in pairs(RestaurantData.recipes) do
            if recipe.businessId == businessId then recipes[recipeId] = publicRecipe(recipe) end
        end
    end
    cb(recipes)
end)

-- One recipe: a built-in one for anyone, a custom one only for its restaurant's staff
QBCore.Functions.CreateCallback('pf-restaurants:server:getRecipe', function(source, cb, recipeId)
    local recipe = type(recipeId) == 'string' and (RestaurantData.recipes[recipeId] or Config.Recipes[recipeId]) or nil
    if not canSee(source, recipe) then cb(nil) return end
    cb(publicRecipe(recipe))
end)

-- Calculate hunger/thirst from components (for assembly validation)
function CalculateNutrition(components, mods)
    local totalHunger = 0
    local totalThirst = 0
    local quality = 100
    local poisonRisk = 0
    
    for _, component in ipairs(components) do
        local itemConfig = Config.Items[component.item]
        if itemConfig then
            -- Add hunger
            if itemConfig.hungerValue then
                totalHunger = totalHunger + (itemConfig.hungerValue * component.qty)
            end
            
            -- Add thirst
            if itemConfig.thirstValue then
                totalThirst = totalThirst + (itemConfig.thirstValue * component.qty)
            end
            
            -- Factor in component quality if it has metadata
            if component.metadata then
                if component.metadata.quality then
                    quality = math.min(quality, component.metadata.quality)
                end
                
                if component.metadata.poisonRisk then
                    poisonRisk = math.max(poisonRisk, component.metadata.poisonRisk)
                end
            end
        end
    end
    
    -- Apply mod penalties/bonuses
    if mods then
        local removedCount = 0
        for modType, modValue in pairs(mods) do
            if modType:match('^remove_') and modValue then
                removedCount = removedCount + 1
            end
        end
        
        if removedCount > 0 then
            local penalty = removedCount * Config.Hunger.RemoveIngredientPenalty
            totalHunger = totalHunger * (1 - penalty)
        end
    end
    
    -- Apply quality multiplier
    if Config.Hunger.QualityMultiplier then
        local qualityBonus = 1 + ((quality / 100) * (Config.Hunger.MaxQualityBonus - 1))
        totalHunger = totalHunger * qualityBonus
    end
    
    return {
        hunger = math.floor(totalHunger),
        thirst = math.floor(totalThirst),
        quality = quality,
        poisonRisk = poisonRisk
    }
end

exports('CalculateNutrition', CalculateNutrition)
