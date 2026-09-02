output "state_bucket_name" {
  description = "S3 bucket holding Terraform state"
  value       = aws_s3_bucket.state.bucket
}

output "plan_reader_role_arn" {
  description = "ARN of the OIDC-assumable role that runs read-only plans"
  value       = aws_iam_role.plan_reader.arn
  sensitive   = true
}

output "deployer_role_arn" {
  description = "ARN of the OIDC-assumable role that applies infrastructure changes"
  value       = aws_iam_role.deployer.arn
  sensitive   = true
}

output "publisher_role_arn" {
  description = "ARN of the OIDC-assumable role that publishes signed images/artifacts"
  value       = aws_iam_role.publisher.arn
  sensitive   = true
}

output "ecr_repository_urls" {
  description = "Map of ECR repository name to repository URL"
  value       = { for k, v in aws_ecr_repository.repos : k => v.repository_url }
  sensitive   = true
}

output "kms_signing_key_arn" {
  description = "ARN of the KMS key used for artifact signing"
  value       = aws_kms_key.signing.arn
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider"
  value       = local.oidc_provider_arn
  sensitive   = true
}

output "task_boundary_policy_arn" {
  description = "ARN of the permissions boundary policy attached to ECS execution/task roles; naming contract: <var.name>-task-boundary"
  value       = aws_iam_policy.task_boundary.arn
  sensitive   = true
}

output "oidc_subjects" {
  description = "Exact OIDC subject strings used in role trust policies, for the smoke test"
  value = {
    main_branch = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:ref:refs/heads/main"
  }
}
