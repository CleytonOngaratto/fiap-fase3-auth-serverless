<#
.SYNOPSIS
    GATE — roda ANTES de `terraform apply`. Custa segundos e evita descobrir na nuvem, com o
    relógio do laboratório correndo, o que dava para saber de graça.

.DESCRIPTION
    Este repositório é o ÚLTIMO da ordem de deploy (2 -> 3 -> 4 -> 1) e consome o contrato dos três
    outros. As quatro perguntas que valem dinheiro:

      1. a sessão do lab está viva?
      2. os repos 2, 3 e 4 publicaram o que este consome?
      3. o /fase3/eks/lb-dns aponta para um LoadBalancer QUE EXISTE?  <- falha em silêncio (503)
      4. o zip da Lambda vai sair com as dependências dentro?         <- falha em runtime
      5. a LabRole consegue ler o SecureString da chave RSA?          <- falha em runtime

.EXAMPLE
    .\scripts\preflight.ps1
#>

[CmdletBinding()]
param(
    [string]$Region = "us-east-1",
    [string]$RoleName = "LabRole",
    # Uma sessão do Learner Lab dura ~4h; um lb-dns mais velho que isso é de outra sessão.
    [int]$LbDnsMaxAgeHours = 4
)

$ErrorActionPreference = "Continue"
$script:Failed = $false

function Write-Head($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Ok($text) { Write-Host "  [OK]   $text" -ForegroundColor Green }
function Write-Warn2($text) { Write-Host "  [WARN] $text" -ForegroundColor Yellow }
function Write-Fail($text) { Write-Host "  [FAIL] $text" -ForegroundColor Red; $script:Failed = $true }

# No PS 5.1, redirecionar o stderr de um executável nativo embrulha cada linha num ErrorRecord
# (NativeCommandError), que com $ErrorActionPreference = 'Stop' derruba o script numa sondagem
# legítima. O 'Continue' local mantém o erro não-terminante e o 2>$null o descarta.
function Invoke-Probe {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string[]]$ProbeArgs)
    $ErrorActionPreference = "Continue"
    $out = & $Exe @ProbeArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return $out
}

$repoRoot = Split-Path $PSScriptRoot -Parent

Write-Head "1. Sessao AWS"
$identity = Invoke-Probe -Exe "aws" -ProbeArgs @("sts", "get-caller-identity", "--output", "json") | ConvertFrom-Json
if ($null -eq $identity) {
    Write-Fail "Sem credenciais validas. A sessao do Learner Lab dura ~4h: abra o lab, copie o bloco 'AWS Details' para ~/.aws/credentials e rode de novo."
    exit 1
}
Write-Ok "Conta $($identity.Account) · $($identity.Arn)"

