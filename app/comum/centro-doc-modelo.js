/* Elolog — Centro Documental (v125): documentos em cartões (Remetente, Destinatário, Dados do navio, Totais de carga), com o Azul Atlântico
   na estrutura e os campos críticos (volumes, peso, código de barras, estados) em alto contraste. Na folha A4 os cartões ficam em duas colunas;
   no ecrã de um telemóvel ou tablet empilham-se (ver centro-doc-folha.css). O mesmo HTML serve o ecrã, o papel e o PDF.
   Uso: elologDocModelo.paginas(doc, marcas) · .etiquetas(doc, marcas) · .barras(texto) */
(function(){"use strict";
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const vazio=v=>v==null||v===""||(typeof v==="number"&&isNaN(v));
const num=(v,d=0)=>vazio(v)?"—":Number(v).toLocaleString("pt-PT",{minimumFractionDigits:d,maximumFractionDigits:d});
const eur=v=>vazio(v)?"—":Number(v).toLocaleString("pt-PT",{style:"currency",currency:"EUR"});
const dia=v=>{const d=new Date(v);return!v||isNaN(d)?"":d.toLocaleDateString("pt-PT",{day:"numeric",month:"long",year:"numeric"})};
const hora=v=>{const d=new Date(v);return!v||isNaN(d)?"":d.toLocaleTimeString("pt-PT",{hour:"2-digit",minute:"2-digit"})};
const curta=v=>{const d=new Date(v);return!v||isNaN(d)?"":d.toLocaleString("pt-PT",{dateStyle:"short",timeStyle:"short"})};
const NOMES={guia:"Guia de encomenda",rececao:"Guia de receção",pagamento:"Comprovativo de pagamento",entrega:"Comprovativo de entrega",etiqueta:"Etiqueta de volume"};
const METODOS={multibanco:"Multibanco",mbway:"MB WAY",mb_way:"MB WAY",transferencia:"transferência bancária",numerario:"numerário",cartao:"cartão"};
const SITE="https://elolog.pt",ligacao=d=>`${SITE}/site/validar.html?c=${encodeURIComponent(d.codigo_validacao||"")}`;
const grupos=c=>String(c||"").replace(/(.{4})(?=.)/g,"$1 ");

function qr(texto,tam){const Q=window.qrcode;if(typeof Q!=="function")return`<div class="fo-qr-falta" style="width:${tam}px;height:${tam}px">QR</div>`;
  const q=Q(0,"M");q.addData(texto);q.make();const n=q.getModuleCount();let p="";for(let r=0;r<n;r++)for(let c=0;c<n;c++)if(q.isDark(r,c))p+=`M${c+2},${r+2}h1v1h-1z`;
  return`<svg class="fo-qr" width="${tam}" height="${tam}" viewBox="0 0 ${n+4} ${n+4}" role="img" aria-label="Código QR de validação" shape-rendering="crispEdges"><rect width="${n+4}" height="${n+4}" fill="#fff"/><path d="${p}" fill="#0B2E45"/></svg>`}

/* código de barras Code 128 (conjunto B), desenhado aqui: lê-se com qualquer leitor de armazém */
const C128="212222 222122 222221 121223 121322 131222 122213 122312 132212 221213 221312 231212 112232 122132 122231 113222 123122 123221 223211 221132 221231 213212 223112 312131 311222 321122 321221 312212 322112 322211 212123 212321 232121 111323 131123 131321 112313 132113 132311 211313 231113 231311 112133 112331 132131 113123 113321 133121 313121 211331 231131 213113 213311 213131 311123 311321 331121 312113 312311 332111 314111 221411 431111 111224 111422 121124 121421 141122 141221 112214 112412 122114 122411 142112 142211 241211 221114 413111 241112 134111 111242 121142 121241 114212 124112 124211 411212 421112 421211 212141 214121 412121 111143 111341 131141 114113 114311 411113 411311 113141 114131 311141 411131 211412 211214 211232".split(" ");
function barras(texto,altura=46){const t=String(texto||"").replace(/[^\x20-\x7e]/g,"");if(!t)return"";const v=[104,...[...t].map(c=>c.charCodeAt(0)-32)];
  const soma=v.reduce((s,x,i)=>s+x*(i||1),0)%103;const padroes=[...v,soma].map(x=>C128[x]).join("")+"2331112";let x=10,p="";
  [...padroes].forEach((w,i)=>{w=+w;if(i%2===0)p+=`M${x},0h${w}v${altura}h-${w}z`;x+=w});
  return`<svg class="fo-barras" viewBox="0 0 ${x+10} ${altura}" preserveAspectRatio="none" role="img" aria-label="Código de barras ${esc(t)}" shape-rendering="crispEdges"><rect width="${x+10}" height="${altura}" fill="#fff"/><path d="${p}" fill="#000"/></svg>`}

/* ---------- peças ---------- */
const negativo=u=>String(u||"").replace(/elolog-logo\.svg/,"elolog-logo-negativo.svg");
const faixa=(d,m)=>{const e=d.dados?.empresa||{};return`<header class="fo-faixa"><img class="fo-elo" src="${esc(negativo(m.elolog))}" alt="Elolog"><span class="fo-faixa-tipo">${esc(NOMES[d.tipo])}</span>
  <span class="fo-prest-chip">${m.prestador?`<img src="${esc(m.prestador)}" alt="${esc(e.nome)}">`:`<b>${esc(e.nome||"Prestador")}</b>`}</span></header>`};
/* estado e versão aparecem só na legenda (sem texto repetido no topo) */
const cabeca=(d,rotulo,principal,pills="")=>`<div class="fo-cabeca"><div class="fo-ident"><span class="fo-rotulo">${esc(rotulo)}</span><strong class="fo-ref fo-mono">${principal}</strong>
  ${pills?`<div class="fo-pills">${pills}</div>`:""}</div><div class="fo-codbarras">${barras(d.referencia)}<span class="fo-mono">${esc(d.referencia)}</span></div></div>`;
const cartao=(titulo,corpo,cls="")=>`<section class="fo-cartao ${cls}"><h2>${esc(titulo)}</h2><div class="fo-cartao-corpo">${corpo}</div></section>`;
const campo=(rotulo,valor,cls="")=>vazio(valor)||valor==="—"?"":`<div class="fo-campo ${cls}"><span>${esc(rotulo)}</span><b>${valor}</b></div>`;
const pessoa=p=>`<strong class="fo-nome">${esc(p?.nome||"—")}</strong>${p?.telefone?`<span class="fo-tel fo-mono">${esc(p.telefone)}</span>`:""}${p?.email?`<span>${esc(p.email)}</span>`:""}${p?.morada?`<span>${esc(p.morada)}</span>`:""}`;
const totais=l=>`<div class="fo-totais">${l.map(([r,v,u,cls])=>`<div class="${cls||""}"><span>${esc(r)}</span><b>${v}${u?`<small> ${u}</small>`:""}</b></div>`).join("")}</div>`;
function legenda(d,pag,total){const e=d.dados?.empresa||{};
  return`<footer class="fo-legenda"><div class="fo-leg-qr">${qr(ligacao(d),78)}</div><div class="fo-leg-grelha">
    <div class="fo-l"><span>Número</span><b class="fo-mono">${esc(d.numero)}</b></div><div class="fo-l"><span>Versão · folha</span><b>${esc(d.versao||1)} · ${pag} de ${total}</b></div><div class="fo-l"><span>Emitido em</span><b>${esc(curta(d.emitido_em))}</b></div>
    <div class="fo-l fo-l2"><span>Emitido por</span><b>${esc(e.nome)}${e.nif?` · NIF ${esc(e.nif)}`:""}</b>${e.morada?`<em>${esc(e.morada)}${e.telefone?` · ${esc(e.telefone)}`:""}</em>`:""}</div>
    <div class="fo-l"><span>Estado</span><b class="${d.estado==="valido"?"fo-txt-ok":"fo-txt-mau"}">${d.estado==="valido"?"Em vigor":d.estado==="anulado"?"Anulado":"Substituído"}</b></div>
    <div class="fo-l fo-l3"><span>Código de validação · leia o QR ou abra elolog.pt/site/validar.html</span><b class="fo-mono fo-codigo">${esc(grupos(d.codigo_validacao))}</b><em>Impressão digital ${esc(String(d.sha256||"").slice(0,16))}</em></div>
  </div>${d.versao>1?`<div class="fo-rev"><b>Revisão ${esc(d.versao)}</b> ${esc(d.motivo||"Correção dos dados")}</div>`:""}</footer>`}
const folha=(d,m,corpo,nota,pag=1,total=1)=>`<article class="edoc fo fo-${esc(d.tipo)}${d.estado!=="valido"?" edoc-inativo":""}" data-pagina="${pag}" data-marca="${d.estado==="anulado"?"Anulado":"Substituído"}">
  ${faixa(d,m)}<div class="fo-corpo">${corpo}</div><p class="fo-nota">${nota}</p>${legenda(d,pag,total)}</article>`;
const paragem=(n,nome,detalhe,total)=>`<li><i>${n}</i><b>${esc(nome)}</b><small>${detalhe||"&nbsp;"}</small><div class="fo-par2"><div><span>Data e hora</span><u></u></div><div><span>Volumes</span><u class="fo-de">de ${esc(total)}</u></div></div><span>Nome e assinatura</span><u class="alto"></u></li>`;
const aviso=(titulo,linhas)=>linhas.length?`<section class="fo-alerta"><b>${esc(titulo)}</b>${linhas.map(t=>`<span>${esc(t)}</span>`).join("")}</section>`:"";

/* ---------- guia ---------- */
function volumes(e){const l=Array.isArray(e.volumes)?e.volumes:[];if(!l.length)return"";const max=4;
  return`<table class="fo-tab"><thead><tr><th>#</th><th>O que é</th><th class="n">Qtd.</th><th class="n">Peso</th><th class="n">Medidas (cm)</th></tr></thead><tbody>${l.slice(0,max).map((v,i)=>{
    const dim=[v.comprimento??v.length,v.largura??v.width,v.altura??v.height].filter(x=>!vazio(x)&&+x>0);
    return`<tr><td>${i+1}</td><td>${esc(v.descricao??v.description??"")}</td><td class="n">${num(v.quantidade??v.quantity??1)}</td><td class="n">${vazio(v.peso??v.weight)?"—":num(v.peso??v.weight,1)+" kg"}</td><td class="n">${dim.length===3?dim.map(x=>num(x)).join(" × "):"—"}</td></tr>`}).join("")}
    ${l.length>max?`<tr><td></td><td colspan="4" class="fo-mais">e mais ${l.length-max} linha(s) registadas na Elolog</td></tr>`:""}</tbody></table>`}
function guia(d,m){const x=d.dados||{},e=x.encomenda||{},total=vazio(e.quantidade)?"__":num(e.quantidade);
  const navio=`<div class="fo-campos2">${campo("Modalidade",esc(e.modalidade))}${campo("Navio",esc(e.navio),"fo-forte")}${campo("Viagem",`<span class="fo-mono">${esc(e.viagem)}</span>`.replace(/^<span class="fo-mono"><\/span>$/,""))}
    ${campo("Recolha prevista",esc(dia(e.data_prevista)))}${campo("Partida prevista",esc(dia(e.partida_prevista)))}${campo("Chegada prevista",esc(dia(e.chegada_prevista)))}</div>${e.navio||e.partida_prevista?"":`<p class="fo-vazio">Navio e datas ainda por confirmar pelo prestador.</p>`}`;
  const cuidado=[e.observacoes,...(x.ocorrencias||[]).map(o=>`${o.codigo||o.tipo}: ${o.descricao||""}`)].filter(Boolean);
  return folha(d,m,`${cabeca(d,"Encomenda",esc(d.referencia))}
    <div class="fo-rota"><span>${esc(e.origem||"Origem por indicar")}</span><i aria-label="para">→</i><span>${esc(e.destino||"Destino por indicar")}</span></div>
    <div class="fo-grelha">${cartao("Remetente",pessoa(x.remetente))}${cartao("Destinatário",pessoa(x.destinatario),"fo-destaque")}
      ${cartao("Dados do navio",navio)}${cartao("Totais de carga",totais([["Volumes",total,"","fo-critico"],["Peso",num(e.peso_kg,1),"kg","fo-critico"],["Volume",num(e.volume_m3,3),"m³"],["Valor declarado",eur(e.valor_declarado),""]]))}</div>
    ${cartao("Conteúdo",`<p class="fo-desc">${esc(e.descricao||e.tipo_carga||"Mercadoria")}${e.tipo_carga&&e.descricao?` <span>· ${esc(e.tipo_carga)}</span>`:""}</p>${volumes(e)}${aviso("Atenção ao manusear",cuidado)}`,"fo-largo")}
    ${cartao("Percurso da carga",`<ol class="fo-percurso">${paragem(1,"Receção no armazém",esc(e.morada_recolha?"Recolha em "+e.morada_recolha:""),total)}${paragem(2,"Expedição",esc([e.navio,e.partida_prevista&&dia(e.partida_prevista)].filter(Boolean).join(", ")),total)}${paragem(3,"Entrega",esc(x.destinatario?.nome||""),total)}</ol>`,"fo-largo")}`,
    "Acompanha a carga até à entrega: em cada paragem conte os volumes, escreva a hora e assine. Não é documento fiscal; a validade como documento de transporte depende da lei aplicável.")}

/* ---------- guia de receção ---------- */
function rececao(d,m){const x=d.dados||{},r=x.rececao||{},e=x.encomenda||{},esp=+r.quantidade_esperada,rec=+r.quantidade_recebida,dif=!isNaN(esp)&&!isNaN(rec)?rec-esp:null;
  const pill=dif==null?"":dif===0?`<span class="fo-pill fo-ok">Sem diferenças</span>`:`<span class="fo-pill fo-atencao">Diferença de ${num(Math.abs(dif))} volume(s)</span>`;
  return folha(d,m,`${cabeca(d,"Receção da encomenda",esc(d.referencia),pill)}
    <p class="fo-frase">${esc(r.armazem||"O armazém")} recebeu a carga${r.em?` a ${esc(dia(r.em))} às ${esc(hora(r.em))}`:""}${r.por?`, conferida por ${esc(r.por)}`:""}.</p>
    <div class="fo-grelha">${cartao("Totais recebidos",totais([["Esperados",num(esp),"vol."],["Recebidos",num(rec),"vol.","fo-critico"],["Diferença",dif==null?"—":dif===0?"0":(dif>0?"+":"")+num(dif),"",dif?"fo-mau-n":""],["Carga conferida",r.conferida===true?"Sim":r.conferida===false?"Não":"—",""]]))}
      ${cartao("Armazém",`<div class="fo-campos2">${campo("Armazém",esc(r.armazem),"fo-forte")}${campo("Localização",esc(r.localizacao),"fo-forte")}${campo("Recebida por",esc(r.por))}${campo("Data e hora",esc(curta(r.em)))}</div>`)}
      ${cartao("Remetente",pessoa(x.remetente))}${cartao("Destinatário",pessoa(x.destinatario))}</div>
    ${aviso("Registado na receção",r.ocorrencias?[r.ocorrencias]:[])}
    ${cartao("Carga",`<p class="fo-desc">${esc(e.descricao||"Mercadoria")} <span>· ${num(e.peso_kg,1)} kg · ${num(e.volume_m3,3)} m³ · ${esc(e.origem||"")} → ${esc(e.destino||"")}</span></p>`,"fo-largo")}
    ${cartao("Assinaturas",`<ol class="fo-percurso fo-dois">${paragem(1,"Entregue por","",num(esp))}${paragem(2,"Recebido pelo armazém",esc(r.armazem||""),num(esp))}</ol>`,"fo-largo")}`,
    "Guia de receção emitida pela Elolog quando o armazém confirmou a entrada da carga. Não é documento fiscal.")}

/* ---------- comprovativo de pagamento ---------- */
function pagamento(d,m){const x=d.dados||{},p=x.pagamento||{},c=x.cliente||{},e=x.encomenda||{};
  const total=+p.total_encomenda||0,pago=+p.total_pago||0,este=+p.valor||0,antes=Math.max(0,pago-este),saldo=Math.max(0,+p.saldo||0),pct=total>0?Math.min(100,Math.round(pago/total*100)):100;
  const metodo=METODOS[String(p.metodo||"").toLowerCase()]||p.metodo,integral=saldo<=0;
  return folha(d,m,`${cabeca(d,"Comprovativo",esc(d.numero),integral?`<span class="fo-pill fo-ok">Pago na totalidade</span>`:`<span class="fo-pill fo-atencao">Pagamento parcial</span>`)}
    <section class="fo-valor"><span>Valor recebido</span><strong>${eur(este)}</strong><p>${c.nome?`Pago por ${esc(c.nome)}`:"Pagamento"}${metodo?` por ${esc(metodo)}`:""}${p.em?`, a ${esc(dia(p.em))} às ${esc(hora(p.em))}`:""}, para a encomenda <b class="fo-mono">${esc(d.referencia)}</b>${e.origem&&e.destino?` (${esc(e.origem)} → ${esc(e.destino)})`:""}.</p>
      <div class="fo-barra"><span class="fo-barra-cheia" style="width:${pct}%"></span></div><p class="fo-barra-txt">${integral?"Encomenda paga na totalidade.":`Pago ${eur(pago)} de ${eur(total)} (${pct}%). <b>Falta pagar ${eur(saldo)}.</b>`}</p></section>
    <div class="fo-grelha">${cartao("A conta",`<table class="fo-conta"><tbody><tr><td>Total da encomenda</td><td class="n">${eur(total)}</td></tr><tr><td>Pago anteriormente</td><td class="n">${eur(antes)}</td></tr>
      <tr class="fo-este"><td>Este pagamento</td><td class="n">+ ${eur(este)}</td></tr><tr class="fo-soma"><td>Total pago</td><td class="n">${eur(pago)}</td></tr><tr class="fo-saldo"><td>Saldo em dívida</td><td class="n">${eur(saldo)}</td></tr></tbody></table>`)}
      ${cartao("Detalhes do pagamento",`<div class="fo-campos2">${campo("Código",`<span class="fo-mono">${esc(p.codigo)}</span>`,"fo-forte")}${campo("Método",esc(metodo))}${campo("Referência",esc(p.referencia))}${campo("Data e hora",esc(curta(p.em)))}</div>`)}
      ${cartao("Cliente",`<div class="fo-campos2">${campo("Nome",esc(c.nome),"fo-forte")}${campo("NIF",esc(c.nif))}</div>`)}${cartao("Encomenda",`<div class="fo-campos2">${campo("Referência",`<span class="fo-mono">${esc(d.referencia)}</span>`,"fo-forte")}${campo("Percurso",esc([e.origem,e.destino].filter(Boolean).join(" → ")))}</div>`)}</div>
    <p class="fo-fiscal">Este papel confirma o dinheiro recebido. <b>Não é recibo nem fatura.</b> O documento fiscal é emitido pelo programa de faturação certificado de ${esc(x.empresa?.nome||"prestador")}.</p>`,
    "Comprovativo operacional emitido pela plataforma Elolog.")}

/* ---------- comprovativo de entrega (assinado no terreno) ---------- */
function entrega(d,m){const x=d.dados||{},n=x.entrega||{},e=x.encomenda||{},assin=/^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(n.assinatura||"")?n.assinatura:"",gps=n.lat!=null&&n.lon!=null;
  return folha(d,m,`${cabeca(d,"Entrega da encomenda",esc(d.referencia))}
    <p class="fo-frase">Entregue a <b>${esc(n.recebido_por||"—")}</b>${n.feito_em?` a ${esc(dia(n.feito_em))} às ${esc(hora(n.feito_em))}`:""}${n.motorista?`, por ${esc(n.motorista)}`:""}.</p>
    <div class="fo-grelha">${cartao("Quem recebeu",`<strong class="fo-nome">${esc(n.recebido_por||"—")}</strong>${n.identificacao?`<span>Identificação: <b class="fo-mono">${esc(n.identificacao)}</b></span>`:""}<span>${esc(x.destinatario?.morada||e.destino||"")}</span>`,"fo-destaque")}
      ${cartao("Totais entregues",totais([["Volumes conferidos",vazio(n.volumes_conferidos)?"—":num(n.volumes_conferidos),vazio(e.quantidade)?"":`de ${num(e.quantidade)}`,"fo-critico"],["Fotografias",num(n.fotos||0),""],["Peso",num(e.peso_kg,1),"kg"],["Volume",num(e.volume_m3,3),"m³"]]))}
      ${cartao("Onde e quando",`<div class="fo-campos2">${campo("Data e hora",esc(curta(n.feito_em)),"fo-forte")}${campo("Motorista",esc(n.motorista))}${campo("Posição GPS",gps?`<span class="fo-mono">${esc(n.lat)}, ${esc(n.lon)}</span>`:"Sem posição")}${campo("Precisão",n.precisao_m!=null?`± ${num(n.precisao_m)} m`:"")}</div>`)}
      ${cartao("Remetente",`<strong class="fo-nome">${esc(x.remetente?.nome||"—")}</strong><span>${esc(e.origem||"")} → ${esc(e.destino||"")}</span>`)}</div>
    ${n.notas?`<section class="fo-alerta"><b>Notas da entrega</b><span>${esc(n.notas)}</span></section>`:""}
    ${cartao("Assinatura de quem recebeu",assin?`<img class="fo-assinatura" src="${assin}" alt="Assinatura de ${esc(n.recebido_por||"quem recebeu")}">`:'<p class="fo-vazio">Sem assinatura.</p>',"fo-largo")}`,
    "Comprovativo de entrega emitido pela Elolog com os dados registados no telemóvel do motorista no momento da entrega. Não é documento fiscal.")}

function paginas(d,m){return[{guia,rececao,pagamento,entrega}[d.tipo]?.(d,m)||folha(d,m,"<p>Tipo de documento desconhecido.</p>","")]}

/* ---------- etiquetas: uma por volume, 4 por folha ---------- */
function etiquetas(d,m){const x=d.dados||{},e=x.encomenda||{},n=Math.max(1,Math.min(200,parseInt(e.quantidade,10)||1)),folhas=[];
  for(let i=0;i<n;i+=4){const et=[];for(let k=i;k<Math.min(n,i+4);k++)et.push(`<div class="fo-etq">${faixa({...d,tipo:"etiqueta"},m)}<span class="fo-rotulo">Encomenda</span><strong class="fo-etq-ref fo-mono">${esc(d.referencia)}</strong>
      <div class="fo-etq-barras">${barras(d.referencia,52)}</div><span class="fo-etq-vol">Volume <b>${k+1}</b> de ${n}</span><span class="fo-rotulo">Entregar a</span><strong>${esc(x.destinatario?.nome||"—")}</strong><span>${esc(e.destino||"")}</span>
      <div class="fo-etq-pe"><span class="fo-mono">${esc(d.numero)}</span>${qr(ligacao(d),80)}</div></div>`);
    folhas.push(`<article class="edoc fo fo-folha-etq">${et.join("")}</article>`)}
  return folhas}

window.elologDocModelo={paginas,etiquetas,barras,NOMES,ligacao,esc};
})();
