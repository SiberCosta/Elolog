/* Elolog — modo suporte (v112). A administração vê a Elolog como uma empresa prestadora a vê, para a ajudar.
   - Pede confirmação, regista o início e o fim na auditoria, e mostra uma faixa fixa com «Voltar à administração».
   - Sem servidor (demonstração): troca a vista para a da empresa e repõe a sessão da administração ao voltar.
   - Com servidor: as regras de segurança da base de dados não deixam a administração entrar nos dados internos da empresa,
     por isso o modo suporte abre em leitura, com os caminhos que a administração pode mesmo usar (ficha, histórico, operações). */
(function(){"use strict";
const CHAVE="elolog_suporte",esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const online=()=>{try{return!!window.elologProducao?.online?.()}catch(_){return false}};
const eu=()=>{try{return typeof currentUser!=="undefined"?currentUser:null}catch(_){return null}};
const ler=()=>{try{return JSON.parse(sessionStorage.getItem(CHAVE)||"null")}catch(_){return null}};
function auditar(p,acao,quem){try{const a=JSON.parse(localStorage.getItem("elolog_admin_audit")||"[]");a.unshift({id:"AUD-"+Date.now(),providerId:p.id,action:acao,by:quem||"Administrador Elolog",at:new Date().toISOString()});
  localStorage.setItem("elolog_admin_audit",JSON.stringify(a.slice(0,500)))}catch(_){}}

function faixa(){document.getElementById("elologFaixaSuporte")?.remove();const s=ler(),u=eu();document.body.classList.toggle("em-suporte",!!(s&&u?.suporte));if(!s||!u?.suporte)return;
  const f=document.createElement("div");f.id="elologFaixaSuporte";f.className="faixa-suporte";f.setAttribute("role","status");
  const desde=new Date(s.desde).toLocaleTimeString("pt-PT",{hour:"2-digit",minute:"2-digit"});
  f.innerHTML=`<span class="fs-ic" aria-hidden="true"><i class="ic ic-headset"></i></span><p><strong>Está a ver a Elolog como ${esc(s.empresa.name)}.</strong><span>Desde as ${desde}. Tudo o que fizer fica registado na auditoria em seu nome.</span></p><button type="button" id="elologVoltarAdmin">Voltar à administração</button>`;
  document.body.prepend(f);f.querySelector("button").onclick=voltar}

function entrar(p){const admin=eu();if(!admin||admin.role!=="admin")return;
  sessionStorage.setItem(CHAVE,JSON.stringify({admin,empresa:{id:p.id,name:p.name},desde:new Date().toISOString()}));auditar(p,"Modo de suporte iniciado",admin.name);
  currentUser={email:p.email||"",role:"prestador",name:`Suporte Elolog (${admin.name||"Administração"})`,providerCompany:{id:p.id,name:p.name},providerCompanyId:p.id,providerFunction:"admin",employeeRole:"admin",suporte:true};
  sessionStorage.setItem("th_user",JSON.stringify(currentUser));startApp();try{showPage("dashboard",null)}catch(_){}faixa();window.elologNavegacao?.atualizar();
  if(typeof showPlatformNotice==="function")showPlatformNotice(`Está a ver a Elolog como ${p.name}.`,"success")}

function voltar(){const s=ler();if(!s)return;auditar(s.empresa,"Modo de suporte terminado",s.admin?.name);sessionStorage.removeItem(CHAVE);
  currentUser=s.admin;sessionStorage.setItem("th_user",JSON.stringify(currentUser));startApp();faixa();window.elologNavegacao?.atualizar();
  try{showAdminPage("adminActiveProviders")}catch(_){}if(typeof showPlatformNotice==="function")showPlatformNotice(`Voltou à administração. A sessão de suporte de ${s.empresa.name} ficou registada.`,"success")}

/* com servidor: vista em leitura com caminhos reais */
function leitura(p){auditar(p,"Consulta de suporte",eu()?.name);
  openPlatformRecordDrawer(`Ajudar ${p.name}`,"Modo suporte",`<section class="pc-confirmar"><p>Com o servidor ligado, a administração não entra nos dados internos de uma empresa: é uma regra de segurança da base de dados. Pode ajudá-la a partir daqui, com o que vê da plataforma.</p></section>
    <div class="suporte-caminhos"><button type="button" class="btn-secondary" onclick="adminProviderDetails('${esc(p.id)}')">Ver a ficha da empresa</button><button type="button" class="btn-secondary" onclick="adminProviderHistory('${esc(p.id)}')">Ver o histórico</button>
    <button type="button" class="btn-secondary" onclick="closeProviderDrawer('platformRecordDrawer');showAdminPage('adminOperations')">Ver as operações</button><button type="button" class="btn-secondary" onclick="closeProviderDrawer('platformRecordDrawer');showAdminPage('adminSupport')">Abrir os pedidos de apoio</button></div>`)}

window.adminSupportMode=function(id){const p=(typeof getProviderProfiles==="function"?getProviderProfiles():[]).find(x=>String(x.id)===String(id));if(!p)return;
  if(online())return leitura(p);
  openPlatformConfirmation({title:`Entrar como suporte de ${p.name}?`,eyebrow:"Modo suporte",message:"Vai ver a Elolog como esta empresa a vê, para a ajudar. Tudo o que fizer fica registado na auditoria em seu nome. Pode voltar à administração a qualquer momento, pela faixa no topo.",
    details:`${p.name}, NIF ${p.nif||"por indicar"}`,confirmLabel:"Entrar como suporte",onConfirm:()=>entrar(p)})};
window.elologSuporte={entrar,voltar,faixa,ativo:()=>!!(ler()&&eu()?.suporte)};
document.addEventListener("DOMContentLoaded",()=>{const ini=window.startApp;if(typeof ini==="function")window.startApp=function(){const r=ini.apply(this,arguments);setTimeout(faixa,0);return r};setTimeout(faixa,1500)});
})();
