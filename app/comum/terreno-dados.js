/* Elolog — Terreno ao vivo (v127), camada de dados: serviços do motorista, partilha da posição com chegada prevista e fila sem rede.
   Servidor: trabalhos_terreno (RLS), iniciar_percurso, registar_posicao, terminar_percurso, servicos_a_caminho, registar_comprovativo.
   Sem rede: o comprovativo fica numa fila no telemóvel (IndexedDB) e é enviado quando houver ligação; o código local evita duplicados.
   Posição: só enquanto o motorista partilha, no máximo de 30 em 30 s; a chegada prevista usa o OSRM (gratuito) de 2 em 2 minutos.
   Demonstração (sem servidor): serviços de exemplo guardados neste navegador. */
(function(){"use strict";
const P=()=>window.elologProducao,online=()=>!!P()?.online?.();
const OSRM="https://router.project-osrm.org",DEMO="elolog_terreno_demo";
const hoje=()=>new Date().toISOString().slice(0,10);
const uuid=()=>crypto.randomUUID?crypto.randomUUID():"10000000-1000-4000-8000-100000000000".replace(/[018]/g,c=>(c^crypto.getRandomValues(new Uint8Array(1))[0]&15>>c/4).toString(16));
const erroTexto=e=>String(e?.message||e||"Erro").replace(/^.*?ERROR:\s*/,"");

/* ---------- serviços ---------- */
function demoLer(){try{const l=JSON.parse(localStorage.getItem(DEMO)||"null");if(Array.isArray(l))return l}catch(_){}
  const base={origem:"Almada, Portugal",destino:"São Tomé"},l=[
    {id:"demo-t1",tipo:"entrega",estado:"planeada",data:hoje(),notas:"Ligar 10 minutos antes.",encomenda:{...base,codigo:"ELO-2026-000123",quantidade:4,estado:"disponivel",destinatario:{nome:"Rui Mendes",telefone:"+351 913 222 111",morada:"Rua Cândido dos Reis 45, 2800-091 Almada"}}},
    {id:"demo-t2",tipo:"recolha",estado:"planeada",data:hoje(),notas:"",encomenda:{...base,codigo:"ELO-2026-000131",quantidade:2,estado:"agendamento",morada_recolha:"Avenida D. Nuno Álvares Pereira 12, 2800-180 Almada",remetente:{nome:"Ana Silva",telefone:"+351 912 345 678"}}}];
  demoGravar(l);return l}
const demoGravar=l=>{try{localStorage.setItem(DEMO,JSON.stringify(l))}catch(_){}};
async function servicos(){if(!online())return demoLer().filter(t=>["planeada","em_curso"].includes(t.estado));const sb=await P().sb();const ontem=new Date(Date.now()-864e5).toISOString().slice(0,10);
  const{data,error}=await sb.from("trabalhos_terreno").select("id,tipo,estado,data,notas,operador_id,encomenda:encomendas(codigo,origem,destino,morada_recolha,destinatario,remetente,quantidade,estado)")
    .in("tipo",["recolha","entrega"]).in("estado",["planeada","em_curso"]).gte("data",ontem).order("data").limit(100);if(error)throw error;return data||[]}
const morada=t=>t.tipo==="recolha"?(t.encomenda?.morada_recolha||t.encomenda?.origem||""):(t.encomenda?.destinatario?.morada||t.encomenda?.destino||"");
const pessoa=t=>t.tipo==="recolha"?(t.encomenda?.remetente||{}):(t.encomenda?.destinatario||{});

/* ---------- posição e chegada prevista ---------- */
const S={vigia:null,trabalho:null,ultimoEnvio:0,ultimaEta:0,eta:null,dist:null,destino:null,trinco:null,ouvintes:new Set(),ultima:null};
const avisar=()=>S.ouvintes.forEach(f=>{try{f(estado())}catch(_){}});
const estado=()=>({trabalho:S.trabalho,eta:S.eta,distancia:S.dist,posicao:S.ultima,ativo:!!S.vigia});
async function rota(a,b){if(window.elologRotas){const r=await window.elologRotas.rota(a,b);if(r)return{min:r.min,km:r.km}}try{const c=new AbortController(),t=setTimeout(()=>c.abort(),8000);const r=await fetch(`${OSRM}/route/v1/driving/${a.lon},${a.lat};${b.lon},${b.lat}?overview=false`,{signal:c.signal});clearTimeout(t);
    const j=await r.json();const x=j?.routes?.[0];return x?{min:x.duration/60,km:x.distance/1000}:null}catch(_){return null}}
const linha=(a,b)=>{const R=6371,r=x=>x*Math.PI/180,h=Math.sin(r(b.lat-a.lat)/2)**2+Math.cos(r(a.lat))*Math.cos(r(b.lat))*Math.sin(r(b.lon-a.lon)/2)**2;return 2*R*Math.atan2(Math.sqrt(h),Math.sqrt(1-h))};
async function aoMover(p){const c={lat:+p.coords.latitude.toFixed(6),lon:+p.coords.longitude.toFixed(6),prec:Math.round(p.coords.accuracy||0),vel:p.coords.speed!=null?Math.round(p.coords.speed*36)/10:null};S.ultima=c;
  if(S.destino&&Date.now()-S.ultimaEta>120000){S.ultimaEta=Date.now();const r=await rota(c,S.destino);const km=r?r.km:linha(c,S.destino)*1.3,min=r?r.min:km/40*60;
    S.dist=Math.round(km*10)/10;S.eta=new Date(Date.now()+min*60000).toISOString()}
  avisar();if(Date.now()-S.ultimoEnvio<30000||!S.trabalho)return;S.ultimoEnvio=Date.now();
  if(online()){try{const sb=await P().sb();await sb.rpc("registar_posicao",{p_trabalho:S.trabalho.id,p_lat:c.lat,p_lon:c.lon,p_precisao:c.prec,p_velocidade:c.vel,p_eta:S.eta,p_distancia:S.dist})}catch(_){}}}
const posicaoAgora=()=>new Promise((ok,falha)=>{if(!navigator.geolocation)return falha(new Error("Este aparelho não tem localização."));
  navigator.geolocation.getCurrentPosition(ok,e=>falha(new Error(e.code===1?"A localização está bloqueada. Autorize a localização para a Elolog nas definições do telemóvel.":"Não foi possível obter a localização. Vá para um local aberto e tente outra vez.")),{enableHighAccuracy:true,timeout:20000,maximumAge:15000})});
async function iniciar(t,previsto){const p=await posicaoAgora();const c={lat:+p.coords.latitude.toFixed(6),lon:+p.coords.longitude.toFixed(6)};
  if(online()){const sb=await P().sb();const{error}=await sb.rpc("iniciar_percurso",{p_trabalho:t.id,p_lat:c.lat,p_lon:c.lon,p_precisao:Math.round(p.coords.accuracy||0),p_previsto_ate:previsto||null});if(error)throw error}
  else{const l=demoLer();const x=l.find(y=>y.id===t.id);if(x){x.estado="em_curso";demoGravar(l)}}
  parar(true);S.trabalho=t;S.ultima={lat:c.lat,lon:c.lon};S.ultimoEnvio=Date.now();S.ultimaEta=0;S.eta=null;S.dist=null;S.destino=null;
  try{if(typeof obterCoordenadas==="function")S.destino=await obterCoordenadas(morada(t))}catch(_){}
  S.vigia=navigator.geolocation.watchPosition(aoMover,()=>{},{enableHighAccuracy:true,maximumAge:10000,timeout:30000});
  try{S.trinco=await navigator.wakeLock?.request("screen")}catch(_){}aoMover(p);avisar()}
function parar(silencioso){if(S.vigia!=null)navigator.geolocation.clearWatch(S.vigia);S.vigia=null;try{S.trinco?.release()}catch(_){}S.trinco=null;
  const t=S.trabalho;S.trabalho=null;if(!silencioso&&t&&online())P().sb().then(sb=>sb.rpc("terminar_percurso",{p_trabalho:t.id})).catch(()=>{});avisar()}
async function aCaminho(){if(!online()){const l=demoLer().filter(t=>t.estado==="em_curso");return l.map(t=>({codigo:t.encomenda.codigo,tipo:t.tipo,lat:38.6790,lon:-9.1569,eta:new Date(Date.now()+18*60000).toISOString(),
    distancia_km:6.4,atualizado_em:new Date(Date.now()-60000).toISOString(),previsto_ate:null,estado:"a_tempo",empresa:"Atlântico Lda",motorista:"Mário",destino:morada(t)}))}
  const sb=await P().sb();const{data,error}=await sb.rpc("servicos_a_caminho");if(error)throw error;return data||[]}

/* ---------- fila sem rede (IndexedDB) ---------- */
const BD=()=>new Promise((ok,falha)=>{const r=indexedDB.open("elolog-terreno",1);r.onupgradeneeded=()=>r.result.createObjectStore("pendentes",{keyPath:"id_local"});r.onsuccess=()=>ok(r.result);r.onerror=()=>falha(r.error)});
async function loja(modo,fn){const db=await BD();return new Promise((ok,falha)=>{const tx=db.transaction("pendentes",modo),st=tx.objectStore("pendentes");const r=fn(st);tx.oncomplete=()=>{db.close();ok(r?.result)};tx.onerror=()=>{db.close();falha(tx.error)}})}
const pendentes=()=>loja("readonly",st=>st.getAll());
async function guardar(c){c.id_local=c.id_local||uuid();c.feito_em=c.feito_em||new Date().toISOString();await loja("readwrite",st=>st.put({...c,guardado_em:Date.now()}));enviarPendentes();return c.id_local}
let aEnviar=false;
async function enviarPendentes(){if(aEnviar)return{enviados:0};aEnviar=true;let n=0;
  try{const l=await pendentes();for(const c of l){if(!navigator.onLine)break;try{let r;const{guardado_em,erro,...p}=c;
        if(online()){const sb=await P().sb();const{data,error}=await sb.rpc("registar_comprovativo",{p});if(error)throw Object.assign(new Error(error.message),{servidor:!!error.code&&!/fetch|network/i.test(error.message||"")});r=data}
        else r=demoRegistar(p);await loja("readwrite",st=>st.delete(c.id_local));n++;window.dispatchEvent(new CustomEvent("elolog-terreno-enviado",{detail:{...r,id_local:c.id_local}}))}
      catch(e){if(e?.servidor||/inv[aá]lid|Falta|Indique|permite|atribu/i.test(e?.message||""))await loja("readwrite",st=>st.put({...c,erro:erroTexto(e)}));else break}}}
  finally{aEnviar=false;window.dispatchEvent(new Event("elolog-terreno-fila"))}return{enviados:n}}
const descartar=id=>loja("readwrite",st=>st.delete(id)).then(()=>window.dispatchEvent(new Event("elolog-terreno-fila")));
function demoRegistar(p){const l=demoLer(),t=l.find(x=>x.id===p.trabalho);if(!t)throw new Error("Serviço de demonstração não encontrado.");
  if(["entregue","recolhido"].includes(p.resultado)&&(!p.recebido_por||!p.assinatura))throw new Error("Falta a assinatura ou o nome de quem recebeu.");
  t.estado=["cliente_ausente","recusado"].includes(p.resultado)?"cliente_ausente":"concluida";demoGravar(l);
  if(t.tipo==="entrega"&&p.resultado==="entregue")try{window.elologDocDemo?.entrega?.(t.encomenda.codigo,p)}catch(_){}return{id:"demo-"+p.id_local,repetido:false}}
window.addEventListener("online",()=>enviarPendentes());setInterval(()=>{if(navigator.onLine)enviarPendentes()},45000);setTimeout(()=>enviarPendentes(),3000);

window.elologTerrenoDados={servicos,morada,pessoa,iniciar,parar,estado,ouvir:f=>{S.ouvintes.add(f);return()=>S.ouvintes.delete(f)},aCaminho,guardar,pendentes,enviarPendentes,descartar,uuid,erroTexto,online,_demoLer:demoLer};
})();
