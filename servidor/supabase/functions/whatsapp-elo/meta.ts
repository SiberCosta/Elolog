// WhatsApp Business Cloud API (Meta): validação da assinatura dos avisos e envio de mensagens de texto.

/** Confirma o cabeçalho X-Hub-Signature-256 (HMAC-SHA256 do corpo com o App Secret), em tempo constante. */
export async function assinaturaValida(corpo: string, cabecalho: string | null, segredo: string): Promise<boolean> {
  if (!cabecalho?.startsWith('sha256=') || !segredo) return false;
  const chave = await crypto.subtle.importKey('raw', new TextEncoder().encode(segredo), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', chave, new TextEncoder().encode(corpo)));
  const esperado = Array.from(mac, (b) => b.toString(16).padStart(2, '0')).join('');
  const recebido = cabecalho.slice(7).toLowerCase();
  if (recebido.length !== esperado.length) return false;
  let dif = 0;
  for (let i = 0; i < esperado.length; i++) dif |= esperado.charCodeAt(i) ^ recebido.charCodeAt(i);
  return dif === 0;
}

export interface Recebida { de: string; nome: string; texto: string; id: string }

/** Extrai as mensagens de texto (e respostas de botões) de um aviso da Meta. Ignora estados de entrega e outros tipos. */
export function mensagens(aviso: unknown): Recebida[] {
  const lista: Recebida[] = [];
  const entradas = (aviso as { entry?: { changes?: { value?: Record<string, unknown> }[] }[] })?.entry ?? [];
  for (const e of entradas) for (const ch of e.changes ?? []) {
    const v = ch.value ?? {};
    const contactos = (v.contacts as { wa_id?: string; profile?: { name?: string } }[] | undefined) ?? [];
    for (const m of (v.messages as Record<string, any>[] | undefined) ?? []) {
      const texto = m.type === 'text' ? m.text?.body : m.type === 'interactive' ? (m.interactive?.button_reply?.title ?? m.interactive?.list_reply?.title)
        : m.type === 'button' ? m.button?.text : null;
      const de = String(m.from ?? '').replace(/\D/g, '');
      if (!de) continue;
      const nome = contactos.find((c) => c.wa_id === m.from)?.profile?.name ?? '';
      lista.push({ de, nome: String(nome).slice(0, 80), texto: typeof texto === 'string' ? texto.slice(0, 1000) : '', id: String(m.id ?? '') });
    }
  }
  return lista;
}

/** Envia uma mensagem de texto. Só funciona dentro das 24 h seguintes à última mensagem do cliente (respostas de serviço). */
export async function enviarTexto(cfg: { token: string; phoneId: string; versao: string }, para: string, texto: string): Promise<boolean> {
  const r = await fetch(`https://graph.facebook.com/${cfg.versao}/${cfg.phoneId}/messages`, {
    method: 'POST', signal: AbortSignal.timeout(10_000),
    headers: { Authorization: `Bearer ${cfg.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ messaging_product: 'whatsapp', to: para, type: 'text', text: { body: texto.slice(0, 4000), preview_url: true } }),
  });
  if (!r.ok) console.error('whatsapp-elo: envio recusado', r.status, (await r.text()).slice(0, 200));
  return r.ok;
}
