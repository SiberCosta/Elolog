// Elolog — abrir uma cópia «.elolog-copia» (Cloudflare R2) e preparar a reposição (v140). Precisa só do Node 20+.
// Uso:  COPIA_SENHA='a sua senha' node ferramentas/repor-copia.mjs 2026-11-16.elolog-copia
// Cria, ao lado do ficheiro: <nome>.json (os dados em claro — guarde com cuidado) e <nome>.sql (reposição).
// Repor: num projeto com a estrutura instalada (servidor/supabase/instalar_projeto_elolog.sql), correr o .sql no editor SQL do
// Supabase. Insere os registos que faltam (não substitui os que já existem) com os gatilhos desligados durante a importação.
import { readFileSync, writeFileSync } from 'node:fs';
import { webcrypto as crypto } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
const [ficheiro] = process.argv.slice(2), senha = process.env.COPIA_SENHA || '';
if (!ficheiro || senha.length < 16) { console.error('Uso: COPIA_SENHA=... node ferramentas/repor-copia.mjs <ficheiro.elolog-copia>'); process.exit(1); }
const b = new Uint8Array(readFileSync(ficheiro));
if (new TextDecoder().decode(b.slice(0, 5)) !== 'ELOC1') { console.error('Não é uma cópia Elolog (cabeçalho ELOC1 em falta).'); process.exit(1); }
const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(senha), 'PBKDF2', false, ['deriveKey']);
const chave = await crypto.subtle.deriveKey({ name: 'PBKDF2', salt: b.slice(5, 21), iterations: 210000, hash: 'SHA-256' }, base, { name: 'AES-GCM', length: 256 }, false, ['decrypt']);
let claro; try { claro = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: b.slice(21, 33) }, chave, b.slice(33))) } catch { console.error('Senha errada ou ficheiro danificado.'); process.exit(1); }
const dados = JSON.parse(gunzipSync(claro).toString('utf8'));
writeFileSync(ficheiro + '.json', JSON.stringify(dados, null, 1));
const q = s => '"' + s.replace(/"/g, '""') + '"', todo = JSON.stringify(dados.tabelas);
let tag; do { tag = '$c' + Math.random().toString(36).slice(2, 10) + '$' } while (todo.includes(tag));   // marca que não aparece nos dados
const sql = ['-- Reposição Elolog gerada a partir de ' + ficheiro + ' (' + dados.gerado_em + ', ' + dados.registos + ' registos)',
  '-- Corre no editor SQL do Supabase, num projeto com a estrutura instalada. Insere só o que falta; repete as tabelas que dependem de outras.',
  'begin;', 'create temp table _copia_elolog (tabela text primary key, linhas jsonb) on commit drop;'];
for (const [nome, linhas] of Object.entries(dados.tabelas)) { if (linhas.length) sql.push(`insert into _copia_elolog values ('${nome.replace(/'/g, "''")}', ${tag}${JSON.stringify(linhas)}${tag}::jsonb);`) }
sql.push(`do $repor$ declare r record; cols text; pend text[]; prox text[]; passo int := 0; erros text;
begin
  select array_agg(tabela) into pend from _copia_elolog;
  while coalesce(array_length(pend, 1), 0) > 0 and passo < 15 loop
    passo := passo + 1; prox := '{}'; erros := '';
    for r in select c.tabela, c.linhas, split_part(c.tabela, '.', 1) esq, split_part(c.tabela, '.', 2) tab from _copia_elolog c where c.tabela = any(pend) loop
      if to_regclass(format('%I.%I', r.esq, r.tab)) is null then raise notice 'Tabela % não existe neste projeto: ignorada.', r.tabela; continue; end if;
      select string_agg(quote_ident(attname), ', ' order by attnum) into cols from pg_attribute
       where attrelid = format('%I.%I', r.esq, r.tab)::regclass and attnum > 0 and not attisdropped and attgenerated = ''
         and attname in (select jsonb_object_keys(r.linhas -> 0));
      begin
        execute format('alter table %I.%I disable trigger user', r.esq, r.tab);
        execute format('insert into %I.%I (%s) overriding system value select %s from jsonb_populate_recordset(null::%I.%I, $1) on conflict do nothing', r.esq, r.tab, cols, cols, r.esq, r.tab) using r.linhas;
        execute format('alter table %I.%I enable trigger user', r.esq, r.tab);
      exception when others then prox := prox || r.tabela; erros := erros || r.tabela || ': ' || sqlerrm || '; ';
      end;
    end loop;
    pend := prox;
  end loop;
  if coalesce(array_length(pend, 1), 0) > 0 then raise exception 'Não foi possível repor: %', erros; end if;
  raise notice 'Reposição concluída em % passagem(ns).', passo;
end $repor$;`);
sql.push('commit;'); writeFileSync(ficheiro + '.sql', sql.join('\n') + '\n');
console.log(`Cópia de ${dados.gerado_em}: ${dados.registos} registos em ${Object.keys(dados.tabelas).length} tabelas.\nCriados: ${ficheiro}.json e ${ficheiro}.sql`);
