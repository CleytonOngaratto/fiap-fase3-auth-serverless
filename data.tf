data "aws_ssm_parameter" "vpc_id" {
  name = "/fase3/vpc/id"
}

data "aws_ssm_parameter" "private_subnets" {
  name = "/fase3/vpc/private-subnets"
}

# O `PLAN-FASE3.md` registrava este parâmetro como órfão (publicado pelo repo 2, consumido por
# ninguém); é aqui que ele ganha o primeiro consumidor.
data "aws_ssm_parameter" "vpc_cidr" {
  name = "/fase3/vpc/cidr"
}

# Host puro: o repo 3 publica `.address`, não `.endpoint`. A porta vem no parâmetro ao lado.
data "aws_ssm_parameter" "rds_endpoint" {
  name = "/fase3/rds/endpoint"
}

data "aws_ssm_parameter" "rds_port" {
  name = "/fase3/rds/port"
}

data "aws_ssm_parameter" "rds_db_name" {
  name = "/fase3/rds/db-name"
}

data "aws_ssm_parameter" "rds_username" {
  name = "/fase3/rds/username"
}

data "aws_ssm_parameter" "rds_client_sg_id" {
  name = "/fase3/rds/client-sg-id"
}

# 🔴 Publicado pelo `cd.yml` do repo 4, por Terraform nenhum: nenhum `destroy` o apaga, e ele
# sobrevive entre sessões apontando para um ELB morto. O apply passa e o proxy nasce em 503.
# Rode o `workflow_dispatch` do repo 4 antes do apply daqui.
data "aws_ssm_parameter" "eks_lb_dns" {
  name = "/fase3/eks/lb-dns"
}

# `/fase3/rds/password` e `/fase3/jwt/private-key` NÃO entram aqui: um data source materializaria os
# dois em texto plano no state. A função os lê em runtime, cifrados.
data "aws_iam_role" "lambda" {
  name = var.lambda_role_name
}
