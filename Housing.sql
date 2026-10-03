USE property_practice;

-- Row counts before cleaning
SELECT
  (SELECT COUNT(*) FROM agents)    AS agents,
  (SELECT COUNT(*) FROM listings)  AS listings,
  (SELECT COUNT(*) FROM inquiries) AS inquiries;
  
  SET SQL_SAFE_UPDATES = 0;

-- Remove stray spaces from area names
update listings
set area = trim(area)
where listing_id > 0;

-- Standardizing capitalization for area names
update listings
set area = case upper(area)
  when 'LEKKI' then 'Lekki'
  when 'AJAH' then 'Ajah'
  when 'IKEJA' then 'Ikeja'
  when 'YABA' then 'Yaba'
  when 'SURULERE' then 'Surulere'
  when 'GBAGADA' then 'Gbagada'
  when 'MAGODO' then 'Magodo'
  when 'MARYLAND' then 'Maryland'
  when 'IKOYI' then 'Ikoyi'
  when 'VICTORIA ISLAND' then 'Victoria Island'
  else area
end
where listing_id > 0;

select distinct area from listings order by area;


-- Find duplicate listings (same agent, area, bedrooms, rent and listed date)
SELECT agent_id, area, bedrooms, rent, listed_date, COUNT(*) AS copies
FROM listings
GROUP BY agent_id, area, bedrooms, rent, listed_date
HAVING COUNT(*) > 1;

-- (continued): identify the extra copies by listing_id (rn > 1)
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

-- Cleanup: delete the extra copies
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

-- Confirm
SELECT COUNT(*) FROM listings;

SET SQL_SAFE_UPDATES=1;
  
        -- ANALYSIS
 
 
 -- Average rent by area and property type, highest first
select area, property_type, round(avg(rent), 0) as avg_rent
from listings
group by area,property_type
order by avg_rent desc;


-- Areas have more than 20 listings and an average rent above ₦1,500,000?
SELECT area,
       COUNT(*) AS total_listings,
       ROUND(AVG(rent), 0) AS avg_rent
FROM listings
GROUP BY area
HAVING COUNT(*) > 20 AND AVG(rent) > 1500000
ORDER BY avg_rent DESC;


-- Every listing with its agent's name, including listings with no agent 
select l.listing_id, l.area, l.property_type, l.bedrooms, l.rent,
       l.status, l.listed_date,
       coalesce(a.agent_name, 'No Agent') as agent_name
from listings l
left join agents a on l.agent_id = a.agent_id;


-- Listings that received no inquiries
select l.listing_id, l.area, l.property_type, l.bedrooms, l.rent,
       l.status, l.listed_date
from listings l
left join inquiries i
  on l.listing_id = i.listing_id
where i.inquiry_id is null;


-- Average days to lease by area (slowest first)
SELECT area, ROUND(AVG(DATEDIFF(leased_date, listed_date)), 1) AS avg_days_to_lease
FROM listings
WHERE status = 'leased'
GROUP BY area
ORDER BY avg_days_to_lease DESC;


-- Rank agents by number of leased listings within each region
select region, agent_name, leased_count,
       rank() over (partition by region order by leased_count desc) as region_rank
from (
   select a.region, a.agent_name, count(*) as leased_count
   from agents a
   join listings l on l.agent_id = a.agent_id
   where l.status = 'leased'
   group by a.region, a.agent_name
) t
order by region, region_rank;


-- Monthly leases per area and the change from the previous month
WITH monthly AS (
  SELECT area,
         DATE_FORMAT(leased_date, '%Y-%m') AS month,
         COUNT(*) AS leases
  FROM listings
  WHERE status = 'leased'
  GROUP BY area, DATE_FORMAT(leased_date, '%Y-%m')
)
SELECT area, month, leases,
       leases - LAG(leases) OVER (PARTITION BY area ORDER BY month) AS change_vs_prev
FROM monthly
ORDER BY area, month;


-- Listings with a missing rent, and bedrooms with any missing values shown as 0
SELECT COUNT(*) AS missing_rent FROM listings WHERE rent IS NULL;

SELECT listing_id, bedrooms, COALESCE(bedrooms, 0) AS bedrooms_clean
FROM listings
WHERE bedrooms IS NULL;

SELECT listing_id, COALESCE(bedrooms, 0) AS bedrooms_clean
FROM listings;



-- Which inquiry channel converts best?
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

-- Extra: Month-over-month % change per area, including months with zero leases
-- Uses a recursive CTE calendar so missing months appear as 0 instead of being skipped
WITH RECURSIVE
bounds AS (
  SELECT CAST(DATE_FORMAT(MIN(leased_date), '%Y-%m-01') AS DATE) AS first_month,
         CAST(DATE_FORMAT(MAX(leased_date), '%Y-%m-01') AS DATE) AS last_month
  FROM listings
  WHERE status = 'leased'
),
months AS (
  SELECT first_month AS month_start FROM bounds
  UNION ALL
  SELECT DATE_ADD(m.month_start, INTERVAL 1 MONTH)
  FROM months m
  JOIN bounds b ON m.month_start < b.last_month
),
calendar AS (
  SELECT a.area, m.month_start
  FROM (SELECT DISTINCT area FROM listings) a
  CROSS JOIN months m
),
monthly AS (
  SELECT area,
         CAST(DATE_FORMAT(leased_date, '%Y-%m-01') AS DATE) AS month_start,
         COUNT(*) AS leases
  FROM listings
  WHERE status = 'leased'
  GROUP BY area, CAST(DATE_FORMAT(leased_date, '%Y-%m-01') AS DATE)
),
filled AS (
  SELECT c.area, c.month_start, COALESCE(m.leases, 0) AS leases
  FROM calendar c
  LEFT JOIN monthly m
    ON m.area = c.area AND m.month_start = c.month_start
),
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
WITH RECURSIVE bounds AS (
  SELECT CAST(DATE_FORMAT(MIN(leased_date), '%Y-%m-01') AS DATE) AS first_month,
         CAST(DATE_FORMAT(MAX(leased_date), '%Y-%m-01') AS DATE) AS last_month
  FROM listings
  WHERE status = 'leased'
),
months AS (
  SELECT first_month AS month_start FROM bounds
  UNION ALL
  SELECT DATE_ADD(m.month_start, INTERVAL 1 MONTH)
  FROM months m
  JOIN bounds b ON m.month_start < b.last_month
)
SELECT COUNT(*) AS months_in_calendar FROM months;