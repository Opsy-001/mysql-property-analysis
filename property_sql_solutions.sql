-- =====================================================================
-- Property Dataset (Lagos) - SQL Practice Solutions (MySQL 8.0+)
-- Author: Abigail Abiodun Opeyemi
--
-- How to run:
--   1. Run property_mysql.sql once to load fresh, dirty data.
--   2. Run this file from the top.
-- Part 1 cleans the data (and answers Q7). Part 2 answers the other questions.
-- =====================================================================

USE property_practice;

-- ---------------------------------------------------------------------
-- PART 1: DATA CLEANING
-- ---------------------------------------------------------------------

-- Row counts before cleaning (expect 25 agents, 609 listings, 2101 inquiries)
SELECT
  (SELECT COUNT(*) FROM agents)    AS agents,
  (SELECT COUNT(*) FROM listings)  AS listings,
  (SELECT COUNT(*) FROM inquiries) AS inquiries;

SET SQL_SAFE_UPDATES = 0;

-- Remove stray spaces from area names
UPDATE listings
SET area = TRIM(area)
WHERE listing_id > 0;

-- Standardize capitalization of area names
UPDATE listings
SET area = CASE UPPER(area)
  WHEN 'LEKKI' THEN 'Lekki'
  WHEN 'AJAH' THEN 'Ajah'
  WHEN 'IKEJA' THEN 'Ikeja'
  WHEN 'YABA' THEN 'Yaba'
  WHEN 'SURULERE' THEN 'Surulere'
  WHEN 'GBAGADA' THEN 'Gbagada'
  WHEN 'MAGODO' THEN 'Magodo'
  WHEN 'MARYLAND' THEN 'Maryland'
  WHEN 'IKOYI' THEN 'Ikoyi'
  WHEN 'VICTORIA ISLAND' THEN 'Victoria Island'
  ELSE area
END
WHERE listing_id > 0;

-- Check: expect exactly 10 distinct areas
SELECT DISTINCT area FROM listings ORDER BY area;

-- Q7: Find duplicate listings (same agent, area, bedrooms, rent and listed date)
-- On fresh data this returns 9 rows, each with copies = 2
SELECT agent_id, area, bedrooms, rent, listed_date, COUNT(*) AS copies
FROM listings
GROUP BY agent_id, area, bedrooms, rent, listed_date
HAVING COUNT(*) > 1;

-- Q7 (continued): identify the extra copies by listing_id (rn > 1)
SELECT listing_id, agent_id, area, bedrooms, rent, listed_date, rn
FROM (
  SELECT listing_id, agent_id, area, bedrooms, rent, listed_date,
         ROW_NUMBER() OVER (
           PARTITION BY agent_id, area, bedrooms, rent, listed_date
           ORDER BY listing_id
         ) AS rn
  FROM listings
) t
WHERE rn > 1;

-- Cleanup: delete the extra copies, keeping the lowest listing_id of each set
DELETE l
FROM listings l
JOIN (
  SELECT listing_id
  FROM (
    SELECT listing_id,
           ROW_NUMBER() OVER (
             PARTITION BY agent_id, area, bedrooms, rent, listed_date
             ORDER BY listing_id
           ) AS rn
    FROM listings
  ) t
  WHERE rn > 1
) d ON l.listing_id = d.listing_id;

-- Confirm: expect 600 listings
SELECT COUNT(*) AS listings_after_cleaning FROM listings;

SET SQL_SAFE_UPDATES = 1;

-- ---------------------------------------------------------------------
-- PART 2: ANALYSIS QUESTIONS (run on the cleaned data)
-- ---------------------------------------------------------------------

-- Q1: Average rent by area and property type, highest first (expect 50 rows)
SELECT area, property_type, ROUND(AVG(rent), 0) AS avg_rent
FROM listings
GROUP BY area, property_type
ORDER BY avg_rent DESC;

-- Q2: Areas with more than 20 listings and an average rent above 1,500,000
SELECT area,
       COUNT(*) AS total_listings,
       ROUND(AVG(rent), 0) AS avg_rent
FROM listings
GROUP BY area
HAVING COUNT(*) > 20 AND AVG(rent) > 1500000
ORDER BY avg_rent DESC;

-- Q3: Every listing with its agent's name, including listings with no agent
SELECT l.listing_id, l.area, l.property_type, l.bedrooms, l.rent,
       l.status, l.listed_date,
       COALESCE(a.agent_name, 'No Agent') AS agent_name
FROM listings l
LEFT JOIN agents a ON l.agent_id = a.agent_id;

-- Q4: Listings that received no inquiries
SELECT l.listing_id, l.area, l.property_type, l.bedrooms, l.rent,
       l.status, l.listed_date
FROM listings l
LEFT JOIN inquiries i ON l.listing_id = i.listing_id
WHERE i.inquiry_id IS NULL;

