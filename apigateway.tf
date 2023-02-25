######################################
# API Gateway Configuration
######################################
resource "aws_iam_role" "apigateway" {
  name               = "${local.prefix}-apigateway-role"
  assume_role_policy = file("${path.module}/iam_policy_document/assume_apigateway.json")

  tags = {
    Name = "${local.prefix}-apigateway-role"
  }
}

resource "aws_iam_policy" "apigateway" {
  name   = "${local.prefix}-apigateway-policy"
  policy = file("${path.module}/iam_policy_document/iam_apigateway.json")

  tags = {
    Name = "${local.prefix}-apigateway-policy"
  }
}

resource "aws_iam_role_policy_attachment" "apigateway" {
  role       = aws_iam_role.apigateway.name
  policy_arn = aws_iam_policy.apigateway.arn
}

resource "aws_api_gateway_rest_api" "backlog_git" {
  name = "${local.prefix}-backlog-git-api"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_rest_api_policy" "backlog_git" {
  rest_api_id = aws_api_gateway_rest_api.backlog_git.id
  policy      = data.aws_iam_policy_document.backlog_git.json

  lifecycle {
    ignore_changes = [
      policy # IP の順序を固定できないため
    ]
  }
}

data "aws_iam_policy_document" "backlog_git" {
  version = "2012-10-17"
  statement {
    effect = "Allow"
    principals {
      identifiers = ["*"]
      type        = "*"
    }
    actions   = ["execute-api:Invoke"]
    resources = ["execute-api:/*/*/*"]
  }
  statement {
    effect = "Deny"
    principals {
      identifiers = ["*"]
      type        = "*"
    }
    actions   = ["execute-api:Invoke"]
    resources = ["execute-api:/*/*/*"]
    condition {
      test     = "NotIpAddress"
      variable = "aws:SourceIp"
      values   = var.backlog.webhook_ip
    }
  }
}

resource "aws_api_gateway_method" "backlog_git" {
  rest_api_id      = aws_api_gateway_rest_api.backlog_git.id
  resource_id      = aws_api_gateway_rest_api.backlog_git.root_resource_id
  http_method      = "POST"
  api_key_required = false
  authorization    = "NONE"
}

resource "aws_api_gateway_integration" "backlog_git" {
  rest_api_id             = aws_api_gateway_rest_api.backlog_git.id
  resource_id             = aws_api_gateway_rest_api.backlog_git.root_resource_id
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:codebuild:action/StartBuild"
  credentials             = aws_iam_role.apigateway.arn
  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-amz-json-1.1'"
    "integration.request.header.X-Amz-Target" = "'CodeBuild_20161006.StartBuild'"
  }
  request_templates = {
    "application/x-www-form-urlencoded" = <<EOF
{
  "projectName": "${aws_codebuild_project.codebuild.name}"
}
EOF
  }
  passthrough_behavior = "NEVER"
  http_method          = aws_api_gateway_method.backlog_git.http_method
}

resource "aws_api_gateway_integration_response" "backlog_git" {
  rest_api_id        = aws_api_gateway_rest_api.backlog_git.id
  resource_id        = aws_api_gateway_rest_api.backlog_git.root_resource_id
  http_method        = aws_api_gateway_method.backlog_git.http_method
  status_code        = 200
  response_templates = {}

  depends_on = [
    aws_api_gateway_integration.backlog_git
  ]
}

resource "aws_api_gateway_method_response" "backlog_git" {
  rest_api_id     = aws_api_gateway_rest_api.backlog_git.id
  resource_id     = aws_api_gateway_rest_api.backlog_git.root_resource_id
  http_method     = aws_api_gateway_method.backlog_git.http_method
  status_code     = 200
  response_models = { "application/json" : "Empty" }

  depends_on = [
    aws_api_gateway_integration_response.backlog_git
  ]
}

resource "aws_api_gateway_deployment" "backlog_git" {
  rest_api_id = aws_api_gateway_rest_api.backlog_git.id
  stage_name  = var.env

  depends_on = [
    aws_codebuild_project.codebuild,
    aws_api_gateway_method_response.backlog_git
  ]
}