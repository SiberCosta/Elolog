# Testar o Elolog num projeto Supabase de teste

Quem escreveu este código **não conseguiu executar o SQL nem as Edge Functions num Supabase real** (sem rede, sem PostgreSQL,
sem acesso a projetos). O que foi testado está em "O que já foi verificado". Estes ficheiros servem para **apanhar o que só
aparece na primeira execução** e dizer, com precisão, o que falhou.

> **Use um projeto de teste novo e vazio.** Não use produção. Não partilhe chaves `service_role`: nada aqui as pede.

## Ordem (cerca de 30–40 minutos)

| Passo | O que fazer | O que enviar de volta |
|---|---|---|
| 1 | SQL Editor: executar `migrations/` por ordem (do `00011_…` ao `01111_…`), **uma de cada vez**, por ordem | a **primeira mensagem de erro** (com o nome do ficheiro), se houver |
| 2 | Executar `testes/01_instalacao.sql` (só leitura) | as linhas **FALHA** e **AVISO** |
| 3 | Executar `testes/02_comportamento.sql` | o **relatório completo** (vem como mensagem de erro; é propositado e desfaz tudo) |
| 4 | Publicar as 3 Edge Functions e definir segredos (`LEIA-ME.md`, secção "Edge Functions") e correr `bash testes/03_funcoes_http.sh` | a saída completa |
| 5 | Configuração do Supabase (lista abaixo) | o que não conseguir fazer ou ver |
| 6 | Teste manual no navegador (lista abaixo) | o passo em que falha e o que aparece |

Se o passo 1 falhar, **pare aí** e envie o erro: o resto depende dele.

## Como ler os resultados
- **01_instalacao.sql** devolve `FALHA` / `AVISO` / `OK`. `AVISO` = convém rever (por exemplo, o administrador da plataforma sem e-mail confirmado, ou `pg_cron` por ativar).
- **02_comportamento.sql** termina com um erro **propositado** cuja mensagem é o relatório: `✔` passou, `✘` falhou com o motivo. Nos testes que esperam um bloqueio mostra `[motivo: …]`: confirme que o motivo é o certo (por exemplo `permission denied`) e não outro erro por acaso.
  Um erro **antes** do relatório significa que a preparação dos dados falhou: envie-o.
- **03_funcoes_http.sh** imprime `PASS` / `FAIL` / `AVISO` e termina com código de saída diferente de 0 se algo falhou.
- Uma falha pode ser **do teste e não do esquema**: envie sempre o relatório completo, não só a linha.

## Passo 5 — configuração do projeto (não se vê por SQL)
1. **Authentication → Providers → Email → Confirm email: LIGADO.** (Sem isto, os avisos por e-mail deixam de estar protegidos contra moradas alheias.)
2. **Authentication → Password:** mínimo ≤ 6 se quiser PIN de 6 dígitos para operadores de terreno.
3. **Settings → API → Exposed schemas:** só `public` (e `graphql_public`). **`private` não pode estar exposto.**
4. **Authentication → URL Configuration:** o endereço onde a aplicação está alojada.
5. **Database → Extensions:** `pg_cron` e `pg_net` ativos (para o envio de e-mails).
6. Criar a conta do administrador da plataforma (Authentication → Users) e inseri-la:
   `insert into administradores_plataforma (user_id, nome) values ('<uuid>', 'Administração');`
7. `app/comum/servidor-config.js` com o *Project URL* e a chave **anon** (nunca a `service_role`) e o ficheiro `app/comum/supabase.js` (ver `app/LEIA-ME.md`).

## Passo 6 — teste manual no navegador (ordem lógica)
1. **Registo de prestador** no ecrã de registo (plano Básico, pagamento "declarado"). Esperado: mensagem de pedido enviado; e-mail de confirmação do Supabase.
2. **Confirmar o e-mail** do administrador da empresa.
3. `…/app/administracao.html`: entrar como administrador da plataforma. Esperado: o pedido aparece em "Pedidos de inscrição" com o pagamento **por confirmar**.
4. Tentar **Autorizar** sem confirmar o pagamento (botão desativado). Depois **Confirmar pagamento** e **Autorizar**.
5. Entrar como **prestador** (nome + NIF + palavra-passe da empresa; depois e-mail e palavra-passe do administrador). Esperado: entra.
6. Em **Funcionários**: criar um operador; entrar com ele noutro separador.
7. Registar-se como **cliente**, fazer uma simulação Lisboa → Luanda e enviá-la a esse prestador (precisa de uma tarifa criada: ver `seed_teste.sql`).
8. No prestador: ver a simulação em Cotações, **aceitar**. No cliente: ver a notificação.
9. Se configurou o Brevo: confirmar que chegaram os e-mails (aprovação da empresa, pagamento, simulação aceite).

## O que já foi verificado (para não repetir)
- **Estático:** parênteses e blocos `$$` equilibrados nas migrações 0002–0009; todas as colunas dos 74 `INSERT`/`UPDATE` das migrações existem nas tabelas; todas as funções chamadas existem; os parâmetros das chamadas `rpc` do front-end coincidem com as funções SQL; as colunas das consultas diretas do front-end e as permissões por coluna de `simulacoes` coincidem.
- **Código:** 108 testes das Edge Functions (dependências simuladas) e ~160 verificações de navegador (Supabase simulado); tipos TypeScript em modo estrito.
- **HTTP:** `03_funcoes_http.sh` foi corrigido contra um servidor local que usa os handlers reais (14 PASS no cenário completo).
- **NÃO verificado:** todo o SQL em PostgreSQL real, o `00011_base_parte1.sql + 00012_base_parte2.sql + 00013_base_parte3.sql` (de origem desconhecida), o RLS/permissões a sério, `pg_cron`/`pg_net`, o Brevo real, o serviço de contas (códigos de erro do `signUp`/`createUser`), o ficheiro `supabase.js` (tem de ser colocado em `js/vendor`, ver `app/LEIA-ME.md`).

## Teste 2 — `02_comportamento.sql`

- Elolog · TESTE 2 — Comportamento (isolamento entre empresas, preços, fluxo, administração, e-mails)
- COMO CORRER: SQL Editor do projeto de TESTE, depois das migrações 0001–0011 e do teste 01. Cole tudo e execute.
- O QUE VAI VER: um ERRO no fim, de propósito. A mensagem do erro é o RELATÓRIO (✔ passou / ✘ falhou).
  Isso é o que faz o PostgreSQL desfazer TUDO o que o teste criou: não fica nenhum dado no projeto.
  Se o erro for outro (antes do relatório), copie-o: indica o primeiro ponto onde algo falhou na preparação.
- Os e-mails de teste usam o domínio reservado ".invalid" (nunca entregue) e nada é enviado: a transação é desfeita.
- Cada teste corre com o papel e o utilizador reais (SET ROLE + JWT), por isso testa as permissões e o RLS a sério.
- NÃO FOI EXECUTADO por quem o escreveu: uma falha pode ser do teste e não do esquema. Envie o relatório completo.
- Não corra em produção.

## Teste 6 — `06_email.sql` (v67)

- Permissões e cofre das caixas de email: 20 verificações (quem vê, quem grava, a palavra-passe só pela chave de serviço, apagar a caixa apaga o segredo). Correu 20/20 numa base PostgreSQL 16 local com todas as migrações. Só em base de testes.
