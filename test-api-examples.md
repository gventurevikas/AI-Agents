# API Testing Examples

## 1. Initialize Call

```bash
curl -X POST https://your-api-server.com/api/voice/init \
  -H "Content-Type: application/json" \
  -H "x-api-key: your_api_key" \
  -d '{
    "type": "conversation_initiation_client_data",
    "dynamic_variables": {
      "client_name": "Aiden Green",
      "address": "85 The Birches, Reading, RG30 6EL",
      "agent_name": "Sage"
    },
    "conversation_config_override": {
      "agent": {
        "first_message": "Hello Aiden Green, it's Sage from Heat Plan, the boiler people. Just a quick call to get the breakdown cover on your boiler back in place for this year.",
        "language": "en"
      }
    }
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "timestamp": "2024-01-15T10:30:00.000Z",
  "conversation_id": "call-uuid-123",
  "client_data": {
    "client_name": "Aiden Green",
    "address": "85 The Birches, Reading, RG30 6EL",
    "agent_name": "Sage"
  },
  "conversation_config": {
    "first_message": "Hello Aiden Green, it's Sage from Heat Plan...",
    "language": "en"
  },
  "call_status": {
    "stage": "introduction",
    "ready_for_customer": true,
    "agent_message": "Hello Aiden Green, it's Sage from Heat Plan..."
  }
}
```

## 2. Start Conversation (Name Verification)

```bash
curl -X POST https://your-api-server.com/api/voice/conversation \
  -H "Content-Type: application/json" \
  -H "x-api-key: your_api_key" \
  -d '{
    "customer_message": "Yes, that is me",
    "conversation_id": "call-uuid-123",
    "call_stage": "introduction"
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "timestamp": "2024-01-15T10:30:00.000Z",
  "conversation_id": "call-uuid-123",
  "agent_reply": "Is this Aiden Green?",
  "next_stage": "name_verification",
  "confidence_score": 0.9,
  "knowledge_used": [],
  "customer_intent": "confirmation",
  "current_stage": "name_verification",
  "transfer_to_human": false,
  "selected_plan": null,
  "call_actions": {
    "should_transfer": false,
    "should_transfer_to_billing": false,
    "next_action": "continue_call"
  }
}
```

## 3. Address Verification

```bash
curl -X POST https://your-api-server.com/api/voice/conversation \
  -H "Content-Type: application/json" \
  -H "x-api-key: your_api_key" \
  -d '{
    "customer_message": "Yes, that is correct",
    "conversation_id": "call-uuid-123",
    "call_stage": "name_verification"
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "agent_reply": "I have your address as 85 The Birches, Reading, RG30 6EL. Is that correct?",
  "next_stage": "address_verification",
  "customer_intent": "confirmation",
  "transfer_to_human": false
}
```

## 4. Plan Selection

```bash
curl -X POST https://your-api-server.com/api/voice/conversation \
  -H "Content-Type: application/json" \
  -H "x-api-key: your_api_key" \
  -d '{
    "customer_message": "Yes, that is right",
    "conversation_id": "call-uuid-123",
    "call_stage": "address_verification"
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "agent_reply": "Great! Now, I have two plans available for you. The Basic Package is £24 per month and covers your boiler and controls, parts and labour costs, unlimited callouts, and 24-hour response time. The Plus Package is £28 per month and covers your whole central heating system including radiators and pipework. Both packages include annual boiler service. Which plan would you prefer - the Basic Package or the Plus Package?",
  "next_stage": "plan_selection",
  "customer_intent": "confirmation",
  "transfer_to_human": false
}
```

## 5. Plan Confirmation

```bash
curl -X POST https://your-api-server.com/api/voice/conversation \
  -H "Content-Type: application/json" \
  -H "x-api-key: your_api_key" \
  -d '{
    "customer_message": "I will go with the Plus Package",
    "conversation_id": "call-uuid-123",
    "call_stage": "plan_selection"
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "agent_reply": "Perfect! You've selected the Plus package. I'll now transfer you to our billing team to finalize your payment details. Thank you for your time, Aiden Green.",
  "next_stage": "transfer_to_billing",
  "customer_intent": "plan_selection",
  "transfer_to_human": true,
  "selected_plan": "Plus",
  "call_actions": {
    "should_transfer": true,
    "should_transfer_to_billing": true,
    "next_action": "transfer_to_billing_team"
  }
}
```

## 6. Transfer to Billing

```bash
curl -X POST https://your-api-server.com/api/voice/transfer \
  -H "Content-Type: application/json" \
  -H "x-api-key: your_api_key" \
  -d '{
    "conversation_id": "call-uuid-123",
    "transfer_reason": "Plan selected",
    "selected_plan": "Plus",
    "billing_agent_id": "billing_001"
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Call transferred to billing team successfully",
  "conversation_id": "call-uuid-123",
  "transfer_details": {
    "reason": "Plan selected",
    "selected_plan": "Plus",
    "billing_agent_id": "billing_001",
    "timestamp": "2024-01-15T10:30:00.000Z"
  }
}
```

## 7. Check Call Status

```bash
curl -X GET https://your-api-server.com/api/voice/status/call-uuid-123 \
  -H "x-api-key: your_api_key"
```

**Expected Response:**
```json
{
  "success": true,
  "data": {
    "conversation": {
      "id": "call-uuid-123",
      "customer_name": "Aiden Green",
      "current_stage": "transfer_to_billing",
      "created_at": "2024-01-15T10:30:00.000Z"
    },
    "call_history": [
      {
        "message_type": "agent",
        "message_content": "Hello Aiden Green, it's Sage from Heat Plan...",
        "timestamp": "2024-01-15T10:30:00.000Z"
      },
      {
        "message_type": "customer",
        "message_content": "Yes, that is me",
        "timestamp": "2024-01-15T10:30:05.000Z"
      }
    ],
    "available_stages": {
      "introduction": "introduction",
      "name_verification": "name_verification",
      "address_verification": "address_verification",
      "plan_selection": "plan_selection",
      "plan_confirmation": "plan_confirmation",
      "transfer_to_billing": "transfer_to_billing"
    },
    "call_progress": {
      "current_stage": "transfer_to_billing",
      "total_stages": 6,
      "stage_number": 6
    }
  }
}
```

## Test Scenarios

### Happy Path (Successful Call)
1. Initialize call with client data
2. Customer confirms name
3. Customer confirms address
4. Customer selects plan (Basic or Plus)
5. Transfer to billing team

### Objection Handling
1. Customer says "I'm not interested" → Handle objection
2. Customer says "It's too expensive" → Handle objection
3. Customer says "Who are you?" → Handle objection
4. Continue with normal flow after objection

### Wrong Information
1. Customer says wrong name → End call
2. Customer says wrong address → End call
3. Customer doesn't recognize the call → Handle objection

## Call Flow Summary

```
Introduction → Name Verification → Address Verification → Plan Selection → Plan Confirmation → Transfer to Billing
```

Each stage:
- ✅ **Verifies information** using client data
- ✅ **Handles objections** appropriately
- ✅ **Progresses naturally** to next stage
- ✅ **Transfers to billing** when plan is selected 