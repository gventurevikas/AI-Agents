#include <switch.h>

SWITCH_MODULE_LOAD_FUNCTION(mod_voice_detector_load);
SWITCH_MODULE_SHUTDOWN_FUNCTION(mod_voice_detector_shutdown);
SWITCH_MODULE_DEFINITION(mod_voice_detector, mod_voice_detector_load, mod_voice_detector_shutdown, NULL);

// Runtime parameters structure
typedef struct {
    int silence_ms;
    float threshold;
    int hits;
    int timeout;
    int interrupt_ms;
    float energy_threshold;
    int total_analysis_time;
    int min_word_length;
    int maximum_word_length;
    int between_words_silence;
    int max_silence;
    int auto_record;
    int recording_format;
    char *recording_path;
    char *recording_prefix;
    char *leg; // Added for leg parameter
} voice_detector_runtime_params_t;

// Configuration structure
typedef struct {
    char *api_url;
    char *api_key;
    char *recording_path;
    char *recording_prefix;
    switch_memory_pool_t *pool;
    switch_mutex_t *mutex;
    switch_hash_t *sessions;
    int energy_threshold;
    int silence_threshold;
    int frame_size;
    int sample_rate;
    int debounce_ms;
    int max_silence_duration;
    int auto_record;
    int recording_format;
} voice_detector_global_t;

// Session-specific data
typedef struct {
    switch_core_session_t *session;
    switch_media_bug_t *bug;
    switch_time_t last_voice_time;
    switch_time_t last_api_call_time;
    int voice_detected;
    int silence_frames;
    int total_frames;
    char *uuid;
    switch_memory_pool_t *pool;
    // Recording specific fields - simplified for compatibility
    char *recording_file;
    int is_recording;
    switch_time_t recording_start_time;
    switch_time_t recording_duration;
    // Runtime parameters
    voice_detector_runtime_params_t runtime_params;
    // Advanced voice detection fields
    int consecutive_hits;
    int word_start_time;
    int word_end_time;
    int current_word_length;
    int between_words_silence_frames;
    int max_silence_frames;
} voice_detector_session_t;

// Global configuration
static voice_detector_global_t *globals = NULL;

// Forward declarations
static switch_status_t voice_detector_callback(switch_media_bug_t *bug, void *user_data, switch_frame_t *frame);
static switch_status_t voice_detector_session_cleanup(voice_detector_session_t *session_data);
static switch_status_t voice_detector_api_call(const char *uuid, int voice_detected, int energy_level, const char *leg);
static switch_status_t voice_detector_parse_config(switch_loadable_module_interface_t **mod_interface, switch_memory_pool_t *pool);
static switch_status_t voice_detector_start_recording(voice_detector_session_t *session_data);
static switch_status_t voice_detector_stop_recording(voice_detector_session_t *session_data);
static switch_status_t voice_detector_get_recording_filename(voice_detector_session_t *session_data, char **filename);
static switch_status_t voice_detector_parse_runtime_params(const char *data, voice_detector_runtime_params_t *params);
static switch_status_t voice_detector_apply_runtime_params(voice_detector_session_t *session_data, const voice_detector_runtime_params_t *params);

