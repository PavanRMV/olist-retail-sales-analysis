"""
Olist Retail Sales — Exploratory Data Analysis
Run this as a script, or paste cells into a Jupyter Notebook.

Goal: explore the cleaned data, surface early patterns, and export
a flattened, dashboard-ready CSV for Tableau / Power BI.
"""

import sqlite3
import pandas as pd
import matplotlib.pyplot as plt

pd.set_option("display.max_columns", None)

# ------------------------------------------------------------------
# 1. Connect and load core tables
# ------------------------------------------------------------------
conn = sqlite3.connect("../olist.db")

orders = pd.read_sql("SELECT * FROM orders", conn, parse_dates=[
    "order_purchase_timestamp", "order_approved_at",
    "order_delivered_carrier_date", "order_delivered_customer_date",
    "order_estimated_delivery_date"
])
order_items = pd.read_sql("SELECT * FROM order_items", conn)
customers = pd.read_sql("SELECT * FROM customers", conn)
products = pd.read_sql("SELECT * FROM products", conn)
category_translation = pd.read_sql("SELECT * FROM product_category_translation", conn)
payments = pd.read_sql("SELECT * FROM order_payments", conn)
reviews = pd.read_sql("SELECT * FROM order_reviews", conn)

print("Rows loaded:")
for name, df in [("orders", orders), ("order_items", order_items),
                  ("customers", customers), ("products", products),
                  ("payments", payments), ("reviews", reviews)]:
    print(f"  {name}: {len(df):,}")

# ------------------------------------------------------------------
# 2. Data quality check — nulls, duplicates, order status breakdown
# ------------------------------------------------------------------
print("\nOrder status breakdown:")
print(orders["order_status"].value_counts())

print("\nNull delivery dates (still in transit / cancelled):")
print(orders["order_delivered_customer_date"].isna().sum())

print("\nDuplicate order_ids in orders table:", orders["order_id"].duplicated().sum())

# Keep only delivered orders for revenue analysis — undelivered orders
# don't represent completed sales.
delivered = orders[orders["order_status"] == "delivered"].copy()

# ------------------------------------------------------------------
# 3. Build one flattened, analysis-ready table
# ------------------------------------------------------------------
df = (
    delivered
    .merge(order_items, on="order_id", how="left")
    .merge(customers, on="customer_id", how="left")
    .merge(products, on="product_id", how="left")
    .merge(category_translation, on="product_category_name", how="left")
)

df["order_total"] = df["price"] + df["freight_value"]
df["order_month"] = df["order_purchase_timestamp"].dt.to_period("M").astype(str)
df["delivery_days"] = (
    df["order_delivered_customer_date"] - df["order_purchase_timestamp"]
).dt.days
df["days_late"] = (
    df["order_delivered_customer_date"] - df["order_estimated_delivery_date"]
).dt.days

print(f"\nFlattened table shape: {df.shape}")

# ------------------------------------------------------------------
# 4. Quick exploratory charts (for your own discovery — not the final dashboard)
# ------------------------------------------------------------------
monthly_revenue = df.groupby("order_month")["order_total"].sum()

plt.figure(figsize=(10, 4))
monthly_revenue.plot(kind="line", marker="o")
plt.title("Monthly Revenue Trend")
plt.ylabel("Revenue (R$)")
plt.xticks(rotation=45)
plt.tight_layout()
plt.savefig("monthly_revenue_trend.png")
plt.close()

top_categories = (
    df.groupby("product_category_name_english")["order_total"]
    .sum()
    .sort_values(ascending=False)
    .head(10)
)

plt.figure(figsize=(10, 5))
top_categories.plot(kind="barh")
plt.title("Top 10 Categories by Revenue")
plt.xlabel("Revenue (R$)")
plt.gca().invert_yaxis()
plt.tight_layout()
plt.savefig("top_categories_revenue.png")
plt.close()

print("\nSaved charts: monthly_revenue_trend.png, top_categories_revenue.png")

# ------------------------------------------------------------------
# 5. Merge in review scores and payment info, then export for the dashboard
# ------------------------------------------------------------------
avg_review = reviews.groupby("order_id")["review_score"].mean().reset_index()
payment_summary = payments.groupby("order_id").agg(
    payment_type=("payment_type", "first"),
    installments=("payment_installments", "max"),
    total_payment=("payment_value", "sum")
).reset_index()

dashboard_df = (
    df.merge(avg_review, on="order_id", how="left")
      .merge(payment_summary, on="order_id", how="left")
)

export_cols = [
    "order_id", "order_month", "customer_state", "customer_city",
    "product_category_name_english", "price", "freight_value",
    "order_total", "delivery_days", "days_late", "review_score",
    "payment_type", "installments", "total_payment"
]

dashboard_df[export_cols].to_csv("olist_dashboard_ready.csv", index=False)
print("\nExported dashboard-ready file: olist_dashboard_ready.csv")
print(f"Final shape: {dashboard_df[export_cols].shape}")

conn.close()
