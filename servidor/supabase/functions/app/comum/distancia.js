/* Elolog — distância da recolha por estrada (v116).
   Mede a partir dos ARMAZÉNS do prestador (guardados no servidor, ou nas Configurações na demonstração) até à morada de recolha.
   Distância por estrada: perfil de camião (Valhalla, comum/rotas.js); se falhar, OSRM (router.project-osrm.org). Se não responder: linha reta × 1,3 (indicado como aproximado).
   O servidor volta a validar o valor (private.km_recolha): um km impossível é corrigido. */
(function(){"use strict";
const OSRM="https://router.project-osrm.org",FATOR=1.3,cache={};let ultimaFonte="carro";
const linha=(a,b)=>{const R=6371,r=x=>x*Math.PI/180,dLat=r(b.lat-a.lat),dLon=r(b.lon-a.lon),h=Math.sin(dLat/2)**2+Math.cos(r(a.lat))*Math.cos(r(b.lat))*Math.sin(dLon/2)**2;return 2*R*Math.atan2(Math.sqrt(h),Math.sqrt(1-h))};
const um=n=>Math.round(n*10)/10;
async function pedir(url){const c=new AbortController(),t=setTimeout(()=>c.abort(),8000);try{const r=await fetch(url,{signal:c.signal});if(!r.ok)throw new Error("OSRM "+r.status);return await r.json()}finally{clearTimeout(t)}}

/** distâncias por estrada (km) de um ponto a vários destinos, num só pedido; null por destino quando não há rota */
async function estradaVarios(a,destinos){if(!destinos.length)return[];const chave=[a,...destinos].map(p=>`${(+p.lon).toFixed(5)},${(+p.lat).toFixed(5)}`).join(";");
  if(cache[chave])return cache[chave];
  if(window.elologRotas){const r=await window.elologRotas.matriz(a,destinos);if(r.fonte){ultimaFonte=r.fonte;return cache[chave]=r.km}}   // v131: camião (Valhalla), depois carro
  try{const j=await pedir(`${OSRM}/table/v1/driving/${chave}?sources=0&annotations=distance`);const d=j?.distances?.[0];if(!Array.isArray(d))throw new Error("sem tabela");
    const r=destinos.map((_,i)=>d[i+1]==null?null:um(d[i+1]/1000));cache[chave]=r;return r}catch(_){return destinos.map(()=>null)}}
async function estrada(a,b){const[k]=await estradaVarios(a,[b]);return k!=null?{km:k,metodo:"estrada",veiculo:ultimaFonte}:{km:um(linha(a,b)*FATOR),metodo:"aproximada"}}

/* pontos de partida: servidor (coordenadas dos armazéns dos prestadores) ou, sem servidor, os armazéns das Configurações deste navegador */
let pontosCache=null,pontosEm=0;
async function pontos(){if(pontosCache&&Date.now()-pontosEm<300000)return pontosCache;let l=[];
  try{if(window.elologProducao?.online?.()){const sb=await window.elologProducao.sb();const{data,error}=await sb.rpc("pontos_recolha");if(error)throw error;
      l=(data||[]).map(p=>({empresa:p.empresa_id,armazem:p.armazem,lat:+p.lat,lon:+p.lon}))}
    else{for(let i=0;i<localStorage.length;i++){const k=localStorage.key(i);if(!/^elolog_provider_settings_/.test(k))continue;const s=JSON.parse(localStorage.getItem(k)||"{}"),emp=k.replace("elolog_provider_settings_","");
      for(const w of Array.isArray(s.warehouses)?s.warehouses:[]){if(!w?.address)continue;let c=w.lat!=null?{lat:+w.lat,lon:+w.lon}:null;
        if(!c&&typeof obterCoordenadas==="function"){try{c=await obterCoordenadas(w.address)}catch(_){}}if(c)l.push({empresa:emp,armazem:w.name||"Armazém",...c})}}}}
  catch(e){console.warn("Armazéns indisponíveis",e?.message)}pontosCache=l;pontosEm=Date.now();return l}

/** km por prestador (armazém mais próximo de cada um) e o mais próximo de todos */
async function recolha(a){const p=await pontos();if(!p.length)return null;const ks=await estradaVarios(a,p),porEmpresa={};let melhor=null,metodo="estrada";
  p.forEach((x,i)=>{let km=ks[i];if(km==null){km=um(linha(a,x)*FATOR);metodo="aproximada"}const atual=porEmpresa[x.empresa];
    if(!atual||km<atual.km)porEmpresa[x.empresa]={km,armazem:x.armazem};if(!melhor||km<melhor.km)melhor={empresa:x.empresa,armazem:x.armazem,km}});
  const kms={};Object.entries(porEmpresa).forEach(([e,v])=>kms[e]=v.km);return{kms,porEmpresa,melhor,metodo}}

const limparCache=()=>{pontosCache=null};
window.elologDistancia={fonte:()=>ultimaFonte,estrada,estradaVarios,linha,pontos,recolha,limparCache};
})();
