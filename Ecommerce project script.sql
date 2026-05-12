CREATE DATABASE ecommerce_db;
USE ecommerce_db;

CREATE TABLE ecommerce_raw (
    Order_ID NVARCHAR(50),
    Customer_ID NVARCHAR(50),
    Date VARCHAR(50),   -- temp VARCHAR (later convert)
    Age INT,
    Gender NVARCHAR(10),
    City NVARCHAR(50),
    Product_Category NVARCHAR(100),
    Unit_Price DECIMAL(10,2),
    Quantity INT,
    Discount_Amount DECIMAL(10,2),
    Total_Amount DECIMAL(10,2),
    Payment_Method NVARCHAR(50),
    Device_Type NVARCHAR(50),
    Session_Duration_Minutes INT,
    Pages_Viewed INT,
    Is_Returning_Customer NVARCHAR(10), -- TRUE/FALSE
    Delivery_Time_Days INT,
    Customer_Rating FLOAT
);


SELECT TOP 10 * FROM ecommerce_raw;

UPDATE ecommerce_raw
SET Date = TRY_CONVERT(DATE, Date);


ALTER TABLE ecommerce_raw
ALTER COLUMN Date DATE;

##Convert Returning Customer to proper format
ALTER TABLE ecommerce_raw
ADD Is_Returning BIT;

UPDATE ecommerce_raw
SET Is_Returning =
    CASE 
        WHEN Is_Returning_Customer = 'TRUE' THEN 1
        WHEN Is_Returning_Customer = 'FALSE' THEN 0
        ELSE NULL
    END;


SELECT
    Order_ID,
    Customer_ID,
    Date,
    Age,
    Gender,
    City,
    Product_Category,
    Unit_Price,
    Quantity,
    Discount_Amount,
    Total_Amount,
    Payment_Method,
    Device_Type,
    Session_Duration_Minutes,
    Pages_Viewed,
    Is_Returning,
    Delivery_Time_Days,
    Customer_Rating
INTO ecommerce_clean
FROM ecommerce_raw;

#NULL Values Check
SELECT * 
FROM ecommerce_clean
WHERE Total_Amount IS NULL 
   OR Customer_ID IS NULL;

# Negative / Wrong Values Check
  SELECT * 
FROM ecommerce_clean
WHERE Quantity <= 0 
   OR Total_Amount <= 0;

#Data Consistency Check
SELECT *
FROM ecommerce_clean
WHERE Total_Amount != (Unit_Price * Quantity - Discount_Amount);

#Duplicate Check
SELECT Order_ID, COUNT(*)
FROM ecommerce_clean
GROUP BY Order_ID
HAVING COUNT(*) > 1;

#Standardization
UPDATE ecommerce_clean
SET Payment_Method = UPPER(Payment_Method);

UPDATE ecommerce_clean
SET City = UPPER(City);

UPDATE ecommerce_clean
SET Product_Category = UPPER(Product_Category);

ALTER TABLE ecommerce_clean
DROP COLUMN Is_Returning_Customer;


#data #modling

#FACT TABLE
CREATE TABLE fact_orders (
    Order_ID NVARCHAR(50),
    Customer_ID NVARCHAR(50),
    Product_Category NVARCHAR(100),
    Total_Amount DECIMAL(10,2),
    Quantity INT,
    Discount_Amount DECIMAL(10,2),
    Date DATE,
    Payment_Method NVARCHAR(50),
    Device_Type NVARCHAR(50)
);

#Customers
CREATE TABLE dim_customers (
    Customer_ID NVARCHAR(50) PRIMARY KEY,
    Age INT,
    Gender NVARCHAR(10),
    City NVARCHAR(50),
    Is_Returning BIT
);

#Products
CREATE TABLE dim_products (
    Product_Category NVARCHAR(100) PRIMARY KEY,
    Unit_Price DECIMAL(10,2)
);

#Date
CREATE TABLE dim_date (
    Date DATE PRIMARY KEY,
    Year INT,
    Month INT,
    Day INT
);

#Payment
CREATE TABLE dim_payment (
    Payment_Method NVARCHAR(50) PRIMARY KEY
);

#Device
CREATE TABLE dim_device (
    Device_Type NVARCHAR(50) PRIMARY KEY
);

#Data INSERT

TRUNCATE TABLE dim_customers;

INSERT INTO dim_customers
SELECT 
    Customer_ID,
    MAX(Age) AS Age,
    MAX(Gender) AS Gender,
    MAX(City) AS City,
    MAX(CAST(Is_Returning AS INT)) AS Is_Returning
