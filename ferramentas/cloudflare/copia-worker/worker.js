/* Elolog — Worker do Cloudflare para a cópia de segurança diária (v140). Plano gratuito.
   Todas as noites (Cron Trigger) pede ao Supabase a cópia dos dados, já cifrada pela função «copia-dados», e grava-a no R2.
   Guarda 30 dias; as mais antigas são removidas. O Worker nunca vê os dados em claro nem a senha da cópia.
   Ligações (Settings › Bindings): R2 bucket com o nome de variável COPIAS.  Segredo (Settings › Variables): COPIA_TOKEN.
   O endereço público do Worker não revela nada; as cópias veem-se no painel do R2. */
const FUNCAO = "https://wcggcpdiswbzrdpwgdpb.supabase.co/functions/v1/copia-dados", DIAS = 30, PASTA = "elolog/";

async function copiar(env) {
  const r = await fetch(FUNCAO, { method: "POST", headers: { "x-copia-token": env.COPIA_TOKEN } });
  if (!r.ok) throw new Error(`O Supabase respondeu ${r.status}: ${(await r.text()).slice(0, 200)}`);
  const dados = await r.arrayBuffer(), nome = `${PASTA}${new Date().toISOString().slice(0, 10)}.elolog-copia`;
  await env.COPIAS.put(nome, dados, { httpMetadata: { contentType: "application/octet-stream" }, customMetadata: { registos: r.headers.get("X-Elolog-Registos") || "" } });
  const limite = Date.now() - DIAS * 864e5, antigas = [];
  let lista = await env.COPIAS.list({ prefix: PASTA });
  for (;;) { for (const o of lista.objects) if (o.uploaded.getTime() < limite) antigas.push(o.key); if (!lista.truncated) break; lista = await env.COPIAS.list({ prefix: PASTA, cursor: lista.cursor }); }
  if (antigas.length) await env.COPIAS.delete(antigas.slice(0, 1000));
  return { nome, bytes: dados.byteLength, removidas: antigas.length };
}

export default {
  async scheduled(evento, env, ctx) { ctx.waitUntil(copiar(env).then(x => console.log("Cópia guardada", JSON.stringify(x)))); },
  /* o endereço público do Worker não mostra nada sobre as cópias: veja-as em R2 › bucket, ou nos registos do Worker */
  async fetch() { return new Response("Elolog: serviço interno.", { status: 404, headers: { "content-type": "text/plain; charset=utf-8" } }); }
};
