CREATE WAREHOUSE PARKS_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 30
  AUTO_RESUME = TRUE;

CREATE DATABASE PARKS_DB;
CREATE SCHEMA PARKS_DB.RAW;
CREATE SCHEMA PARKS_DB.CLEAN;
CREATE SCHEMA PARKS_DB.ANALYTICS;


SHOW SCHEMAS IN DATABASE PARKS_DB;



SELECT COUNT(*) FROM PARKS_DB.RAW.NPS_VISITS;     -- 19919
SELECT COUNT(*) FROM PARKS_DB.RAW.PARKS;          -- 64
SELECT COUNT(*) FROM PARKS_DB.RAW.WEATHER_DAILY;  -- 607,808


CREATE OR REPLACE TABLE PARKS_DB.CLEAN.VISITS AS
SELECT
  UPPER("UnitCode")                                                  AS unit_code,
  "ParkName"                                                         AS park_name,
  TRY_TO_NUMBER("Year")                                              AS year,
  TRY_TO_NUMBER("Month")                                             AS month,
  DATE_FROM_PARTS(TRY_TO_NUMBER("Year"), TRY_TO_NUMBER("Month"), 1)  AS month_start,
  TRY_TO_NUMBER(REPLACE("RecreationVisits", ',', ''))                AS recreation_visits
FROM PARKS_DB.RAW.NPS_VISITS;



SELECT COUNT(*)                AS total_rows,
       COUNT(recreation_visits) AS rows_with_visits,
       MIN(month_start)         AS first_month,
       MAX(month_start)         AS last_month
FROM PARKS_DB.CLEAN.VISITS;


CREATE OR REPLACE TABLE PARKS_DB.ANALYTICS.SEASONALITY AS
WITH monthly AS (
  -- Step 1: average visits for each park in each calendar month
  SELECT unit_code, park_name, month,
         AVG(recreation_visits) AS avg_visits
  FROM PARKS_DB.CLEAN.VISITS
  GROUP BY unit_code, park_name, month
),
shares AS (
  -- Step 2: each month's share of the park's year, and its rank within the park
  SELECT unit_code, park_name, month, avg_visits,
         avg_visits / SUM(avg_visits) OVER (PARTITION BY unit_code) AS month_share,
         ROW_NUMBER() OVER (PARTITION BY unit_code ORDER BY avg_visits DESC) AS month_rank
  FROM monthly
)
-- Step 3: collapse to one row per park using only its top 3 months
SELECT unit_code,
       park_name,
       MAX(CASE WHEN month_rank = 1 THEN month END)                  AS peak_month,
       ROUND(MAX(CASE WHEN month_rank = 1 THEN month_share END), 3)  AS peak_share,
       ROUND(SUM(month_share), 3)                                    AS top3_share
FROM shares
WHERE month_rank <= 3
GROUP BY unit_code, park_name;

DESCRIBE TABLE PARKS_DB.RAW.WEATHER_DAILY;


CREATE OR REPLACE TABLE PARKS_DB.CLEAN.WEATHER_MONTHLY AS
SELECT
  UPPER("unit_code")                                       AS unit_code,
  DATE_TRUNC('month', TRY_TO_DATE("date"))                 AS month_start,
  ROUND(AVG("tmax_c"), 1)                                  AS avg_high_c,
  ROUND(AVG("tmin_c"), 1)                                  AS avg_low_c,
  ROUND(SUM("precip_mm"), 1)                               AS total_precip_mm,
  COUNT_IF("tmin_c" < 0)                                   AS freezing_days,
  COUNT(*)                                                 AS days_in_month,
  COUNT("tmax_c")                                          AS days_with_temp
FROM PARKS_DB.RAW.WEATHER_DAILY
GROUP BY UPPER("unit_code"), DATE_TRUNC('month', TRY_TO_DATE("date"));


SELECT COUNT(*) AS rows_, COUNT(DISTINCT unit_code) AS parks,
       MIN(month_start), MAX(month_start),
       SUM(days_in_month) AS total_days
FROM PARKS_DB.CLEAN.WEATHER_MONTHLY;

