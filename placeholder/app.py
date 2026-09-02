import logging
import os
import uuid
from datetime import datetime, timezone

import boto3
from fastapi import FastAPI, Response

app = FastAPI()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Low-level clients are thread-safe; the credential chain resolves once per
# process, so create the client at module level instead of per-request.
_s3 = boto3.client("s3")
logger.info("s3 client region=%s", _s3.meta.region_name)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/ready")
def ready() -> dict:
    return {"status": "ok"}


@app.get("/s3-roundtrip")
def s3_roundtrip(response: Response) -> dict:
    bucket = os.environ.get("PLACEHOLDER_BUCKET")
    if not bucket:
        response.status_code = 503
        return {"ok": False, "error": "PLACEHOLDER_BUCKET unset"}

    key = f"roundtrip/{uuid.uuid4()}.txt"
    body = datetime.now(timezone.utc).isoformat().encode("utf-8")

    try:
        _s3.put_object(Bucket=bucket, Key=key, Body=body)
        _s3.get_object(Bucket=bucket, Key=key)["Body"].read()
        _s3.delete_object(Bucket=bucket, Key=key)
        return {"bucket": bucket, "key": key, "ok": True}
    except Exception as exc:
        logger.exception("s3 roundtrip failed")
        response.status_code = 500
        return {"ok": False, "error": type(exc).__name__}
