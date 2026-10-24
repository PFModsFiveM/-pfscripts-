-- ============================================================================
-- SQL AUTO-INJECTION SYSTEM
-- Automatically imports database schema on resource start
-- ============================================================================

local function dprint(...)
    if Config and Config.Debug then
        print('[PF-MECHANIC SQL]', ...)
    end
end

-- Read SQL file and return content
local function ReadSQLFile(filepath)
    local resourceName = GetCurrentResourceName()
    local file = LoadResourceFile(resourceName, filepath)
    
    if not file then
        print('^1[PF-MECHANIC SQL ERROR] Failed to load SQL file: ' .. filepath .. '^0')
        return nil
    end
    
    return file
end

-- Parse SQL file into individual statements
local function ParseSQL(content)
    local statements = {}
    local currentStatement = ''
    local inComment = false
    
    -- Split by lines
    for line in content:gmatch('[^\r\n]+') do
        -- Skip empty lines
        if line:match('%S') then
            -- Remove single-line comments
            local cleanLine = line:gsub('%-%-.*$', '')
            
            -- Skip if line is only whitespace after removing comments
            if cleanLine:match('%S') then
                currentStatement = currentStatement .. ' ' .. cleanLine
                
                -- Check if statement ends with semicolon
                if cleanLine:match(';%s*$') then
                    -- Clean up the statement
                    currentStatement = currentStatement:gsub('^%s+', ''):gsub('%s+$', '')
                    if currentStatement ~= '' and currentStatement ~= ';' then
                        table.insert(statements, currentStatement)
                    end
                    currentStatement = ''
                end
            end
        end
    end
    
    -- Add any remaining statement
    if currentStatement:match('%S') then
        currentStatement = currentStatement:gsub('^%s+', ''):gsub('%s+$', '')
        if currentStatement ~= '' and currentStatement ~= ';' then
            table.insert(statements, currentStatement)
        end
    end
    
    return statements
end

-- Execute SQL statements
local function ExecuteSQL(statements)
    local successCount = 0
    local errorCount = 0
    local skippedCount = 0
    
    print('^3[PF-MECHANIC SQL] Starting database initialization...^0')
    print('^3[PF-MECHANIC SQL] Total statements to execute: ' .. #statements .. '^0')
    
    for i, statement in ipairs(statements) do
        -- Skip empty statements
        if statement and statement ~= '' then
            -- Skip DROP TABLE statements in auto-injection to preserve data
            if statement:upper():find('^%s*DROP%s+TABLE') then
                dprint('Skipping DROP TABLE statement to preserve existing data')
                skippedCount = skippedCount + 1
            else
                -- Execute the statement with error handling
                local success, result = pcall(function()
                    return MySQL.Sync.execute(statement)
                end)
                
                if success and result then
                    successCount = successCount + 1
                    dprint('Statement ' .. i .. ' executed successfully')
                elseif success and not result then
                    -- MySQL returned false (likely duplicate)
                    skippedCount = skippedCount + 1
                    dprint('Statement ' .. i .. ' skipped (already exists)')
                else
                    -- Check if error is about existing table/column
                    local errorMsg = tostring(result):lower()
                    if errorMsg:find('already exists') or errorMsg:find('duplicate') then
                        skippedCount = skippedCount + 1
                        dprint('Statement ' .. i .. ' skipped (already exists)')
                    else
                        errorCount = errorCount + 1
                        dprint('Statement ' .. i .. ' failed: ' .. tostring(result))
                    end
                end
            end
        end
        
        -- Add small delay every 10 statements to prevent overload
        if i % 10 == 0 then
            Wait(50)
        end
    end
    
    -- Print summary
    print('^2[PF-MECHANIC SQL] Database initialization complete!^0')
    print('^2[PF-MECHANIC SQL] Successful: ' .. successCount .. ' | Skipped: ' .. skippedCount .. ' | Errors: ' .. errorCount .. '^0')
    
    if errorCount > 0 then
        print('^3[PF-MECHANIC SQL] Note: Some errors are normal if tables/columns already exist^0')
    end
end

-- Main initialization function
local function InitializeDatabase()
    -- Check if auto-injection is enabled
    if Config.AutoInjectSQL == false then
        print('^3[PF-MECHANIC SQL] Auto-injection is disabled in config^0')
        return
    end
    
    -- Wait a bit for MySQL to be ready
    Wait(1000)
    
    print('^3[PF-MECHANIC SQL] Initializing database...^0')
    
    -- SQL file path
    local sqlFile = 'pf_mechanic.sql'
    print('^3[PF-MECHANIC SQL] Using SQL file: ' .. sqlFile .. '^0')
    
    -- Read the SQL file
    local content = ReadSQLFile(sqlFile)
    if not content then
        print('^1[PF-MECHANIC SQL ERROR] Failed to read SQL file^0')
        return
    end
    
    -- Parse SQL into statements
    local statements = ParseSQL(content)
    print('^3[PF-MECHANIC SQL] Parsed ' .. #statements .. ' SQL statements^0')
    
    if #statements == 0 then
        print('^1[PF-MECHANIC SQL ERROR] No SQL statements found in file^0')
        return
    end
    
    -- Execute SQL statements
    ExecuteSQL(statements)
end

-- Run initialization when resource starts
CreateThread(function()
    InitializeDatabase()
end)

-- Export for manual re-initialization if needed
exports('ReinitializeDatabase', InitializeDatabase)

print('^2[PF-MECHANIC SQL] Auto-injection system loaded^0')
