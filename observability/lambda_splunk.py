import base64
import gzip
import json
import os
import ssl
import urllib.request
import urllib.error

SPLUNK_HEC_URL   = os.environ["SPLUNK_HEC_URL"]
SPLUNK_HEC_TOKEN = os.environ["SPLUNK_HEC_TOKEN"]

# Disable SSL verification for Splunk Cloud (POC only)
SSL_CONTEXT = ssl.create_default_context()
SSL_CONTEXT.check_hostname = False
SSL_CONTEXT.verify_mode = ssl.CERT_NONE


def lambda_handler(event, context):
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
        with urllib.request.urlopen(req, context=SSL_CONTEXT) as resp:
            print(f"Splunk response: {resp.status} {resp.read().decode()}")
    except urllib.error.HTTPError as e:
        print(f"Splunk HEC error: {e.code} {e.read().decode()}")
        raise
