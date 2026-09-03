// Contrato HTTP do endpoint: os códigos de status que o Definition of Done cobra, sem tocar em RDS
// nem SSM. Os caminhos que dependem de banco (200 e 404) são provados pelo harness local
// (`scripts/invoke-local.ps1`) e, na nuvem, pelo `curl` no API Gateway.

import test from "node:test";
import assert from "node:assert/strict";

import { handler } from "../lambda/index.mjs";

const post = (body, extra = {}) =>
  handler({ requestContext: { http: { method: "POST", path: "/auth" } }, body, ...extra });

const parse = (response) => JSON.parse(response.body);

test("body ausente -> 400 invalid_request", async () => {
  const response = await post(undefined);
  assert.equal(response.statusCode, 400);
  assert.equal(parse(response).error, "invalid_request");
});

test("body que não é JSON -> 400, sem estourar exceção", async () => {
  const response = await post("cpf=98765432100");
  assert.equal(response.statusCode, 400);
  assert.equal(parse(response).error, "invalid_request");
});

test("JSON sem o campo cpf -> 400", async () => {
  assert.equal((await post(JSON.stringify({ documento: "98765432100" }))).statusCode, 400);
  assert.equal((await post(JSON.stringify({ cpf: 98765432100 }))).statusCode, 400, "número, não string");
});

test("cpf vazio ou só espaços -> invalid_request, não invalid_cpf", async () => {
  // Campo não preenchido não é documento errado. Os dois dão 400, mas o `error` é o que diz ao
  // cliente se ele esqueceu de mandar o CPF ou se digitou um inválido.
  for (const cpf of ["", "   ", "\t\n"]) {
    const response = await post(JSON.stringify({ cpf }));
    assert.equal(response.statusCode, 400, JSON.stringify(cpf));
    assert.equal(parse(response).error, "invalid_request", JSON.stringify(cpf));
  }
});

test("CPF do seed com dígitos inválidos -> 400 invalid_cpf", async () => {
  // "John Silva" (12345678901) foi semeado por SQL contornando o validador do domínio.
  const response = await post(JSON.stringify({ cpf: "12345678901" }));
  assert.equal(response.statusCode, 400);
  assert.equal(parse(response).error, "invalid_cpf");
});

test("aceita o body em base64, como o API Gateway pode entregar", async () => {
  const response = await post(Buffer.from(JSON.stringify({ cpf: "12345" })).toString("base64"), {
    isBase64Encoded: true,
  });
  // Chega ao validador de CPF (400 invalid_cpf) em vez de morrer no parse (invalid_request):
  // prova que o base64 foi decodificado.
  assert.equal(parse(response).error, "invalid_cpf");
});

test("a resposta é sempre JSON com content-type", async () => {
  const response = await post(undefined);
  assert.equal(response.headers["content-type"], "application/json");
  assert.doesNotThrow(() => JSON.parse(response.body));
});

test("a rejeição por CPF inválido não vaza o documento na mensagem", async () => {
  const response = await post(JSON.stringify({ cpf: "12345678901" }));
  assert.ok(!response.body.includes("12345678901"));
});
