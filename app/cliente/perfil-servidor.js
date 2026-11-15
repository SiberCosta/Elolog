/* Elolog — perfil do cliente com o servidor (v142).
   1) «Dados do Cliente» lê a ficha do servidor (clientes): NIF, telefone e morada aparecem em qualquer aparelho; o que falta
      diz «Por indicar» e o botão passa a «Completar os meus dados».
   2) «Solicitar alteração dos dados» e «Eliminar conta» gravam um pedido no servidor (pedidos_cliente), que a administração
      aprova ou recusa em Operações › Clientes. Antes ficavam só neste navegador e a administração nunca os via.
   3) O perfil mostra o pedido pendente e a última decisão. Conta bloqueada ou eliminada: aviso e fim da sessão.
   Sem servidor (demonstração) fica tudo como estava. */
(function(){"use strict";
const S=()=>window.ELOLogServidor,P=()=>window.elologProducao,$=id=>document.getElementById(id);
const ativo=()=>typeof currentUser!=="undefined"&&currentUser?.role==="cliente"&&currentUser?.authenticatedBy!=="local-demo"&&!!S()?.ativo?.()&&!!P();
const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const dia=v=>{const d=new Date(v);return isNaN(d)?"":d.toLocaleDateString("pt-PT")};
const aviso=(t,k)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,k):alert(t);
const erro=e=>String(e?.message||e||"").replace(/^.*?ERROR:\s*/,"");
const TIPO={alteracao_dados:"alteração de dados",eliminacao_conta:"eliminação da conta"};
let ficha=null,pedidos=[],aLer=null;

async function ler(){if(!ativo())return null;if(aLer)return aLer;aLer=(async()=>{try{const sb=await P().sb(),u=await P().utilizador();if(!u)return null;
    const[c,p]=await Promise.all([sb.from("clientes").select("id,nome,nif,telefone,email,morada,estado").eq("id",u.id).maybeSingle(),
      sb.from("pedidos_cliente").select("id,tipo,estado,created_at,tratado_em").eq("cliente_id",u.id).order("created_at",{ascending:false}).limit(10)]);
    ficha=c.data||null;pedidos=p.data||[];return ficha}catch(e){console.warn("Perfil do cliente:",erro(e));return null}finally{setTimeout(()=>{aLer=null},300)}})();return aLer}

function campo(id,valor){const el=$(id);if(!el)return;const v=String(valor||"").trim();el.textContent=v||"Por indicar";el.classList.toggle("perfil-vazio",!v)}
function desenhar(){if(!ficha)return;
  if(ficha.estado==="bloqueado"||ficha.estado==="eliminado"){fechar(ficha.estado);return}
  currentUser.profile=Object.assign(currentUser.profile||{},{nif:ficha.nif||"",phone:ficha.telefone||"",address:ficha.morada||""});
  campo("clientProfileName",ficha.nome||currentUser.name);campo("clientProfileNif",ficha.nif);campo("clientProfilePhone",ficha.telefone);
  campo("clientProfileEmail",ficha.email||currentUser.email);campo("clientProfileAddress",ficha.morada);
  const falta=!ficha.nif||!ficha.telefone||!ficha.morada,acoes=document.querySelector("#clientProfile .client-profile-actions");
  const bt=acoes?.querySelector('[onclick="openClientDataChangeModal()"]');if(bt)bt.textContent=falta?"Completar os meus dados":"Solicitar alteração dos dados";
  let estado=$("clientePedidoEstado");if(!estado&&acoes){estado=document.createElement("p");estado.id="clientePedidoEstado";estado.className="perfil-pedido";acoes.after(estado)}
  if(!estado)return;const pend=pedidos.find(p=>p.estado==="pendente"),ult=pedidos.find(p=>p.estado!=="pendente");
  estado.innerHTML=pend?`<span class="perfil-selo">Em validação</span> Pedido de ${esc(TIPO[pend.tipo])} enviado a ${esc(dia(pend.created_at))}. A administração responde em breve.`
    :ult?`<span class="perfil-selo ${ult.estado==="aprovado"?"ok":"nao"}">${ult.estado==="aprovado"?"Aprovado":"Recusado"}</span> O seu pedido de ${esc(TIPO[ult.tipo])} foi ${ult.estado==="aprovado"?"aprovado":"recusado"} a ${esc(dia(ult.tratado_em||ult.created_at))}.`:"";
  estado.hidden=!estado.innerHTML}

let fechado=false;
function fechar(estado){if(fechado)return;fechado=true;
  aviso(estado==="bloqueado"?"A sua conta está bloqueada. Contacte o apoio Elolog para a desbloquear.":"A sua conta foi eliminada a seu pedido. Obrigado por ter usado a Elolog.","warning");
  setTimeout(()=>{try{typeof logout==="function"?logout():location.reload()}catch(_){location.reload()}},2500)}

async function enviarPedido(tipo,dadosPedido){const sb=await P().sb(),u=await P().utilizador();if(!u)throw new Error("Sessão terminada. Entre outra vez.");
  if(pedidos.some(p=>p.estado==="pendente"&&p.tipo===tipo))throw new Error(`Já tem um pedido de ${TIPO[tipo]} à espera de validação.`);
  const{error}=await sb.from("pedidos_cliente").insert({cliente_id:u.id,tipo,estado:"pendente",dados:dadosPedido});if(error)throw error;await ler();desenhar()}

function ligar(){
  const rp=window.renderClientProfile;if(typeof rp==="function"&&!rp.__srv){const n=function(){const r=rp.apply(this,arguments);if(ativo()){if(ficha)desenhar();ler().then(desenhar)}return r};n.__srv=1;window.renderClientProfile=n}
  const ab=window.openClientDataChangeModal;if(typeof ab==="function"&&!ab.__srv){const n=function(){const r=ab.apply(this,arguments);
      ["changeClientName","changeClientNif","changeClientPhone","changeClientEmail","changeClientAddress"].forEach(id=>{const i=$(id);if(i&&/^(Por indicar|—|-)$/.test(i.value.trim()))i.value=""});return r};n.__srv=1;window.openClientDataChangeModal=n}
  const sub=window.submitClientDataChangeRequest;if(typeof sub==="function"&&!sub.__srv){const n=async function(){if(!ativo())return sub.apply(this,arguments);
      const v=id=>$(id)?.value.trim()||"",notas=v("changeClientNotes");
      const d={nome:v("changeClientName"),nif:v("changeClientNif"),telefone:v("changeClientPhone"),email:v("changeClientEmail"),morada:v("changeClientAddress"),notas};
      if(!notas&&!d.nif&&!d.telefone&&!d.morada){aviso("Indique os dados que quer alterar ou completar.","warning");$("changeClientNotes")?.focus();return}
      if(d.nif&&!/^\d{9}$/.test(d.nif.replace(/\s/g,""))){aviso("O NIF tem 9 algarismos.","warning");$("changeClientNif")?.focus();return}
      try{await enviarPedido("alteracao_dados",d);window.closeClientDataChangeModal?.();aviso("Pedido enviado. A administração Elolog valida as alterações e o seu perfil é atualizado.","success")}
      catch(e){aviso(erro(e),"error")}};n.__srv=1;window.submitClientDataChangeRequest=n}
  const del=window.confirmClientAccountDeletion;if(typeof del==="function"&&!del.__srv){const n=async function(){if(!ativo())return del.apply(this,arguments);
      try{await enviarPedido("eliminacao_conta",{notas:"Pedido feito no perfil"});window.closeClientDeleteModal?.();
        aviso("Pedido de eliminação enviado. A conta fica ativa até a administração o confirmar.","success")}catch(e){aviso(erro(e),"error")}};n.__srv=1;window.confirmClientAccountDeletion=n}}

/* ao entrar: confirma que a conta continua ativa */
async function verificar(){if(!ativo())return;const f=await ler();if(f&&(f.estado==="bloqueado"||f.estado==="eliminado"))fechar(f.estado);else if($("clientProfile")?.classList.contains("active"))desenhar()}
ligar();if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);
window.addEventListener("load",()=>{ligar();setTimeout(verificar,2000)});setInterval(verificar,120000);
window.elologPerfilCliente={ler,desenhar,verificar};
})();
