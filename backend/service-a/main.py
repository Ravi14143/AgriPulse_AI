from flask import Flask, request, jsonify
from flask_cors import CORS
import base64, requests, time, re, firebase_admin
from firebase_admin import credentials, firestore
from google.cloud import texttospeech

app = Flask(__name__)
CORS(app)

# Firebase Init
cred = credentials.Certificate("kishan-468d1-firebase-adminsdk-fbsvc-dd78759eee.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

GEMINI_API_KEY = "AIzaSyCL-1wDr3FKZmsjL4ui6tphOkdcdLjMv8Y"

def fetch_doctors():
    doctors_ref = db.collection("doctors")
    docs = doctors_ref.stream()
    return [{
        "name": doc.to_dict().get("doctorName"),
        "mobile": doc.to_dict().get("mobile"),
        "specialist": doc.to_dict().get("specialist")
    } for doc in docs]

@app.route("/diagnose", methods=["POST"])
def diagnose():
    progress = []
    t0 = time.time()

    if "image" not in request.files:
        return jsonify({"error": "No image provided", "progress": progress}), 400
    image_file = request.files["image"]
    user_text = request.form.get("description", "")
    image_bytes = base64.b64encode(image_file.read()).decode("utf-8")
    progress.append(f"[{time.time()-t0:.2f}s] ✅ Image & description received")

    # Prepare prompt
    doctors = fetch_doctors()
    doctor_list = "\n".join([f"- Dr. {d['name']}, Specialist in {d['specialist']}, Mobile: {d['mobile']}" for d in doctors]) or "No doctors listed."

    prompt = f"""
This is an image of a crop. {user_text}

Based on the visible symptoms and the user’s description, please:
1. Diagnose the disease affecting the crop.
2. Explain the causes and possible remedies.
3. Suggest the best matching doctor from the list below who can help, including name and mobile number.

Doctors available:
{doctor_list}
"""

    gemini_req = {
        "contents": [{
            "parts": [
                {"inline_data": {"mime_type": "image/jpeg", "data": image_bytes}},
                {"text": prompt}
            ]
        }]
    }

    response = requests.post(
        f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={GEMINI_API_KEY}",
        headers={"Content-Type": "application/json"},
        json=gemini_req,
    )
    diagnosis = response.json()["candidates"][0]["content"]["parts"][0]["text"]
    progress.append(f"[{time.time()-t0:.2f}s] ✅ Gemini response received")

    # Extract doctor info
    doctor_match = re.search(r"\*\*Dr\. ([^*]+)\*\*.*?Mobile: (\d{10})", diagnosis)
    doctor_name = doctor_match.group(1).strip() if doctor_match else "Not found"
    doctor_mobile = doctor_match.group(2) if doctor_match else "Not found"

    return jsonify({
        "diagnosis": diagnosis,
        "doctorName": doctor_name,
        "doctorMobile": doctor_mobile,
        "progress": progress
    })

@app.route("/tts", methods=["POST"])
def tts():
    data = request.get_json()
    text = data.get("text", "")
    client = texttospeech.TextToSpeechClient()
    input_text = texttospeech.SynthesisInput(text=text)
    voice = texttospeech.VoiceSelectionParams(language_code="en-US", name="en-US-Wavenet-D")
    config = texttospeech.AudioConfig(audio_encoding=texttospeech.AudioEncoding.MP3)
    response = client.synthesize_speech(input=input_text, voice=voice, audio_config=config)
    audio_b64 = base64.b64encode(response.audio_content).decode("utf-8")
    return jsonify({"audio_base64": audio_b64})

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)
