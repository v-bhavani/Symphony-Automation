import json
import time
import requests
from azure.identity import ClientSecretCredential

# Constants
subscription_id = "bf18f464-1469-4216-834f-9c6694dbfe26"
from_date = "$Start_date"
to_date = "$End_date"
api_version = "2021-10-01"
url = f"https://management.azure.com/subscriptions/{subscription_id}/providers/Microsoft.CostManagement/query?api-version={api_version}"
AZURE_TENANT_ID = "$Tenantid"
AZURE_CLIENT_ID = "$Clientid"
AZURE_CLIENT_SECRET = "$Clientsecret"

# Azure Authentication
credential = ClientSecretCredential(AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET)
token = credential.get_token("https://management.azure.com/.default").token
headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json"
}

# Request body
body = {
    "type": "ActualCost",
    "timeframe": "Custom",
    "timePeriod": {
        "from": from_date,
        "to": to_date
    },
    "dataset": {
        "granularity": "None",
        "aggregation": {
            "totalCost": {
                "name": "PreTaxCost",
                "function": "Sum"
            }
        },
        "grouping": [
            {
                "type": "Dimension",
                "name": "MeterCategory"
            }
        ]
    }
}

# Retry logic
MAX_RETRIES = 5
WAIT_TIME = 10  # seconds

for attempt in range(MAX_RETRIES):
    try:
        response = requests.post(url, headers=headers, json=body)
        response.raise_for_status()
        break
    except requests.exceptions.HTTPError as e:
        if response.status_code == 429:
            retry_after = int(response.headers.get("Retry-After", WAIT_TIME))
            print(f"[Attempt {attempt+1}] 429 Too Many Requests. Retrying in {retry_after} seconds...")
            time.sleep(retry_after)
        else:
            raise
else:
    raise Exception("Failed after multiple retries due to 429 errors.")

# Extract rows
rows = response.json()["properties"]["rows"]
table_data = []
pie_labels = []
pie_sizes = []

# Optional: colors for pie chart
color_palette = [
    "#c45850", "#ff9f40", "#ffcc66", "#3cba9f", "#8e5ea2",
    "#00aaff", "#ff66cc", "#9933ff", "#66cc33", "#ff3333",
    "#3399ff", "#ffcc00", "#66ffff", "#cc99ff", "#ff9966"
]

for i, row in enumerate(rows):
    cost = float(row[0])
    metercategory = row[1]
    currency = row[2]

    table_data.append({
        "MeterCategory": metercategory,
        "PreTaxCost": round(cost, 2),
        "Currency": currency
    })

    pie_labels.append(f"{metercategory} ({cost:.2f} {currency})")
    pie_sizes.append(cost)

# Compose pie chart structure
pie_data = {
    "type": "pie",
    "dataSet": [{
        "label": "Azure Service Cost",
        "data": pie_sizes,
        "backgroundColor": color_palette[:len(pie_sizes)]
    }],
    "label": pie_labels
}

# Print final JSON blocks
print(f"##gbStart##copilot_ctable_data##splitKeyValue##{json.dumps(table_data)}##gbEnd##")
print(f"##gbStart##copilot_cpiechart_data##splitKeyValue##{json.dumps(pie_data)}##gbEnd##")
print("Azure cost table and pie chart data compiled successfully.")
