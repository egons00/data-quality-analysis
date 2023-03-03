--1.Pointing out data quality issues

--ORDERS TABLE

--Duplicate order_id
SELECT "ORDER_ID"
     , COUNT("ORDER_ID") AS duplicate_count
FROM orders
GROUP BY 1
HAVING COUNT("ORDER_ID") > 1
ORDER BY duplicate_count DESC

--All duplicate order %
SELECT COUNT("ORDER_ID")                                                                       AS all_orders
     , COUNT(DISTINCT "ORDER_ID")                                                              AS distinct_orders
     , CONCAT(ROUND((1 - COUNT(DISTINCT "ORDER_ID") * 1.0 / COUNT("ORDER_ID")) * 100, 2), '%') AS duplicate_order_percentage
FROM orders;

--Missing shop ID values in orders
SELECT COUNT(*)
FROM orders
WHERE "SHOP_ID" IS NULL
   OR LENGTH("SHOP_ID"::text) < 5;

--Where SUB is active, even though sub plan is null
SELECT *
FROM orders
WHERE "SUB_IS_ACTIVE_FLAG" = TRUE
  AND "SUB_PLAN" IS NULL;

--No shipment carrier is generated even though the order has been delivered
SELECT *
FROM orders o
     LEFT JOIN line_items li
    ON o."ORDER_ID" = li."ORDER_ID"
WHERE o."SHIPMENT_CARRIER" IS NULL
  AND LOWER(li."ITEM_STATUS") LIKE '%delivered%';

--Also inconsistencies for shipment_carrier fields e.g. "UPS" and "ups_"
SELECT DISTINCT "SHIPMENT_CARRIER", COUNT(*)
FROM orders
GROUP BY 1;

SELECT DISTINCT "SHIPMENT_CARRIER"
FROM orders
WHERE (CASE WHEN REGEXP_REPLACE(LOWER("SHIPMENT_CARRIER"), '[_-]', ' ', 'g') LIKE '%ups%' THEN 1 ELSE 0 END) = 1;

--There are 173 rows in orders where the shipment_delivered_dt is smaller than the fulfilled or ordered date
SELECT COUNT(*)
FROM orders
WHERE "FULFILLED_DT" > "SHIPMENT_DELIVERD_DT";

--There are 247 rows inorders where the total costs of the order was 0
SELECT COUNT(*)
FROM orders
WHERE "TOTAL_COST" = 0
   OR "TOTAL_COST" IS NULL;

--There are 52 rows in orders where the shipping costs of the order were negative
SELECT COUNT(*)
FROM orders
WHERE "TOTAL_SHIPPING" < 0;



--LINE_ITEMS TABLE


--Missing order data for line items
SELECT *
FROM line_items li
     LEFT JOIN orders o
    ON li."ORDER_ID" = o."ORDER_ID"
WHERE o."ORDER_ID" IS NULL
ORDER BY li."ORDER_ID" DESC;


--Checking duplicates NO UNIQUE IDENTIFIER FOR LINE ITEM TABLE
SELECT "ORDER_ID", "PRINT_PROVIDER_ID", "PRODUCT_BRAND", "PRODUCT_TYPE", "ITEM_STATUS", "QUANTITY", COUNT(*)
FROM line_items
GROUP BY 1, 2, 3, 4, 5, 6
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;

--Order with highest item count, count seems unrealisticly high
SELECT *
FROM line_items
WHERE "ORDER_ID" = '1750015.166';

--Checking data quality for "quantity" - no issues
SELECT COUNT(*)
FROM line_items
WHERE "QUANTITY" = 0;

--There is inconsistencies for item status. e.g "on hold" and "on-hold"
SELECT DISTINCT "ITEM_STATUS"
FROM line_items;

SELECT "ITEM_STATUS", COUNT(*)
FROM line_items
GROUP BY 1
ORDER BY 1 DESC;

