# Esquema Supabase do Elolog

Aplicar **por ordem (0001 → 0011)** (SQL Editor do Supabase ou `supabase db push`):

| Ficheiro | O que faz |
|---|---|
| `00011_base_parte1.sql + 00012_base_parte2.sql + 00013_base_parte3.sql` | Tabelas, enums, índices, restrições, códigos legíveis (SIM-/PROP-/TR-…), RLS ligada em todas as tabelas |
| `00021_regras_fluxo_parte1.sql + 00022_regras_fluxo_parte2.sql` | Regras do fluxo como funções e gatilhos: `transitar_encomenda()`, `aceitar_proposta()`, `decidir_empresa()`, tarifas versionadas, manifestos, notificações à administração |
| `00031_rls_parte1.sql + 00032_rls_parte2.sql` | Funções auxiliares, políticas por empresa e por papel, permissões por coluna, bucket privado `documentos` |
| `seed_teste.sql` | Dados de teste (1 prestador + 2 tarifas); **não usar em produção** |
| `00041_calculo_tarifas.sql` | **Cálculo de preços no servidor**: `calcular_propostas()`, `enviar_simulacao()`, `cancelar_simulacao()` |
| `00061_funcoes_servico_parte1.sql + 00062_funcoes_servico_parte2.sql` | **Apoio às Edge Functions**: funções `servico_*` (só `service_role`), limite de funcionários do plano, colunas do funcionário, fecho da edição direta de `funcionarios` |
| `00111_mfa_admin.sql` | **Verificação em dois passos da administração** (TOTP): a regra `exigir_mfa_admin`, desligada por omissão (ver «Acesso reservado») |
| `00121_avisos_seguranca.sql` | Correções dos avisos de segurança do Supabase: vista `empresas_disponiveis` com `security_invoker` e fora da API, `search_path` fixo nas funções internas, tabelas internas sem privilégios para `anon`/`authenticated` |
| `00131_producao_parte1.sql` | pg_cron + pg_net; `private.agendar_tarefas(url)` (segredo do agendador no cofre, tarefas de emails, navios e pagamentos); limites do bucket `documentos`; documentos do cliente nas encomendas; tabela `faturas` e validação de NIF |
| `00132_producao_parte2.sql` | `registar_fatura` (QR da AT validado no servidor); configuração de pagamentos por empresa (`ver_config_pagamentos`, `guardar_config_pagamentos`) |
| `00133_producao_parte3.sql` | `pedidos_pagamento` e funções de serviço da ifthenpay; `navios_seguidos` e `navios_posicoes` (AIS) |
| `00101_painel.sql` | **Indicadores do painel da administração**: `painel_administracao(dias)` devolve tudo numa só chamada (só leitura, só administração) |
| `00091_endurecer.sql` | **Opcional**: retira ao papel `anon` as permissões que as tabelas/funções novas herdam por omissão (só deixa `validar_empresa`) |
| `testes/` | **Kit de testes para um projeto de teste**: `01_instalacao.sql`, `02_comportamento.sql`, `03_funcoes_http.sh` e `LEIA-ME.md` com a ordem e o que enviar de volta |
| `00081_emails.sql` | **Aviso por e-mail**: fila `emails_fila` alimentada pelas notificações, destinatários só com e-mail confirmado, limite por pessoa, funções `servico_*` do envio |
| `agendar_emails.sql` | Agenda o envio a cada minuto (pg_cron + pg_net) e traz consultas para acompanhar a fila |
| `00071_admin.sql` | **Painel da administração**: `sou_admin_plataforma()`, `decidir_empresa()` corrigida, `confirmar_pagamento_subscricao()` |
| `aprovar_empresa.sql` | Alternativa à mão (SQL Editor) para aprovar/recusar uma empresa, se o painel não estiver disponível |
| `00051_prestador_parte1.sql + 00052_prestador_parte2.sql` | **Prestador**: login da empresa com bloqueio de tentativas, sessão de empresa exigida pelo RLS, `aceitar_simulacao()`, `recusar_simulacao()`, dados de entrega/recolha |

## Dependências de outros sites

