// Fingerprint da chave PÚBLICA correspondente a um PEM — aceita tanto a privada quanto a pública, e
// devolve o mesmo valor para as duas quando são o par. É assim que se prova que a chave com que a
// Lambda ASSINA é a que a aplicação usa para VALIDAR; sem isso o teste offline poderia rodar sobre
// pares diferentes e "provar" um contrato que na nuvem não vale.
//
//   node scripts/key-fingerprint.mjs <caminho-do-pem>
//
// Em Node e não em openssl por dois motivos concretos: o Git for Windows esconde o openssl em
// `usr\bin` (fora do PATH do PowerShell), e no PS 5.1 o stderr informativo do openssl ("writing RSA
// key") vira NativeCommandError, que derruba o script chamador mesmo com o comando bem-sucedido.

import { readFileSync } from "node:fs";
import { createHash, createPublicKey, createPrivateKey } from "node:crypto";

const path = process.argv[2];
if (!path) {
  console.error("uso: node scripts/key-fingerprint.mjs <arquivo.pem>");
  process.exit(2);
}

// O PEM local é CRLF e o do SSM é LF; normalizar deixa a comparação sobre a CHAVE, não sobre a
// codificação de linha do arquivo.
const pem = readFileSync(path, "utf8").replace(/\r/g, "");

let publicKey;
try {
  publicKey = pem.includes("PRIVATE KEY")
    ? createPublicKey(createPrivateKey(pem)) // deriva a pública da privada
    : createPublicKey(pem);
} catch (error) {
  console.error(`PEM invalido em ${path}: ${error.message}`);
  process.exit(1);
}

// SPKI DER: forma canônica da chave pública, então o hash não depende de espaçamento nem de tipo de
// encapsulamento do PEM de origem.
const der = publicKey.export({ type: "spki", format: "der" });
console.log(createHash("sha256").update(der).digest("hex"));
