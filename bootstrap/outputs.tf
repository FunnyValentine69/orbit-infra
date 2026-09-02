output "state_bucket_name" {
  description = "S3 bucket holding Terraform state"
  value       = aws_s3_bucket.state.bucket
}

output "plan_reader_role_arn" {
  value     = aws_iam_role.plan_reader.arn
  sensitive = true
}

output "deployer_role_arn" {
  value     = aws_iam_role.deployer.arn
  sensitive = true
}

output "publisher_role_arn" {
  value     = aws_iam_role.publisher.arn
  sensitive = true
}

output "ecr_repository_urls" {
  value     = { for k, v in aws_ecr_repository.repos : k => v.repository_url }
  sensitive = true
}

output "kms_signing_key_arn" {
  value     = aws_kms_key.signing.arn
  sensitive = true
}

output "oidc_provider_arn" {
  value     = local.oidc_provider_arn
  sensitive = true
}

output "oidc_subjects" {
  description = "Exact OIDC subject strings used in role trust policies, for the smoke test"
  value = {
    main_branch = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:ref:refs/heads/main"
  }
}