SELECT * FROM PARKS_DB.CLEAN.WEATHER_MONTHLY
WHERE unit_code = 'ACAD' AND MONTH(month_start) IN (1, 7)
ORDER BY month_start LIMIT 6;



CREATE OR REPLACE TABLE PARKS_DB.CLEAN.PARK_MONTH AS
SELECT
  w.unit_code,
  w.month_start,
  w.avg_high_c,
  w.avg_low_c,
  w.total_precip_mm,
  w.freezing_days,
  v.recreation_visits
FROM PARKS_DB.CLEAN.WEATHER_MONTHLY w
LEFT JOIN PARKS_DB.CLEAN.VISITS v
  ON w.unit_code = v.unit_code
 AND w.month_start = v.month_start;

 SELECT COUNT(*) AS total_rows,
       COUNT(recreation_visits) AS rows_with_visits,
       COUNT(*) - COUNT(recreation_visits) AS missing_visit_months
FROM PARKS_DB.CLEAN.PARK_MONTH;

SELECT unit_code, COUNT(*) AS missing_months
FROM PARKS_DB.CLEAN.PARK_MONTH
WHERE recreation_visits IS NULL
GROUP BY unit_code;

CREATE OR REPLACE TABLE PARKS_DB.ANALYTICS.WEATHER_SENSITIVITY AS
SELECT unit_code,
       ROUND(CORR(avg_high_c, recreation_visits), 2) AS temp_correlation
FROM PARKS_DB.CLEAN.PARK_MONTH
WHERE YEAR(month_start) <> 2020
GROUP BY unit_code
ORDER BY temp_correlation, unit_code;


select month, sum(recreation_visits) as visit_sum
from PARKS_DB.CLEAN.VISITS
where unit_code='DEVA'
group by month
order by visit_sum desc;

CREATE OR REPLACE TABLE PARKS_DB.ANALYTICS.RECOVERY AS
SELECT
  unit_code,
  MAX(park_name) AS park_name,
  SUM(CASE WHEN year = 2019 THEN recreation_visits END) AS visits_2019,
  SUM(CASE WHEN year = 2020 THEN recreation_visits END) AS visits_2020,
  SUM(CASE WHEN year = 2024 THEN recreation_visits END) AS visits_2024,
  ROUND(100 * SUM(CASE WHEN year = 2020 THEN recreation_visits END)
        / NULLIF(SUM(CASE WHEN year = 2019 THEN recreation_visits END), 0), 1) AS pct_2020_vs_2019,
  ROUND(100 * SUM(CASE WHEN year = 2024 THEN recreation_visits END)
        / NULLIF(SUM(CASE WHEN year = 2019 THEN recreation_visits END), 0), 1) AS pct_2024_vs_2019
FROM PARKS_DB.CLEAN.VISITS
GROUP BY unit_code;


SELECT unit_code, park_name, visits_2019, visits_2024, pct_2020_vs_2019, pct_2024_vs_2019
FROM PARKS_DB.ANALYTICS.RECOVERY
ORDER BY pct_2024_vs_2019 DESC;



CREATE OR REPLACE TABLE PARKS_DB.ANALYTICS.GROWTH AS
WITH yearly AS (
  SELECT unit_code, MAX(park_name) AS park_name, year,
         SUM(recreation_visits) AS total_visits
  FROM PARKS_DB.CLEAN.VISITS
  GROUP BY unit_code, year
)
SELECT
  unit_code,
  park_name,
  AVG(CASE WHEN year BETWEEN 2000 AND 2004 THEN total_visits END) AS avg_2000_2004,
  AVG(CASE WHEN year BETWEEN 2021 AND 2025 THEN total_visits END) AS avg_2021_2025,
  ROUND(100 * (AVG(CASE WHEN year BETWEEN 2021 AND 2025 THEN total_visits END)
        / NULLIF(AVG(CASE WHEN year BETWEEN 2000 AND 2004 THEN total_visits END), 0) - 1), 1) AS pct_change
FROM yearly
GROUP BY unit_code, park_name;


