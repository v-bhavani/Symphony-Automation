import boto3
import json
import datetime
import os
import sys

# === AWS Credentials (Access Key) ===
AWS_ACCESS_KEY = "$Accesskey"
AWS_SECRET_KEY = "$Secretkey"
AWS_REGION = "us-east-1"  # Can be any region (billing data is global)

# === Cost Timeframe ===
FROM_DATE = "$Start_date"
TO_DATE = "$End_date"

# === Boto3 session using keys ===
session = boto3.Session(
    aws_access_key_id=AWS_ACCESS_KEY,
    aws_secret_access_key=AWS_SECRET_KEY,
    region_name=AWS_REGION
)

ce_client = session.client("ce")  # Cost Explorer is a global service

try:
    response = ce_client.get_cost_and_usage(
        TimePeriod={
            "Start": FROM_DATE,
            "End": TO_DATE
        },
        Granularity="MONTHLY",
        Metrics=["UnblendedCost"],
        GroupBy=[
            {"Type": "DIMENSION", "Key": "SERVICE"}
        ]
    )
except Exception as e:
    print(f"Error fetching cost data: {e}")
    sys.exit(1)

# === Parse and prepare table + pie data ===
results = response.get("ResultsByTime", [])
if not results:
    print("⚠️ No results returned from AWS Cost Explorer.")
    sys.exit(1)

grouped_costs = results[0].get("Groups", [])
total = results[0].get("Total", {})

# Use default currency fallback
currency = total.get("UnblendedCost", {}).get("Unit", "USD")

table_data = []
pie_labels = []
pie_values = []

color_palette = [
    "#c45850", "#ff9f40", "#ffcc66", "#3cba9f", "#8e5ea2",
    "#00aaff", "#ff66cc", "#9933ff", "#66cc33", "#ff3333",
    "#3399ff", "#ffcc00", "#66ffff", "#cc99ff", "#ff9966"
]

for i, group in enumerate(grouped_costs):
    service = group["Keys"][0]
    cost_str = group["Metrics"].get("UnblendedCost", {}).get("Amount", "0")
    try:
        cost = float(cost_str)
    except ValueError:
        cost = 0.0

    table_data.append({
        "Service": service,
        "UnblendedCost": round(cost, 2),
        "Currency": currency
    })

    pie_labels.append(f"{service} ({cost:.2f} {currency})")
    pie_values.append(cost)

# === Pie data ===
pie_data = {
    "type": "pie",
    "dataSet": [{
        "label": "AWS Service Cost",
        "data": pie_values,
        "backgroundColor": color_palette[:len(pie_values)]
    }],
    "label": pie_labels
}

# === Output JSON blocks ===
print(f"##gbStart##copilot_ctable_data##splitKeyValue##{json.dumps(table_data)}##gbEnd##")
print(f"##gbStart##copilot_cpiechart_data##splitKeyValue##{json.dumps(pie_data)}##gbEnd##")
print("AWS cost table and pie chart data compiled successfully.")
