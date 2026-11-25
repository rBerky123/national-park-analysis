import pandas as pd
import urllib.request
import urllib.parse
import urllib.error
import json
import os
import time
from dotenv import load_dotenv

load_dotenv()

key = os.environ["NPS_API_KEY"]

CACHE_FILE = "park_info.json"
HEADERS = {"X-Api-Key": key}

def load_cache():
    if os.path.exists(CACHE_FILE):
        with open(CACHE_FILE, "r") as f:
            return json.load(f)
    return {}

def save_cache(cache):
    with open(CACHE_FILE, "w") as f:
        json.dump(cache, f, indent=4)

parks_info = pd.read_csv('national_park_data.csv')
keep_cols = ["ParkName", "UnitCode", "State", "Year", "Month", "RecreationVisits"]
working_parks = parks_info[keep_cols]

all_park_codes = list(working_parks["UnitCode"].unique())
park_codes = [c for c in all_park_codes if c not in ("KICA", "SEQU")]
park_codes.append('SEKI')

park_api_info = load_cache()

try:
    for code in park_codes:
        if code in park_api_info and park_api_info[code]["data"]:
            continue
        try:
            endpoint = f"https://developer.nps.gov/api/v1/parks?parkCode={code}"
            req = urllib.request.Request(endpoint, headers=HEADERS)
            
            with urllib.request.urlopen(req) as response:
                raw_data = response.read().decode("utf-8")
                
            park_api_info[code] = json.loads(raw_data)
        except:
            print(f"Error loading {code}")
        time.sleep(0.1)
finally:
    save_cache(park_api_info)
    print(f"Saved {len(park_api_info)} parks to {CACHE_FILE}")



rows = []

for code in all_park_codes:
    if code == "KICA" or code == "SEQU":
        park_data = park_api_info["SEKI"]["data"][0]
        coord_source = "shared with SEKI"
    else:
        park_data = park_api_info[code]["data"][0]
        coord_source = "NPS API"

    csv_name = working_parks[working_parks["UnitCode"] == code]["ParkName"].iloc[0]

    row = {
        "unit_code": code,
        "park_name": csv_name,
        "api_full_name": park_data["fullName"],
        "designation": park_data["designation"],
        "states": park_data["states"],
        "latitude": float(park_data["latitude"]),
        "longitude": float(park_data["longitude"]),
        "coord_source": coord_source,
    }
    rows.append(row)

parks = pd.DataFrame(rows)

os.makedirs("raw", exist_ok=True)
parks.to_csv("raw/parks.csv", index=False)

#----------------------weather section--------------------------------
BASE_URL = "https://archive-api.open-meteo.com/v1/archive"
WEATHER_DIR = "raw/weather"
START_DATE = "2000-01-01"
END_DATE = "2025-12-31"
EXPECTED_DAYS = 9497

os.makedirs(WEATHER_DIR, exist_ok=True)

missing = []
for code in parks["unit_code"]:
    if not os.path.exists(f"{WEATHER_DIR}/{code}.json"):
        missing.append(code)
print(f"{len(missing)} parks still need weather data")

failed = []
saved_this_run = 0

for i in range(len(parks)):
    code = parks.loc[i, "unit_code"]
    lat = parks.loc[i, "latitude"]
    lon = parks.loc[i, "longitude"]

    out_path = f"{WEATHER_DIR}/{code}.json"
    if os.path.exists(out_path):
        continue

    params = {
        "latitude": lat,
        "longitude": lon,
        "start_date": START_DATE,
        "end_date": END_DATE,
        "daily": "temperature_2m_max,temperature_2m_min,precipitation_sum",
        "timezone": "auto",
    }
    url = BASE_URL + "?" + urllib.parse.urlencode(params)

    success = False
    rate_limited = False

    try:
        with urllib.request.urlopen(url) as response:
            raw_data = response.read().decode("utf-8")
        result = json.loads(raw_data)

        if "daily" not in result:
            print(f"{code}: no 'daily' block in response")
        else:
            n_days = len(result["daily"]["time"])
            if n_days != EXPECTED_DAYS:
                print(f"{code}: got {n_days} days, expected {EXPECTED_DAYS}")
            else:
                with open(out_path, "w") as f:
                    json.dump(result, f)
                print(f"Saved {code}")
                success = True
                saved_this_run += 1

    except urllib.error.HTTPError as e:
        if e.code == 429:
            print(f"{code}: rate limited. Stopping, rerun later.")
            rate_limited = True
        else:
            print(f"{code}: HTTP error {e.code}")
    except Exception as e:
        print(f"{code}: error {e}")

    if rate_limited:
        failed.append(code)
        break

    if not success:
        failed.append(code)
    time.sleep(12)

print("Saved this run:", saved_this_run)
print("Failed:", failed)
print("Weather files total:", len(os.listdir(WEATHER_DIR)), "of", len(parks)) 