// Parse runtime parameters from application data
static switch_status_t voice_detector_parse_runtime_params(const char *data, voice_detector_runtime_params_t *params)
{
    // Set default values
    params->silence_ms = 150;
    params->threshold = 0.5f;
    params->hits = 2;
    params->timeout = 2000;
    params->interrupt_ms = 50;
    params->energy_threshold = 0.05f;
    params->total_analysis_time = 4000;
    params->min_word_length = 100;
    params->maximum_word_length = 3500;
    params->between_words_silence = 50;
    params->max_silence = 2000;
    params->auto_record = 1;
    params->recording_format = 0;
    params->recording_path = NULL;
    params->recording_prefix = NULL;
    params->leg = "a";  // Default to leg A

    if (!data || !*data) {
        return SWITCH_STATUS_SUCCESS; // Use defaults
    }

    char *mycmd = switch_core_strdup(switch_core_permanent_pool(), data);
    char *argv[20] = { 0 };
    int argc = 0;

    argc = switch_separate_string(mycmd, ' ', argv, (sizeof(argv) / sizeof(argv[0])));

    for (int i = 0; i < argc; i++) {
        char *arg = argv[i];
        if (!arg || !*arg) continue;

        char *equals = strchr(arg, '=');
        if (!equals) continue;

        *equals = '\0';
        char *value = equals + 1;

        if (!strcasecmp(arg, "silence_ms")) {
            params->silence_ms = atoi(value);
        } else if (!strcasecmp(arg, "threshold")) {
            params->threshold = atof(value);
        } else if (!strcasecmp(arg, "hits")) {
            params->hits = atoi(value);
        } else if (!strcasecmp(arg, "timeout")) {
            params->timeout = atoi(value);
        } else if (!strcasecmp(arg, "interrupt_ms")) {
            params->interrupt_ms = atoi(value);
        } else if (!strcasecmp(arg, "energy_threshold")) {
            params->energy_threshold = atof(value);
        } else if (!strcasecmp(arg, "total_analysis_time")) {
            params->total_analysis_time = atoi(value);
        } else if (!strcasecmp(arg, "min_word_length")) {
            params->min_word_length = atoi(value);
        } else if (!strcasecmp(arg, "maximum_word_length")) {
            params->maximum_word_length = atoi(value);
        } else if (!strcasecmp(arg, "between_words_silence")) {
            params->between_words_silence = atoi(value);
        } else if (!strcasecmp(arg, "max_silence")) {
            params->max_silence = atoi(value);
        } else if (!strcasecmp(arg, "auto_record")) {
            params->auto_record = atoi(value);
        } else if (!strcasecmp(arg, "recording_format")) {
            params->recording_format = atoi(value);
        } else if (!strcasecmp(arg, "recording_path")) {
            params->recording_path = switch_core_strdup(switch_core_permanent_pool(), value);
        } else if (!strcasecmp(arg, "recording_prefix")) {
            params->recording_prefix = switch_core_strdup(switch_core_permanent_pool(), value);
        } else if (!strcasecmp(arg, "leg")) {
            params->leg = switch_core_strdup(switch_core_permanent_pool(), value);
        }
    }

    return SWITCH_STATUS_SUCCESS;
}

// Apply runtime parameters to session
static switch_status_t voice_detector_apply_runtime_params(voice_detector_session_t *session_data, const voice_detector_runtime_params_t *params)
{
    // Copy runtime parameters to session
    memcpy(&session_data->runtime_params, params, sizeof(voice_detector_runtime_params_t));
    
    // Set default values for recording path and prefix if not specified
    if (!session_data->runtime_params.recording_path) {
        session_data->runtime_params.recording_path = globals->recording_path;
    }
    if (!session_data->runtime_params.recording_prefix) {
        session_data->runtime_params.recording_prefix = globals->recording_prefix;
    }
    
    // Convert time values to frame counts
    session_data->max_silence_frames = (params->max_silence * globals->sample_rate) / (globals->frame_size * 1000);
    session_data->between_words_silence_frames = (params->between_words_silence * globals->sample_rate) / (globals->frame_size * 1000);
    
    return SWITCH_STATUS_SUCCESS;
}

