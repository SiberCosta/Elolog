// Elolog — copia todos os ficheiros dos «buckets» do Supabase Storage para uma pasta local (usado pela cópia de segurança diária).
// Uso: SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… node ferramentas/copia-armazenamento.mjs <pasta>
// Só usa a API REST do Storage (sem dependências). A chave de serviço nunca é escrita em disco nem mostrada.
import fs from 'node:fs/promises';
import path from 'node:path';

const URL_BASE = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const CHAVE = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const DESTINO = process.argv[2] || 'copia/armazenamento';
if (!/^(https:\/\/[a-z0-9-]+\.supabase\.co|http:\/\/localhost:\d+)$/.test(URL_BASE) || CHAVE.length < 20) {
  console.error('Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}
const cab = { Authorization: `Bearer ${CHAVE}`, apikey: CHAVE };

async function pedir(caminho, init = {}) {
  for (let tentativa = 1; ; tentativa++) {
    const r = await fetch(`${URL_BASE}/storage/v1/${caminho}`, { ...init, headers: { ...cab, ...(init.headers || {}) } });
    if (r.ok) return r;
    if (tentativa >= 3 || r.status < 500) throw new Error(`${r.status} em ${caminho.split('/').slice(0, 2).join('/')}`);
    await new Promise((ok) => setTimeout(ok, 1000 * tentativa));
  }
}

/** Lista recursivamente os ficheiros de um bucket (as pastas vêm sem id). */
async function listar(bucket, prefixo = '') {
  const ficheiros = [];
  for (let offset = 0; ; offset += 1000) {
    const r = await pedir(`object/list/${bucket}`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefix: prefixo, limit: 1000, offset, sortBy: { column: 'name', order: 'asc' } }) });
    const itens = await r.json();
    for (const it of itens) {
      const nome = prefixo ? `${prefixo}/${it.name}` : it.name;
      if (it.id) ficheiros.push(nome); else ficheiros.push(...(await listar(bucket, nome)));
    }
    if (itens.length < 1000) return ficheiros;
  }
}

const buckets = await (await pedir('bucket')).json();
await fs.mkdir(DESTINO, { recursive: true });
await fs.writeFile(path.join(DESTINO, 'buckets.json'), JSON.stringify(buckets.map(({ id, name, public: p, file_size_limit, allowed_mime_types }) =>
  ({ id, name, public: p, file_size_limit, allowed_mime_types })), null, 2));
let total = 0, bytes = 0;
for (const b of buckets) {
  for (const nome of await listar(b.id)) {
    const destino = path.join(DESTINO, b.id, ...nome.split('/'));
    if (!path.resolve(destino).startsWith(path.resolve(DESTINO) + path.sep)) continue;   // nunca escrever fora da pasta
    const r = await pedir(`object/${b.id}/${nome.split('/').map(encodeURIComponent).join('/')}`);
    const dados = Buffer.from(await r.arrayBuffer());
    await fs.mkdir(path.dirname(destino), { recursive: true });
    await fs.writeFile(destino, dados);
    total++; bytes += dados.length;
  }
}
console.log(`Armazenamento copiado: ${buckets.length} bucket(s), ${total} ficheiro(s), ${(bytes / 1048576).toFixed(1)} MB.`);
