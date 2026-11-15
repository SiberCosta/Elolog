/* Elolog — «Lembrar este dispositivo durante 30 dias» na verificação em dois passos (v153, migração 00196).
   Guarda neste navegador um identificador aleatório por pessoa; o servidor só tem o resumo SHA-256 e reforça a sessão
   quando o reconhece. «Esquecer este dispositivo» apaga o identificador local; esquecerTodos() invalida todos no servidor. */
(function(){"use strict";
const S=()=>window.ELOLogServidor,chave=uid=>"elolog_dispositivo_"+uid;
async function uid(){try{const sb=await S().cliente(),{data}=await sb.auth.getUser();return data?.user?.id||null}catch(e){return null}}
function nomeAparelho(){const u=navigator.userAgent||"";const so=/Android/i.test(u)?"Android":/iPhone|iPad/i.test(u)?"iPhone/iPad":/Windows/i.test(u)?"Windows":/Mac/i.test(u)?"Mac":/Linux/i.test(u)?"Linux":"Aparelho";
  const nav=/Edg\//.test(u)?"Edge":/Chrome\//.test(u)?"Chrome":/Firefox\//.test(u)?"Firefox":/Safari\//.test(u)?"Safari":"navegador";return so+", "+nav}
async function reconhecer(){const id=await uid();if(!id)return false;let t=null;try{t=localStorage.getItem(chave(id))}catch(e){}if(!t)return false;
  try{const sb=await S().cliente(),{data,error}=await sb.rpc("reconhecer_dispositivo",{p_token:t});if(error)throw error;
    if(data===true)return true;try{localStorage.removeItem(chave(id))}catch(e){}return false}catch(e){console.warn("Dispositivo não reconhecido",e&&e.message);return false}}
async function lembrarSePedido(){const c=document.getElementById("mfaLembrar");if(!c||!c.checked)return;const id=await uid();if(!id)return;
  try{const sb=await S().cliente(),{data,error}=await sb.rpc("lembrar_dispositivo",{p_nome:nomeAparelho()});if(error)throw error;
    if(typeof data==="string"&&data.length===64)localStorage.setItem(chave(id),data)}catch(e){console.warn("Não foi possível lembrar o dispositivo",e&&e.message)}}
async function esquecerEste(){const id=await uid();if(id)try{localStorage.removeItem(chave(id))}catch(e){}}
async function esquecerTodos(){await esquecerEste();const sb=await S().cliente(),{data,error}=await sb.rpc("esquecer_dispositivos");if(error)throw error;return data||0}
window.elologDispositivo={reconhecer,lembrarSePedido,esquecerEste,esquecerTodos};
/* caixa por baixo do código */
function caixa(){const g=document.getElementById("mfaGrupoCodigo");if(!g||document.getElementById("mfaLembrar"))return;
  g.insertAdjacentHTML("afterend",`<label class="mfa-lembrar" style="display:flex;gap:10px;align-items:flex-start;margin:10px 0 4px;font-size:14px;line-height:1.4;cursor:pointer">
  <input type="checkbox" id="mfaLembrar" style="margin-top:3px;width:18px;height:18px;flex:none"><span><b>Lembrar este dispositivo durante 30 dias</b><br><small style="color:#5B6B78">Não volta a pedir o código neste aparelho. Não use em computadores partilhados.</small></span></label>`)}
/* em «Segurança e histórico»: esquecer todos os dispositivos de confiança */
function botaoSeguranca(){const pg=document.getElementById("providerSecurity");if(!pg||pg.querySelector("#dispEsquecer"))return;const alvo=pg.querySelector(".card")||pg;
  alvo.insertAdjacentHTML("beforeend",`<div class="provider-optional-tool" style="margin-top:16px;padding:14px 16px"><b>Dispositivos de confiança</b><p style="margin:4px 0 10px;color:#5B6B78;font-size:13.5px">Aparelhos onde escolheu «Lembrar este dispositivo». Se perdeu um telemóvel ou usou um computador partilhado, esqueça-os todos: o código volta a ser pedido.</p><button type="button" id="dispEsquecer" class="btn-secondary">Esquecer todos os dispositivos</button></div>`);
  pg.querySelector("#dispEsquecer").onclick=async ev=>{const b=ev.currentTarget;b.disabled=true;try{const n=await esquecerTodos();window.showPlatformNotice?.(n?`${n} ${n===1?"dispositivo esquecido":"dispositivos esquecidos"}. O código volta a ser pedido.`:"Não havia dispositivos de confiança.","success")}catch(e){window.showPlatformNotice?.(S()?.mensagem?.(e)||"Não foi possível concluir.","error")}finally{b.disabled=false}}}
function ligarSeguranca(){const sp=window.showProviderPage;if(typeof sp!=="function"||sp.__disp)return;const f=function(p){const r=sp.apply(this,arguments);const u=typeof currentUser!=="undefined"?currentUser:null;if(p==="providerSecurity"&&u?.providerCompany?.server)setTimeout(botaoSeguranca,50);return r};f.__disp=true;window.showProviderPage=f}
window.addEventListener("load",ligarSeguranca);
if(document.readyState!=="loading")caixa();else document.addEventListener("DOMContentLoaded",caixa);setTimeout(caixa,1500);
})();
