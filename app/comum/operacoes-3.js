function renderProposals(){const container=document.getElementById("proposalsList");let list=proposals;if(currentUser.role==="cliente"){list=proposals.filter(p=>p.operationId==="TR-2026-000184")}if(list.length===0){
container.innerHTML="<p>Nenhuma proposta disponível.</p>";return}
container.innerHTML=list.map(p=>`

        <div class="proposal">

            <div class="proposal-header">

                <div>

                    <strong>
                        ${p.provider}
                    </strong>

                    <div>
                        ⭐ ${p.rating}
                    </div>

                </div>

                <div class="price">
                    €${p.price}
                </div>

            </div>

            <br>

            <p>
                Operação:
                <strong>${p.operationId}</strong>
            </p>

            <p>
                Prazo:
                ${p.days} dias
            </p>

            <br>

            <small>
                ${p.message}
            </small>

            ${currentUser.role==="cliente"?`
                <br><br>

                <button
                    class="btn-success"
                    onclick="acceptProposal('${p.id}')"
                >
                    Aceitar proposta
                </button>
                `:""}

        </div>

    `).join("")}
function acceptProposal(id){const proposal=proposals.find(p=>p.id===id);if(!proposal)return;const operation=operations.find(o=>o.id===proposal.operationId);if(!operation)return;operation.status="Confirmado";operation.provider=proposal.provider;
let payment=payments.find(p=>p.operationId===operation.id);if(!payment){payments.push({id:"PAY-"+Math.floor(1e3+Math.random()*9e3),operationId:operation.id,amount:proposal.price,status:"Pendente"})}else{payment.amount=proposal.price}saveAll();
renderEverything();alert("Proposta aceite com sucesso.")}function advanceOperation(id){const operation=operations.find(o=>o.id===id);if(!operation)return;const states=["Recebido","Propostas","Confirmado","Em trânsito","Entregue"];
const index=states.indexOf(operation.status);if(index<states.length-1){operation.status=states[index+1];saveAll();renderEverything()}else{alert("A operação já está concluída.")}}function trackOperation(id){showPage("tracking",
document.querySelector('.menu button[onclick*="tracking"], .menu button[onclick*="OrdersMenu"]'));document.getElementById("trackingCode").value=id;loadTracking()}
function loadTracking(){const input=document.getElementById("trackingCode");const result=document.getElementById("trackingResult");if(!input||!result)return;const code=input.value.trim();
const operation=operations.find(o=>String(o.id).toLowerCase()===code.toLowerCase());if(!operation){result.innerHTML=`<div class="tracking-minimal"><p>❌ Encomenda não encontrada.</p></div>`;return}const stages=["Simulação","Cotação","Aprovação","Recolha",
"Pagamento","Armazenamento","Expedição","Em trânsito","Destino","Disponível","Levantado"];const stageMap={"Simulação":0,"Cotação":1,"Aprovação":2,"Recolha":3,"Pagamento":4,"Armazenamento":5,"Expedição":6,"Em trânsito":7,"Destino":8,"Disponível":9,
"Levantado":10};const currentIndex=stageMap[operation.status]??0;const currentStage=stages[currentIndex];
result.innerHTML=`
        <div class="tracking-minimal">
            <div class="tracking-minimal-head">
                <div><span class="tracking-label">Encomenda</span><strong class="tracking-code">${operation.id}</strong></div>
                <div class="tracking-status-pill">${currentStage}</div>
            </div>
            <div class="tracking-timeline" aria-label="Progresso da encomenda">
                ${stages.map((stage,
index)=>{const completed=index<currentIndex;const current=index===currentIndex;
return`<div class="tracking-mini-step ${completed?"done":""} ${current?"active":""}">
                        <div class="tracking-mini-dot">${completed?"✓":index+1}</div><span>${stage}</span>
                    </div>${index<stages.length-1?`<div class="tracking-mini-line ${index<currentIndex?"done":""}"></div>`:""}`}).join("")}
            </div>
            <div class="tracking-minimal-meta">
                <span><small>Previsão</small><strong>${operation.date||"—"}</strong></span>
                <span><small>Rota</small><strong>${operation.origin||"—"} → ${operation.destination||"—"}</strong></span>
            </div>
        </div>`}
