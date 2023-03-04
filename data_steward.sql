--1.Pointing out data quality issues

--ORDERS TABLE

--Duplicate order_id. There are 255 duplicate orders
SELECT COUNT(*) AS duplicates
FROM (
    SELECT "ORDER_ID"        AS order_id
         , COUNT("ORDER_ID") AS duplicate_count
    FROM orders
    GROUP BY 1
    HAVING COUNT("ORDER_ID") > 1
    ORDER BY duplicate_count DESC
) dup
WHERE duplicate_count > 1;

--All duplicate order %, In total 2.78% of orders are duplicate
SELECT COUNT("ORDER_ID")                                                                       AS all_orders
     , COUNT(DISTINCT "ORDER_ID")                                                              AS distinct_orders
     , CONCAT(ROUND((1 - COUNT(DISTINCT "ORDER_ID") * 1.0 / COUNT("ORDER_ID")) * 100, 2), '%') AS duplicate_order_percentage
FROM orders;

--Missing 83 shop ID values in orders
SELECT COUNT(*) AS missing_shop_velues
FROM orders
WHERE "SHOP_ID" IS NULL
   OR LENGTH("SHOP_ID"::text) < 5;

--Where SUB is active, even though sub plan is null. There are 321 cases like this
SELECT "ORDER_ID"           AS order_id
     , "SUB_IS_ACTIVE_FLAG" AS sub_is_active
     , "SUB_PLAN"           AS sub_plan
FROM orders
WHERE "SUB_IS_ACTIVE_FLAG" = TRUE
    AND "SUB_PLAN" IS NULL
   OR "SUB_IS_ACTIVE_FLAG" = FALSE
    AND "SUB_PLAN" IS NOT NULL;

--No shipment carrier is generated even though the order has been delivered. There are 97 cases like this
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
SELECT COUNT(*) AS wrong_delivered_dt
FROM orders
WHERE "FULFILLED_DT" > "SHIPMENT_DELIVERD_DT";

--There are 247 rows in orders, where the total costs of the order was 0
SELECT COUNT(*) AS order_costs_0
FROM orders
WHERE "TOTAL_COST" = 0
   OR "TOTAL_COST" IS NULL;

--There are 52 rows in orders, where the shipping costs of the order were negative
SELECT COUNT(*) AS negative_shipping_costs
FROM orders
WHERE "TOTAL_SHIPPING" < 0;

--There are foreign characters in the address to region field
SELECT DISTINCT "ADDRESS_TO_REGION" AS address_to_region
              , CASE
                    WHEN "ADDRESS_TO_REGION" = REGEXP_REPLACE("ADDRESS_TO_REGION", '[^a-zA-Z0-9\s]+', '')
                        THEN 'matching'
                    ELSE 'not matching'
    END                             AS foreign_character_check
FROM orders;

--There are orders where the total price is higher than 500,000$, even an order of 86,909,916.16$ which couldn't be correct
--These are the orders that have this issue: 5876312, 7549260, 7209629, 7453498, 7476675, 6870251, 7074065
SELECT "ORDER_ID"                               AS order_id
     , "TOTAL_COST"                             AS cost_in_cents
     , CAST("TOTAL_COST" / 100.0 AS DEC(10, 2)) AS dollar_cost
FROM orders
ORDER BY "TOTAL_COST" DESC;




--LINE_ITEMS TABLE


--Missing order data for line items. There are 6582 rows like that.
SELECT *
FROM line_items li
     LEFT JOIN orders o
    ON li."ORDER_ID" = o."ORDER_ID"
WHERE o."ORDER_ID" IS NULL
ORDER BY li."ORDER_ID" DESC;


--Checking duplicates NO UNIQUE IDENTIFIER FOR LINE ITEM TABLE! - Table is missing a table identifier column that is unique for each row.
SELECT "ORDER_ID", "PRINT_PROVIDER_ID", "PRODUCT_BRAND", "PRODUCT_TYPE", "ITEM_STATUS", "QUANTITY", COUNT(*)
FROM line_items
GROUP BY 1, 2, 3, 4, 5, 6
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;

--Order with highest item count, count seems unrealistically high - having 15661 item rows
SELECT *
FROM line_items
WHERE "ORDER_ID" = '1750015.166';

--Checking data quality for "quantity" - no issues - 0
SELECT COUNT(*) AS zero_quantity
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

--Normal status count and similar inconsistent
SELECT COUNT(DISTINCT "ITEM_STATUS")
     , COUNT(DISTINCT REGEXP_REPLACE("ITEM_STATUS", '_', ' ', 'g')) AS distinct_statuses
FROM line_items;



--2. Propose a data quality measurement metric for a single data column and data table


--2.1. & 2.2.
-- I chose validity for single data column and completeness for a data table


--3. data column
---Validity of order id - VALID
SELECT COUNT(*)                                                                              AS total_row
     , COUNT(CASE WHEN "ORDER_ID"::text ~ '^[1-9]\d{0,6}(\.\d{1,5})?$' THEN 1 ELSE NULL END) AS valid_rows
     , CONCAT(ROUND((COUNT(CASE WHEN "ORDER_ID"::text ~ '^[1-9]\d{0,6}(\.\d{1,5})?$' THEN 1 ELSE NULL END) * 100.0 /
                     COUNT(*)), 2), '%')                                                     AS validity_percentage
