// Edge Function «pagamentos»: referências Multibanco e pedidos MB WAY pela ifthenpay, com as chaves de cada empresa.
// Deploy: supabase functions deploy pagamentos --no-verify-jwt   (o token do cliente é validado no código)
// As chaves ficam na tabela empresa_pagamentos_config (só o servidor as lê); a empresa grava-as em Empresa › Pagamentos online.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { tratar, type DepsPag, type Pedido } from './handler.ts';
import { criarIfthenpay } from './ifthenpay.ts';
import { pedidoAgendado } from '../_shared/cofre.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  { auth: { persistSession: false, autoRefreshToken: false } });
const api = criarIfthenpay((k) => Deno.env.get(k));

const deps: DepsPag = {
  agendado: (req) => pedidoAgendado(req, admin),
  async autenticar(jwt) {
    const { data, error } = await admin.auth.getUser(jwt);
    return error || !data.user ? null : data.user.id;
  },
  async limite(chave, max, janelaMin) {
    const { data, error } = await admin.rpc('servico_limite', { p_chave: chave, p_max: max, p_janela_min: janelaMin });
    if (error) throw error;
    return data === true;
  },
  async preparar(cliente, encomenda, metodo, telemovel) {
    const { data, error } = await admin.rpc('servico_preparar_pedido', { p_cliente: cliente, p_encomenda: encomenda, p_metodo: metodo, p_telemovel: telemovel });
    if (error) { if (error.code === 'P0001') return { erro: error.message }; throw error; }
    return data as { reutilizar: boolean; pedido: Pedido; chave?: string; sandbox?: boolean; descricao?: string };
  },
  async atualizar(id, estado, dados) {
    const { error } = await admin.rpc('servico_atualizar_pedido', { p_id: id, p_estado: estado, p_dados: dados });
    if (error) throw error;
  },
  async confirmar(orderId, valor, origem) {
    const { data, error } = await admin.rpc('servico_confirmar_pedido', { p_order_id: orderId, p_chave: null, p_valor: valor, p_origem: origem });
    if (error) throw error;
    return String(data);
  },
  async pendentesMbway() {
    const { data, error } = await admin.rpc('servico_pedidos_mbway_pendentes');
    if (error) throw error;
    return (data ?? []) as { id: string; order_id: string; request_id: string; valor: number; chave: string }[];
  },
  async lerPedido(cliente, id) {
    const { data, error } = await admin.from('pedidos_pagamento').select('*').eq('id', id).eq('cliente_id', cliente).maybeSingle();
    if (error) throw error;
    if (!data) return null;
    const { data: cfg } = await admin.from('empresa_pagamentos_config').select('mbway_key').eq('empresa_id', data.empresa_id).maybeSingle();
    return { ...(data as Pedido), chave: cfg?.mbway_key ?? undefined };
  },
  api,
};

Deno.serve((req: Request) => tratar(req, deps));