FROM ecommerce_clean
GROUP BY Customer_ID;

TRUNCATE TABLE dim_products;

INSERT INTO dim_products
SELECT 
    Product_Category,
    AVG(Unit_Price) AS Unit_Price
FROM ecommerce_clean
GROUP BY Product_Category;

TRUNCATE TABLE dim_date;

INSERT INTO dim_date
SELECT DISTINCT
    Date,
    YEAR(Date) AS Year,
    MONTH(Date) AS Month,
    DAY(Date) AS Day
FROM ecommerce_clean;

TRUNCATE TABLE dim_payment;

INSERT INTO dim_payment
SELECT DISTINCT
    Payment_Method
FROM ecommerce_clean;

TRUNCATE TABLE dim_device;

INSERT INTO dim_device
SELECT DISTINCT
    Device_Type
FROM ecommerce_clean;


#FACT TABLE insert

TRUNCATE TABLE fact_orders;

INSERT INTO fact_orders
SELECT 
    Order_ID,
    Customer_ID,
    Product_Category,
    Total_Amount,
    Quantity,
    Discount_Amount,
    Date,
    Payment_Method,
    Device_Type
FROM ecommerce_clean;

#Quick Validation
SELECT COUNT(*) FROM fact_orders;
SELECT COUNT(*) FROM ecommerce_clean;

#join test
SELECT TOP 10 *
FROM fact_orders f
JOIN dim_customers c ON f.Customer_ID = c.Customer_ID;

#Qurries;
1️⃣ Total orders & total revenue

SELECT 
    COUNT(DISTINCT Order_ID) AS Total_Orders,
    SUM(Total_Amount) AS Total_Revenue
FROM fact_orders;

2️⃣ Monthly sales trend

SELECT 
    d.Year,
    d.Month,
    SUM(f.Total_Amount) AS Monthly_Sales
FROM fact_orders f
JOIN dim_date d ON f.Date = d.Date
GROUP BY d.Year, d.Month
ORDER BY d.Year, d.Month;

3️⃣ Month-over-Month (MoM) sales growth

SELECT 
    Year,
    Month,
    Monthly_Sales,
    Monthly_Sales 
      - LAG(Monthly_Sales) OVER (ORDER BY Year, Month) AS MoM_Change
FROM (
    SELECT 
        d.Year,
        d.Month,
        SUM(f.Total_Amount) AS Monthly_Sales
    FROM fact_orders f
    JOIN dim_date d ON f.Date = d.Date
    GROUP BY d.Year, d.Month
) t;

4️⃣ Top product categories by revenue

SELECT 
    Product_Category,
    SUM(Total_Amount) AS Revenue
FROM fact_orders
GROUP BY Product_Category
ORDER BY Revenue DESC;

5️⃣ Average Order Value (AOV)

SELECT 
    SUM(Total_Amount) / COUNT(DISTINCT Order_ID) AS AOV
FROM fact_orders;

6️⃣ New vs Returning customers distribution

SELECT 
    c.Is_Returning,
    COUNT(DISTINCT f.Customer_ID) AS Customers,
    SUM(f.Total_Amount) AS Total_Sales
FROM fact_orders f
JOIN dim_customers c ON f.Customer_ID = c.Customer_ID
GROUP BY c.Is_Returning;

7️⃣ Customer retention rate 

SELECT 
    CAST(SUM(CASE WHEN Is_Returning = 1 THEN 1 ELSE 0 END) AS FLOAT)
    / COUNT(*) * 100 AS Retention_Rate_Percent
FROM dim_customers;

8️⃣ Most used payment methods

SELECT 
    Payment_Method,
    COUNT(*) AS Orders
FROM fact_orders
GROUP BY Payment_Method
ORDER BY Orders DESC;

9️⃣ Top cities by sales

SELECT 
    c.City,
    SUM(f.Total_Amount) AS Total_Sales
FROM fact_orders f
JOIN dim_customers c ON f.Customer_ID = c.Customer_ID
GROUP BY c.City
ORDER BY Total_Sales DESC;

🔟 Peak sales days

SELECT 
    d.Year,
    d.Month,
    d.Day,
    SUM(f.Total_Amount) AS Sales
FROM fact_orders f
JOIN dim_date d ON f.Date = d.Date
GROUP BY d.Year, d.Month, d.Day
ORDER BY Sales DESC;