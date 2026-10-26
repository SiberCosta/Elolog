function renderOperations(){const container=document.getElementById("operationsList");if(operations.length===0){container.innerHTML="<p>Nenhuma operação encontrada.</p>";return}let visible=operations;if(currentUser.role==="cliente"){
visible=operations.filter(o=>o.client===currentUser.name||o.client==="João Silva")}
container.innerHTML=visible.map(operation=>`

        <div class="operation">

            <div class="operation-head">

                <div>

                    <div class="operation-code">
                        ${operation.id}
                    </div>

                    <div class="route">
                        ${operation.origin}
                        →
                        ${operation.destination}
                    </div>

                </div>

                <span class="status ${statusClass(operation.status)}">
                    ${operation.status}
                </span>

            </div>

            <div class="operation-info">

                <span>
                    <i class="ic ic-user" aria-hidden="true"></i> ${operation.client}
                </span>

                <span>
                    <i class="ic ic-box" aria-hidden="true"></i> ${operation.cargo}
                </span>

                <span>
                    ⚖️ ${operation.weight||"-"}
                </span>

                <span>
                    <i class="ic ic-calendar" aria-hidden="true"></i> ${operation.date}
                </span>

            </div>

            <div class="operation-actions">

                <button
                    class="btn-primary"
                    onclick="showOperationDetail('${operation.id}')"
                >
                    Ver detalhes
                </button>

                <button
                    class="btn-secondary"
                    onclick="trackOperation('${operation.id}')"
                >
                    Acompanhar
                </button>

                ${currentUser.role==="admin"?`
                    <button
                        class="btn-success"
                        onclick="advanceOperation('${operation.id}')"
                    >
                        Avançar estado
                    </button>
                    `:""}

            </div>

        </div>

    `).join("")}
function showOperationDetail(id){const operation=operations.find(o=>o.id===id);if(!operation)return;const operationProposals=proposals.filter(p=>p.operationId===id);
document.getElementById("detailContent").innerHTML=`

        <div class="operation">

            <div class="operation-head">

                <strong>
                    ${operation.id}
                </strong>

                <span class="status ${statusClass(operation.status)}">
                    ${operation.status}
                </span>

            </div>

            <div class="route">
                ${operation.origin}
                →
                ${operation.destination}
            </div>

            <p>
                <strong>Cliente:</strong>
                ${operation.client}
            </p>

            <br>

            <p>
                <strong>Carga:</strong>
                ${operation.cargo}
            </p>

            <br>

            <p>
                <strong>Peso:</strong>
                ${operation.weight||"-"}
            </p>

            <br>

            <p>
                <strong>Data:</strong>
                ${operation.date}
            </p>

            <br>

            <p>
                <strong>Observações:</strong>
                ${operation.notes||"Sem observações."}
            </p>

        </div>

        <h3 style="margin:25px 0 15px">
            Propostas (${operationProposals.length})
        </h3>

        ${operationProposals.length?operationProposals.map(p=>`

                <div class="proposal">

                    <div class="proposal-header">

                        <strong>
                            ${p.provider}
                        </strong>

                        <span class="price">
                            €${p.price}
                        </span>

                    </div>

                    <p>
                        ${p.days} dias ·
                        <span class="stars">
                            ⭐ ${p.rating}
                        </span>
                    </p>

                    <small>
                        ${p.message}
                    </small>

                </div>

            `).join(""):"<p>Nenhuma proposta.</p>"}

    `;document.getElementById("detailModal").classList.add("active")}
