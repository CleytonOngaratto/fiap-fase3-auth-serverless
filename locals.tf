locals {
  name = "${var.project}-auth"

  tags = {
    Project   = var.project
    ManagedBy = "terraform"
    Repo      = "fiap-fase3-auth-serverless"
  }

  # O provider marca TODO `aws_ssm_parameter` como sensitive, inclusive String comum: sem
  # `nonsensitive()` o plan esconde `integration_uri` e `DB_HOST` atrás de "(sensitive value)" —
  # justamente os campos que denunciam um lb-dns obsoleto — e o output `proxied_lb_dns` nem compila.
  vpc_id          = nonsensitive(data.aws_ssm_parameter.vpc_id.value)
  vpc_cidr        = nonsensitive(data.aws_ssm_parameter.vpc_cidr.value)
  private_subnets = split(",", nonsensitive(data.aws_ssm_parameter.private_subnets.value)) # StringList vem como CSV

  rds_host      = nonsensitive(data.aws_ssm_parameter.rds_endpoint.value)
  rds_port      = nonsensitive(data.aws_ssm_parameter.rds_port.value)
  rds_db_name   = nonsensitive(data.aws_ssm_parameter.rds_db_name.value)
  rds_username  = nonsensitive(data.aws_ssm_parameter.rds_username.value)
  rds_client_sg = nonsensitive(data.aws_ssm_parameter.rds_client_sg_id.value)

  lb_dns  = nonsensitive(data.aws_ssm_parameter.eks_lb_dns.value)
  app_url = "http://${local.lb_dns}"

  jwt_private_key_param = "/fase3/jwt/private-key"
  rds_password_param    = "/fase3/rds/password"
}
