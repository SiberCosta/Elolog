/* Elolog — configuração do servidor (Supabase).
   Deixar vazio = MODO LOCAL (comportamento anterior, dados no navegador).
   Preencher os dois valores = o cliente autentica-se e os preços são calculados no servidor.

   Onde obter: Supabase → Project Settings → API.
   - supabaseUrl: "Project URL" (https://xxxx.supabase.co)
   - supabaseAnonKey: chave "anon / public". Esta chave é pública por desenho; a proteção
     dos dados está nas políticas RLS (supabase/migrations/0003_rls.sql).
   NUNCA colocar aqui a chave "service_role".

   usarCdn: por omissão false = a aplicação NÃO pede nada a outros sites: a biblioteca do Supabase tem de estar em
   app/comum/supabase.js (ver app/LEIA-ME.md). Com true, se esse ficheiro faltar, tenta o jsDelivr (versão fixa). */
// Projeto «Elolog» (wcggcpdiswbzrdpwgdpb, Frankfurt), ligado a 28/10/2026. Para voltar ao modo local, esvazie os dois valores.
window.ELOLOG_SERVIDOR = {
  supabaseUrl: 'https://wcggcpdiswbzrdpwgdpb.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndjZ2djcGRpc3dienJkcHdnZHBiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMxMjMxODIsImV4cCI6MjEwODY5OTE4Mn0.lUFXIez4q9Mt4yTJjgl7tdPbA7EGWEyKCDQ6zNHZG4M',
  usarCdn: true   // a biblioteca ainda não está em app/comum/supabase.js: usa o jsDelivr (versão fixa 2.45.4)
};
