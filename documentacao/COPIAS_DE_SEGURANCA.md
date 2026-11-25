# Cópias de segurança

O plano gratuito do Supabase não guarda cópias que se possam descarregar. Por isso a Elolog faz a sua própria cópia, todos os dias às 02:23 (UTC), com o GitHub Actions (gratuito): `.github/workflows/copia-seguranca.yml`.

## O que é copiado

- **Base de dados**: papéis, estrutura (tabelas, funções, regras de acesso) e todos os dados, com o método indicado pelo Supabase (`supabase db dump`).
- **Ficheiros**: tudo o que está no armazenamento (faturas, documentos, fotografias), com `ferramentas/copia-armazenamento.mjs`.
- Tudo é comprimido e **cifrado com AES-256** antes de sair da máquina do GitHub e fica 30 dias nos artefactos do repositório. O repositório é **público** (o site é servido pelo GitHub Pages): sem a `COPIA_SENHA` a cópia não se lê, por isso use uma frase longa e única.

## Ativar (uma vez)

No repositório do GitHub: Settings › Secrets and variables › Actions › New repository secret.

| Segredo | Onde obter |
|---|---|
| `SUPABASE_DB_URL` | Supabase › Project Settings › Database › Connection string › **Session pooler** (substitua `[YOUR-PASSWORD]`) |
| `COPIA_SENHA` | Uma frase longa (16+ caracteres) inventada por si. **Guarde-a fora do GitHub**: sem ela a cópia não abre |
| `SUPABASE_URL` | (para os ficheiros) `https://<projeto>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | (para os ficheiros) Project Settings › API › service_role. Fica só nos segredos do GitHub |

Depois: separador Actions › «Cópia de segurança diária» › **Run workflow** para a primeira cópia. Se algo falhar, o GitHub envia um email.

## Repor

1. Actions › escolher a cópia › descarregar o artefacto e descomprimir o ZIP.
2. Decifrar: `gpg -d elolog-AAAA-MM-DD-HHMM.tar.gz.gpg | tar -xzf -` (pede a `COPIA_SENHA`).
3. Base de dados num projeto vazio (pasta `copia/base-de-dados`):

   ```
   psql --single-transaction --variable ON_ERROR_STOP=1 \
     --file roles.sql --file schema.sql \
     --command 'SET session_replication_role = replica' \
     --file data.sql --dbname "<ligação do projeto novo>"
   ```
4. Ficheiros: criar os buckets com as definições de `copia/armazenamento/buckets.json` e voltar a carregar as pastas (Storage no painel, ou a API).
5. Publicar as funções e correr `select private.agendar_tarefas('https://<projeto novo>.supabase.co');` (ver `PRODUCAO.md`).

Faça um ensaio de reposição num projeto de teste pelo menos uma vez por trimestre.


## Segunda cópia: Cloudflare R2 (v140)

Duas cópias independentes:
1. **GitHub Actions** (`.github/workflows/copia-seguranca.yml`): cópia **completa** (estrutura, dados e ficheiros) todas as noites, cifrada, guardada 30 dias como artefacto do repositório (que deve ser **privado**).
2. **Cloudflare** (Worker + R2, plano gratuito): cópia dos **dados** (todas as tabelas de `public` e `private`), cifrada no Supabase antes de sair, guardada 30 dias no R2.

**Como funciona a do Cloudflare**: às 03:15 (UTC) o Worker `ferramentas/cloudflare/copia-worker/worker.js` chama a Edge Function `copia-dados` com o cabeçalho `x-copia-token`; a função exporta (`servico_exportar_dados`, só service_role), comprime e cifra (AES-256-GCM, chave PBKDF2 a partir de `COPIA_SENHA`) e devolve o ficheiro `AAAA-MM-DD.elolog-copia`, que o Worker grava no R2. O Worker nunca vê os dados em claro.

**Instalar**
- Supabase › Edge Functions › Secrets: `COPIA_TOKEN` (texto aleatório longo) e `COPIA_SENHA` (16+ caracteres; guarde-a fora do Supabase e do Cloudflare — sem ela a cópia não se abre).
- Cloudflare › R2 › Criar bucket `elolog-copias` (privado). Na primeira vez o Cloudflare pede um meio de pagamento para verificação; o plano gratuito tem 10 GB.
- Cloudflare › Workers e Pages › Criar › Worker «elolog-copias» › Editar código › colar `worker.js` › Implementar.
  - Definições › Ligações › Adicionar › R2 bucket: variável `COPIAS`, bucket `elolog-copias`.
  - Definições › Variáveis e segredos › Adicionar › Segredo `COPIA_TOKEN` (o mesmo do Supabase).
  - Definições › Acionadores › Cron › `15 3 * * *`.
- Testar: no editor do Worker, separador «Agendado» › acionar; depois ver o ficheiro do dia em R2 › `elolog-copias` › `elolog/`.

**Repor**: descarregar o ficheiro do R2 e correr `COPIA_SENHA='…' node ferramentas/repor-copia.mjs AAAA-MM-DD.elolog-copia`. Cria `.json` (dados em claro) e `.sql`. Num projeto com a estrutura instalada (`instalar_projeto_elolog.sql`), correr o `.sql` no editor SQL: insere só o que falta, desliga os gatilhos de cada tabela durante a importação e repete as tabelas que dependem de outras. Validado com os dados reais (27 tabelas com registos, uma passagem).
