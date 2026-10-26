# Cópias de segurança

O plano gratuito do Supabase não guarda cópias que se possam descarregar. Por isso a Elolog faz a sua própria cópia, todos os dias às 02:23 (UTC), com o GitHub Actions (gratuito): `.github/workflows/copia-seguranca.yml`.

## O que é copiado

- **Base de dados**: papéis, estrutura (tabelas, funções, regras de acesso) e todos os dados, com o método indicado pelo Supabase (`supabase db dump`).
- **Ficheiros**: tudo o que está no armazenamento (faturas, documentos, fotografias), com `ferramentas/copia-armazenamento.mjs`.
- Tudo é comprimido e **cifrado com AES-256** antes de sair da máquina do GitHub e fica 30 dias nos artefactos do repositório (privado).

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
