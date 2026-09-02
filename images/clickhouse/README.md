# images/clickhouse

Derived ClickHouse image for the upstream workload: the same pinned,
digest-referenced base image `mirror-images.yml` mirrors into private ECR,
with the upstream workload's schema init script layered on top.

The init SQL is never committed to this repo. `scripts/build-upstream.sh`
passes the local upstream `git archive` extraction as a named BuildKit
build context (`--build-context upstream=<archive dir>`), and this
Dockerfile's `COPY --from=upstream infrastructure/scripts/init-clickhouse.sql`
pulls the file from that context at build time only. `.gitignore` also
excludes `**/init-clickhouse.sql` as a second layer of protection in case
the file is ever copied into this repo by mistake.
