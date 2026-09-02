resource "aws_ecr_repository" "repos" {
  #checkov:skip=CKV_AWS_136:AES256 chosen; a per-repo KMS CMK adds standing cost against the near-zero-idle budget (ADR 0007 covers signing, not storage encryption)
  for_each = toset([
    "placeholder",
    "orbit-api",
    "orbit-worker",
    "orbit-clickhouse",
    "mirror/clickhouse",
    "mirror/redis",
  ])

  name                 = "${var.name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle {
    prevent_destroy = true
  }
}
