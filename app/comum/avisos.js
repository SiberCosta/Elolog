/* Elolog — avisos (notificações temporárias no canto do ecrã). Script clássico: carregar antes de administracao/paginas.js
   e de comum/operacional.js (que acrescenta a empresa e a pessoa ao título quando há sessão).
   showPlatformNotice(mensagem, tipo, título): tipo = success | warning | error | info (deduzido do texto se faltar).
   - Título por tipo quando não há sessão («Não foi possível concluir», «Atenção», «Concluído», «Informação»).
   - Ícone em traço (SVG), barra de tempo que pára ao passar o rato, no máximo 4 avisos e sem repetidos. */
(function(){const TITULOS={success:"Concluído",warning:"Atenção",error:"Não foi possível concluir",info:"Informação"};const ICONES={success:'<path d="M5 12.5l4.2 4.2L19 7"/>',
warning:'<path d="M12 8v5"/><path d="M12 16.5v.5"/><path d="M10.3 3.9 2.4 18a2 2 0 0 0 1.7 3h15.8a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',error:'<circle cx="12" cy="12" r="9"/><path d="M15 9l-6 6M9 9l6 6"/>',
info:'<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><path d="M12 7.5v.5"/>'};const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);function tipoDe(texto,tipo){
if(TITULOS[tipo]&&tipo!=="info")return tipo;if(/erro|incorret|não foi possível|inválid|não encontr|não autorizado|sem ligação/i.test(texto))return"error";if(/atenção|pendente|deve |selecione|indique|preencha|limite/i.test(texto))return"warning";
if(/sucesso|guardad|criad|enviad|confirmad|atualizad|eliminad|autorizad/i.test(texto))return"success";return"info"}function remover(aviso){if(aviso.dataset.saindo)return;aviso.dataset.saindo="1";aviso.classList.add("removing");setTimeout(()=>aviso.remove(),
220)}window.showPlatformNotice=function(mensagem,tipo="info",titulo=""){const pilha=document.getElementById("platformToastStack");const texto=String(mensagem??"").trim();if(!texto)return;if(!pilha){console.info(texto);return}const k=tipoDe(texto,tipo);
const t=String(titulo||"").trim()||TITULOS[k];const igual=[...pilha.children].find(a=>a.dataset.chave===k+"|"+texto&&!a.dataset.saindo);if(igual){igual._recomecar?.();return}const duracao=Math.min(12e3,(k==="error"?6500:4500)+texto.length*25);
const aviso=document.createElement("article");aviso.className="platform-toast "+k;aviso.dataset.chave=k+"|"+texto;aviso.setAttribute("role",k==="error"?"alert":"status");
aviso.innerHTML='<span class="platform-toast-icon" aria-hidden="true"><svg viewBox="0 0 24 24">'+ICONES[k]+'</svg></span><div class="platform-toast-text"><strong>'+esc(t)+"</strong><p>"+esc(texto)+'</p></div><button type="button" class="platform-toast-close" aria-label="Fechar aviso"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button><span class="platform-toast-bar" aria-hidden="true"></span>';
let relogio=0,fim=0,resta=duracao;const barra=aviso.querySelector(".platform-toast-bar");const correr=()=>{fim=Date.now()+resta;barra.style.transition="none";barra.style.transform="scaleX("+resta/duracao+")";requestAnimationFrame(()=>{
barra.style.transition="transform "+resta+"ms linear";barra.style.transform="scaleX(0)"});relogio=setTimeout(()=>remover(aviso),resta)};const parar=()=>{clearTimeout(relogio);resta=Math.max(600,fim-Date.now());barra.style.transition="none";
barra.style.transform="scaleX("+resta/duracao+")"};aviso._recomecar=()=>{clearTimeout(relogio);resta=duracao;correr();aviso.classList.remove("pulsar");void aviso.offsetWidth;aviso.classList.add("pulsar")};aviso.addEventListener("mouseenter",parar);
aviso.addEventListener("mouseleave",correr);aviso.addEventListener("focusin",parar);aviso.querySelector(".platform-toast-close").onclick=()=>{clearTimeout(relogio);remover(aviso)};pilha.prepend(aviso);
while(pilha.children.length>4)pilha.lastElementChild.remove();correr()}})();
