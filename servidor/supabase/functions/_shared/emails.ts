// Modelos dos e-mails da Elolog. Sem dependências: corre igual em Deno e em Node (testes).
// REGRAS: tudo o que vem de pessoas (motivos, títulos) é escapado; nunca se incluem palavras-passe, PIN nem segredos;
// os e-mails só avisam e apontam para a aplicação (os dados ficam lá, atrás do início de sessão).

export interface ItemEmail {
  id: string; notificacao_id?: string; destinatario: string; destino: 'plataforma' | 'empresa' | 'utilizador';
  tipo: string; titulo: string; corpo: string | null; tentativas?: number;
}
export interface EmailPronto { assunto: string; texto: string; html: string }

export const escaparHtml = (v: string): string =>
  v.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

/** Assunto numa só linha (sem quebras de linha: evita injeção de cabeçalhos) e com limite de tamanho. */
export function limparAssunto(v: string, max = 150): string {
  const linha = v.replace(/[\p{Cc}\p{Zl}\p{Zp}]+/gu, ' ').replace(/\s+/g, ' ').trim();
  return linha.length > max ? linha.slice(0, max - 1) + '…' : linha;
}

const ESTADOS: Record<string, string> = {
  aprovacao: 'Em aprovação', agendamento: 'Agendada', recolha: 'Em recolha', armazenamento: 'Em armazém',
  expedicao: 'Em expedição', em_transito: 'Em trânsito', destino: 'No destino', entregue: 'Entregue', cancelada: 'Cancelada',
};

interface Modelo { intro: string; mostrarCorpo?: (corpo: string) => string }

const MODELOS: Record<string, Modelo> = {
  novo_prestador: { intro: 'Foi submetido um novo pedido de inscrição de prestador. Abra o painel da administração para o analisar.' },
  pedido_subscricao: { intro: 'Há um novo pedido de subscrição. Confirme o pagamento declarado no painel da administração antes de autorizar a empresa.' },
  pedido_cliente: { intro: 'Um cliente fez um pedido que precisa da sua decisão. Abra o painel da administração.' },
  apoio: { intro: 'Há um novo pedido de apoio ou reclamação à espera de resposta. Abra o painel da administração.' },
  nova_simulacao: { intro: 'Recebeu um novo pedido de simulação de um cliente. Entre na Área de Prestador para o analisar e responder.' },
  empresa_aprovada: { intro: 'A sua empresa foi autorizada na plataforma. Já pode iniciar sessão: primeiro com os dados da empresa e depois com a sua conta.' },
  empresa_recusada: { intro: 'A administração tomou uma decisão sobre a sua empresa.', mostrarCorpo: c => `Motivo indicado: ${c}` },
  pagamento_confirmado: { intro: 'Confirmámos o pagamento da subscrição da sua empresa.', mostrarCorpo: c => `Nota: ${c}` },
  simulacao_aceite: { intro: 'O prestador aceitou o seu pedido.', mostrarCorpo: c => c },
  simulacao_recusada: { intro: 'O prestador não pôde aceitar o seu pedido.', mostrarCorpo: c => `Motivo indicado: ${c}` },
  fatura_emitida: { intro: 'A empresa emitiu a fatura da sua encomenda. Pode descarregá-la em Pagamentos e documentos.', mostrarCorpo: c => c },
  pagamento_recebido: { intro: 'Foi registado um pagamento online.', mostrarCorpo: c => c },
  estado_encomenda: { intro: 'A sua encomenda mudou de estado.', mostrarCorpo: c => `Novo estado: ${ESTADOS[c] ?? c}` },
};

/** Endereço da aplicação para o botão. Só aceita http(s); para a administração acrescenta o acesso administrativo. */
export function ligacao(appUrl: string, destino: ItemEmail['destino']): string | null {
  let url: URL;
  try { url = new URL(appUrl); } catch { return null; }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
  if (destino === 'plataforma') url.searchParams.set('acesso', 'administracao');
  return url.toString();
}

export function renderizar(item: ItemEmail, appUrl: string): EmailPronto {
  const modelo = MODELOS[item.tipo];
  const titulo = limparAssunto(item.titulo, 120) || 'Notificação Elolog';
  const corpo = (item.corpo ?? '').trim().slice(0, 500);
  const intro = modelo ? modelo.intro : titulo;
  const detalhe = corpo ? (modelo?.mostrarCorpo ? modelo.mostrarCorpo(corpo) : corpo) : '';
  const url = ligacao(appUrl, item.destino);

  const rodape = 'Mensagem automática da Elolog. Não responda a este e-mail. Se não reconhece esta mensagem, ignore-a.';
  const texto = [
    'Olá,', '', titulo, '', intro, ...(detalhe ? ['', detalhe] : []),
    ...(url ? ['', 'Abrir a Elolog: ' + url] : []), '', rodape,
  ].join('\n');

  const html = `<!doctype html><html lang="pt"><body style="margin:0;padding:24px;background:#f4f6f9;font-family:Arial,Helvetica,sans-serif;color:#20354d">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">
<table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:8px;padding:28px">
<tr><td style="font-size:12px;letter-spacing:1px;color:#64748b">ELOLOG</td></tr>
<tr><td style="font-size:20px;font-weight:bold;padding:8px 0 16px">${escaparHtml(titulo)}</td></tr>
<tr><td style="font-size:15px;line-height:1.5">${escaparHtml(intro)}</td></tr>
${detalhe ? `<tr><td style="font-size:15px;line-height:1.5;padding-top:12px"><div style="background:#f1f5f9;border-radius:6px;padding:12px">${escaparHtml(detalhe)}</div></td></tr>` : ''}
${url ? `<tr><td style="padding-top:20px"><a href="${escaparHtml(url)}" style="display:inline-block;background:#0b5cab;color:#ffffff;text-decoration:none;padding:11px 20px;border-radius:6px;font-size:15px">Abrir a Elolog</a></td></tr>` : ''}
<tr><td style="font-size:12px;color:#64748b;padding-top:24px;line-height:1.4">${escaparHtml(rodape)}</td></tr>
</table></td></tr></table></body></html>`;

  return { assunto: limparAssunto(`[Elolog] ${titulo}`), texto, html };
}
