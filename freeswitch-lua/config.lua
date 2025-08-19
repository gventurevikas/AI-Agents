-- Configuration file for Live GPT AI Agent
-- Centralized configuration management

local config = {}

-- API Endpoints
config.apis = {
    outbound_calls = "http://127.0.0.1:7999/api/outbound-calls",
    conversations = "http://127.0.0.1:7999/api/conversations",
    tts = "http://127.0.0.1:8001/tts",
    stt = "http://localhost:8002/stt",
    webhook = "https://aivoice.gventure.us:3000/freeswitch/webhook",
    customer_info = "https://aiagent.gventure.us/"
}

-- File Paths
config.paths = {
    audio_generated = "/usr/local/freeswitch/aiagent/cartesia/generated_audio/",
    recordings = "/var/www/html/recording/",
    ambience = "/usr/local/freeswitch/aiagent/call-center-ambience.wav",
    temp = "/tmp/"
}

-- Voice Configuration
config.voice = {
    sophie_id = "4f7f1324-1853-48a6-b294-4e78e8036a83",
    fallback_ids = {
        "bf0a246a-8642-498a-9950-80c35e9276b5",
        "71a7ad14-091c-4e8e-a314-022ece01c121"
    }
}

-- Transfer Configuration
config.transfer = {
    min_confidence = 60,
    max_conversation_iterations = 10,
    max_blank_responses = 2
}

-- Audio Processing
config.audio = {
    sample_rate = 16000,
    stereo = false,
    tts_chunk_size = 80,
    silence_detection = {
        ultra = {
            silence_ms = 150,
            threshold = 0.5,
            hits = 2,
            timeout = 2000,
            interrupt_ms = 50,
            energy_threshold = 0.05,
            description = "Ultra-aggressive: Immediate interruption on any speech"
        },
        aggressive = {
            silence_ms = 300,
            threshold = 1,
            hits = 3,
            timeout = 3000,
            interrupt_ms = 100,
            energy_threshold = 0.1,
            description = "Aggressive: Quick response to customer input"
        },
        optimized = {
            silence_ms = 600,
            threshold = 2,
            hits = 5,
            timeout = 6000,
            interrupt_ms = 200,
            energy_threshold = 0.2,
            description = "Optimized: Balanced response and accuracy"
        },
        conservative = {
            silence_ms = 1500,
            threshold = 3,
            hits = 10,
            timeout = 10000,
            interrupt_ms = 500,
            energy_threshold = 0.3,
            description = "Conservative: Wait for clear customer input"
        }
    }
}

-- HTTP Configuration
config.http = {
    timeout = 30,
    retry_attempts = 3,
    headers = {
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "LiveGPT-AIAgent/1.0"
    }
}

-- Logging Configuration
config.logging = {
    level = "info", -- debug, info, warn, error
    enable_console = true,
    enable_file = false,
    log_file = "/var/log/live-gpt/aiagent.log",
    max_file_size = "10MB",
    max_files = 5
}

-- Session Configuration
config.session = {
    ready_timeout = 1000, -- ms
    max_ready_attempts = 10,
    call_answer_delay = 500 -- ms
}

return config
