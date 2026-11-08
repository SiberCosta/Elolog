/* Elolog — estados vazios, etapas e esperas sem resposta (v110).
   1. Estado vazio = o que se passa + o que fazer a seguir + (quando existe) um botão que leva lá.
   2. Etapas do percurso: «Etapa 4 de 11», o nome de cada etapa e qual vem a seguir (em vez de 11 pontos sem nome).
   3. Esperas órfãs: uma mensagem «A carregar…» que fica no ecrã mais de 15 s passa a dizer o que fazer e dá «Tentar outra vez».
   Só apresentação: não altera dados nem fluxos. */
(function(){"use strict";
var esc=function(s){return String(s==null?"":s).replace(/[&<>"]/g,function(c){return{"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]})};
var CURTO={"Armazenamento":"Armazém","Levantamento":"Entrega"};
var ETAPAS=["Simulação","Cotação","Aprovação","Recolha","Pagamento","Armazenamento","Expedição","Em trânsito","Destino","Disponível","Levantamento"];

/* Páginas de etapa do prestador: número da etapa, o vazio e a ação que faz avançar o trabalho */
var ETAPA_PAG={
  providerRecolha:{n:4,t:"Não há recolhas por fazer",d:"Quando aprovar um pedido com recolha, ele aparece aqui para combinar o dia com o cliente.",a:"Ver pedidos por aprovar",ir:"providerAprovacao"},
  providerArmazenamento:{n:6,t:"O armazém está à espera da próxima carga",d:"Cada carga aparece aqui assim que a recolha ficar registada. Confira a quantidade e o estado quando chegar.",a:"Ver recolhas",ir:"providerRecolha"},
  providerExpedicao:{n:7,t:"Nada para expedir por agora",d:"Quando houver carga no armazém, prepare aqui a viagem e a lista de carga. Entretanto, confirme as próximas saídas.",a:"Ver calendário marítimo",ir:"providerMaritimeCalendar"},
  providerTransito:{n:8,t:"Nenhuma carga em viagem",d:"As cargas que expedir aparecem aqui até chegarem ao destino, com a previsão de chegada.",a:"Ver expedição",ir:"providerExpedicao"},
  providerDestino:{n:9,t:"Nada a chegar neste momento",d:"Quando um navio chegar com carga sua, confirme aqui a receção e o estado da carga.",a:"Ver cargas em trânsito",ir:"providerTransito"},
  providerDisponivel:{n:10,t:"Nenhuma encomenda à espera de levantamento",d:"Depois de confirmar a chegada, a encomenda passa para aqui e o destinatário fica a saber onde a levantar.",a:"Ver chegadas",ir:"providerDestino"},
  providerLevantamento:{n:11,t:"Nenhuma entrega por fechar",d:"As encomendas prontas a levantar aparecem aqui para registar quem levantou e fechar o processo.",a:"Ver encomendas disponíveis",ir:"providerDisponivel"}};

/* Mensagens vazias já existentes noutros módulos (texto exato) e a versão que ajuda a avançar */
var TXT={
  "Sem encomendas nesta etapa.":["Nada por tratar aqui agora","As encomendas aparecem nesta lista quando chegarem a este ponto do percurso."],
  "Não existem pedidos de apoio.":["Ninguém precisa de ajuda agora","Quando um cliente ou prestador pedir apoio, o pedido aparece aqui com a conversa toda."],
  "Sem registos nesta área.":["Ainda não há nada registado aqui","Assim que criar o primeiro registo, ele fica guardado nesta lista."],
  "Não existem encomendas a aguardar aprovação.":["Não há pedidos à espera da sua aprovação","Quando um cliente escolher a sua proposta, o pedido chega aqui para confirmar a carga e aceitar.","Ver cotações recebidas","showProviderPage('providerCotacao')"],
  "Nenhuma encomenda ativa corresponde aos filtros selecionados.":["Nenhuma encomenda com estes filtros","Limpe a pesquisa ou escolha outro estado para ver as restantes."],
  "Nenhum prestador corresponde aos filtros.":["Nenhuma empresa com estes filtros","Limpe a pesquisa ou escolha «Todos os estados» para ver as restantes.","Limpar filtros","elologVazio.limparFiltros('adminProviderSearch','adminProviderStatusFilter')"],
  "Ainda não existem simulações enviadas pelos clientes.":["Ainda não chegou nenhuma simulação","Quando um cliente pedir preço para uma rota sua, o pedido aparece aqui para responder."],
  "Ainda não existem encomendas registadas.":["Ainda não há encomendas","A primeira aparece aqui quando um cliente aprovar uma proposta."],
  "Sem pagamentos pendentes.":["Não há nada por pagar","Os pagamentos das próximas encomendas aparecem aqui com o valor confirmado."],
  "Sem pagamentos por receber.":["Não há valores por receber","Quando uma encomenda for paga, o recebimento aparece aqui."],
  "Sem ocorrências registadas.":["Sem ocorrências","Se algo correr mal numa recolha ou viagem, registe-o aqui para o cliente e a equipa saberem."],
  "Sem serviços agendados para hoje.":["Nada agendado para hoje","Os serviços que lhe forem atribuídos para hoje aparecem aqui por ordem de hora."],
  "Sem recolhas atribuídas para hoje.":["Nenhuma recolha para si hoje","Quando lhe atribuírem uma recolha, aparece aqui com a morada e o contacto."]};

var SVG='<svg viewBox="0 0 220 46" aria-hidden="true"><path class="vz-l" d="M10 30H210"/><circle class="vz-p" cx="10" cy="30" r="6"/><circle class="vz-p" cx="210" cy="30" r="6"/><rect class="vz-v" x="6" y="12" width="20" height="12" rx="2"/></svg>';
function bloco(t,d,a,js){return SVG+"<strong>"+esc(t)+"</strong>"+(d?"<p>"+esc(d)+"</p>":"")+(a&&js?'<button type="button" class="btn-secondary vz-acao" onclick="'+esc(js)+'">'+esc(a)+"</button>":"")}

/* Estado vazio de uma página de etapa (usado por manifestos.js) */
function etapa(page){var e=ETAPA_PAG[page];if(!e)return'<div class="provider-order-empty">Sem encomendas nesta etapa.</div>';
  return'<div class="provider-order-empty vz vz2" data-vz="1" role="status"><span class="vz-ic" aria-hidden="true"><i class="ic ic-'+icone(e.t+" "+e.d)+'"></i></span>'+bloco(e.t,e.d,e.a,"showProviderPage('"+e.ir+"')").replace(SVG,"")+"</div>"}
/* Estado vazio da equipa no terreno, conforme o separador escolhido */
function terreno(tipo,filtro,operador){var t=String(tipo||"serviço").toLowerCase(),pl=t==="recolha"?"recolhas":t==="entrega"?"entregas":t+"s",
  M={scheduled:["Nenhuma "+t+" agendada","As "+pl+" que agendar aparecem aqui por ordem de data."],active:["Nenhuma "+t+" em curso","Quando alguém começar uma "+t+" no terreno, acompanha-a aqui em tempo real."],
  done:["Ainda sem "+pl+" concluídas","Cada "+t+" fechada com assinatura e fotografias fica guardada aqui."],issues:["Sem ocorrências","Nenhuma "+t+" teve problemas registados."]},
  m=M[filtro]||["Ainda não há "+pl,"Agende a primeira "+t+" e escolha quem a faz e em que viatura."];
  return'<div class="provider-order-empty vz vz2" data-vz="1" role="status"><span class="vz-ic" aria-hidden="true"><i class="ic ic-truck"></i></span>'+bloco(m[0],m[1],operador?"":"Agendar "+t,operador?"":"openFieldAssignment('','"+String(tipo).replace(/'/g,"")+"')")+"</div>"}
function limparFiltros(){[].forEach.call(arguments,function(id){var c=document.getElementById(id);if(c){c.value="";c.dispatchEvent(new Event("input",{bubbles:true}));c.dispatchEvent(new Event("change",{bubbles:true}))}})}

/* Ícone acolhedor escolhido pelo assunto do vazio (biblioteca de ícones da plataforma) */
var ICONES=[[/navio|viage|manifest|mar[ií]tim/i,"ship"],[/pagament|valor|fatura|reembols|financeir|recebiment/i,"wallet"],[/document|ficheiro|comprovativ|fotografia/i,"file"],
  [/funcion|colega|equipa|grupo|operador/i,"users"],[/prestador|empresa|transportadora/i,"building"],[/apoio|reclama|ajuda/i,"headset"],[/ocorr|alerta|atras/i,"warning"],
  [/auditoria|acesso|entrada/i,"shield"],[/recolha|viatura|rota|servi[cç]o|paragem|expedi/i,"truck"],[/simula|proposta|cota/i,"tag"],[/mensage|conversa|notifica/i,"bell"],[/encomenda|opera|carga/i,"box"]];
function icone(t){for(var i=0;i<ICONES.length;i++)if(ICONES[i][0].test(t))return ICONES[i][1];return"check"}
/* Dois tamanhos: grande nas páginas e listas; compacto dentro de cartões e painéis */
var COMPACTO=".pa-vazio,.pf-vazio,.fo-vazio,.field-board-empty,.em-vazio,.notification-empty,.pm-vazio,.au-vazio,.pv-vazio,.ed-vazio";
function vazio(el){if(el.dataset.vz)return;var t=(el.textContent||"").trim(),m=TXT[t]||(window.ELOLOG_VAZIOS||{})[t];if(!m||el.children.length)return;el.dataset.vz=1;el.setAttribute("role","status");
  var ic='<span class="vz-ic" aria-hidden="true"><i class="ic ic-'+icone(t+" "+m[0])+'"></i></span>';
  if(el.matches(COMPACTO)){el.classList.add("vz-c");el.innerHTML=ic+"<div><strong>"+esc(m[0])+"</strong>"+(m[1]?"<span>"+esc(m[1])+"</span>":"")+(m[2]&&m[3]?'<button type="button" class="vz-ligacao" onclick="'+esc(m[3])+'">'+esc(m[2])+"</button>":"")+"</div>";return}
  el.classList.add("vz","vz2");el.innerHTML=ic+bloco(m[0],m[1],m[2],m[3]).replace(SVG,"")}
var VAZIOS=".provider-order-empty,.finance-empty,.empty-state,.automation-empty,.employee-empty,.client-payment-empty,.client-home-empty,.client-doc-empty,.client-active-empty,"+COMPACTO;
function varrer(r){(r||document).querySelectorAll(VAZIOS).forEach(vazio)}

/* Etapas com nome: substitui «ETAPA 04» e os 11 pontos por «Etapa 4 de 11», a barra com os nomes e o que vem a seguir */
function etapas(){document.querySelectorAll(".provider-status-card").forEach(function(c){if(c.dataset.et)return;var s=c.querySelector("span"),m=s&&/(\d+)/.exec(s.textContent);if(!m)return;var n=+m[1];c.dataset.et=1;
  c.classList.add("et-cartao");s.className="et-num";s.textContent="Etapa "+n+" de "+ETAPAS.length;
  var seg=ETAPAS.map(function(nome,i){var k=i+1;return'<li class="'+(k<n?"feito":k===n?"atual":"")+'"'+(k===n?' aria-current="step"':"")+'><i></i><span>'+esc(CURTO[nome]||nome)+"</span></li>"}).join("");
  var seguinte=ETAPAS[n]?"A seguir: "+ETAPAS[n]:"Última etapa: a encomenda fecha aqui";
  c.querySelector(".vz-trilho")&&c.querySelector(".vz-trilho").remove();
  c.insertAdjacentHTML("beforeend",'<ol class="et-barra" aria-label="Percurso da encomenda">'+seg+'</ol><p class="et-seguinte">'+esc(seguinte)+"</p>")})}

/* Esperas órfãs: «A carregar…», «A calcular…», «A consultar…» paradas mais de 15 s */
var vistos=new WeakMap(),ESPERA=/^A (carregar|calcular|consultar|obter|ler|enviar)[^.]{0,60}(…|\.\.\.)$/;
function vigiar(){var agora=Date.now();document.querySelectorAll(".page.active .provider-order-empty, .page.active .pm-vazio, .page.active .pa-vazio, .page.active td, .page.active p, .page.active div:not(:has(*))").forEach(function(el){
  if(el.children.length||!ESPERA.test((el.textContent||"").trim())){vistos.delete(el);return}if(!vistos.has(el)){vistos.set(el,agora);return}if(agora-vistos.get(el)<15000||el.dataset.orfa)return;
  el.dataset.orfa=1;el.classList.add("vz","vz2","vz-orfa");el.setAttribute("role","status");
  el.innerHTML=bloco("Está a demorar mais do que o costume","Pode ser a ligação à internet. Verifique-a e tente outra vez; os seus dados não se perdem.","Tentar outra vez","elologVazio.repetir()")})}
function repetir(){var b=document.querySelector("#sidebar button.active, .provider-submenu button.active, #sidebar .menu>button.active");if(b){b.click();return}location.reload()}

window.elologVazio={etapa:etapa,terreno:terreno,limparFiltros:limparFiltros,repetir:repetir,ETAPAS:ETAPAS};
document.addEventListener("DOMContentLoaded",function(){etapas();varrer();setInterval(vigiar,5000);
  new MutationObserver(function(ms){ms.forEach(function(m){m.addedNodes.forEach(function(n){if(n.nodeType===1)varrer(n.matches&&n.matches(VAZIOS)?n.parentNode:n)})})}).observe(document.body,{childList:true,subtree:true})})})();
