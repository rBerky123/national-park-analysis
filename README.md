# national-park-analysis
Python + Snowflake + SQL + Tableau pipeline analyzing 26 years of national park visits against weather.


# U.S. National Parks: Seasonality, Weather, and Recovery

An end-to-end data pipeline that pulls 26 years of monthly visitation for 64 U.S. national parks plus daily weather for each park, loads both into Snowflake, cleans and joins them with SQL, and publishes an interactive Tableau dashboard.

**[View the live dashboard on Tableau Public](https://public.tableau.com/app/profile/ryan.berkhimer/viz/U_S_NationalParksseasonalityweatherandCOVIDrecovery/Dashboard1?publish=yes)**

<img width="768" height="958" alt="image" src="https://github.com/user-attachments/assets/75f36e6f-6e40-489a-813b-1d00b3f948ce" />

---

## Questions this project answers

1. **How seasonal is each park?** Which months carry the year, and which parks are busy all year?
2. **Does weather explain visits?** Where do visits track temperature closely, and where do they not?
3. **How did parks recover after 2020, and which have grown?** Which parks are back above their 2019 level, and which are still well below it?

## Key numbers

| | |
|---|---|
| Parks | 64 (all units the NPS classifies as "National Park") |
| Period | January 2000 to December 2025 |
| Monthly visit records | 19,919 |
| Daily weather records | 607,808 (64 parks x 9,497 days) |
| Park-months in the joined analysis table | 19,968 (49 have no visit record, see [Data quality](#data-quality-and-cleaning-decisions)) |

---

## Pipeline

```
 NPS Stats (monthly visits, CSV)   --+
 NPS API (park coordinates)        --+--> Python --> Snowflake RAW --> CLEAN --> ANALYTICS --> CSV extracts --> Tableau Public
 Open-Meteo (daily weather API)    --+
```

| Layer | Schema | What it holds |
|---|---|---|
| Landing | `RAW` | Source data exactly as received (`NPS_VISITS`, `PARKS`, `WEATHER_DAILY`). Visit counts stay as text. |
| Cleaned | `CLEAN` | Typed, standardized tables: `VISITS`, `WEATHER_MONTHLY`, and the joined `PARK_MONTH` (one row per park per month). |
| Analysis | `ANALYTICS` | One table per question: `SEASONALITY`, `WEATHER_SENSITIVITY`, `RECOVERY`, `GROWTH`, `MONTHLY_SHARE`, plus the `PARK_SUMMARY` and `PARK_MONTH_EXPORT` tables that feed Tableau. |

**Stack:** Python (pandas, urllib, python-dotenv), Snowflake (SQL, `snowflake-connector-python`), Tableau Public.

### Data sources

| Source | Used for | Notes |
|---|---|---|
| [NPS Stats](https://irma.nps.gov/STATS) (Query Builder for Public Use Statistics) | Monthly recreation visits by park | Filtered to park type "National Park", 2000-2025. 2026 is excluded because the NPS marks it preliminary. |
| [NPS API](https://www.nps.gov/subjects/developer/) | Park coordinates | Free API key required. |
| [Open-Meteo Historical Weather API](https://open-meteo.com/) | Daily max/min temperature and precipitation | Free for non-commercial use, no key. Gridded reanalysis data, not station readings. |

---

## Findings

### 1. Visits are highly seasonal, but the shape differs a lot by park

- **Across all 64 parks, July is the busiest month** (about 334 million visits over 26 years) and January the quietest (about 65 million). June through September alone carries about **56%** of all visits.
- **Peak-month share ranges from about 9% to 43% of a park's year.**
- **Acadia** peaks in August with about 23% of its annual visits, and July through September together hold about **61%**.
- **Yellowstone** peaks in July with about 24% of its year, and its top three months hold about **65%**.
- **Most concentrated:** Katmai, Isle Royale, Gates of the Arctic, and North Cascades, where visits pile into a few summer months.
- **Flattest:** Hawai'i Volcanoes, Haleakala, Dry Tortugas, and Death Valley, with no single month dominating.
- **Not all parks peak in summer.** Chiricahua is busiest in late winter and spring, and Shenandoah has a distinct October peak.

### 2. Temperature predicts visits at cold-winter parks and fails elsewhere

Correlation is between a park's monthly average high temperature and its monthly visits (312 months per park, 2020 included).

| Park | Correlation | Exponential-fit R² | What the scatter looks like |
|---|---|---|---|
| Acadia | 0.91 | 0.93 | Visits stay low below about 40 F, then climb steeply |
| Everglades | -0.55 | 0.28 | Slopes downward: the park is busiest in the cooler months |
| Death Valley | 0.10 | 0.009 | A cloud with no pattern (p = 0.09) |
| Hawai'i Volcanoes | -0.01 | n/a | A narrow vertical smear: temperature barely varies (about 62-76 F) |

- **Strongest positive correlations:** Mesa Verde (0.93), Yellowstone, Yosemite, and Grand Teton (0.92 each).
- **Strongest negative:** Saguaro (-0.60), Everglades (-0.55), Virgin Islands (-0.50), Joshua Tree (-0.40). These are hot or humid parks where summer is the off-season.
- **Near zero for two different reasons:** parks with a mid-year dip or no clear seasonal peak (Death Valley, Guadalupe Mountains, Pinnacles, Congaree), and tropical parks with almost no temperature swing (Hawai'i Volcanoes, Dry Tortugas).
- R² values come from Tableau's exponential trend model (fit on the log of visits). Acadia's exponential R² of 0.93 compares with a linear R² of roughly 0.83 implied by its 0.91 correlation.

### 3. Recovery from 2020 was uneven

Percentages compare each park's 2024 and 2020 visits with 2019.

- **Still below 2019 in 2024:** American Samoa (38%), Katmai (43%), North Cascades (43%), Channel Islands (64%), Everglades (66%).
- **Above 2019:** **[N] of 64** parks exceeded their 2019 visits in 2024.
- **The 2020 drop varied enormously.** Gateway Arch fell to 24% of its 2019 level, while Cuyahoga Valley (123%), Shenandoah (117%), and Indiana Dunes (107%) had *more* visits in 2020 than in 2019.
- **Biggest gains vs. 2019:** Pinnacles (200%), Hot Springs (168%), Congaree (152%), and New River Gorge (152%), mostly smaller parks near population centers.

### 4. Long-term growth (2000-04 average vs. 2021-25 average)

Ranked only for the 53 parks with a full five-year baseline and at least 100,000 visits a year.

- **Utah's parks roughly doubled or more:** Zion +96%, Arches +103%, Canyonlands +117%, Bryce Canyon +130%, Capitol Reef +144%.
- **Joshua Tree grew +146%** (1.24M to 3.06M visits a year), the largest absolute gain among the fastest growers.
- **Acadia grew +64%** (2.44M to 3.99M a year).
- **Largest declines:** Mammoth Cave (-65%), Virgin Islands (-52%), Channel Islands (-47%), Haleakala (-42%), Gateway Arch (-37%).
- **A baseline matters.** Mammoth Cave recovered to 135% of its 2019 level, yet it is still 65% below its early-2000s level, because the decline happened before 2019.

---

## Dashboard

The Tableau Public workbook has four linked views:

1. **Park map:** dot size is average yearly visits (2021-25), color is the share of a park's visits that fall in its peak month.
2. **Seasonal heatmap:** each park's share of yearly visits by month, sorted from most to least seasonal.
3. **Weather vs. visits:** monthly visits against average monthly high temperature, with a park dropdown, a trend line, and 2020 highlighted.
4. **Recovery vs. 2019:** 2024 visits as a percent of 2019, colored by whether the park is above or below its 2019 level.

Tableau Public cannot connect to Snowflake directly, so the dashboard is built on two CSV extracts exported from the `ANALYTICS` schema (`PARK_SUMMARY` and `PARK_MONTH_EXPORT`).

---

## Data quality and cleaning decisions

Row counts were reconciled at every layer:

| Layer | Object | Rows | Check |
|---|---|---|---|
| RAW | `NPS_VISITS` | 19,919 | Matches the source file |
| RAW | `PARKS` | 64 | One row per park |
| RAW | `WEATHER_DAILY` | 607,808 | 64 parks x 9,497 days |
| CLEAN | `VISITS` | 19,919 | All 19,919 visit values converted to numbers |
| CLEAN | `WEATHER_MONTHLY` | 19,968 | Daily row total is still 607,808, so nothing was lost in the rollup |
| CLEAN | `PARK_MONTH` | 19,968 | 19,919 with visits, 49 NULL |
| ANALYTICS | `PARK_SUMMARY` | 64 | Every metric populated for all 64 parks |
| ANALYTICS | `PARK_MONTH_EXPORT` | 19,968 | 64 parks |

Decisions worth knowing about:

- **Visit counts arrive as text with thousands separators** (`"22,500"`). RAW keeps them as text. CLEAN converts with `TRY_TO_NUMBER(REPLACE(..., ',', ''))`, so a bad value would become NULL instead of failing the load. None did.
- **The source export contained every visit type** (about 35 columns, including `...Total` columns). RAW keeps all of it. CLEAN keeps six columns.
- **Missing months are NULL, not zero.** Channel Islands has no December 2005 record, and American Samoa has no data for 2000, 2001, 2004, or 2005 (48 months). The joined table starts from the complete weather calendar and `LEFT JOIN`s visits onto it, so these gaps show up as explicit NULL rows (49 in total) instead of silently disappearing.
- **Zero-visit months are kept as real zeros.** They are concentrated in remote Alaska parks and Isle Royale (for example Katmai has 77, Gates of the Arctic 76, Lake Clark 34, Isle Royale 29), which is consistent with seasonal closure.
- **Sequoia (SEQU) and Kings Canyon (KICA) share one weather point.** The NPS API has a single record for the two (`SEKI`). Both keep separate visit series (checked: they are not duplicates), and a `coord_source` column documents the shared coordinates.
- **The NPS API `designation` field is inconsistent** ("National Park & Preserve", "National and State Parks", blank for American Samoa), so the visits file is the source of truth for which parks are included.
- **The loader is idempotent.** An early run loaded the visits table twice (39,838 rows instead of 19,919), which the row-count check caught immediately. All loads now use `overwrite=True`, so rerunning the script gives the same result as running it once.
- **Weather ingestion is resumable and validated.** Each response must contain the expected 9,497 days before it is saved, existing files are skipped on rerun, and the script stops cleanly on an HTTP 429 (the free tier rate-limited the full 26-year pull, which took several sessions).
- **No weather gaps.** Zero missing temperature days across all 607,808 daily records.

---


## How to run it

### Prerequisites

- Python 3.11+
- A free [Snowflake trial](https://signup.snowflake.com/) account
- A free [NPS API key](https://www.nps.gov/subjects/developer/get-started.htm)

```bash
git clone https://github.com/rBerky123/national-park-analysis.git
cd national-park-analysis
pip install pandas python-dotenv "snowflake-connector-python[pandas]"
```

Copy `.env.example` to `.env` and fill in your values:

```
SNOWFLAKE_ACCOUNT=your-org-your-account
SNOWFLAKE_USER=your-login-name
SNOWFLAKE_PASSWORD=your-password
NPS_API_KEY=your-nps-key
```

Use your Snowflake **login name** for `SNOWFLAKE_USER`, which can differ from your username (run `DESC USER "<username>";` in Snowsight and read the `LOGIN_NAME` row). `.env` is git-ignored, so credentials never reach the repo.

### Steps

1. **Download the visits file.** In the NPS Stats *Query Builder for Public Use Statistics*: park type "National Park", all parks, years 2000-2025, field "Recreation Visits", months selected, and "Annual Summary Only" unchecked. Add Unit Code and Park Type as additional fields. Save the export as `national_park_data.csv` in the project root. (Data files are not stored in the repo.)
2. **Fetch park coordinates and weather:** `python main.py`. It builds `raw/parks.csv` and downloads daily weather per park into `raw/weather/`. If it stops on a rate limit (HTTP 429), wait and rerun: it skips parks it already has.
3. **Flatten the weather:** `python flatten_weather.py`. It writes `raw/weather_daily.csv` (607,808 rows).
4. **Create the Snowflake objects:** run `sql/00_setup.sql` in a Snowsight worksheet.
5. **Load RAW:** `python load_snowflake.py`. It is safe to rerun.
6. **Build CLEAN and ANALYTICS:** run the remaining files in `sql/` in numeric order.
7. **Export for Tableau:** download `ANALYTICS.PARK_SUMMARY` and `ANALYTICS.PARK_MONTH_EXPORT` as CSVs and connect them in Tableau.

Built by Ryan Berkhimer.
