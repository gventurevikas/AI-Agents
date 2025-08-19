# Live GPT AI Agent

A modern, modular, and optimized FreeSWITCH-based AI agent for handling customer conversations with intelligent transfer management.

## 🚀 Features

- **Modular Architecture**: Clean separation of concerns with dedicated modules
- **Advanced Transfer Management**: Uses new transfer APIs to prevent premature transfers
- **Comprehensive Logging**: Structured logging with different levels and colors
- **Configuration Management**: Centralized configuration for easy customization
- **Error Handling**: Robust error handling and recovery mechanisms
- **Resource Management**: Automatic cleanup and resource management
- **Performance Monitoring**: Built-in performance tracking and metrics

## 📁 Project Structure

```
live-gpt/
├── config.lua              # Configuration management
├── logger.lua              # Advanced logging system
├── utils.lua               # Utility functions and helpers
├── audio.lua               # Audio processing (TTS/STT)
├── api_client.lua          # API communication layer
├── manager.lua              # Conversation flow and transfer logic
├── main.lua                # Main application orchestrator
└── README.md               # This documentation
```

## 🏗️ Architecture

### Core Modules

1. **Configuration (`config.lua`)**
   - Centralized settings for all components
   - Environment-specific configurations
   - Easy to modify and maintain

2. **Logging (`logger.lua`)**
   - Multi-level logging (DEBUG, INFO, WARN, ERROR, FATAL)
   - Colored console output
   - Structured logging with metadata
   - Performance tracking

3. **Utilities (`utils.lua`)**
   - Common helper functions
   - Text processing utilities
   - File and session management
   - Error handling helpers

4. **Audio Processing (`audio.lua`)**
   - Text-to-Speech (TTS) generation
   - Speech-to-Text (STT) transcription
   - Audio file management
   - Silence detection

5. **API Client (`api_client.lua`)**
   - HTTP/HTTPS communication
   - RESTful API integration
   - Error handling and retry logic
   - Request/response logging

6. **Manager (`manager.lua`)**
   - Conversation flow control
   - Transfer logic management
   - State tracking
   - Cleanup operations

7. **Main Application (`main.lua`)**
   - Application orchestration
   - Session management
   - Call flow coordination
   - Resource lifecycle management

## ⚙️ Configuration

### Key Configuration Options

```lua
-- Transfer settings
config.transfer = {
    min_confidence = 60,                    -- Minimum confidence for transfer
    max_conversation_iterations = 10,       -- Prevent infinite loops
    max_blank_responses = 2                 -- Max blank responses before hangup
}

-- Audio processing
config.audio = {
    sample_rate = 16000,                    -- Audio sample rate
    tts_chunk_size = 80,                   -- TTS text chunk size
    silence_detection = { ... }            -- Silence detection levels
}

-- API endpoints
config.apis = {
    outbound_calls = "http://127.0.0.1:7999/api/outbound-calls",
    conversations = "http://127.0.0.1:7999/api/conversations",
    tts = "http://127.0.0.1:8001/tts",
    stt = "http://localhost:8002/stt"
}
```

## 🔧 Installation & Setup

### Prerequisites

- FreeSWITCH 1.10+
- Lua 5.1+
- Required Lua modules: `cjson`, `socket.http`, `ssl.https`, `ltn12`
- SOX audio processing tool
- cURL command-line tool

### Installation Steps

1. **Copy files to FreeSWITCH directory:**
   ```bash
   cp -r live-gpt /usr/local/freeswitch/scripts/
   ```

2. **Set proper permissions:**
   ```bash
   chmod +x /usr/local/freeswitch/scripts/live-gpt/*.lua
   ```

3. **Update FreeSWITCH configuration:**
   ```xml
   <!-- In your dialplan -->
   <action application="lua" data="/usr/local/freeswitch/scripts/live-gpt/main.lua"/>
   ```

4. **Verify dependencies:**
   ```bash
   # Check SOX installation
   which sox
   
   # Check cURL installation
   which curl
   ```

