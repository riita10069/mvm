output "image_arn" {
  value = aws_cloudformation_stack.image.outputs["ImageArn"]
}

output "image_version" {
  value = aws_cloudformation_stack.image.outputs["LatestActiveVersion"]
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}
