import { config, loadSecrets } from "./config.mjs";
import { isValidCpf, maskCpf } from "./cpf.mjs";
import { getPool, findCustomerByDocument } from "./db.mjs";
import { signCustomerToken } from "./jwt.mjs";

const json = (statusCode, body) => ({
  statusCode,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

function readCpf(event) {
  if (!event?.body) return null;
  const raw = event.isBase64Encoded ? Buffer.from(event.body, "base64").toString("utf8") : event.body;

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof parsed?.cpf !== "string") return null;

  // `""` volta como ausência, não como CPF inválido: o campo não foi preenchido, e a distinção
  // entre "faltou o campo" e "o documento está errado" é o que o contrato de resposta promete.
  const trimmed = parsed.cpf.trim();
  return trimmed === "" ? null : trimmed;
}

export const handler = async (event) => {
  const cpf = readCpf(event);

  if (cpf === null) {
    return json(400, { error: "invalid_request", message: "Body must be JSON with a 'cpf' field." });
  }
  if (!isValidCpf(cpf)) {
    // 400 e não 404: o documento é inválido em si, e responder "não encontrado" para um CPF que
    // nunca poderia existir transformaria este endpoint num oráculo de quais CPFs estão cadastrados.
    console.warn(JSON.stringify({ event: "cpf_rejected", cpf: maskCpf(cpf) }));
    return json(400, { error: "invalid_cpf", message: "CPF check digits are invalid." });
  }

  try {
    const secrets = await loadSecrets();
    const pool = getPool({ ...config.db, password: secrets.dbPassword });
    const customer = await findCustomerByDocument(pool, cpf);

    if (!customer) {
      // 404, não 401: nada foi rejeitado por falta de credencial — o recurso é que não existe.
      console.info(JSON.stringify({ event: "customer_not_found", cpf: maskCpf(cpf) }));
      return json(404, { error: "customer_not_found", message: "No customer with this CPF." });
    }

    const token = signCustomerToken({
      cpf,
      privateKey: secrets.privateKey,
      issuer: config.jwt.issuer,
      ttlSeconds: config.jwt.ttlSeconds,
    });

    console.info(
      JSON.stringify({ event: "token_issued", cpf: maskCpf(cpf), customerId: customer.id })
    );
    return json(200, {
      access_token: token,
      token_type: "Bearer",
      expires_in: config.jwt.ttlSeconds,
    });
  } catch (error) {
    // No CloudWatch: `AccessDeniedException` aqui é permissão da execution role (SSM/KMS), enquanto
    // um timeout seria NAT ou security group.
    console.error(JSON.stringify({ event: "internal_error", message: error.message }));
    return json(500, { error: "internal_error" });
  }
};
