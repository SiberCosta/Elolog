/* Elolog — componentes únicos do portal (v56; substitui botoes.js). Corre no site e na aplicação.
   1. Botões: tipo, rótulo, estado ocupado, onda e seta.   2. Campos sem rótulo recebem aria-label.   3. Tabelas viram cartões no telemóvel.
   4. Linhas com muitas ações: as secundárias passam para «Mais ações».   5. Menu: só a secção ativa é realçada e o seu grupo fica aberto.
   6. Validação: email/telefone/obrigatórios ao sair do campo; window.eloValidar(ids) marca e foca o primeiro em falta. */
(function(){"use strict";function improve(root){(root||document).querySelectorAll("button").forEach(function(button){if(!button.getAttribute("type")&&!(button.form&&!button.getAttribute("onclick")))button.type="button";
if(!button.hasAttribute("aria-label")&&!button.textContent.trim()&&button.title)button.setAttribute("aria-label",button.title);if(button.disabled)button.setAttribute("aria-disabled","true")})}document.addEventListener("DOMContentLoaded",function(){
improve(document);new MutationObserver(function(records){records.forEach(function(record){record.addedNodes.forEach(function(node){if(node.nodeType===1)improve(node)})})}).observe(document.body,{childList:true,subtree:true})});
document.addEventListener("click",function(event){var button=event.target.closest("button");if(!button)return;if(button.disabled||button.getAttribute("aria-disabled")==="true"){event.preventDefault();event.stopImmediatePropagation()}},true)})();(function(){
var SEL=".btn-primary,.btn-secondary,.btn-success,.btn-danger,.btn-ghost,.btn-client,.btn-simulate,.primary-btn,.btn-search,.btn-register-profile,.sim-add-button,.pwa-install-button,.hero-btn,.employee-action";document.addEventListener("pointerdown",
function(e){var b=e.target.closest&&e.target.closest(SEL);if(!b||b.disabled||matchMedia("(prefers-reduced-motion:reduce)").matches)return;var r=b.getBoundingClientRect(),s=document.createElement("span");s.className="bt-onda";s.style.left=e.clientX-r.left+"px";
s.style.top=e.clientY-r.top+"px";b.appendChild(s);setTimeout(function(){s.remove()},600)},true);window.elologBotao={carregar:function(b,on){if(!b)return;if(on){b.dataset.eloBusy="true";b.setAttribute("aria-busy","true")}else{delete b.dataset.eloBusy;
b.removeAttribute("aria-busy")}}}})();(function(){var SEL=".btn-primary,.primary-btn,.btn-simulate,.btn-search,.btn-success,.btn-register-profile,.hero .hero-btn-primary,#form-rastreio button[type=submit],.contact-form-actions button[type=submit]";
function setas(root){var lista=[];if(root.matches&&root.matches(SEL))lista.push(root);if(root.querySelectorAll)lista=lista.concat([].slice.call(root.querySelectorAll(SEL)));lista.forEach(function(b){
if(b.querySelector(".bt-seta")||b.dataset.semSeta!==void 0||b.querySelector("svg,i.ic,.ic"))return;[].slice.call(b.childNodes).forEach(function(n){if(n.nodeType===3)n.nodeValue=n.nodeValue.replace(/\s*[→›»]\s*$/,"");
else if(n.nodeType===1&&/^\s*[→›»]\s*$/.test(n.textContent))n.remove()});if(!b.textContent.trim())return;var s=document.createElement("span");s.className="bt-seta";s.setAttribute("aria-hidden","true");b.appendChild(s)})}function iniciar(){setas(document);
new MutationObserver(function(r){r.forEach(function(x){x.addedNodes.forEach(function(n){if(n.nodeType===1)setas(n)});if(x.target.nodeType===1&&x.target.matches(SEL))setas(x.target)})}).observe(document.body,{childList:true,subtree:true})}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",iniciar);else iniciar()})();
(function(){"use strict";
var $$=function(r,s){return [].slice.call((r||document).querySelectorAll(s))};
function texto(e){return (e&&e.textContent||"").replace(/\s+/g," ").trim()}
/* 2. rótulos */
function rotular(r){$$(r,"input:not([type=hidden]),select,textarea").forEach(function(c){
  if(c.getAttribute("aria-label")||c.getAttribute("aria-labelledby")||c.closest("label")||(c.id&&document.querySelector('label[for="'+c.id+'"]')))return;
  var t=c.placeholder||"";if(!t&&c.tagName==="SELECT"&&c.options[0])t=c.options[0].text;
  var a=c.previousElementSibling;if(a&&a.tagName==="LABEL"&&!a.htmlFor&&c.id&&!a.querySelector("input,select,textarea")){a.htmlFor=c.id;return}
  if(!t&&a&&/^(SMALL|SPAN|STRONG|B|P|LABEL)$/.test(a.tagName))t=texto(a);if(!t&&c.type==="date")t="Data";
  if(!t)t=c.title||c.name||"";if(t)c.setAttribute("aria-label",t.replace(/[…:]+$/,""))})}
/* 3. tabelas → cartões */
function tabelas(r){$$(r,"table").forEach(function(t){if(t.classList.contains("sem-cartoes"))return;var th=$$(t,"thead th");if(!th.length||th.length>9)return;
  t.classList.add("tabela-cartoes");$$(t,"tbody tr").forEach(function(tr){[].slice.call(tr.children).forEach(function(td,i){if(td.tagName==="TD"&&!td.hasAttribute("data-label")&&th[i]&&texto(th[i]))td.setAttribute("data-label",texto(th[i]))})})})}
/* 4. ações: mostra a principal e o primeiro botão; o resto fica em «Mais ações» */
var PRINC=/btn-primary|btn-success|primary-btn/;
function acoes(r){$$(r,"[class*=actions],[class*=acoes],[class*=action-menu]").forEach(function(box){if(box.dataset.acoes||box.closest("nav,.sidebar,.provider-desktop-header"))return;
  var bs=[].slice.call(box.children).filter(function(b){return b.tagName==="BUTTON"});if(bs.length<5)return;box.dataset.acoes="1";
  var extra=bs.filter(function(b,i){return i>0&&!PRINC.test(b.className)&&!/danger/.test(b.className)});if(extra.length<2)return;
  var d=document.createElement("details");d.className="acoes-mais";d.innerHTML='<summary>Mais ações</summary><div role="menu"></div>';
  extra.forEach(function(b){b.setAttribute("role","menuitem");if(/risk|delete|danger/.test(b.className)||/elimin|delete|remov/i.test(b.getAttribute("onclick")||""))b.classList.add("acao-perigo");d.lastChild.appendChild(b)});box.insertBefore(d,bs[0].nextSibling);
  d.addEventListener("click",function(e){if(e.target.closest("[role=menuitem]"))d.open=false})})}
document.addEventListener("click",function(e){$$(document,"details.acoes-mais[open]").forEach(function(d){if(!d.contains(e.target))d.open=false})});
/* 5. secção ativa no menu lateral */
function secao(){var pg=document.querySelector(".page.active");if(!pg)return;var menu=document.querySelector("#sidebar .menu");if(!menu)return;
  var bs=$$(menu,"button[onclick]"),alvo=null,id=pg.id;
  if(id==="tracking"||id==="clientOrders")alvo=document.getElementById("menuOrders");
  var cand=bs.filter(function(b){return b.dataset.pagina===id&&getComputedStyle(b).display!=="none"});if(cand.length)alvo=cand.filter(function(b){return b===ultimo})[0]||cand[0];
  bs.forEach(function(b){if(!alvo&&new RegExp("\\(\\s*['\"]"+id+"['\"]").test(b.getAttribute("onclick"))&&getComputedStyle(b).display!=="none")alvo=b});
  if(!alvo)alvo=menu.querySelector("button.active");
  bs.forEach(function(b){if(b!==alvo)b.removeAttribute("aria-current")});$$(menu,".secao-ativa").forEach(function(b){b.classList.remove("secao-ativa")});
  if(!alvo)return;alvo.setAttribute("aria-current","page");if(alvo.closest("#providerMenuStructure")){var ti=document.getElementById("pageTitle");if(ti&&id!=="dashboard")ti.textContent=texto(alvo)}var sub=alvo.closest(".client-submenu,.provider-submenu");if(!sub)return;
  var grp=sub.previousElementSibling&&sub.previousElementSibling.tagName==="BUTTON"?sub.previousElementSibling:sub.parentElement.querySelector(".provider-menu-main");
  if(grp){grp.classList.add("secao-ativa");grp.setAttribute("aria-expanded","true")}
  $$(menu,".client-submenu,.provider-submenu").forEach(function(s){var meu=s===sub;if(s.classList.contains("provider-submenu"))s.classList.toggle("open",meu);
    else if(s.id!=="clientOrdersSubmenu"||!meu)s.style.display=meu?"block":"none"})}
var tSec,ultimo=null;function agendar(){clearTimeout(tSec);tSec=setTimeout(secao,60)}
document.addEventListener("click",function(e){var b=e.target.closest&&e.target.closest("#sidebar .menu button[onclick]");if(!b||b.classList.contains("provider-menu-main")||b.classList.contains("client-group"))return;ultimo=b;agendar();setTimeout(secao,400);
  if(innerWidth<=900){var s=document.getElementById("sidebar");if(s)s.classList.remove("open");document.body.classList.remove("sidebar-mobile-open")}});
/* «Mais» do prestador: estado aberto/fechado para leitores de ecrã */
document.addEventListener("click",function(e){var tr=e.target.closest&&e.target.closest(".provider-more-trigger");$$(document,".provider-desktop-more").forEach(function(m){
  var abre=!!tr&&m.contains(tr)&&!m.classList.contains("aberto");m.classList.toggle("aberto",abre);var t2=m.querySelector(".provider-more-trigger");if(t2)t2.setAttribute("aria-expanded",String(abre))})});
document.addEventListener("keydown",function(e){if(e.key==="Escape")$$(document,".provider-desktop-more.aberto").forEach(function(m){m.classList.remove("aberto")})});
/* 6. validação */
var REGRA={email:/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/,tel:/^\+?[\d\s()-]{9,}$/};
function erro(c,msg){var id=(c.id||"campo")+"-erro",m=document.getElementById(id);c.toggleAttribute("aria-invalid",!!msg);if(msg)c.setAttribute("aria-invalid","true");
  if(!msg){if(m)m.remove();c.removeAttribute("aria-describedby");return}
  if(!m){m=document.createElement("small");m.id=id;m.className="campo-erro";m.setAttribute("role","alert");c.insertAdjacentElement("afterend",m)}m.textContent=msg;c.setAttribute("aria-describedby",id)}
function verificar(c){var v=(c.value||"").trim();if(!v)return c.required||c.dataset.obrigatorio!==void 0?"Campo obrigatório.":"";
  if(c.type==="email"&&!REGRA.email.test(v))return"Indique um email válido.";if(c.type==="tel"&&!REGRA.tel.test(v))return"Indique um telefone válido (mín. 9 dígitos).";
  if(c.type==="number"&&c.min!==""&&+v<+c.min)return"Valor mínimo: "+c.min+".";return""}
document.addEventListener("focusout",function(e){var c=e.target;if(c&&c.matches&&c.matches("input,select,textarea")&&(c.type==="email"||c.type==="tel"||c.required||c.getAttribute("aria-invalid")))erro(c,verificar(c))});
document.addEventListener("input",function(e){var c=e.target;if(c&&c.getAttribute&&c.getAttribute("aria-invalid")==="true"&&!verificar(c))erro(c,"")});
window.eloValidar=function(ids){var primeiro=null;ids.forEach(function(id){var c=document.getElementById(id);if(!c||c.disabled||!c.offsetParent)return;
  var v=(c.value||"").trim(),m=v?verificar(c):"Campo obrigatório.";erro(c,m);if(m&&!primeiro)primeiro=c});if(primeiro)primeiro.focus({preventScroll:false});return!primeiro};
function tudo(r){try{rotular(r);tabelas(r);acoes(r)}catch(e){}}
function iniciar(){tudo(document);secao();var fila=[],t;new MutationObserver(function(rs){rs.forEach(function(x){if(x.type==="attributes"){if(x.target.classList&&x.target.classList.contains("page"))agendar();return}
  x.addedNodes.forEach(function(n){if(n.nodeType===1)fila.push(n)})});clearTimeout(t);t=setTimeout(function(){var f=fila;fila=[];f.forEach(function(n){if(n.isConnected)tudo(n)})},40)})
  .observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:["class"]})}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",iniciar);else iniciar()})();
/* v60 — Iniciais do avatar da barra lateral sempre iguais ao nome do perfil (em todos os painéis). */
(function(){function iniciais(){var n=document.getElementById("userName"),a=document.getElementById("fieldSidebarAvatar");if(!n||!a)return;
  var p=(n.textContent||"").replace(/\(.*?\)/g,"").trim().split(/\s+/).filter(function(x){return/^[\p{L}\d]/u.test(x)&&!/^(de|da|do|dos|das|e|lda\.?|sa)$/i.test(x)});
  var i=p.length?(p[0][0]+(p.length>1?p[p.length-1][0]:"")).toUpperCase():"";if(i&&a.textContent!==i)a.textContent=i}
  function ligar(){var n=document.getElementById("userName");if(!n)return;iniciais();new MutationObserver(iniciais).observe(n,{childList:true,characterData:true,subtree:true})}
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);else ligar()})();
