# Teste do servidor real — 23-11-2026

Projeto Supabase «Elolog» (wcggcpdiswbzrdpwgdpb, Frankfurt), o mesmo que a aplicação usa.

## Como foi feito, sem tocar nos dados

- Leituras: estado do projeto, migrações, avisos de segurança e desempenho do Supabase, tarefas agendadas, fila de emails,
  respostas HTTP das últimas 24 h e registos (Postgres, API, Edge Functions).
- Testes de comportamento do kit `servidor/supabase/testes`: cada um corre numa só transação que termina com um erro
  propositado, por isso **nada fica gravado**. Confirmado antes e depois: empresas, clientes, encomendas, simulações,
  utilizadores, avisos, emails e pedidos HTTP com as mesmas contagens. Onde um teste supunha a base vazia, foi limitado
  aos dados do próprio teste.
- Funções do servidor: um pedido inofensivo a cada uma (sem sessão), feito pela própria base de dados (pg_net).

## Resultados

| Área | Resultado |
|---|---|
| Instalação (tabelas, RLS, funções, permissões, gatilhos, extensões, bucket) | 18 OK, 1 aviso esperado (rastreio público aberto a anónimos) |
| Isolamento entre empresas, preços no servidor, simulação → encomenda, administração, 2 passos da administração, avisos por email (02) | 66/66 |
| Regras de segurança: ficheiros, auditoria imutável, limites, bloqueios (17) | 12/12 |
| Fluxo completo da encomenda com bloqueios, histórico e ficha (24) | 20/20 |
| Encomenda criada pelo prestador (32) | 10/10 |
| Seguimento por email: consentimento, boas-vindas, sair (27) | 18/18 |
| Tarifários, motor de preços, versões, suplementos, comissões (28) | 30/30 |
| Login de funcionário por n.º e 2 passos do administrador da empresa (15, 16) | 15/15 |
| Encomendas diretas (22) | 22/22 |
| Códigos ELO_<REF>/ELO_SM (09) | 7/7 |
| **Total** | **200/200** |
| Tarefas agendadas (24 h) | 7 tarefas, 1581 execuções, 0 falhas |
| Fila de emails | 24 enviados, 0 presos |
| Edge Functions (17 testadas) | todas respondem e recusam pedidos sem sessão; `copia-dados` responde 503 (ver abaixo) |
| Coerência dos dados reais | sem encomendas órfãs, sem pagamentos soltos, sem documentos sem ficheiro, todas as contas confirmadas |

## Problemas encontrados

1. **Email de boas-vindas recusado (corrigido no código, falta publicar).** Depois de o cliente aprovar uma cotação, a
   função `seguimento` enviava `headers: {}` ao Brevo, que responde 400 «headers is blank». Um cliente está à espera
   deste email desde 15/11 e a função tenta de hora a hora (13 recusas só hoje). Correção em
   `servidor/supabase/functions/seguimento/index.ts`; publicar com `supabase functions deploy seguimento --no-verify-jwt`.
2. **Chegada prevista sem viagens até recarregar a página (corrigido).** `app/comum/previsao-chegada.js` lia as viagens
   3 s depois de abrir a página, antes de haver sessão (o servidor recusa: 401) e não voltava a ler depois de entrar.
3. **Sem cópias de segurança ativas.** A `copia-dados` não tem os segredos `COPIA_TOKEN` e `COPIA_SENHA` (Cloudflare
   ainda não existe) e o repositório não tem o ficheiro `.github/workflows/copia-seguranca.yml` que a
   documentação descreve. Hoje não há nenhuma cópia automática dos dados.
4. **Proteção contra palavras-passe divulgadas desligada** (Supabase › Authentication › Passwords › «Leaked password
   protection»).
5. **Migração 00159 (retirar a pesquisa marítima) não aplicada.** As tabelas `viagens_maritimas`, `navios_*` e as funções
   `navios-ais` e `navios-mst` continuam no servidor. A previsão de chegada e o calendário marítimo do prestador ainda
   usam `viagens_maritimas`, por isso **não aplicar a 00159 sem rever isto primeiro**.
6. Dados de teste parados: 4 encomendas em «Recolha» e 3 serviços de terreno abertos há mais de 7 dias.

## Avisos do Supabase (sem ação urgente)

- 106 funções `security definer` chamáveis por utilizadores autenticados: é o desenho da Elolog (cada função verifica
  quem chama); os testes acima confirmam as recusas.
- 51 tabelas com várias políticas de leitura e 93 índices ainda sem uso: só pesa com muito volume.

## O que não foi possível testar daqui

- A aplicação no navegador contra o servidor real: este ambiente não tem acesso à internet (o navegador de teste também
  não). Fazer o teste manual de `testes/LEIA-ME.md` (passo 6) no computador.
- Envio real de emails, SMS, pagamentos ifthenpay, MyShipTracking e HERE (gastam créditos ou mexem em dinheiro).
- Testes do kit não corridos: 05, 06, 07, 08, 10, 11, 12, 13, 14, 18, 21, 23, 25, 26, 29, 30, 31.