SELECT regexp_replace("ITEM_STATUS", '_', ' ') AS modified_status, COUNT(*) AS count
FROM line_items
GROUP BY modified_status
HAVING COUNT(*) > 1
ORDER BY count DESC;

SELECT "ORDER_ID", COUNT(DISTINCT "ITEM_STATUS") AS distinct_values
FROM line_items
GROUP BY 1
HAVING COUNT(DISTINCT "ITEM_STATUS") > 1
ORDER BY distinct_values DESC;

--normal status count and similar inconsistent
SELECT COUNT(DISTINCT "ITEM_STATUS")
     , COUNT(DISTINCT REGEXP_REPLACE("ITEM_STATUS", '_', ' ', 'g')) AS distinct_statuses
FROM line_items;



--2. Propose a data quality meassurement metric for a single data column and data table


--2.1. & 2.2.
-- I chose validity for single data column and completeness for a data table


--3. data column
---Validity of order id - VALID
SELECT COUNT(*) AS total_row,
       COUNT(CASE WHEN "ORDER_ID"::text ~ '^[1-9]\d{0,6}(\.\d{1,5})?$' THEN 1 ELSE NULL END) AS valid_rows,
       CONCAT(ROUND((COUNT(CASE WHEN "ORDER_ID"::text ~ '^[1-9]\d{0,6}(\.\d{1,5})?$' THEN 1 ELSE NULL END)*100.0/COUNT(*)), 2), '%') AS validity_percentage
FROM orders;

--Validity of merchant id - VALID
select a."MERCHANT_ID", a.length from(
SELECT "MERCHANT_ID", length("MERCHANT_ID"::text) as length
FROM orders
    ) a
where length > 7;

-- Check all date type validity in orders - INVALID
SELECT COUNT(CASE
                 WHEN "ORDER_DT"::text !~ '^\d{4}-(0[1-9]|1[0-2])-\d{2} \d{2}:\d{2}:\d{2}$' THEN 1
                 ELSE NULL END)                                               AS not_valid_rows_ORDER_DT
     , COUNT(CASE WHEN "ORDER_DT" IS NULL THEN 1 ELSE NULL END)               AS null_rows_ORDER_DT
     , COUNT(CASE
                 WHEN "FULFILLED_DT"::text !~ '^\d{4}-(0[1-9]|1[0-2])-\d{2} \d{2}:\d{2}:\d{2}$' THEN 1
                 ELSE NULL END)                                               AS not_valid_rows_FULFILLED_DT
     , COUNT(CASE WHEN "FULFILLED_DT" IS NULL THEN 1 ELSE NULL END)           AS null_rows_FULFILLED_DT
     , COUNT(CASE
                 WHEN "MERCHANT_REGISTERED_DT"::text !~ '^\d{4}-(0[1-9]|1[0-2])-\d{2} \d{2}:\d{2}:\d{2}$' THEN 1
                 ELSE NULL END)                                               AS not_valid_rows_MERCHANT_REGISTERED_DT
     , COUNT(CASE WHEN "MERCHANT_REGISTERED_DT" IS NULL THEN 1 ELSE NULL END) AS null_rows_MERCHANT_REGISTERED_DT
     , COUNT(CASE
                 WHEN "SHIPMENT_DELIVERD_DT"::text !~ '^\d{4}-(0[1-9]|1[0-2])-\d{2} \d{2}:\d{2}:\d{2}$' THEN 1
                 ELSE NULL END)                                               AS not_valid_rows_SHIPMENT_DELIVERD_DT
     , COUNT(CASE WHEN "SHIPMENT_DELIVERD_DT" IS NULL THEN 1 ELSE NULL END)   AS null_rows_SHIPMENT_DELIVERD_DT
FROM orders;


--2.2 data table
--Completeness metric- data line_item table

SELECT column_name
     , completeness_pct
     , ROW_NUMBER() OVER (ORDER BY completeness_pct ASC) AS completeness_rank
