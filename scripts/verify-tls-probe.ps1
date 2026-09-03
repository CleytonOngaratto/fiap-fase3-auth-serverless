<#
.SYNOPSIS
    Reproduz LOCALMENTE, por US$ 0,00, o modo de falha nº 1 deste bloco: o `pg` do Node contra um
    PostgreSQL que exige TLS.

.DESCRIPTION
    O RDS deste projeto tem `rds.force_ssl = 1` (parameter group default do Postgres 16, verificado
    no Bloco 3). O `pg` do Node nasce com `ssl: false` e leva RECUSA do servidor, com um erro que
    parece security group:

        no pg_hba.conf entry for host "10.0.x.x", user "postgres", database "oficina_db",
        no encryption

    O `verify-offline.ps1` roda com DB_SSL=disable contra o Postgres do compose — ou seja, deixa
    justamente este caminho sem exercitar. Esta sonda fecha o buraco: sobe um Postgres descartável
    que se comporta como o RDS e prova as DUAS direções.

    Duas armadilhas de Windows que a mecânica evita:

    * bind mount NÃO serve. O PostgreSQL recusa iniciar se a chave privada tiver permissão de grupo
      ou de outros (`FATAL: private key file ... has group or world access`), e no Docker Desktop os
      arquivos montados aparecem como root/0777 — nenhum chmod do host atravessa. Por isso o par vai
      para dentro da IMAGEM, onde o chmod 600 vive numa layer.
    * `ssl=on` sozinho não força nada. O pg_hba default da imagem aceita conexão em claro, e o
      primeiro caso passaria quando deveria falhar. O pg_hba também é assado na imagem, só com
      entradas `hostssl`, e apontado por `-c hba_file=`.

.EXAMPLE
    .\scripts\verify-tls-probe.ps1
#>

[CmdletBinding()]
param(
    [int]$Port = 55432,
    [string]$ContainerName = "fase3-tls-probe"
)

# 'Continue', não 'Stop': no PS 5.1 o stderr de um executável nativo vira NativeCommandError, e o
# progresso do `docker build` ou um aviso do Node derrubariam o script com o comando bem-sucedido.
$ErrorActionPreference = "Continue"
$script:Failed = $false

function Write-Head($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Ok($text) { Write-Host "  [OK]   $text" -ForegroundColor Green }
function Write-Fail($text) { Write-Host "  [FAIL] $text" -ForegroundColor Red; $script:Failed = $true }

# `"$_"` converte cada ErrorRecord em string: sem isso um objeto de erro no array volta a se
# comportar como erro mais adiante no pipeline.
function Invoke-Native {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string[]]$NativeArgs)
    $ErrorActionPreference = "Continue"
    $out = & $Exe @NativeArgs 2>&1 | ForEach-Object { "$_" }
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = @($out); Text = ($out -join "`n") }
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$build = Join-Path $env:TEMP "fase3-tls-probe"
Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $build | Out-Null

Write-Head "1. Certificado self-signed para o servidor"

# O Postgres precisa de um X.509, que o `node:crypto` nao emite — entao aqui o openssl e a
# ferramenta certa. O cuidado e outro: resolver o caminho (o Git for Windows o esconde em `usr\bin`,
# fora do PATH do PowerShell) e capturar o stderr, que e informativo mas vira NativeCommandError.
$openssl = $null
foreach ($candidate in @(
        "openssl.exe",
        "$env:ProgramFiles\Git\usr\bin\openssl.exe",
        "${env:ProgramFiles(x86)}\Git\usr\bin\openssl.exe",
        "$env:LOCALAPPDATA\Programs\Git\usr\bin\openssl.exe")) {
    $found = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($found) { $openssl = $found.Source; break }
}
if (-not $openssl) { Write-Fail "openssl nao encontrado (o Git for Windows traz um em usr\bin)"; exit 1 }

$req = Invoke-Native -Exe $openssl -NativeArgs @(
    "req", "-new", "-x509", "-days", "1", "-nodes", "-newkey", "rsa:2048",
    "-keyout", (Join-Path $build "server.key"), "-out", (Join-Path $build "server.crt"),
    "-subj", "/CN=localhost")
if (-not (Test-Path (Join-Path $build "server.crt"))) {
    Write-Fail "openssl nao gerou o certificado"
    $req.Lines | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    exit 1
}
Write-Ok "server.crt / server.key gerados no scratchpad"

Write-Head "2. Imagem descartavel que se comporta como o RDS"

# Sem NENHUMA linha `host`: e o que faz o servidor recusar conexao em claro, igual ao rds.force_ssl.
# A linha `local` fica porque o entrypoint da imagem inicializa o banco pelo socket unix.
@"
local   all   all               trust
hostssl all   all   all         scram-sha-256
"@ | Set-Content -Path (Join-Path $build "pg_hba.conf") -Encoding ascii

