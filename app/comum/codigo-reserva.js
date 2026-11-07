/* Elolog — 2.ª opção de verificação: CÓDIGO DE RESERVA (v85, migração 00152).
   Para quando não há acesso ao telemóvel. Funciona no 2.º passo da administração da plataforma e do administrador da empresa.
   - Depois de confirmar o código do telemóvel, se ainda não houver código de reserva, a plataforma gera um e mostra-o UMA vez.
   - Sem telemóvel: «Usar o código de reserva» → escreve o código → entra (cada uso fica registado e gera um aviso por email). */
(function(){"use strict";
const S=()=>window.ELOLogServidor,esc=v=>String(v).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const rpc=async(nome,args)=>{const sb=await S().cliente();const{data,error}=await sb.rpc(nome,args||{});if(error)throw error;return data};
let trocar=false;

function janela(html){return new Promise(fim=>{const d=document.createElement("div");d.className="reserva-fundo";d.setAttribute("role","dialog");d.setAttribute("aria-modal","true");
  d.innerHTML=`<div class="reserva-caixa">${html}</div>`;document.body.appendChild(d);
  d.querySelector("[data-fim]").onclick=()=>{d.remove();fim()};d.querySelector("[data-copiar]")?.addEventListener("click",e=>{
    navigator.clipboard?.writeText(d.querySelector("code").textContent).then(()=>{e.target.textContent="Copiado ✓"}).catch(()=>{})})})}

/** Chamado logo a seguir ao código do telemóvel estar certo. Gera e mostra o código se ainda não existir (ou se pediu um novo). */
async function depoisDoTelemovel(){try{
  const e=await rpc("estado_codigo_reserva"),tem=(Array.isArray(e)?e[0]:e)?.tem;if(tem&&!trocar)return;
  const codigo=await rpc("gerar_codigo_reserva");trocar=false;
  await janela(`<h2>O seu código de reserva</h2><p>Use-o para entrar se <strong>não tiver acesso ao telemóvel</strong>. Guarde-o num local seguro (papel, gestor de palavras-passe). <strong>Só é mostrado agora.</strong></p>
    <p class="reserva-codigo"><code>${esc(codigo)}</code></p><p class="reserva-nota">Cada uso fica registado e recebe um aviso por email. Pode gerar um novo quando quiser (o anterior deixa de valer).</p>
    <div class="reserva-botoes"><button type="button" class="btn-secondary" data-copiar>Copiar</button><button type="button" class="btn-primary" data-fim>Já guardei o código</button></div>`)
}catch(_){/* sem código de reserva: a entrada continua normalmente com o telemóvel */}}

/** Usa o código de reserva na sessão atual (palavra-passe já confirmada). */
async function usar(codigo){const c=String(codigo||"").toUpperCase().replace(/[^A-Z0-9]/g,"");
  if(c.length!==16)throw new Error("O código de reserva tem 16 caracteres (ex.: ABCD-EFGH-JKLM-NPQR).");
  if(await rpc("usar_codigo_reserva",{p_codigo:c})!==true)throw new Error("Código de reserva errado, ou demasiadas tentativas. Aguarde 15 minutos e tente de novo.")}

/** Acrescenta ao painel do 2.º passo: «Sem telemóvel? Usar o código de reserva» e «Gerar um novo código de reserva». */
function montar(painel,registoId,entrar){if(!painel||painel.querySelector(".reserva-opcoes"))return;
  painel.insertAdjacentHTML("beforeend",`<div class="reserva-opcoes"><button type="button" class="reserva-link" data-abrir>Sem acesso ao telemóvel? Usar o código de reserva</button>
    <div class="reserva-form" hidden><label>Código de reserva<input type="text" maxlength="19" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="XXXX-XXXX-XXXX-XXXX"></label>
      <p class="reserva-erro" role="alert"></p><button type="button" class="btn-primary full" data-usar>Entrar com o código de reserva</button></div>
    <label class="reserva-trocar"><input type="checkbox" data-trocar> Gerar um novo código de reserva ao entrar com o telemóvel</label></div>`);
  const caixa=painel.querySelector(".reserva-opcoes"),form=caixa.querySelector(".reserva-form"),campo=form.querySelector("input"),msg=form.querySelector(".reserva-erro"),botao=form.querySelector("[data-usar]");
  caixa.querySelector("[data-abrir]").onclick=()=>{if(registoId&&!document.getElementById(registoId)?.hidden){msg.textContent="Ainda não tem código de reserva: configure primeiro a aplicação de autenticação.";form.hidden=false;return}
    form.hidden=!form.hidden;msg.textContent="";if(!form.hidden)campo.focus()};
  caixa.querySelector("[data-trocar]").onchange=e=>{trocar=e.target.checked};
  const ir=async()=>{botao.disabled=true;msg.textContent="";try{await usar(campo.value);campo.value="";await entrar()}catch(e){msg.textContent=e.message||"Não foi possível usar o código."}finally{botao.disabled=false}};
  botao.onclick=ir;campo.addEventListener("keydown",e=>{if(e.key==="Enter")ir()})}

async function entrarAdmin(){const r=await rpc("sou_admin_plataforma"),a=Array.isArray(r)?r[0]:r;if(!a?.ok)throw new Error("Esta conta não tem acesso à administração.");
  const sb=await S().cliente(),{data:{user}}=await sb.auth.getUser();window.entrarAdmin?.({id:user.id,email:user.email,nome:a.nome})}

window.elologReserva={depoisDoTelemovel,usar};
const iniciar=()=>{montar(document.getElementById("adminMfaGroup"),"adminMfaRegisto",entrarAdmin);
  montar(document.getElementById("providerMfaPage"),"mfaRegisto",()=>window.elologMfaEmpresaConcluir?.())};
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",iniciar);else iniciar();
})();
