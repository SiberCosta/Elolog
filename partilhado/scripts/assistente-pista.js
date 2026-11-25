/* Elolog — ELO: encontrar uma encomenda sem o código, por pistas (v166).
   A pessoa escreve o que se lembra (destino, data, quem recebe, o que leva, o peso) e o ELO procura SÓ nas encomendas que
   a conta já pode ver (regras de acesso do servidor). Cada nova pista junta-se às anteriores até sobrar uma encomenda;
   nunca mostra a lista das outras. Sem servidor (demonstração), procura nas encomendas guardadas neste aparelho.
   Carregar depois de assistente-regras.js e antes de assistente.js. */
(function(){"use strict";
const norm=v=>String(v||"").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"").replace(/[^a-z0-9/ ]+/g," ").replace(/\s+/g," ").trim();
const VAZIAS=new Set(("a o as os de da do das dos e em no na nos nas para por com sem uma um uns umas que foi era e minha meu minhas meus sua seu encomenda encomendas "+
  "enviei enviado enviada mandei carga envio pacote acho tinha tem levava leva sei nao codigo pista dia mes ano kg quilos ela ele isso foi ate entre").split(" "));
const MESES=["janeiro","fevereiro","marco","abril","maio","junho","julho","agosto","setembro","outubro","novembro","dezembro"];
const datas=v=>{const d=new Date(String(v||"").length===10?v+"T12:00":v);if(!v||isNaN(d))return"";const p=x=>String(x).padStart(2,"0"),a=d.getDate(),m=d.getMonth()+1;
  return` ${p(a)}/${p(m)} ${a}/${m} ${p(a)}/${p(m)}/${d.getFullYear()} ${a} de ${MESES[m-1]} ${MESES[m-1]} ${d.getFullYear()} `};
const juntar=x=>x&&typeof x==="object"?Object.values(x).filter(v=>typeof v!=="object").join(" "):x||"";
function texto(o){return" "+norm([o.codigo,o.origem,o.destino,o.tipo_carga,o.descricao,o.observacoes,o.navio,juntar(o.destinatario),juntar(o.remetente),o.cliente_nome,
  o.peso_kg?Math.round(Number(o.peso_kg))+" kg":""].join(" "))+" "+datas(o.created_at)+datas(o.data_prevista)+datas(o.chegada_prevista)}
/** Termos úteis de uma pista: datas (15/11, 15/11/2026) e palavras com significado. */
function termos(p){const t=[];let n=norm(p).replace(/\b(\d{1,2})\/(\d{1,2})(?:\/\d{2,4})?\b/g,(_,a,b)=>{t.push(`${a}/${b}`);return" "});
  n.split(" ").forEach(w=>{if(w.length>=2&&!VAZIAS.has(w))t.push(w)});return t}
function filtrar(lista,pistas){const ts=pistas.flatMap(termos);if(!ts.length)return null;
  return lista.filter(o=>{const h=texto(o);return ts.every(t=>/^[\d/]+$/.test(t)?h.includes(" "+t+" "):h.includes(t))})}
async function encomendas(){const S=window.ELOLogServidor;
  if(S?.ativo?.()&&window.eloRegras?.servidor?.()){const sb=await S.cliente();
    const{data,error}=await sb.from("encomendas").select("codigo,origem,destino,tipo_carga,descricao,observacoes,navio,destinatario,remetente,cliente_nome,peso_kg,created_at,data_prevista,chegada_prevista")
      .order("created_at",{ascending:false}).limit(300);if(error)throw error;return data||[]}
  const l=[];["th_operations","elologClientShipments"].forEach(k=>{try{(JSON.parse(localStorage.getItem(k)||"[]")||[]).forEach(o=>l.push({codigo:o.id||o.code,origem:o.origin,destino:o.destination,
    tipo_carga:o.cargoType||o.cargo,descricao:o.description,destinatario:{nome:o.recipientName,morada:o.deliveryAddress},remetente:{nome:o.client||o.senderName},peso_kg:o.weight,created_at:o.createdAt,data_prevista:o.date}))}catch(_){}});
  return l}
/** Procura com todas as pistas juntas. n: quantas encomendas servem (-1 = a pista não tinha nada de concreto). */
window.eloPista={async procurar(pistas){const r=filtrar(await encomendas(),pistas);return{n:r?r.length:-1,codigo:r&&r.length===1?r[0].codigo:null}},termos};
})();
