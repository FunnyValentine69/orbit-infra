# placeholder

Public workload image that proves the stack and the task-role credential
chain without the private upstream.

## Endpoints

- `GET /health` — liveness check
- `GET /ready` — readiness check
- `GET /s3-roundtrip` — put/get/delete a test object using the default AWS
  credential chain; reads bucket name from `PLACEHOLDER_BUCKET`

## Build

```
docker build --platform linux/arm64 -t placeholder:dev placeholder/
```
