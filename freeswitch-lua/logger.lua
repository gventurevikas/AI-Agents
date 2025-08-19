-- Logger module for Live GPT AI Agent
-- Provides structured logging with different levels and formatting

local config = require("config")
local json = require("cjson")

local Logger = {}
Logger.__index = Logger

-- Log levels
Logger.LEVELS = {
    DEBUG = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3,
    FATAL = 4
}

-- Level names for display
Logger.LEVEL_NAMES = {
    [0] = "DEBUG",
    [1] = "INFO", 
    [2] = "WARN",
    [3] = "ERROR",
    [4] = "FATAL"
}

-- ANSI color codes for console output
Logger.COLORS = {
    DEBUG = "\27[36m", -- Cyan
    INFO = "\27[32m",  -- Green
    WARN = "\27[33m",  -- Yellow
    ERROR = "\27[31m", -- Red
    FATAL = "\27[35m", -- Magenta
    RESET = "\27[0m"   -- Reset
}

function Logger.new(component)
    local self = setmetatable({}, Logger)
    self.component = component or "LiveGPT"
    self.log_level = Logger.LEVELS[string.upper(config.logging.level or "info")]
    return self
end

-- Format timestamp
function Logger:format_timestamp()
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local milliseconds = math.floor((os.clock() % 1) * 1000)
    return string.format("%s.%03d", timestamp, milliseconds)
end

-- Format log message
function Logger:format_message(level, message, data)
    local timestamp = self:format_timestamp()
    local level_name = Logger.LEVEL_NAMES[level]
    local formatted_message = string.format("[%s] [%s] [%s] %s", 
        timestamp, level_name, self.component, message)
    
    if data then
        if type(data) == "table" then
            formatted_message = formatted_message .. "\n" .. json.encode(data)
        else
            formatted_message = formatted_message .. " | Data: " .. tostring(data)
        end
    end
    
    return formatted_message
end

-- Write to console with colors
function Logger:write_console(level, message, data)
    if not config.logging.enable_console then
        return
    end
    
    local level_name = Logger.LEVEL_NAMES[level]
    local color = Logger.COLORS[level_name] or Logger.COLORS.RESET
    local reset = Logger.COLORS.RESET
    
    local formatted_message = self:format_message(level, message, data)
    
    -- Check if freeswitch is available (FreeSWITCH environment)
    if freeswitch and freeswitch.consoleLog then
        freeswitch.consoleLog(level_name:lower(), color .. formatted_message .. reset .. "\n")
    else
        -- Fallback for non-FreeSWITCH environments (testing, development)
        print(string.format("[%s] %s", level_name, formatted_message))
    end
end

-- Write to file (future implementation)
function Logger:write_file(level, message, data)
    if not config.logging.enable_file then
        return
    end
    
    -- TODO: Implement file logging with rotation
    -- This would write to config.logging.log_file
end

-- Main logging function
function Logger:log(level, message, data)
    if level < self.log_level then
        return
    end
    
    self:write_console(level, message, data)
    self:write_file(level, message, data)
end

-- Convenience methods for each log level
function Logger:debug(message, data)
    self:log(Logger.LEVELS.DEBUG, message, data)
end

function Logger:info(message, data)
    self:log(Logger.LEVELS.INFO, message, data)
end

function Logger:warn(message, data)
    self:log(Logger.LEVELS.WARN, message, data)
end

function Logger:error(message, data)
    self:log(Logger.LEVELS.ERROR, message, data)
end

function Logger:fatal(message, data)
    self:log(Logger.LEVELS.FATAL, message, data)
end

-- Specialized logging methods
function Logger:api_call(method, url, data)
    self:debug("API Call", {
        method = method,
        url = url,
        data = data
    })
end

function Logger:api_response(method, url, status, response)
    self:debug("API Response", {
        method = method,
        url = url,
        status = status,
        response = response
    })
end

function Logger:session_event(event, session_id, details)
    self:info("Session Event", {
        event = event,
        session_id = session_id,
        details = details
    })
end

function Logger:transfer_event(event, conversation_id, details)
    self:info("Transfer Event", {
        event = event,
        conversation_id = conversation_id,
        details = details
    })
end

function Logger:audio_event(event, filename, details)
    self:debug("Audio Event", {
        event = event,
        filename = filename,
        details = details
    })
end

-- Performance logging
function Logger:performance(operation, duration_ms, details)
    self:debug("Performance", {
        operation = operation,
        duration_ms = duration_ms,
        details = details
    })
end

-- Error logging with stack trace
function Logger:error_with_trace(message, error_obj)
    local traceback = debug.traceback()
    self:error(message, {
        error = tostring(error_obj),
        traceback = traceback
    })
end

-- Create default logger instance
local default_logger = Logger.new("LiveGPT")

-- Export both the class and default instance
return {
    Logger = Logger,
    log = default_logger
}