**A aplicação, por omissão, não pede nada a outros sites** (testado no navegador: nenhum pedido externo ao carregar, nem em modo local nem com servidor).
- **Biblioteca do Supabase:** vem de `app/comum/supabase.js`, no próprio servidor da aplicação. O jsDelivr só é usado se puser `usarCdn: true` em `app/comum/servidor-config.js` (e o ficheiro local faltar).
- **Tipos de letra, logótipos e estilos:** estão dentro do projeto (a aplicação usa os tipos do sistema operativo; o sistema de design traz Work Sans e Big Shoulders em ficheiros).
- **Exceção que continua:** o simulador do site público (`Simulador/js/script.js`) consulta o serviço de moradas do OpenStreetMap (Nominatim) para calcular distâncias. É um **serviço de dados**, não código de interface, e só funciona com internet. Substituir exige uma fonte de geocodificação própria.
- **Ligações (não dependências):** `wa.me` (WhatsApp) e o endereço do site abrem noutro separador, mas nada é carregado deles.

## Testar antes de usar
Nada disto foi executado num Supabase real. **Comece por `testes/LEIA-ME.md`**: tem a ordem, os testes automáticos e o que enviar de volta.

## Estado e origem (importante)

- **Nenhum destes ficheiros foi executado** (não havia PostgreSQL disponível). Só passaram verificações estruturais. Testar primeiro num projeto Supabase de teste.
- `00011_base_parte1.sql + 00012_base_parte2.sql + 00013_base_parte3.sql` **não veio no teu zip**: já estava na pasta de trabalho, de origem desconhecida. Foi revisto e está **sem alterações**; corresponde às regras de `DOCUMENTACAO/`. `0002` e `0003` foram escritos nesta sessão, a partir do `0001` e de `PROVIDER_PERMISSIONS`.
- A `0002` move `segredo_acesso_hash` de `empresas` para `empresa_segredos` (sem políticas: só o `service_role` lhe acede), preservando os dados.

## Primeiro administrador da plataforma

Criar o utilizador em Authentication e depois, no SQL Editor:

```sql
insert into administradores_plataforma (user_id, nome)
values ('<uuid do utilizador>', 'Administração Elolog');
```

## Edge Functions (registo de prestador e equipa)

Pasta `supabase/functions/`: `registar-prestador`, `gerir-funcionarios` e `_shared` (validação e HTTP). Cada função tem a lógica em `handler.ts` (testável sem Deno) e o arranque em `index.ts`.

### Publicar
```bash
supabase login
supabase link --project-ref <referência do projeto>
supabase functions deploy registar-prestador --no-verify-jwt
supabase functions deploy gerir-funcionarios --no-verify-jwt
supabase functions deploy enviar-emails --no-verify-jwt        # ver "Aviso por e-mail" (segredos próprios)
supabase functions deploy pagamentos --no-verify-jwt           # ifthenpay (ver documentacao/PRODUCAO.md)
supabase functions deploy pagamentos-aviso --no-verify-jwt     # aviso (callback) da ifthenpay
supabase functions deploy navios-ais --no-verify-jwt           # AIS, segredo AISSTREAM_API_KEY
supabase secrets set SITE_URL=https://o-seu-endereço      # opcional: destino do link do e-mail de confirmação
```
`SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` já são injetadas pelo Supabase nas Edge Functions. **A chave `service_role` nunca vai para o front-end.** `--no-verify-jwt` porque o registo é público e a outra função valida o token no próprio código (`auth.getUser`).

### `registar-prestador` (pública)
Recebe empresa, senha da empresa, 1.º administrador, plano e pagamento **declarado**. Fluxo: valida → limites (por IP, por NIF e por e-mail, 1 h) → e-mail livre? → cria a conta do administrador com `signUp` (se o projeto exigir confirmação, o Supabase envia o e-mail e o administrador só entra depois de a confirmar) → `servico_registar_prestador` (atómico: empresa **pendente**, senha da empresa cifrada com pgcrypto, subscrição **pendente**, administrador, registo da aceitação dos termos). Se o registo na base de dados falhar, a conta de autenticação criada é apagada (sem contas órfãs).
- **O pagamento não é confirmado por aqui.** Só fica registado o método e a referência; `pago_em` fica vazio até a administração confirmar (no painel da administração). A interface deixou de dizer "pagamento confirmado".

