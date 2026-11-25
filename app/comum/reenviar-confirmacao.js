/* Elolog — reenviar o email de confirmação da conta (v175).
   Quando alguém tenta entrar e o servidor responde «Email not confirmed», aparece por baixo do aviso um cartão com
   «Reenviar email de confirmação» (Supabase Auth: auth.resend, tipo signup). Espera 60 s entre envios.
   Sem esta opção, quem não recebesse o primeiro email ficava sem forma de o pedir de novo. */
(function(){"use strict";
const S=()=>window.ELOLogServidor;let espera=0;
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
window.elologReenviarConfirmacao=function(email){document.getElementById("reenvConf")?.remove();
  const d=document.createElement("div");d.id="reenvConf";d.className="reenv-conf";d.setAttribute("role","status");
  d.innerHTML=`<button type="button" class="reenv-fechar" aria-label="Fechar">×</button><strong>Ainda não confirmou o email</strong>
    <p>Enviámos uma ligação para <b>${esc(email)}</b> quando criou a conta. Se não a encontra (veja também o spam ou as promoções), peça outra.</p>
    <button type="button" class="btn-secondary reenv-btn">Reenviar email de confirmação</button><small class="reenv-info" aria-live="polite"></small>`;
  document.body.appendChild(d);const b=d.querySelector(".reenv-btn"),info=d.querySelector(".reenv-info");
  d.querySelector(".reenv-fechar").onclick=()=>d.remove();
  b.onclick=async()=>{if(Date.now()<espera){info.textContent=`Aguarde ${Math.ceil((espera-Date.now())/1000)} s para pedir outro.`;return}
    b.disabled=true;info.textContent="A enviar…";
    try{const sb=await S().cliente();const{error}=await sb.auth.resend({type:"signup",email,options:{emailRedirectTo:/^https?:$/.test(location.protocol)?location.origin+location.pathname+"?confirmado=1":undefined}});if(error)throw error;
      espera=Date.now()+60000;info.textContent="Enviado. Pode demorar 1 a 2 minutos; abra a ligação do email mais recente e depois inicie sessão."}
    catch(e){info.textContent=/rate|security purposes|after \d+ seconds/i.test(e?.message||"")?"Já pedimos um email há pouco. Aguarde um minuto e tente de novo.":"Não foi possível reenviar agora. Tente daqui a pouco ou fale com contacto@elolog.pt."}
    finally{setTimeout(()=>{b.disabled=false},Math.max(0,espera-Date.now()))}}};
})();
