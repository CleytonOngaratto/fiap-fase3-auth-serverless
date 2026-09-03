import jwt from "jsonwebtoken";

// O formato espelha o JwtTokenAdapter do repo 4 e é obrigação, não escolha: quem valida é o SmallRye
// da app, que não será alterada. Sem `aud` porque ela não configura `mp.jwt.verify.audiences`, e
// emitir audiência que ninguém verifica só simula uma checagem.
const CUSTOMER_GROUPS = ["CUSTOMER"];

// O AWS CLI no Windows traduz LF->CRLF na saída, e o `jsonwebtoken` recusa um PEM com `\r` — com um
// erro que parece falta de permissão.
const normalizePem = (pem) => pem.replace(/\r/g, "");

export function signCustomerToken({ cpf, privateKey, issuer, ttlSeconds, issuedAt }) {
  const iat = issuedAt ?? Math.floor(Date.now() / 1000);

  return jwt.sign(
    {
      sub: cpf,
      iss: issuer,
      groups: CUSTOMER_GROUPS,
      cpf,
      iat,
      exp: iat + ttlSeconds,
    },
    normalizePem(privateKey),
    { algorithm: "RS256" }
  );
}