### `gerir-funcionarios` (só o administrador da empresa, com a sessão de empresa aberta)
Ações: `criar`, `atualizar` (nome, função, ativo, dados, permissões), `repor_senha`, `eliminar`. A **empresa vem sempre da sessão do administrador**; um `empresaId` enviado no pedido é ignorado.
- **Limite do plano:** passa a ser aplicado (`planos.max_funcionarios`, só em funcionários ativos) — antes não era.
- **Último administrador:** não pode ser desativado, rebaixado nem eliminado; ninguém retira o próprio acesso de administrador.
- **Desativar** bloqueia também a conta no serviço de contas (`ban`) e fecha a sessão de empresa. **Reativar** volta a respeitar o limite do plano.
- **Eliminar:** quem já tem histórico (encomendas, propostas…) não pode ser apagado sem perder o autor dos registos; fica **desativado e bloqueado** e a interface diz isso.
- **Repor palavra-passe:** fecha as sessões de empresa desse funcionário e fica na auditoria. **Não** permite redefinir a própria conta (sem fluxo de recuperação para prestadores ainda).
- **Funcionários criados pelo administrador entram com o e-mail já confirmado** (é o administrador que garante o endereço e partilha a palavra-passe inicial).
- **Operador de terreno:** o PIN passa a ter **6 a 8 dígitos** (a interface pedia 4 a 8). O serviço de contas não aceita menos de 6; a proteção extra é a sessão de empresa (senha da empresa com bloqueio ao fim de 5 falhas). Se definir no Supabase um mínimo de palavra-passe superior a 6, os PIN de 6 dígitos deixam de ser aceites.
- A edição direta de `funcionarios` pela API foi **fechada** na `0006`: tudo passa por esta função.
- A permissão de pré-pagamento no terreno chama-se `confirm_field_prepayment` na interface; a política de pagamentos da `0003` usava `receive_cash`. A `0006` alinha-a com o nome da interface.

### Configuração do projeto Supabase a rever
- Authentication → Providers → Email: **Confirm email** ligado (para verificar o e-mail do administrador no registo).
- Authentication → Password: mínimo ≤ 6 se quiser PIN de 6 dígitos para operadores de terreno.
- Authentication → Rate limits: manter os limites por IP ativos.

## Acesso reservado (prestador e administração) e verificação em dois passos

O ecrã de entrada só serve o **cliente**: não mostra o prestador nem a administração, nem no «Criar perfil». Cada área reservada tem a sua porta, numa pasta própria, sem ligação a partir do site e com `noindex`:

| Porta | Quem usa |
|---|---|
| `app/prestador.html` | Prestadores: empresa e depois funcionário (e o pedido de inscrição da empresa) |
| `app/administracao.html` | Administração da plataforma |

A porta abre a aplicação e **apaga o parâmetro do endereço**: ao recarregar volta ao ecrã do cliente, e o endereço reservado não fica no histórico nem em ligações partilhadas. **Esconder não é proteger**: quem ler o código da página encontra o endereço. A proteção está no servidor:

- **Administração: código de 6 dígitos (TOTP).** Depois da palavra-passe, o ecrã pede o código da aplicação de autenticação (qualquer uma que leia o código QR). No **primeiro acesso** mostra o QR (gerado pelo Supabase, sem sites externos) para registar a aplicação.
- **A regra no servidor** (`0011`): com `exigir_mfa_admin = true`, só é administrador quem tem a sessão no nível `aal2`; todas as políticas e funções de administração passam por essa verificação. Sem o código, mesmo com a palavra-passe certa, a conta não lê nem altera nada.
- **Prestador:** as duas camadas que já existiam (empresa e depois funcionário) e o bloqueio por tentativas. **Ainda não existe** o link privado por empresa (fica para a fase seguinte).

**Pôr em funcionamento, por esta ordem** (a regra vem **desligada**, para ninguém ficar sem entrar):
1. No painel do Supabase, ativar o MFA por TOTP (*Authentication → Multi-factor*).
2. Entrar pela porta da administração e registar a aplicação de autenticação (1.º acesso). Sair e voltar a entrar com o código, para confirmar que funciona.
3. Só então ligar a regra, no SQL Editor: `update private.plataforma_config set valor = 'true' where chave = 'exigir_mfa_admin';`
4. **Recuperação** (perdeu o telemóvel): no SQL Editor, `update private.plataforma_config set valor = 'false' where chave = 'exigir_mfa_admin';`, entrar só com a palavra-passe e registar outra aplicação.

