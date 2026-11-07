/* Elolog — Ficha da operação (v100): próximo passo e ações de etapa.
   Mostra o que falta para avançar (calculado no servidor) e só ativa «Avançar» quando os requisitos estão cumpridos.
   Dispensar a aprovação (entrada direta no armazém) exige motivo de exceção; o cancelamento exige observação. */
(function(){"use strict";
const F=()=>window.elologFichaDados,P=()=>window.elologProducao;
const esc=v=>String(v??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const aviso=(t,k)=>window.showPlatformNotice?.(t,k||"info");
const B=(k,t,extra,p)=>`<button type="button" class="${p?"btn-primary":"btn-secondary"}" data-fa="${k}" ${extra||""}>${t}</button>`;

function passo(f){if(f.demo)return`<div class="fo-passo-in"><p class="fo-nota">Demonstração: a ficha mostra os dados guardados neste navegador. As ações de etapa ficam disponíveis com o servidor.</p></div>`;
  const e=f.encomenda,N=F().nomeEstado,adm=f.papel==="administracao",acoes=[];
  if(!adm){const a=f.armazem;
    if(["aprovacao","agendamento","recolha","armazenamento"].includes(e.estado)&&!(a?.confirmado&&a?.carga_conferida))acoes.push(B("rececao","Confirmar receção no armazém"));
    if(["armazenamento","expedicao"].includes(e.estado))acoes.push(B("expedicao",e.navio?"Alterar navio e viagem":"Associar navio e viagem"));
    if(e.estado==="destino"&&f.tarefa_destino?.estado!=="concluida")acoes.push(B("processamento","Concluir processamento no destino",'',1));
    if(e.estado==="disponivel"&&!f.entrega?.identificacao)acoes.push(B("levantamento","Confirmar levantamento",'',1))}
  const prox=(f.proximos||[]).map(p=>{const falta=(p.falta||[]).filter(x=>!/motivo de exceção/.test(x));const ok=p.permitido&&!falta.length;
    const rot=p.excecao?"Entrada direta no armazém (dispensar aprovação)":`Avançar para ${N(p.para)}`;
    return`<div class="fo-prox ${ok?"ok":""}">${adm||!p.permitido?`<strong>${esc(rot)}</strong>`:B("avancar",rot,`data-para="${esc(p.para)}" data-exc="${p.excecao?1:""}" ${ok?"":"disabled"}`,ok&&!p.excecao)}
      ${falta.length?`<small>Falta: ${falta.map(esc).join(" · ")}</small>`:`<small>${p.permitido||adm?"Requisitos cumpridos.":"A sua função não executa esta etapa."}</small>`}</div>`}).join("");
  return`<div class="fo-passo-in"><h5>Próximo passo</h5>${adm?'<p class="fo-nota">Só a empresa prestadora executa as etapas; a administração acompanha.</p>':""}
    ${acoes.length?`<div class="fo-acoes">${acoes.join("")}</div>`:""}${prox||'<p class="fo-nota">Sem etapas seguintes.</p>'}
    ${f.pode_cancelar&&!adm?`<div class="fo-acoes">${B("avancar","Cancelar encomenda",'data-para="cancelada"')}</div>`:""}</div>`}

function janela(titulo,f,html,txtOk,fazer){const j=P().janela({eyebrow:"ENCOMENDA "+f.encomenda.codigo,titulo});
  j.mostrar(html+'<p class="campo-erro" id="faErro" role="alert"></p>',[{texto:"Voltar",acao:()=>j.fechar()},{texto:txtOk,principal:true,acao:async()=>{
    try{await fazer();j.fechar()}catch(x){document.getElementById("faErro").textContent=F().erro(x)}}}]);return j}
const v=id=>(document.getElementById(id)?.value||"").trim();
const campo=(id,rot,tipo,x)=>`<div class="pc-campo"><label for="${id}">${rot}</label><input id="${id}" type="${tipo||"text"}" ${x||""}></div>`;

function clique(ev,f,depois){const b=ev.target.closest("[data-fa]");if(!b||b.disabled||!f)return;const k=b.dataset.fa,e=f.encomenda,N=F().nomeEstado;
  const ok=t=>{aviso(t,"success");depois()};
  if(k==="avancar"){const para=b.dataset.para,exc=!!b.dataset.exc,canc=para==="cancelada";
    janela(canc?"Cancelar encomenda":exc?"Entrada direta no armazém":`Avançar para ${N(para)}`,f,
      `<p class="ed-intro">${N(e.estado)} → <b>${N(para)}</b>. Fica no histórico com data, hora, responsável e prestador.</p>
      ${exc?`<div class="pc-campo"><label for="faExc">Motivo de exceção * <small>(dispensa a aprovação)</small></label><textarea id="faExc" rows="2" maxlength="300"></textarea></div>`:""}
      <div class="pc-campo"><label for="faNota">Observações${canc?" *":""}</label><textarea id="faNota" rows="2" maxlength="500"></textarea></div>
      <div class="pc-campo"><label for="faDoc">Documento ou comprovativo <small>(opcional)</small></label><input id="faDoc" type="file" accept=".pdf,.jpg,.jpeg,.png"></div>`,
      canc?"Cancelar encomenda":"Avançar",async()=>{if(exc&&v("faExc").length<5)throw new Error("Indique o motivo de exceção.");if(canc&&v("faNota").length<5)throw new Error("Indique o motivo do cancelamento.");
        await F().avancar(f,para,v("faNota"),document.getElementById("faDoc").files[0],exc?v("faExc"):null);ok(`Encomenda em ${N(para)}.`)});return}
  if(k==="rececao"){const q=e.quantidade;janela("Confirmar receção no armazém",f,`<div class="pc-grelha">${campo("faQt","Quantidade recebida *","number",`min="0" step="1" value="${q??""}"`)}${campo("faLoc","Localização no armazém")}
      <div class="pc-campo ed-largo"><label><input id="faConf" type="checkbox"> Carga conferida (estado, etiquetas e volumes)</label></div>
      <div class="pc-campo ed-largo"><label for="faOc">Ocorrências ${q!=null?`<small>(obrigatório se não forem ${q} volumes)</small>`:""}</label><textarea id="faOc" rows="2" maxlength="500"></textarea></div></div>`,
      "Confirmar receção",async()=>{const n=v("faQt");if(n==="")throw new Error("Indique a quantidade recebida.");
        await F().rececao(f,{quantidade:Math.round(Number(n)),conferida:document.getElementById("faConf").checked,ocorrencias:v("faOc"),localizacao:v("faLoc")});ok("Receção registada.")});return}
  if(k==="expedicao"){janela("Navio, viagem e datas",f,`<div class="pc-grelha">${campo("faNavio","Navio *","text",`value="${esc(e.navio||"")}" maxlength="80"`)}${campo("faViagem","Viagem *","text",`value="${esc(e.viagem||"")}" maxlength="40"`)}
      ${campo("faPart","Partida prevista *","date",`value="${esc(e.partida_prevista||"")}"`)}${campo("faCheg","Chegada prevista","date",`value="${esc(e.chegada_prevista||"")}"`)}</div>`,
      "Guardar",async()=>{await F().expedicao(f,{navio:v("faNavio"),viagem:v("faViagem"),partida:v("faPart")||null,chegada:v("faCheg")||null});ok("Expedição associada.")});return}
  if(k==="processamento"){janela("Processamento no destino",f,`<p class="ed-intro">Confirme que a carga foi conferida no destino e está pronta para ser disponibilizada ao cliente.</p>
      <div class="pc-campo"><label for="faNota">Observações</label><textarea id="faNota" rows="2" maxlength="300"></textarea></div>`,"Concluir",async()=>{await F().processamento(f,v("faNota"));ok("Processamento concluído. Pode avançar para Disponível.")});return}
  if(k==="levantamento"){janela("Confirmar levantamento",f,`<div class="pc-campo"><label for="faId">Identificação de quem levanta * <small>(nome e documento)</small></label><input id="faId" maxlength="120"></div>
      <div class="pc-campo"><label for="faDoc">Comprovativo de entrega assinado *</label><input id="faDoc" type="file" accept=".pdf,.jpg,.jpeg,.png"></div>`,
      "Confirmar",async()=>{await F().levantamento(f,v("faId"),document.getElementById("faDoc").files[0]);ok("Levantamento confirmado. Pode avançar para Levantado.")})}}
window.elologFichaAcoes={passo,clique};
})();
