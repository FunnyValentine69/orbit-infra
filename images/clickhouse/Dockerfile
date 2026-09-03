# clickhouse/clickhouse-server:24.3-alpine, resolved 2026-09-02
# same reference mirror-images.yml mirrors (SOURCE_IMAGE, "Mirror
# clickhouse/clickhouse-server:24.3-alpine" step)
FROM clickhouse/clickhouse-server:24.3-alpine@sha256:c3f166f4a80098480463d897a63f6867d24e3a7661fc1fe72e889788115a25f1

COPY --from=upstream infrastructure/scripts/init-clickhouse.sql /docker-entrypoint-initdb.d/
