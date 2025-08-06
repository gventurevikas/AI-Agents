from fastapi import FastAPI, File, UploadFile, HTTPException, Query, BackgroundTasks
from fastapi.responses import JSONResponse
from io import BytesIO
from vosk import Model, KaldiRecognizer
import wave
import json
import subprocess
import tempfile
import os
import spacy
import language_tool_python
from pydantic import BaseModel
from typing import Optional, Dict, List
import logging
from concurrent.futures import ThreadPoolExecutor
import asyncio

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Speech-to-Text API", description="Advanced speech recognition and text processing API")

# Abusive keywords (English)
abusive_keywords = {
    "stupid", "idiot", "dumb", "moron", "retard", "asshole", "bitch", "bastard", "jerk",
    "scumbag", "loser", "dipshit", "dickhead", "prick", "wanker", "twat", "fuckhead", "shithead",
    "motherfucker", "cocksucker", "douchebag", "dumbass", "jackass", "pisshead", "fuckwit",
    "arsehole", "bellend", "clown", "cretin", "numpty", "pillock", "tosser", "git", "muppet",
    "tool", "chump", "fool", "airhead", "bonehead", "blockhead", "dimwit", "nitwit", "halfwit",
    "dunce", "knucklehead", "meathead", "pea-brain", "simpleton", "dillweed", "lamebrain",
    "numbskull", "dick", "schmuck", "shitface", "dirtbag", "fucktard", "shitbag", "skank",
    "scumbucket", "shitlicker", "cumstain", "cockroach", "maggot", "waste of space", "oxygen thief",
    "dumbfuck", "shitbrain", "clueless", "brain-dead", "imbecile", "neanderthal", "troglodyte",
    "vermin", "peasant", "filthy animal", "barbarian", "uncultured swine", "turd", "slag",
    "cow", "pig", "dog", "snake", "rat", "leech", "cockwaffle", "fucknugget", "shithole",
    "scrote", "fuckstick", "shitstain", "fartknocker", "anus", "buttface", "douche",
    "cunt", "whore", "slut", "tramp", "harlot", "trollop", "ho", "sket", "thot"
}

# Model loading with error handling
def load_model(model_path: str) -> Optional[Model]:
    try:
        if not os.path.exists(model_path):
            logger.error(f"Model path does not exist: {model_path}")
            return None
        return Model(model_path)
    except Exception as e:
        logger.error(f"Error loading model {model_path}: {str(e)}")
        return None

# Load Vosk models with error handling
model_en = load_model("/usr/local/vosk_models/vosk-model-en-us-0.22")
model_hi = load_model("/usr/local/vosk_models/hi")

if not model_en or not model_hi:
    logger.error("Failed to load one or more models. Please check model paths.")

models = {
    "en": model_en,
    "hi": model_hi
}

# Load NLP components with error handling
try:
    nlp = spacy.load("en_core_web_sm")
    tool = language_tool_python.LanguageTool('en-US')
except Exception as e:
    logger.error(f"Error loading NLP components: {str(e)}")
    nlp = None
    tool = None

class TextRequest(BaseModel):
    text: str

class TranscriptionResponse(BaseModel):
    transcription: str
    confidence: float
    language: str
    processing_time: float
    word_count: int

def remove_silence(audio_file_path: str, threshold: float = 0.1, min_silence_duration: float = 0.1) -> str:
    """Use sox to trim silence from the audio file with configurable parameters"""
    output_path = tempfile.mktemp(suffix='.wav')
    command = [
        "sox", audio_file_path, output_path,
        "silence", "1", str(min_silence_duration), f"{threshold}%",
        "-1", str(min_silence_duration), f"{threshold}%"
    ]
    try:
        subprocess.run(command, check=True, capture_output=True)
        return output_path
    except subprocess.CalledProcessError as e:
        logger.error(f"Error removing silence: {str(e)}")
        raise HTTPException(status_code=500, detail="Error processing audio file")

def process_audio_chunk(recognizer: KaldiRecognizer, data: bytes) -> str:
    """Process a chunk of audio data"""
    if recognizer.AcceptWaveform(data):
        return recognizer.Result()
    return ""

async def transcribe_audio_chunk(recognizer: KaldiRecognizer, wf: wave.Wave_read, chunk_size: int = 4000) -> str:
    """Process audio in chunks asynchronously"""
    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor() as executor:
        result = ""
        while True:
            data = wf.readframes(chunk_size)
            if len(data) == 0:
                break
            chunk_result = await loop.run_in_executor(executor, process_audio_chunk, recognizer, data)
            result += chunk_result + " "
        return result