Write-Head "2. Contrato de entrada (repos 2, 3 e 4 aplicados?)"
$contract = [ordered]@{
    "/fase3/vpc/id"              = "repo 2 (fiap-fase3-infra-k8s)"
    "/fase3/vpc/private-subnets" = "repo 2 (fiap-fase3-infra-k8s)"
    "/fase3/rds/endpoint"        = "repo 3 (fiap-fase3-infra-db)"
    "/fase3/rds/port"            = "repo 3 (fiap-fase3-infra-db)"
    "/fase3/rds/db-name"         = "repo 3 (fiap-fase3-infra-db)"
    "/fase3/rds/username"        = "repo 3 (fiap-fase3-infra-db)"
    "/fase3/rds/client-sg-id"    = "repo 3 (fiap-fase3-infra-db)"
    "/fase3/jwt/private-key"     = "bootstrap manual (sobrevive ao destroy)"
}
foreach ($name in $contract.Keys) {
    $value = Invoke-Probe -Exe "aws" -ProbeArgs @("ssm", "get-parameter", "--name", $name, "--region", $Region, "--query", "Parameter.Value", "--output", "text")
    if ($value) {
        # A chave RSA nao vai para a tela; so o tamanho, que ja denuncia parametro truncado.
        $shown = if ($name -like "*jwt*") { "<$(($value -join "`n").Length) chars>" } else { $value }
        Write-Ok "$name = $shown"
    }
    else {
        Write-Fail "$name AUSENTE — quem publica: $($contract[$name]). Ordem de deploy: 2 -> 3 -> 4 -> 1."
    }
}

Write-Head "3. /fase3/eks/lb-dns aponta para um LoadBalancer VIVO?"

# 🔴 A armadilha central deste bloco. Este parametro e publicado pelo `cd.yml` do repo 4, por
# NENHUM Terraform — entao nenhum `destroy` o apaga, e ele sobrevive entre sessoes apontando para um
# ELB morto. O `terraform apply` daqui passa, e o ANY /{proxy+} nasce devolvendo 503: o parametro
# EXISTIR faz parecer que esta tudo certo. Conferimos a data E sondamos o ELB de verdade.
$lb = Invoke-Probe -Exe "aws" -ProbeArgs @("ssm", "get-parameter", "--name", "/fase3/eks/lb-dns", "--region", $Region, "--query", "Parameter.[Value,LastModifiedDate]", "--output", "text")
if (-not $lb) {
    Write-Fail "/fase3/eks/lb-dns AUSENTE — rode o workflow_dispatch do cd.yml no repo 4 (fiap-fase3-app)."
}
else {
    $parts = ($lb -join " ") -split "\s+"
    $lbDns = $parts[0]
    $modified = [datetime]::Parse($parts[1])
    $ageHours = [math]::Round(((Get-Date) - $modified).TotalHours, 1)

    if ($ageHours -gt $LbDnsMaxAgeHours) {
        Write-Warn2 "publicado ha $ageHours h ($modified) — mais que uma sessao do lab. Provavelmente e lixo da sessao anterior."
    }
    else {
        Write-Ok "publicado ha $ageHours h ($modified)"
    }

    # A sondagem e o que decide: data velha com ELB vivo passa, data nova com ELB morto reprova.
    $health = "http://$lbDns/carworkshop/v1/q/health/ready"
    $code = Invoke-Probe -Exe "curl.exe" -ProbeArgs @("-s", "-o", "NUL", "-m", "15", "-w", "%{http_code}", $health)
    if ($code -eq "200") {
        Write-Ok "$lbDns responde 200 em /q/health/ready — o proxy vai nascer apontando para algo vivo"
    }
    else {
        Write-Fail "$lbDns NAO responde (codigo '$code'). O ANY /{proxy+} nasceria devolvendo 503."
        Write-Host "         Rode o workflow_dispatch do cd.yml no repo 4 e repita este preflight." -ForegroundColor Red
    }
}

Write-Head "4. Zip da Lambda tera as dependencias?"

# O archive_file empacota o que ESTA NO DISCO no momento do plan. Sem node_modules, o apply fica
# verde e a funcao quebra na primeira invocacao com `Cannot find module 'pg'`.
$modules = Join-Path $repoRoot "lambda/node_modules"
if (Test-Path (Join-Path $modules "pg")) {
    Write-Ok "lambda/node_modules presente (pg, jsonwebtoken, @aws-sdk/client-ssm)"
}
else {
    Write-Fail "lambda/node_modules AUSENTE ou incompleto — rode:  npm ci --omit=dev --prefix lambda"
}

Write-Head "5. A LabRole consegue ler a chave RSA cifrada?"

# A funcao le /fase3/jwt/private-key (SecureString) COMO A LABROLE. Tudo o que foi provado ate aqui
# usou a credencial de console do lab, que e outra identidade — entao esta permissao e premissa,
# nao fato. Se faltar, o sintoma e AccessDeniedException no CloudWatch e HTTP 500 na borda; timeout
# seria NAT/security group. Duas tentativas, da mais provavel para a menos.
$roleArn = "arn:aws:iam::$($identity.Account):role/$RoleName"
$simulated = Invoke-Probe -Exe "aws" -ProbeArgs @(
    "iam", "simulate-principal-policy", "--policy-source-arn", $roleArn,
    "--action-names", "ssm:GetParameters", "kms:Decrypt",
    "--query", "EvaluationResults[].[EvalActionName,EvalDecision]", "--output", "text")

if ($simulated) {
    $denied = @($simulated | Where-Object { $_ -notmatch "allowed" })
    if ($denied.Count -eq 0) { Write-Ok "simulate-principal-policy: ssm:GetParameters e kms:Decrypt permitidos para $RoleName" }
    else { Write-Fail "$RoleName SEM permissao: $($denied -join '; ') — ver 'Plano B' no README." }
}
else {
    # A trust policy da LabRole confia em servicos (lambda.amazonaws.com), nao no principal voclabs
    # do console, entao esta segunda tentativa costuma ser negada tambem. Vale o custo: e de graca.
    $assumed = Invoke-Probe -Exe "aws" -ProbeArgs @(
        "sts", "assume-role", "--role-arn", $roleArn, "--role-session-name", "fase3-preflight",
        "--query", "Credentials.AccessKeyId", "--output", "text")
    if ($assumed) { Write-Warn2 "simulate negado, mas o assume-role funciona — teste manual descrito no README." }
    else {
        Write-Warn2 "iam:SimulatePrincipalPolicy e sts:AssumeRole negados ao seu usuario do lab (esperado)."
        Write-Host "         RISCO EM ABERTO: se a LabRole nao tiver kms:Decrypt, /auth devolve 500 e o" -ForegroundColor Yellow
        Write-Host "         CloudWatch da funcao mostra AccessDeniedException. Plano B no README." -ForegroundColor Yellow
    }
}

Write-Head "6. backend.hcl"
$backendPath = Join-Path $repoRoot "backend.hcl"
if (Test-Path $backendPath) {
    Write-Ok "backend.hcl ja existe"
}
else {
    Write-Warn2 "backend.hcl ausente. Crie com o conteudo abaixo (o bucket veio do bootstrap do repo 2):"
    Write-Host ""
    Write-Host "bucket       = `"fiap-fase3-tfstate-$($identity.Account)`"" -ForegroundColor DarkGray
    Write-Host "key          = `"auth-serverless/terraform.tfstate`"" -ForegroundColor DarkGray
    Write-Host "region       = `"$Region`"" -ForegroundColor DarkGray
    Write-Host "use_lockfile = true" -ForegroundColor DarkGray
    Write-Host "encrypt      = true" -ForegroundColor DarkGray
}

Write-Host ""
if ($script:Failed) {
    Write-Host "PREFLIGHT REPROVADO — resolva os [FAIL] acima antes do apply." -ForegroundColor Red
    exit 1
}
Write-Host "PREFLIGHT OK — pode seguir para terraform init/plan/apply." -ForegroundColor Green