# COPY + chmod DENTRO da imagem: em bind mount do Docker Desktop no Windows os arquivos aparecem
# como root/0777 e o Postgres recusa iniciar por "has group or world access". Na layer, funciona.
@"
FROM postgres:16
COPY server.crt server.key pg_hba.conf /etc/pg/
RUN chown postgres:postgres /etc/pg/* && chmod 600 /etc/pg/server.key
"@ | Set-Content -Path (Join-Path $build "Dockerfile") -Encoding ascii

$image = Invoke-Native -Exe "docker" -NativeArgs @("build", "-q", "-t", "fase3-tls-probe:local", $build)
if ($image.ExitCode -ne 0) {
    Write-Fail "docker build falhou — o Docker Desktop esta rodando?"
    $image.Lines | Select-Object -Last 8 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    exit 1
}
Write-Ok "imagem construida (permissao da chave na layer, nao em bind mount)"

Write-Head "3. Subir o servidor"
Invoke-Native -Exe "docker" -NativeArgs @("rm", "-f", $ContainerName) | Out-Null
$run = Invoke-Native -Exe "docker" -NativeArgs @(
    "run", "-d", "--name", $ContainerName,
    "-e", "POSTGRES_PASSWORD=postgres", "-e", "POSTGRES_DB=oficina_db",
    "-p", "${Port}:5432", "fase3-tls-probe:local",
    "-c", "ssl=on", "-c", "ssl_cert_file=/etc/pg/server.crt", "-c", "ssl_key_file=/etc/pg/server.key",
    "-c", "hba_file=/etc/pg/pg_hba.conf")
if ($run.ExitCode -ne 0) {
    Write-Fail "docker run falhou"
    $run.Lines | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    exit 1
}

try {
    $up = $false
    foreach ($attempt in 1..40) {
        Start-Sleep -Seconds 2
        $log = (Invoke-Native -Exe "docker" -NativeArgs @("logs", $ContainerName)).Text
        if ($log -match "has group or world access") {
            Write-Fail "o Postgres recusou a chave por permissao — a imagem nao aplicou o chmod"
            break
        }
        # O entrypoint sobe um servidor TEMPORARIO durante a inicializacao e imprime a mesma linha;
        # so a que vem depois de "ready for start up" e o servidor definitivo, ja com o nosso pg_hba.
        if ($log -match "ready for start up" -and $log -match "database system is ready to accept connections") {
            $up = $true; break
        }
    }
    if (-not $up) { Write-Fail "servidor nao ficou pronto"; exit 1 }
    Write-Ok "postgres com ssl=on e pg_hba so-hostssl na porta $Port"

    # Tabela minima que o handler consulta. `document` e o unico campo que importa para a sonda.
    $seed = Invoke-Native -Exe "docker" -NativeArgs @(
        "exec", $ContainerName, "psql", "-U", "postgres", "-d", "oficina_db", "-c",
        "CREATE TABLE customers (id int8 PRIMARY KEY, document varchar(255), name varchar(255)); INSERT INTO customers VALUES (2, '98765432100', 'Maria Santos');")
    if ($seed.ExitCode -ne 0) {
        Write-Fail "nao consegui semear a tabela"
        $seed.Lines | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
        exit 1
    }

    $env:DB_HOST = "localhost"
    $env:DB_PORT = "$Port"
    $env:DB_NAME = "oficina_db"
    $env:DB_USER = "postgres"
    $env:DB_PASSWORD = "postgres"
    $env:AWS_REGION = "us-east-1"

    Push-Location $repoRoot
    try {
        Write-Head "4. DB_SSL=disable -> tem que FALHAR como na nuvem"
        $env:DB_SSL = "disable"
        # Processo separado por caso: o pool do `pg` vive no escopo do modulo e seria reaproveitado.
        $plain = Invoke-Native -Exe "node" -NativeArgs @("scripts/invoke-local.mjs", "--cpf", "98765432100")
        if ($plain.Text -match "no encryption|no pg_hba.conf entry") {
            Write-Ok "recusado com 'no pg_hba.conf entry ... no encryption' — MESMO erro do RDS"
        }
        else {
            Write-Fail "conectou sem TLS: o servidor de teste nao esta forcando SSL, a sonda daria falso verde."
            $plain.Lines | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
        }

        Write-Head "5. DB_SSL=require -> tem que CONECTAR (o caminho que vai para a nuvem)"
        $env:DB_SSL = "require"
        $tls = Invoke-Native -Exe "node" -NativeArgs @("scripts/invoke-local.mjs", "--cpf", "98765432100")
        if ($tls.ExitCode -eq 0 -and $tls.Text -match '"statusCode":200') {
            Write-Ok "conectou por TLS e emitiu o token — ssl rejectUnauthorized:false funciona"
        }
        else {
            Write-Fail "nao conectou com TLS habilitado."
            $tls.Lines | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
        }
    }
    finally { Pop-Location }
}
finally {
    Invoke-Native -Exe "docker" -NativeArgs @("rm", "-f", $ContainerName) | Out-Null
    Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($script:Failed) {
    Write-Host "SONDA DE TLS REPROVADA." -ForegroundColor Red
    exit 1
}
Write-Host "SONDA DE TLS OK — o caminho TLS do pg esta provado sem gastar sessao de lab." -ForegroundColor Green
