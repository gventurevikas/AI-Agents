-- Main application file for Live GPT AI Agent
-- Orchestrates all modules and handles the main call flow

local config = require("config")
local logger = require("logger").log
local utils = require("utils")
local AudioProcessor = require("audio")
local Manager = require("manager")

-- Main application class
local LiveGPTAgent = {}
LiveGPTAgent.__index = LiveGPTAgent

function LiveGPTAgent.new()
    local self = setmetatable({}, LiveGPTAgent)
    self.audio_processor = AudioProcessor.new()
    self.manager = Manager.new()
    return self
end

-- Initialize the agent
function LiveGPTAgent:initialize(session)
    if not utils.validate_session(session) then
        logger:error("Invalid session for agent initialization")
        return false
    end
    
    logger:info("Initializing Live GPT AI Agent")
    
    -- Wait for session to be ready
    local session_ready = utils.wait_for_session_ready(
        session, 
        config.session.max_ready_attempts, 
        config.session.ready_timeout
    )
    
    if not session_ready then
        logger:error("Session never became ready after initialization attempts")
        return false
    end
    
    -- Set up session variables
    session:setVariable("conversation_count", "0")
    session:setVariable("transfer_initiated", "false")
    session:setVariable("transfer_completed", "false")
    
    logger:info("Live GPT AI Agent initialized successfully")
    return true
end

-- Handle call setup and initialization
function LiveGPTAgent:setup_call(session)
    if not utils.validate_session(session) then
        logger:error("Invalid session for call setup")
        return false
    end
    
    logger:info("Setting up call")
    
    -- Check if call is already answered
    local call_state = session:getVariable("call_state")
    logger:info("Current call state", { state = call_state })
    
    -- Answer the call if not already answered
    if call_state ~= "ACTIVE" then
        logger:info("Answering call")
        session:answer()
        if freeswitch and freeswitch.msleep then
            freeswitch.msleep(config.session.call_answer_delay)
        else
            -- Fallback for non-FreeSWITCH environments
            os.execute("sleep " .. (config.session.call_answer_delay / 1000))
        end
    else
        logger:info("Call already answered")
    end
    
    -- Get call UUID
    local uuid = session:get_uuid()
    if not uuid then
        logger:error("Failed to get call UUID")
        return false
    end
    
    logger:info("Call setup completed", { uuid = uuid })
    return true, uuid
end

-- Start the conversation
function LiveGPTAgent:start_conversation(session, uuid)
    if not utils.validate_session(session) then
        logger:error("Invalid session for conversation start")
        return false
    end
    
    logger:info("Starting conversation", { uuid = uuid })
    
    -- Get customer information
    local customer_info = self.manager.api_client:get_customer_info()
    if not customer_info then
        logger:error("Failed to get customer information")
        return false
    end
    
    -- Start conversation
    local success, response = self.manager:start_conversation(session, uuid, customer_info)
    if not success then
        logger:error("Failed to start conversation")
        return false
    end
    
    logger:info("Conversation started successfully", {
        conversation_id = response.conversationId,
        opening_script_length = #response.openingScript
    })
    
    return true, response, customer_info
end

