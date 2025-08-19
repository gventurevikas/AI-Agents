-- Conversation Manager module for Live GPT AI Agent
-- Handles conversation flow, transfer logic, and state management

local config = require("config")
local logger = require("logger").log
local utils = require("utils")
local APIClient = require("api_client")

local Manager = {}
Manager.__index = Manager

function Manager.new()
    local self = setmetatable({}, Manager)
    self.api_client = APIClient.new()
    return self
end

-- Start a new conversation
function Manager:start_conversation(session, uuid, customer_info)
    if not utils.validate_session(session) then
        logger:error("Session is not active for conversation start")
        return false, nil
    end
    
    if not customer_info then
        logger:error("Customer info is required to start conversation")
        return false, nil
    end
    
    logger:info("Starting new conversation", { uuid = uuid, customer_id = customer_info.customerId })
    
    -- Start outbound call via API
    local success, response = self.api_client:start_outbound_call(customer_info)
    if not success then
        logger:error("Failed to start outbound call")
        return false, nil
    end
    
    -- Store conversation ID in session
    session:setVariable("conversation_id", response.conversationId)
    session:setVariable("customer_id", response.conversation.customerId)
    
    logger:session_event("conversation_started", response.conversationId, {
        uuid = uuid,
        customer_id = customer_info.customerId,
        opening_script_length = #response.openingScript
    })
    
    return true, response
end

-- Continue an existing conversation
function Manager:continue_conversation(session, customer_response, customer_info)
    if not utils.validate_session(session) then
        logger:error("Session is not active for conversation continuation")
        return false, nil
    end
    
    local conversation_id = session:getVariable("conversation_id")
    if not conversation_id then
        logger:error("No conversation ID found for continuation")
        return false, nil
    end
    
    if utils.is_empty(customer_response) then
        logger:error("Customer response is required for conversation continuation")
        return false, nil
    end
    
    logger:info("Continuing conversation", { 
        conversation_id = conversation_id, 
        response_length = #customer_response 
    })
    
    -- Continue conversation via API
    local success, response = self.api_client:continue_outbound_call(
        conversation_id, customer_response, customer_info
    )
    
    if not success then
        logger:error("Failed to continue conversation")
        return false, nil
    end
    
    logger:session_event("conversation_continued", conversation_id, {
        response_length = #response.response,
        has_transfer_status = response.transferStatus ~= nil
    })
    
    return true, response
end

