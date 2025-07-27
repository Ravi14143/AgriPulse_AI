from flask import Flask, request, jsonify
from flask_cors import CORS
import requests
from bs4 import BeautifulSoup
from datetime import datetime, timedelta
import firebase_admin
from firebase_admin import credentials, firestore

app = Flask(__name__)
CORS(app)

# === Firebase Init ===
cred = credentials.Certificate("kishan-468d1-firebase-adminsdk-fbsvc-dd78759eee.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

# === Utility: Get crop and state IDs from Agmarknet ===
def get_crop_and_state_ids():
    url = "https://agmarknet.gov.in/SearchCmmMkt.aspx"
    headers = {"User-Agent": "Mozilla/5.0"}
    response = requests.get(url, headers=headers)
    soup = BeautifulSoup(response.content, "html.parser")

    crop_id_map = {
        option.text.strip().lower(): option["value"]
        for option in soup.find("select", {"id": "ddlCommodity"}).find_all("option")
        if option["value"] != "0"
    }
    state_id_map = {
        option.text.strip().lower(): option["value"]
        for option in soup.find("select", {"id": "ddlState"}).find_all("option")
        if option["value"] != "0"
    }

    return crop_id_map, state_id_map

# === Scrape today's mandi prices for a crop and state ===
def fetch_crop_prices(crop_name, crop_id, user_state_name, state_id_map):
    today = datetime.today()
    from_date = (today - timedelta(days=15)).strftime("%d-%b-%Y")
    to_date = today.strftime("%d-%b-%Y")

    highest_price = -1
    lowest_price = float('inf')
    current_price = None

    for state_name, state_code in state_id_map.items():
        url = (
            f"https://agmarknet.gov.in/SearchCmmMkt.aspx?"
            f"Tx_Commodity={crop_id}&Tx_State={state_code}&Tx_District=0&Tx_Market=0"
            f"&DateFrom={from_date}&DateTo={to_date}&Fr_Date={from_date}&To_Date={to_date}"
            f"&Tx_Trend=0&Tx_CommodityHead={crop_name}&Tx_StateHead={state_name}"
            f"&Tx_DistrictHead=--Select--&Tx_MarketHead=--Select--"
        )
        headers = {"User-Agent": "Mozilla/5.0"}
        try:
            resp = requests.get(url, headers=headers, timeout=15)
            soup = BeautifulSoup(resp.content, "html.parser")
            tables = soup.find_all("table")

            for table in tables:
                if "Market Name" in table.text and "Min Price" in table.text:
                    rows = table.find_all("tr")[1:]
                    for row in rows:
                        cols = row.find_all("td")
                        if len(cols) >= 9:
                            try:
                                modal_price = int(cols[8].text.strip())
                                highest_price = max(highest_price, modal_price)
                                lowest_price = min(lowest_price, modal_price)

                                if state_name.lower() == user_state_name:
                                    current_price = modal_price
                            except:
                                continue
                    break
        except Exception as e:
            print(f"Error scraping {crop_name} in {state_name}: {e}")
            continue

    return {
        "crop": crop_name,
        "highest_price": highest_price if highest_price != -1 else None,
        "lowest_price": lowest_price if lowest_price != float('inf') else None,
        "current_price_in_user_state": current_price
    }

# === Endpoint: Today's Prices for All User Crops ===
@app.route('/user-crop-prices/<userid>', methods=['GET'])
def get_user_crop_prices(userid):
    user_ref = db.collection("users").document(userid)
    user_doc = user_ref.get()
    if not user_doc.exists:
        return jsonify({"error": "User not found"}), 404

    user_data = user_doc.to_dict()
    user_state = user_data.get("state", "").strip().lower()
    if not user_state:
        return jsonify({"error": "User state missing"}), 400

    crop_docs = db.collection("crops").where("userid", "==", userid).stream()
    user_crops = []
    for doc in crop_docs:
        crop_data = doc.to_dict()
        crop_name = crop_data.get("cropname", "").strip().lower()
        crop_state = crop_data.get("cropstate", "").strip().lower()
        if crop_name and crop_state:
            user_crops.append((crop_name, crop_state))

    if not user_crops:
        return jsonify({"error": "No crops found for user"}), 404

    crop_id_map, state_id_map = get_crop_and_state_ids()
    user_state_code = state_id_map.get(user_state)
    if not user_state_code:
        return jsonify({"error": f"User state '{user_state}' not found in Agmarknet"}), 400

    results = []
    for crop_name, crop_state in user_crops:
        crop_id = crop_id_map.get(crop_name)
        if not crop_id:
            continue
        result = fetch_crop_prices(crop_name, crop_id, user_state, state_id_map)
        results.append(result)

    return jsonify(results)

# === Endpoint: Custom Date-Range Mandi Prices ===
@app.route('/mandi-prices', methods=['GET'])
def get_mandi_prices():
    crop = request.args.get('crop')
    state = request.args.get('state')
    from_date = request.args.get('from_date')
    to_date = request.args.get('to_date')

    if not all([crop, state, from_date, to_date]):
        return jsonify({"error": "Missing required parameters"}), 400

    # Use fixed mapping (or dynamic if needed)
    crop_id_map, state_id_map = get_crop_and_state_ids()
    crop_id = crop_id_map.get(crop.strip().lower())
    state_code = state_id_map.get(state.strip().lower())

    if not crop_id or not state_code:
        return jsonify({"error": "Invalid crop or state name"}), 400

    url = (
        f"https://agmarknet.gov.in/SearchCmmMkt.aspx?"
        f"Tx_Commodity={crop_id}&Tx_State={state_code}&Tx_District=0&Tx_Market=0"
        f"&DateFrom={from_date}&DateTo={to_date}&Fr_Date={from_date}&To_Date={to_date}"
        f"&Tx_Trend=0&Tx_CommodityHead={crop}&Tx_StateHead={state}"
        f"&Tx_DistrictHead=--Select--&Tx_MarketHead=--Select--"
    )

    headers = {"User-Agent": "Mozilla/5.0"}
    response = requests.get(url, headers=headers)
    soup = BeautifulSoup(response.content, "html.parser")
    tables = soup.find_all("table")

    target_table = None
    for table in tables:
        if "Market Name" in table.text and "Min Price" in table.text:
            target_table = table
            break

    if not target_table:
        return jsonify({"error": "No price data found"}), 404

    rows = target_table.find_all("tr")
    mandi_data = []

    for row in rows[1:]:
        cols = row.find_all("td")
        if len(cols) >= 10:
            mandi_data.append({
                "district": cols[1].text.strip(),
                "market": cols[2].text.strip(),
                "commodity": cols[3].text.strip(),
                "variety": cols[4].text.strip(),
                "grade": cols[5].text.strip(),
                "min_price": cols[6].text.strip(),
                "max_price": cols[7].text.strip(),
                "modal_price": cols[8].text.strip(),
                "date": cols[9].text.strip()
            })

    return jsonify(mandi_data)

# === Root Endpoint ===
@app.route('/')
def home():
    return jsonify({"message": "🌾 Mandi Price API is running!"})

# === Run Server ===
if __name__ == '__main__':
    app.run(debug=True)
