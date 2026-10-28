# Elolog — pôr em produção (v65)

Tudo o que falta ativar já está construído e testado. Esta página diz o que fazer, por esta ordem.

| Ponto | Estado no projeto «Elolog» | Falta fazer (por si) | Custo |
|---|---|---|---|
| Emails | Fila, modelos e envio a cada 5 minutos ativos | Criar conta Brevo e definir 3 segredos | Grátis até 300 emails/dia |
| Documentos | Armazenamento privado por empresa e por cliente, 20 MB por ficheiro | Nada | Grátis até 1 GB |
| Faturas certificadas | Leitura do QR da AT, validação e registo | Cada empresa usa o seu programa certificado | Grátis na Elolog |
| Pagamentos | Multibanco e MB WAY pela ifthenpay, aviso automático e verificação a cada 10 min | Cada empresa pede chaves à ifthenpay e grava-as na Elolog | Comissão da ifthenpay por pagamento |
| Navios (AIS) | Leitura a cada 30 minutos dos navios seguidos | Criar chave gratuita no aisstream.io | Grátis |
| Cópias de segurança | Cópia diária cifrada no GitHub Actions | Definir 2 a 4 segredos no GitHub | Grátis |

## Pôr a funcionar no projeto «Elolog» (wcggcpdiswbzrdpwgdpb)

Já feito: tabelas base (00011–00013), as 7 Edge Functions publicadas e a aplicação ligada ao projeto. Falta, por esta ordem:

1. **Base de dados** — Supabase › SQL Editor › New query › colar todo o `servidor/supabase/instalar_projeto_elolog.sql` › Run. No fim aparece «Tarefas agendadas: …». (Uma só transação: ou fica tudo instalado, ou nada muda.)
2. **Primeiro administrador** — Authentication › Users › Add user › Create new user (o seu email, uma palavra-passe forte, «Auto Confirm User» ligado). Depois, no SQL Editor:
   ```sql
   insert into administradores_plataforma (user_id, nome, email, papel)
   select id, 'Administração Elolog', email, 'admin' from auth.users where email = 'O_SEU_EMAIL';
   ```
   Entre em `https://www.elolog.pt/app/area-cliente.html?acesso=administracao`. Para criar a equipa Elolog ative o código de autenticação (2.º fator) no seu perfil.
3. **Endereços** — Authentication › URL Configuration: Site URL `https://www.elolog.pt/app/area-cliente.html`; Redirect URLs `https://www.elolog.pt/**`.
4. **Segredos** — Edge Functions › Secrets: `BREVO_API_KEY`, `EMAIL_REMETENTE` (`notificacoes@elolog.pt`), `APP_URL` e `SITE_URL` (`https://www.elolog.pt/app/area-cliente.html`); opcional `AISSTREAM_API_KEY`.
5. **Cópias de segurança** — no GitHub, atualizar `SUPABASE_DB_URL` (e `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`) para o projeto novo (ver `COPIAS_DE_SEGURANCA.md`).
6. **Prestadores e pagamentos** — cada empresa regista-se em «Tornar-se prestador»; a administração aprova; a empresa cria tarifas e, se quiser pagamentos online, grava as chaves ifthenpay.

## Domínio elolog.pt

O endereço principal é **https://www.elolog.pt** (o ficheiro `CNAME` na raiz do projeto já o indica ao GitHub Pages). A aplicação fica em `https://www.elolog.pt/app/area-cliente.html`.

**1. Registos DNS** (painel do registador do elolog.pt, «Zona DNS» / «Gestão de DNS»):

| Tipo | Nome | Valor | Para quê |
|---|---|---|---|
| A | `@` (elolog.pt) | `185.199.108.153` | site (GitHub Pages) |
| A | `@` | `185.199.109.153` | site |
| A | `@` | `185.199.110.153` | site |
| A | `@` | `185.199.111.153` | site |
| CNAME | `www` | `sibercosta.github.io.` | site |
| TXT | `@` | o código `brevo-code:…` dado pela Brevo | email (prova de posse) |
| CNAME | `brevo1._domainkey` | valor dado pela Brevo | email (DKIM) |
| CNAME | `brevo2._domainkey` | valor dado pela Brevo | email (DKIM) |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com` | email (DMARC) |

Apague antes os registos A/CNAME de «página de estacionamento» que o registador tenha criado para `@` e `www`. Os valores da Brevo são próprios da sua conta: copie-os de Brevo › Senders, Domains & Dedicated IPs › **Domains › Add a domain** (elolog.pt) › «Authenticate». A propagação demora de minutos a algumas horas.

**2. GitHub**: repositório › Settings › Pages › Custom domain: `www.elolog.pt` › Save; quando o certificado ficar pronto, ligar **Enforce HTTPS**. O `elolog.pt` sem «www» passa a redirecionar sozinho para `www.elolog.pt`.

**3. Brevo**: depois de o domínio ficar «Authenticated», em Senders crie `Elolog <notificacoes@elolog.pt>`.

**4. Supabase**
- Authentication › URL Configuration › Site URL: `https://www.elolog.pt/app/area-cliente.html`; Redirect URLs: `https://www.elolog.pt/**` (mantenha também `https://sibercosta.github.io/**` enquanto houver links antigos).
- Edge Functions › Secrets: `EMAIL_REMETENTE` = `notificacoes@elolog.pt`, `APP_URL` e `SITE_URL` = `https://www.elolog.pt/app/area-cliente.html`, `BREVO_API_KEY` = chave da Brevo.

