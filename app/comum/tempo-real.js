/* Elolog — tempo real (v153). Com sessão no servidor, ouve as mudanças (Supabase Realtime, migração 00195) nas tabelas
   que a pessoa pode ler e atualiza logo o ecrã: encomendas, simulações, pagamentos, notificações, apoio, terreno.
   As regras de acesso do servidor decidem quem recebe cada mudança. Se o canal cair, pergunta ao servidor a cada 5 s.
   Cada mudança dispara o evento «elolog:mudanca» (usado pelos avisos de novidade) e as atualizações que já existiam. */
(function(){"use strict";
const TABELAS=["encomendas","simulacoes","pagamentos","notificacoes","tickets","ticket_mensagens","trabalhos_terreno","encomenda_historico","cliente_notas"];
let canal=null,ligado=false,espera=null,reserva=null,pendentes=new Set();
const S=()=>window.ELOLogServidor;
const comSessao=()=>{try{const u=typeof currentUser!=="undefined"?currentUser:window.currentUser;return !!(u&&S()?.ativo?.()&&(u.role==="cliente"||u.providerCompany?.server||u.role==="admin"))}catch(e){return false}};
function atualizarTudo(origem){
  const tabelas=[...pendentes];pendentes.clear();window.elologSemSaltos?.proteger();
  try{window.elologAtualizarCotacoes?.()}catch(e){}
  try{window.elologAtualizarCliente?.()}catch(e){}
  try{const u=typeof currentUser!=="undefined"?currentUser:null;if(u?.role==="prestador")window.elologSincronizarEncomendas?.sincronizar?.()}catch(e){}
  /* os módulos que já se atualizavam ao voltar à página ouvem este evento */
  try{if(document.visibilityState==="visible")document.dispatchEvent(new Event("visibilitychange"))}catch(e){}
  window.dispatchEvent(new CustomEvent("elolog:mudanca",{detail:{tabelas,origem}}))}
function agendar(tabela){if(tabela)pendentes.add(tabela);clearTimeout(espera);espera=setTimeout(()=>atualizarTudo("tempo-real"),250)}
function reservaLigar(){clearInterval(reserva);reserva=setInterval(()=>{if(!comSessao())return;if(!canal){ligar();return}if(!ligado&&document.visibilityState==="visible")atualizarTudo("reserva")},5000)}
async function ligar(){
  if(canal||!comSessao())return;
  try{const sb=await S().cliente();if(!sb?.channel)return;
    canal=sb.channel("elolog-vivo-"+Math.random().toString(36).slice(2,8));
    TABELAS.forEach(t=>canal.on("postgres_changes",{event:"*",schema:"public",table:t},()=>agendar(t)));
    canal.subscribe(estado=>{ligado=estado==="SUBSCRIBED";if(estado==="CHANNEL_ERROR"||estado==="TIMED_OUT"||estado==="CLOSED"){ligado=false}})}
  catch(e){console.warn("Tempo real indisponível; a atualizar a cada 5 segundos.",e&&e.message);ligado=false}
  reservaLigar()}
async function desligar(){ligado=false;const c=canal;canal=null;try{if(c)(await S().cliente()).removeChannel(c)}catch(e){}}
window.elologTempoReal={ligar,desligar,estado:()=>({ligado,canal:!!canal})};
const inicio=window.startApp;if(typeof inicio==="function")window.startApp=async function(){const r=await inicio.apply(this,arguments);setTimeout(ligar,400);return r};
const sair=window.logout;if(typeof sair==="function")window.logout=function(){desligar();return sair.apply(this,arguments)};
reservaLigar();
})();