FROM orders;

--Validity of merchant id - VALID
SELECT a."MERCHANT_ID", a.length
FROM (
         SELECT "MERCHANT_ID", LENGTH("MERCHANT_ID"::text) AS length
         FROM orders
     ) a
WHERE length > 7;

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


--3 data table
--Completeness metric - data from orders table

SELECT field
     , completeness_pct
     , ROW_NUMBER() OVER (ORDER BY completeness_pct ASC) AS completeness_rank
FROM (
    SELECT 'MERCHANT_ID'                         AS field
         , 100 * COUNT("MERCHANT_ID") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'ORDER_ID'                           AS field
         , 100 * COUNT(o."ORDER_ID") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'SHOP_ID'                         AS field
         , 100 * COUNT("SHOP_ID") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'ADDRESS_TO_COUNTRY'                         AS field
         , 100 * COUNT("ADDRESS_TO_COUNTRY") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'ADDRESS_TO_REGION'                         AS field
         , 100 * COUNT("ADDRESS_TO_REGION") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'ORDER_DT'                         AS field
         , 100 * COUNT("ORDER_DT") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'FULFILLED_DT'                         AS field
         , 100 * COUNT("FULFILLED_DT") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'REPRINT_FLAG'                         AS field
         , 100 * COUNT("REPRINT_FLAG") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'SALES_CHANNEL_TYPE_ID'                         AS field
         , 100 * COUNT("SALES_CHANNEL_TYPE_ID") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'TOTAL_COST'                         AS field
         , 100 * COUNT("TOTAL_COST") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'TOTAL_SHIPPING'                         AS field
         , 100 * COUNT("TOTAL_SHIPPING") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'MERCHANT_REGISTERED_DT'                         AS field
         , 100 * COUNT("MERCHANT_REGISTERED_DT") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'SUB_IS_ACTIVE_FLAG'                         AS field
         , 100 * COUNT("SUB_IS_ACTIVE_FLAG") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'SUB_PLAN'                         AS field
         , 100 * COUNT("SUB_PLAN") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'SHIPMENT_CARRIER'                         AS field
         , 100 * COUNT("SHIPMENT_CARRIER") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled')
    UNION ALL
    SELECT 'SHIPMENT_DELIVERD_DT'                         AS field
         , 100 * COUNT("SHIPMENT_DELIVERD_DT") / COUNT(*) AS completeness_pct
    FROM orders o
    LEFT JOIN line_items li
              ON
                  o."ORDER_ID" = li."ORDER_ID"
    WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
      AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
      AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure',
                                          'shipment%cancelled') -- Checking only orders that were delivered as for the ones that are not there will be null for SHIPMENT_DELIVERD_DT, ADDRESS_TO_COUNTRY, SHIPMENT_CARRIER
) AS completeness_data
WHERE UPPER(field) != 'REPRINT_FLAG'
  AND UPPER(field) != 'SUB_PLAN'; -- As sub_plan will be null for those merchants who do not have the subscription


SELECT 100 * COUNT("MERCHANT_ID") / COUNT(*)            AS merchant_id_complete_pct
     , 100 * COUNT(o."ORDER_ID") / COUNT(*)             AS order_id_complete_pct
     , 100 * COUNT("SHOP_ID") / COUNT(*)                AS shop_id_complete_pct
     , 100 * COUNT("ADDRESS_TO_COUNTRY") / COUNT(*)     AS address_to_country_complete_pct
     , 100 * COUNT("ADDRESS_TO_REGION") / COUNT(*)      AS address_to_region_complete_pct
     , 100 * COUNT("ORDER_DT") / COUNT(*)               AS order_dt_complete_pct
     , 100 * COUNT("FULFILLED_DT") / COUNT(*)           AS fulfilled_dt_complete_pct
     , 100 * COUNT("REPRINT_FLAG") / COUNT(*)           AS reprint_flag_complete_pct
     , 100 * COUNT("SALES_CHANNEL_TYPE_ID") / COUNT(*)  AS sales_channel_type_id_complete_pct
     , 100 * COUNT("TOTAL_COST") / COUNT(*)             AS total_costs_complete_pct
     , 100 * COUNT("TOTAL_SHIPPING") / COUNT(*)         AS total_shipping_complete_pct
     , 100 * COUNT("MERCHANT_REGISTERED_DT") / COUNT(*) AS merchant_registered_dt_complete_pct
     , 100 * COUNT("SUB_IS_ACTIVE_FLAG") / COUNT(*)     AS sub_is_active_flag_complete_pct
     , 100 * COUNT("SUB_PLAN") / COUNT(*)               AS sub_plan_complete_pct
     , 100 * COUNT("SHIPMENT_CARRIER") / COUNT(*)       AS shipment_carrier_complete_pct
     , 100 * COUNT("SHIPMENT_DELIVERD_DT") / COUNT(*)   AS shipment_delivered_dt_complete_pct
FROM orders o
     LEFT JOIN line_items li ON
        o."ORDER_ID" = li."ORDER_ID"
WHERE LOWER(li."ITEM_STATUS") LIKE '%deliver%'
  AND LOWER(li."ITEM_STATUS") LIKE '%shipment%'
  AND LOWER(li."ITEM_STATUS") NOT IN ('shipment%failure', 'shipment%cancelled');