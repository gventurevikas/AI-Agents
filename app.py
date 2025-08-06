from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import spacy
import language_tool_python
from boiler_response_ai import BERTTrainer
import json
import uvicorn

app = FastAPI(title="Boiler Response AI API")

# Initialize spaCy and language tool
nlp = spacy.load("en_core_web_sm")
tool = language_tool_python.LanguageTool('en-US')

# Initialize the AI model
try:
    ai_model = BERTTrainer("training_data.json")
    ai_model.load_data()
    ai_model.load_model("bert_trained_model")
except Exception as e:
    print(f"Error loading model: {e}")
    ai_model = None

class QuestionRequest(BaseModel):
    text: str

def preprocess_text(text: str) -> str:
    # Process text with spaCy
    doc = nlp(text)
    
    # Basic text cleaning
    cleaned_text = " ".join([token.text.lower() for token in doc if not token.is_stop and not token.is_punct])
    
    # Spell check
    matches = tool.check(cleaned_text)
    for match in matches:
        if match.replacements:
            cleaned_text = cleaned_text.replace(match.context[match.offset:match.offset + match.errorLength], match.replacements[0])
    
    return cleaned_text

@app.post("/api/ask")
async def ask_question(request: QuestionRequest):
    if not ai_model:
        raise HTTPException(status_code=503, detail="AI model not loaded")
    
    try:
        # Preprocess the input text
        processed_text = preprocess_text(request.text)
        
        # Get response from the model
        response = ai_model.predict(processed_text)
        
        return {
            "original_question": request.text,
            "processed_question": processed_text,
            "response": response
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    return {"status": "healthy", "model_loaded": ai_model is not None}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000) 