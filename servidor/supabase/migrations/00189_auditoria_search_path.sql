-- v134 (auditoria): fixa o caminho de pesquisa de três funções internas assinaladas pelo Supabase («Function Search Path Mutable»).
-- Não usam tabelas (só devolvem uma lista ou recusam alterações), por isso o caminho vazio é seguro. Não altera dados nem permissões.
alter function private.evento_imutavel() set search_path = '';
alter function private.comprovativo_imutavel() set search_path = '';
alter function private.documento_papeis(text) set search_path = '';
