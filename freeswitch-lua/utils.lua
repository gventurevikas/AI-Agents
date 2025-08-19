-- Utilities module for Live GPT AI Agent
-- Common helper functions and utilities

local utils = {}

-- Text processing utilities
function utils.split_text_for_tts(text, max_len)
    local chunks = {}
    local buffer = ""

    max_len = max_len or 200

    -- Remove decimal .00 from numbers
    text = text:gsub("(%d+)%.00", "%1")

    -- Split by sentences
    for sentence in text:gmatch("[^%.!?]+[%.!?]*") do
        sentence = sentence:gsub("^%s+", "")
        sentence = sentence:gsub("%s+$", "")

        if #buffer + #sentence + 1 <= max_len then
            buffer = buffer .. " " .. sentence
        else
            table.insert(chunks, buffer)
            buffer = sentence
        end
    end

    if buffer ~= "" then
        table.insert(chunks, buffer)
    end

    -- Separate the last chunk
    local last_chunk = ""
    if #chunks > 0 then
        last_chunk = table.remove(chunks)
    end

    return chunks, last_chunk
end

function utils.expand_contractions(sentence)
    local contractions = {
        ["[Tt]hat's"] = "That is",
        ["[Ii]t's"] = "It is",
        ["[Yy]ou're"] = "You are",
        ["[Ww]e're"] = "We are",
        ["[Ii]'m"] = "I am",
        ["[Dd]on't"] = "do not",
        ["[Cc]an't"] = "cannot",
        ["[Ww]on't"] = "will not",
        ["[Ss]houldn't"] = "should not",
        ["[Ww]ouldn't"] = "would not",
        ["[Hh]asn't"] = "has not",
        ["[Hh]aven't"] = "have not"
    }

    for pattern, replacement in pairs(contractions) do
        sentence = sentence:gsub(pattern, replacement)
    end

    return sentence
end

-- File utilities
function utils.file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    else
        return false
    end
end

function utils.ensure_directory(path)
    local dir = path:match("(.*)/")
    if dir then
        os.execute("mkdir -p " .. dir)
    end
end

-- String utilities
function utils.is_empty(str)
    return not str or str == "" or str:match("^%s*$")
end

function utils.trim(str)
    if not str then return "" end
    return str:match("^%s*(.-)%s*$") or ""
end

function utils.capitalize_first(str)
    if not str or str == "" then return str end
    return str:sub(1,1):upper() .. str:sub(2):lower()
end

-- Table utilities
function utils.table_is_empty(t)
    return not t or next(t) == nil
end

function utils.table_length(t)
    if not t then return 0 end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function utils.table_merge(t1, t2)
    if not t1 then return t2 end
    if not t2 then return t1 end
    
    local result = {}
    for k, v in pairs(t1) do
        result[k] = v
    end
    for k, v in pairs(t2) do
        result[k] = v
    end
    return result
end

function utils.table_deep_copy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[utils.table_deep_copy(orig_key)] = utils.table_deep_copy(orig_value)
        end
        setmetatable(copy, utils.table_deep_copy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Validation utilities
function utils.validate_session(session)
    return session and session:ready()
end

function utils.validate_uuid(uuid)
    if not uuid then return false end
    -- Basic UUID validation (8-4-4-4-12 format)
    return uuid:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")
end

function utils.validate_conversation_id(conversation_id)
    return utils.validate_uuid(conversation_id)
end

-- Time utilities
function utils.format_duration(ms)
    if not ms or ms < 1000 then
        return string.format("%dms", ms or 0)
    elseif ms < 60000 then
        return string.format("%.1fs", ms / 1000)
    else
        local minutes = math.floor(ms / 60000)
        local seconds = math.floor((ms % 60000) / 1000)
        return string.format("%dm %ds", minutes, seconds)
    end
end

function utils.get_timestamp()
    return os.time()
end

function utils.get_timestamp_ms()
    return math.floor(os.clock() * 1000)
end

-- Error handling utilities
function utils.safe_call(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        return false, result
    end
    return true, result
end

function utils.retry_operation(operation, max_attempts, delay_ms)
    max_attempts = max_attempts or 3
    delay_ms = delay_ms or 1000
    
    for attempt = 1, max_attempts do
        local success, result = operation()
        if success then
            return true, result
        end
        
        if attempt < max_attempts then
            if freeswitch and freeswitch.msleep then
                freeswitch.msleep(delay_ms)
            else
                -- Fallback for non-FreeSWITCH environments
                os.execute("sleep " .. (delay_ms / 1000))
            end
        end
    end
    
    return false, "Max retry attempts exceeded"
end

-- HTTP utilities
function utils.build_curl_command(method, url, data, headers)
    local command = string.format("curl --location --request %s '%s'", method:upper(), url)
    
    if headers then
        for key, value in pairs(headers) do
            command = command .. string.format(" --header '%s: %s'", key, value)
        end
    end
    
    if data and data ~= "" then
        command = command .. string.format(" --data '%s'", data)
    end
    
    return command
end

function utils.execute_curl_command(command)
    local handle = io.popen(command, "r")
    if not handle then
        return false, "Failed to execute cURL command"
    end
    
    local output = ""
    for line in handle:lines() do
        output = output .. line
    end
    handle:close()
    
    return true, output
end

-- Audio utilities
function utils.generate_filename(prefix, uuid, extension)
    extension = extension or "wav"
    return string.format("%s_%s.%s", prefix, uuid, extension)
end

function utils.cleanup_temp_files(files)
    if not files then return end
    
    for _, file in ipairs(files) do
        if utils.file_exists(file) then
            os.remove(file)
        end
    end
end

-- Session utilities
function utils.wait_for_session_ready(session, max_attempts, delay_ms)
    max_attempts = max_attempts or 10
    delay_ms = delay_ms or 100
    
    for attempt = 1, max_attempts do
        if session:ready() then
            return true
        end
        if freeswitch and freeswitch.msleep then
            freeswitch.msleep(delay_ms)
        else
            -- Fallback for non-FreeSWITCH environments
            os.execute("sleep " .. (delay_ms / 1000))
        end
    end
    
    return false
end

function utils.get_session_info(session)
    if not session then return nil end
    
    return {
        uuid = session:get_uuid(),
        ready = session:ready(),
        caller_id = session:getVariable("caller_id_number"),
        destination = session:getVariable("destination_number"),
        sip_from = session:getVariable("sip_from_user"),
        conversation_id = session:getVariable("conversation_id"),
        customer_id = session:getVariable("customer_id")
    }
end

return utils
