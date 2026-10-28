(function(){let installPrompt=null;const button=()=>document.getElementById("installPwaButton");function isStandalone(){return window.matchMedia("(display-mode: standalone)").matches||window.navigator.standalone===true}function updateButton(){
const el=button();if(!el)return;el.hidden=isStandalone()||!installPrompt;el.classList.toggle("is-ready",!!installPrompt)}window.addEventListener("beforeinstallprompt",event=>{event.preventDefault();installPrompt=event;updateButton()});
window.addEventListener("appinstalled",()=>{installPrompt=null;updateButton();if(typeof showPlatformNotice==="function")showPlatformNotice("Aplicação Elolog instalada com sucesso.","success")});document.addEventListener("DOMContentLoaded",()=>{
const el=button();if(el)el.addEventListener("click",async()=>{if(!installPrompt)return;installPrompt.prompt();await installPrompt.userChoice;installPrompt=null;updateButton()});updateButton()});
if("serviceWorker"in navigator&&location.protocol.startsWith("http"))window.addEventListener("load",()=>navigator.serviceWorker.register("service-worker.js",{scope:"./"}).then(registration=>{registration.update();
if(registration.waiting)registration.waiting.postMessage({type:"SKIP_WAITING"})}).catch(()=>{}))})();
/* v70 — atualização automática da aplicação: quando há uma versão nova publicada, a página recarrega sozinha
   (só quando não está a escrever nem com uma janela aberta, para não perder nada). Verifica a cada 5 min e ao voltar à página. */
(function(){const atual=Number((document.querySelector('script[src*="?v="]')?.getAttribute("src")||"").match(/\?v=(\d+)/)?.[1]||0);if(!atual||!location.protocol.startsWith("http"))return;let nova=0;
  const ocupado=()=>!!document.querySelector("#pmJanela,.platform-modal.open,.modal.active")||/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName||"");
  const aplicar=()=>{if(!nova)return;if(ocupado())return;typeof showPlatformNotice==="function"&&showPlatformNotice("Nova versão da Elolog. A atualizar…","info");setTimeout(()=>location.reload(),1500)};
  async function verificar(){if(nova)return aplicar();try{const t=await (await fetch(location.pathname+"?verificar="+Date.now(),{cache:"no-store"})).text();const v=Number(t.match(/\?v=(\d+)/)?.[1]||0);if(v>atual){nova=v;aplicar()}}catch(e){}}
  setInterval(()=>{if(document.visibilityState==="visible")verificar()},3e5);document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="visible")verificar()});setInterval(aplicar,2e4)})();
