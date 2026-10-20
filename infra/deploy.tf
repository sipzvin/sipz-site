# Lets GitHub Actions deploy the site WITHOUT any stored AWS keys: the workflow proves who it is with a short-lived token from GitHub
# (OIDC), and AWS hands back temporary credentials for this one role. Nothing secret is stored anywhere.
#
# Skipped unless github_repo is set. The OIDC provider can exist only once per account; if your account already has GitHub's, set
# create_oidc_provider = false and it will be looked up instead.
variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one (there can be only one)."
  type        = bool
  default     = true
}

variable "deploy_branch" {
  description = "The only branch whose workflow runs may deploy."
  type        = string
  default     = "main"
}

locals {
  deploy = var.github_repo != null
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = local.deploy && var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's certificate chain is validated by AWS itself now; this value is required by the API but no longer trusted for security.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = local.deploy && !var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_arn = local.deploy ? (var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn) : null
}

data "aws_iam_policy_document" "deploy_trust" {
  count = local.deploy ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # The exact repository AND the exact branch. A fork, another repo, or a pull request branch cannot assume this role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.deploy_branch}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  count                = local.deploy ? 1 : 0
  name                 = "${replace(var.domain, ".", "-")}-site-deploy"
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust[0].json
  max_session_duration = 3600
}

# Exactly what a deploy does: copy files into this bucket, delete the ones that were removed, and clear the CDN cache. Nothing else.
data "aws_iam_policy_document" "deploy" {
  count = local.deploy ? 1 : 0

  statement {
    sid       = "ReadWriteSiteFiles"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
  }
  statement {
    sid       = "ListSiteBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn]
  }
  statement {
    sid       = "ClearCache"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  count  = local.deploy ? 1 : 0
  name   = "deploy"
  role   = aws_iam_role.deploy[0].id
  policy = data.aws_iam_policy_document.deploy[0].json
}