**Limites:** o SQL da `0011` e a ligação ao MFA do Supabase não foram executados contra um projeto real (o teste 02 tem 10 verificações próprias, `4c.1`–`4c.10`). Se o MFA não estiver ativo no projeto, o ecrã avisa e entra só com a palavra-passe **enquanto a regra estiver desligada**; com a regra ligada, essa conta fica sem entrar até se desligar a regra.

## Painel da administração (aprovar empresas e confirmar pagamentos)

Ficheiros: `app/administracao/servidor-1…2.js` + funções da administração em `app/comum/servidor-adaptador-1…2.js` + `00071_admin.sql`. Só ativo com o servidor configurado.

**Entrar:** pelo endereço reservado `…/app/administracao.html` (não aparece em nenhum menu nem ligação; ver «Acesso reservado»). A conta é uma conta normal do Supabase Auth que também esteja em `administradores_plataforma` (ver "Primeiro administrador da plataforma"). Qualquer outra conta, mesmo válida, recebe a mesma mensagem genérica e a sessão é terminada. Uma sessão guardada no separador só vale se o servidor ainda a reconhecer como administradora (não basta o `th_user`). Com servidor, **não se cria nenhuma conta de administrador local** no navegador.

**Fluxo:** a empresa regista-se (pendente) → a administração vê o **pagamento declarado** (método e referência) → confirma que o dinheiro chegou → autoriza a empresa → a empresa já pode iniciar sessão e aparece aos clientes.
- **Confirmar pagamento** (`confirmar_pagamento_subscricao`): exige marcar "verifiquei no extrato"; grava `pago_em` e quem confirmou, cria um **recibo interno** em `faturas_plataforma` (sem número fiscal: a fatura fiscal sai do software certificado), notifica a empresa e fica na auditoria. Não se confirma duas vezes.
- **Autorizar** (`decidir_empresa`): o servidor recusa se o pagamento não estiver confirmado; na interface o botão está desativado até lá.
- **Recusar / suspender:** o motivo é obrigatório e fica na auditoria e na notificação à empresa; as sessões de empresa fecham.
- **Reativar** uma empresa suspensa **retoma também a subscrição paga**.
- **Correção da `0002`:** `decidir_empresa()` suspendia a subscrição ao suspender a empresa e nunca a retomava ao reativar; a empresa ficava aprovada mas fora da lista dos clientes e sem o limite de funcionários do plano. A `0007` substitui a função (mesma assinatura).
- **Notificações:** o sino da administração lê as notificações do servidor (novo registo, pedido de subscrição…) e marca-as como lidas no servidor.
- **Faturação:** lista os recibos criados ao confirmar pagamentos (só leitura).

**O que continua local (dados de demonstração):** planos, comissões, conformidade, apoio, clientes, operações, relatórios, segurança/auditoria e definições. Os botões que alterariam dados locais de prestadores ou faturas (criar/eliminar prestador, redefinir palavra-passe, comprovativos, notas de crédito, faturas) mostram um aviso e não fazem nada.

**Limites e riscos a conhecer**
- **Não há como desfazer** uma confirmação de pagamento pela interface (corrige-se por SQL). Confirme só depois de ver o extrato.
- **Aviso por e-mail das decisões:** só funciona depois de configurar o envio (secção "Aviso por e-mail"). Sem isso, a empresa vê apenas a notificação dentro da aplicação.
- **O prazo de 48 h** de validação da versão local **não existe** no servidor: os pedidos pendentes não expiram.
- **Recomenda-se ativar autenticação de dois fatores (MFA) nas contas de administração** no Supabase: quem tiver a conta decide sobre pagamentos e acessos de todas as empresas.
- A conta de administração é uma conta normal de Supabase Auth: a palavra-passe segue as regras do projeto.

## Painel de indicadores da administração (logística transitária)

