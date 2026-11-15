/* Elolog — editar funcionário no servidor (v154). Antes, «Guardar alterações» só mudava a cópia local e a função voltava
   ao que estava no servidor. Agora envia as alterações à função «gerir-funcionarios» (ação «atualizar»), que valida,
   regista na auditoria e mantém pelo menos um Admin ativo. A fotografia continua a ser gravada como antes. */
(function(){"use strict";
const S=()=>window.ELOLogServidor;
const PAPEL={admin:"admin_empresa",operador:"operador",field_operator:"operador_terreno",armazem:"armazem",financeiro:"financeiro"};
const noServidor=()=>{const u=typeof currentUser!=="undefined"?currentUser:null;return u?.role==="prestador"&&u?.providerCompany?.server===true};
const avisar=(m,t)=>window.showPlatformNotice?.(m,t||"info");
function instalar(){const original=window.saveProviderEmployeeEdit;if(typeof original!=="function"||original.__servidor)return;
  const novo=async function(event,id){if(!noServidor())return original.apply(this,arguments);event?.preventDefault?.();
    if(typeof requireProviderPermission==="function"&&!requireProviderPermission("manage_employees"))return;
    const $=i=>document.getElementById(i),erro=m=>{const b=$("editEmpError");if(b){b.textContent=m;b.hidden=false}else avisar(m,"error")};
    const lista=typeof getProviderEmployees==="function"?getProviderEmployees():[],e=lista.find(x=>String(x.id)===String(id));if(!e)return erro("Funcionário não encontrado.");
    const eu=e.email===currentUser?.email,nome=$("editEmpName")?.value.trim()||"",email=($("editEmpEmail")?.value||"").trim().toLowerCase();
    if(nome.length<2)return erro("Indique o nome completo.");
    if(email&&email!==String(e.email||"").toLowerCase())return erro("O email é o utilizador de entrada e não pode ser alterado aqui. Crie um funcionário novo com o email certo.");
    const alteracoes={nome,numeroInterno:$("editEmpNo")?.value.trim()||"",telefone:$("editEmpPhone")?.value.trim()||"",licenca:$("editEmpLicense")?.value.trim()||"",veiculo:$("editEmpVehicle")?.value.trim()||""};
    if(!eu){const papel=PAPEL[$("editEmpRole")?.value]||null;if(papel)alteracoes.papel=papel;alteracoes.ativo=($("editEmpStatus")?.value||"active")==="active"}
    const botao=event?.target?.querySelector?.('button[type="submit"]');if(botao){botao.disabled=true;botao.textContent="A guardar…"}
    try{const r=await S().gerirFuncionarios("atualizar",{id,alteracoes});if(r?.aviso)avisar(r.aviso,"warning");
      try{original.call(this,{preventDefault(){}},id)}catch(_){}/* mantém a fotografia e a cópia local iguais */
      try{closeProviderDrawer("platformRecordDrawer")}catch(_){}
      avisar(alteracoes.papel&&PAPEL[e.role]!==alteracoes.papel?`Função de ${nome} alterada para ${typeof providerRoleLabel==="function"?providerRoleLabel($("editEmpRole")?.value):"a nova função"}.`:"Dados do funcionário guardados.","success");
      try{renderProviderEmployees()}catch(_){}}
    catch(err){erro(S()?.mensagem?.(err)||"Não foi possível guardar.")}
    finally{if(botao){botao.disabled=false;botao.textContent="Guardar alterações"}}};
  novo.__servidor=true;window.saveProviderEmployeeEdit=novo}
window.addEventListener("load",instalar);
})();