def detect_language(audio_data: bytes) -> str:
    """Detect the language of the audio using available models"""
    try:
        # Create temporary file for audio data
        with tempfile.NamedTemporaryFile(delete=False, suffix='.wav') as temp_audio_file:
            temp_audio_file.write(audio_data)
            temp_audio_file_path = temp_audio_file.name

        wf = wave.open(temp_audio_file_path, "rb")
        if wf.getframerate() != 16000:
            raise ValueError("Audio must be 16000 Hz sample rate.")

        # Try each model and get confidence scores
        best_lang = "en"
        best_confidence = 0.0

        for lang, model in models.items():
            if not model:
                continue
                
            recognizer = KaldiRecognizer(model, wf.getframerate())
            while True:
                data = wf.readframes(4000)
                if len(data) == 0:
                    break
                recognizer.AcceptWaveform(data)
            
            result = json.loads(recognizer.FinalResult())
            confidence = len(result.get('text', '').split()) / (wf.getnframes() / wf.getframerate())
            
            if confidence > best_confidence:
                best_confidence = confidence
                best_lang = lang

        wf.close()
        os.unlink(temp_audio_file_path)
        return best_lang

    except Exception as e:
        logger.error(f"Error in language detection: {str(e)}")
        return "en"  # Default to English if detection fails

