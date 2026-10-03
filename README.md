# Lagos Property Listings: SQL Analysis (MySQL)

A self-directed SQL project that cleans and analyzes a relational property-listings dataset in MySQL 8.0.
The data is **synthetic** (randomly generated for practice) and modeled on Lagos rental listings. Rents are in naira per year.

## Dataset
| Table | Rows | Description |
|---|---|---|
| `listings` | 609 (600 after cleaning) | Property type, area, bedrooms, rent, status, listed and leased dates |
| `agents` | 25 | Agent name, region, hire date |
| `inquiries` | 2,101 | Customer inquiries by listing and channel (WhatsApp, Website, Instagram, Referral, Walk-in) |

The data was loaded with deliberate quality problems: missing values, inconsistent area names, and duplicate listings.

## Data cleaning
- Standardized area names (trailing spaces and inconsistent capitalization) with `TRIM()` and `CASE`
- Found duplicate listings with `GROUP BY ... HAVING` and removed the extra copies with `ROW_NUMBER()`
- Handled missing rent and bedroom values with `IS NULL` and `COALESCE()`

## Analysis questions
1. Average rent by area and property type
2. Areas with more than 20 listings and an average rent above ₦1.5M
3. All listings with agent names, including unassigned listings (`LEFT JOIN`)
4. Listings that received no inquiries
5. Average days to lease by area (`DATEDIFF`)
6. Agent ranking by leased listings within each region (`RANK() OVER`)
7. Duplicate listing detection and removal
8. Monthly leases per area with month-over-month change (CTE + `LAG`)
9. Missing-value handling
10. Inquiry channel conversion rate (conditional aggregation with `COUNT(DISTINCT CASE ...)`)

**Extra:** month-over-month % change in leases per area, using a recursive CTE calendar so months with zero leases are included rather than skipped.

## SQL skills shown
Joins (inner and left), aggregation, `GROUP BY` / `HAVING`, subqueries, CTEs (including recursive), window functions (`RANK`, `ROW_NUMBER`, `LAG`), conditional aggregation, date functions, data cleaning, null handling.

## How to run
1. Install MySQL 8.0+ and MySQL Workbench.
2. Run [property_mysql.sql](property_mysql.sql) to create the `property_practice` database and load the data.
3. Run [property_sql_solutions.sql](property_sql_solutions.sql) from the top. Part 1 cleans the data, and Part 2 answers the questions.

Expected checkpoints: 609 listings before cleaning, 10 distinct areas after, 9 duplicates found, 600 listings after.

## Key findings
Results from this synthetic dataset (not real market data):
- **Price gap:** Ikoyi has the highest average rent (₦9.15M/year) and Surulere the lowest (₦1.77M), about a 5x difference.
- **Speed to lease:** Listings lease in 41 days on average. Magodo is fastest (32 days) and Surulere slowest (47 days), so the cheapest area is also the slowest to move.
- **Channel quality vs volume:** WhatsApp brings the most inquiries but converts worst (61.6%), while Referral converts best (71.3%).
- **Inquiries matter:** 40 listings received no inquiries, and none of them was leased.
- **Data quality:** Cleaning removed 9 duplicate listings and standardized inconsistent area names; 12 listings have no recorded rent.

## Files
- [property_mysql.sql](property_mysql.sql): creates the database and loads the data
- [property_sql_solutions.sql](property_sql_solutions.sql): cleaning steps and all 10 queries

## Author
Abigail Abiodun Opeyemi · [LinkedIn](https://www.linkedin.com/in/abigail-abiodun-0205903a7) · [Portfolio](https://opsy-001.github.io/Portfolio)
