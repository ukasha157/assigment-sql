/* ============================================================
   BikeStores — Sales & Inventory Intelligence Layer
   Junior Data Engineer Assignment
   Written for SQL Server (T-SQL)
   ============================================================ */


/* ============================================================
   TASK 1 — Sales Detail Dataset (one row per order item)
   ============================================================ */
SELECT
    o.order_id,
    o.order_date,
    c.first_name + ' ' + c.last_name          AS customer_name,
    st.store_name,
    s.first_name + ' ' + s.last_name          AS staff_name,
    p.product_name,
    cat.category_name,
    b.brand_name,
    oi.quantity,
    oi.list_price,
    oi.discount,
    (oi.quantity * oi.list_price * (1 - oi.discount)) AS net_line_revenue
FROM sales.order_items      oi
JOIN sales.orders           o   ON oi.order_id   = o.order_id
JOIN sales.customers        c   ON o.customer_id = c.customer_id
JOIN sales.stores           st  ON o.store_id    = st.store_id
JOIN sales.staffs           s   ON o.staff_id    = s.staff_id
JOIN production.products    p   ON oi.product_id = p.product_id
JOIN production.categories  cat ON p.category_id = cat.category_id
JOIN production.brands      b   ON p.brand_id    = b.brand_id
WHERE o.order_status = 4                     -- completed orders only
ORDER BY o.order_date DESC;                  -- newest to oldest


/* ============================================================
   TASK 2 — Store Performance Summary
   ============================================================ */
SELECT
    st.store_name,
    COUNT(DISTINCT o.order_id)                                     AS number_of_orders,
    SUM(oi.quantity)                                                AS total_units_sold,
    SUM(oi.quantity * oi.list_price * (1 - oi.discount))            AS total_net_revenue,
    SUM(oi.quantity * oi.list_price * (1 - oi.discount))
        / COUNT(DISTINCT o.order_id)                                AS average_order_value
FROM sales.orders o
JOIN sales.order_items oi ON o.order_id = oi.order_id
JOIN sales.stores      st ON o.store_id = st.store_id
WHERE o.order_status = 4
GROUP BY st.store_name
ORDER BY total_net_revenue DESC;


/* ============================================================
   TASK 3 — High-Value Customers
   (spending greater than the average spending of customers
    who have at least one completed order)
   ============================================================ */
WITH customer_spending AS (
    SELECT
        c.customer_id,
        c.first_name + ' ' + c.last_name                       AS customer_name,
        COUNT(DISTINCT o.order_id)                             AS completed_order_count,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount))   AS total_spending
    FROM sales.customers c
    JOIN sales.orders      o  ON c.customer_id = o.customer_id
    JOIN sales.order_items oi ON o.order_id    = oi.order_id
    WHERE o.order_status = 4
    GROUP BY c.customer_id, c.first_name, c.last_name
)
SELECT
    customer_id,
    customer_name,
    completed_order_count,
    total_spending
FROM customer_spending
WHERE total_spending > (SELECT AVG(total_spending) FROM customer_spending)
ORDER BY total_spending DESC;


/* ============================================================
   TASK 4 — Inventory Risk Report
   (quantity < 5 in at least one store; zero stock first,
    then lowest remaining quantities)
   ============================================================ */
SELECT
    p.product_name,
    st.store_name,
    s.quantity,
    cat.category_name,
    b.brand_name
FROM production.stocks     s
JOIN production.products   p   ON s.product_id  = p.product_id
JOIN production.categories cat ON p.category_id = cat.category_id
JOIN production.brands     b   ON p.brand_id    = b.brand_id
JOIN sales.stores          st  ON s.store_id    = st.store_id
WHERE s.quantity < 5
ORDER BY s.quantity ASC;   -- 0 first, then 1,2,3,4


/* ============================================================
   TASK 5 — Top 3 Products Within Each Category
   (DENSE_RANK so ties share a position and no gaps occur)
   ============================================================ */
WITH product_revenue AS (
    SELECT
        cat.category_name,
        p.product_name,
        SUM(oi.quantity)                                      AS total_units_sold,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount))  AS total_net_revenue
    FROM sales.order_items     oi
    JOIN sales.orders          o   ON oi.order_id   = o.order_id
    JOIN production.products  p   ON oi.product_id = p.product_id
    JOIN production.categories cat ON p.category_id = cat.category_id
    WHERE o.order_status = 4
    GROUP BY cat.category_name, p.product_name
),
ranked AS (
    SELECT
        *,
        DENSE_RANK() OVER (
            PARTITION BY category_name
            ORDER BY total_net_revenue DESC
        ) AS category_rank
    FROM product_revenue
)
SELECT
    category_name,
    product_name,
    total_units_sold,
    total_net_revenue,
    category_rank
