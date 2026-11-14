/* Elolog — rotas por estrada para CAMIÃO (v131; v132: HERE primeiro, com trânsito, através da Edge Function «mapas-here»). Valhalla público (FOSSGIS, gratuito, sem chave), perfil «truck»: respeita
   restrições de altura, peso e acessos de pesados. Se não responder, usa o OSRM (carro) e, por fim, linha reta × 1,3.
   Dá: matriz (km de um ponto a vários), rota (km, minutos e o traçado para desenhar no mapa). Uso moderado: há cache. */
(function(){"use strict";
const VALHALLA="https://valhalla1.openstreetmap.de",OSRM="https://router.project-osrm.org",cache={};
const um=n=>Math.round(n*10)/10,pt=p=>({lat:+(+p.lat).toFixed(6),lon:+(+p.lon).toFixed(6)});
async function pedir(url,ms){const c=new AbortController(),t=setTimeout(()=>c.abort(),ms||9000);
  try{const r=await fetch(url,{signal:c.signal});if(!r.ok)throw new Error("HTTP "+r.status);return await r.json()}finally{clearTimeout(t)}}
/* HERE (só com sessão iniciada; a chave fica no servidor). Sem chave, quota esgotada ou erro: pausa 10 min e usa os gratuitos */
let herePausa=0;
async function hereFn(corpo){const P=window.elologProducao;if(!P?.online?.()||Date.now()<herePausa)return null;
  try{const sb=await P.sb();const{data,error}=await sb.functions.invoke("mapas-here",{body:corpo});if(error||!data||data.encontrado===false){if(error)herePausa=Date.now()+600000;return null}return data}
  catch(_){herePausa=Date.now()+600000;return null}}
const v=(acao,corpo)=>pedir(`${VALHALLA}/${acao}?json=${encodeURIComponent(JSON.stringify({...corpo,costing:"truck",units:"kilometers"}))}`);

/* traçado codificado (polyline de 6 casas) → [[lon,lat],…] */
function descodificar(s){const l=[];let i=0,lat=0,lon=0;const um=()=>{let r=0,sh=0,b;do{b=s.charCodeAt(i++)-63;r|=(b&31)<<sh;sh+=5}while(b>=32);return r&1?~(r>>1):r>>1};
  while(i<s.length){lat+=um();lon+=um();l.push([lon/1e6,lat/1e6])}return l}

/** km por estrada de «a» até cada destino (null quando não há rota); fonte: "camiao", "carro" ou null */
async function matriz(a,destinos){if(!destinos.length)return{km:[],fonte:null};const k="m"+JSON.stringify([pt(a),...destinos.map(pt)]);if(cache[k])return cache[k];
  {const h=destinos.length<=10?await hereFn({acao:"matriz",de:pt(a),para:destinos.map(pt)}):null;if(Array.isArray(h?.km)&&h.km.some(x=>x!=null))return cache[k]={km:h.km,fonte:"here"}}
  try{const j=await v("sources_to_targets",{sources:[pt(a)],targets:destinos.map(pt)});const l=j?.sources_to_targets?.[0];if(!Array.isArray(l))throw 0;
    const km=destinos.map((_,i)=>{const d=l.find(x=>x.to_index===i)??l[i];return d?.distance!=null?um(d.distance):null});
    if(km.some(x=>x!=null))return cache[k]={km,fonte:"camiao"}}catch(_){}
  try{const ch=[a,...destinos].map(p=>`${(+p.lon).toFixed(5)},${(+p.lat).toFixed(5)}`).join(";");const j=await pedir(`${OSRM}/table/v1/driving/${ch}?sources=0&annotations=distance`);
    const d=j?.distances?.[0];if(!Array.isArray(d))throw 0;return cache[k]={km:destinos.map((_,i)=>d[i+1]==null?null:um(d[i+1]/1000)),fonte:"carro"}}
  catch(_){return{km:destinos.map(()=>null),fonte:null}}}

/** rota de a até b: {km, min, linha:[[lon,lat]…], fonte} ou null */
async function rota(a,b){const k="r"+JSON.stringify([pt(a),pt(b)]);if(cache[k]&&Date.now()-cache[k].em<120000)return cache[k];
  {const h=await hereFn({acao:"rota",de:pt(a),para:pt(b)});if(h?.km!=null)return cache[k]={...h,em:Date.now()}}
  try{const j=await v("route",{locations:[pt(a),pt(b)]});const t=j?.trip;if(!t?.summary)throw 0;
    return cache[k]={km:um(t.summary.length),min:t.summary.time/60,linha:(t.legs||[]).flatMap(g=>g.shape?descodificar(g.shape):[]),fonte:"camiao",em:Date.now()}}catch(_){}
  try{const j=await pedir(`${OSRM}/route/v1/driving/${a.lon},${a.lat};${b.lon},${b.lat}?overview=full&geometries=geojson`);const x=j?.routes?.[0];if(!x)throw 0;
    return cache[k]={km:um(x.distance/1000),min:x.duration/60,linha:x.geometry?.coordinates||[],fonte:"carro",em:Date.now()}}catch(_){return null}}

window.elologRotas={matriz,rota,descodificar,hereFn};
})();
