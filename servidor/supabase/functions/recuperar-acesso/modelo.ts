// Emails da recuperação de acesso (HTML simples, compatível com os leitores de email, e versão em texto).
export interface Email { assunto: string; html: string; texto: string }
const esc = (v: string) => v.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function base(o: { site: string; titulo: string; paragrafos: string[]; botao?: { texto: string; url: string }; codigo?: string; nota: string }): string {
  const p = o.paragrafos.map((t) => `<p style="margin:0 0 14px;font-size:15px;line-height:1.55;color:#4b5d6b">${esc(t)}</p>`).join('');
  const botao = o.botao ? `<p style="margin:22px 0"><a href="${esc(o.botao.url)}" style="display:inline-block;padding:13px 22px;border-radius:10px;background:#236186;color:#ffffff;font-weight:700;font-size:15px;text-decoration:none">${esc(o.botao.texto)}</a></p>` : '';
  const codigo = o.codigo ? `<p style="margin:0 0 6px;font-size:13px;color:#6b7d89">Ou use este código na mesma página:</p>
    <p style="margin:0 0 18px;font:700 28px/1.2 Consolas,Menlo,monospace;letter-spacing:6px;color:#0E2433">${esc(o.codigo)}</p>` : '';
  return `<!doctype html><html lang="pt"><body style="margin:0;padding:24px;background:#f3f6f8;font-family:Arial,Helvetica,sans-serif">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">
  <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:16px;border:1px solid #e1e9ef">
  <tr><td style="padding:26px 32px 6px"><img src="${esc(o.site)}/partilhado/imagens/elolog-logo-600.png" width="96" height="96" alt="Elolog" style="display:block"></td></tr>
  <tr><td style="padding:6px 32px 26px"><h1 style="margin:0 0 16px;font-size:22px;color:#0E2433">${esc(o.titulo)}</h1>${p}${botao}${codigo}
  <p style="margin:18px 0 0;padding-top:14px;border-top:1px solid #e1e9ef;font-size:12px;line-height:1.5;color:#6b7d89">${esc(o.nota)}</p></td></tr></table>
  <p style="font-size:12px;color:#6b7d89">Elolog · Intermediação e Gestão Logística · ${esc(o.site.replace(/^https?:\/\//, ''))}</p></td></tr></table></body></html>`;
}

export function emailRecuperacao(site: string, url: string, codigo: string): Email {
  return { assunto: 'Recuperar a palavra-passe da Elolog',
    html: base({ site, titulo: 'Criar uma nova palavra-passe', paragrafos: ['Recebemos um pedido para recuperar o acesso à sua conta Elolog.', 'Carregue no botão para criar uma nova palavra-passe. A ligação é válida durante 1 hora e só pode ser usada uma vez.'],
      botao: { texto: 'Criar nova palavra-passe', url }, codigo, nota: 'Se não foi você que pediu, ignore este email: a sua palavra-passe continua igual. Nunca partilhe este código.' }),
    texto: `Recuperar a palavra-passe da Elolog\n\nCrie uma nova palavra-passe aqui (válido 1 hora, uma única vez):\n${url}\n\nOu use o código: ${codigo}\n\nSe não foi você que pediu, ignore este email.` };
}

export function emailAlterada(site: string, quando: string): Email {
  return { assunto: 'A sua palavra-passe da Elolog foi alterada',
    html: base({ site, titulo: 'Palavra-passe alterada', paragrafos: [`A palavra-passe da sua conta Elolog foi alterada em ${quando}.`, 'Por segurança, as sessões abertas noutros aparelhos foram terminadas.'],
      botao: { texto: 'Entrar na Elolog', url: `${site}/app/area-cliente.html` }, nota: 'Se não foi você, recupere já o acesso em «Esqueceu-se da palavra-passe?» e contacte contacto@elolog.pt.' }),
    texto: `A palavra-passe da sua conta Elolog foi alterada em ${quando}. As sessões noutros aparelhos foram terminadas.\nSe não foi você, recupere o acesso em ${site}/app/area-cliente.html e contacte contacto@elolog.pt.` };
}

export function emailEmpresa(site: string, empresa: string, url: string, codigo: string): Email {
  return { assunto: `Repor a palavra-passe da empresa ${empresa} na Elolog`,
    html: base({ site, titulo: 'Palavra-passe da empresa', paragrafos: [`Foi pedido repor a palavra-passe de acesso da empresa ${empresa} (1.º passo do login do prestador).`, 'Carregue no botão para definir a nova palavra-passe. A ligação e o código são válidos durante 30 minutos.'],
      botao: { texto: 'Definir nova palavra-passe da empresa', url }, codigo, nota: 'Este email foi enviado para o endereço oficial da empresa. Se ninguém da empresa pediu, ignore-o: a palavra-passe continua igual.' }),
    texto: `Repor a palavra-passe da empresa ${empresa} na Elolog\n\nDefina a nova palavra-passe aqui (válido 30 minutos):\n${url}\n\nOu use o código: ${codigo}\n\nSe ninguém da empresa pediu, ignore este email.` };
}

export function emailPrimeiroAcesso(site: string, o: { empresa: string; nif: string; adminNome: string; adminEmail: string; codigo: string; expira: string }): Email {
  const url = `${site}/app/area-cliente.html?acesso=prestador`;
  return { assunto: `Acesso à Elolog — ${o.empresa}`,
    html: base({ site, titulo: 'A sua empresa já está na Elolog', paragrafos: [`Olá ${o.adminNome}, a equipa Elolog criou o acesso da empresa ${o.empresa} (NIF ${o.nif}).`,
      `Para entrar: 1.º passo — nome da empresa «${o.empresa}», NIF ${o.nif} e o código abaixo; 2.º passo — o seu email (${o.adminEmail}) e o mesmo código.`,
      `No primeiro acesso a plataforma pede-lhe para criar a palavra-passe da empresa e a sua palavra-passe pessoal. O código é válido até ${o.expira}.`],
      botao: { texto: 'Entrar na Elolog', url }, codigo: o.codigo, nota: 'Código temporário de uso único. Não o partilhe. Se expirar, peça um novo à Elolog (contacto@elolog.pt).' })
      .replace('Ou use este código na mesma página:', 'Código de acesso temporário:'),
    texto: `A empresa ${o.empresa} (NIF ${o.nif}) já está na Elolog.\n\nEntre em ${url}\n1.º passo: nome da empresa, NIF e o código ${o.codigo}\n2.º passo: ${o.adminEmail} e o mesmo código.\nNo primeiro acesso cria as palavras-passe definitivas. Válido até ${o.expira}.` };
}