FROM ranked
WHERE category_rank <= 3
ORDER BY category_name, category_rank;


/* ============================================================
   TASK 6 — Monthly Sales Trend (month-over-month change)
   ============================================================ */
WITH monthly_sales AS (
    SELECT
        YEAR(o.order_date)   AS sales_year,
        MONTH(o.order_date)  AS sales_month,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_net_revenue
    FROM sales.orders o
    JOIN sales.order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 4
    GROUP BY YEAR(o.order_date), MONTH(o.order_date)
)
SELECT
    sales_year,
    sales_month,
    total_net_revenue,
    LAG(total_net_revenue) OVER (ORDER BY sales_year, sales_month) AS previous_month_revenue,
    total_net_revenue
        - LAG(total_net_revenue) OVER (ORDER BY sales_year, sales_month) AS revenue_change
FROM monthly_sales
ORDER BY sales_year, sales_month;


/* ============================================================
   TASK 7 — Reusable Reporting View
   (customers with no completed orders still appear, via LEFT JOIN)
   ============================================================ */
CREATE VIEW sales.vw_customer_sales_summary AS
SELECT
    c.customer_id,
    c.first_name + ' ' + c.last_name                                    AS customer_name,
    COUNT(DISTINCT o.order_id)                                          AS total_completed_orders,
    ISNULL(SUM(oi.quantity), 0)                                         AS total_units_purchased,
    ISNULL(SUM(oi.quantity * oi.list_price * (1 - oi.discount)), 0)     AS total_net_revenue,
    MAX(o.order_date)                                                   AS most_recent_order_date
FROM sales.customers c
LEFT JOIN sales.orders      o  ON c.customer_id = o.customer_id AND o.order_status = 4
LEFT JOIN sales.order_items oi ON o.order_id    = oi.order_id
GROUP BY c.customer_id, c.first_name, c.last_name;
GO


/* ============================================================
   TASK 8 — Safe Data Modification (transaction + rollback)
   ============================================================ */
BEGIN TRANSACTION;

UPDATE sales.customers
SET phone = '(999) 555-0101'
WHERE customer_id = 1;

-- Validation query: confirm the change took effect before committing
SELECT customer_id, first_name, last_name, phone
FROM sales.customers
WHERE customer_id = 1;

-- During testing, undo the change so the assessment database is untouched:
ROLLBACK TRANSACTION;

-- Once verified in a real scenario, replace the line above with:
-- COMMIT TRANSACTION;


/* ============================================================
   TASK 9 — Store Sales Stored Procedure (with error handling)
   ============================================================ */
CREATE PROCEDURE sales.usp_store_sales_report
    @store_id   INT,
    @start_date DATE,
    @end_date   DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @start_date > @end_date
    BEGIN
        RAISERROR('Invalid date range: @start_date cannot be later than @end_date.', 16, 1);
        RETURN;
    END

    SELECT
        p.product_name,
        SUM(oi.quantity)                                      AS total_units_sold,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount))  AS total_net_revenue
    FROM sales.orders o
    JOIN sales.order_items   oi ON o.order_id   = oi.order_id
    JOIN production.products p  ON oi.product_id = p.product_id
    WHERE o.order_status = 4
      AND o.store_id     = @store_id
      AND o.order_date BETWEEN @start_date AND @end_date
    GROUP BY p.product_name
    ORDER BY total_net_revenue DESC;
END;
GO

-- Example call:
-- EXEC sales.usp_store_sales_report @store_id = 1, @start_date = '2018-01-01', @end_date = '2018-12-31';


/* ============================================================
   TASK 10 — Management Insight Query
   Staff performance: revenue generated per staff member per store
   ============================================================ */
SELECT
    s.first_name + ' ' + s.last_name                                  AS staff_name,
    st.store_name,
    COUNT(DISTINCT o.order_id)                                        AS orders_handled,
    SUM(oi.quantity * oi.list_price * (1 - oi.discount))              AS revenue_generated
FROM sales.staffs s
JOIN sales.orders      o  ON s.staff_id = o.staff_id
JOIN sales.order_items oi ON o.order_id = oi.order_id
JOIN sales.stores      st ON s.store_id = st.store_id
WHERE o.order_status = 4
GROUP BY s.first_name, s.last_name, st.store_name
ORDER BY revenue_generated DESC;

-- 1. Business question: Which staff members drive the most revenue in each store?
-- 2. Result measures: number of completed orders handled and total net revenue per staff member.
-- 3. Management should care: helps identify top performers for incentives, coaching, and staffing decisions.
