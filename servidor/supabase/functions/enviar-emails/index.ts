// Edge Function de envio da fila de e-mails (Brevo). Chamada por agendamento, nunca pelo navegador.
// Deploy:  supabase functions deploy enviar-emails --no-verify-jwt     (o acesso é protegido por x-cron-secret)
// Segredo do agendador: lido do cofre da base de dados (migração 00131); CRON_SECRET só se quiser substituí-lo.
// Segredos:
//   supabase secrets set BREVO_API_KEY=<chave API v3 do Brevo> \
//     EMAIL_REMETENTE=<endereço validado no Brevo> EMAIL_NOME="Elolog" APP_URL=<endereço da aplicação>
// Opcionais: EMAIL_LIMITE_DIARIO (por omissão 250, abaixo dos 300 do plano gratuito), EMAIL_LOTE (20), EMAIL_ATIVO=false (pausa)
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { tratar, type DepsEmails } from './handler.ts';
import { criarBrevo } from './brevo.ts';
import type { ItemEmail } from '../_shared/emails.ts';
import { segredoCron } from '../_shared/cofre.ts';

const URL_PROJETO = Deno.env.get('SUPABASE_URL') ?? '';
const CHAVE_SERVICO = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const admin = createClient(URL_PROJETO, CHAVE_SERVICO, { auth: { persistSession: false, autoRefreshToken: false } });

const inteiro = (v: string | undefined, omissao: number, min: number, max: number): number => {
  const n = Number.parseInt(v ?? '', 10);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : omissao;
};

const chave = Deno.env.get('BREVO_API_KEY') ?? '';
const remetenteEmail = Deno.env.get('EMAIL_REMETENTE') ?? '';
const enviar = criarBrevo({ chave, remetenteEmail, remetenteNome: (Deno.env.get('EMAIL_NOME') ?? 'Elolog').slice(0, 60) });

async function dependencias(): Promise<DepsEmails> {
  return {
    segredo: await segredoCron(admin),
    ativo: (Deno.env.get('EMAIL_ATIVO') ?? 'true').toLowerCase() !== 'false',
    fornecedorConfigurado: chave.length > 10 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(remetenteEmail),
    appUrl: Deno.env.get('APP_URL') ?? '',
    limiteDiario: inteiro(Deno.env.get('EMAIL_LIMITE_DIARIO'), 250, 1, 100_000),
    lote: inteiro(Deno.env.get('EMAIL_LOTE'), 20, 1, 100),
    async enviadosHoje() {
      const { data, error } = await admin.rpc('servico_emails_enviados_hoje');
      if (error) throw error;
      return Number(data) || 0;
    },
    async reservar(max) {
      const { data, error } = await admin.rpc('servico_reservar_emails', { p_max: max, p_reserva_min: 5 });
      if (error) throw error;
      return (data ?? []) as ItemEmail[];
    },
    async marcar(id, resultado, fornecedorId, erro) {
      const { error } = await admin.rpc('servico_marcar_email', { p_id: id, p_resultado: resultado, p_fornecedor_id: fornecedorId ?? null, p_erro: erro ?? null });
      if (error) console.error('enviar-emails: não foi possível registar o resultado', id, error.code);
    },
    enviar,
  };
}

Deno.serve(async (req: Request) => tratar(req, await dependencias()));