// Parse configuration from XML
static switch_status_t voice_detector_parse_config(switch_loadable_module_interface_t **mod_interface, switch_memory_pool_t *pool)
{
    switch_xml_t cfg, xml, settings, param;
    const char *api_url = NULL;
    const char *api_key = NULL;
    const char *recording_path = NULL;
    const char *recording_prefix = NULL;
    const char *energy_threshold = NULL;
    const char *silence_threshold = NULL;
    const char *frame_size = NULL;
    const char *sample_rate = NULL;
    const char *debounce_ms = NULL;
    const char *max_silence_duration = NULL;
    const char *auto_record = NULL;
    const char *recording_format = NULL;

    // Set defaults
    globals->energy_threshold = 1000;
    globals->silence_threshold = 100;
    globals->frame_size = 160;
    globals->sample_rate = 8000;
    globals->debounce_ms = 500;
    globals->max_silence_duration = 2000;
    globals->auto_record = 1;
    globals->recording_format = 0; // 0 = wav, 1 = mp3, 2 = ogg

    // Load configuration
    if (!(xml = switch_xml_open_cfg(getenv("SWITCH_CONF_DIR") ? getenv("SWITCH_CONF_DIR") : SWITCH_GLOBAL_dirs.conf_dir, "voice_detector.conf", &cfg))) {
        switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_WARNING, "No voice_detector.conf found, using defaults\n");
        return SWITCH_STATUS_SUCCESS;
    }

    if ((settings = switch_xml_child(cfg, "settings"))) {
        for (param = switch_xml_child(settings, "param"); param; param = param->next) {
            char *var = (char *)switch_xml_attr_soft(param, "name");
            char *val = (char *)switch_xml_attr_soft(param, "value");

            if (!strcasecmp(var, "api-url")) {
                api_url = val;
            } else if (!strcasecmp(var, "api-key")) {
                api_key = val;
            } else if (!strcasecmp(var, "recording-path")) {
                recording_path = val;
            } else if (!strcasecmp(var, "recording-prefix")) {
                recording_prefix = val;
            } else if (!strcasecmp(var, "energy-threshold")) {
                energy_threshold = val;
            } else if (!strcasecmp(var, "silence-threshold")) {
                silence_threshold = val;
            } else if (!strcasecmp(var, "frame-size")) {
                frame_size = val;
            } else if (!strcasecmp(var, "sample-rate")) {
                sample_rate = val;
            } else if (!strcasecmp(var, "debounce-ms")) {
                debounce_ms = val;
            } else if (!strcasecmp(var, "max-silence-duration")) {
                max_silence_duration = val;
            } else if (!strcasecmp(var, "auto-record")) {
                auto_record = val;
            } else if (!strcasecmp(var, "recording-format")) {
                recording_format = val;
            }
        }
    }

    // Apply configuration values
    if (api_url) {
        globals->api_url = switch_core_strdup(globals->pool, api_url);
    }
    if (api_key) {
        globals->api_key = switch_core_strdup(globals->pool, api_key);
    }
    if (recording_path) {
        globals->recording_path = switch_core_strdup(globals->pool, recording_path);
    } else {
        globals->recording_path = switch_core_strdup(globals->pool, "/tmp");
    }
    if (recording_prefix) {
        globals->recording_prefix = switch_core_strdup(globals->pool, recording_prefix);
    } else {
        globals->recording_prefix = switch_core_strdup(globals->pool, "voice_detection");
    }
    if (energy_threshold) {
        globals->energy_threshold = atoi(energy_threshold);
    }
    if (silence_threshold) {
        globals->silence_threshold = atoi(silence_threshold);
    }
    if (frame_size) {
        globals->frame_size = atoi(frame_size);
    }
    if (sample_rate) {
        globals->sample_rate = atoi(sample_rate);
    }
    if (debounce_ms) {
        globals->debounce_ms = atoi(debounce_ms);
    }
    if (max_silence_duration) {
        globals->max_silence_duration = atoi(max_silence_duration);
    }
    if (auto_record) {
        globals->auto_record = atoi(auto_record);
    }
    if (recording_format) {
        globals->recording_format = atoi(recording_format);
    }

    switch_xml_free(xml);
    return SWITCH_STATUS_SUCCESS;
}

