/* Elolog — módulo 09/15: Apoio ao cliente, perfil e acompanhamento de encomendas
   Script clássico: partilha o âmbito global com os restantes módulos. Carregar pela ordem numérica. */
function updateSupportSubsubject(){const subject=document.getElementById("supportSubject");const wrap=document.getElementById("supportSubsubjectWrap");const input=document.getElementById("supportSubsubject");
const isOther=subject&&subject.value.trim().toLowerCase()==="outro";if(wrap)wrap.style.display=isOther?"block":"none";if(input){input.required=isOther;if(!isOther)input.value=""}}function sendClientSupport(){
const subject=document.getElementById("supportSubject");const subsubject=document.getElementById("supportSubsubject");const message=document.getElementById("supportMessage");const feedback=document.getElementById("supportFeedback");
if(subject&&subject.value.trim().toLowerCase()==="outro"&&(!subsubject||!subsubject.value.trim())){alert("Indique o subassunto.");if(subsubject)subsubject.focus();return}if(!message||!message.value.trim()){alert("Escreva a sua mensagem antes de enviar.");
if(message)message.focus();return}const tickets=getAdminSupportTickets();const next=Math.max(104,...tickets.map(ticket2=>Number(String(ticket2.id||"").replace(/\D/g,""))||0))+1;const subjectLabel=subject?.value||"Apoio ao cliente";const ticket={id:"SUP-"+next,
audience:"Cliente",requester:currentUser?.name||"Cliente",contact:currentUser?.email||"",subject:subjectLabel+(subsubject?.value?` · ${subsubject.value.trim()}`:""),category:"Apoio ao cliente",priority:"Normal",status:"Aberto",description:message.value.trim(),
assignedTo:"Equipa de apoio",createdAt:new Date().toISOString(),createdBy:currentUser?.name||"Cliente"};tickets.unshift(ticket);localStorage.setItem("elolog_admin_support_tickets",JSON.stringify(tickets));
if(typeof addAdminRequestNotification==="function")addAdminRequestNotification({title:"Novo pedido de cliente",message:`${ticket.requester}: ${ticket.subject}.`,targetPage:"adminSupport",reference:ticket.id,actor:ticket.requester});if(feedback){
feedback.style.display="block";feedback.style.padding="12px 14px";feedback.style.borderRadius="10px";feedback.style.background="#f0fdf4";feedback.style.color="#166534";
feedback.textContent="Pedido enviado. A equipa de Apoio Cliente irá analisar a sua solicitação."}message.value="";if(subsubject)subsubject.value="";updateSupportSubsubject()}document.addEventListener("DOMContentLoaded",()=>{
const subject=document.getElementById("supportSubject");if(subject){subject.addEventListener("change",updateSupportSubsubject);updateSupportSubsubject()}});function renderClientProfile(){if(!currentUser||currentUser.role!=="cliente")return;
document.getElementById("clientProfileName").textContent=currentUser.name||"João Silva";document.getElementById("clientProfileEmail").textContent=currentUser.email||"—";const profile=currentUser.profile||{};
document.getElementById("clientProfileNif").textContent=profile.nif||"—";document.getElementById("clientProfilePhone").textContent=profile.phone||"—";document.getElementById("clientProfileAddress").textContent=profile.address||"—"}
function renderClientTracking(){if(!currentUser||currentUser.role!=="cliente")return;window.toggleClientOrderDetails=function(target){const card=target?.classList?.contains("client-order-card")?target:target?.closest?.(".client-order-card");if(!card)return;
card.classList.toggle("expanded");const expanded=card.classList.contains("expanded");const button=card.querySelector(".client-order-toggle");if(button){button.textContent=expanded?"Ocultar detalhes":"Ver detalhes";button.setAttribute("aria-expanded",
expanded?"true":"false")}};window.clientOrderStageIndex=function(order){const stages=["Simulação","Cotação","Aprovação","Recolha","Pagamento","Armazenamento","Expedição","Em trânsito","Destino","Disponível","Levantado"];
const raw=String(order?.stage||order?.status||"Simulação").trim().toLowerCase();const aliases={"recebido":"Simulação","propostas":"Cotação","proposta":"Cotação","aprovado":"Aprovação","aprovada":"Aprovação","recolhido":"Recolha","pago":"Pagamento",
"armazenado":"Armazenamento","expedido":"Expedição","destino":"Destino","disponivel":"Disponível","disponível":"Disponível","levantado":"Levantado","entregue":"Levantado","concluída":"Levantado","concluída":"Levantado","concluido":"Levantado",
"concluído":"Levantado"};const normalized=aliases[raw]||order?.stage||order?.status||"Simulação";const idx=stages.findIndex(x=>x.toLowerCase()===String(normalized).toLowerCase());return idx<0?0:idx};window.renderClientOrderProgress=function(order){
const stages=["Simulação","Cotação","Aprovação","Recolha","Pagamento","Armazenamento","Expedição","Em trânsito","Destino","Disponível","Levantado"];const current=clientOrderStageIndex(order);return stages.map((stage,i)=>{
const state=i<current?"done":i===current?"current":"";return`<div class="client-order-stage ${state}"><span class="client-order-stage-dot">${i+1}</span><span class="client-order-stage-label">${stage}</span></div>`}).join("")};
const clientOps=operations.filter(o=>!o.client||o.client===currentUser.name||o.client==="João Silva").sort((a,b)=>String(b.createdAt||b.created||b.date||"").localeCompare(String(a.createdAt||a.created||a.date||"")));const estadosFinais=["levantado",
"concluída","concluido","concluído","entregue","cancelada","cancelado"];const activeOps=clientOps.filter(o=>!estadosFinais.includes(String(o.status||o.stage||"").trim().toLowerCase()));const orders=document.getElementById("clientOrdersList");
const history=document.getElementById("clientHistoryList");if(orders){orders.innerHTML=activeOps.length?activeOps.map((o,
index)=>`
                <article class="client-order-card" data-order-index="${index}">
                    <div class="client-order-summary client-order-summary-clickable" onclick="toggleClientOrderDetails(this.closest('.client-order-card'))" role="button" tabindex="0" onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();toggleClientOrderDetails(this.closest('.client-order-card'))}">
                        <div class="client-order-summary-item">
                            <small>Código da encomenda</small>
                            <strong>${o.id||"—"}</strong>
                        </div>
                        <div class="client-order-summary-item">
                            <small>Estado</small>
                            <strong>${o.status||"Recebido"}</strong>
                        </div>
                        <div class="client-order-summary-item">
                            <small>Data prevista</small>
                            <strong>${o.date||"—"}</strong>
                        </div>
                        <div class="client-order-summary-action">
                            <button type="button" class="client-order-toggle" onclick="event.stopPropagation(); toggleClientOrderDetails(this.closest('.client-order-card'))">Ver detalhes</button>
                        </div>
                    </div>

                    <div class="client-order-details-panel">
                        <div class="client-order-dynamic-status">
                            <div class="client-order-status-head">
                                <div>
                                    <small>Estado da encomenda</small>
                                    <strong>${o.status||"Recebido"}</strong>
                                </div>
                                <div class="client-order-created-by">${o.createdBy==="prestador"||o.provider?"Criada/atualizada pelo prestador":"Criada pelo cliente"}</div>
                            </div>
                            <div class="client-order-progress-track">
                                ${renderClientOrderProgress(o)}
                            </div>
                        </div>

                        <div class="client-order-route">
                            <div class="client-order-place">
                                <small>Origem</small>
                                <strong>${o.origin||"—"}</strong>
                            </div>
                            <div class="client-order-arrow">→</div>
                            <div class="client-order-place">
                                <small>Destino</small>
                                <strong>${o.destination||"—"}</strong>
                            </div>
                        </div>

                        <div class="client-order-details">
                            <div class="client-order-detail">
                                <small>Tipo de carga</small>
                                <strong>${o.cargo||"—"}</strong>
                            </div>
                            <div class="client-order-detail">
                                <small>Peso / volume</small>
                                <strong>${o.weight||"—"}</strong>
                            </div>
                            <div class="client-order-detail">
                                <small>Data de criação</small>
                                <strong>${o.created||"—"}</strong>
                            </div>
                            <div class="client-order-detail">
                                <small>Transportador</small>
                                <strong>${o.provider||"Por atribuir"}</strong>
                            </div>
                        </div>

                        <div class="client-order-goods">
                            <div class="client-order-goods-title"><i class="ic ic-box" aria-hidden="true"></i> Bens envolvidos na carga</div>
                            <div class="client-order-goods-text">
                                ${o.goods?`<ul class="client-order-goods-list">${String(o.goods).split(/[;,\n]+/).map(item=>item.trim()).filter(Boolean).map(item=>`<li>${item}</li>`).join("")}</ul>`:"Não foram indicados bens específicos para esta encomenda."}
                            </div>
                        </div>

                        <div class="client-order-recipient">
                            <div class="client-order-goods-title"><i class="ic ic-user" aria-hidden="true"></i> Destinatário</div>
                            <div class="client-order-details">
                                <div class="client-order-detail">
                                    <small>Nome / Empresa</small>
                                    <strong>${o.recipient?.name||o.recipient?.nome||"—"}</strong>
                                </div>
                                <div class="client-order-detail">
                                    <small>NIF</small>
                                    <strong>${o.recipient?.nif||"—"}</strong>
                                </div>
                                <div class="client-order-detail">
                                    <small>Telefone</small>
                                    <strong>${o.recipient?.phone||o.recipient?.telefone||"—"}</strong>
                                </div>
                                <div class="client-order-detail">
                                    <small>E-mail</small>
                                    <strong>${o.recipient?.email||"—"}</strong>
                                </div>
                                <div class="client-order-detail" style="grid-column:1/-1">
                                    <small>Morada de entrega</small>
                                    <strong>${o.recipient?.address||o.recipient?.morada||"—"}</strong>
                                </div>
                            </div>
                        </div>

                        <div class="client-order-notes">
                            <strong>Descrição / observações:</strong>
                            ${o.notes||"Sem observações adicionais registadas."}
                        </div>
                        ${o.anomalyPhotos?.length?`<div class="client-order-goods"><div class="client-order-goods-title"><i class="ic ic-camera" aria-hidden="true"></i> Provas de anomalia</div><div class="client-anomaly-preview">${o.anomalyPhotos.map(f=>`<figure class="client-anomaly-photo"><img src="${f.data}" alt="Prova fotográfica de anomalia"></figure>`).join("")}</div></div>`:""}
                    </div>
                </article>
            `).join(""):'<p style="color:#64748b">Não existem envios ativos neste momento.</p>'}
if(history){history.className="client-history-table";
history.innerHTML=clientOps.length?`<div class="client-history-table-head"><span>Código</span><span>Rota</span><span>Data</span><span>Estado</span></div>`+clientOps.map(o=>`
                <div class="client-history-row">
                    <div><strong>${o.id||"—"}</strong></div>
                    <div class="client-history-route">${o.origin||"—"} → ${o.destination||"—"}</div>
                    <div class="client-history-date">${o.date||o.created||"—"}</div>
                    <div><span class="status ${statusClass(o.status)}">${o.status||o.stage||"Recebido"}</span></div>
                </div>
            `).join(""):'<p style="color:#64748b">Ainda não existe histórico.</p>'}
}function clientDashboardProgress(status){const s=String(status||"Recebido").toLowerCase();const map=[["levantado",100],["disponível",95],["entregue",100],["concluída",100],["concluído",100],["destino",90],["em trânsito",75],["expedição",65],["armazenamento",
55],["pagamento",45],["recolha",35],["aprovação",25],["cotação",15],["simulação",8]];const hit=map.find(([k])=>s.includes(k));return hit?hit[1]:20}
