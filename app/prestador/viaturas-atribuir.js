/* Elolog — atribuir uma viatura a um funcionário (v155). Em «Viaturas», cada viatura tem «Atribuir a funcionário».
   A viatura fica como «viatura habitual» da pessoa escolhida (e deixa de estar com quem a tinha). Com servidor, grava
   no servidor (gerir-funcionarios › atualizar › veiculo), com auditoria; sem servidor, grava neste aparelho. */
(function(){"use strict";
const S=()=>window.ELOLogServidor,esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const noServidor=()=>{const u=typeof currentUser!=="undefined"?currentUser:null;return u?.role==="prestador"&&u?.providerCompany?.server===true};
const equipa=()=>typeof getProviderEmployees==="function"?getProviderEmployees().filter(e=>e.active!==false):[];
window.atribuirViatura=function(matricula){if(typeof requireProviderPermission==="function"&&!requireProviderPermission("manage_employees"))return;
  const l=equipa().sort((a,b)=>(a.role==="field_operator"?0:1)-(b.role==="field_operator"?0:1)||String(a.name).localeCompare(String(b.name),"pt")),atual=l.find(e=>e.usualVehicle===matricula);
  openPlatformRecordDrawer(`Viatura ${matricula}`,"ATRIBUIR A FUNCIONÁRIO",`<form class="admin-provider-form" onsubmit="event.preventDefault();guardarAtribuicaoViatura('${esc(matricula)}')">
    <section class="admin-provider-form-section"><label>Funcionário<select id="viaturaFuncionario">
      <option value="">Sem funcionário (viatura livre)</option>${l.map(e=>`<option value="${esc(e.id)}" ${atual?.id===e.id?"selected":""}>${esc(e.name)}, ${esc(typeof providerRoleLabel==="function"?providerRoleLabel(e.role):e.role)}${e.usualVehicle&&e.usualVehicle!==matricula?` (tem ${esc(e.usualVehicle)})`:""}</option>`).join("")}</select></label>
    <p class="provider-modal-note">A viatura passa a ser a viatura habitual desta pessoa e aparece já escolhida nos serviços que lhe forem atribuídos. Fica registado na auditoria.</p>
    <div id="viaturaErro" class="password-recovery-feedback error" hidden></div>
    <div class="provider-modal-actions"><button type="button" class="btn-secondary" onclick="closeProviderDrawer('platformRecordDrawer')">Cancelar</button><button type="submit" class="btn-primary">Guardar</button></div></section></form>`)};
window.guardarAtribuicaoViatura=async function(matricula){const id=document.getElementById("viaturaFuncionario")?.value||"",erro=m=>{const b=document.getElementById("viaturaErro");if(b){b.textContent=m;b.hidden=false}};
  const l=typeof getProviderEmployees==="function"?getProviderEmployees():[],antes=l.filter(e=>e.usualVehicle===matricula&&String(e.id)!==String(id)),novo=l.find(e=>String(e.id)===String(id));
  const btn=document.querySelector('#platformRecordDrawer button[type="submit"]');if(btn){btn.disabled=true;btn.textContent="A guardar…"}
  try{if(noServidor()){for(const e of antes)await S().gerirFuncionarios("atualizar",{id:e.id,alteracoes:{veiculo:""}});if(novo)await S().gerirFuncionarios("atualizar",{id:novo.id,alteracoes:{veiculo:matricula}})}
    antes.forEach(e=>e.usualVehicle="");if(novo)novo.usualVehicle=matricula;if(!noServidor())try{saveProviderEmployees(l)}catch(_){}
    try{closeProviderDrawer("platformRecordDrawer")}catch(_){}window.showPlatformNotice?.(novo?`Viatura ${matricula} atribuída a ${novo.name}.`:`Viatura ${matricula} ficou livre.`,"success");
    try{renderProviderEmployees()}catch(_){}try{renderProviderFieldTeam()}catch(_){}setTimeout(()=>{try{renderProviderFieldTeam()}catch(_){}},1200)}
  catch(e){erro(S()?.mensagem?.(e)||"Não foi possível guardar.")}finally{if(btn){btn.disabled=false;btn.textContent="Guardar"}}};
})();
