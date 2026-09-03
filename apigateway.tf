resource "aws_apigatewayv2_api" "main" {
  name          = local.name
  description   = "Borda do Car Workshop: /auth emite o token por CPF, o resto vai para o EKS."
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "auth" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.auth.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "auth" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /auth"
  target    = "integrations/${aws_apigatewayv2_integration.auth.id}"
}

# Sem isto o Gateway leva 403 da Lambda e devolve 500 — erro que parece bug na função.
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# `{proxy}` na URI recebe o path capturado pela rota, então /carworkshop/v1/tracking/1 chega ao ELB
# inteiro. Sem `request_parameters` de propósito: carimbar o X-Trace-Id exigiria `overwrite` (apaga o
# header do cliente) ou `append` (produz "id-cliente,id-gateway"), e o id de fora atravessar intacto
# é a propriedade em que a correlação dos Blocos 4b-4e se apoia.
resource "aws_apigatewayv2_integration" "app" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "${local.app_url}/{proxy}"
}

# Rota mais específica ganha: o `POST /auth` acima não é engolido por este `{proxy+}`.
resource "aws_apigatewayv2_route" "app" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.app.id}"
}

resource "aws_cloudwatch_log_group" "api" {
  count = var.enable_access_logs ? 1 : 0

  name              = "/aws/apigateway/${local.name}"
  retention_in_days = var.log_retention_days
}

# Stage `$default`: a URL sai sem prefixo, então o path que o cliente chama é o que a app recebe.
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  dynamic "access_log_settings" {
    for_each = var.enable_access_logs ? [1] : []

    content {
      destination_arn = aws_cloudwatch_log_group.api[0].arn
      # `integrationErrorMessage` distingue "o ELB morreu" de "a app respondeu erro" — é o
      # diagnóstico do 503 quando o /fase3/eks/lb-dns está obsoleto.
      format = jsonencode({
        requestId               = "$context.requestId"
        requestTime             = "$context.requestTime"
        httpMethod              = "$context.httpMethod"
        path                    = "$context.path"
        routeKey                = "$context.routeKey"
        status                  = "$context.status"
        responseLatency         = "$context.responseLatency"
        integrationStatus       = "$context.integration.status"
        integrationErrorMessage = "$context.integrationErrorMessage"
      })
    }
  }
}
