import os
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

# Azure Client Credential Auth
tenant_id = AZURE_TENANT_ID
client_id = AZURE_CLIENT_ID
client_secret = AZURE_CLIENT_SECRET

if not all([tenant_id, client_id, client_secret]):
    raise Exception("Missing Azure client credentials in script variables.")

credential = ClientSecretCredential(tenant_id, client_id, client_secret)
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

# Process and format data
rows = response.json()["properties"]["rows"]
table_data = []
labels = []
sizes = []

for row in rows:
    cost = float(row[0])
    service = row[1]
    currency = row[2]
    table_data.append({
        "PreTaxCost": round(cost, 2),
        "MeterCategory": service,
        "Currency": currency
    })
    labels.append(f"{service} ({cost:.2f} {currency})")
    sizes.append(cost)

# === Output Table JSON ===
table_output = {
    "AzureCostSummary": table_data
}

# Print JSON block for table
print(f"##gbStart##copilot_ctable_data##splitKeyValue##{json.dumps(table_output)}##gbEnd##")

# Write to file
with open("azure_cost_table.json", "w") as f:
    json.dump(table_output, f, indent=2)
    print("Table data written to azure_cost_table.json")

# === Output Pie Chart JSON ===
pie_data = {
    "type": "pie",
    "dataSet": [{
        "label": "Azure Service Cost",
        "data": sizes,
        "backgroundColor": [
            "#c45850", "#ff9f40", "#ffcc66", "#3cba9f", "#8e5ea2",
            "#00aaff", "#ff66cc", "#9933ff", "#66cc33", "#ff3333",
            "#3399ff", "#ffcc00", "#66ffff", "#cc99ff", "#ff9966"
        ][:len(sizes)]
    }],
    "label": labels
}

# Print JSON block for pie chart
print(f"##gbStart##copilot_cpiechart_data##splitKeyValue##{json.dumps(pie_data)}##gbEnd##")

# Write to file
with open("azure_cost_piechart.json", "w") as f:
    json.dump(pie_data, f, indent=2)
    print("Pie chart data written to azure_cost_piechart.json")
