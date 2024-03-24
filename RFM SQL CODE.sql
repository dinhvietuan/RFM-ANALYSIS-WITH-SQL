
-- CLEAN DATA

-- 1. Omit customers with ID=0
DELETE FROM [dbo].[Customer_Transaction]
WHERE CustomerID = 0;

DELETE FROM [dbo].[Customer_Registered]
WHERE ID = 0;

-- 2. Exclude records lacking information on created_date or with empty created_date fields.
DELETE FROM [dbo].[Customer_Registered]
WHERE created_date IS NULL OR created_date = '';

-- 3. Remove customers with stop_date != NULL, indicating discontinued service usage.
DELETE FROM [dbo].[Customer_Registered]
WHERE stopdate IS NOT NULL;

-- 4. Filter out transactions without revenue generation, i.e., GMV equals 0.
DELETE FROM [dbo].[Customer_Transaction]
WHERE gmv = 0;


-- ANALYTICS

-- OVERVIEW

-- 1. CUSTOMER AND TRANSACTION:

-- Number of customers
SELECT COUNT(DISTINCT CustomerID) AS NumberOfCustomers
FROM [dbo].[Customer_Transaction];

-- Number of transactions
SELECT COUNT(*) AS NumberOfTransactions
FROM [dbo].[Customer_Transaction];

-- Average number of transactions per customer
SELECT 
    MIN(NumberOfTransactions) AS MinTransactions,
    MAX(NumberOfTransactions) AS MaxTransactions,
    AVG(NumberOfTransactions) AS AvgTransactions
FROM (
    SELECT 
        CustomerID,
        COUNT(*) AS NumberOfTransactions
    FROM [dbo].[Customer_Transaction]
    GROUP BY CustomerID
) AS TransactionCounts;

-- TRANSACTION MONTHLY
SELECT 
    YEAR(Purchase_Date) AS Year,
    MONTH(Purchase_Date) AS Month,
    COUNT(Transaction_ID) AS NumberOfTransactions
FROM 
    [dbo].[Customer_Transaction]
GROUP BY
    YEAR(Purchase_Date),
    MONTH(Purchase_Date)
ORDER BY
    YEAR(Purchase_Date),
    MONTH(Purchase_Date);


-- GMV

-- Calculate the average GMV (Gross Merchandise Volume)
SELECT AVG(CAST(GMV AS BIGINT)) AS AverageGMV
FROM [dbo].[Customer_Transaction];

-- TIME

-- Select first date and last date
SELECT 
    MIN(Purchase_Date) AS min_Date, 
    MAX(Purchase_Date) AS max_date
FROM 
    [dbo].[Customer_Transaction];


                                                     -- RFM MODELS

-- Drop temporary tables if they exist to avoid conflicts
IF OBJECT_ID('tempdb..#calculation') IS NOT NULL
    DROP TABLE #calculation;
IF OBJECT_ID('tempdb..#result') IS NOT NULL
    DROP TABLE #result;
IF OBJECT_ID('tempdb..#customer_segmentation') IS NOT NULL
    DROP TABLE #customer_segmentation;

-- Perform calculations and store intermediate results
SELECT 
    CustomerID,
    DATEDIFF(DAY, MAX(CAST(Purchase_Date AS DATE)), '2022-09-01') AS recency,
    ROUND(
        CAST(COUNT(DISTINCT CAST(Purchase_Date AS DATE)) AS FLOAT) / 
        CAST(DATEDIFF(YEAR, CAST(created_date AS DATE), '2022-09-01') AS FLOAT), 2
    ) AS frequency,
    SUM(gmv) / DATEDIFF(YEAR, CAST(created_date AS DATE), '2022-09-01') AS monetary,
    ROW_NUMBER() OVER (ORDER BY DATEDIFF(DAY, MAX(CAST(Purchase_Date AS DATE)), '2022-09-01')) AS rn_recency,
    ROW_NUMBER() OVER (ORDER BY ROUND(
                                        CAST(COUNT(DISTINCT CAST(Purchase_Date AS DATE)) AS FLOAT) / 
                                        CAST(DATEDIFF(YEAR, CAST(created_date AS DATE), '2022-09-01') AS FLOAT), 2
                                    )) AS rn_frequency,
    ROW_NUMBER() OVER (ORDER BY SUM(gmv)) AS rn_monetary