**5. Receber emails** (contacto@elolog.pt): a Brevo só envia. Para receber, use o reencaminhamento de email do registador (muitos incluem-no grátis) ou o ImprovMX (grátis): aponta `contacto@elolog.pt` para o seu Gmail com 2 registos MX.

## 0. Email de confirmação de conta (abre «localhost:3000»)

O Supabase usa o «Site URL» para onde reencaminha depois de o utilizador confirmar o email; por omissão é `http://localhost:3000`.
1. Supabase › Authentication › URL Configuration › **Site URL**: o endereço público da aplicação (`https://www.elolog.pt/app/area-cliente.html`).
2. Em **Redirect URLs** acrescente `https://<o seu domínio>/app/area-cliente.html*` (e o endereço de testes, se tiver).
3. Supabase › Edge Functions › Secrets: `SITE_URL` com o mesmo endereço (usado no registo das empresas).

A aplicação já pede ao Supabase para voltar à página onde a conta foi criada e, ao regressar, mostra «Email confirmado. Já pode iniciar sessão» (ou um aviso claro se o link tiver expirado). Os links já enviados antes desta alteração continuam a ir para o endereço antigo: peça um novo email.

## 1. Emails (Brevo)

1. Crie conta em brevo.com e valide o endereço remetente (Senders & IP › Senders).
2. Supabase › Edge Functions › Secrets: `BREVO_API_KEY` (chave API v3), `EMAIL_REMETENTE` (o endereço validado), `APP_URL` (endereço público da aplicação).
3. Teste: SQL Editor → `select private.chamar_funcao('enviar-emails', '{"teste":"o-seu-email@exemplo.pt"}');` e veja a resposta em `select status_code, content from net._http_response order by id desc limit 1;`.

O agendamento já está ativo (`elolog-emails`, a cada 5 minutos). Enquanto os segredos não existirem a função responde «fornecedor não configurado» e os emails ficam na fila sem se perderem.

## 2. Documentos

Não precisa de nada. Os ficheiros ficam no bucket privado `documentos`, numa pasta por empresa (ou por cliente). Só abre quem tem acesso ao registo em `documentos`; os links de descarga duram 2 minutos. Formatos: PDF, JPG, PNG, WEBP, Word e Excel, até 20 MB.

## 3. Faturas certificadas

A lei exige que a fatura saia de um programa certificado pela AT; a Elolog não a emite. O fluxo é: **Financeiro › Registar fatura certificada** (ou Documentos) → carregar o PDF → a plataforma lê o código QR → mostra o resumo (número, ATCUD, NIF, IVA, total) → confirmar. O servidor volta a verificar: NIF do emitente igual ao da empresa, NIF do cliente válido e igual ao da encomenda, ATCUD, data, fatura repetida e total acima do preço da encomenda. O cliente recebe um aviso e vê a fatura nos seus documentos.

## 4. Pagamentos (ifthenpay)

Para cada empresa prestadora:

1. Contrato com a ifthenpay e pedido das chaves **Multibanco (dinâmico)** e **MB WAY**, e de uma **chave anti-phishing**. Peça primeiro chaves de teste (sandbox).
2. Na Elolog, o administrador da empresa abre **Empresa e configurações › Pagamentos online**, grava as chaves, deixa «Modo de testes» ligado e ativa.
3. Dê à ifthenpay o endereço de aviso que aparece nessa janela:
   `https://<projeto>.supabase.co/functions/v1/pagamentos-aviso?key=[ANTI_PHISHING_KEY]&orderId=[ORDER_ID]&amount=[AMOUNT]&requestId=[REQUEST_ID]`
4. Faça um pagamento de teste como cliente; depois desligue «Modo de testes».

O cliente escolhe Multibanco (recebe entidade, referência e prazo de 3 dias) ou MB WAY (recebe o pedido na app e tem 4 minutos). O valor é sempre calculado no servidor (preço da encomenda menos o que já foi pago). Um aviso com chave ou valor errados é recusado e repetir o aviso não paga duas vezes. Se a ifthenpay mudar os endereços da API, defina `IFTHENPAY_MB_URL`, `IFTHENPAY_MB_SANDBOX_URL`, `IFTHENPAY_MBWAY_URL` ou `IFTHENPAY_MBWAY_ESTADO_URL` nos segredos das Edge Functions.

## 5. Navios em tempo real (AIS)

1. Crie conta gratuita em aisstream.io e gere uma chave.
2. Supabase › Edge Functions › Secrets: `AISSTREAM_API_KEY`.
3. Na Elolog: **Armazém › Navios em tempo real** → nome do navio e MMSI (9 dígitos). A cada 30 minutos aparecem posição, velocidade, destino e ETA declarados pelo navio, com ligação ao mapa.

## 6. Cópias de segurança

Ver `COPIAS_DE_SEGURANCA.md`.

## Num projeto novo do Supabase

1. Aplicar as migrações por ordem (`servidor/supabase/migrations`).
2. Publicar as funções: `registar-prestador`, `gerir-funcionarios`, `gerir-equipa`, `enviar-emails`, `pagamentos`, `pagamentos-aviso`, `navios-ais` (todas com `--no-verify-jwt`; validam o acesso no código).
3. SQL Editor: `select private.agendar_tarefas('https://<projeto>.supabase.co');` — cria o segredo do agendador no cofre e as 4 tarefas.
4. Correr os testes `servidor/supabase/testes/01`, `02` e `05` (o 5 cobre faturas, pagamentos, navios e documentos: 39 verificações).