// Generate recording filename
static switch_status_t voice_detector_get_recording_filename(voice_detector_session_t *session_data, char **filename)
{
    switch_time_t now = switch_micro_time_now();
    char timestamp[64];
    const char *extension = "wav";
    
    // Set extension based on recording format
    switch (session_data->runtime_params.recording_format) {
        case 1:
            extension = "mp3";
            break;
        case 2:
            extension = "ogg";
            break;
        default:
            extension = "wav";
            break;
    }
    
    // Format timestamp
    switch_snprintf(timestamp, sizeof(timestamp), "%ld", now / 1000000);
    
    // Create filename
    *filename = switch_mprintf("%s/%s_%s_%s.%s", 
                              session_data->runtime_params.recording_path,
                              session_data->runtime_params.recording_prefix,
                              session_data->uuid,
                              timestamp,
                              extension);
    
    return SWITCH_STATUS_SUCCESS;
}

// Start recording
static switch_status_t voice_detector_start_recording(voice_detector_session_t *session_data)
{
    switch_status_t status = SWITCH_STATUS_SUCCESS;
    char *filename = NULL;
    switch_record_flag_t flags = SWITCH_RECORD_FLAG_RECORD;
    
    if (!session_data->runtime_params.auto_record || session_data->is_recording) {
        return SWITCH_STATUS_SUCCESS;
    }
    
    // Generate filename
    status = voice_detector_get_recording_filename(session_data, &filename);
    if (status != SWITCH_STATUS_SUCCESS || !filename) {
        switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_ERROR, "Failed to generate recording filename\n");
        return SWITCH_STATUS_FALSE;
    }
    
    // Set recording flags based on format
    switch (session_data->runtime_params.recording_format) {
        case 1: // MP3
            flags |= SWITCH_RECORD_FLAG_MP3;
            break;
        case 2: // OGG
            flags |= SWITCH_RECORD_FLAG_OGG;
            break;
        default: // WAV
            flags |= SWITCH_RECORD_FLAG_WAV;
            break;
    }
    
    // Start recording
    status = switch_core_session_record_start(session_data->session, &session_data->record_session, filename, flags, NULL);
    if (status != SWITCH_STATUS_SUCCESS) {
        switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_ERROR, "Failed to start recording: %s\n", filename);
        switch_safe_free(filename);
        return status;
    }
    
    // Store recording info
    session_data->recording_file = filename;
    session_data->is_recording = 1;
    session_data->recording_start_time = switch_micro_time_now();
    session_data->recording_duration = 0;
    
    switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_INFO, "Started recording: %s\n", filename);
    
    // Send API call for recording start
    voice_detector_api_call(session_data->uuid, 2, 0, session_data->runtime_params.leg); // 2 = recording started
    
    return SWITCH_STATUS_SUCCESS;
}

// Stop recording
static switch_status_t voice_detector_stop_recording(voice_detector_session_t *session_data)
{
    switch_status_t status = SWITCH_STATUS_SUCCESS;
    
    if (!session_data->is_recording || !session_data->record_session) {
        return SWITCH_STATUS_SUCCESS;
    }
    
    // Calculate recording duration
    switch_time_t now = switch_micro_time_now();
    session_data->recording_duration = (now - session_data->recording_start_time) / 1000000; // Convert to seconds
    
    // Stop recording
    status = switch_core_session_record_stop(session_data->record_session);
    if (status != SWITCH_STATUS_SUCCESS) {
        switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_ERROR, "Failed to stop recording\n");
        return status;
    }
    
    switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_INFO, "Stopped recording: %s (duration: %lds)\n", 
                      session_data->recording_file, session_data->recording_duration);
    
    // Send API call for recording stop
    voice_detector_api_call(session_data->uuid, 3, session_data->recording_duration, session_data->runtime_params.leg); // 3 = recording stopped
    
    // Clean up recording session
    session_data->record_session = NULL;
    session_data->is_recording = 0;
    
    return SWITCH_STATUS_SUCCESS;
}