Ficheiros: `app/administracao/painel-1…2.js` (usa o motor `app/comum/painel-motor.js`), `app/administracao/painel.css`, `app/comum/painel.css` e `00101_painel.sql`. É o dashboard do administrador ("Centro de comando da plataforma").

**Dados reais vs. demonstração**
- **Com servidor** (sessão de administrador no servidor): números reais de `public.painel_administracao(dias)`, que o servidor calcula numa só chamada. Só a administração a executa; não devolve nomes de clientes, moradas nem e-mails.
- **Sem servidor** (modo local de testes): o mesmo painel com **dados fictícios** e uma faixa «DEMONSTRAÇÃO» bem visível, para apresentar o desenho. Nunca se mostram como reais.

**O que mostra e como se calcula**
| Bloco | Significado |
|---|---|
| Prestadores ativos / a aguardar validação | empresas aprovadas / pendentes |
| Receita recorrente mensal | soma das subscrições **ativas** (as anuais a 1/12). Não inclui pagamentos por confirmar |
| Encomendas em curso | estado diferente de «entregue» e «cancelada». O valor é o **preço do serviço de transporte** (não o valor da mercadoria nem receita da Elolog) |
| Conversão simulação → encomenda | encomendas criadas / simulações enviadas **no período** |
| Entregas concluídas | encomendas **criadas no período** que já estão entregues (não as entregues no período) |
| Atenção agora | pagamentos por confirmar; registos pendentes há mais de 48 h; encomendas sem movimento há mais de 7 dias; apoio aberto/escalado. Cada alerta abre a página certa |
| Pipeline logístico | retrato **atual**: quantas encomendas estão em cada etapa (aprovação → agendamento → recolha → armazém → expedição → trânsito → destino). «Entregue» é o acumulado |
| Funil comercial | simulações → propostas → aceites → encomendas → entregues, com a percentagem do passo anterior |
| Evolução semanal | encomendas criadas nas últimas 8 semanas (a última está em curso) |
| Rotas e prestadores | os 5 primeiros do período |
| Atividade recente | as 8 últimas ações da auditoria (só o tipo, o papel, a empresa e a hora) |

**Utilização**
- **Período** de 7, 30 ou 90 dias. O painel pede também o **dobro** (14, 60 ou 180) para calcular a **tendência** face ao período anterior (▲/▼ com a palavra, não só cor); o servidor aceita esses valores. **Atualiza sozinho a cada 30 s** quando o separador está visível e o dashboard aberto; botão «Atualizar» para forçar.
- **Modo apresentação** (▶): esconde a barra lateral, os controlos, o assistente e os avisos, e pede ecrã inteiro (se o navegador o recusar, funciona na mesma). **Esc** ou o botão ✕ saem.
- Se uma atualização falhar, **mantém os últimos dados** e avisa; se a primeira carga falhar, mostra o erro e «Tentar novamente».
- Um projeto novo mostra uma orientação em vez de zeros sem explicação.

**Personalizar:** cada pessoa escolhe os blocos e a ordem (guardado no navegador, por utilizador). O mesmo motor serve os dashboards do cliente e do prestador, que mostram blocos diferentes consoante o perfil e, no prestador, a função.

**Limites:** o SQL da `0010` não foi executado (o teste 02 tem 10 verificações próprias, `4b.1`–`4b.10`). Os valores monetários são em euros (as tarifas noutras moedas não são convertidas). Os dados vêm de toda a plataforma: não há ainda filtro por prestador.

## Aviso por e-mail (decisões e notificações)

**Serviço escolhido: Brevo** (plano gratuito). Motivo: o plano gratuito permanente dá **300 e-mails por dia** e API transacional; o Resend gratuito dá 100 por dia (3 000 por mês) e exige um domínio verificado antes de enviar qualquer e-mail. Os limites e as condições mudam com o tempo e foram lidos em páginas de terceiros, não na documentação oficial: **confirme-os na sua conta Brevo**. O plano gratuito pode acrescentar a marca da Brevo às mensagens.

**Desde a v59** o agendamento é criado por `select private.agendar_tarefas('https://<projeto>.supabase.co');` (a cada 5 minutos; o segredo fica no cofre e não é preciso `CRON_SECRET`). O ficheiro `agendar_emails.sql` fica só como referência.

