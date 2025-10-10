data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../app/backend"
  output_path = "${path.module}/../build/backend.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "luvlaunch-teetgergergerger-9de1c5a8-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "ddb_rw" {
  name = "luvlaunch-teetgergergerger-9de1c5a8-ddb-rw"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = ["dynamodb:PutItem","dynamodb:GetItem"],
      Resource = aws_dynamodb_table.main.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ddb_rw_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.ddb_rw.arn
}

resource "aws_lambda_function" "writer" {
  function_name    = "luvlaunch-teetgergergerger-9de1c5a8-writer"
  role             = aws_iam_role.lambda_exec.arn
  runtime          = "python3.11"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = "luvlaunch-teetgergergerger-9de1c5a8-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_methods = ["GET", "POST", "PATCH", "DELETE", "OPTIONS"]
    allow_origins = ["*"]
    allow_headers = ["content-type"]
    max_age = 3600
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.writer.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_item" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /items"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "get_items" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /items"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "patch_item" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "PATCH /items/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "delete_item" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "DELETE /items/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowInvokeFromAPIGW"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.writer.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

output "api_base_url" {
  value = aws_apigatewayv2_api.http.api_endpoint
}