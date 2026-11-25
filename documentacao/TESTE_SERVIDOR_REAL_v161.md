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
| Faturas, pagamentos ifthenpay, navios, documentos do cliente (05) | 38/39 — a única diferença é a expectativa antiga de 4 tarefas agendadas (hoje há 7, de migrações posteriores) |
| Email, acessos e grupos do chat (06, 07, 08) | 55/55 |
| Repor empresa, espaço de ficheiros, declarações, acesso temporário, ocorrências (10–14) | 48/48 |
| Código de reserva, código por email, painel vivo (18, 26, 25) | 39/39 |
| Revisão de encomendas diretas, regras de cobrança, centro documental (23, 29, 30) | 80/80 |
| Fase 1: seguimento ao vivo, alertas, comprovativo de entrega, EL-ENT, webhooks (31) | 31/31 |
| Funis (21) | obsoleto: `painel_funis` foi retirado de propósito na v100 |
| **Total** | **491/492** (a falha é só a contagem desatualizada do teste) |
| Tarefas agendadas (24 h) | 7 tarefas, 1581 execuções, 0 falhas |
| Fila de emails | 24 enviados, 0 presos |
| Edge Functions (17 testadas) | todas respondem e recusam pedidos sem sessão; `copia-dados` responde 503 (ver abaixo) |
| Coerência dos dados reais | sem encomendas órfãs, sem pagamentos soltos, sem documentos sem ficheiro, todas as contas confirmadas |

## Problemas encontrados

1. **Email de boas-vindas recusado (corrigido e publicado).** Depois de o cliente aprovar uma cotação, a
   função `seguimento` enviava `headers: {}` ao Brevo, que responde 400 «headers is blank». Um cliente está à espera
   deste email desde 15/11 e a função tenta de hora a hora (13 recusas só hoje). Correção em
   `servidor/supabase/functions/seguimento/index.ts`, publicada no servidor (versão 3) a 24/11. O email em espera foi
   enviado logo a seguir (`{"ok":true,"enviados":1}`).
2. **Chegada prevista sem viagens até recarregar a página (corrigido).** `app/comum/previsao-chegada.js` lia as viagens
   3 s depois de abrir a página, antes de haver sessão (o servidor recusa: 401) e não voltava a ler depois de entrar.
3. **Sem cópias de segurança ativas (preparado na v162, falta ativar).** O ficheiro `.github/workflows/copia-seguranca.yml`
   já existe (todas as noites às 02:23 UTC; base de dados e ficheiros, cifrados com AES-256, 30 dias). Só começa a copiar
   depois de criados os segredos do GitHub `SUPABASE_DB_URL` e `COPIA_SENHA`, e também `SUPABASE_URL` e
   `SUPABASE_SERVICE_ROLE_KEY` para os ficheiros (ver `COPIAS_DE_SEGURANCA.md`). O repositório é **público**: a cópia só
   se lê com a `COPIA_SENHA`, por isso use uma frase longa. A segunda cópia (Cloudflare) continua opcional.
4. **Proteção contra palavras-passe divulgadas desligada.** O projeto está no plano gratuito e esta opção do Supabase só
   existe a partir do plano Pro. Fica como está.
5. **Migração 00159 revista (v162).** Já não apaga `viagens_maritimas` nem `viagens_elolog` (a previsão de chegada e o
   calendário marítimo usam-nas). Só retira as 4 funções da antiga pesquisa e a tabela `navios_rota`, sem nenhuma
   referência na aplicação nem no servidor. Pode ser executada à mão no SQL Editor; não é urgente.
6. **Encomendas paradas em «Recolha».** Revisto: as 4 (ELO_SOIM-000002 a 000005, de 15/11) são da empresa real «Soim lda», não
   de teste, e não foram alteradas. Cabe ao prestador avançá-las ou cancelá-las na aplicação. Já não há serviços de
   terreno abertos há mais de 7 dias.

## Avisos do Supabase (sem ação urgente)

- 106 funções `security definer` chamáveis por utilizadores autenticados: é o desenho da Elolog (cada função verifica
  quem chama); os testes acima confirmam as recusas.
- 51 tabelas com várias políticas de leitura e 93 índices ainda sem uso: só pesa com muito volume.

## O que não foi possível testar daqui

- A aplicação no navegador contra o servidor real: este ambiente não tem acesso à internet (o navegador de teste também
  não). Fazer o teste manual de `testes/LEIA-ME.md` (passo 6) no computador.
- Envio real de emails, SMS, pagamentos ifthenpay, MyShipTracking e HERE (gastam créditos ou mexem em dinheiro).
- Todos os testes do kit foram corridos; só o 21 ficou de fora por estar obsoleto.
