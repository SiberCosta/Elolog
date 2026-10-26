function renderClientDashboard(){if(!currentUser||currentUser.role!=="cliente")return;const home=document.getElementById("clientDashboardHome");const defaultSearch=document.querySelector(".dashboard-default-search");
const stats=document.getElementById("dashboardStats");const welcome=document.getElementById("dashboardWelcome");const name=document.getElementById("clientHomeName");const list=document.getElementById("clientHomeHistoryList");
const activeList=document.getElementById("clientHomeActiveList");const activeCount=document.getElementById("clientActiveCount");const transitCount=document.getElementById("clientTransitCount");
const completedCount=document.getElementById("clientCompletedCount");if(home)home.hidden=false;if(defaultSearch)defaultSearch.style.display="none";if(stats)stats.style.display="none";if(welcome)welcome.style.display="none";
if(name)name.textContent=currentUser.name||"João Silva";const clientOps=operations.filter(o=>!o.client||o.client===currentUser.name||o.client==="João Silva").sort((a,b)=>String(b.created||b.date||"").localeCompare(String(a.created||a.date||"")));
const finalStatuses=["Disponível","Levantado","Concluída","Concluído","Entregue","Cancelada","Cancelado"];const activeOps=clientOps.filter(o=>!finalStatuses.includes(String(o.status||"Recebido")));
const transitOps=clientOps.filter(o=>String(o.status||"").toLowerCase().includes("trânsito"));const completedOps=clientOps.filter(o=>finalStatuses.includes(String(o.status||"")));if(activeCount)activeCount.textContent=activeOps.length;
if(transitCount)transitCount.textContent=transitOps.length;if(completedCount)completedCount.textContent=completedOps.length;if(activeList){activeList.innerHTML=activeOps.length?activeOps.slice(0,4).map(o=>{const pct=clientDashboardProgress(o.status);
return`<div class="client-active-card">
                <div class="client-active-top"><div><div class="client-active-code">${o.id||"—"}</div><div class="client-active-route">${o.origin||"—"} → ${o.destination||"—"}</div></div><span class="status ${statusClass(o.status)}">${o.status||"Recebido"}</span></div>
                <div class="client-active-date">Data prevista: <strong>${o.date||"—"}</strong></div>
                <div class="client-progress" title="${pct}% do processo"><span style="width:${pct}%"></span></div>
            </div>`}
).join(""):'<div class="client-active-empty">Não existem encomendas ativas neste momento.</div>'}if(list){list.className="client-history-table";list.innerHTML=clientOps.length?clientOps.slice(0,
7).map(o=>`<div class="client-history-row">
            <div><strong>${o.id||"—"}</strong></div>
            <div class="client-history-route">${o.origin||"—"} → ${o.destination||"—"}</div>
            <div class="client-history-date">${o.date||o.created||"—"}</div>
            <div><span class="status ${statusClass(o.status)}">${o.status||"Recebido"}</span></div>
        </div>`).join(""):'<div class="client-home-empty">Ainda não existem encomendas registadas.</div>'}
}function searchClientHomeOrder(){const input=document.getElementById("clientHomeTrackingSearch");const result=document.getElementById("clientHomeSearchResult");const code=input?.value.trim().toUpperCase();if(!result)return;if(!code){
result.innerHTML='<div class="client-home-result-error">Indique o código da encomenda para pesquisar.</div>';return}const operation=operations.find(o=>String(o.id||"").toUpperCase()===code&&(!o.client||o.client===currentUser?.name||o.client==="João Silva"));
if(!operation){result.innerHTML='<div class="client-home-result-error">Encomenda não encontrada no seu histórico.</div>';return}result.innerHTML=`
        <div class="client-home-result client-home-result-card">
            <div>
                <strong>${operation.id}</strong>
                <small>${operation.origin||"—"} → ${operation.destination||"—"} · Previsão: ${operation.date||"—"}</small>
            </div>
            <span class="status ${statusClass(operation.status)}">${operation.status||"Recebido"}</span>
        </div>`}