**Como funciona.** Cada notificação que o servidor já cria (tabela `notificacoes`) gera uma linha por destinatário na fila `emails_fila` (`0008`). A Edge Function `enviar-emails` envia a fila pelo Brevo, a cada minuto (agendamento), com repetição em caso de falha. **Um problema com a fila nunca bloqueia uma decisão ou uma notificação.**

| Notificação | Quem recebe |
|---|---|
| `novo_prestador`, `pedido_subscricao`, `pedido_cliente`, `apoio` | administradores da plataforma |
| `empresa_aprovada`, `empresa_recusada`, `pagamento_confirmado` | administradores ativos da empresa |
| `nova_simulacao` | administradores e operadores ativos do prestador |
| `simulacao_aceite`, `simulacao_recusada`, `estado_encomenda` | o cliente |

**Segurança e abuso (o que foi desenhado e o que fica de fora)**
- **Só recebem e-mail endereços confirmados** no serviço de contas. Sem isto, alguém podia registar uma empresa com o e-mail de outra pessoa e enviar-lhe avisos. **Com "Confirm email" desligado no Supabase esta proteção desaparece:** mantenha-o ligado.
- **Máximo de 30 e-mails por pessoa em 24 h** (anti-inundação: um cliente a gerar centenas de simulações não consegue lotar a caixa de um prestador nem gastar a quota de todos). Os avisos dentro da aplicação continuam.
- **Teto diário de 250** (abaixo dos 300 do plano). O excedente fica na fila para o dia seguinte; o Brevo repõe o limite à meia-noite UTC. E-mails com mais de 3 dias na fila expiram.
- **O conteúdo é mínimo:** título, o motivo/nota escrita pela administração ou pelo prestador, e uma ligação para a aplicação. **Nunca** palavras-passe, PIN nem dados de encomendas. Tudo o que escreve uma pessoa é escapado no HTML; o assunto é sempre uma linha.
- **A função só aceita chamadas com `x-cron-secret`** (comparação em tempo constante). Sem `CRON_SECRET` definido recusa tudo. A chave do Brevo e o segredo só existem como segredos da Edge Function.
- **Não há preferências nem "cancelar subscrição"**: são avisos de serviço, sem escolha por pessoa. Para parar tudo: `EMAIL_ATIVO=false` (a fila acumula) ou `select cron.unschedule('elolog-enviar-emails');`.
- **Atraso:** até cerca de 1 minuto. A administração recebe **um e-mail por notificação** (um registo novo gera dois: inscrição e subscrição).
- A empresa só é avisada se o administrador dela tiver o e-mail **confirmado**. Um pedido recusado antes de o administrador confirmar o e-mail não gera aviso.

**Configurar (uma vez)**
1. **Brevo:** criar conta; em *Senders, Domains & Dedicated IPs* validar um **remetente** (rápido, serve para testar) ou, melhor para a entrega, um **domínio** (registos SPF/DKIM). Criar uma **chave API (v3)** em *SMTP & API*.
2. **Segredos e publicação:**
```bash
supabase secrets set CRON_SECRET="$(openssl rand -hex 32)" BREVO_API_KEY="<chave API v3>" \
  EMAIL_REMETENTE="avisos@o-seu-dominio.pt" EMAIL_NOME="Elolog" APP_URL="https://o-seu-endereço/Area%20de%20Cliente/Area%20de%20Cliente.html"
supabase functions deploy enviar-emails --no-verify-jwt
```
   (guarde o `CRON_SECRET`: será preciso no passo 4.) Opcionais: `EMAIL_LIMITE_DIARIO` (250), `EMAIL_LOTE` (20), `EMAIL_ATIVO`.
3. **Testar o envio** sem passar pela fila:
```bash
curl -X POST "https://<referência>.supabase.co/functions/v1/enviar-emails" \
  -H "x-cron-secret: <CRON_SECRET>" -H "Content-Type: application/json" -d '{"teste":"o-seu-email@exemplo.pt"}'
```
   Se o Brevo recusar, a resposta traz `resultado` (`configuracao` = chave ou remetente não aceites) e um detalhe curto.
4. **Agendar** com `agendar_emails.sql` (pg_cron + pg_net), trocando a referência do projeto e o `CRON_SECRET`. O ficheiro tem também as consultas para acompanhar a fila (enviados, pendentes, falhas) e reenviar um e-mail.

