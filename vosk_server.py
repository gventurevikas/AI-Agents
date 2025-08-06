import json
import asyncio
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from vosk import Model, KaldiRecognizer
import uvicorn
import wave
import struct

# Load Vosk ASR Model
MODEL_PATH = "/usr/local/vosk_models/vosk-model-en-us-0.22/"
model = Model(MODEL_PATH)

# SSL Certificate Paths
SSL_CERT_PATH = "/etc/letsencrypt/live/websocket.gventure.us/fullchain.pem"
SSL_KEY_PATH = "/etc/letsencrypt/live/websocket.gventure.us/privkey.pem"

# Audio configuration
SAMPLE_RATE = 16000
CHANNELS = 1
SAMPLE_WIDTH = 2  # 16-bit audio

app = FastAPI()

@app.websocket("/asr")
async def websocket_endpoint(websocket: WebSocket):
    """Handles WebSocket connections for ASR"""
    await websocket.accept()
    print("✅ New Secure Connection Established (WSS)")

    recognizer = KaldiRecognizer(model, SAMPLE_RATE)
    recognizer.SetWords(True)

    try:
        while True:
            try:
                # Receive audio data
                message = await websocket.receive_bytes()
                
                # Process the audio chunk
                if recognizer.AcceptWaveform(message):
                    result = json.loads(recognizer.Result())
                    if result["text"].strip():  # Only send non-empty results
                        print("📝 Transcription:", result["text"])
                        await websocket.send_text(json.dumps(result))
                
                # Send partial results for real-time feedback
                partial = json.loads(recognizer.PartialResult())
                if partial["partial"].strip():  # Only send non-empty partial results
                    await websocket.send_text(json.dumps(partial))

            except Exception as e:
                print(f"🔥 Error processing audio chunk: {e}")
                continue

    except WebSocketDisconnect:
        print("⚠️ Client Disconnected")
    except asyncio.CancelledError:
        print("❌ Connection Cancelled")
    except Exception as e:
        print(f"🔥 Error: {e}")
    finally:
        # Send final result if available
        try:
            final_result = json.loads(recognizer.FinalResult())
            if final_result["text"].strip():
                print("🎤 Final Transcription:", final_result["text"])
                await websocket.send_text(json.dumps(final_result))
        except Exception as e:
            print(f"🔥 Error sending final result: {e}")

if __name__ == "__main__":
    uvicorn.run(
        app, 
        host="0.0.0.0", 
        port=2700, 
        ssl_keyfile=SSL_KEY_PATH, 
        ssl_certfile=SSL_CERT_PATH
    )
