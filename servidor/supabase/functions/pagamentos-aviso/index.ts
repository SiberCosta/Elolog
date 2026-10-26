// Edge Function «pagamentos-aviso»: endereço de aviso (callback) que a ifthenpay chama quando um pagamento é feito.
// Deploy: supabase functions deploy pagamentos-aviso --no-verify-jwt
// Endereço a dar à ifthenpay (um por empresa, com a chave anti-phishing dessa empresa):
//   https://<projeto>.supabase.co/functions/v1/pagamentos-aviso?key=[ANTI_PHISHING_KEY]&orderId=[ORDER_ID]&amount=[AMOUNT]&requestId=[REQUEST_ID]
// A chave é comparada no servidor com a guardada pela empresa; o valor tem de ser igual ao do pedido; repetir o aviso não paga duas vezes.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { avisar, texto } from './aviso.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  { auth: { persistSession: false, autoRefreshToken: false } });
Deno.serve(async (req: Request) => {
  if (req.method !== 'GET' && req.method !== 'POST') return texto(405, 'metodo');
  try {
    return await avisar(new URL(req.url), async (o, k, v) => {
      const { data, error } = await admin.rpc('servico_confirmar_pedido', { p_order_id: o, p_chave: k, p_valor: v, p_origem: 'aviso' });
      if (error) throw error;
      return String(data);
    });
  } catch (e) {
    console.error('pagamentos-aviso: erro', e instanceof Error ? e.message : e);
    return texto(500, 'erro');
  }
});
