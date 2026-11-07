-- v100 (parte A) — novas etapas: «Disponível» (aviso ao cliente) entre «Destino» e «Levantado», e a tarefa de processamento no destino.
-- Só acrescenta valores aos tipos existentes (têm de ficar numa transação própria, antes da parte B).
alter type estado_encomenda add value if not exists 'disponivel' after 'destino';
alter type tipo_trabalho add value if not exists 'processamento_destino';