// Media bug callback function
static switch_status_t voice_detector_callback(switch_media_bug_t *bug, void *user_data, switch_frame_t *frame)
{
    voice_detector_session_t *session_data = (voice_detector_session_t *)user_data;
    switch_core_session_t *session = session_data->session;
    switch_time_t now = switch_micro_time_now();
    int16_t *audio_data = (int16_t *)frame->data;
    int samples = frame->samples;
    float energy = 0.0f;
    int i;

    if (!session_data || !session || !audio_data || samples <= 0) {
        return SWITCH_STATUS_SUCCESS;
    }

    // Calculate audio energy (normalized)
    for (i = 0; i < samples; i++) {
        energy += (float)(audio_data[i] * audio_data[i]);
    }
    energy = sqrt(energy / samples) / 32768.0f; // Normalize to 0-1 range

    session_data->total_frames++;

    // Advanced voice detection logic with runtime parameters
    // API Call Sequence:
    // 1. First voice frame detected -> API call for voice start (immediate)
    // 2. Consecutive hits reached -> Start recording -> API call for recording start
    // 3. Silence threshold reached -> Stop recording -> API call for recording stop
    // 4. Voice end confirmed -> API call for voice end
    if (energy > session_data->runtime_params.energy_threshold) {
        if (!session_data->voice_detected) {
            // Voice start detection - call API immediately on first voice frame
            session_data->consecutive_hits++;
            
            // Call API immediately when first voice frame is detected
            if ((now - session_data->last_api_call_time) > (globals->debounce_ms * 1000)) {
                voice_detector_api_call(session_data->uuid, 1, (int)(energy * 1000), session_data->runtime_params.leg); // Voice started
                session_data->last_api_call_time = now;
            }
            
            // Start recording and set voice detected after consecutive hits validation
            if (session_data->consecutive_hits >= session_data->runtime_params.hits) {
                session_data->voice_detected = 1;
                session_data->last_voice_time = now;
                session_data->silence_frames = 0;
                session_data->word_start_time = now;
                session_data->current_word_length = 0;
                
                // Start recording when voice is confirmed (after consecutive hits)
                voice_detector_start_recording(session_data);
            }
        } else {
            // Voice is continuing
            session_data->consecutive_hits = 0;
            session_data->current_word_length += (globals->frame_size * 1000 / globals->sample_rate);
            
            // Check if word length exceeds maximum
            if (session_data->current_word_length > session_data->runtime_params.maximum_word_length) {
                // Word too long, might be noise - reset
                session_data->voice_detected = 0;
                session_data->consecutive_hits = 0;
                voice_detector_stop_recording(session_data);
            }
        }
    } else {
        if (session_data->voice_detected) {
            session_data->silence_frames++;
            session_data->consecutive_hits = 0;
            
            // Check if silence duration exceeds threshold
            int silence_duration = session_data->silence_frames * (globals->frame_size * 1000 / globals->sample_rate);
            
            if (silence_duration > session_data->runtime_params.max_silence) {
                // Long silence - stop recording and voice detection
                session_data->voice_detected = 0;
                voice_detector_stop_recording(session_data);
                
                // Trigger API call for voice end
                if ((now - session_data->last_api_call_time) > (globals->debounce_ms * 1000)) {
                    voice_detector_api_call(session_data->uuid, 0, (int)(energy * 1000), session_data->runtime_params.leg);
                    session_data->last_api_call_time = now;
                }
            } else if (silence_duration > session_data->runtime_params.between_words_silence) {
                // Short silence between words - check word length
                if (session_data->current_word_length >= session_data->runtime_params.min_word_length) {
                    // Valid word detected
                    session_data->word_end_time = now;
                    int word_duration = (session_data->word_end_time - session_data->word_start_time) / 1000000;
                    
                    // Send word detection event
                    voice_detector_api_call(session_data->uuid, 4, word_duration, session_data->runtime_params.leg); // 4 = word detected
                    
                    // Reset for next word
                    session_data->word_start_time = now;
                    session_data->current_word_length = 0;
                }
            }
        }
    }

    return SWITCH_STATUS_SUCCESS;
}

