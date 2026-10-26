#!/usr/bin/env bash
# =====================================================================
# Elolog · TESTE 3 — Edge Functions publicadas (HTTP)
# Verifica, por fora, se as 3 funções estão publicadas e a recusar o que devem. NÃO cria contas nem dados
# e NÃO precisa de chaves secretas: só do endereço do projeto e da chave pública (anon).
#
#   SUPABASE_URL=https://<ref>.supabase.co SUPABASE_ANON_KEY=<chave anon> bash 03_funcoes_http.sh
#
# Opcional (testa o envio de e-mails; precisa do segredo que definiu em CRON_SECRET):
#   CRON_SECRET=<segredo>  EMAIL_TESTE=o-seu-email@exemplo.pt  bash 03_funcoes_http.sh
#
# Resultado: PASS / FAIL / AVISO por verificação. NÃO FOI EXECUTADO contra um projeto real por quem o escreveu.
# =====================================================================
set -u
: "${SUPABASE_URL:?Defina SUPABASE_URL (ex.: https://abcd1234.supabase.co)}"
: "${SUPABASE_ANON_KEY:?Defina SUPABASE_ANON_KEY (chave anon/public do projeto)}"
BASE="${SUPABASE_URL%/}/functions/v1"
TMP="$(mktemp)"; trap 'rm -f "$TMP" "$TMP.h"' EXIT
PASS=0; FAIL=0; AVISO=0

# pedido METODO NOME [curl extra...] -> deixa o estado HTTP em $COD, o corpo em $TMP e os cabeçalhos em $TMP.h
pedido() {
  local metodo="$1" nome="$2"; shift 2
  COD="$(curl -s -m 25 -X "$metodo" -D "$TMP.h" -o "$TMP" -w '%{http_code}' "$BASE/$nome" "$@" 2>/dev/null)" || COD="000"
}
corpo() { cat "$TMP" 2>/dev/null | head -c 300; }
ok()    { PASS=$((PASS+1));  printf 'PASS   %s\n' "$1"; }
falha() { FAIL=$((FAIL+1));  printf 'FAIL   %s\n       → %s\n' "$1" "$2"; }
aviso() { AVISO=$((AVISO+1)); printf 'AVISO  %s\n       → %s\n' "$1" "$2"; }
# espera ESTADO [TEXTO_NO_CORPO]
espera() {
  local nome="$1" estado="$2" texto="${3:-}"
  if [ "$COD" = "000" ]; then falha "$nome" "sem resposta (rede, endereço do projeto errado ou função não publicada)"; return; fi
  if [ "$COD" != "$estado" ]; then falha "$nome" "HTTP $COD (esperado $estado). Corpo: $(corpo)"; return; fi
  if [ -n "$texto" ] && ! grep -q "$texto" "$TMP" 2>/dev/null; then falha "$nome" "HTTP $COD certo, mas o corpo não contém \"$texto\": $(corpo)"; return; fi
  ok "$nome"
}
JSON=(-H 'Content-Type: application/json')
AUT=(-H "Authorization: Bearer $SUPABASE_ANON_KEY" -H "apikey: $SUPABASE_ANON_KEY")

echo "== registar-prestador (pública) =="
pedido OPTIONS registar-prestador -H 'Origin: https://exemplo.pt' -H 'Access-Control-Request-Method: POST'
espera "pré-voo CORS (OPTIONS) devolve 204" 204
grep -qi '^access-control-allow-origin:' "$TMP.h" 2>/dev/null && ok "cabeçalho Access-Control-Allow-Origin presente" || falha "cabeçalho CORS" "falta Access-Control-Allow-Origin (o navegador bloqueará o registo)"
pedido POST registar-prestador "${JSON[@]}" -d '{}'
espera "pedido vazio → 400 da PRÓPRIA função (prova que foi publicada com --no-verify-jwt)" 400 '"ok":false'
pedido POST registar-prestador "${JSON[@]}" "${AUT[@]}" -d '{não é json'
espera "JSON inválido → 400 json_invalido" 400 'json_invalido'
pedido GET registar-prestador
espera "GET → 405" 405

echo "== gerir-funcionarios (só administrador de empresa) =="
pedido OPTIONS gerir-funcionarios -H 'Origin: https://exemplo.pt' -H 'Access-Control-Request-Method: POST'
espera "pré-voo CORS (OPTIONS) devolve 204" 204
pedido POST gerir-funcionarios "${JSON[@]}" -d '{"acao":"criar"}'
espera "sem sessão → 401 sem_sessao (da própria função)" 401 'sem_sessao'
pedido POST gerir-funcionarios "${JSON[@]}" "${AUT[@]}" -d '{"acao":"criar"}'
espera "com a chave anon (não é um utilizador) → 401 sessao_invalida" 401 'sessao_invalida'
pedido GET gerir-funcionarios
espera "GET → 405" 405

echo "== enviar-emails (só o agendamento) =="
pedido GET enviar-emails
espera "GET → 405" 405
pedido POST enviar-emails "${JSON[@]}" -d '{}'
if [ "$COD" = "503" ] && grep -q 'nao_configurado' "$TMP" 2>/dev/null; then
  aviso "sem segredo → a função recusa" "CRON_SECRET ainda não definido na função (supabase secrets set CRON_SECRET=...). Recusar tudo é o comportamento seguro."
else espera "sem segredo → 401" 401 'nao_autorizado'; fi
pedido POST enviar-emails "${JSON[@]}" -H 'x-cron-secret: segredo-errado-de-proposito' -d '{}'
if [ "$COD" = "503" ] && grep -q 'nao_configurado' "$TMP" 2>/dev/null; then aviso "segredo errado" "CRON_SECRET não definido (ver acima)"
else espera "segredo errado → 401" 401 'nao_autorizado'; fi

if [ -n "${CRON_SECRET:-}" ]; then
  pedido POST enviar-emails "${JSON[@]}" -H "x-cron-secret: $CRON_SECRET" -d '{}'
  if [ "$COD" = "200" ]; then ok "com o segredo certo → 200 (fila processada ou vazia): $(corpo)"
  elif [ "$COD" = "503" ] && grep -q 'fornecedor_nao_configurado' "$TMP"; then aviso "com o segredo certo" "Brevo ainda não configurado (BREVO_API_KEY / EMAIL_REMETENTE)"
  elif [ "$COD" = "401" ]; then falha "com o segredo certo" "HTTP 401: o CRON_SECRET usado aqui não é o que está definido na função"
  else falha "com o segredo certo" "HTTP $COD: $(corpo)"; fi
  if [ -n "${EMAIL_TESTE:-}" ]; then
    pedido POST enviar-emails "${JSON[@]}" -H "x-cron-secret: $CRON_SECRET" -d "{\"teste\":\"$EMAIL_TESTE\"}"
    if [ "$COD" = "200" ]; then ok "e-mail de teste enviado para $EMAIL_TESTE — confirme na caixa de correio (e no spam)"
    else falha "e-mail de teste" "HTTP $COD: $(corpo)  (resultado 'configuracao' = chave API ou remetente não aceites pelo Brevo)"; fi
  else aviso "e-mail de teste" "defina EMAIL_TESTE=o-seu-email para testar o envio real"; fi
else aviso "envio de e-mails" "defina CRON_SECRET (e EMAIL_TESTE) para testar o Brevo"; fi

echo
echo "Resumo: $PASS PASS · $FAIL FAIL · $AVISO AVISO"
[ "$FAIL" -eq 0 ]
