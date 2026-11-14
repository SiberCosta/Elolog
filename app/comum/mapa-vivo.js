/* Elolog — mapa interativo (v131): MapLibre GL (cdnjs, carregado só quando se abre um mapa) com o mapa vetorial gratuito
   da OpenFreeMap (dados OpenStreetMap, sem chave). Mostra o motorista, o destino e o percurso de camião (comum/rotas.js).
   Sem ligação ou sem WebGL, abre o OpenStreetMap noutra janela: o botão «Ver no mapa» nunca fica sem resposta. */
(function(){"use strict";
const V="4.5.2",CDN=`https://cdnjs.cloudflare.com/ajax/libs/maplibre-gl/${V}/`,ESTILO="https://tiles.openfreemap.org/styles/liberty";
const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const osm=p=>`https://www.openstreetmap.org/?mlat=${p.lat}&mlon=${p.lon}#map=15/${p.lat}/${p.lon}`;
let pronto=null;
function biblioteca(){if(window.maplibregl)return Promise.resolve(window.maplibregl);
  return pronto||=new Promise((ok,falha)=>{const css=document.createElement("link");css.rel="stylesheet";css.href=CDN+"maplibre-gl.min.css";css.crossOrigin="anonymous";document.head.appendChild(css);
    const s=document.createElement("script");s.src=CDN+"maplibre-gl.min.js";s.crossOrigin="anonymous";s.async=true;
    s.onload=()=>window.maplibregl?ok(window.maplibregl):falha(new Error("sem biblioteca"));s.onerror=()=>{pronto=null;s.remove();falha(new Error("sem ligação"))};document.head.appendChild(s)})}
const temWebGL=()=>{try{const c=document.createElement("canvas");return!!(c.getContext("webgl2")||c.getContext("webgl"))}catch(_){return false}};

function janela(titulo){document.getElementById("mvJanela")?.remove();const d=document.createElement("div");d.id="mvJanela";d.className="mv-fundo";d.setAttribute("role","dialog");d.setAttribute("aria-modal","true");d.setAttribute("aria-label",titulo);
  d.innerHTML=`<div class="mv-caixa"><header class="mv-topo"><div><h2>${esc(titulo)}</h2><p class="mv-info" role="status">A abrir o mapa…</p></div><button type="button" class="btn-secondary mv-fechar">Fechar</button></header><div class="mv-mapa" id="mvMapa"></div>
    <p class="mv-fonte">Mapa: <a href="https://openfreemap.org" target="_blank" rel="noopener">OpenFreeMap</a> © OpenMapTiles, dados © <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>. Percurso: <span class="mv-motor">HERE ou Valhalla (camião)</span>.</p></div>`;
  const fechar=()=>{d.remove();document.removeEventListener("keydown",tecla);mapa?.remove?.()};const tecla=e=>{if(e.key==="Escape")fechar()};let mapa=null;
  d.querySelector(".mv-fechar").onclick=fechar;d.addEventListener("click",e=>{if(e.target===d)fechar()});document.addEventListener("keydown",tecla);document.body.appendChild(d);d.querySelector(".mv-fechar").focus();
  return{d,info:t=>{d.querySelector(".mv-info").textContent=t},guardar:m=>{mapa=m},fechar}}

/** abrir({titulo, de:{lat,lon,rotulo}, para:{lat,lon,rotulo} ou paraMorada:"texto"}) */
async function abrir(o){const de=o.de&&Number.isFinite(+o.de.lat)?{...o.de,lat:+o.de.lat,lon:+o.de.lon}:null;
  if(!de)return;if(!temWebGL()){window.open(osm(de),"_blank","noopener");return}
  const j=janela(o.titulo||"Mapa");let gl;try{gl=await biblioteca()}catch(_){j.fechar();window.open(osm(de),"_blank","noopener");return}
  let para=o.para&&Number.isFinite(+o.para.lat)?{...o.para,lat:+o.para.lat,lon:+o.para.lon}:null;
  if(!para&&o.paraMorada&&window.elologMoradas){try{const m=await window.elologMoradas.procurar(o.paraMorada);if(m)para={lat:m.lat,lon:m.lon,rotulo:o.paraMorada}}catch(_){}}
  if(!document.getElementById("mvMapa"))return;
  const mapa=new gl.Map({container:"mvMapa",style:ESTILO,center:[de.lon,de.lat],zoom:13,attributionControl:{compact:true}});j.guardar(mapa);
  mapa.addControl(new gl.NavigationControl({showCompass:false}),"top-right");
  const marca=(p,cls,txt)=>{const el=document.createElement("div");el.className="mv-marca "+cls;el.setAttribute("aria-label",txt);el.title=txt;
    new gl.Marker({element:el}).setLngLat([p.lon,p.lat]).setPopup(new gl.Popup({offset:18}).setText(txt)).addTo(mapa)};
  marca(de,"mv-motorista",de.rotulo||"Posição do motorista");if(para)marca(para,"mv-destino",para.rotulo||"Destino");
  mapa.on("error",()=>j.info("Parte do mapa não carregou. Verifique a ligação."));
  mapa.on("load",async()=>{if(!para){j.info("Posição do motorista. Destino sem coordenadas.");return}
    const b=new gl.LngLatBounds([de.lon,de.lat],[de.lon,de.lat]).extend([para.lon,para.lat]);
    const r=window.elologRotas?await window.elologRotas.rota(de,para):null;
    if(r?.linha?.length&&mapa.getStyle()){mapa.addSource("mvRota",{type:"geojson",data:{type:"Feature",geometry:{type:"LineString",coordinates:r.linha}}});
      mapa.addLayer({id:"mvRotaFundo",type:"line",source:"mvRota",layout:{"line-cap":"round","line-join":"round"},paint:{"line-color":"#ffffff","line-width":8}});
      mapa.addLayer({id:"mvRotaLinha",type:"line",source:"mvRota",layout:{"line-cap":"round","line-join":"round"},paint:{"line-color":"#1F5F8B","line-width":5}});r.linha.forEach(c=>b.extend(c))}
    mapa.fitBounds(b,{padding:60,maxZoom:15,duration:0});
    j.info(r?`${String(r.km).replace(".",",")} km, cerca de ${Math.max(1,Math.round(r.min))} min ${r.fonte==="here"?"de camião, com o trânsito atual (HERE)":r.fonte==="camiao"?"de camião":"de carro"}.`:"Percurso indisponível agora: mostramos só os pontos.")})}

window.elologMapa={abrir,osm};
})();