## 🚀 Usage

### Basic Usage

The agent automatically handles:
- Call initialization and setup
- Customer information retrieval
- Conversation flow management
- Transfer logic and execution
- Resource cleanup

### Customization

1. **Modify Configuration:**
   Edit `config.lua` to adjust settings for your environment

2. **Custom Logging:**
   ```lua
   local logger = require("logger").Logger.new("CustomComponent")
   logger:info("Custom message", { data = "value" })
   ```

3. **Extend Functionality:**
   Add new modules or extend existing ones following the established patterns

## 📊 Logging

### Log Levels

- **DEBUG**: Detailed debugging information
- **INFO**: General information about operations
- **WARN**: Warning messages for potential issues
- **ERROR**: Error conditions that need attention
- **FATAL**: Critical errors that may cause failures

### Log Format

```
[2024-01-15 10:30:00.123] [INFO] [LiveGPT] Message content
```

### Specialized Logging

```lua
-- API calls
logger:api_call("POST", "/api/endpoint", { data = "value" })

-- Session events
logger:session_event("call_started", "uuid-123", { details = "info" })

-- Transfer events
logger:transfer_event("transfer_initiated", "conv-456", { reason = "enrollment" })

-- Performance metrics
logger:performance("operation_name", 150, { details = "info" })
```

## 🔄 Transfer Management

### Transfer Flow

1. **Monitoring**: Continuously monitors transfer readiness and confidence
2. **Initiation**: Only initiates transfer when confidence threshold is met (≥60%)
3. **Execution**: Uses new transfer APIs (`/initiate-transfer`, `/transfer`)
4. **Completion**: Proper cleanup and call termination

### Transfer Requirements

- Confidence score ≥ 60%
- Customer must show interest
- Package selection completed
- Transfer process properly initiated

## 🛠️ Development

### Adding New Features

1. **Create new module:**
   ```lua
   local NewModule = {}
   NewModule.__index = NewModule
   
   function NewModule.new()
       local self = setmetatable({}, NewModule)
       return self
   end
   
   return NewModule
   ```

2. **Follow naming conventions:**
   - Use descriptive names
   - Follow existing patterns
   - Add proper error handling
   - Include logging

3. **Update configuration:**
   Add new settings to `config.lua`

### Testing

- Test individual modules in isolation
- Verify API integrations
- Check error handling scenarios
- Validate transfer logic

## 🐛 Troubleshooting

### Common Issues

1. **Session not ready:**
   - Check FreeSWITCH session state
   - Verify call establishment
   - Review session initialization

2. **API communication failures:**
   - Verify API endpoints in config
   - Check network connectivity
   - Review API response formats

3. **Audio processing issues:**
   - Verify SOX installation
   - Check audio file permissions
   - Review TTS/STT API responses

### Debug Mode

Enable debug logging in `config.lua`:
```lua
config.logging.level = "debug"
```

## 📈 Performance

### Optimization Features

- **Connection pooling**: Reuse API connections
- **Async operations**: Non-blocking audio processing
- **Resource cleanup**: Automatic cleanup of temporary files
- **Performance monitoring**: Built-in timing and metrics

### Monitoring

- API response times
- Audio processing duration
- Transfer execution time
- Resource usage patterns

## 🔒 Security

### Security Features

- Input validation and sanitization
- Secure API communication
- Resource access controls
- Error message sanitization

### Best Practices

- Use HTTPS for external APIs
- Validate all inputs
- Implement proper error handling
- Regular security updates

## 📝 License

This project is proprietary software. All rights reserved.

## 🤝 Contributing

For internal development:
1. Follow established coding standards
2. Add comprehensive logging
3. Include error handling
4. Update documentation
5. Test thoroughly

## 📞 Support

For technical support and questions:
- Review logs for error details
- Check configuration settings
- Verify API connectivity
- Consult development team

---

**Version**: 2.0.0  
**Last Updated**: January 2024  
**Compatibility**: FreeSWITCH 1.10+
