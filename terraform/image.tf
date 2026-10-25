# The image is built from ../image (Dockerfile at the zip root). A content change gives a new S3 key,
# which updates the stack, which makes Lambda build a new image version.
data "archive_file" "image" {
  type        = "zip"
  source_dir  = "${path.module}/../image"
  output_path = "${path.module}/.build/${var.name}-image.zip"
  excludes    = ["**/.DS_Store", "**/__pycache__/**", "**/*.pyc"]
}

resource "aws_s3_object" "image" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "images/${var.name}/${data.archive_file.image.output_sha256}.zip"
  source = data.archive_file.image.output_path
  # Old build contexts are deleted only after the stack points at the new one. There is no lifecycle
  # expiry: it would also delete the context of the current version.
  lifecycle { create_before_destroy = true }
}

# aws_lambdamicrovms_image (provider 6.70) cannot set hooks or logging, and mvm-agent needs the
# /ready and /run hooks, so the image is a CloudFormation AWS::Lambda::MicrovmImage.
resource "aws_cloudformation_stack" "image" {
  name = "${var.name}-image"

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Resources = {
      Image = {
        Type = "AWS::Lambda::MicrovmImage"
        Properties = {
          Name                     = var.name
          Description              = "mvm image (artifact ${substr(data.archive_file.image.output_sha256, 0, 16)})"
          BaseImageArn             = "arn:${local.partition}:lambda:${var.region}:aws:microvm-image:al2023-1"
          BaseImageVersion         = var.base_image_version
          BuildRoleArn             = aws_iam_role.build.arn
          CodeArtifact             = { Uri = "s3://${aws_s3_object.image.bucket}/${aws_s3_object.image.key}" }
          Logging                  = { CloudWatch = { LogGroup = aws_cloudwatch_log_group.mvm.name } }
          EgressNetworkConnectors  = ["arn:${local.partition}:lambda:${var.region}:aws:network-connector:aws-network-connector:INTERNET_EGRESS"]
          CpuConfigurations        = [{ Architecture = "ARM_64" }]
          Resources                = [{ MinimumMemoryInMiB = var.minimum_memory_mib }]
          AdditionalOsCapabilities = []
          EnvironmentVariables     = []
          Hooks = {
            Port              = 9000
            MicrovmImageHooks = { Ready = "ENABLED", ReadyTimeoutInSeconds = 120 }
            MicrovmHooks = {
              Run       = "ENABLED", RunTimeoutInSeconds = 15
              Resume    = "ENABLED", ResumeTimeoutInSeconds = 5
              Suspend   = "ENABLED", SuspendTimeoutInSeconds = 5
              Terminate = "ENABLED", TerminateTimeoutInSeconds = 5
            }
          }
          # mvm reads the role for RunMicrovm from this tag, so the CLI needs no local config.
          Tags = [
            { Key = "mvm:execution-role", Value = aws_iam_role.execution.arn },
            { Key = "mvm:managed", Value = "true" },
          ]
        }
      }
    }
    Outputs = {
      ImageArn            = { Value = { "Fn::GetAtt" = ["Image", "ImageArn"] } }
      LatestActiveVersion = { Value = { "Fn::GetAtt" = ["Image", "LatestActiveImageVersion"] } }
    }
  })

  timeouts {
    create = "60m"
    update = "60m"
    delete = "30m"
  }

  depends_on = [aws_iam_role_policy.build]
}
