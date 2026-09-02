import os
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, Response

app = FastAPI()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/ready")
def ready():
    return {"status": "ok"}


@app.get("/s3-roundtrip")
def s3_roundtrip(response: Response):
    bucket = os.environ.get("PLACEHOLDER_BUCKET")
    if not bucket:
        response.status_code = 503
        return {"ok": False, "error": "PLACEHOLDER_BUCKET unset"}

    key = f"roundtrip/{uuid.uuid4()}.txt"
    body = datetime.now(timezone.utc).isoformat().encode("utf-8")

    try:
        s3 = boto3.client("s3")
        s3.put_object(Bucket=bucket, Key=key, Body=body)
        s3.get_object(Bucket=bucket, Key=key)
        s3.delete_object(Bucket=bucket, Key=key)
        return {"bucket": bucket, "key": key, "ok": True}
    except ClientError as exc:
        response.status_code = 500
        return {"ok": False, "error": type(exc).__name__}
    except Exception as exc:
        response.status_code = 500
        return {"ok": False, "error": type(exc).__name__}
