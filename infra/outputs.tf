output "bucket" {
  description = "Where the files go (aws s3 sync site/ s3://<bucket> --delete)."
  value       = aws_s3_bucket.site.bucket
}

output "distribution_id" {
  description = "For cache invalidation after a deploy."
  value       = aws_cloudfront_distribution.site.id
}

output "site_url" {
  value = "https://${var.domain}"
}

output "deploy_role_arn" {
  description = "Put this in the repository's GitHub Actions workflow as role-to-assume."
  value       = local.deploy ? aws_iam_role.deploy[0].arn : null
}
