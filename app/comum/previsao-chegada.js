/* Elolog — chegada prevista de uma encomenda (v144).
   A previsão de chegada deixa de ser a data prevista da encomenda (que é o dia da recolha). Vem, por esta ordem:
   1) da viagem associada à encomenda no servidor (chegada_prevista, navio);
   2) do calendário marítimo: a primeira viagem para o mesmo destino que parte no dia da recolha ou depois (viagens publicadas
      no servidor e o calendário da empresa guardado neste aparelho);
   3) sem viagem: «por definir». Nada é inventado. */
(function(){"use strict";
const norm=v=>String(v||"").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"").replace(/[^a-z0-9 ]+/g," ").trim();
const iso=v=>{if(!v)return"";const s=String(v).trim(),m=/^(\d{1,2})\/(\d{1,2})\/(\d{4})/.exec(s);if(m)return`${m[3]}-${m[2].padStart(2,"0")}-${m[1].padStart(2,"0")}`;return/^\d{4}-\d{2}-\d{2}/.test(s)?s.slice(0,10):""};
const dia=v=>{const s=iso(v);return s?new Date(s+"T12:00:00").toLocaleDateString("pt-PT"):""};
const FECHADA=/cancel|conclu/i;
let servidor=[];

/* viagens do calendário da empresa neste aparelho */
function locais(){const out=[];try{for(let i=0;i<localStorage.length;i++){const k=localStorage.key(i);if(!/^elolog_maritime_calendar_/.test(k))continue;
  (JSON.parse(localStorage.getItem(k)||"[]")||[]).forEach(v=>out.push({partida:iso(v.departure),chegada:iso(v.arrival),destino:v.destination||"",navio:v.vessel||"",viagem:v.voyage||"",estado:v.status||""}))}}catch(_){}
  return out}
/* v161: só lê com sessão iniciada (sem sessão o servidor recusa) e volta a ler quando a pessoa entra */
let escuta=false;
async function lerServidor(){const P=window.elologProducao;if(!P?.online?.())return;const hoje=new Date(Date.now()-30*864e5).toISOString().slice(0,10);
  try{const sb=await P.sb();if(!escuta&&sb?.auth?.onAuthStateChange){escuta=true;sb.auth.onAuthStateChange(ev=>{if(ev==="SIGNED_IN")setTimeout(lerServidor,500)})}
    const{data:ses}=await sb.auth.getSession();if(!ses?.session)return;const r=await Promise.all(["viagens_maritimas","viagens_elolog"].map(t=>sb.from(t).select("navio,viagem,porto_destino,partida,chegada,estado").eq("publicada",true).gte("partida",hoje).limit(200)));
    servidor=r.flatMap(x=>x.data||[]).map(v=>({partida:iso(v.partida),chegada:iso(v.chegada),destino:v.porto_destino||"",navio:v.navio||"",viagem:v.viagem||"",estado:v.estado||""}))}catch(_){}}

const mesmoDestino=(a,b)=>{const x=norm(a).split(" ").filter(w=>w.length>2),y=new Set(norm(b).split(" ").filter(w=>w.length>2));return x.some(w=>y.has(w))};

/** {data:"AAAA-MM-DD"|null, fonte:"viagem"|"calendario"|null, navio, viagem, partida} */
function chegada(o){if(!o)return{data:null,fonte:null};
  const fixa=iso(o.arrivalDate||o.chegada_prevista);if(fixa)return{data:fixa,fonte:"viagem",navio:o.vessel||o.navio||"",partida:iso(o.departureDate||o.partida_prevista)};
  const recolha=iso(o.date||o.data_prevista)||new Date().toISOString().slice(0,10),destino=o.destination||o.destino;if(!destino)return{data:null,fonte:null};
  const v=[...servidor,...locais()].filter(x=>x.partida&&x.chegada&&x.partida>=recolha&&!FECHADA.test(x.estado)&&mesmoDestino(destino,x.destino))
    .sort((a,b)=>a.partida.localeCompare(b.partida))[0];
  return v?{data:v.chegada,fonte:"calendario",navio:v.navio,viagem:v.viagem,partida:v.partida}:{data:null,fonte:null}}

/** frase curta para o rodapé do Fluxo */
function texto(o){const c=chegada(o);if(!c.data)return"Chegada prevista: por definir, ainda sem viagem no calendário para este destino.";
  const barco=c.navio?` no navio ${c.navio}`:"";return c.fonte==="viagem"?`Chegada prevista: ${dia(c.data)}${barco}.`:`Chegada prevista: ${dia(c.data)}, pela próxima viagem do calendário${barco} (partida a ${dia(c.partida)}).`}

window.elologPrevisao={chegada,texto,dia,iso,lerServidor};
window.addEventListener("load",()=>setTimeout(lerServidor,3000));
})();
