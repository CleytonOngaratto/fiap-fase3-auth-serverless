// O contrato do token contra a validação que a app JÁ faz (SmallRye), sem rede e sem nuvem.
// A prova de ponta a ponta é o `scripts/verify-offline.ps1`, que joga um token destes na app real;
// aqui ficam as invariantes que não precisam de container para falhar.
//
// A verificação usa `node:crypto` cru, não o próprio `jsonwebtoken`: quem valida o token em
// produção é o SmallRye, em Java. Conferir a assinatura no primitivo prova que ela é um RS256 de
// verdade sobre `header.payload` — em vez de provar que a biblioteca concorda consigo mesma.

import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";

import { signCustomerToken } from "../lambda/jwt.mjs";

const keyPair = () =>
  generateKeyPairSync("rsa", {
    modulusLength: 2048,
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
    publicKeyEncoding: { type: "spki", format: "pem" },
  });

// Par efêmero: a chave de produção vive no SSM e nunca entra num teste.
const { privateKey, publicKey } = keyPair();

const ISSUER = "https://oficina-api.com";

const sign = (overrides = {}) =>
  signCustomerToken({ cpf: "98765432100", privateKey, issuer: ISSUER, ttlSeconds: 3600, ...overrides });

const decode = (segment) => JSON.parse(Buffer.from(segment, "base64url"));
const header = (token) => decode(token.split(".")[0]);
const claims = (token) => decode(token.split(".")[1]);

function signatureIsValid(token, key) {
  const [h, p, signature] = token.split(".");
  return verify("RSA-SHA256", Buffer.from(`${h}.${p}`), key, Buffer.from(signature, "base64url"));
}

test("assina em RS256 — o algoritmo que a app espera", () => {
  assert.equal(header(sign()).alg, "RS256");
  assert.equal(header(sign()).typ, "JWT");
});

test("a assinatura fecha com a pública do par", () => {
  assert.equal(signatureIsValid(sign(), publicKey), true);
});

test("a chave errada é rejeitada — a verificação não é decorativa", () => {
  assert.equal(signatureIsValid(sign(), keyPair().publicKey), false);
});

test("issuer e subject: mesmo formato do JwtTokenAdapter da app", () => {
  const token = claims(sign());
  assert.equal(token.iss, ISSUER); // mp.jwt.verify.issuer
  assert.equal(token.sub, "98765432100"); // papel do subject(username)
});

test("F10: groups=[CUSTOMER] e a claim cpf", () => {
  const token = claims(sign());
  // mp.jwt.verify.groups.path=groups — o array é o que vira @RolesAllowed("CUSTOMER") na app.
  assert.deepEqual(token.groups, ["CUSTOMER"]);
  assert.equal(token.cpf, "98765432100");
});

test("expira em 3600s, igual ao token que a app assina", () => {
  const token = claims(sign({ issuedAt: 1_700_000_000 }));
  assert.equal(token.iat, 1_700_000_000);
  assert.equal(token.exp - token.iat, 3600);
});

test("não emite aud — a app não configura mp.jwt.verify.audiences", () => {
  // Mandar audiência que ninguém verifica cria a ilusão de uma checagem que não existe.
  assert.equal(claims(sign()).aud, undefined);
});

test("um PEM contaminado com CRLF ainda assina", () => {
  // O AWS CLI no Windows traduz LF->CRLF na saída: um PEM que passou por `--output text` numa
  // máquina Windows chega com `\r`, e o jsonwebtoken recusa a chave com erro que parece falta de
  // permissão. Este teste é a rede de proteção da normalização em jwt.mjs.
  const crlf = privateKey.replace(/\n/g, "\r\n");
  assert.equal(signatureIsValid(sign({ privateKey: crlf }), publicKey), true);
});