-- Process conversation response and handle transfer logic
function Manager:process_conversation_response(session, response, customer_info, audio_processor)
    if not response then
        logger:error("No response to process")
        return false
    end
    
    local conversation_id = session:getVariable("conversation_id")
    if not conversation_id then
        logger:error("No conversation ID found for response processing")
        return false
    end
    
    logger:info("Processing conversation response", { conversation_id = conversation_id })
    
    -- Handle AI response
    if response.response then
        logger:info("AI response received", { response_length = #response.response })
        
        -- Send message to webhook
        self.api_client:send_webhook_message(session, "user1", response.response)
        
        -- Play AI response
        local last_part = audio_processor:play_content(session, response.response)
        
        -- Generate TTS for last part if needed
        if last_part and last_part ~= "" then
            local tts_success, audio = audio_processor:generate_tts(session, last_part)
            if tts_success and audio then
                local audio_url = audio.filename
                local get_content_success, state, content = audio_processor:get_content(
                    session:get_uuid(), session, audio_url, 10000
                )
                
                if get_content_success then
                    -- Send customer response to webhook
                    self.api_client:send_webhook_message(session, "user2", content)
                    
                    -- Process customer response for next iteration
                    return self:handle_customer_response(session, content, customer_info, audio_processor)
                else
                    logger:error("Failed to get content from audio")
                    return false
                end
            else
                logger:error("Failed to generate TTS for last part")
                return false
            end
        end
    end
    
    -- Handle conversation metadata
    self:process_conversation_metadata(session, response)
    
    -- Handle transfer status
    if response.transferStatus then
        return self:handle_transfer_status(session, response, customer_info, audio_processor)
    end
    
    return true
end

-- Process conversation metadata (customer info, objections, etc.)
function Manager:process_conversation_metadata(session, response)
    local conversation_id = session:getVariable("conversation_id")
    
    -- Handle customer info updates
    if response.conversation and response.conversation.customerInfo then
        local customer_info = response.conversation.customerInfo
        logger:info("Customer info updated", {
            conversation_id = conversation_id,
            postcode = customer_info.postcode,
            address = customer_info.address,
            agent_name = customer_info.agentName,
            customer_name = customer_info.customerName
        })
    end
    
    -- Handle objections
    if response.conversation and response.conversation.objections then
        local objections = response.conversation.objections
        if #objections > 0 then
            logger:info("Objections detected", {
                conversation_id = conversation_id,
                count = #objections,
                objections = objections
            })
        else
            logger:debug("No objections detected", { conversation_id = conversation_id })
        end
    end
    
    -- Handle qualification answers
    if response.conversation and response.conversation.qualificationAnswers then
        local qual_answers = response.conversation.qualificationAnswers
        if not utils.table_is_empty(qual_answers) then
            logger:info("Qualification answers received", {
                conversation_id = conversation_id,
                answers = qual_answers
            })
        end
    end
    
    -- Handle savings estimate
    if response.conversation and response.conversation.savingsEstimate then
        logger:info("Savings estimate received", {
            conversation_id = conversation_id,
            estimate = response.conversation.savingsEstimate
        })
    end
    
    -- Handle next action
    if response.conversation and response.conversation.nextAction then
        logger:info("Next action specified", {
            conversation_id = conversation_id,
            action = response.conversation.nextAction
        })
    end
end

-- Handle transfer status and logic
function Manager:handle_transfer_status(session, response, customer_info, audio_processor)
    local conversation_id = session:getVariable("conversation_id")
    local transfer_status = response.transferStatus
    
    logger:info("Processing transfer status", {
        conversation_id = conversation_id,
        is_ready = transfer_status.isReady,
        confidence = transfer_status.confidence,
        reason = transfer_status.reason,
        blank_response_count = transfer_status.blankResponseCount or 0
    })
    
    -- Handle blank response count
    if transfer_status.blankResponseCount and transfer_status.blankResponseCount >= config.transfer.max_blank_responses then
        logger:info("Too many blank responses, ending call", {
            conversation_id = conversation_id,
            count = transfer_status.blankResponseCount
        })
        self:cleanup_conversation(session, "Too many blank responses")
        session:hangup()
        return false
    end
    
    -- Check if customer is ready for transfer
    if transfer_status.isReady and transfer_status.confidence >= config.transfer.min_confidence then
        logger:info("Customer ready for transfer", {
            conversation_id = conversation_id,
            confidence = transfer_status.confidence
        })
        
        return self:execute_transfer(session, conversation_id, response, audio_processor)
    else
        logger:info("Customer not ready for transfer", {
            conversation_id = conversation_id,
            reason = transfer_status.reason,
            confidence = transfer_status.confidence or 0
        })
        
        -- Log missing items for debugging
        if transfer_status.missingItems then
            logger:info("Missing items for transfer", {
                conversation_id = conversation_id,
                items = transfer_status.missingItems
            })
        end
        
        return true
    end
end

-- Execute transfer process
function Manager:execute_transfer(session, conversation_id, response, audio_processor)
    logger:info("Executing transfer process", { conversation_id = conversation_id })
    
    -- Check if transfer has already been initiated
    local transfer_initiated = session:getVariable("transfer_initiated")
    if not transfer_initiated or transfer_initiated ~= "true" then
        -- Initiate transfer
        local transfer_success = self.api_client:initiate_transfer(conversation_id)
        if not transfer_success then
            logger:error("Failed to initiate transfer", { conversation_id = conversation_id })
            return false
        end
        
        session:setVariable("transfer_initiated", "true")
        logger:transfer_event("transfer_initiated", conversation_id, { reason = "Customer ready for enrollment" })
        
        -- Play final message before transfer
        if response.response then
            self.api_client:send_webhook_message(session, "user1", response.response)
            local tts_success, audio = audio_processor:generate_tts(session, response.response)
            if tts_success and audio then
                local audio_url = audio.filename
                session:streamFile(config.paths.audio_generated .. audio_url)
            end
        end
        
        -- Complete the transfer
        local transfer_complete = self.api_client:complete_transfer(conversation_id)
        if transfer_complete then
            logger:transfer_event("transfer_completed", conversation_id, { reason = "billing_enrollment" })
            session:setVariable("transfer_completed", "true")
            
            -- Cleanup and hangup
            self:cleanup_conversation(session, "Transfer completed successfully")
            session:hangup()
            return false
        else
            logger:error("Failed to complete transfer", { conversation_id = conversation_id })
            return false
        end
    else
        logger:info("Transfer already initiated, proceeding to completion", { conversation_id = conversation_id })
        
        local transfer_complete = self.api_client:complete_transfer(conversation_id)
        if transfer_complete then
            logger:transfer_event("transfer_completed", conversation_id, { reason = "billing_enrollment" })
            session:setVariable("transfer_completed", "true")
            
            -- Cleanup and hangup
            self:cleanup_conversation(session, "Transfer completed successfully")
            session:hangup()
            return false
        else
            logger:error("Failed to complete transfer", { conversation_id = conversation_id })
            return false
        end
    end
end

-- Handle customer response and continue conversation
function Manager:handle_customer_response(session, content, customer_info, audio_processor)
    if utils.is_empty(content) then
        logger:debug("Empty customer response, skipping processing")
        return true
    end
    
    local conversation_id = session:getVariable("conversation_id")
    logger:info("Processing customer response", {
        conversation_id = conversation_id,
        content_length = #content
    })
    
    -- Continue conversation
    local success, response = self:continue_conversation(session, content, customer_info)
    if not success then
        logger:error("Failed to continue conversation")
        return false
    end
    
    -- Check conversation iteration limit
    local conversation_count = tonumber(session:getVariable("conversation_count") or "0")
    if conversation_count >= config.transfer.max_conversation_iterations then
        logger:warn("Maximum conversation iterations reached, ending call", {
            conversation_id = conversation_id,
            count = conversation_count
        })
        self:cleanup_conversation(session, "Maximum conversation iterations reached")
        session:hangup()
        return false
    end
    
    -- Increment conversation counter
    session:setVariable("conversation_count", tostring(conversation_count + 1))
    
    -- Process the response
    return self:process_conversation_response(session, response, customer_info, audio_processor)
end

-- Cleanup conversation when call ends
function Manager:cleanup_conversation(session, reason)
    local conversation_id = session:getVariable("conversation_id")
    if not conversation_id then
        logger:info("No conversation ID found for cleanup")
        return
    end
    
    logger:info("Cleaning up conversation", { conversation_id = conversation_id, reason = reason })
    
    -- Check transfer status
    local transfer_completed = session:getVariable("transfer_completed")
    local transfer_initiated = session:getVariable("transfer_initiated")
    
    local close_reason = reason or "Call ended"
    if transfer_completed == "true" then
        close_reason = "Transfer completed successfully"
    elseif transfer_initiated == "true" then
        close_reason = "Transfer initiated but call ended before completion"
    end
    
    -- Close conversation via API
    local close_success = self.api_client:close_conversation(conversation_id, close_reason)
    if close_success then
        logger:info("Conversation cleanup completed successfully", { conversation_id = conversation_id })
    else
        logger:error("Conversation cleanup failed", { conversation_id = conversation_id })
    end
end

return Manager