FROM (
         SELECT 'MERCHANT_ID'                         AS column_name
              , 100 * COUNT("MERCHANT_ID") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'ORDER_ID'                         AS column_name
              , 100 * COUNT("ORDER_ID") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'SHOP_ID'                         AS column_name
              , 100 * COUNT("SHOP_ID") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'ADDRESS_TO_COUNTRY'                         AS column_name
              , 100 * COUNT("ADDRESS_TO_COUNTRY") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'ADDRESS_TO_REGION'                         AS column_name
              , 100 * COUNT("ADDRESS_TO_REGION") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'ORDER_DT'                         AS column_name
              , 100 * COUNT("ORDER_DT") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'FULFILLED_DT'                         AS column_name
              , 100 * COUNT("FULFILLED_DT") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'REPRINT_FLAG'                         AS column_name
              , 100 * COUNT("REPRINT_FLAG") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'SALES_CHANNEL_TYPE_ID'                         AS column_name
              , 100 * COUNT("SALES_CHANNEL_TYPE_ID") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'TOTAL_COST'                         AS column_name
              , 100 * COUNT("TOTAL_COST") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'TOTAL_SHIPPING'                         AS column_name
              , 100 * COUNT("TOTAL_SHIPPING") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'MERCHANT_REGISTERED_DT'                         AS column_name
              , 100 * COUNT("MERCHANT_REGISTERED_DT") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'SUB_IS_ACTIVE_FLAG'                         AS column_name
              , 100 * COUNT("SUB_IS_ACTIVE_FLAG") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'SUB_PLAN'                         AS column_name
              , 100 * COUNT("SUB_PLAN") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'SHIPMENT_CARRIER'                         AS column_name
              , 100 * COUNT("SHIPMENT_CARRIER") / COUNT(*) AS completeness_pct
         FROM orders
         UNION ALL
         SELECT 'SHIPMENT_DELIVERD_DT'                         AS column_name
              , 100 * COUNT("SHIPMENT_DELIVERD_DT") / COUNT(*) AS completeness_pct
         FROM orders
     ) AS completeness_data
WHERE column_name != 'REPRINT_FLAG';


SELECT 100 * COUNT("MERCHANT_ID") / COUNT(*)            AS order_id_complete_pct
     , 100 * COUNT("ORDER_ID") / COUNT(*)               AS print_provider_id_complete_pct
     , 100 * COUNT("SHOP_ID") / COUNT(*)                AS product_brand_complete_pct
     , 100 * COUNT("ADDRESS_TO_COUNTRY") / COUNT(*)     AS product_type_complete_pct
     , 100 * COUNT("ADDRESS_TO_REGION") / COUNT(*)      AS item_status_complete_pct
     , 100 * COUNT("ORDER_DT") / COUNT(*)               AS quantity_complete_pct
     , 100 * COUNT("FULFILLED_DT") / COUNT(*)           AS order_id_complete_pct
     , 100 * COUNT("REPRINT_FLAG") / COUNT(*)           AS print_provider_id_complete_pct
     , 100 * COUNT("SALES_CHANNEL_TYPE_ID") / COUNT(*)  AS product_brand_complete_pct
     , 100 * COUNT("TOTAL_COST") / COUNT(*)             AS product_type_complete_pct
     , 100 * COUNT("TOTAL_SHIPPING") / COUNT(*)         AS item_status_complete_pct
     , 100 * COUNT("MERCHANT_REGISTERED_DT") / COUNT(*) AS quantity_complete_pct
     , 100 * COUNT("SUB_IS_ACTIVE_FLAG") / COUNT(*)     AS product_brand_complete_pct
     , 100 * COUNT("SUB_PLAN") / COUNT(*)               AS product_type_complete_pct
     , 100 * COUNT("SHIPMENT_CARRIER") / COUNT(*)       AS item_status_complete_pct
     , 100 * COUNT("SHIPMENT_DELIVERD_DT") / COUNT(*)   AS quantity_complete_pct
FROM orders;