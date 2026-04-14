import base64
import gzip
import json
import os
import urllib.request
import urllib.error

SPLUNK_HEC_URL   = os.environ["SPLUNK_HEC_URL"]    # e.g. https://<splunk-cloud>.splunkcloud.com:8088/services/collector
SPLUNK_HEC_TOKEN = os.environ["SPLUNK_HEC_TOKEN"]  # Splunk HEC token


def lambda_handler(event, context):
    # Decode and decompress CloudWatch Logs data
    log_data = json.loads(gzip.decompress(base64.b64decode(event["awslogs"]["data"])))

    events = []
    for log_event in log_data["logEvents"]:
        events.append({
            "time":       log_event["timestamp"] / 1000,
            "host":       log_data["logGroup"],
            "source":     log_data["logStream"],
            "sourcetype": "dbt:snowflake",
            "index":      "main",
            "event":      log_event["message"]
        })

    payload = "\n".join(json.dumps(e) for e in events).encode("utf-8")

    req = urllib.request.Request(
        SPLUNK_HEC_URL,
        data=payload,
        headers={
            "Authorization": f"Splunk {SPLUNK_HEC_TOKEN}",
            "Content-Type":  "application/json"
        }
    )

    try:
        with urllib.request.urlopen(req) as resp:
            print(f"Splunk response: {resp.status} {resp.read().decode()}")
    except urllib.error.HTTPError as e:
        print(f"Splunk HEC error: {e.code} {e.read().decode()}")
        raise