@app.post("/transcribe/", response_model=TranscriptionResponse)
async def transcribe_audio(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    lang: Optional[str] = Query(None, description="Language code (en/hi). If not provided, will auto-detect."),
    remove_silence_threshold: float = Query(0.1, description="Silence threshold (0.0-1.0)"),
    min_silence_duration: float = Query(0.1, description="Minimum silence duration in seconds")
):
    start_time = asyncio.get_event_loop().time()
    
    # Validate audio file
    if not file.filename.endswith('.wav'):
        raise HTTPException(status_code=400, detail="Only WAV files are supported")

    try:
        # Convert uploaded file to bytes
        audio_data = await file.read()
        
        # Auto-detect language if not provided
        if not lang:
            lang = detect_language(audio_data)
            logger.info(f"Detected language: {lang}")
        
        # Validate detected/provided language
        if lang not in models:
            raise HTTPException(status_code=400, detail="Unsupported language. Use 'en' or 'hi'")
        
        if not models[lang]:
            raise HTTPException(status_code=500, detail=f"Model for language {lang} not loaded properly")

        # Write to temporary file
        with tempfile.NamedTemporaryFile(delete=False, suffix='.wav') as temp_audio_file:
            temp_audio_file.write(audio_data)
            temp_audio_file_path = temp_audio_file.name

        # Remove silence with configurable parameters
        trimmed_audio_file_path = remove_silence(
            temp_audio_file_path,
            threshold=remove_silence_threshold,
            min_silence_duration=min_silence_duration
        )

        # Process audio
        wf = wave.open(trimmed_audio_file_path, "rb")
        
        if wf.getframerate() != 16000:
            raise HTTPException(status_code=400, detail="Audio must be 16000 Hz sample rate.")

        recognizer = KaldiRecognizer(models[lang], wf.getframerate())
        
        # Process audio in chunks asynchronously
        result = await transcribe_audio_chunk(recognizer, wf)
        
        # Get final result
        final_result = recognizer.FinalResult()
        result += final_result

        try:
            result_json = json.loads(result)
            transcription = result_json.get('text', '').strip()
            if not transcription:
                transcription = result.strip()
        except json.JSONDecodeError:
            transcription = result.strip()

        # Calculate confidence and word count
        confidence = 1.0  # Placeholder - implement actual confidence calculation
        word_count = len(transcription.split())
        processing_time = asyncio.get_event_loop().time() - start_time

        return TranscriptionResponse(
            transcription=transcription,
            confidence=confidence,
            language=lang,
            processing_time=processing_time,
            word_count=word_count
        )

    except Exception as e:
        logger.error(f"Error processing audio: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # Cleanup temporary files
        background_tasks.add_task(os.remove, temp_audio_file_path)
        background_tasks.add_task(os.remove, trimmed_audio_file_path)
        if 'wf' in locals():
            wf.close()

@app.post("/process_text")
async def process_text(data: TextRequest):
    """English text processing only"""
    text = data.text
    if not text:
        raise HTTPException(status_code=400, detail="No text provided")

    # English-specific processing
    corrected_text = tool.correct(text)
    doc = nlp(corrected_text)
    sentences = [sent.text for sent in doc.sents]
    tokens = [token.text for token in doc]

    return {"sentences": sentences, "tokens": tokens, "corrected": corrected_text}

@app.post("/detect_text")
async def detect_yes_no(data: TextRequest):
    """English detection only"""
    text = data.text
    if not text:
        raise HTTPException(status_code=400, detail="No text provided")

    # English keywords
    positive_keywords = {
    "yes", "yeah", "yup", "yep", "sure", "absolutely", "definitely", "certainly",
    "of course", "right", "correct", "true", "affirmative", "indeed", "alright",
    "ok", "okay", "roger", "got it", "agreed", "fine", "sounds good", "good",
    "great", "excellent", "fantastic", "brilliant", "wonderful", "superb",
    "awesome", "amazing", "perfect", "cool", "alrighty", "aye", "uh-huh",
    "for sure", "totally", "without a doubt", "undoubtedly", "you bet", "positively"
    }

    negative_keywords = {
    "no", "nah", "nope", "not", "never", "no way", "incorrect", "false",
    "negative", "wrong", "disagree", "decline", "reject", "denied",
    "not really", "not at all", "no chance", "absolutely not", "definitely not",
    "I don't think so", "out of the question", "no sir", "no ma'am", "no thanks",
    "no deal", "forget it", "nothing doing", "no way José", "by no means",
    "under no circumstances", "nah-ah", "no can do"
    }

    words = text.lower().split()
    response = "UNKNOWN"
    
    if any(word in positive_keywords for word in words):
        response = "YES"
    elif any(word in negative_keywords for word in words):
        response = "NO"

    return {"response": response}

@app.post("/detect_abusive")
async def detect_abusive_words(data: TextRequest):
    """English abusive words detection only"""
    text = data.text.lower()
    words = set(text.split())
    abusive_found = words.intersection(abusive_keywords)
    
    return {
        "abusive_words_found": list(abusive_found),
        "response": "YES" if abusive_found else "NO"
    }

@app.post("/detect_answering_machine")
async def detect_answering_machine(
    file: UploadFile = File(...)
):
    """Detect if an audio file contains an answering machine message"""
    if not file.filename.endswith('.wav'):
        raise HTTPException(status_code=400, detail="Only WAV files are supported")

    try:
        # Convert uploaded file to bytes
        audio_data = await file.read()
        
        # Write to temporary file
        with tempfile.NamedTemporaryFile(delete=False, suffix='.wav') as temp_audio_file:
            temp_audio_file.write(audio_data)
            temp_audio_file_path = temp_audio_file.name

        # Analyze audio characteristics
        wf = wave.open(temp_audio_file_path, "rb")
        
        # Get audio properties
        duration = wf.getnframes() / wf.getframerate()
        channels = wf.getnchannels()
        sample_width = wf.getsampwidth()
        
        # Common answering machine characteristics
        answering_machine_indicators = {
            "duration": {
                "min": 5,  # Minimum typical duration
                "max": 60  # Maximum typical duration
            },
            "channels": 1,  # Usually mono
            "sample_rate": 8000  # Common for answering machines
        }

        # Calculate confidence score
        confidence_score = 0.0
        total_indicators = 3

        # Check duration
        if answering_machine_indicators["duration"]["min"] <= duration <= answering_machine_indicators["duration"]["max"]:
            confidence_score += 1.0

        # Check channels
        if channels == answering_machine_indicators["channels"]:
            confidence_score += 1.0

        # Check sample rate
        if wf.getframerate() == answering_machine_indicators["sample_rate"]:
            confidence_score += 1.0

        # Calculate final confidence
        confidence_score = confidence_score / total_indicators

        # Determine result
        result = "YES" if confidence_score >= 0.5 else "NO"

        return {
            "is_answering_machine": result,
            "confidence_score": confidence_score,
            "audio_characteristics": {
                "duration_seconds": duration,
                "channels": channels,
                "sample_rate": wf.getframerate(),
                "sample_width": sample_width
            }
        }

    except Exception as e:
        logger.error(f"Error detecting answering machine: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # Cleanup temporary file
        if os.path.exists(temp_audio_file_path):
            os.remove(temp_audio_file_path)
        if 'wf' in locals():
            wf.close()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5002)
