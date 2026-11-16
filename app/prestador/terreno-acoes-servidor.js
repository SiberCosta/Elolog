/* Elolog — botões do serviço de terreno com servidor (v157).
   Na ficha do serviço (REC-…/ENT-…), cada botão faz agora a ação real no servidor, a mesma de «Serviços ao vivo»:
   - Iniciar rota: partilha a posição e calcula a chegada prevista (iniciar_percurso);
   - Cheguei: deixa de partilhar a posição e abre o comprovativo;
   - Conferir carga, Assinatura / PIN e Concluir: abrem o comprovativo (volumes conferidos, fotografias, assinatura no ecrã,
     quem entregou/recebeu). Ao enviar, o serviço fica concluído e a encomenda avança;
   - Ocorrência: abre as ocorrências da encomenda (ficam no servidor e todos as veem).
   Antes, com servidor, estes botões só mostravam um aviso ou não faziam nada. */
(function(){"use strict";
const D=()=>window.elologTerrenoDados,avisar=(m,t)=>window.showPlatformNotice?.(m,t||"info");
const noServidor=()=>{const u=typeof currentUser!=="undefined"?currentUser:null;return u?.role==="prestador"&&u?.providerCompany?.server===true};
const fechar=()=>{try{closeProviderDrawer("platformRecordDrawer")}catch(_){}};
const atualizar=()=>{try{window.elologTerrenoServidor?.ler?.().then(()=>{try{renderProviderFieldTeam()}catch(_){}})}catch(_){}try{window.elologSincronizarEncomendas?.sincronizar?.()}catch(_){}};
async function trabalho(id){const l=await D().servicos();return l.find(t=>String(t.id)===String(id))||null}
function codigo(id){try{const j=(getFieldJobs()||[]).find(x=>String(x.id)===String(id));return j?.operationId||""}catch(_){return""}}
function comprovativo(t){fechar();window.elologComprovativo?.abrir?.(t,()=>{try{sessionStorage.removeItem("elolog_chegou_"+t.id)}catch(_){}avisar(`${t.tipo==="recolha"?"Recolha":"Entrega"} registada. A encomenda avançou para a etapa seguinte.`,"success");atualizar()})}
async function acao(id,a,original,self,args){
  if(a==="route")return original.apply(self,args);
  if(a==="incident"){let c=codigo(id);if(!c)try{c=(await trabalho(id))?.encomenda?.codigo||""}catch(_){}
    if(!c)return avisar("Não encontrámos a encomenda deste serviço.","warning");fechar();return window.elologOcorrencias?.abrir?.(c)}
  if(!D()?.servicos)return avisar("O registo no terreno ainda está a carregar. Tente de novo dentro de segundos.","warning");
  let t=null;try{t=await trabalho(id)}catch(e){return avisar(D().erroTexto?.(e)||"Não foi possível ler o serviço.","error")}
  if(!t)return avisar("Este serviço já foi concluído ou não está agendado para hoje ou amanhã.","warning");
  if(a==="start"){if(D().estado?.().trabalho?.id===t.id)return avisar("O percurso deste serviço já está iniciado.","info");
    avisar("A obter a localização…","info");try{await D().iniciar(t,null);avisar("Rota iniciada. A empresa e o cliente veem a chegada prevista.","success");atualizar()}
    catch(e){avisar(D().erroTexto?.(e)||"Não foi possível iniciar a rota. Autorize a localização no telemóvel.","error")}return}
  if(a==="arrive"){if(D().estado?.().trabalho?.id===t.id)D().parar?.();else try{const sb=await window.elologProducao.sb();await sb.rpc("terminar_percurso",{p_trabalho:t.id})}catch(_){}window.elologMarcarChegada?.(t.id);avisar("Chegada registada. Confira a carga e recolha a assinatura.","success");return comprovativo(t)}
  if(["check","signature","complete","photo"].includes(a))return comprovativo(t);
  return original.apply(self,args)}
function instalar(){const f=window.fieldJobAction;if(typeof f!=="function"||f.__acoesSrv)return;
  const g=function(id,a){if(!noServidor())return f.apply(this,arguments);return acao(id,a,f,this,arguments)};Object.assign(g,f);g.__acoesSrv=true;window.fieldJobAction=g}
window.addEventListener("load",()=>setTimeout(instalar,50));
})();