SELECT unit_code, park_name, avg_2000_2004, avg_2021_2025, pct_change
FROM PARKS_DB.ANALYTICS.GROWTH
ORDER BY pct_change DESC;


CREATE OR REPLACE TABLE PARKS_DB.ANALYTICS.WEATHER_SENSITIVITY AS
SELECT unit_code,
       ROUND(CORR(avg_high_c, recreation_visits), 2) AS temp_correlation
FROM PARKS_DB.CLEAN.PARK_MONTH
GROUP BY unit_code;


CREATE OR REPLACE TABLE PARKS_DB.ANALYTICS.GROWTH AS
WITH yearly AS (
  SELECT unit_code, MAX(park_name) AS park_name, year,
         SUM(recreation_visits) AS total_visits
  FROM PARKS_DB.CLEAN.VISITS
  GROUP BY unit_code, year
),
windows AS (
  SELECT
    unit_code,
    park_name,
    AVG(CASE WHEN year BETWEEN 2000 AND 2004 THEN total_visits END) AS avg_2000_2004,
    AVG(CASE WHEN year BETWEEN 2021 AND 2025 THEN total_visits END) AS avg_2021_2025,
    COUNT(CASE WHEN year BETWEEN 2000 AND 2004 THEN 1 END)          AS baseline_years
  FROM yearly
  GROUP BY unit_code, park_name
)
SELECT
  unit_code,
  park_name,
  ROUND(avg_2000_2004, 0)                                        AS avg_2000_2004,
  ROUND(avg_2021_2025, 0)                                        AS avg_2021_2025,
  ROUND(avg_2021_2025 - avg_2000_2004, 0)                        AS abs_change,
  ROUND(100 * (avg_2021_2025 / NULLIF(avg_2000_2004, 0) - 1), 1) AS pct_change,
  baseline_years,
  IFF(baseline_years = 5 AND avg_2000_2004 >= 100000, TRUE, FALSE) AS is_rankable
FROM windows;


SHOW TABLES IN SCHEMA PARKS_DB.ANALYTICS;


DESCRIBE TABLE PARKS_DB.ANALYTICS.GROWTH;


SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT unit_code) AS parks
FROM PARKS_DB.ANALYTICS.GROWTH;

SELECT baseline_years, is_rankable, COUNT(*) AS parks
FROM PARKS_DB.ANALYTICS.GROWTH
GROUP BY baseline_years, is_rankable
ORDER BY baseline_years, is_rankable;

SELECT year, SUM(recreation_visits) AS total_visits
FROM PARKS_DB.CLEAN.VISITS
WHERE unit_code = 'ACAD' AND year BETWEEN 2000 AND 2004
GROUP BY year
ORDER BY year;

SELECT * FROM PARKS_DB.ANALYTICS.GROWTH WHERE unit_code = 'ACAD';


SELECT unit_code, park_name, avg_2000_2004, avg_2021_2025, abs_change, pct_change
FROM PARKS_DB.ANALYTICS.GROWTH
WHERE is_rankable
ORDER BY pct_change ASC
LIMIT 5;


SELECT park_name, visits_2019, pct_2020_vs_2019, pct_2024_vs_2019
FROM PARKS_DB.ANALYTICS.PARK_SUMMARY
ORDER BY pct_2024_vs_2019 ASC
LIMIT 5;



CREATE OR REPLACE TABLE PARKS_DB.ANALYTICS.PARK_SUMMARY AS
SELECT
  p."unit_code"          AS unit_code,
  p."park_name"          AS park_name,
  p."states"             AS states,
  p."latitude"           AS latitude,
  p."longitude"          AS longitude,
  s.peak_month,
  s.peak_share,
  s.top3_share,
  w.temp_correlation,
  r.visits_2019,
  r.pct_2020_vs_2019,
  r.pct_2024_vs_2019,
  g.avg_2000_2004,
  g.avg_2021_2025,
  g.abs_change,
  g.pct_change,
  g.is_rankable
