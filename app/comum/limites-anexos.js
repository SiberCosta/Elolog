/* Elolog — limites de fotografias e documentos por pedido, definidos por cada prestador (v116).
   Por omissão não há limite. O administrador da empresa define-os em Configurações (vazio = sem limite).
   Com servidor: empresas.limite_fotos / limite_documentos (definir_limites_anexos, limites_anexos). Sem servidor: neste navegador.
   O tamanho de cada ficheiro continua limitado a 4 MB (limite técnico do envio). */
(function(){"use strict";
const P=()=>window.elologProducao,cache={},SEM={fotos:Infinity,documentos:Infinity};
const chaveLocal=nome=>"elolog_limites_anexos_"+String(nome||"").trim().toLowerCase();
const norm=v=>Number(v)>0?Number(v):Infinity;
const empresaPropria=()=>typeof currentProviderCompanyName==="function"?currentProviderCompanyName():"";
/* prestador escolhido pelo cliente no simulador (id no servidor, nome na demonstração) */
const escolhido=()=>{const c=document.querySelector('.sim-provider-proposal[aria-pressed="true"]');return c?(c.dataset.empresaId||c.dataset.provider||""):""};

function ler(ref){if(!ref)return SEM;if(cache[ref])return cache[ref];try{const l=JSON.parse(localStorage.getItem(chaveLocal(ref))||"null");if(l)return{fotos:norm(l.fotos),documentos:norm(l.documentos)}}catch(_){}return SEM}
async function carregar(ref,id){if(!P()?.online?.()||!id)return ler(ref);try{const sb=await P().sb();const{data,error}=await sb.rpc("limites_anexos",{p_empresa:id||null});if(error)throw error;
  cache[ref]={fotos:norm(data?.fotos),documentos:norm(data?.documentos)};return cache[ref]}catch(_){return ler(ref)}}

/** limites a aplicar: «prestador» (a própria empresa) ou «cliente» (o prestador escolhido; sem escolha, sem limite) */
function limites(ctx){if(ctx==="prestador")return ler(cache.__minha?"__minha":empresaPropria());const ref=escolhido();return ref?ler(ref):SEM}
const restantes=(tipo,ctx,usados)=>{const m=limites(ctx)[tipo];return m===Infinity?Infinity:Math.max(0,m-usados)};
const texto=(tipo,ctx,usados)=>{const m=limites(ctx)[tipo];return m===Infinity?`${usados} ${tipo==="fotos"?"fotos":"documentos"}`:`${usados}/${m} ${tipo==="fotos"?"fotos":"documentos"}`};
const aviso=(tipo,ctx)=>`Este prestador aceita no máximo ${limites(ctx)[tipo]} ${tipo==="fotos"?"fotografias":"documentos"} por pedido.`;

/* configurações do prestador: cartão «Fotografias e documentos por pedido» */
async function guardar(){const f=document.getElementById("cfgLimiteFotos")?.value.trim(),d=document.getElementById("cfgLimiteDocs")?.value.trim(),fb=document.getElementById("cfgLimitesFb");
  const n=v=>v===""?null:Math.round(Number(v));if([f,d].some(v=>v!==""&&!(Number(v)>=1&&Number(v)<=1000))){if(fb)fb.textContent="Indique um número entre 1 e 1000, ou deixe vazio para não ter limite.";return}
  try{if(P()?.online?.()){const sb=await P().sb();const{error}=await sb.rpc("definir_limites_anexos",{p_fotos:n(f),p_documentos:n(d)});if(error)throw error}
    localStorage.setItem(chaveLocal(empresaPropria()),JSON.stringify({fotos:n(f),documentos:n(d)}));delete cache[empresaPropria()];delete cache.__minha;
    if(fb)fb.textContent=`Guardado. Fotografias: ${n(f)??"sem limite"}. Documentos: ${n(d)??"sem limite"}.`}
  catch(e){if(fb)fb.textContent="Não foi possível guardar: "+String(e.message||e).replace(/^.*?ERROR:\s*/,"")}}
function cartao(){const box=document.getElementById("providerSettingsContent");if(!box||box.querySelector("#cfgLimiteFotos"))return;const l=ler(empresaPropria()),v=x=>x===Infinity?"":x;
  const s=document.createElement("section");s.className="provider-warehouse-settings cfg-limites";
  s.innerHTML=`<header><div><h4>Fotografias e documentos por pedido</h4><p>Quantos ficheiros os clientes e a sua equipa podem anexar a cada pedido. Deixe vazio para não ter limite.</p></div></header>
    <div class="admin-settings-grid"><div class="admin-setting-card"><label for="cfgLimiteFotos">Máximo de fotografias</label><input id="cfgLimiteFotos" type="number" min="1" max="1000" inputmode="numeric" placeholder="Sem limite" value="${v(l.fotos)}"></div>
    <div class="admin-setting-card"><label for="cfgLimiteDocs">Máximo de documentos</label><input id="cfgLimiteDocs" type="number" min="1" max="1000" inputmode="numeric" placeholder="Sem limite" value="${v(l.documentos)}"></div></div>
    <div class="provider-settings-actions"><button type="button" class="btn-secondary" id="cfgLimitesGuardar">Guardar limites</button><small id="cfgLimitesFb" role="status"></small></div>`;
  const acoes=box.querySelector(".provider-settings-actions");acoes?acoes.before(s):box.appendChild(s);s.querySelector("#cfgLimitesGuardar").addEventListener("click",guardar)}
function ligar(){const r=window.renderProviderSettings;if(typeof r==="function"&&!r.__limites){const n=function(){const x=r.apply(this,arguments);cartao();return x};n.__limites=1;window.renderProviderSettings=n}}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);else ligar();

/* carregar os limites do prestador escolhido pelo cliente e os da própria empresa */
document.addEventListener("click",e=>{const c=e.target.closest?.(".sim-provider-proposal");if(!c)return;const ref=c.dataset.empresaId||c.dataset.provider;if(ref)carregar(ref,c.dataset.empresaId)});
async function minha(){if(!P()?.online?.()||typeof currentUser==="undefined"||currentUser?.role!=="prestador")return;try{const sb=await P().sb();const{data}=await sb.rpc("limites_anexos",{p_empresa:null});
  if(data){cache.__minha={fotos:norm(data.fotos),documentos:norm(data.documentos)}}}catch(_){}}
setTimeout(minha,4000);
window.elologLimitesAnexos={limites,restantes,texto,aviso,carregar,minha};
})();
