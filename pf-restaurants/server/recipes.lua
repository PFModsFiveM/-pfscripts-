-- Recipe management

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
    local recipeId = ('custom_%s_%d_%d'):format(businessId, os.time(), math.random(100, 999))
    
    RestaurantData.recipes[recipeId] = {
        recipeId = recipeId,
        businessId = businessId,
        label = recipeData.label,
        category = recipeData.category,
        components = recipeData.components,
        output = recipeData.output,
        baseHunger = recipeData.baseHunger or 0,
        baseThirst = recipeData.baseThirst or 0,
        allowedMods = recipeData.allowedMods or {},
        requiresOven = recipeData.requiresOven or false,
        createdBy = GetPlayerIdentifier(src, 0),
        createdAt = os.time()
    }
    RestaurantData.recipes[recipeId].output = { item = recipeData.output.item, qty = 1 }
    RestaurantDB.SaveRecipe(RestaurantData.recipes[recipeId])
        
    LogAction('recipe_create', {
        businessId = businessId,
        recipeId = recipeId,
        label = recipeData.label,
        by = GetPlayerIdentifier(src, 0)
    })
    
    NotifyPlayer(src, 'Recipe created: ' .. recipeData.label, 'success')
    TriggerClientEvent('pf-restaurants:client:recipeUpdate', -1, recipeId, RestaurantData.recipes[recipeId])
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
    
    -- Update fields
    recipe.label = recipeData.label or recipe.label
    recipe.category = recipeData.category or recipe.category
    recipe.components = recipeData.components or recipe.components
    recipe.baseHunger = recipeData.baseHunger or recipe.baseHunger
    recipe.baseThirst = recipeData.baseThirst or recipe.baseThirst
    recipe.allowedMods = recipeData.allowedMods or recipe.allowedMods
    recipe.updatedBy = GetPlayerIdentifier(src, 0)
    recipe.updatedAt = os.time()
    
    LogAction('recipe_edit', {
        businessId = businessId,
        recipeId = recipeId,
        by = GetPlayerIdentifier(src, 0)
    })
    
    NotifyPlayer(src, 'Recipe updated', 'success')
    TriggerClientEvent('pf-restaurants:client:recipeUpdate', -1, recipeId, recipe)
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
        by = GetPlayerIdentifier(src, 0)
    })
    
    RestaurantData.recipes[recipeId] = nil
    
    NotifyPlayer(src, 'Recipe deleted', 'success')
    TriggerClientEvent('pf-restaurants:client:recipeDeleted', -1, recipeId)
end)

-- Get all recipes for a business
QBCore.Functions.CreateCallback('pf-restaurants:server:getRecipes', function(source, cb, businessId)
    local recipes = {}
    
    -- Include config recipes
    for recipeId, recipe in pairs(Config.Recipes) do
        recipes[recipeId] = recipe
    end
    
    -- Include custom recipes for this business
    for recipeId, recipe in pairs(RestaurantData.recipes) do
        if recipe.businessId == businessId or not recipe.businessId then
            recipes[recipeId] = recipe
        end
    end
    
    cb(recipes)
end)

-- Get single recipe
QBCore.Functions.CreateCallback('pf-restaurants:server:getRecipe', function(source, cb, recipeId)
    local recipe = RestaurantData.recipes[recipeId] or Config.Recipes[recipeId]
    cb(recipe)
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
