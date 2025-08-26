#ifndef MOD_VOICE_DETECTOR_H
#define MOD_VOICE_DETECTOR_H

#include <switch.h>
#include <switch_types.h>
#include <switch_core.h>
#include <switch_core_event_hook.h>
#include <switch_core_media.h>
#include <switch_core_session.h>
#include <switch_core_utils.h>
#include <switch_curl.h>
#include <switch_json.h>

// Module definition macros
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
    char *leg;  // "a", "b", or "both" - which leg to monitor
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

// Session-specific data structure
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
    // Recording specific fields
    switch_record_session_t *record_session;
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

// Function declarations
static switch_status_t voice_detector_callback(switch_media_bug_t *bug, void *user_data, switch_frame_t *frame);
static switch_status_t voice_detector_session_cleanup(voice_detector_session_t *session_data);
static switch_status_t voice_detector_api_call(const char *uuid, int voice_detected, int energy_level, const char *leg);
static switch_status_t voice_detector_parse_config(switch_loadable_module_interface_t **mod_interface, switch_memory_pool_t *pool);
static switch_status_t voice_detector_start_recording(voice_detector_session_t *session_data);
static switch_status_t voice_detector_stop_recording(voice_detector_session_t *session_data);
static switch_status_t voice_detector_get_recording_filename(voice_detector_session_t *session_data, char **filename);
static switch_status_t voice_detector_parse_runtime_params(const char *data, voice_detector_runtime_params_t *params);
static switch_status_t voice_detector_apply_runtime_params(voice_detector_session_t *session_data, const voice_detector_runtime_params_t *params);
static switch_status_t voice_detector_app_function(switch_core_session_t *session, const char *data);
static switch_status_t voice_detector_api_function(switch_core_session_t *session, const char *data, switch_io_data_stream_t *stream, switch_input_callback_t *write_callback);
static switch_status_t voice_detector_event_hook(switch_event_t *event, void *user_data);

// Constants
#define VOICE_DETECTOR_SYNTAX "<start|stop|status> [uuid]"
#define DEFAULT_ENERGY_THRESHOLD 1000
#define DEFAULT_SILENCE_THRESHOLD 100
#define DEFAULT_FRAME_SIZE 160
#define DEFAULT_SAMPLE_RATE 8000
#define DEFAULT_DEBOUNCE_MS 500
#define DEFAULT_MAX_SILENCE_DURATION 2000
#define DEFAULT_AUTO_RECORD 1
#define DEFAULT_RECORDING_FORMAT 0

// Runtime parameter defaults
#define DEFAULT_SILENCE_MS 150
#define DEFAULT_THRESHOLD 0.5f
#define DEFAULT_HITS 2
#define DEFAULT_TIMEOUT 2000
#define DEFAULT_INTERRUPT_MS 50
#define DEFAULT_RUNTIME_ENERGY_THRESHOLD 0.05f
#define DEFAULT_TOTAL_ANALYSIS_TIME 4000
#define DEFAULT_MIN_WORD_LENGTH 100
#define DEFAULT_MAXIMUM_WORD_LENGTH 3500
#define DEFAULT_BETWEEN_WORDS_SILENCE 50
#define DEFAULT_MAX_SILENCE 2000
#define DEFAULT_LEG "a"  // Default to leg A

// Event type constants
#define VOICE_DETECTOR_EVENT_VOICE_START 1
#define VOICE_DETECTOR_EVENT_VOICE_END 0
#define VOICE_DETECTOR_EVENT_RECORDING_START 2
#define VOICE_DETECTOR_EVENT_RECORDING_STOP 3
#define VOICE_DETECTOR_EVENT_WORD_DETECTED 4

// Recording format constants
#define RECORDING_FORMAT_WAV 0
#define RECORDING_FORMAT_MP3 1
#define RECORDING_FORMAT_OGG 2

// Global configuration pointer
extern voice_detector_global_t *globals;

#endif // MOD_VOICE_DETECTOR_H
