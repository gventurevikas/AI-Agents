-- API Client module for Live GPT AI Agent
-- Handles all external API communications

local config = require("config")
local logger = require("logger").log
local utils = require("utils")

local APIClient = {}
APIClient.__index = APIClient

function APIClient.new()
    local self = setmetatable({}, APIClient)
    return self
end

-- Generic API call function
function APIClient:make_request(method, url, data, headers)
    local start_time = utils.get_timestamp_ms()
    
    -- Merge default headers with custom headers
    local request_headers = utils.table_merge(config.http.headers, headers or {})
    
    -- Build cURL command
    local curl_command = utils.build_curl_command(method, url, data, request_headers)
    
    logger:api_call(method, url, data)
    
    -- Execute request
    local success, output = utils.execute_curl_command(curl_command)
    if not success then
        logger:error("API request failed", { method = method, url = url, error = output })
        return false, nil
    end
    
    local duration = utils.get_timestamp_ms() - start_time
    logger:performance("API Request", duration, { method = method, url = url })
    
    -- Parse response
    if utils.is_empty(output) then
        logger:error("Empty response from API", { method = method, url = url })
        return false, nil
    end
    
    local ok, response_data = utils.safe_call(json.decode, output)
    if not ok then
        logger:error("Failed to parse API response as JSON", { 
            method = method, 
            url = url, 
            response = output 
        })
        return false, nil
    end
    
    logger:api_response(method, url, "success", response_data)
    return true, response_data
end

-- Customer Info API
function APIClient:get_customer_info()
    logger:info("Fetching customer information from API")
    
    local success, response = self:make_request("GET", config.apis.customer_info)
    if not success then
        logger:error("Failed to fetch customer information")
        return nil
    end
    
    -- Parse and validate response
    if not response or not response.dynamic_variables then
        logger:error("Invalid customer info response format")
        return nil
    end
    
    local customer_info = {
        customerId = "outbound_test_" .. os.time(),
        customerInfo = {
            customerName = response.dynamic_variables.client_name or "Customer",
            agentName = response.dynamic_variables.agent_name or "Agent",
            address = response.dynamic_variables.address or "",
            postcode = response.dynamic_variables.postcode or "SM6 5DD"
        }
    }
    
    logger:info("Customer information retrieved successfully", customer_info)
    return customer_info
end

-- Outbound Calls API
function APIClient:start_outbound_call(customer_info)
    if not customer_info then
        logger:error("Customer info is required to start outbound call")
        return false, nil
    end
    
    logger:info("Starting outbound call", { customer_id = customer_info.customerId })
    
    local request_body = json.encode(customer_info)
    local success, response = self:make_request("POST", config.apis.outbound_calls, request_body)
    
    if not success then
        logger:error("Failed to start outbound call")
        return false, nil
    end
    
    if not response or not response.openingScript then
        logger:error("Invalid outbound call response - missing opening script")
        return false, nil
    end
    
    logger:info("Outbound call started successfully", {
        conversation_id = response.conversationId,
        customer_id = response.conversation.customerId
    })
    
    return true, response
end

function APIClient:continue_outbound_call(conversation_id, customer_response, customer_info)
    if not utils.validate_conversation_id(conversation_id) then
        logger:error("Invalid conversation ID for continue call", { conversation_id = conversation_id })
        return false, nil
    end
    
    if utils.is_empty(customer_response) then
        logger:error("Customer response is required to continue call")
        return false, nil
    end
    
    logger:info("Continuing outbound call", { 
        conversation_id = conversation_id, 
        response_length = #customer_response 
    })
    
    local request_data = {
        customerResponse = customer_response,
        customerId = customer_info.customerInfo.customerId or "unknown",
        customerInfo = customer_info.customerInfo
    }
    
    local request_body = json.encode(request_data)
    local url = config.apis.outbound_calls .. "/" .. conversation_id .. "/continue"
    
    local success, response = self:make_request("POST", url, request_body)
    
    if not success then
        logger:error("Failed to continue outbound call")
        return false, nil
    end
    
    if not response or not response.response then
        logger:error("Invalid continue call response - missing response")
        return false, nil
    end
    
    logger:info("Outbound call continued successfully", {
        conversation_id = conversation_id,
        response_length = #response.response
    })
    
    return true, response
end

-- Conversations API
function APIClient:get_conversation_details(conversation_id)
    if not utils.validate_conversation_id(conversation_id) then
        logger:error("Invalid conversation ID for details", { conversation_id = conversation_id })
        return false, nil
    end
    
    logger:info("Getting conversation details", { conversation_id = conversation_id })
    
    local url = config.apis.conversations .. "/" .. conversation_id
    local success, response = self:make_request("GET", url)
    
    if not success then
        logger:error("Failed to get conversation details")
        return false, nil
    end
    
    logger:info("Conversation details retrieved successfully", { conversation_id = conversation_id })
    return true, response
