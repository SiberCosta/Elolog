// Lógica de "enviar-emails", separada do arranque (index.ts) para poder ser testada sem Deno nem rede.
// Chamada por agendamento (pg_cron → pg_net) com o cabeçalho x-cron-secret. Não é uma função para o navegador.
import { erro, lerJson, resposta } from '../_shared/http.ts';
import { emailValido } from '../_shared/validar.ts';
import { renderizar, type EmailPronto, type ItemEmail } from '../_shared/emails.ts';
import type { Enviar, ResultadoEnvio } from './brevo.ts';

export interface DepsEmails {
  segredo: string;                                   // CRON_SECRET (vazio = função não configurada)
  ativo: boolean;                                    // EMAIL_ATIVO != 'false'
  fornecedorConfigurado: boolean;                    // chave e remetente definidos
  appUrl: string;
  limiteDiario: number;
  lote: number;
  enviadosHoje(): Promise<number>;
  reservar(max: number): Promise<ItemEmail[]>;
  marcar(id: string, resultado: 'enviado' | 'repetir' | 'falhou' | 'libertar', fornecedorId?: string, erro?: string): Promise<void>;
  enviar: Enviar;
}

import { igualConstante } from '../_shared/comparar.ts';
export { igualConstante };

export async function tratar(req: Request, deps: DepsEmails): Promise<Response> {
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');
  try {
    if (!deps.segredo) return erro(503, 'nao_configurado', 'Segredo do agendador não definido.');
    const recebido = req.headers.get('x-cron-secret') ?? '';
    if (!(await igualConstante(recebido, deps.segredo))) return erro(401, 'nao_autorizado', 'Não autorizado.');

    if (!deps.ativo) return resposta(200, { ok: true, ativo: false, enviados: 0 });
    if (!deps.fornecedorConfigurado) return erro(503, 'fornecedor_nao_configurado', 'BREVO_API_KEY e EMAIL_REMETENTE ainda não estão definidos.');

    const corpo = await lerJson(req, 2_000);
    if (!corpo.ok) return corpo.resp;
    const c = (typeof corpo.valor === 'object' && corpo.valor !== null ? corpo.valor : {}) as Record<string, unknown>;

    // Teste de configuração: envia um e-mail de teste diretamente (não passa pela fila).
    if (typeof c.teste === 'string') {
      const para = c.teste.trim().toLowerCase();
      if (!emailValido(para)) return erro(400, 'dados_invalidos', 'Endereço de teste inválido.');
      const pronto: EmailPronto = renderizar({
        id: 'teste', destinatario: para, destino: 'utilizador', tipo: 'teste', titulo: 'E-mail de teste da Elolog',
        corpo: 'Se está a ler isto, o envio de e-mails está configurado.',
      }, deps.appUrl);
      const r = await deps.enviar(para, pronto, 'teste');
      return resposta(r.tipo === 'ok' ? 200 : 502,
        r.tipo === 'ok' ? { ok: true, enviado: true } : { ok: false, enviado: false, resultado: r.tipo, detalhe: r.erro });
    }

    const jaEnviados = await deps.enviadosHoje();
    const restante = deps.limiteDiario - jaEnviados;
    if (restante <= 0) return resposta(200, { ok: true, enviados: 0, adiado: 'limite diário atingido', enviadosHoje: jaEnviados });

    const itens = await deps.reservar(Math.min(deps.lote, restante));
    let enviados = 0, repetidos = 0, falhados = 0, libertados = 0, seguidosTemporarios = 0;
    let paragem: string | undefined;

    for (const item of itens) {
      if (paragem) {                                   // lote interrompido: devolve à fila sem gastar a tentativa
        await deps.marcar(item.id, 'libertar', undefined, paragem);
        libertados++;
        continue;
      }
      let r: ResultadoEnvio;
      try {
        r = await deps.enviar(item.destinatario, renderizar(item, deps.appUrl), item.tipo);
      } catch (e) {
        console.error('enviar-emails: erro inesperado a enviar', item.id, e instanceof Error ? e.name : 'erro');
        r = { tipo: 'repetir', erro: 'Erro interno ao enviar.' };
      }
      if (r.tipo === 'ok') { await deps.marcar(item.id, 'enviado', r.id); enviados++; seguidosTemporarios = 0; continue; }
      if (r.tipo === 'falhou') { await deps.marcar(item.id, 'falhou', undefined, r.erro); falhados++; continue; }
      if (r.tipo === 'limite' || r.tipo === 'configuracao') {
        // não é culpa deste e-mail: devolve-o e para o lote
        await deps.marcar(item.id, 'libertar', undefined, r.erro);
        libertados++;
        paragem = r.tipo === 'limite' ? 'Limite do fornecedor: lote interrompido.' : 'Configuração do fornecedor recusada: lote interrompido.';
        console.error('enviar-emails:', paragem, r.erro);
        continue;
      }
      // repetir (falha temporária)
      await deps.marcar(item.id, 'repetir', undefined, r.erro);
      repetidos++;
      if (++seguidosTemporarios >= 3) paragem = 'Falhas temporárias seguidas: lote interrompido.';
    }
    return resposta(200, { ok: true, reservados: itens.length, enviados, repetidos, falhados, libertados, interrompido: paragem ?? null });
  } catch (e) {
    console.error('enviar-emails: erro inesperado', e instanceof Error ? e.name : 'erro');
    return erro(503, 'indisponivel', 'Serviço temporariamente indisponível.');
  }
}
