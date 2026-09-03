// Segredo não entra em variável de ambiente: lá a chave privada apareceria no console da função e na
// captura de ambiente de qualquer agente. Só o NOME do parâmetro vem por env; o valor é lido cifrado.

import { SSMClient, GetParametersCommand } from "@aws-sdk/client-ssm";

const num = (value, fallback) => (value ? Number(value) : fallback);

export const config = {
  db: {
    host: process.env.DB_HOST,
    port: num(process.env.DB_PORT, 5432),
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    // Único ponto em que local e nuvem divergem de comportamento. Espelha o DB_SSLMODE da app.
    ssl: process.env.DB_SSL ?? "require",
  },
  jwt: {
    issuer: process.env.JWT_ISSUER,
    ttlSeconds: num(process.env.JWT_TTL_SECONDS, 3600),
  },
  params: {
    privateKey: process.env.JWT_PRIVATE_KEY_PARAM,
    dbPassword: process.env.DB_PASSWORD_PARAM,
  },
  // O Terraform NUNCA preenche estes: existem para o harness local rodar o handler sem um parâmetro
  // que só existe com o repo 3 aplicado, e são o plano B se a LabRole não tiver `kms:Decrypt`.
  overrides: {
    privateKey: process.env.JWT_PRIVATE_KEY,
    dbPassword: process.env.DB_PASSWORD,
  },
};

let cached;

async function fetchSecrets() {
  const wanted = [
    { key: "privateKey", name: config.params.privateKey },
    { key: "dbPassword", name: config.params.dbPassword },
  ].filter((entry) => !config.overrides[entry.key]);

  const resolved = { ...config.overrides };
  if (wanted.length === 0) return resolved;

  const client = new SSMClient({});
  const response = await client.send(
    new GetParametersCommand({ Names: wanted.map((e) => e.name), WithDecryption: true })
  );

  // Parâmetro ausente não é erro da API: volta em InvalidParameters, com HTTP 200. Sem esta checagem
  // a função seguiria com a chave `undefined` e falharia na assinatura, longe da causa.
  if (response.InvalidParameters?.length) {
    throw new Error(`Parametros ausentes no SSM: ${response.InvalidParameters.join(", ")}`);
  }

  for (const entry of wanted) {
    resolved[entry.key] = response.Parameters.find((p) => p.Name === entry.name)?.Value;
  }
  return resolved;
}

export function loadSecrets() {
  cached ??= fetchSecrets().catch((error) => {
    cached = undefined; // um erro transitório no cold start não pode envenenar o container inteiro
    throw error;
  });
  return cached;
}