-- Play opening script and get customer response
function LiveGPTAgent:play_opening_script(session, response, customer_info)
    if not utils.validate_session(session) then
        logger:error("Invalid session for opening script playback")
        return false
    end
    
    logger:info("Playing opening script", { script_length = #response.openingScript })
    
    -- Send opening script to webhook
    self.manager.api_client:send_webhook_message(session, "user1", response.openingScript)
    
    -- Play opening script
    local last_part = self.audio_processor:play_content(session, response.openingScript)
    
    -- Generate TTS for last part if needed
    if last_part and last_part ~= "" then
        local tts_success, audio = self.audio_processor:generate_tts(session, last_part)
        if tts_success and audio then
            local audio_url = audio.filename
            
            -- Record customer response
            local get_content_success, state, content = self.audio_processor:get_content(
                session:get_uuid(), session, audio_url, 10000
            )
            
            if get_content_success then
                -- Send customer response to webhook
                self.manager.api_client:send_webhook_message(session, "user2", content)
                
                logger:info("Customer response received", { content_length = #content })
                return true, content
            else
                logger:error("Failed to get customer response")
                return false
            end
        else
            logger:error("Failed to generate TTS for last part")
            return false
        end
    end
    
    return true, ""
end

-- Main conversation loop
function LiveGPTAgent:run_conversation(session, initial_content, customer_info)
    if not utils.validate_session(session) then
        logger:error("Invalid session for conversation loop")
        return false
    end
    
    if utils.is_empty(initial_content) then
        logger:info("No initial content, starting conversation loop")
        return true
    end
    
    logger:info("Starting conversation loop with initial content", { content_length = #initial_content })
    
    -- Process initial customer response
    local success = self.manager:handle_customer_response(
        session, initial_content, customer_info, self.audio_processor
    )
    
    if not success then
        logger:error("Failed to process initial customer response")
        return false
    end
    
    return true
end

-- Cleanup resources
function LiveGPTAgent:cleanup(session)
    if not session then
        logger:warn("No session provided for cleanup")
        return
    end
    
    logger:info("Cleaning up Live GPT AI Agent")
    
    -- Cleanup conversation
    self.manager:cleanup_conversation(session, "Call ended")
    
    -- Cleanup audio processor
    self.audio_processor:cleanup()
    
    logger:info("Live GPT AI Agent cleanup completed")
end

-- Main execution function
function LiveGPTAgent:run(session)
    if not session then
        logger:error("No session provided to Live GPT AI Agent")
        return
    end
    
    logger:info("Live GPT AI Agent starting")
    
    -- Initialize agent
    local init_success = self:initialize(session)
    if not init_success then
        logger:error("Failed to initialize Live GPT AI Agent")
        return
    end
    
    -- Setup call
    local setup_success, uuid = self:setup_call(session)
    if not setup_success then
        logger:error("Failed to setup call")
        return
    end
    
    -- Start conversation
    local conv_success, response, customer_info = self:start_conversation(session, uuid)
    if not conv_success then
        logger:error("Failed to start conversation")
        return
    end
    
    -- Play opening script and get customer response
    local play_success, initial_content = self:play_opening_script(session, response, customer_info)
    if not play_success then
        logger:error("Failed to play opening script")
        return
    end
    
    -- Run conversation loop
    local run_success = self:run_conversation(session, initial_content, customer_info)
    if not run_success then
        logger:error("Failed to run conversation loop")
        return
    end
    
    logger:info("Live GPT AI Agent execution completed successfully")
end

-- Create global instance
local agent = LiveGPTAgent.new()

-- Main execution block
local function main(session)
    logger:info("Main function called", { session = tostring(session) })
    
    if not session then
        logger:error("No session provided to main function")
        return
    end
    
    -- Run the agent
    agent:run(session)
    
    -- Cleanup when main function ends
    agent:cleanup(session)
end

-- Session initialization and validation
if not session then
    logger:error("Session variable not available, trying to get from current channel")
    
    -- Try to get session from current channel
    local current_session
    if freeswitch and freeswitch.Session then
        current_session = freeswitch.Session("current")
    else
        current_session = nil
    end
    if current_session then
        logger:info("Got session from current channel", { session = tostring(current_session) })
        session = current_session
    else
        logger:error("Could not get session from current channel")
        return
    end
end

-- Wait for session to be fully initialized
if session then
    logger:info("Waiting for session to be ready")
    
    local attempts = 0
    while not session:ready() and attempts < config.session.max_ready_attempts do
        if freeswitch and freeswitch.msleep then
            freeswitch.msleep(100)
        else
            -- Fallback for non-FreeSWITCH environments
            os.execute("sleep 0.1")
        end
        attempts = attempts + 1
        logger:debug("Session ready check attempt", { attempt = attempts, ready = session:ready() })
    end
    
    if not session:ready() then
        logger:error("Session never became ready after initialization attempts", { attempts = attempts })
        return
    end
    
    logger:info("Session is now ready")
    
    -- Check call establishment
    local call_uuid = session:getVariable("uuid")
    if call_uuid then
        logger:info("Call UUID from variables", { uuid = call_uuid })
    else
        logger:warn("No call UUID found in variables")
    end
end

-- Get final UUID and set up ambience
local uuid = session:get_uuid()
if uuid then
    logger:info("Final call UUID", { uuid = uuid })
end

-- Play background ambience
session:execute("displace_session", config.paths.ambience .. " mux")

-- Execute main function
main(session)

-- Set up hangup handler for cleanup
if session then
    session:setInputCallback("hangup_handler", function(s, type, obj)
        if type == "event" and obj:getHeader("Event-Name") == "CHANNEL_HANGUP" then
            logger:info("Call hangup detected, performing cleanup")
            agent:cleanup(s)
        end
        return true
    end)
end
