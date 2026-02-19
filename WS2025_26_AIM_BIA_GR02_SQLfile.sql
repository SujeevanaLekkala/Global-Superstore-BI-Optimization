-- **********************************************************************************
-- 1. Create Schema db_global_superstore_dev.
-- ----------------------------------------------------------------------------------
CREATE DATABASE db_global_superstore_dev; -- CREATE SCHEMA command has to be run only once!

DROP TABLE IF EXISTS Fact_Sales;
DROP TABLE IF EXISTS DIM_DATE;
DROP TABLE IF EXISTS DIM_PRODUCT;
DROP TABLE IF EXISTS DIM_GEOGRAPHY;
DROP TABLE IF EXISTS DIM_CUSTOMER;
DROP TABLE IF EXISTS psa_superstore_dev;

-- ----------------------------------------------------------------------------------
-- Each time you start working on 'Global Superstore' you have to issue USE SCHEMA
-- command to tell the DBMS that you want to work with database objects belonging 
-- to this schema.
-- ----------------------------------------------------------------------------------
USE db_global_superstore_dev;

-- **********************************************************************************
-- 2. Create your first table. This table is used for uploading csv-file (2. step).
-- ----------------------------------------------------------------------------------
CREATE TABLE psa_superstore_dev (
    -- Primary Keys / Identifiers
    RowID INT NOT NULL,
    OrderID VARCHAR(25) NOT NULL,
    ProductID VARCHAR(25) NOT NULL,

    -- Date and Time Information (use VARCHAR for flexibility during import)
    OrderDate VARCHAR(25) DEFAULT NULL,
    ShipDate VARCHAR(25) DEFAULT NULL,
    Year VARCHAR(10) DEFAULT NULL,       
    Weeknum VARCHAR(10) DEFAULT NULL,

    -- Customer and Segment
    CustomerID VARCHAR(25) DEFAULT NULL,
    CustomerName VARCHAR(100) DEFAULT NULL,
    Segment VARCHAR(25) DEFAULT NULL,

    -- Product Information
    Category VARCHAR(50) DEFAULT NULL,
    SubCategory VARCHAR(50) DEFAULT NULL,
    ProductName VARCHAR(255) DEFAULT NULL,

    -- Geography and Shipping
    Country VARCHAR(50) DEFAULT NULL,
    City VARCHAR(50) DEFAULT NULL,
    State VARCHAR(50) DEFAULT NULL,
    Region VARCHAR(50) DEFAULT NULL,
    Market VARCHAR(100) DEFAULT NULL,
    Market2 VARCHAR(100) DEFAULT NULL,   
    ShipMode VARCHAR(25) DEFAULT NULL,
    OrderPriority VARCHAR(25) DEFAULT NULL,

    -- Measures (Facts - use VARCHAR for flexibility, cast later)
    Sales VARCHAR(25) DEFAULT NULL,
    Quantity VARCHAR(25) DEFAULT NULL,
    Discount VARCHAR(25) DEFAULT NULL,
    Profit VARCHAR(25) DEFAULT NULL,
    ShippingCost VARCHAR(25) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- If you want to drop the table issue the drop table statement as follows:
-- DROP TABLE `psa_superstore_dev`;

-- ----------------------------------------------------------------------------------
-- 3. Now upload data using Load command. To make sure your csv-file can be found by
-- the system check where the file is stored on your computer. 
-- If you run into errors and file cannot be found, check secure_file_priv setting as
-- explained in PDF document "Working with MySQL".
-- If secure_file_priv is set to "" data file should be stored in this folder:
-- C:\ProgramData\MySQL\MySQL Server 8.0\Data\psa_superstore_dev
-- Be aware of the folders name after \Data\. Its the same name as your schemas name!
-- ----------------------------------------------------------------------------------
-- SELECT LOAD_FILE('C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/cleaned_dataset_superstore.csv');
-- SHOW VARIABLES LIKE 'secure_file_priv';

LOAD DATA INFILE "C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/cleaned_dataset_superstore.csv"
INTO TABLE psa_superstore_dev
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(
  Category,
  City,
  Country,
  CustomerID,
  CustomerName,
  Discount,
  Market,
  OrderDate,
  OrderID,
  OrderPriority,
  ProductID,
  ProductName,
  Profit,
  Quantity,
  Region,
  RowID,
  Sales,
  Segment,
  ShipDate,
  ShipMode,
  ShippingCost,
  State,
  SubCategory,
  Year,
  Market2,
  Weeknum
);

ALTER TABLE psa_superstore_dev ADD CONSTRAINT PK_psa_superstore PRIMARY KEY (RowID);

-- ----------------------------------------------------------------------------------
-- 4. Check whether upload of data was successfull.
-- Validate PSA load
SELECT COUNT(*) FROM psa_superstore_dev;
SELECT * FROM psa_superstore_dev LIMIT 10;
-- ----------------------------------------------------------------------------------


-- **********************************************************************************
-- 5. Build dimensional model (DIM & FACT tables) from staging data
-- ----------------------------------------------------------------------------------- 
-- CUSTOMER Dimension
DROP TABLE IF EXISTS DIM_CUSTOMER;
-- -----------------------------------------------------------------------------------
CREATE TABLE DIM_CUSTOMER (
    CustomerKey INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    CustomerID VARCHAR(10) NOT NULL UNIQUE, -- Business Key
    CustomerName VARCHAR(100),
    Segment VARCHAR(25)
) ENGINE=InnoDB;

INSERT INTO DIM_CUSTOMER (CustomerID, CustomerName, Segment)
SELECT DISTINCT
    S.CustomerID,
    S.CustomerName,
    S.Segment
FROM psa_superstore_dev S
-- Use ON DUPLICATE KEY UPDATE for safety, even on the initial load
ON DUPLICATE KEY UPDATE
    CustomerName = VALUES(CustomerName),
    Segment = VALUES(Segment);

-- ----------------------------------------------------------------------------------- 
-- GEOGRAPHY Dimension
DROP TABLE IF EXISTS DIM_GEOGRAPHY;
-- -----------------------------------------------------------------------------------
CREATE TABLE DIM_GEOGRAPHY (
    GeoKey INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    Country VARCHAR(50),
    Region VARCHAR(50),
    State VARCHAR(50),
    City VARCHAR(50),
    Market VARCHAR(100),    
    Market2 VARCHAR(100),   
    UNIQUE KEY uk_Geography (Country, Region, State, City)
);

INSERT INTO DIM_GEOGRAPHY (Country, Region, State, City, Market, Market2)
SELECT DISTINCT
    S.Country,
    S.Region,
    S.State,
    S.City,
    S.Market,       
    S.Market2       
FROM psa_superstore_dev S
ON DUPLICATE KEY UPDATE
    Market = S.Market,      -- Using S (the alias for the SELECT source) instead of VALUES()
    Market2 = S.Market2;    -- Using S instead of VALUES()

-- ----------------------------------------------------------------------------------- 
-- PRODUCT Dimension
DROP TABLE IF EXISTS DIM_PRODUCT;
-- -----------------------------------------------------------------------------------
CREATE TABLE DIM_PRODUCT (
    ProductKey INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    ProductID VARCHAR(20) NOT NULL UNIQUE, -- Business Key
    ProductName VARCHAR(150),
    Category VARCHAR(50),
    SubCategory VARCHAR(50)
);

-- B. INSERT ETL
INSERT INTO DIM_PRODUCT (ProductID, ProductName, Category, SubCategory)
SELECT DISTINCT
    S.ProductID,
    S.ProductName,
    S.Category,
    S.SubCategory
FROM psa_superstore_dev S
ON DUPLICATE KEY UPDATE
    ProductName = S.ProductName,
    Category = S.Category,
    SubCategory = S.SubCategory;
    
-- ----------------------------------------------------------------------------------- 
-- DATE Dimension
DROP TABLE IF EXISTS DIM_DATE;
-- Increase the recursion limit to handle more than 1000 days (approx 4 years = 1460+ days)
SET SESSION cte_max_recursion_depth = 10000;
-- -----------------------------------------------------------------------------------
CREATE TABLE DIM_DATE (
    DateKey INT PRIMARY KEY,          -- YYYYMMDD
    FullDate DATE NOT NULL UNIQUE,    -- continuous dates
    Year SMALLINT NOT NULL,
    Month TINYINT NOT NULL,
    MonthName VARCHAR(10) NOT NULL,
    Quarter CHAR(2) NOT NULL,
    YearMonth CHAR(7) NOT NULL,       -- e.g. 2014-07
    StartOfMonth DATE NOT NULL
) ENGINE=InnoDB;

-- 4. Insert data using recursive CTE
INSERT INTO DIM_DATE (DateKey, FullDate, Year, Month, MonthName, Quarter, YearMonth, StartOfMonth)
WITH RECURSIVE bounds AS (
    SELECT 
        MIN(dt) AS min_dt, 
        MAX(dt) AS max_dt
    FROM (
        -- Combine OrderDate and ShipDate to find the absolute date range
        SELECT DATE(STR_TO_DATE(OrderDate, '%d/%m/%Y %H:%i')) AS dt
        FROM psa_superstore_dev 
        WHERE OrderDate IS NOT NULL
        UNION ALL
        SELECT DATE(STR_TO_DATE(ShipDate, '%d/%m/%Y %H:%i')) AS dt
        FROM psa_superstore_dev 
        WHERE ShipDate IS NOT NULL
    ) x
),
date_series AS (
    -- Anchor member: start from the minimum date
    SELECT min_dt AS d, max_dt FROM bounds
    UNION ALL
    -- Recursive member: increment by 1 day until reaching max_dt
    SELECT DATE_ADD(d, INTERVAL 1 DAY), max_dt
    FROM date_series
    WHERE d < max_dt
)
SELECT 
    CAST(DATE_FORMAT(d, '%Y%m%d') AS UNSIGNED) AS DateKey,
    d AS FullDate,
    YEAR(d) AS Year,
    MONTH(d) AS Month,
    MONTHNAME(d) AS MonthName,
    CONCAT('Q', QUARTER(d)) AS Quarter,
    DATE_FORMAT(d, '%Y-%m') AS YearMonth,
    -- Get the first day of the month
    DATE_FORMAT(d, '%Y-%m-01') AS StartOfMonth
FROM date_series;

-- ----------------------------------------------------------------------------------- 
-- Fact_Sales
DROP TABLE IF EXISTS Fact_Sales;
-- -----------------------------------------------------------------------------------
CREATE TABLE Fact_Sales (
    SalesKey INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    -- Foreign Keys
    -- DateKey INT NOT NULL,
    OrderDateKey INT NOT NULL,     -- UPDATE (22.12.25): previously DateKey
    ShipDateKey INT NOT NULL,      -- UPDATE (22.12.25): 2nd DateKey (shipping)
    
    CustomerKey INT NOT NULL,
    ProductKey INT NOT NULL,
    GeoKey INT NOT NULL,
    
    -- Degenerate Dimensions
    OrderID VARCHAR(25) NOT NULL,
    ShipMode VARCHAR(25),
    OrderPriority VARCHAR(25), 
    
    -- Measures (Facts)
    Sales DECIMAL(10, 2) NOT NULL,
    Quantity INT NOT NULL,
    Discount DECIMAL(5, 2) NOT NULL,
    Profit DECIMAL(10, 2) NOT NULL,
    ShippingCost DECIMAL(10, 2) NOT NULL,

    -- Define Foreign Key Constraints
    -- FOREIGN KEY (DateKey) REFERENCES DIM_DATE(DateKey),     -- UPDATE(22.12.25)
    FOREIGN KEY (OrderDateKey) REFERENCES DIM_DATE(DateKey),   -- UPDATE(22.12.25)
    FOREIGN KEY (ShipDateKey)  REFERENCES DIM_DATE(DateKey),   -- UPDATE(22.12.25)
    FOREIGN KEY (CustomerKey) REFERENCES DIM_CUSTOMER(CustomerKey),
    FOREIGN KEY (ProductKey) REFERENCES DIM_PRODUCT(ProductKey),
    FOREIGN KEY (GeoKey) REFERENCES DIM_GEOGRAPHY(GeoKey)
);


INSERT INTO Fact_Sales (
    -- DateKey,   -- UPDATE(22.12.25)
    OrderDateKey, -- UPDATE(22.12.25)
    ShipDateKey,  -- UPDATE(22.12.25)
    CustomerKey, 
    ProductKey, 
    GeoKey,
    OrderID, 
    ShipMode, 
    OrderPriority,
    Sales, 
    Quantity, 
    Discount, 
    Profit, 
    ShippingCost
)
SELECT
    -- UPDATE: OrderDateKey
    CAST(DATE_FORMAT(DATE(STR_TO_DATE(S.OrderDate, '%d/%m/%Y %H:%i')), '%Y%m%d') AS UNSIGNED) AS OrderDateKey,

    -- UPDATE: ShipDateKey (nullable)
    CASE
        WHEN S.ShipDate IS NULL OR S.ShipDate = '' THEN NULL
        ELSE CAST(DATE_FORMAT(DATE(STR_TO_DATE(S.ShipDate, '%d/%m/%Y %H:%i')), '%Y%m%d') AS UNSIGNED)
    END AS ShipDateKey,
    
    -- 2. Dimension Key Lookups (JOINs)
    C.CustomerKey,
    P.ProductKey,
    G.GeoKey,

    -- 3. Degenerate Dimensions
    S.OrderID,
    S.ShipMode,
    S.OrderPriority,

    -- 4. Measures (CLEANING AND CASTING)
-- Measures (FIX: jangan hapus '.' karena itu desimal!)
CAST(S.Sales AS DECIMAL(18, 6)) AS Sales,
CAST(S.Quantity AS SIGNED) AS Quantity,
CAST(S.Discount AS DECIMAL(18, 6)) AS Discount,
CAST(S.Profit AS DECIMAL(18, 6)) AS Profit,
CAST(S.ShippingCost AS DECIMAL(18, 6)) AS ShippingCost

FROM
    psa_superstore_dev S
INNER JOIN DIM_CUSTOMER C ON S.CustomerID = C.CustomerID
INNER JOIN DIM_PRODUCT P ON S.ProductID = P.ProductID
INNER JOIN DIM_GEOGRAPHY G ON
    S.Country = G.Country AND S.Region = G.Region AND
    S.State = G.State AND S.City = G.City
WHERE C.CustomerKey IS NOT NULL AND P.ProductKey IS NOT NULL AND G.GeoKey IS NOT NULL;


---------------------------------- TEST -----------------------------
# 1. OrderDate and ShipDate
-- Duration OrderDate and ShipDate
SELECT
  MIN(STR_TO_DATE(OrderDate,'%d/%m/%Y %H:%i')) AS min_order,
  MAX(STR_TO_DATE(OrderDate,'%d/%m/%Y %H:%i')) AS max_order,
  MIN(STR_TO_DATE(ShipDate,'%d/%m/%Y %H:%i'))  AS min_ship,
  MAX(STR_TO_DATE(ShipDate,'%d/%m/%Y %H:%i'))  AS max_ship
FROM psa_superstore_dev;


SELECT
    MIN(FullDate) AS min_date,
    MAX(FullDate) AS max_date,
    DATEDIFF(MAX(FullDate), MIN(FullDate)) + 1 AS total_days,
    COUNT(*) AS row_count
FROM DIM_DATE;

# 2. Sales and Profit
-- Test Sales Year
SELECT
    d.Year,
    SUM(f.Sales) AS Sales
FROM Fact_Sales f
JOIN DIM_DATE d
    ON f.OrderDateKey = d.DateKey
GROUP BY d.Year
ORDER BY d.Year;

SELECT
  SUM(Sales) AS total_sales,
  SUM(Profit) AS total_profit,
  ROUND(SUM(Profit)/SUM(Sales), 4) AS margin
FROM fact_sales;

-- Check SUM Sales and Profit
SELECT Sales, Profit
FROM psa_superstore_dev
LIMIT 20;

-- Check Total Sales and Total Profit
SELECT
  SUM(Sales) AS total_sales,
  SUM(Profit) AS total_profit,
  ROUND(SUM(Profit)/SUM(Sales), 4) AS margin
FROM psa_superstore_dev;

SELECT
    Profit AS raw_profit,
    CAST(Profit AS DECIMAL(10,2)) AS safe_cast,
    CAST(REPLACE(Profit, '.', '') AS DECIMAL(10,2)) AS broken_cast
FROM psa_superstore_dev
WHERE Profit LIKE '-%'
LIMIT 20;

SELECT
  fs.ShipMode,
  COUNT(DISTINCT fs.OrderID) AS Orders,
  AVG(DATEDIFF(dShip.FullDate, dOrder.FullDate)) AS AvgShipDays,
  AVG(
    CASE
      WHEN fs.ShipMode='Same Day'       AND DATEDIFF(dShip.FullDate, dOrder.FullDate) <= 1 THEN 1
      WHEN fs.ShipMode='First Class'    AND DATEDIFF(dShip.FullDate, dOrder.FullDate) <= 2 THEN 1
      WHEN fs.ShipMode='Second Class'   AND DATEDIFF(dShip.FullDate, dOrder.FullDate) <= 3 THEN 1
      WHEN fs.ShipMode='Standard Class' AND DATEDIFF(dShip.FullDate, dOrder.FullDate) <= 4 THEN 1
      ELSE 0
    END
  ) AS OnTimeRate
FROM Fact_Sales fs
JOIN DIM_DATE dOrder ON dOrder.DateKey = fs.OrderDateKey
JOIN DIM_DATE dShip  ON dShip.DateKey  = fs.ShipDateKey
GROUP BY fs.ShipMode;










