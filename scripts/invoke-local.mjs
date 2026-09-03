// Roda O MESMO handler que vai para a nuvem, com um evento sintético do API Gateway (payload 2.0),
// contra um Postgres local. Serve para separar dois problemas que, juntos, custam horas: o contrato
// do token e a rede da VPC. Se isto passa, o que sobra na nuvem é rede e permissão.
//
//   node scripts/invoke-local.mjs --cpf 98765432100
//
// Configuração por ambiente, os mesmos nomes que o Terraform escreve na função. Os dois overrides
// (DB_PASSWORD / JWT_PRIVATE_KEY) existem só aqui: o Terraform nunca os define.

const args = new Map();
for (let i = 2; i < process.argv.length; i += 2) {
  args.set(process.argv[i].replace(/^--/, ""), process.argv[i + 1]);
}

const cpf = args.get("cpf");
if (!cpf) {
  console.error("uso: node scripts/invoke-local.mjs --cpf <cpf> [--raw <body cru>]");
  process.exit(2);
}

// Defaults apontando para o docker-compose do repo 4 (porta 5433 no host, sem TLS).
const defaults = {
  DB_HOST: "localhost",
  DB_PORT: "5433",
  DB_NAME: "oficina_db",
  DB_USER: "postgres",
  DB_PASSWORD: "postgres",
  DB_SSL: "disable",
  JWT_ISSUER: "https://oficina-api.com",
  JWT_TTL_SECONDS: "3600",
  // Sem override de JWT_PRIVATE_KEY, a chave é buscada AQUI no SSM — de propósito: exercita o mesmo
  // caminho de leitura cifrada que a função usa na nuvem, com a credencial local do lab.
  JWT_PRIVATE_KEY_PARAM: "/fase3/jwt/private-key",
  DB_PASSWORD_PARAM: "/fase3/rds/password",
  AWS_REGION: "us-east-1",
};
for (const [key, value] of Object.entries(defaults)) {
  process.env[key] ??= value;
}

// Import dinâmico DEPOIS do ambiente: config.mjs lê process.env no carregamento do módulo.
const { handler } = await import("../lambda/index.mjs");

const response = await handler({
  version: "2.0",
  rawPath: "/auth",
  requestContext: { http: { method: "POST", path: "/auth" } },
  headers: { "content-type": "application/json" },
  body: args.get("raw") ?? JSON.stringify({ cpf }),
  isBase64Encoded: false,
});

console.log(JSON.stringify({ statusCode: response.statusCode, body: JSON.parse(response.body) }));

// O código de saída deixa o script chamador decidir sem precisar interpretar JSON.
process.exit(response.statusCode === 200 ? 0 : 1);
