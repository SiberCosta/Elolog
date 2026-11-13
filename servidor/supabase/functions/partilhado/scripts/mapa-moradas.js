/* Elolog — localizar moradas (v130). Três serviços gratuitos e sem chave, pela ordem em que acertam mais em Portugal:
   1) GeoAPI.pt: códigos postais oficiais portugueses (0000-000), precisos à rua;
   2) Photon (komoot, dados OpenStreetMap): tolera moradas incompletas ou com erros;
   (v132) HERE entre 1) e 2), na aplicação com sessão iniciada;
   3) Nominatim (OpenStreetMap): o serviço usado até aqui, como último recurso.
   Uma morada com código postal português e sem outro país escrito é procurada só em Portugal (evita «Campo Grande» no Brasil).
   Devolve {lat, lon, fonte} ou null. */
(function(){"use strict";
const PT={minLat:32.4,maxLat:42.2,minLon:-31.5,maxLon:-6.1};   // continente, Madeira e Açores
const OUTRO_PAIS=/s[aã]o tom[eé]|angola|brasil|brazil|cabo verde|mo[cç]ambique|guin[eé]|espanha|spain|fran[cç]a|france|luxemb|su[ií][cç]a|reino unido|alemanha/i;
const cpDe=q=>(String(q).match(/\b(\d{4})-(\d{3})\b/)||[])[0]||"";
const soPortugal=q=>!!cpDe(q)&&!OUTRO_PAIS.test(q);
const emPortugal=p=>p&&p.lat>=PT.minLat&&p.lat<=PT.maxLat&&p.lon>=PT.minLon&&p.lon<=PT.maxLon;
const ok=(lat,lon,fonte)=>Number.isFinite(lat)&&Number.isFinite(lon)?{lat,lon,fonte}:null;
async function pedir(url,ms){const c=new AbortController(),t=setTimeout(()=>c.abort(),ms||8000);
  try{const r=await fetch(url,{signal:c.signal,headers:{Accept:"application/json"}});return r.ok?await r.json():null}catch(_){return null}finally{clearTimeout(t)}}

/* 1) GeoAPI.pt: o centro do código postal (a ordem das coordenadas é verificada, não presumida) */
async function geoapi(q){const cp=cpDe(q);if(!cp)return null;const j=await pedir("https://json.geoapi.pt/cp/"+cp);if(!j)return null;
  const par=Array.isArray(j.centro)?j.centro:Array.isArray(j.centroide)?j.centroide:Array.isArray(j.pontos)&&Array.isArray(j.pontos[0])?j.pontos[0]:null;if(!par)return null;
  const a=Number(par[0]),b=Number(par[1]);const p=Math.abs(a)>Math.abs(b)?ok(a,b,"geoapi"):ok(b,a,"geoapi");return emPortugal(p)?p:null}

/* 2) Photon: GeoJSON, coordenadas [longitude, latitude] */
async function photon(q,pt){const u="https://photon.komoot.io/api/?limit=1&q="+encodeURIComponent(q)+(pt?`&bbox=${PT.minLon},${PT.minLat},${PT.maxLon},${PT.maxLat}`:"");
  const j=await pedir(u);const c=j?.features?.[0]?.geometry?.coordinates;if(!Array.isArray(c))return null;const p=ok(Number(c[1]),Number(c[0]),"photon");return pt&&!emPortugal(p)?null:p}

/* 3) Nominatim */
async function nominatim(q,pt){const j=await pedir("https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&accept-language=pt"+(pt?"&countrycodes=pt":"")+"&q="+encodeURIComponent(q));
  return Array.isArray(j)&&j.length?ok(Number(j[0].lat),Number(j[0].lon),"nominatim"):null}

async function procurar(q){q=String(q||"").replace(/\s+/g," ").trim();if(q.length<3)return null;const pt=soPortugal(q);
  const comPais=pt&&!/portugal/i.test(q)?q+", Portugal":q;
  return(pt&&await geoapi(q))||await here(q)||await photon(comPais,pt)||await nominatim(comPais,pt)}
/* v132: HERE (só na aplicação, com sessão; a chave fica no servidor) */
async function here(q){const f=window.elologRotas?.hereFn;if(!f)return null;const d=await f({acao:"morada",q});return d&&Number.isFinite(+d.lat)?ok(+d.lat,+d.lon,"here"):null}

window.elologMoradas={procurar,soPortugal,emPortugal,cpDe};
})();
