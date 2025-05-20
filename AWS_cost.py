import boto3
import json
import datetime
import os
import sys

# === AWS Credentials (Access Key) ===
AWS_ACCESS_KEY = "YOUR_AWS_ACCESS_KEY_ID"
AWS_SECRET_KEY = "YOUR_AWS_SECRET_ACCESS_KEY"
AWS_REGION = "us-east-1"  # Can be any region (billing data is global)

# === Cost Timeframe ===
FROM_DATE = "2025-02-01"
TO_DATE = "2025-02-28"

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
grouped_costs = response["ResultsByTime"][0]["Groups"]
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
    cost = float(group["Metrics"]["UnblendedCost"]["Amount"])
    currency = response["ResultsByTime"][0]["Total"]["UnblendedCost"]["Unit"]

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
