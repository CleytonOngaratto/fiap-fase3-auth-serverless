output "api_endpoint" {
  description = "URL base do API Gateway (stage $default, sem prefixo de stage)."
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "auth_endpoint" {
  description = "POST aqui com {\"cpf\":\"...\"} para receber o token do cliente."
  value       = "${aws_apigatewayv2_api.main.api_endpoint}/auth"
}

output "app_endpoint" {
  description = "Base das rotas da aplicação pelo Gateway (ex.: <isto>/tracking/1 com o Bearer)."
  value       = "${aws_apigatewayv2_api.main.api_endpoint}/carworkshop/v1"
}

# Conferir DEPOIS do apply: se este hostname não for o ELB desta sessão, o /{proxy+} devolve 503 e
# o parâmetro obsoleto do repo 4 é a causa.
output "proxied_lb_dns" {
  description = "Hostname do LoadBalancer para onde o /{proxy+} aponta, como lido do SSM no apply."
  value       = local.lb_dns
}

output "lambda_function_name" {
  description = "Nome da função — use em `aws logs tail` para ver o motivo real de um 500."
  value       = aws_lambda_function.auth.function_name
}

output "lambda_log_group" {
  description = "Onde o AccessDeniedException do SSM/KMS apareceria, se a execution role não bastar."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "lambda_security_group_id" {
  description = "SG criado aqui (saída 443). O acesso ao RDS vem do crachá do repo 3, não deste."
  value       = aws_security_group.lambda.id
}
