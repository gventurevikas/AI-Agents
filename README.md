# Sales Executive Agent API

An AI-powered sales executive agent built with Node.js and Anthropic's Claude API, featuring knowledge base integration and complete call flow management.

## Features

- 🤖 **AI-Powered Responses**: Uses Anthropic's Claude for intelligent sales conversations
- 📚 **Knowledge Base**: Stores and retrieves objection handling patterns from previous interactions
- 🔄 **Call Flow Management**: Tracks conversation stages and guides through sales process
- 🔒 **HTTPS Security**: SSL/TLS encryption for secure communications
- 📊 **Analytics**: Tracks response effectiveness and conversation success rates
- 🛡️ **Security**: API key authentication, rate limiting, and input validation

## Quick Start

### 1. Install Dependencies
```bash
npm install
```

### 2. Configure Environment
Copy the environment template and add your API keys:
```bash
cp env.example .env
```

Edit `.env` file:
```env
# Anthropic API Configuration
ANTHROPIC_API_KEY=your_anthropic_api_key_here
ANTHROPIC_MODEL=claude-3-sonnet-20240229

# Server Configuration
PORT=3000
NODE_ENV=development

# Security
API_KEY=your_api_key_here
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100

# Database
DB_PATH=./data/sales_agent.db

# Logging
LOG_LEVEL=info
```

### 3. Generate SSL Certificates
```bash
npm run generate-ssl
```

### 4. Initialize Sample Data
```bash
npm run init-data
```

### 5. Start the Server
```bash
npm start
```

Or use the complete setup:
```bash
npm run setup
```

## API Endpoints

### Main Conversation Endpoint
```http
POST /api/conversation
```

**Headers:**
```
Content-Type: application/json
x-api-key: your_api_key_here
```

**Request Body:**
```json
{
  "customer_message": "I'm interested in your product but it seems expensive",
  "conversation_id": "optional_conversation_id",
  "customer_context": {
    "name": "John Doe",
    "previous_interactions": [],
    "current_stage": "introduction"
  }
}
```

**Response:**
```json
{
  "success": true,
  "timestamp": "2024-01-15T10:30:00.000Z",
  "conversation_id": "uuid-string",
  "agent_reply": "I understand price is a concern. Let me show you the value you'll receive...",
  "next_action": "address_concerns",
  "confidence_score": 0.85,
  "knowledge_used": ["price_objection"],
  "customer_intent": "objection",
  "current_stage": "introduction"
}
```

### Knowledge Base Management
```http
POST /api/knowledge/objection
GET /api/knowledge/patterns
```

### Call Flow Management
```http
GET /api/flow/stages
POST /api/flow/progress
GET /api/flow/status/:conversation_id
```

### Health Check
```http
GET /health
```

## Knowledge Base Structure

The system stores objection handling patterns with:
- **Objection Types**: price_objection, timing_objection, need_objection, authority_objection
- **Common Patterns**: Phrases that indicate specific objections
- **Effective Responses**: Proven responses for each objection type
- **Success Rates**: Tracked effectiveness of responses

## Call Flow Stages

1. **Introduction**: Build rapport and identify needs
2. **Discovery**: Understand pain points and requirements
3. **Presentation**: Present relevant solutions
4. **Objection Handling**: Address concerns professionally
5. **Closing**: Guide toward decision or next steps

## Example Usage

### Start a Conversation
```bash
curl -X POST https://localhost:3000/api/conversation \
  -H "Content-Type: application/json" \
  -H "x-api-key: your_api_key" \
  -d '{
    "customer_message": "Hi, I heard about your software solution",
    "customer_context": {
      "name": "Sarah Johnson"
    }
  }'
```

### Add Knowledge Base Entry
```bash
curl -X POST https://localhost:3000/api/knowledge/objection \
  -H "Content-Type: application/json" \
  -H "x-api-key: your_api_key" \
  -d '{
    "objection_type": "competitor_objection",
    "common_patterns": ["using competitor", "happy with current", "switching costs"],
    "effective_responses": [
      "I understand. What specific features are you looking for?",
      "Let me show you how our solution compares to your current setup."
    ]
  }'
```

## Development

### Run in Development Mode
```bash
npm run dev
```

### Initialize Sample Data
```bash
npm run init-data
```

### Generate SSL Certificates
```bash
npm run generate-ssl
```

## Architecture

- **Express.js**: Web framework
- **SQLite**: Lightweight database for conversations and knowledge base
- **Anthropic Claude**: AI-powered response generation
- **HTTPS**: Secure communication with SSL/TLS
- **Rate Limiting**: API protection against abuse
- **Authentication**: API key-based access control

## Security Features

- ✅ HTTPS with SSL/TLS encryption
- ✅ API key authentication
- ✅ Rate limiting (100 requests per 15 minutes)
- ✅ Input validation and sanitization
- ✅ Helmet.js security headers
- ✅ CORS protection

## Monitoring

The API includes built-in monitoring:
- Request/response logging
- Performance metrics
- Error tracking
- Health check endpoint
- Service status monitoring

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Your Anthropic API key | Required |
| `ANTHROPIC_MODEL` | Claude model to use | claude-3-sonnet-20240229 |
| `PORT` | Server port | 3000 |
| `API_KEY` | API authentication key | Required |
| `DB_PATH` | SQLite database path | ./data/sales_agent.db |
| `RATE_LIMIT_MAX_REQUESTS` | Rate limit per window | 100 |
| `RATE_LIMIT_WINDOW_MS` | Rate limit window (ms) | 900000 |

## License

MIT License 