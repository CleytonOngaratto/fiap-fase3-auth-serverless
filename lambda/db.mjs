import pg from "pg";

// 🔴 O `pg` nasce com `ssl: false` e o RDS tem `rds.force_ssl = 1`: sem TLS o servidor recusa com
// "no pg_hba.conf entry ... no encryption", que parece security group. `rejectUnauthorized: false`
// cifra sem verificar a CA — o equivalente exato do `?sslmode=require` que a app já usa.
function sslOption(mode) {
  return mode === "disable" ? false : { rejectUnauthorized: false };
}

let pool;

export function getPool({ host, port, database, user, password, ssl }) {
  pool ??= new pg.Pool({
    host,
    port,
    database,
    user,
    password,
    ssl: sslOption(ssl),
    max: 1, // cada container atende uma invocação por vez; mais que isso só ocupa conexão no RDS
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 30000,
  });
  return pool;
}

// Sem filtro de estado por F7 (o requisito é existência) e porque `customers` não tem coluna de
// status nem de soft delete — o V2.0.0 só adicionou `deleted` em `work_orders`.
export async function findCustomerByDocument(client, document) {
  const { rows } = await client.query(
    "SELECT id, name FROM customers WHERE document = $1 LIMIT 1",
    [document]
  );
  return rows[0] ?? null;
}