-- Q5: Average days to lease by area (slowest first)
SELECT area, ROUND(AVG(DATEDIFF(leased_date, listed_date)), 1) AS avg_days_to_lease
FROM listings
WHERE status = 'leased'
GROUP BY area
ORDER BY avg_days_to_lease DESC;

-- Q6: Rank agents by number of leased listings within each region
SELECT region, agent_name, leased_count,
       RANK() OVER (PARTITION BY region ORDER BY leased_count DESC) AS region_rank
FROM (
  SELECT a.region, a.agent_name, COUNT(*) AS leased_count
  FROM agents a
  JOIN listings l ON l.agent_id = a.agent_id
  WHERE l.status = 'leased'
  GROUP BY a.region, a.agent_name
) t
ORDER BY region, region_rank;

-- Q7: answered in Part 1 above (duplicate detection, identification and cleanup)

-- Q8: Monthly leases per area and the change from the previous month
-- Note: months with zero leases have no row, so LAG compares to the previous month that has data
WITH monthly AS (
  SELECT area,
         DATE_FORMAT(leased_date, '%Y-%m') AS lease_month,
         COUNT(*) AS leases
  FROM listings
  WHERE status = 'leased'
  GROUP BY area, DATE_FORMAT(leased_date, '%Y-%m')
)
SELECT area, lease_month, leases,
       leases - LAG(leases) OVER (PARTITION BY area ORDER BY lease_month) AS change_vs_prev
FROM monthly
ORDER BY area, lease_month;

-- Q9: Listings with a missing rent, and bedrooms with missing values shown as 0
SELECT COUNT(*) AS missing_rent FROM listings WHERE rent IS NULL;

SELECT listing_id, bedrooms, COALESCE(bedrooms, 0) AS bedrooms_clean
FROM listings
WHERE bedrooms IS NULL;

-- Q10: Which inquiry channel converts best?
-- Share of listings with an inquiry in that channel that ended up leased.
-- A listing with inquiries from several channels counts once in each.
SELECT i.channel,
       COUNT(DISTINCT i.listing_id) AS listings_with_inquiry,
       COUNT(DISTINCT CASE WHEN l.status = 'leased' THEN l.listing_id END) AS leased,
       ROUND(
         100 * COUNT(DISTINCT CASE WHEN l.status = 'leased' THEN l.listing_id END)
             / COUNT(DISTINCT i.listing_id),
         1) AS conversion_pct
FROM inquiries i
JOIN listings l ON l.listing_id = i.listing_id
GROUP BY i.channel
ORDER BY conversion_pct DESC;

-- ---------------------------------------------------------------------
-- EXTRA: Month-over-month % change per area, including months with zero leases
-- Uses a recursive CTE calendar so missing months appear as 0 instead of being skipped.
-- A % change from a previous month of 0 is undefined, so it is returned as NULL.
-- ---------------------------------------------------------------------
WITH RECURSIVE
-- first and last month that had a lease
bounds AS (
  SELECT CAST(DATE_FORMAT(MIN(leased_date), '%Y-%m-01') AS DATE) AS first_month,
         CAST(DATE_FORMAT(MAX(leased_date), '%Y-%m-01') AS DATE) AS last_month
  FROM listings
  WHERE status = 'leased'
),
-- one row per month from the first to the last lease month
months AS (
  SELECT first_month AS month_start FROM bounds
  UNION ALL
  SELECT DATE_ADD(m.month_start, INTERVAL 1 MONTH)
  FROM months m
  JOIN bounds b ON m.month_start < b.last_month
),
-- every area paired with every month
calendar AS (
  SELECT a.area, m.month_start
  FROM (SELECT DISTINCT area FROM listings) a
  CROSS JOIN months m
),
-- actual lease counts per area and month
monthly AS (
  SELECT area,
         CAST(DATE_FORMAT(leased_date, '%Y-%m-01') AS DATE) AS month_start,
         COUNT(*) AS leases
  FROM listings
  WHERE status = 'leased'
  GROUP BY area, CAST(DATE_FORMAT(leased_date, '%Y-%m-01') AS DATE)
),
-- join counts onto the calendar; missing months become 0
filled AS (
  SELECT c.area, c.month_start, COALESCE(m.leases, 0) AS leases
  FROM calendar c
  LEFT JOIN monthly m
    ON m.area = c.area AND m.month_start = c.month_start
),
-- previous month's count for each area
with_prev AS (
  SELECT area, month_start, leases,
         LAG(leases) OVER (PARTITION BY area ORDER BY month_start) AS prev_leases
  FROM filled
)
SELECT area,
       DATE_FORMAT(month_start, '%Y-%m') AS lease_month,
       leases,
       prev_leases,
       ROUND(100 * (leases - prev_leases) / NULLIF(prev_leases, 0), 1) AS pct_change
FROM with_prev
ORDER BY area, month_start;
