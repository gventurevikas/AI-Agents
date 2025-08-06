from fastapi import FastAPI, File, UploadFile
from io import BytesIO
from vosk import Model, KaldiRecognizer
import wave
import json
import subprocess
import tempfile
import os

app = FastAPI()

# Load Vosk model once during server initialization
model = Model("/usr/local/vosk_models/vosk-model-en-us-0.22")

def remove_silence(audio_file_path):
    """Use sox to trim silence from the audio file"""
    output_path = tempfile.mktemp(suffix='.wav')
    command = [
        "sox", audio_file_path, output_path,
        "silence", "1", "0.1", "1%", "-1", "0.1", "1%"
    ]
    subprocess.run(command, check=True)
    return output_path

@app.post("/transcribe/")
async def transcribe_audio(file: UploadFile = File(...)):
    # Convert uploaded file to bytes
    audio_data = await file.read()

    # Write the audio data to a temporary file
    with tempfile.NamedTemporaryFile(delete=False, suffix='.wav') as temp_audio_file:
        temp_audio_file.write(audio_data)
        temp_audio_file_path = temp_audio_file.name

    # Remove silence from the audio file using sox
    trimmed_audio_file_path = remove_silence(temp_audio_file_path)

    # Open the trimmed audio file
    wf = wave.open(trimmed_audio_file_path, "rb")

    # Check if the sample rate is 16000 Hz, as Vosk expects it
    if wf.getframerate() != 16000:
        return {"error": "Audio must be 16000 Hz sample rate."}

    recognizer = KaldiRecognizer(model, wf.getframerate())

    result = ""
    final_result = ""
    while True:
        data = wf.readframes(4000)
        if len(data) == 0:
            break
        if recognizer.AcceptWaveform(data):
            result += recognizer.Result() + " "  # Append intermediate results

    # Add the final result
    final_result = recognizer.FinalResult()

    # Combine the results and filter out empty parts
    result += final_result

    # Log the raw result before attempting to decode it
    print(f"Raw result: {result}")

    # Parse the final result JSON and extract the text
    try:
        result_json = json.loads(result)
        transcription = result_json.get('text', '')
        if not transcription:
            # If transcription is empty, fallback to using the last valid intermediate result
            transcription = result.strip()
    except json.JSONDecodeError:
        transcription = f"Error decoding transcription. Raw result: {result}"

    # Cleanup the temporary audio files
    os.remove(temp_audio_file_path)
    os.remove(trimmed_audio_file_path)

    # Return the transcription result as a JSON response
    return {"transcription": transcription}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5002)
