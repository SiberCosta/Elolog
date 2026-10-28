// Assistente ELO no WhatsApp: decide a resposta a cada mensagem. Funções puras (sem rede), testadas em Node.
export interface Conversa { passo?: string | null; humano_desde?: string | null; dados?: Record<string, unknown> }
export interface Encomenda { autorizado: boolean; codigo?: string; estado?: string; origem?: string; destino?: string; data_prevista?: string | null; prestador?: string | null }
export type Acao =
  | { tipo: 'responder'; texto: string; passo: string | null }
  | { tipo: 'estado'; codigo: string }
  | { tipo: 'humano'; texto: string }
  | { tipo: 'silencio' };

const SITE = 'https://www.elolog.pt';
export const ESTADOS: Record<string, string> = {
  aprovacao: 'Em aprovação pelo prestador', agendamento: 'Recolha agendada', recolha: 'Em recolha', armazenamento: 'No armazém',
  expedicao: 'Em expedição', em_transito: 'Em trânsito', destino: 'Chegou ao destino', entregue: 'Entregue', cancelada: 'Cancelada',
};

export const MENU = [
  'Olá! Sou o *ELO*, o assistente da Elolog. 👋', '',
  'Responda com o número:',
  '*1* · Estado de uma encomenda',
  '*2* · Simular um envio (preços)',
  '*3* · Falar com a equipa',
  '*4* · Contactos e horário',
  '*5* · Ser prestador na Elolog',
].join('\n');

export const normalizar = (t: string) => t.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim();
export const codigoEm = (t: string) => (t.toUpperCase().match(/\bTR-?\s?(\d{4})-?\s?(\d{6})\b/) ?? null);

/** Decide o que fazer com uma mensagem de texto. */
export function interpretar(texto: string, c: Conversa, agora = Date.now()): Acao {
  const q = normalizar(texto);
  const cod = codigoEm(texto);
  if (cod) return { tipo: 'estado', codigo: `TR-${cod[1]}-${cod[2]}` };
  const voltar = /^(menu|inicio|0|ola|oi|bom dia|boa tarde|boa noite)\b/.test(q);
  if (c.humano_desde && agora - Date.parse(c.humano_desde) < 12 * 3600e3 && !voltar) {
    if (c.dados?.avisado) return { tipo: 'silencio' };
    return { tipo: 'responder', passo: 'humano', texto: 'A equipa Elolog já foi avisada e vai responder-lhe em breve. Se quiser voltar ao assistente, escreva *MENU*.' };
  }
  if (voltar || !q) return { tipo: 'responder', texto: MENU, passo: null };
  if (q === '1' || /\b(estado|encomenda|rastre|seguir|onde esta|tracking)/.test(q))
    return { tipo: 'responder', passo: 'codigo', texto: 'Indique o código da encomenda (por exemplo *TR-2026-000123*). Por segurança, só mostro o estado se escrever a partir do número de telemóvel associado à encomenda.' };
  if (c.passo === 'codigo') return { tipo: 'responder', passo: 'codigo', texto: 'Não reconheci o código. Tem o formato *TR-AAAA-NNNNNN* e aparece no email de confirmação. Ou escreva *MENU*.' };
  if (q === '2' || /\b(simul|preco|cotac|orcament|quanto custa|enviar)/.test(q))
    return { tipo: 'responder', passo: null, texto: `Pode simular o envio e comparar propostas de prestadores verificados aqui:\n${SITE}/site/simulador.html\n\nDemora 2 minutos e é sem compromisso.` };
  if (q === '3' || /\b(pessoa|humano|atendente|equipa|falar com|reclama|problema|ajuda)/.test(q))
    return { tipo: 'humano', texto: 'Combinado: avisei a equipa Elolog, que lhe responde em breve (dias úteis, 9h–18h). Se quiser, descreva já aqui o assunto.' };
  if (q === '4' || /\b(contact|horario|email|telefone|morada)/.test(q))
    return { tipo: 'responder', passo: null, texto: `📧 contacto@elolog.pt\n🌐 ${SITE}\n🕘 Dias úteis, 9h–18h (hora de Lisboa)\n\nEscreva *3* para falar com a equipa.` };
  if (q === '5' || /\b(prestador|transitari|parceir|empresa de transport|registar empresa)/.test(q))
    return { tipo: 'responder', passo: null, texto: `Registe a sua empresa em ${SITE}/app/prestador.html — depois da aprovação recebe pedidos de clientes e gere encomendas, tarifas e pagamentos na plataforma.` };
  return { tipo: 'responder', passo: null, texto: `Não percebi bem. 🙂\n\n${MENU}` };
}

/** Texto da resposta ao pedido de estado. */
export function textoEstado(e: Encomenda, codigo: string): string {
  if (!e.autorizado || !e.estado) return `Não encontrei a encomenda *${codigo}* associada a este número. Confirme o código ou consulte-a na Área de Cliente: ${SITE}/app/area-cliente.html`;
  const data = e.data_prevista ? `\n📅 Data prevista: ${String(e.data_prevista).split('-').reverse().join('/')}` : '';
  return `📦 *${e.codigo}* · ${e.origem} → ${e.destino}\nEstado: *${ESTADOS[e.estado] ?? e.estado}*${e.prestador ? `\nPrestador: ${e.prestador}` : ''}${data}\n\nMais detalhes na Área de Cliente: ${SITE}/app/area-cliente.html`;
}
