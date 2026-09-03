variable "region" {
  description = "Região AWS. O Learner Lab só libera us-east-1 e us-west-2."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefixo de nome e valor da tag Project."
  type        = string
  default     = "fiap-fase3"
}

variable "lambda_role_name" {
  description = <<-EOT
    Execution role da função. Aqui É a LabRole, sem sufixo — quem usa role de sufixo gerado por
    CloudFormation é o EKS (repo 2). O Terraform só CONSOME a role: o Learner Lab não deixa criar.
  EOT
  type        = string
  default     = "LabRole"
}

variable "lambda_runtime" {
  description = <<-EOT
    Runtime da Lambda. Se a AWS já tiver bloqueado a criação neste runtime, o apply falha com
    "runtime is no longer supported" — troque para o managed runtime seguinte e reaplique.
  EOT
  type        = string
  default     = "nodejs22.x"
}

variable "lambda_memory_size" {
  description = "MB de memória. 128 fica apertado com o SDK do SSM carregado; a CPU escala junto."
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Segundos. Cobre o cold start com ENI na VPC + leitura do SSM + query no RDS."
  type        = number
  default     = 15
}

variable "jwt_issuer" {
  description = "Tem que ser IDÊNTICO ao mp.jwt.verify.issuer da app, senão o token é recusado."
  type        = string
  default     = "https://oficina-api.com"
}

variable "jwt_ttl_seconds" {
  description = "Validade do token do cliente. 3600 é o mesmo do token que a app assina."
  type        = number
  default     = 3600
}

variable "log_retention_days" {
  description = <<-EOT
    Retenção dos logs. Sem um log group explícito a Lambda cria o dela com retenção INFINITA, que
    o destroy não remove — e a conta acumula log group órfão a cada sessão do lab.
  EOT
  type        = number
  default     = 7
}

variable "enable_access_logs" {
  description = <<-EOT
    Access log da stage do API Gateway: é a evidência de que o Gateway roteia (útil no Bloco 6 e na
    banca). Se o lab negar a permissão, o apply falha com "Insufficient permissions to enable
    logging" — aí ponha false e siga; nada mais depende disto.
  EOT
  type        = bool
  default     = true
}
