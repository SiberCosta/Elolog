/* Elolog — notificações do servidor para prestadores e clientes (v162).
   Até aqui só a administração lia a tabela «notificacoes»; o prestador e o cliente viam apenas os avisos criados neste
   aparelho. Com sessão real, este módulo junta ao painel as notificações que o servidor guarda para a pessoa ou para a sua
   empresa (as regras de acesso do servidor decidem quais) e grava no servidor quando são lidas.
   Sem sessão (demonstração) não faz nada. Carregar depois de comum/notificacoes.js. */
(function(){"use strict";
const S=()=>window.ELOLogServidor;
const eu=()=>{try{return typeof currentUser!=="undefined"?currentUser:window.currentUser}catch(e){return null}};
const ativo=()=>{const u=eu();if(!u||!S()?.ativo?.())return false;
  return u.role==="prestador"?u.providerCompany?.server===true:u.role==="cliente"&&u.authenticatedBy!=="local-demo"};
/* tipo do servidor → categoria do painel, prioridade e página que abre (prestador / cliente) */
const TIPOS={
  nova_simulacao:["operacional","normal","providerCotacao","proposals"],
  simulacao_aceite:["operacional","normal","providerAprovacao","proposals"],
  encomenda_nova:["operacional","normal","providerAprovacao","tracking"],
  estado_encomenda:["operacional","normal","providerOrder","tracking"],
  atraso_previsto:["terreno","alta","providerFieldTeam","tracking"],
  sem_sinal:["terreno","alta","providerFieldTeam","tracking"],
  pagamento_confirmado:["financeiro","normal","providerPagamentos","payments"],
  auto_pagamento:["financeiro","normal","providerPagamentos","payments"],
  alerta_financeiro:["financeiro","alta","providerFinanceiro","payments"],
  pedido_subscricao:["financeiro","normal","providerSubscription","dashboard"],
  documento_emitido:["documentos","normal","providerDocumentos","documents"],
  alerta_seguranca:["sistema","alta","providerSecurity","dashboard"],
  empresa_aprovada:["sistema","alta","providerSettings","dashboard"],
  tarifa_decisao:["sistema","normal","providerSettings","dashboard"],
  veiculo_decisao:["sistema","normal","providerSettings","dashboard"]};
let lista=[],uid="",aLer=null,ultima=0;
const ids=new Set();
function empresa(){try{return typeof currentProviderCompanyName==="function"?currentProviderCompanyName():eu()?.providerCompany?.name||""}catch(e){return""}}
function converter(n){const u=eu(),t=TIPOS[n.tipo]||["operacional","normal","providerOrder","dashboard"],prest=u?.role==="prestador";
  return{id:n.id,servidor:true,tipo:n.tipo,title:n.titulo||"Notificação",message:n.corpo||"",type:t[1]==="alta"?"warning":"info",
    audience:prest?"provider":"client",company:prest?empresa():"",to:n.user_id&&n.user_id===uid?u?.email:undefined,
    categoria:t[0],prioridade:t[1],pagina:prest?t[2]:t[3],actor:"Elolog",at:n.created_at,read:!!n.lida_em}}
async function ler(){if(!ativo()){if(lista.length){lista=[];ids.clear();desenhar()}return}
  if(aLer)return aLer;
  aLer=(async()=>{try{const sb=await S().cliente();const{data:ses}=await sb.auth.getSession();if(!ses?.session)return;uid=ses.session.user.id;
      const{data,error}=await sb.from("notificacoes").select("id,user_id,empresa_id,tipo,titulo,corpo,lida_em,created_at")
        .eq("para_plataforma",false).order("created_at",{ascending:false}).limit(100);
      if(error)throw error;
      const novas=(data||[]).map(converter),assin=JSON.stringify(novas.map(n=>[n.id,n.read]));
      if(assin!==JSON.stringify(lista.map(n=>[n.id,n.read]))){lista=novas;ids.clear();novas.forEach(n=>ids.add(n.id));desenhar();window.elologAlertas?.avisar?.()}
      ultima=Date.now()}
    catch(e){console.warn("Notificações do servidor indisponíveis:",e?.message||e)}
    finally{aLer=null}})();
  return aLer}
function desenhar(){try{window.renderNotificationCenter?.()}catch(e){}}
async function marcarLidas(novas){if(!novas.length)return;try{const sb=await S().cliente();
    const{error}=await sb.from("notificacoes").update({lida_em:new Date().toISOString()}).in("id",novas);if(error)throw error}
  catch(e){console.warn("Não foi possível marcar como lida no servidor:",e?.message||e);ler()}}
/* o painel lê e grava a lista local; aqui junta-se a do servidor, por ordem de data */
const getOrig=window.getOperationNotifications,saveOrig=window.saveOperationNotifications;
if(typeof getOrig!=="function"||typeof saveOrig!=="function")return;
window.getOperationNotifications=getOperationNotifications=function(){const local=getOrig.apply(this,arguments);
  if(!ativo()||!lista.length)return local;
  return[...local,...lista.map(n=>({...n}))].sort((a,b)=>Date.parse(b.at||0)-Date.parse(a.at||0))};
window.saveOperationNotifications=saveOperationNotifications=function(l){
  if(!ativo()||!lista.length||!Array.isArray(l))return saveOrig.apply(this,arguments);
  const lidas=l.filter(n=>ids.has(n.id)&&n.read&&lista.some(s=>s.id===n.id&&!s.read)).map(n=>n.id);
  lidas.forEach(id=>{const s=lista.find(x=>x.id===id);if(s)s.read=true});
  marcarLidas(lidas);
  return saveOrig.call(this,l.filter(n=>!ids.has(n.id)))};
/* abrir uma notificação do servidor leva à página certa */
const abrirOrig=window.openOperationNotification;
if(typeof abrirOrig==="function")window.openOperationNotification=openOperationNotification=function(id){
  const n=lista.find(x=>x.id===id);if(!n)return abrirOrig.apply(this,arguments);
  const todas=getOperationNotifications(),m=todas.find(x=>x.id===id);if(m){m.read=true;saveOperationNotifications(todas)}
  const p=document.getElementById("notificationPanel");if(p)p.hidden=true;desenhar();
  try{if(eu()?.role==="prestador")showProviderPage(n.pagina,null);else{const menu={proposals:"menuProposals",tracking:"menuOrders",payments:"menuPayments",documents:"menuDocuments",dashboard:"menuDashboard"}[n.pagina];
      showPage(n.pagina,menu?document.getElementById(menu):null)}}catch(e){}};
/* quando ler: ao entrar, quando o servidor avisa uma mudança, ao voltar à página e, por segurança, a cada minuto */
const inicio=window.startApp;if(typeof inicio==="function")window.startApp=async function(){const r=await inicio.apply(this,arguments);setTimeout(ler,600);return r};
window.addEventListener("elolog:mudanca",e=>{const t=e.detail?.tabelas||[];if(!t.length||t.includes("notificacoes"))ler()});
document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="visible"&&Date.now()-ultima>15e3)ler()});
setInterval(()=>{if(document.visibilityState==="visible")ler()},6e4);
window.elologNotificacoesServidor={ler,lista:()=>lista.map(n=>({...n}))};
})();
