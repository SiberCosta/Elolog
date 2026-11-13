/* Elolog — Fluxo Vivo de Operação (v111). Substitui as barras de 11 etapas (cliente, prestador e rastreio) por:
   uma frase que diz o que está a acontecer (e quem tratou, se a plataforma o sabe), a «saúde» do processo calculada
   com a previsão e o último movimento reais, quatro fases com o passo atual a respirar, e a ação certa com a urgência certa.
   Regra: nada inventado. Sem previsão ou sem movimento registado, diz isso mesmo. */
(function(){"use strict";
const eu=()=>{try{return typeof currentUser!=="undefined"?currentUser:null}catch(_){return null}};
const esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const ETAPAS=["Simulação","Cotação","Aprovação","Recolha","Pagamento","Armazenamento","Expedição","Em trânsito","Destino","Disponível","Levantado"];
const FASES=[["Acordo",[0,1,2]],["Origem",[3,4,5]],["No mar",[6,7]],["Chegada",[8,9,10]]];
const FINAIS=/levantad|entregue|conclu/i,CANCEL=/cancel|rejeit|anulad/i;

function indice(o){const v=String(o?.stage||o?.status||"").toLowerCase();if(FINAIS.test(v))return 10;
  const P=[["dispon",9],["destino",8],["trânsito",7],["transito",7],["expedi",6],["armazen",5],["pag",4],["recol",3],["aprova",2],["cota",1],["propost",1]];
  const h=P.find(([k])=>v.includes(k));return h?h[1]:0}
function data(v){if(!v)return null;const s=String(v).trim(),m=/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{1,2}):(\d{2}))?/.exec(s);
  const d=m?new Date(+m[3],m[2]-1,+m[1],+(m[4]||12),+(m[5]||0)):new Date(s);return isNaN(d)?null:d}
const dias=d=>Math.floor((Date.now()-d.getTime())/864e5);
const quando=d=>{const n=dias(d);const h=d.toLocaleTimeString("pt-PT",{hour:"2-digit",minute:"2-digit"});return n<=0?`hoje às ${h}`:n===1?`ontem às ${h}`:`a ${d.toLocaleDateString("pt-PT")}`};

/* o último movimento conhecido: mudança de estado registada, ou a atualização mais recente da encomenda */
function movimento(o){const l=o?.lastStatusChange;if(l&&data(l.datetime))return{d:data(l.datetime),quem:l.employee||"",para:l.next||""};
  const d=data(o?.updatedAt)||data(o?.created_at);return d?{d,quem:"",para:""}:null}

/* saúde do processo: ok (a bom ritmo), aviso (vale a pena olhar), erro (atrasada), neutro (sem dados para dizer) */
function saude(o,i){const v=String(o?.status||o?.stage||"");if(CANCEL.test(v))return{k:"neutro",t:"Encomenda cancelada"};if(i>=10)return{k:"ok",t:"Concluída"};
  const prev=data(o?.date),mv=movimento(o),parado=mv?dias(mv.d):null;
  if(prev&&Date.now()>prev.getTime()+864e5&&i<8)return{k:"erro",t:`Passou da previsão de ${prev.toLocaleDateString("pt-PT")}`};
  if(parado!=null&&parado>7)return{k:"erro",t:`Sem movimento há ${parado} dias`};
  const pg=emAberto(o),pd=pg&&pg.d?dias(pg.d):0;if(pd>=2)return{k:"aviso",t:`Pagamento por fazer há ${pd} dias`};
  if(parado!=null&&parado>4)return{k:"aviso",t:`Sem movimento há ${parado} dias`};
  if(prev&&i<7&&prev.getTime()-Date.now()<2*864e5)return{k:"aviso",t:"A previsão está perto e a carga ainda não saiu"};
  if(prev||mv)return{k:"ok",t:"Segue a bom ritmo"};return{k:"neutro",t:"Ainda sem previsão de chegada"}}

/* o que está a acontecer, dito por uma pessoa (cliente e prestador ouvem coisas diferentes) */
function frase(o,i,papel){const mv=movimento(o),por=mv&&mv.quem&&new RegExp(ETAPAS[i].slice(0,5),"i").test(mv.para)?` por ${mv.quem}`:"",dest=o?.destination?` de ${o.destination}`:"",em=o?.destination?` a ${o.destination}`:"";
  const C=["Estamos a pedir preços às transportadoras para esta rota.","Já há propostas. Compare-as e escolha a que lhe serve.","A transportadora está a confirmar os dados da sua carga"+por+".",
    "A recolha da carga está a ser combinada"+por+".","Falta confirmar o pagamento para a carga avançar.","A carga está no armazém a ser conferida"+por+".","A carga está a ser preparada para seguir viagem"+por+".",
    "A carga vai a caminho"+dest+".","A carga chegou"+em+" e está a ser recebida"+por+".","A encomenda está pronta para levantar.","Entregue. Obrigado por enviar com a Elolog."];
  const P=["O cliente fez uma simulação para uma rota sua.","O cliente espera a sua proposta de preço.","Confirme os dados da carga e aceite o pedido.","Combine a recolha com o cliente e registe-a no terreno.",
    "Confirme o pagamento para a carga seguir para o armazém.","Confira a carga no armazém e diga onde ficou guardada.","Feche a lista de carga e ligue-a a uma viagem.","Mantenha a previsão de chegada atualizada.",
    "Confirme a receção e o estado da carga.","Avise quem levanta e confirme a identificação.","Encomenda fechada. Fica tudo no histórico."];
  return(papel==="prestador"?P:C)[i]}