// API call function
static switch_status_t voice_detector_api_call(const char *uuid, int voice_detected, int energy_level, const char *leg)
{
    switch_curl_slist_t *headers = NULL;
    switch_curl_slist_t *cur;
    switch_memory_pool_t *pool;
    switch_status_t status = SWITCH_STATUS_SUCCESS;
    char *url = NULL;
    char *post_data = NULL;
    switch_json_t *json = NULL;
    switch_curl_handle_t *curl = NULL;

    if (!globals->api_url) {
        return SWITCH_STATUS_SUCCESS; // No API URL configured
    }

    // Create memory pool for this request
    switch_core_new_memory_pool(&pool);

    // Create JSON payload
    json = switch_json_create_object(pool);
    switch_json_add_string(json, "uuid", uuid);
    switch_json_add_string(json, "leg", leg ? leg : "a");  // Include leg information
    switch_json_add_int(json, "voice_detected", voice_detected);
    switch_json_add_int(json, "energy_level", energy_level);
    switch_json_add_int(json, "timestamp", (int)switch_micro_time_now() / 1000000);
    
    // Add recording information for recording events
    if (voice_detected == 2) { // Recording started
        switch_json_add_string(json, "event_type", "recording_started");
    } else if (voice_detected == 3) { // Recording stopped
        switch_json_add_string(json, "event_type", "recording_stopped");
        switch_json_add_int(json, "recording_duration", energy_level); // energy_level contains duration in this case
    } else if (voice_detected == 1) { // Voice start
        switch_json_add_string(json, "event_type", "voice_started");
    } else if (voice_detected == 0) { // Voice end
        switch_json_add_string(json, "event_type", "voice_ended");
    } else if (voice_detected == 4) { // Word detected
        switch_json_add_string(json, "event_type", "word_detected");
        switch_json_add_int(json, "word_duration", energy_level); // energy_level contains word duration in this case
    }

    post_data = switch_json_print(json, pool);

    // Set up headers
    headers = switch_curl_slist_append(headers, "Content-Type: application/json");
    if (globals->api_key) {
        char auth_header[256];
        snprintf(auth_header, sizeof(auth_header), "Authorization: Bearer %s", globals->api_key);
        headers = switch_curl_slist_append(headers, auth_header);
    }

    // Initialize CURL
    curl = switch_curl_easy_init();
    if (!curl) {
        switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_ERROR, "Failed to initialize CURL\n");
        status = SWITCH_STATUS_FALSE;
        goto cleanup;
    }

    // Set CURL options
    switch_curl_easy_setopt(curl, CURLOPT_URL, globals->api_url);
    switch_curl_easy_setopt(curl, CURLOPT_POSTFIELDS, post_data);
    switch_curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    switch_curl_easy_setopt(curl, CURLOPT_TIMEOUT, 10L);
    switch_curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);

    // Perform request
    CURLcode res = switch_curl_easy_perform(curl);
    if (res != CURLE_OK) {
        switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_ERROR, "CURL request failed: %s\n", switch_curl_easy_strerror(res));
        status = SWITCH_STATUS_FALSE;
    } else {
        long http_code = 0;
        switch_curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
        switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_DEBUG, "API call successful: HTTP %ld\n", http_code);
    }

cleanup:
    if (curl) {
        switch_curl_easy_cleanup(curl);
    }
    if (headers) {
        switch_curl_slist_free_all(headers);
    }
    switch_core_destroy_memory_pool(&pool);

    return status;
}

