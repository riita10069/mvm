data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account   = data.aws_caller_identity.current.account_id
  partition = data.aws_partition.current.partition
  log_group = "/aws/lambda-microvms/${var.name}"
}

# ---- Build context bucket ----
resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "${var.name}-artifacts-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_cloudwatch_log_group" "mvm" {
  name              = local.log_group
  retention_in_days = var.log_retention_days
}

# ---- IAM ----
# aws:SourceArn is not added: CloudTrail does not show the ARN the service sends, and a wrong guess
# would break every build and VM.
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

data "aws_iam_policy_document" "logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.mvm.arn}:*"]
  }
}

resource "aws_iam_role" "build" {
  name_prefix        = "${var.name}-build-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "build" {
  source_policy_documents = [data.aws_iam_policy_document.logs.json]
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
}

resource "aws_iam_role_policy" "build" {
  role   = aws_iam_role.build.id
  name   = "build"
  policy = data.aws_iam_policy_document.build.json
}

# Runs inside every VM: Claude Code (Bedrock Anthropic models) and Codex (bedrock-mantle), plus logs.
resource "aws_iam_role" "execution" {
  name_prefix        = "${var.name}-exec-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "execution" {
  source_policy_documents = [data.aws_iam_policy_document.logs.json]
  statement {
    sid     = "ClaudeOnBedrock"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = [
      "arn:${local.partition}:bedrock:*::foundation-model/anthropic.*",
      "arn:${local.partition}:bedrock:::foundation-model/anthropic.*",
      "arn:${local.partition}:bedrock:*:${local.account}:inference-profile/*anthropic.*",
    ]
  }
  # Codex's openai.gpt-5.5 is served only by bedrock-mantle in us-east-1 (codex-config.toml).
  statement {
    sid       = "CodexOnBedrockMantle"
    actions   = ["bedrock-mantle:CreateInference"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-east-1"]
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  role   = aws_iam_role.execution.id
  name   = "runtime"
  policy = data.aws_iam_policy_document.execution.json
}