/* pagamento em aberto desta encomenda (para o botão mudar com a urgência) */
function emAberto(o){try{return(typeof payments!=="undefined"?payments:[]).filter(p=>String(p.operationId)===String(o.id)&&!/pago|anulad|reembols/i.test(p.status||""))
  .map(p=>({p,d:data(p.createdAt||p.date)})).sort((a,b)=>(a.d||0)-(b.d||0))[0]||null}catch(_){return null}}

/* Botão de ação contextual: normal, agora (principal) ou urgente (com «há N dias»). Também usado fora do Fluxo Vivo. */
function acao(texto,js,nivel,desde){if(!texto||!js)return"";const n=desde?dias(desde):0,cls=nivel==="urgente"?"bt-ctx bt-urgente":nivel==="agora"?"btn-primary bt-ctx":"btn-secondary bt-ctx";
  return`<button type="button" class="${cls}" onclick="${esc(js)}"${nivel==="urgente"&&n?` data-dica="Este pagamento está por fazer há ${n} ${n===1?"dia":"dias"}. Resolva-o num só passo."`:""}>${esc(texto)}${nivel==="urgente"&&n?`<small>há ${n} ${n===1?"dia":"dias"}</small>`:""}</button>`}

const IR_P={2:["Rever e aceitar","providerAprovacao"],3:["Registar a recolha","providerRecolha"],4:["Confirmar pagamento","providerPagamentos"],5:["Registar entrada no armazém","providerArmazenamento"],
  6:["Preparar a expedição","providerExpedicao"],7:["Atualizar a viagem","providerTransito"],8:["Confirmar a chegada","providerDestino"],9:["Avisar quem levanta","providerDisponivel"]};
function proximaAcao(o,i,papel){const pg=emAberto(o);
  if(papel==="cliente"){if(pg){const n=pg.d?dias(pg.d):0;return n>=2?acao("Regularizar agora","showPage('payments')","urgente",pg.d):acao("Pagar agora","showPage('payments')","agora")}return""}
  if(papel==="prestador"&&IR_P[i]){const urg=i===4&&pg&&pg.d&&dias(pg.d)>=2;return acao(IR_P[i][0],`showProviderPage('${IR_P[i][1]}')`,urg?"urgente":"agora",urg?pg.d:null)}return""}

/* Fluxo Vivo completo */
function render(o,papel){papel=papel||(eu()?.role==="prestador"?"prestador":"cliente");const i=indice(o),s=saude(o,i),mv=movimento(o);
  const fases=FASES.map(([nome,idx])=>{const ini=idx[0],fim=idx[idx.length-1],est=i>fim?"feito":i>=ini?"atual":"";
    const p=est==="feito"?100:est==="atual"?Math.round((idx.indexOf(i)+.5)*100/idx.length):0;
    const sub=est==="feito"?"Concluído":est==="atual"?`${ETAPAS[i]}, passo ${idx.indexOf(i)+1} de ${idx.length}`:idx.map(k=>ETAPAS[k]).join(", ");
    return`<li class="${est}"${est==="atual"?' aria-current="step"':""}><b>${nome}</b><span class="fv-pista"><i style="--p:${p}%"></i></span><small>${esc(sub)}</small></li>`}).join("");
  const ult=mv?`Última atualização ${quando(mv.d)}${mv.quem?` por ${esc(mv.quem)}`:""}.`:"";
  return`<section class="fv fv-${s.k}" aria-label="Estado da encomenda ${esc(o?.id||"")}"><div class="fv-topo"><p class="fv-frase">${esc(frase(o,i,papel))}</p><span class="fv-saude"><i aria-hidden="true"></i>${esc(s.t)}</span></div>
    <ol class="fv-fases">${fases}</ol><div class="fv-rodape"><small>${ult}${o?.date&&i<10?` Previsão de chegada: ${esc(o.date)}.`:""}</small>${proximaAcao(o,i,papel)}</div></section>`}

/* versão compacta para listas e painéis: frase + saúde + fio de 4 fases */
function compacto(o,papel){const i=indice(o),s=saude(o,i);const f=FASES.map(([,idx])=>`<i class="${i>idx[idx.length-1]?"feito":i>=idx[0]?"atual":""}"></i>`).join("");
  return`<div class="fv-mini fv-${s.k}"><span class="fv-fio" aria-hidden="true">${f}</span><span><b>${esc(ETAPAS[i])}</b><small><i aria-hidden="true"></i>${esc(s.t)}</small></span></div>`}

window.elologFluxo={render,compacto,acao,indice,saude,ETAPAS};
/* liga-se aos ecrãs existentes: cliente (Encomendas), prestador (ficha da encomenda) e rastreio */
Object.defineProperty(window,"renderClientOrderProgress",{configurable:true,get:()=>o=>render(o,"cliente"),set:()=>{}});
document.addEventListener("DOMContentLoaded",()=>{window.renderProviderOrderProgress=o=>render(o,"prestador");
  const rastrear=window.loadTracking;if(typeof rastrear==="function")window.loadTracking=function(){const r=rastrear.apply(this,arguments);try{
    const cod=(document.getElementById("trackingCode")?.value||"").trim().toUpperCase(),o=(typeof operations!=="undefined"?operations:[]).find(x=>String(x.id).toUpperCase()===cod),t=document.querySelector("#trackingResult .tracking-timeline");
    if(o&&t)t.outerHTML=render(o,eu()?.role==="prestador"?"prestador":"cliente")}catch(_){}return r}})})();
