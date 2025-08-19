-- Simple launcher script for Live GPT AI Agent
-- This file can be used as a direct entry point in FreeSWITCH

-- Load required modules
local config = require("config")
local logger = require("logger").log
local utils = require("utils")
local AudioProcessor = require("audio")
local Manager = require("manager")

-- Initialize components
local audio_processor = AudioProcessor.new()
local manager = Manager.new()

-- Main execution function
local function main(session)
    logger:info("Live GPT AI Agent launcher started")
    
    if not session then
        logger:error("No session provided")
        return
    end
    
    -- Initialize session
    if not utils.wait_for_session_ready(session, config.session.max_ready_attempts, config.session.ready_timeout) then
        logger:error("Session initialization failed")
        return
    end
    
    -- Setup call
    local uuid = session:get_uuid()
    if not uuid then
        logger:error("Failed to get call UUID")
        return
    end
    
    logger:info("Call setup", { uuid = uuid })
    
    -- Answer call if needed
    local call_state = session:getVariable("call_state")
    if call_state ~= "ACTIVE" then
        session:answer()
        if freeswitch and freeswitch.msleep then
            freeswitch.msleep(config.session.call_answer_delay)
        else
            -- Fallback for non-FreeSWITCH environments
            os.execute("sleep " .. (config.session.call_answer_delay / 1000))
        end
    end
    
    -- Get customer info
    local customer_info = manager.api_client:get_customer_info()
    if not customer_info then
        logger:error("Failed to get customer information")
        session:hangup()
        return
    end
    
    -- Start conversation
    local success, response = manager:start_conversation(session, uuid, customer_info)
    if not success then
        logger:error("Failed to start conversation")
        session:hangup()
        return
    end
    
    -- Play opening script
    if response.openingScript then
        manager.api_client:send_webhook_message(session, "user1", response.openingScript)
        local last_part = audio_processor:play_content(session, response.openingScript)
        
        if last_part and last_part ~= "" then
            local tts_success, audio = audio_processor:generate_tts(session, last_part)
            if tts_success and audio then
                local audio_url = audio.filename
                local get_content_success, state, content = audio_processor:get_content(
                    uuid, session, audio_url, 10000
                )
                
                if get_content_success and not utils.is_empty(content) then
                    manager.api_client:send_webhook_message(session, "user2", content)
                    
                    -- Process customer response
                    manager:handle_customer_response(session, content, customer_info, audio_processor)
                end
            end
        end
    end
    
    -- Cleanup
    manager:cleanup_conversation(session, "Call ended")
    audio_processor:cleanup()
    
    logger:info("Live GPT AI Agent launcher completed")
end

-- Execute main function
if session then
    main(session)
else
    logger:error("No session available")
end
