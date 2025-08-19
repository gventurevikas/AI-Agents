-- Audio processing module for Live GPT AI Agent
-- Handles TTS, STT, and audio file operations

local config = require("config")
local logger = require("logger").log
local utils = require("utils")

local AudioProcessor = {}
AudioProcessor.__index = AudioProcessor

function AudioProcessor.new()
    local self = setmetatable({}, AudioProcessor)
    self.temp_files = {}
    return self
end

-- TTS (Text-to-Speech) functions
function AudioProcessor:generate_tts(session, text, voice_id)
    if not utils.validate_session(session) then
        logger:error("Session is not active for TTS generation")
        return false
    end

    if utils.is_empty(text) then
        logger:error("Text cannot be empty for TTS generation")
        return false
    end

    voice_id = voice_id or config.voice.sophie_id
    logger:info("Generating TTS", { text_length = #text, voice_id = voice_id })

    local start_time = utils.get_timestamp_ms()

    -- Prepare request data
    local request_data = {
        text = text,
        voice_id = voice_id
    }
    local request_body = json.encode(request_data)

    -- Make HTTP request to TTS API
    local response_body = {}
    local res, code, response_headers = http.request {
        url = config.apis.tts,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#request_body)
        },
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_body)
    }

    local duration = utils.get_timestamp_ms() - start_time
    logger:performance("TTS Generation", duration, { text_length = #text, voice_id = voice_id })

    if code == 200 then
        local response_text = table.concat(response_body)
        logger:debug("TTS API response", { response = response_text })
        
        local response_data = json.decode(response_text)
        
        if response_data and response_data.success and response_data.data then
            local audio_data = response_data.data
            logger:info("TTS generated successfully", {
                filename = audio_data.filename,
                voice = audio_data.voice,
                file_size = audio_data.fileSize
            })
            
            -- Track temp file for cleanup
            if audio_data.filename then
                table.insert(self.temp_files, config.paths.audio_generated .. audio_data.filename)
            end
            
            return true, audio_data
        else
            logger:error("Invalid TTS API response format")
            return false
        end
    else
        local error_msg = string.format("TTS generation failed with status code: %d", code)
        if #response_body > 0 then
            error_msg = error_msg .. ", Response: " .. table.concat(response_body)
        end
        logger:error(error_msg)
        return false
    end
end

function AudioProcessor:play_content(session, content, voice_id)
    if not utils.validate_session(session) then
        logger:error("Session is not active for content playback")
        return false
    end

    if utils.is_empty(content) then
        logger:error("Content cannot be empty for playback")
        return false
    end

    logger:info("Playing content", { content_length = #content, voice_id = voice_id })

    local start_time = utils.get_timestamp_ms()
    
    -- Split content into manageable chunks
    local parts, last = utils.split_text_for_tts(content, config.audio.tts_chunk_size)
    
    -- Play each chunk
    for i, chunk in ipairs(parts) do
        if not utils.validate_session(session) then
            logger:error("Session became inactive during content playback")
            return false
        end
        
        local status, audio = self:generate_tts(session, chunk, voice_id)
        if status and audio then
            local audio_url = audio.filename
            session:streamFile(config.paths.audio_generated .. audio_url)
            logger:debug("Played audio chunk", { chunk_number = i, filename = audio_url })
        else
            logger:error("Failed to generate TTS for chunk", { chunk_number = i, chunk = chunk })
            return false
        end
    end

    local duration = utils.get_timestamp_ms() - start_time
    logger:performance("Content Playback", duration, { chunks = #parts, content_length = #content })

    return last
end

-- STT (Speech-to-Text) functions
function AudioProcessor:transcribe_audio(audio_path, filename)
    if not utils.file_exists(audio_path) then
        logger:error("Audio file does not exist", { path = audio_path })
        return false, ""
    end

    logger:info("Transcribing audio", { path = audio_path, filename = filename })

    local start_time = utils.get_timestamp_ms()

    -- Trim silence from audio
    local trimmed_path = self:trim_silence(audio_path, config.paths.temp .. filename)
    if not trimmed_path then
        logger:error("Failed to trim silence from audio")
        return false, ""
    end

    -- Build cURL command for transcription
    local curl_command = utils.build_curl_command("POST", config.apis.stt, nil, {
        ["Content-Type"] = "multipart/form-data"
    })
    curl_command = curl_command .. string.format(" -F 'file=@%s'", trimmed_path)

    logger:api_call("POST", config.apis.stt, { file = trimmed_path })

    -- Execute transcription
    local success, output = utils.execute_curl_command(curl_command)
    if not success then
        logger:error("Failed to execute transcription cURL command")
        return false, ""
    end

    local duration = utils.get_timestamp_ms() - start_time
    logger:performance("Audio Transcription", duration, { filename = filename })

    -- Parse transcription result
    if not utils.is_empty(output) then
        local transcription = output:match('"transcription":%s*"([^"]+)"')
        if transcription then
            logger:info("Transcription successful", { 
                original_length = #output, 
                transcription_length = #transcription 
            })
            
            -- Clean up temp file
            os.remove(trimmed_path)
            
            return true, utils.expand_contractions(transcription)
        else
            logger:error("No transcription result found in API response")
            return false, ""
        end
    else
        logger:error("Empty response from transcription API")
        return false, ""
    end
end

function AudioProcessor:trim_silence(input, output)
    if not utils.file_exists(input) then
        logger:error("Input audio file does not exist", { input = input })
        return nil
    end

    logger:debug("Trimming silence from audio", { input = input, output = output })

    local sox_command = string.format(
        "/usr/bin/sox %s %s silence 1 0.1 1%% reverse silence 1 0.1 1%% reverse",
        input, output
    )

    local handle = io.popen(sox_command, "r")
    if handle then
        local result = handle:read("*a")
        handle:close()
        logger:debug("SOX silence trimming completed", { result = result })
        return output
    else
        logger:error("Failed to execute SOX command for silence trimming")
        return nil
    end
end

-- Audio recording functions
function AudioProcessor:play_and_record(session, prompt, filename, duration)
    if not utils.validate_session(session) then
        logger:error("Session is not active for play and record")
        return nil
    end

    local record_path = filename .. ".wav"
    logger:info("Starting play and record", { prompt = prompt, filename = record_path, duration = duration })

    -- Configure recording settings
    session:execute("set", "record_waste=false")
    session:execute("set", "record_direction=in")
    session:setVariable("RECORD_SAMPLE_RATE", tostring(config.audio.sample_rate))
    session:setVariable("RECORD_STEREO", tostring(config.audio.stereo))

    -- Play prompt and start recording
    session:streamFile(config.paths.audio_generated .. prompt)
    session:execute("record_session", filename)

    -- Wait for silence detection
    self:detect_silence(session, filename, "aggressive")

    logger:info("Play and record completed", { record_path = record_path })
    return record_path
end

function AudioProcessor:detect_silence(session, filename, aggression_level)
    if not utils.validate_session(session) then
        logger:error("Session is not active for silence detection")
        return
    end

    local detection_config = config.audio.silence_detection[aggression_level or "optimized"]
    if not detection_config then
        detection_config = config.audio.silence_detection.optimized
        logger:warn("Invalid aggression level, using optimized", { provided = aggression_level })
    end

    logger:info("Starting silence detection", {
        level = aggression_level,
        config = detection_config
    })

    local wait_cmd = string.format("%d %d %d %d", 
        detection_config.silence_ms, 
        detection_config.threshold, 
        detection_config.hits, 
        detection_config.timeout
    )

    while session:ready() do
        session:execute("wait_for_silence", wait_cmd)

        local silence_detected = session:getVariable("silence_detected")
        local last_silence_duration = session:getVariable("last_silence_duration")
        local wait_for_silence_timeout = session:getVariable("wait_for_silence_timeout")
        local speech_result = session:getVariable("detect_speech_result")

        if silence_detected == "true" then
            logger:info("Silence detected", { duration_ms = last_silence_duration })
        elseif wait_for_silence_timeout == "true" then
            logger:info("Silence detection timed out", { timeout_ms = detection_config.timeout })
        else
            logger:debug("No significant silence detected, continuing to wait")
        end

        if speech_result and speech_result ~= "" then
            logger:debug("Speech detected during silence detection", { speech = speech_result })
        end

        -- Stop recording if silence detected or timeout
        if silence_detected == "true" or wait_for_silence_timeout == "true" then
            session:execute("stop_record_session", filename)
            logger:info("Recording stopped", { filename = filename, reason = silence_detected == "true" and "silence" or "timeout" })
            return
        end
    end

    logger:warn("Session became inactive during silence detection")
end

-- Cleanup functions
function AudioProcessor:cleanup()
    logger:info("Cleaning up audio processor temp files", { count = #self.temp_files })
    utils.cleanup_temp_files(self.temp_files)
    self.temp_files = {}
end

-- Get content from audio recording
function AudioProcessor:get_content(uuid, session, message, duration)
    local filename = utils.generate_filename(uuid, message, "wav")
    local full_path = config.paths.recordings .. filename
    
    logger:info("Getting content from audio", { filename = filename, duration = duration })

    local record_path = self:play_and_record(session, message, full_path, duration)
    if not record_path then
        logger:error("Failed to record audio content")
        return false, "", ""
    end

    local state, content = self:transcribe_audio(full_path, filename)
    if state then
        logger:info("Content extraction successful", { content_length = #content })
        return true, "", content
    else
        logger:error("Failed to transcribe audio content")
        return false, "", ""
    end
end

return AudioProcessor