// Session cleanup function
static switch_status_t voice_detector_session_cleanup(voice_detector_session_t *session_data)
{
    if (!session_data) {
        return SWITCH_STATUS_SUCCESS;
    }

    // Stop recording if active
    if (session_data->is_recording) {
        voice_detector_stop_recording(session_data);
    }

    // Remove media bug if exists
    if (session_data->bug) {
        switch_core_media_bug_remove(session_data->bug, SWITCH_TRUE);
        session_data->bug = NULL;
    }

    // Free recording file name
    if (session_data->recording_file) {
        switch_safe_free(session_data->recording_file);
    }

    // Free session data
    if (session_data->pool) {
        switch_core_destroy_memory_pool(&session_data->pool);
    }

    return SWITCH_STATUS_SUCCESS;
}

// Application function
static switch_status_t voice_detector_app_function(switch_core_session_t *session, const char *data)
{
    switch_channel_t *channel = switch_core_session_get_channel(session);
    const char *uuid = switch_channel_get_uuid(channel);
    voice_detector_session_t *session_data = NULL;
    voice_detector_runtime_params_t runtime_params;
    switch_status_t status = SWITCH_STATUS_SUCCESS;

    if (!uuid) {
        switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_ERROR, "No UUID found for channel\n");
        return SWITCH_STATUS_FALSE;
    }

    // Check if already monitoring this session
    switch_mutex_lock(globals->mutex);
    if (switch_core_hash_find(globals->sessions, uuid)) {
        switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_WARNING, "Voice detection already active for session %s\n", uuid);
        switch_mutex_unlock(globals->mutex);
        return SWITCH_STATUS_SUCCESS;
    }
    switch_mutex_unlock(globals->mutex);

    // Parse runtime parameters
    status = voice_detector_parse_runtime_params(data, &runtime_params);
    if (status != SWITCH_STATUS_SUCCESS) {
        switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_ERROR, "Failed to parse runtime parameters\n");
        return status;
    }

    // Create session data
    switch_core_new_memory_pool(&session_data->pool);
    session_data->session = session;
    session_data->uuid = switch_core_strdup(session_data->pool, uuid);
    session_data->voice_detected = 0;
    session_data->silence_frames = 0;
    session_data->total_frames = 0;
    session_data->last_voice_time = 0;
    session_data->last_api_call_time = 0;
    session_data->record_session = NULL;
    session_data->recording_file = NULL;
    session_data->is_recording = 0;
    session_data->recording_start_time = 0;
    session_data->recording_duration = 0;
    session_data->consecutive_hits = 0;
    session_data->word_start_time = 0;
    session_data->word_end_time = 0;
    session_data->current_word_length = 0;
    session_data->between_words_silence_frames = 0;
    session_data->max_silence_frames = 0;

    // Apply runtime parameters
    voice_detector_apply_runtime_params(session_data, &runtime_params);

    // Create media bug based on leg selection
    switch_media_bug_flag_t flags = SMBF_READ_STREAM | SMBF_NO_PAUSE;
    
    if (!strcasecmp(session_data->runtime_params.leg, "a")) {
        // Monitor leg A (read stream)
        flags |= SMBF_READ_STREAM;
    } else if (!strcasecmp(session_data->runtime_params.leg, "b")) {
        // Monitor leg B (write stream)
        flags |= SMBF_WRITE_STREAM;
    } else if (!strcasecmp(session_data->runtime_params.leg, "both")) {
        // Monitor both legs
        flags |= SMBF_READ_STREAM | SMBF_WRITE_STREAM;
    } else {
        // Default to leg A if invalid value
        flags |= SMBF_READ_STREAM;
        session_data->runtime_params.leg = "a";
    }
    
    status = switch_core_media_bug_add(session, "voice_detector", NULL, voice_detector_callback, session_data, 0, flags, &session_data->bug);
    if (status != SWITCH_STATUS_SUCCESS) {
        switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_ERROR, "Failed to create media bug for session %s\n", uuid);
        voice_detector_session_cleanup(session_data);
        return status;
    }

    // Add to sessions hash
    switch_mutex_lock(globals->mutex);
    switch_core_hash_insert(globals->sessions, uuid, session_data);
    switch_mutex_unlock(globals->mutex);

    switch_log_printf(SWITCH_CHANNEL_LOG, SWITCH_LOG_INFO, "Voice detection started for session %s on leg %s (auto-recording: %s, energy_threshold: %.3f, max_silence: %dms)\n", 
                      uuid, 
                      session_data->runtime_params.leg,
                      session_data->runtime_params.auto_record ? "enabled" : "disabled",
                      session_data->runtime_params.energy_threshold,
                      session_data->runtime_params.max_silence);
    return SWITCH_STATUS_SUCCESS;
}