INTO #calculation
FROM 
    [dbo].[Customer_Transaction] T
JOIN 
    [dbo].[Customer_Registered] R ON T.CustomerID = R.ID
GROUP BY 
    CustomerID, created_date;

-- Check count of records in the calculation table
SELECT 
    COUNT(*)
FROM 
    #calculation;

-- Perform RFM grouping and mapping
SELECT 
    *,
    CASE
        WHEN recency < (SELECT recency FROM #calculation WHERE rn_recency = (SELECT CAST(COUNT(DISTINCT customerid) * 0.25 AS INT) FROM #calculation) AND recency >= (SELECT recency FROM #calculation WHERE rn_recency = 1)) THEN '1'
        WHEN recency >= (SELECT recency FROM #calculation WHERE rn_recency = (SELECT CAST(COUNT(DISTINCT customerid) * 0.25 AS INT) FROM #calculation)) AND recency < (SELECT recency FROM #calculation WHERE rn_recency = (SELECT CAST(COUNT(DISTINCT customerid) * 0.5 AS INT) FROM #calculation)) THEN '2'
        WHEN recency >= (SELECT recency FROM #calculation WHERE rn_recency = (SELECT CAST(COUNT(DISTINCT customerid) * 0.5 AS INT) FROM #calculation)) AND recency < (SELECT recency FROM #calculation WHERE rn_recency = (SELECT CAST(COUNT(DISTINCT customerid) * 0.75 AS INT) FROM #calculation)) THEN '3'
        ELSE '4'
    END AS R,
    CASE
        WHEN frequency < (SELECT frequency FROM #calculation WHERE rn_frequency = (SELECT CAST(COUNT(DISTINCT customerid) * 0.25 AS INT) FROM #calculation)) AND frequency >= (SELECT frequency FROM #calculation WHERE rn_frequency = 1) THEN '1'
        WHEN frequency >= (SELECT frequency FROM #calculation WHERE rn_frequency = (SELECT CAST(COUNT(DISTINCT customerid) * 0.25 AS INT) FROM #calculation)) AND frequency < (SELECT frequency FROM #calculation WHERE rn_frequency = (SELECT CAST(COUNT(DISTINCT customerid) * 0.5 AS INT) FROM #calculation)) THEN '2'
        WHEN frequency >= (SELECT frequency FROM #calculation WHERE rn_frequency = (SELECT CAST(COUNT(DISTINCT customerid) * 0.5 AS INT) FROM #calculation)) AND frequency < (SELECT frequency FROM #calculation WHERE rn_frequency = (SELECT CAST(COUNT(DISTINCT customerid) * 0.75 AS INT) FROM #calculation)) THEN '3'
        ELSE '4'
    END AS F,
    CASE
        WHEN monetary < (SELECT monetary FROM #calculation WHERE rn_monetary = (SELECT CAST(COUNT(DISTINCT customerid) * 0.25 AS INT) FROM #calculation)) AND monetary >= (SELECT monetary FROM #calculation WHERE rn_monetary = 1) THEN '1'
        WHEN monetary >= (SELECT monetary FROM #calculation WHERE rn_monetary = (SELECT CAST(COUNT(DISTINCT customerid) * 0.25 AS INT) FROM #calculation)) AND monetary < (SELECT monetary FROM #calculation WHERE rn_monetary = (SELECT CAST(COUNT(DISTINCT customerid) * 0.5 AS INT) FROM #calculation)) THEN '2'
        WHEN monetary >= (SELECT monetary FROM #calculation WHERE rn_monetary = (SELECT CAST(COUNT(DISTINCT customerid) * 0.5 AS INT) FROM #calculation)) AND monetary < (SELECT monetary FROM #calculation WHERE rn_monetary = (SELECT CAST(COUNT(DISTINCT customerid) * 0.75 AS INT) FROM #calculation)) THEN '3'
        ELSE '4'
    END AS M
INTO #result 
FROM 
    #calculation;

-- Display the results with concatenated RFM group
SELECT 
    *,
    CONCAT(R, F, M) AS [group]
INTO 
    #customer_segmentation
FROM 
    #result;

-- Mapping data to customer segments
SELECT 
    CONCAT(R, F, M) AS [group],
    COUNT(*) AS total_client,
    CASE
        WHEN CONCAT(R, F, M) IN ('444', '443', '434', '344') THEN 'champions'
        WHEN CONCAT(R, F, M) IN ('442', '441', '432', '431', '433', '343', '342', '341') THEN 'loyal customer'
        WHEN CONCAT(R, F, M) IN ('424', '423', '324', '323', '413', '414', '343', '334') THEN 'potential loyalist'
        WHEN CONCAT(R, F, M) IN ('333', '332', '331', '313') THEN 'recent customer'
        WHEN CONCAT(R, F, M) IN ('422', '421', '412', '411', '311', '321', '312', '322', '314') THEN 'promising customers'
        WHEN CONCAT(R, F, M) IN ('142', '231', '232', '241') THEN 'customer needing attention'
        WHEN CONCAT(R, F, M) IN ('244', '234', '243', '233', '224', '144', '143', '133') THEN 'new customer'
        WHEN CONCAT(R, F, M) IN ('131', '132', '141', '242') THEN 'at risk customer'
        WHEN CONCAT(R, F, M) IN ('214', '213', '134') THEN 'cant lose them'
        WHEN CONCAT(R, F, M) IN ('223', '221', '222', '211', '212', '124') THEN 'hibernating'
        WHEN CONCAT(R, F, M) IN ('111', '112', '113', '114', '121', '122', '123', '222') THEN 'lost'
        ELSE 'other'
    END AS customer_type
INTO 
    #customer_segmentation
FROM 
    #result
GROUP BY 
    CONCAT(R, F, M)
ORDER BY 
    total_client;

-- Display final customer segmentation
SELECT 
    *
FROM 
    #customer_segmentation;



-- CREATE TABLE CUSTOMER_SEGMENTATION
SELECT * INTO Customer_Segmentation FROM #customer_segmentation;

-- Calculate total customers per customer type
SELECT 
    SUM(total_client) AS TOTAL_CUSTOMER, 
    customer_type
FROM 
    Customer_Segmentation
GROUP BY 
    customer_type
ORDER BY 
    SUM(total_client) DESC;

-- Calculate Quartile R, F, và M
WITH CTE AS (
    SELECT
        [recency],
        ROUND([frequency] * 12, 4) AS frequency_scaled, -- Multiply Frequency by 12
        [monetary],
        ROW_NUMBER() OVER (ORDER BY [recency]) AS R_RowNum,
        ROW_NUMBER() OVER (ORDER BY [frequency]) AS F_RowNum,
        ROW_NUMBER() OVER (ORDER BY [monetary]) AS M_RowNum,
        COUNT(*) OVER () AS TotalRows
    FROM
        #calculation
)
SELECT
    (SELECT [recency] FROM CTE WHERE R_RowNum = CEILING(TotalRows * 0.25)) AS R_25th_Percentile,
    (SELECT [recency] FROM CTE WHERE R_RowNum = CEILING(TotalRows * 0.50)) AS R_50th_Percentile,
    (SELECT [recency] FROM CTE WHERE R_RowNum = CEILING(TotalRows * 0.75)) AS R_75th_Percentile,
    (SELECT [frequency_scaled] FROM CTE WHERE F_RowNum = CEILING(TotalRows * 0.25)) AS F_25th_Percentile, -- Use frequency_scaled instead of frequency
    (SELECT [frequency_scaled] FROM CTE WHERE F_RowNum = CEILING(TotalRows * 0.50)) AS F_50th_Percentile,
    (SELECT [frequency_scaled] FROM CTE WHERE F_RowNum = CEILING(TotalRows * 0.75)) AS F_75th_Percentile,
    (SELECT [monetary] FROM CTE WHERE M_RowNum = CEILING(TotalRows * 0.25)) AS M_25th_Percentile,
    (SELECT [monetary] FROM CTE WHERE M_RowNum = CEILING(TotalRows * 0.50)) AS M_50th_Percentile,
    (SELECT [monetary] FROM CTE WHERE M_RowNum = CEILING(TotalRows * 0.75)) AS M_75th_Percentile;