**Limites desta fase:** a fila e as funções SQL **não foram executadas** (sem PostgreSQL); as funções foram testadas com o Brevo e a base de dados **simulados**: a API real do Brevo, o `pg_cron`/`pg_net` e a entrega em caixas de correio reais **não foram testados**. Os formatos de erro do Brevo usados para classificar falhas (por exemplo, remetente não validado) são uma suposição. Só há e-mail para o que já cria uma notificação no servidor: por exemplo, o cliente aceitar uma proposta ou cancelar uma simulação ainda **não** avisa o prestador. O cliente recebe um e-mail por **cada** mudança de estado da encomenda (até 9 por encomenda).

## Cálculo de preços no servidor (decidido)

Os clientes **não leem a tabela `tarifas`**. O preço calcula-se no servidor e devolve só o total por prestador:

```js
// pré-visualização (substitui o cálculo em atualizarPrestadoresCliente)
const { data } = await supabase.rpc('calcular_propostas', {
  p_origem, p_destino, p_tipo_carga, p_quantidade, p_peso_kg, p_volume_m3, p_recolha_km
});
// → [{ prestador_id, prestador_nome, disponivel, preco_total, moeda }]  (disponivel=false → "A aguardar tarifa")

// envio explícito: o servidor recalcula e guarda o preço (o valor do navegador nunca é usado)
await supabase.rpc('enviar_simulacao', { p_simulacao, p_empresa });
```

`enviar_simulacao` guarda `preco_estimado` na simulação como base para a proposta do prestador. O cliente já não consegue escrever `estado`, `preco_estimado` nem o destinatário. A `aceitar_proposta` continua a usar o preço da **proposta**, não o da estimativa.

## Ligação do front-end (feita para o lado do CLIENTE)

Ficheiros: `app/comum/servidor-config.js` (URL e chave), `app/comum/servidor-adaptador-1…2.js` (adaptador) e `app/cliente/servidor.js`.
**Com `servidor/config.js` vazio nada muda** (modo local, como antes). Preenchido:

- **Login e registo do cliente** passam pelo Supabase Auth; a palavra-passe deixa de ser guardada no navegador (no modo local ainda é guardada em texto simples).
- **Propostas** vêm de `calcular_propostas` (um pedido agrupado por simulação).
- **Enviar ao prestador** grava a simulação e chama `enviar_simulacao`; o preço mostrado e guardado é o do servidor (se diferir do cartão, a mensagem diz "atualizado pelo servidor").
- **Sair** termina também a sessão no servidor.

### Passos para ligar
1. Criar o projeto no Supabase e executar `0001` → `0010` no SQL Editor.
2. (Só para testar) executar `seed_teste.sql`: cria 1 prestador aprovado com 2 tarifas.
3. Authentication → Providers → Email: decidir se exige confirmação de e-mail e, em URL Configuration, indicar o endereço onde a app está alojada.
4. Copiar o *Project URL* e a chave *anon* para `app/comum/servidor-config.js` (nunca a `service_role`).
   **Colocar também a biblioteca em `app/comum/supabase.js`** (instruções em `app/LEIA-ME.md`): a aplicação não pede código a outros sites. Sem este ficheiro, com servidor configurado, o ecrã diz «Falta o ficheiro app/comum/supabase.js».
5. Criar uma conta de cliente pelo ecrã de registo e fazer uma simulação Lisboa → Luanda.

## Ligação do prestador (feita)

Ficheiros: `app/prestador/servidor.js` + funções do prestador em `app/comum/servidor-adaptador-1…2.js`. Só ativo com o servidor configurado.

