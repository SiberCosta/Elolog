// Emails do seguimento de simulações (nutrição, com consentimento) e das boas-vindas depois de aprovar uma cotação.
// Regras de texto: falar como uma pessoa da equipa, uma só ação por email, nunca inventar preços, prazos ou datas.
export interface Email { assunto: string; html: string; texto: string }
export interface Dados {
  nome: string; fluxo: string; passo: number; codigo: string; origem: string; destino: string;
  propostas: number; encomenda: string | null;
}
// logótipo em PNG servido pela função «logo-email» (endereço público estável: o Gmail não mostra SVG nem imagens embutidas)
const LOGO = `${(Deno.env.get('SUPABASE_URL') ?? 'https://wcggcpdiswbzrdpwgdpb.supabase.co').replace(/\/+$/, '')}/functions/v1/logo-email`;
const esc = (v: string) => v.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function base(site: string, o: { titulo: string; paragrafos: string[]; lista?: string[]; fim?: string; botao: { texto: string; url: string }; sair?: string }): string {
  const p = o.paragrafos.map((t) => `<p style="margin:0 0 14px;font-size:15px;line-height:1.6;color:#3e5263">${esc(t)}</p>`).join('');
  const l = o.lista?.length ? `<ul style="margin:0 0 16px;padding-left:20px;font-size:15px;line-height:1.7;color:#3e5263">${o.lista.map((t) => `<li>${esc(t)}</li>`).join('')}</ul>` : '';
  const sair = o.sair ? `<br>Não quer receber mais emails sobre esta simulação? <a href="${esc(o.sair)}" style="color:#1F5F8B">Deixar de receber</a>.` : '';
  return `<!doctype html><html lang="pt"><body style="margin:0;padding:24px;background:#f3f6f8;font-family:Arial,Helvetica,sans-serif">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">
  <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:16px;border:1px solid #e1e9ef">
  <tr><td style="padding:26px 32px 6px"><img src="${LOGO}" width="120" height="91" alt="Elolog" style="display:block;border:0;outline:none;text-decoration:none;height:91px;width:120px"></td></tr>
  <tr><td style="padding:6px 32px 26px"><h1 style="margin:0 0 16px;font-size:22px;line-height:1.3;color:#13293D">${esc(o.titulo)}</h1>${p}${l}${o.fim ? `<p style="margin:0 0 14px;font-size:15px;line-height:1.6;color:#3e5263">${esc(o.fim)}</p>` : ''}
  <p style="margin:22px 0"><a href="${esc(o.botao.url)}" style="display:inline-block;padding:13px 22px;border-radius:10px;border:2px solid #13293D;color:#13293D;font-weight:700;font-size:15px;text-decoration:none">${esc(o.botao.texto)}</a></p>
  <p style="margin:18px 0 0;padding-top:14px;border-top:1px solid #e1e9ef;font-size:12px;line-height:1.6;color:#6b7d89">A equipa Elolog. Pode responder a este email se tiver alguma dúvida.${sair}</p></td></tr></table>
  <p style="font-size:12px;color:#6b7d89">Elolog, intermediação e gestão logística. ${esc(site.replace(/^https?:\/\//, ''))}</p></td></tr></table></body></html>`;
}
const texto = (titulo: string, ps: string[], lista: string[], fim: string, botao: { texto: string; url: string }, sair?: string) =>
  [titulo, '', ...ps, ...lista.map((t) => '- ' + t), fim, '', `${botao.texto}: ${botao.url}`, '', 'A equipa Elolog', sair ? `\nDeixar de receber: ${sair}` : ''].join('\n');

/** Escolhe e escreve o email certo para o passo em que a pessoa está. */
export function emailSeguimento(site: string, d: Dados, sair: string): Email {
  const app = `${site}/app/area-cliente.html`, ola = d.nome ? `Olá ${d.nome.split(' ')[0]},` : 'Olá,';
  const rota = d.origem && d.destino ? `de ${d.origem} para ${d.destino}` : 'que simulou';
  let assunto: string, titulo: string, ps: string[], lista: string[] = [], fim = '', botao: { texto: string; url: string }, saida: string | undefined = sair;

  if (d.fluxo === 'boas_vindas') {
    saida = undefined; // email de serviço: confirma uma encomenda que a pessoa aprovou
    assunto = d.encomenda ? `A sua encomenda ${d.encomenda} está confirmada` : 'A sua encomenda está confirmada';
    titulo = 'Está tratado. A partir daqui acompanhamos consigo.';
    ps = [ola, `Aprovou a cotação para a carga ${rota}${d.encomenda ? ` e a encomenda ${d.encomenda} já está criada` : ''}. Obrigado pela confiança.`, 'O que acontece a seguir:'];
    lista = ['A transportadora combina consigo a recolha da carga.', 'Cada mudança de etapa aparece em Encomendas e recebe um aviso na Área de Cliente.',
      'Dúvidas sobre documentos ou desalfandegamento? Pergunte ao assistente ELO ou responda a este email.'];
    botao = { texto: 'Ver o estado da encomenda', url: app };
  } else if (d.passo === 0) {
    if (d.propostas > 0) {
      assunto = d.propostas === 1 ? `Já tem uma proposta para a carga ${rota}` : `Já tem ${d.propostas} propostas para a carga ${rota}`;
      titulo = d.propostas === 1 ? 'Chegou uma proposta para a sua carga' : `Chegaram ${d.propostas} propostas para a sua carga`;
      ps = [ola, `As transportadoras responderam à simulação ${d.codigo}, ${rota}. Pode comparar e aprovar a que lhe servir melhor, sem compromisso até aprovar.`];
      botao = { texto: 'Comparar as propostas', url: app };
    } else {
      assunto = `A sua simulação ${d.codigo} continua guardada`;
      titulo = 'Guardámos a sua simulação';
      ps = [ola, `A simulação ${d.codigo}, ${rota}, está guardada e as transportadoras já a receberam. Assim que chegar uma proposta, aparece na Área de Cliente.`];
      botao = { texto: 'Ver o estado do pedido', url: app };
    }
  } else if (d.passo === 1) {
    assunto = 'Os documentos que costumam ser pedidos na alfândega';
    titulo = 'Uma ajuda para o desalfandegamento';
    ps = [ola, `Quem envia carga para ${d.destino || 'fora'} pergunta-nos muitas vezes o que preparar. Estes são os documentos mais pedidos:`];
    lista = ['Fatura comercial ou lista de bens com o valor de cada um.', 'Lista de volumes (o que vai em cada caixa).', 'Identificação e NIF de quem envia e de quem recebe.'];
    fim = ('As regras mudam de país para país. A transportadora que escolher confirma a lista certa para a sua carga.');
    botao = { texto: d.propostas > 0 ? 'Rever as propostas' : 'Ver o estado do pedido', url: app };
  } else {
    assunto = `Ainda quer enviar a carga para ${d.destino || 'o destino'}?`;
    titulo = 'Só para não ficar esquecida';
    ps = [ola, `A simulação ${d.codigo}, ${rota}, continua à sua espera. Se os planos mudaram, não precisa de fazer nada.`, 'Este é o último email que lhe enviamos sobre esta simulação.'];
    botao = { texto: 'Retomar a simulação', url: app };
  }
  return { assunto, html: base(site, { titulo, paragrafos: ps, lista, fim, botao, sair: saida }), texto: texto(titulo, ps, lista, fim, botao, saida) };
}