/* Elolog — edição dos dados de um funcionário (Admin do prestador). Script clássico, carregado depois de equipa-terreno.js. */
function openProviderEmployeeEdit(id){editFoto=void 0;if(!requireProviderPermission("manage_employees"))return;const e=getProviderEmployees().find(x=>String(x.id)===String(id));if(!e)return showPlatformNotice("Funcionário não encontrado.","error");
const v=k=>escapeHtml(e[k]||""),roles=["admin","operador","field_operator","armazem","financeiro"],self=e.email===currentUser?.email;openPlatformRecordDrawer(`Editar · ${e.name}`,
"DADOS DO FUNCIONÁRIO",`<form class="admin-provider-form" onsubmit="saveProviderEmployeeEdit(event,'${e.id}')"><section class="admin-provider-form-section"><div class="admin-provider-form-grid">
    <label>Nome completo<input id="editEmpName" required value="${v("name")}"></label>
    <label>E-mail / utilizador<input id="editEmpEmail" type="email" required value="${v("email")}"></label>
    <label>Número interno<input id="editEmpNo" value="${v("internalNo")}"></label>
    <label>Telefone<input id="editEmpPhone" type="tel" value="${v("phone")}"></label>
    <label>Função<select id="editEmpRole" ${self?'disabled title="Não pode alterar a sua própria função"':""}>${roles.map(r=>`<option value="${r}" ${r===e.role?"selected":""}>${providerRoleLabel(r)}</option>`).join("")}</select></label>
    <label>Estado<select id="editEmpStatus" ${self?"disabled":""}>${[["active",
"Ativo"],["suspended","Suspenso"],["inactive","Inativo"]].map(([k,
t])=>`<option value="${k}" ${(e.status||(e.active?"active":"inactive"))===k?"selected":""}>${t}</option>`).join("")}</select></label>
    <label class="wide">Fotografia de perfil<span class="av-edit"><span id="editEmpAv">${elologFoto.av(e.email,e.name,
"av-grande")}</span><input id="editEmpPhoto" type="file" accept="image/*" onchange="editarFoto(this)"><button type="button" class="employee-action" onclick="editarFoto(null)">Remover</button></span></label>
    <label>Documento / licença<input id="editEmpLicense" value="${v("license")}"></label>
    <label>Viatura habitual<input id="editEmpVehicle" value="${v("usualVehicle")}"></label>
    </div><p class="provider-modal-note">A palavra-passe não é alterada aqui; use «Redefinir palavra-passe». Todas as alterações ficam registadas na auditoria.</p>
    <div id="editEmpError" class="password-recovery-feedback error" hidden></div>
    <div class="provider-modal-actions"><button type="button" class="btn-secondary" onclick="closeProviderDrawer('platformRecordDrawer')">Cancelar</button><button class="btn-primary" type="submit">Guardar alterações</button></div></section></form>`)}
let editFoto;async function editarFoto(i){try{editFoto=i?await elologFoto.reduzir(i.files[0]):"";
document.getElementById("editEmpAv").innerHTML=editFoto?`<span class="av av-grande" style="background-image:url('${editFoto}')"></span>`:`<span class="av av-grande">${escapeHtml((document.getElementById("editEmpName").value||"?").trim().split(/\s+/).slice(0,
2).map(x=>x[0]).join("").toUpperCase())}</span>`}catch(e){showPlatformNotice(e.message,"error");if(i)i.value=""}}function saveProviderEmployeeEdit(event,id){event.preventDefault();if(!requireProviderPermission("manage_employees"))return;
const val=i=>document.getElementById(i),err=m=>{const b=val("editEmpError");b.textContent=m;b.hidden=false},list=getProviderEmployees(),e=list.find(x=>String(x.id)===String(id));if(!e)return err("Funcionário não encontrado.");
const email=val("editEmpEmail").value.trim().toLowerCase(),name=val("editEmpName").value.trim(),self=e.email===currentUser?.email,role=self?e.role:val("editEmpRole").value,status=self?e.status||"active":val("editEmpStatus").value;
if(!name)return err("Indique o nome.");if(!/^\S+@\S+\.\S+$/.test(email))return err("Indique um e-mail válido.");if(list.some(x=>x.id!==e.id&&x.email===email))return err("Já existe um funcionário com este e-mail.");
const admins=list.filter(x=>x.role==="admin"&&x.active&&x.id!==e.id).length;if(e.role==="admin"&&(role!=="admin"||status!=="active")&&!admins)return err("Tem de existir pelo menos um Admin ativo na empresa.");const before={name:e.name,email:e.email,
role:e.role,status:e.status,phone:e.phone,internalNo:e.internalNo,license:e.license,usualVehicle:e.usualVehicle},base=["view_assigned_jobs","update_assigned_jobs","capture_load","register_signature","create_incident"];Object.assign(e,{name,email,role,status,
active:status==="active",phone:val("editEmpPhone").value.trim(),internalNo:val("editEmpNo").value.trim(),license:val("editEmpLicense").value.trim(),usualVehicle:val("editEmpVehicle").value.trim(),updatedAt:new Date().toISOString(),
updatedBy:currentUser?.name||"Administrador da empresa"});if(role!==before.role)e.permissions=role==="field_operator"?base:[];elologFoto.mover(before.email,email);if(editFoto!==void 0)elologFoto.set(email,editFoto);saveProviderEmployees(list);try{
elologPlatform.audit("Funcionário editado",e.id,{before,after:{name,email,role,status}})}catch(x){}closeProviderDrawer("platformRecordDrawer");renderProviderEmployees();showPlatformNotice(`Dados de ${name} atualizados.`,"success")}