- **Login em dois níveis, aplicado pelo servidor.** 1.º nível: nome + NIF + palavra-passe da empresa (`validar_empresa`, 5 falhas bloqueiam 15 min). 2.º nível: e-mail e palavra-passe do funcionário (Supabase Auth) e `abrir_sessao_empresa`, que abre uma **sessão de empresa de 12 h**. Sem essa sessão, as políticas RLS não devolvem nada ao prestador, mesmo com a conta de funcionário certa. A palavra-passe da empresa só vive em memória durante o login.
- **Cotações:** simulações que os clientes enviaram à empresa, com rota, preço (calculado pelo servidor), destinatário, morada de entrega, recolha e observações. Atualizam sozinhas (20 s e ao voltar ao separador).
- **Aceitar** (`aceitar_simulacao`): cria a proposta aceite ao preço do servidor e a encomenda em "aprovação"; o cliente é notificado. **Recusar** (`recusar_simulacao`): exige motivo e notifica o cliente.
- **Aprovação:** aprovar (→ agendamento) ou rejeitar (→ cancelada, com nota) através de `transitar_encomenda`. As restantes encomendas aparecem em lista **só de leitura**.
- Se a sessão de empresa expirar, a app avisa e pede novo login.

### Funcionário de teste
Authentication → Add user (`operador@transitaria-teste.pt`, "Auto Confirm User") e depois executar o bloco final de `seed_teste.sql`. Empresa de teste: `Transitária Teste, Lda` · NIF `500000001` · senha `senha-empresa-teste` (apenas para testes).

### Limites desta fase
- **Registo de prestadores e gestão de funcionários:** ligados pelas Edge Functions (secção acima). A aprovação de empresas e a confirmação de pagamentos fazem-se no painel da administração (secção acima).
- **Do prestador só estão ligados** login, cotações, aceitar/recusar e aprovação. O acompanhamento (recolha, armazém, expedição, manifestos), pagamentos, documentos e financeiro continuam locais. O histórico de logins da equipa ainda é local. Uma encomenda aprovada só aparece na lista de leitura.
- **O cliente ainda não vê o estado:** as notificações e o estado das encomendas ficam gravados no servidor, mas a área do cliente ainda não os lê.
- **Ainda não há contraproposta** (preço diferente do calculado): o prestador aceita ou recusa.
- Testado com um Supabase **simulado** no Chromium; o SQL da `0005` a `0008` não foi executado (sem PostgreSQL), as Edge Functions não foram executadas em Deno (só verificadas em tipos estritos e testadas com dependências simuladas) e o ficheiro `supabase.js` tem de ser obtido por quem tenha internet (o comando de `app/LEIA-ME.md` não foi executado).
- Um mesmo e-mail não deve ser cliente e funcionário: o primeiro login de cliente cria sempre a linha em `clientes`.

## Decisões a confirmar

- **Recolha:** o front-end cobra 1 €/km; está fixo em `private.custo_recolha_por_km()`. Se for outra regra, é aí que se muda.
- **Desempate** entre tarifas igualmente específicas: o front-end usava a ordem de gravação; o SQL usa a versão mais recente.
- **Só tarifas de aplicação "carga"** entram no preço da carga (o front-end podia apanhar também as de recolha).
- **`peso_kg` é o peso total** da carga. O fator volumétrico lê-se de `tarifas.regras->>'volumetricFactor'` (167 por omissão, como no código atual) e a migração de dados deve manter essa chave.
- **Moeda:** soma a recolha (calculada a 1 €/km) ao preço da tarifa sem converter moedas.
- **Extensão `unaccent`** (comparações sem acentos, como o `norm()` do JS): a 0004 ativa-a no schema `extensions`.

- **Documentos e ficheiros não se alteram nem apagam** pela API (versionamento). O botão "apagar documento" da interface terá de passar a "arquivar/nova versão".
- **O cliente pode editar uma simulação enquanto está `enviada`** (antes de ser respondida). Se preferires bloquear logo após o envio, remove `'enviada'` do `using` de `sim_cliente_editar`.
- **`select *` em `empresas`**: já não expõe segredos, mas o front-end deve pedir colunas explícitas.

## Teste mínimo sugerido

Com 2 empresas, 1 cliente e 1 operador de terreno: (1) a empresa A não vê dados da B; (2) um rascunho não aparece ao prestador; (3) `calcular_propostas` devolve `disponivel=false` para um prestador sem tarifa na rota e um cliente não consegue `select` em `tarifas`; (4) `transitar_encomenda` recusa saltar etapas e recusa `armazenamento` sem pagamento/assinatura; (5) o operador de terreno só vê os seus serviços; (6) `update simulacoes set estado=…` e `update encomendas set estado=…` direto falha.
