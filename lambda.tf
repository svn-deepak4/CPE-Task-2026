data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/.terraform/lambda.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = local.api_access_log_group_name
  retention_in_days = 30
}

resource "aws_cloudwatch_log_stream" "api_access" {
  name           = "requests"
  log_group_name = aws_cloudwatch_log_group.api_access.name
}

resource "aws_lambda_function" "api" {
  function_name    = local.name
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 15
  memory_size      = 128

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      PARAMETER_NAME        = aws_ssm_parameter.runtime_config.name
      API_ACCESS_LOG_GROUP  = aws_cloudwatch_log_group.api_access.name
      API_ACCESS_LOG_STREAM = aws_cloudwatch_log_stream.api_access.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda,
    aws_vpc_endpoint.interface,
  ]

  tags = {
    Name = local.name
  }
}
