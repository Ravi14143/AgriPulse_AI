from flask import Flask, request, jsonify
from flask_cors import CORS
import base64
import requests
import time
import firebase_admin
from firebase_admin import credentials, firestore
from google.cloud import texttospeech

# ------------------ App Setup ------------------ #
app = Flask(__name__)
CORS(app)  # Enable CORS for all origins

# Replace with your Firebase service account key
cred = credentials.Certificate("kishan-468d1-firebase-adminsdk-fbsvc-dd78759eee.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

# Replace with your Gemini API key
GEMINI_API_KEY = "AIzaSyCL-1wDr3FKZmsjL4ui6tphOkdcdLjMv8Y"

# ------------------ Helper ------------------ #
def fetch_doctors():
    try:
        doctors_ref = db.collection("doctors")
        docs = doctors_ref.stream()
        doctors = []
        for doc in docs:
            data = doc.to_dict()
            doctors.append({
                "name": data.get("doctorName"),
                "email": data.get("email"),
                "location": data.get("location"),
                "mobile": data.get("mobile"),
                "specialist": data.get("specialist")
            })
        return doctors
    except Exception as e:
        print("⚠️ Error fetching doctors:", str(e))
        return []

# ------------------ Diagnose Route ------------------ #
@app.route("/diagnose", methods=["POST"])
def diagnose():
    progress = []
    t0 = time.time()

    # Step 1: Receive image and description
    if "image" not in request.files:
        return jsonify({"error": "No image received", "details": "Form must include 'image' file.", "progress": progress}), 400

    image_file = request.files["image"]
    if image_file.filename == "":
        return jsonify({"error": "Empty image file", "progress": progress}), 400

    try:
        image_bytes = base64.b64encode(image_file.read()).decode("utf-8")
        user_text = request.form.get("description", "")
        progress.append(f"[{time.time()-t0:.2f}s] ✅ Image and description received.")
    except Exception as e:
        return jsonify({"error": "Failed to read image or description", "details": str(e), "progress": progress}), 400

    # Step 2: Construct prompt with doctor list
    doctors = fetch_doctors()
    doctor_list_text = "\n".join([
        f"- Dr. {doc['name']}, Specialist in {doc['specialist']}, Mobile: {doc['mobile']}"
        for doc in doctors
    ]) or "No doctors available."

    prompt = f"""
    This is an image of a crop. {user_text}

    Based on the visible symptoms and the user’s description, please:
    1. Diagnose the disease affecting the crop.
    2. Explain the causes and possible remedies.
    3. Suggest the best matching doctor from the list below who can help, including name and mobile number.

    Doctors available:
    {doctor_list_text}
    """
    progress.append(f"[{time.time()-t0:.2f}s] ✅ Prompt with doctors constructed.")

    # Step 3: Gemini API Request
    gemini_request = {
        "contents": [
            {
                "parts": [
                    {"inline_data": {"mime_type": "image/jpeg", "data": image_bytes}},
                    {"text": prompt}
                ]
            }
        ]
    }

    try:
        response = requests.post(
            f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={GEMINI_API_KEY}",
            headers={"Content-Type": "application/json"},
            json=gemini_request,
        )
        progress.append(f"[{time.time()-t0:.2f}s] ✅ Gemini API request sent.")
    except Exception as e:
        return jsonify({"error": "Failed to call Gemini API", "details": str(e), "progress": progress}), 500

    # Step 4: Parse Gemini Response
    try:
        gemini_output = response.json()
        print("🔍 Gemini Response:", gemini_output)

        if "candidates" not in gemini_output:
            raise KeyError("'candidates' not found in Gemini response")

        diagnosis = gemini_output["candidates"][0]["content"]["parts"][0]["text"]
        progress.append(f"[{time.time()-t0:.2f}s] ✅ Diagnosis received from Gemini.")
    except Exception as e:
        return jsonify({
            "error": "Failed to parse Gemini response",
            "details": str(e),
            "raw_response": response.text,
            "progress": progress
        }), 500

    progress.append(f"[{time.time()-t0:.2f}s] ✅ Diagnosis sent to frontend.")
    return jsonify({"diagnosis": diagnosis, "progress": progress})

# ------------------ TTS Route ------------------ #
@app.route("/tts", methods=["POST"])
def generate_tts():
    progress = []
    t0 = time.time()

    try:
        data = request.get_json()
        text = data.get("text", "")
        if not text:
            raise ValueError("Text not provided")
        progress.append(f"[{time.time()-t0:.2f}s] ✅ Text received for TTS.")
    except Exception as e:
        return jsonify({"error": "Invalid TTS input", "details": str(e), "progress": progress}), 400

    try:
        client = texttospeech.TextToSpeechClient()
        synthesis_input = texttospeech.SynthesisInput(text=text)
        voice = texttospeech.VoiceSelectionParams(
            language_code="en-US", name="en-US-Wavenet-D"
        )
        audio_config = texttospeech.AudioConfig(audio_encoding=texttospeech.AudioEncoding.MP3)
        progress.append(f"[{time.time()-t0:.2f}s] ✅ Google TTS client configured.")
    except Exception as e:
        return jsonify({"error": "Failed to configure TTS client", "details": str(e), "progress": progress}), 500

    try:
        response = client.synthesize_speech(
            input=synthesis_input, voice=voice, audio_config=audio_config
        )
        audio_b64 = base64.b64encode(response.audio_content).decode("utf-8")
        progress.append(f"[{time.time()-t0:.2f}s] ✅ Speech synthesized.")
    except Exception as e:
        return jsonify({"error": "TTS synthesis failed", "details": str(e), "progress": progress}), 500

    progress.append(f"[{time.time()-t0:.2f}s] ✅ Audio sent to frontend.")
    return jsonify({"audio_base64": audio_b64, "progress": progress})

# ------------------ Run App ------------------ #
if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)
