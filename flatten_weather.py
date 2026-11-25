import json
import os
import pandas as pd

WEATHER_DIR = "raw/weather"
rows = []
files = sorted(os.listdir(WEATHER_DIR))

for filename in files:
    if not filename.endswith(".json"):
        continue
    unit_code = filename.replace(".json", "")

    with open(f"{WEATHER_DIR}/{filename}", "r") as f:
        w = json.load(f)

    daily = w["daily"]
    for i in range(len(daily["time"])):
        rows.append({
            "unit_code": unit_code,
            "date": daily["time"][i],
            "tmax_c": daily["temperature_2m_max"][i],
            "tmin_c": daily["temperature_2m_min"][i],
            "precip_mm": daily["precipitation_sum"][i],
        })

weather = pd.DataFrame(rows)
weather.to_csv("raw/weather_daily.csv", index=False)

print("Parks:", weather["unit_code"].nunique())
print("Rows:", len(weather)) 