end

function APIClient:close_conversation(conversation_id, reason)
    if not utils.validate_conversation_id(conversation_id) then
        logger:error("Invalid conversation ID for closure", { conversation_id = conversation_id })
        return false
    end
    
    logger:info("Closing conversation", { conversation_id = conversation_id, reason = reason })
    
    local request_data = {}
    if reason then
        request_data.reason = reason
    end
    
    local request_body = json.encode(request_data)
    local url = config.apis.conversations .. "/" .. conversation_id .. "/close"
    
    local success, response = self:make_request("POST", url, request_body)
    
    if not success then
        logger:error("Failed to close conversation")
        return false
    end
    
    if response and response.message then
        logger:info("Conversation closed successfully", { 
            conversation_id = conversation_id, 
            message = response.message 
        })
        return true
    else
        logger:error("Invalid close conversation response")
        return false
    end
end

-- Transfer Management API
function APIClient:initiate_transfer(conversation_id, reason)
    if not utils.validate_conversation_id(conversation_id) then
        logger:error("Invalid conversation ID for transfer initiation", { conversation_id = conversation_id })
        return false
    end
    
    reason = reason or "Customer ready for enrollment"
    logger:info("Initiating transfer", { conversation_id = conversation_id, reason = reason })
    
    local request_data = { transferReason = reason }
    local request_body = json.encode(request_data)
    local url = config.apis.conversations .. "/" .. conversation_id .. "/initiate-transfer"
    
    local success, response = self:make_request("POST", url, request_body)
    
    if not success then
        logger:error("Failed to initiate transfer")
        return false
    end
    
    if response and response.success then
        logger:info("Transfer initiated successfully", { conversation_id = conversation_id })
        return true
    else
        local error_msg = response and response.message or "Unknown error"
        logger:error("Transfer initiation failed", { 
            conversation_id = conversation_id, 
            error = error_msg 
        })
        return false
    end
end

function APIClient:complete_transfer(conversation_id, reason)
    if not utils.validate_conversation_id(conversation_id) then
        logger:error("Invalid conversation ID for transfer completion", { conversation_id = conversation_id })
        return false
    end
    
    reason = reason or "billing_enrollment"
    logger:info("Completing transfer", { conversation_id = conversation_id, reason = reason })
    
    local request_data = { transferReason = reason }
    local request_body = json.encode(request_data)
    local url = config.apis.conversations .. "/" .. conversation_id .. "/transfer"
    
    local success, response = self:make_request("POST", url, request_body)
    
    if not success then
        logger:error("Failed to complete transfer")
        return false
    end
    
    if response and response.success then
        logger:info("Transfer completed successfully", { conversation_id = conversation_id })
        return true
    else
        local error_msg = response and response.message or "Unknown error"
        logger:error("Transfer completion failed", { 
            conversation_id = conversation_id, 
            error = error_msg 
        })
        return false
    end
end

function APIClient:get_transfer_status(conversation_id)
    if not utils.validate_conversation_id(conversation_id) then
        logger:error("Invalid conversation ID for transfer status", { conversation_id = conversation_id })
        return false, nil
    end
    
    logger:info("Getting transfer status", { conversation_id = conversation_id })
    
    local url = config.apis.conversations .. "/" .. conversation_id .. "/transfer-status"
    local success, response = self:make_request("GET", url)
    
    if not success then
        logger:error("Failed to get transfer status")
        return false, nil
    end
    
    logger:info("Transfer status retrieved successfully", { conversation_id = conversation_id })
    return true, response
end

-- Webhook API
function APIClient:send_webhook_message(session, person, content)
    if not utils.validate_session(session) then
        logger:error("Session is not active for webhook message")
        return false
    end
    
    if utils.is_empty(content) then
        logger:error("Message content is required for webhook")
        return false
    end
    
    local username = session:getVariable("sip_from_user")
    logger:info("Sending webhook message", { 
        username = username, 
        person = person, 
        content_length = #content 
    })
    
    local message_data = {
        sipUsername = username,
        message = { person = person, message = content },
        eventType = "chat"
    }
    
    local request_body = json.encode(message_data)
    
    -- Use HTTPS for webhook
    local response_body = {}
    local res, code, response_headers = https.request {
        url = config.apis.webhook,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#request_body)
        },
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_body),
        verify = "none"
    }
    
    if code == 200 then
        logger:info("Webhook message sent successfully")
        return true
    else
        local error_msg = string.format("Failed to send webhook message. Status code: %d", code)
        if #response_body > 0 then
            error_msg = error_msg .. ", Response: " .. table.concat(response_body)
        end
        logger:error(error_msg)
        return false
    end
end

return APIClient
