output "provision_role_arn" {
  description = "Set as AWS_PROVISION_ROLE_ARN in GitHub repo variables."
  value       = aws_iam_role.provision.arn
}

output "platform_ci_role_arn" {
  description = "Set as AWS_PLATFORM_ROLE_ARN in GitHub repo variables."
  value       = aws_iam_role.platform_ci.arn
}

output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN."
  value       = aws_iam_openid_connect_provider.github.arn
}
