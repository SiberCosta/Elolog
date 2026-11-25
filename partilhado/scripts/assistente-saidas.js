/* Elolog — ELO: próximas saídas (v169).
   Quando alguém pergunta pelo próximo barco ou pelas saídas, o ELO responde no chat com as saídas que a administração mostra
   no site (site_conteudo: publicadas pelos prestadores verificados). Se a pergunta tiver um destino ou origem, filtra por ele.
   Sem saídas publicadas, diz que ainda não há e não inventa datas. Carregar depois de assistente-regras.js. */
(function(){"use strict";
const norm=v=>String(v||"").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"").replace(/[^a-z0-9 ]+/g," ").replace(/\s+/g," ").trim();
const dia=v=>{const d=new Date(String(v||"").length===10?v+"T12:00":v);return isNaN(d)?"":d.toLocaleDateString("pt-PT",{day:"2-digit",month:"2-digit",year:"numeric"})};
const PERGUNTA=/\b(proximo (barco|navio)|proxima (saida|partida)|proximas (saidas|partidas)|saidas( previstas)?|quando (sai|parte) o (barco|navio)|datas? de (saida|partida)|calendario (de saidas|maritimo)|next (ship|vessel|sailing|boat)|sailings?|departures?)\b/;
const VAZIAS=new Set("o a os as de da do para quando qual quais proximo proxima proximas saida saidas barco navio partida datas data sai parte ha existe tem previstas prevista calendario maritimo".split(" "));
async function conteudo(){if(window.elologSiteConteudo)return window.elologSiteConteudo;const c=window.ELOLOG_SERVIDOR||{},url=String(c.supabaseUrl||"").replace(/\/$/,""),k=c.supabaseAnonKey||"";
  if(!/^https:\/\//.test(url)||k.length<20)return null;
  const r=await fetch(url+"/rest/v1/rpc/site_conteudo",{method:"POST",headers:{"Content-Type":"application/json",apikey:k,Authorization:"Bearer "+k},body:"{}"});if(!r.ok)throw new Error("servidor");
  return window.elologSiteConteudo=await r.json()}
async function responder(texto){const diz=t=>window.eloRegras?.dizer?.(t);
  try{const c=await conteudo();if(!c)return diz("Não consigo consultar as saídas agora. Fale com uma pessoa da equipa ou tente daqui a pouco.");
    let l=c.saidas||[];const filtro=norm(texto).split(" ").filter(w=>w.length>2&&!VAZIAS.has(w));
    const lugar=filtro.length?l.filter(s=>filtro.some(w=>norm(s.destino+" "+s.origem).includes(w))):l;
    if(filtro.length&&!lugar.length&&l.length)diz(`Não há saídas publicadas para «${filtro.join(" ")}». Estas são as próximas:`);else l=lugar;
    if(!l.length)return diz("Ainda não há saídas publicadas pelos prestadores. Quando houver, aparecem aqui e no site.");
    diz([...l.slice(0,4).map(s=>`• ${dia(s.partida)} · ${s.origem} → ${s.destino}\n  ${s.navio||""}${s.prestador?` · ${s.prestador}`:""}${s.fecho_carga?` · fecho de carga ${dia(s.fecho_carga)}`:""}${s.estado==="lotada"?" · lotada":""}`),
      "","As datas são as publicadas pelos prestadores e podem mudar; a data certa fica na sua encomenda."].join("\n"))}
  catch(_){diz("Não consigo consultar as saídas agora. Fale com uma pessoa da equipa ou tente daqui a pouco.")}}
const fluxos=window.eloFluxos||(window.eloFluxos=[]);
fluxos.unshift({re:{test:n=>PERGUNTA.test(norm(n))&&!/tempo real|\bais\b/.test(norm(n))},fazer:x=>{setTimeout(()=>responder(x),200);return{texto:"A ver as próximas saídas…",chips:["Nova simulação","Falar com uma pessoa"]}}});
window.eloSaidas={responder};
})();
