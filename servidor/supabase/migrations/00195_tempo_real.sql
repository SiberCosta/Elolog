-- Elolog v153: «tempo real». As páginas passam a saber logo quando algo muda nestas tabelas e atualizam-se sozinhas.
-- Só acrescenta tabelas à publicação do Supabase Realtime (gratuito). As regras de acesso (RLS) continuam a decidir
-- quem recebe cada mudança: cada pessoa só é avisada do que já podia ler. Não apaga nem altera dados.
alter publication supabase_realtime add table public.encomendas, public.simulacoes, public.pagamentos, public.notificacoes,
  public.tickets, public.ticket_mensagens, public.trabalhos_terreno, public.encomenda_historico, public.cliente_notas;
