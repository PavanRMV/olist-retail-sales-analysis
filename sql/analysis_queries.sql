-- ============================================================
-- Olist Retail Sales Analysis — SQL Queries
-- Database: olist.db (SQLite)
-- Each query below answers a specific business question.
-- ============================================================

-- Q1: What is total revenue, order count, and avg order value by month?
-- (Trend over time — used for the dashboard's main KPI line chart)
SELECT
    strftime('%Y-%m', o.order_purchase_timestamp) AS order_month,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    ROUND(SUM(oi.price + oi.freight_value) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY order_month
ORDER BY order_month;


-- Q2: Which product categories generate the most revenue?
SELECT
    pct.product_category_name_english AS category,
    COUNT(DISTINCT oi.order_id) AS num_orders,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    ROUND(AVG(oi.price), 2) AS avg_item_price
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
JOIN product_category_translation pct ON p.product_category_name = pct.product_category_name
JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY category
ORDER BY total_revenue DESC
LIMIT 15;


-- Q3: Which Brazilian states generate the most revenue and have the most customers?
SELECT
    c.customer_state,
    COUNT(DISTINCT c.customer_id) AS num_customers,
    COUNT(DISTINCT o.order_id) AS num_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY total_revenue DESC;


-- Q4: Running total of monthly revenue (window function — cumulative growth)
WITH monthly AS (
    SELECT
        strftime('%Y-%m', o.order_purchase_timestamp) AS order_month,
        SUM(oi.price + oi.freight_value) AS monthly_revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY order_month
)
SELECT
    order_month,
    ROUND(monthly_revenue, 2) AS monthly_revenue,
    ROUND(SUM(monthly_revenue) OVER (ORDER BY order_month), 2) AS running_total_revenue
FROM monthly
ORDER BY order_month;


-- Q5: Rank product categories by revenue within each state (window function — RANK)
WITH state_category_revenue AS (
    SELECT
        c.customer_state,
        pct.product_category_name_english AS category,
        SUM(oi.price) AS revenue
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    JOIN product_category_translation pct ON p.product_category_name = pct.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_state, category
)
SELECT customer_state, category, revenue, category_rank
FROM (
    SELECT
        customer_state,
        category,
        ROUND(revenue, 2) AS revenue,
        RANK() OVER (PARTITION BY customer_state ORDER BY revenue DESC) AS category_rank
    FROM state_category_revenue
)
WHERE category_rank <= 3;


-- Q6: Average delivery time vs. estimated delivery time (operations insight)
SELECT
    strftime('%Y-%m', order_purchase_timestamp) AS order_month,
    ROUND(AVG(julianday(order_delivered_customer_date) - julianday(order_purchase_timestamp)), 1) AS avg_actual_delivery_days,
    ROUND(AVG(julianday(order_estimated_delivery_date) - julianday(order_purchase_timestamp)), 1) AS avg_estimated_delivery_days,
    ROUND(AVG(julianday(order_delivered_customer_date) - julianday(order_estimated_delivery_date)), 1) AS avg_days_late
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
GROUP BY order_month
ORDER BY order_month;


-- Q7: Which payment types are most common, and do installment plans correlate with order value?
SELECT
    payment_type,
    COUNT(*) AS num_payments,
    ROUND(AVG(payment_installments), 1) AS avg_installments,
    ROUND(AVG(payment_value), 2) AS avg_payment_value,
    ROUND(SUM(payment_value), 2) AS total_payment_value
FROM order_payments
GROUP BY payment_type
ORDER BY total_payment_value DESC;


-- Q8: Review scores vs. delivery delay — does a late delivery hurt review scores?
SELECT
    CASE
        WHEN julianday(o.order_delivered_customer_date) - julianday(o.order_estimated_delivery_date) <= 0 THEN 'On time or early'
        ELSE 'Late'
    END AS delivery_status,
    COUNT(*) AS num_orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_status;


-- Q9: Top 10 sellers by revenue (for a "seller performance" view)
SELECT
    oi.seller_id,
    s.seller_state,
    COUNT(DISTINCT oi.order_id) AS num_orders,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    ROUND(AVG(oi.price), 2) AS avg_item_price
FROM order_items oi
JOIN sellers s ON oi.seller_id = s.seller_id
JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY oi.seller_id, s.seller_state
ORDER BY total_revenue DESC
LIMIT 10;