FROM PARKS_DB.RAW.PARKS p
LEFT JOIN PARKS_DB.ANALYTICS.SEASONALITY         s ON p."unit_code" = s.unit_code
LEFT JOIN PARKS_DB.ANALYTICS.WEATHER_SENSITIVITY w ON p."unit_code" = w.unit_code
LEFT JOIN PARKS_DB.ANALYTICS.RECOVERY            r ON p."unit_code" = r.unit_code
LEFT JOIN PARKS_DB.ANALYTICS.GROWTH              g ON p."unit_code" = g.unit_code;


SELECT COUNT(*) AS rows_,
       COUNT(peak_month)       AS has_seasonality,
       COUNT(temp_correlation) AS has_correlation,
       COUNT(pct_2024_vs_2019) AS has_recovery,
       COUNT(pct_change)       AS has_growth
FROM PARKS_DB.ANALYTICS.PARK_SUMMARY;


SELECT park_name, visits_2019, pct_2020_vs_2019, pct_2024_vs_2019
FROM PARKS_DB.ANALYTICS.PARK_SUMMARY
ORDER BY pct_2024_vs_2019 ASC
LIMIT 5;


CREATE OR REPLACE TABLE PARKS_DB.ANALYTICS.PARK_MONTH_EXPORT AS
SELECT
  pm.unit_code,
  p."park_name"                AS park_name,
  pm.month_start,
  MONTH(pm.month_start)        AS month_num,
  YEAR(pm.month_start)         AS year,
  pm.avg_high_c,
  ROUND(pm.avg_high_c * 9/5 + 32, 1) AS avg_high_f,
  pm.avg_low_c,
  pm.total_precip_mm,
  pm.freezing_days,
  pm.recreation_visits
FROM PARKS_DB.CLEAN.PARK_MONTH pm
JOIN PARKS_DB.RAW.PARKS p ON pm."unit_code" = p."unit_code";



CREATE OR REPLACE TABLE PARKS_DB.ANALYTICS.PARK_MONTH_EXPORT AS
SELECT
  pm.unit_code,
  p."park_name"                       AS park_name,
  pm.month_start,
  MONTH(pm.month_start)               AS month_num,
  YEAR(pm.month_start)                AS year,
  pm.avg_high_c,
  ROUND(pm.avg_high_c * 9/5 + 32, 1)  AS avg_high_f,
  pm.avg_low_c,
  pm.total_precip_mm,
  pm.freezing_days,
  pm.recreation_visits
FROM PARKS_DB.CLEAN.PARK_MONTH pm
JOIN PARKS_DB.RAW.PARKS p
  ON pm.unit_code = p."unit_code";


SELECT COUNT(*) AS rows_, COUNT(DISTINCT unit_code) AS parks
FROM PARKS_DB.ANALYTICS.PARK_MONTH_EXPORT;



SELECT * FROM PARKS_DB.ANALYTICS.PARK_SUMMARY;        -- save as park_summary.csv

SELECT * FROM PARKS_DB.ANALYTICS.PARK_MONTH_EXPORT;   -- save as park_month.csv

CREATE OR REPLACE TABLE PARKS_DB.ANALYTICS.MONTHLY_SHARE AS
WITH monthly AS (
  SELECT unit_code, park_name, month AS month_num,
         AVG(recreation_visits) AS avg_visits
  FROM PARKS_DB.CLEAN.VISITS
  GROUP BY unit_code, park_name, month
)
SELECT unit_code,
       park_name,
       month_num,
       ROUND(avg_visits, 0) AS avg_visits,
       ROUND(avg_visits / SUM(avg_visits) OVER (PARTITION BY unit_code), 4) AS month_share
FROM monthly;

SELECT COUNT(*) AS rows_,
       COUNT(DISTINCT unit_code) AS parks,
       MAX(month_share) AS highest_share
FROM PARKS_DB.ANALYTICS.MONTHLY_SHARE;

SELECT unit_code, ROUND(SUM(month_share), 3) AS total
FROM PARKS_DB.ANALYTICS.MONTHLY_SHARE
GROUP BY unit_code
ORDER BY total
LIMIT 3;


SELECT * FROM PARKS_DB.ANALYTICS.MONTHLY_SHARE;