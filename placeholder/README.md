# placeholder

Public workload image that proves the stack and the task-role credential
chain without the private upstream.

## Endpoints

- `GET /health` — liveness check
- `GET /ready` — readiness check
- `GET /s3-roundtrip` — put/get/delete a test object using the default AWS
  credential chain; reads bucket name from `PLACEHOLDER_BUCKET`

## Region configuration

The S3 client silently defaults to `us-east-1` when no region is
configured. `AWS_REGION` (or `AWS_DEFAULT_REGION`) is required in the
task definition, and `PLACEHOLDER_BUCKET` must be in that same region.
The client's resolved region is logged at startup as
`s3 client region=<region>`.

## Build

```
docker build --platform linux/arm64 -t placeholder:dev placeholder/
```
