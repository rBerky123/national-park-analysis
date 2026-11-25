import os
import pandas as pd
import snowflake.connector
from snowflake.connector.pandas_tools import write_pandas
from dotenv import load_dotenv

load_dotenv()


visits = pd.read_csv("national_park_data.csv", dtype=str)
parks = pd.read_csv("raw/parks.csv")
weather = pd.read_csv("raw/weather_daily.csv")

print(f"Weather rows: {len(weather)}")
print("Visits rows:", len(visits))   # expect 19,
print("Parks rows:", len(parks))     # expect 64

# 2. Connect
conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    password=os.environ["SNOWFLAKE_PASSWORD"],
    warehouse="PARKS_WH",
    database="PARKS_DB",
    schema="RAW",
)

success, n_chunks, n_rows, _ = write_pandas(conn, visits, "NPS_VISITS", auto_create_table=True, overwrite=True)
print("Visits loaded:", n_rows)

success, n_chunks, n_rows, _ = write_pandas(conn, parks, "PARKS", auto_create_table=True, overwrite=True)
print("Parks loaded:", n_rows)

success, n_chunks, n_rows, _ = write_pandas(conn, weather, "WEATHER_DAILY", auto_create_table=True, overwrite=True)
print("Weather days loaded:", n_rows)

conn.close()