// API function
static switch_status_t voice_detector_api_function(switch_core_session_t *session, const char *data, switch_io_data_stream_t *stream, switch_input_callback_t *write_callback)
{
    switch_channel_t *channel = switch_core_session_get_channel(session);
    char *mycmd = NULL;
    char *argv[10] = { 0 };
    int argc = 0;
    switch_status_t status = SWITCH_STATUS_SUCCESS;

    if (!data) {
        stream->write_function(stream, "Usage: voice_detector <start|stop|status> [uuid]\n");
        return SWITCH_STATUS_SUCCESS;
    }

    mycmd = switch_core_strdup(session->pool, data);
    argc = switch_separate_string(mycmd, ' ', argv, (sizeof(argv) / sizeof(argv[0])));

    if (argc < 1) {
        stream->write_function(stream, "Usage: voice_detector <start|stop|status> [uuid]\n");
        return SWITCH_STATUS_SUCCESS;
    }

    if (!strcasecmp(argv[0], "start")) {
        if (argc < 2) {
            stream->write_function(stream, "Usage: voice_detector start <uuid>\n");
            return SWITCH_STATUS_SUCCESS;
        }
        // Start voice detection on specific UUID
        // Implementation would involve finding the session and starting detection
        stream->write_function(stream, "Starting voice detection on %s\n", argv[1]);
    } else if (!strcasecmp(argv[0], "stop")) {
        if (argc < 2) {
            stream->write_function(stream, "Usage: voice_detector stop <uuid>\n");
            return SWITCH_STATUS_SUCCESS;
        }
        // Stop voice detection on specific UUID
        stream->write_function(stream, "Starting voice detection on %s\n", argv[1]);
    } else if (!strcasecmp(argv[0], "status")) {
        // Show status of all monitored sessions
        switch_hash_index_t *hi;
        void *val;
        voice_detector_session_t *session_data;
        int count = 0;

        switch_mutex_lock(globals->mutex);
        for (hi = switch_core_hash_first(globals->sessions); hi; hi = switch_core_hash_next(&hi)) {
            switch_core_hash_this(hi, NULL, NULL, &val);
            session_data = (voice_detector_session_t *)val;
            if (session_data) {
                stream->write_function(stream, "Session: %s, Leg: %s, Voice: %s, Recording: %s, Frames: %d, Energy: %.3f, Max Silence: %dms\n", 
                    session_data->uuid, 
                    session_data->runtime_params.leg,
                    session_data->voice_detected ? "YES" : "NO",
                    session_data->is_recording ? "YES" : "NO",
                    session_data->total_frames,
                    session_data->runtime_params.energy_threshold,
                    session_data->runtime_params.max_silence);
                count++;
            }
        }
        switch_mutex_unlock(globals->mutex);

        stream->write_function(stream, "Total monitored sessions: %d\n", count);
        stream->write_function(stream, "Auto-recording: %s\n", globals->auto_record ? "enabled" : "disabled");
        stream->write_function(stream, "Recording path: %s\n", globals->recording_path);
    } else {
        stream->write_function(stream, "Unknown command: %s\n", argv[0]);
        stream->write_function(stream, "Usage: voice_detector <start|stop|status> [uuid]\n");
    }

    return SWITCH_STATUS_SUCCESS;
}

// Event hook function
static switch_status_t voice_detector_event_hook(switch_event_t *event, void *user_data)
{
    // Handle channel events if needed
    return SWITCH_STATUS_SUCCESS;
}
