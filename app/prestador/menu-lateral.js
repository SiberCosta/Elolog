/* Elolog — menu lateral do prestador (v58), igual ao do cliente e da administração: 12 áreas, submenus recolhíveis, só a secção ativa realçada.
   Substitui a barra de navegação superior. Cada entrada chama uma função que já existe; as permissões da função do funcionário decidem o que aparece.
   Formato de cada entrada: [texto, ação, página, permissão (ou ""), só administrador]. Carregar depois de permissoes.js e de acesso-por-funcao.js. */
(function(){
  const I=n=>`<i class="ic ic-${n}" aria-hidden="true"></i>`;
  const AREAS=[
    ["dashboard","Dashboard","chart",[["Dashboard","showPage('dashboard',this)","dashboard",""]]],
    ["op","Operações","box",[["Quadro de encomendas","showProviderPage('providerBoard',this)","providerBoard","view_loads"],["Criar encomenda","openProviderDirectMode('order',this)","providerDirectSimulation","create_order"],
      ["Simular serviço","openProviderDirectMode('simulation',this)","providerDirectSimulation","create_order"],["Atualizar estado","showProviderPage('providerOrder',this)","providerOrder","change_status"],
      ["Aprovar pedidos","showProviderPage('providerAprovacao',this)","providerAprovacao","approve"],["Programar recolhas","showProviderPage('providerRecolha',this)","providerRecolha","view_loads"],
      ["Ocorrências","showProviderFieldPage('incidents',this)","providerFieldTeam","field_work"],["Histórico","showProviderPage('providerOrderHistory',this)","providerOrderHistory","view_loads"],
      ["Automação","showProviderPage('providerAutomation',this)","providerAutomation","view_loads"]]],
    ["cli","Clientes","users",[["Lista de clientes","showProviderPage('providerClientList',this)","providerClientList","view_clients"],["Ficha do cliente","showProviderPage('providerClientProfile',this)","providerClientProfile","view_clients"]]],
    ["prop","Propostas","tag",[["Pedidos recebidos","showProviderProposalTab('new',this)","providerCotacao","create_quote"],["Criar cotação","showProviderProposalTab('create',this)","providerCotacao","create_quote"],
      ["Enviadas","showProviderProposalTab('sent',this)","providerCotacao","create_quote"],["Aceites","showProviderProposalTab('accepted',this)","providerCotacao","create_quote"],["Recusadas","showProviderProposalTab('rejected',this)","providerCotacao","create_quote"]]],
    ["arm","Armazém","warehouse",[["Receção e localização","showProviderPage('providerArmazenamento',this)","providerArmazenamento","view_loads"],["Expedição","showProviderPage('providerExpedicao',this)","providerExpedicao","view_loads"],
      ["Manifestos de carga","showProviderPage('providerManifestos',this)","providerManifestos","view_manifests"],["Calendário marítimo","showProviderPage('providerMaritimeCalendar',this)","providerMaritimeCalendar","view_loads"],
      ["Mapa marítimo","showProviderPage('providerMapa',this)","providerMapa","view_loads"],["Em trânsito","showProviderPage('providerTransito',this)","providerTransito","view_loads"],
      ["No destino","showProviderPage('providerDestino',this)","providerDestino","view_loads"],["Disponível","showProviderPage('providerDisponivel',this)","providerDisponivel","view_loads"],
      ["Saídas e levantamentos","showProviderPage('providerLevantamento',this)","providerLevantamento","view_loads"],["Navios em tempo real","elologNavios.abrir(this)","","view_loads"]]],
    ["eq","Equipa e transportes","truck",[["Agenda de serviços","showProviderFieldPage('planning',this)","providerFieldTeam","field_work"],["Painel do terreno","showProviderFieldPage('dashboard',this)","providerFieldTeam","field_work"],
      ["Motoristas e operadores","showProviderFieldPage('operators',this)","providerFieldTeam","field_work"],["Viaturas","showProviderFieldPage('vehicles',this)","providerFieldTeam","field_work"],
      ["Recolhas","showProviderFieldPage('pickups',this)","providerFieldTeam","field_work"],["Entregas","showProviderFieldPage('deliveries',this)","providerFieldTeam","field_work"]]],
    ["fin","Financeiro","euro",[["Resumo","showProviderFinanceTab('overview',this)","providerFinanceiro","manage_payments"],["Tabela de preços","showProviderFinanceTab('prices',this)","providerFinanceiro","manage_payments"],
      ["Faturação","showProviderFinanceTab('billing',this)","providerFinanceiro","manage_payments"],["Recebimentos","showProviderFinanceTab('receipts',this)","providerFinanceiro","manage_payments"],
      ["Movimentos e reconciliação","showProviderFinanceTab('history',this)","providerFinanceiro","manage_payments"],["Registar fatura certificada","elologFaturas.abrir(this)","","manage_payments"]]],
    ["doc","Documentos","file",[["Documentos","showProviderPage('providerDocumentos',this)","providerDocumentos","download_manifest"]]],
    ["rel","Relatórios","clipboard",[["Relatórios","showProviderPage('providerReports',this)","providerReports","view_loads"]]],
    ["apoio","Apoio ao cliente","headset",[["Pedidos de apoio","showProviderPage('providerSupport',this)","providerSupport","view_clients"],["Reclamações","showProviderPage('providerComplaints',this)","providerComplaints","view_clients"]]],
    ["func","Funcionários e acessos","shield",[["Funcionários e funções","showProviderPage('providerEmployees',this)","providerEmployees","manage_employees",1],["Segurança e histórico","showProviderPage('providerSecurity',this)","providerSecurity",""]]],
    ["emp","Empresa e configurações","settings",[["Dados da empresa","showProviderPage('providerSettings',this)","providerSettings","settings",1],["Subscrição","showProviderPage('providerSubscription',this)","providerSubscription","",1],
      ["Pagamentos online","elologPagamentos.config(this)","","settings",1],
      ["O meu perfil","showProviderPage('providerPerfil',this)","providerPerfil",""]]]];
  const CAMPO=[["Dashboard","dashboard","chart"],["Recolhas","pickups","truck"],["Entregas","deliveries","pin"],["Rota","route","map"],["Pagamentos","payments","euro"],["Ocorrências","incidents","warning"],["Histórico","history","clock"],["O meu perfil","profile","user"]];
  const pode=(perm,soAdmin)=>{try{const f=providerFunction();if(soAdmin&&f!=="admin")return false;return!perm||f==="admin"||hasProviderPermission(perm)}catch(e){return true}};
  const item=([t,ir,pg])=>`<button type="button" data-pagina="${pg}" onclick="${ir}">${t}</button>`;
  window.elologGrupoPrestador=function(id,b){const g=document.getElementById(id);if(!g)return;const abre=!g.classList.contains("open");
    document.querySelectorAll("#providerMenuStructure .provider-submenu").forEach(s=>s.classList.toggle("open",s===g&&abre));
    document.querySelectorAll("#providerMenuStructure .provider-menu-main").forEach(x=>x.setAttribute("aria-expanded",String(x===b&&abre)))};
  function construir(){const box=document.getElementById("providerMenuStructure");if(!box||typeof currentUser==="undefined"||currentUser?.role!=="prestador")return;
    let html="";const campo=(()=>{try{return providerFunction()==="field_operator"}catch(e){return false}})();
    if(campo)html=CAMPO.map(([t,k,ic])=>`<button type="button" data-pagina="providerFieldTeam" onclick="showProviderFieldPage('${k}',this)"><span class="mi-l">${I(ic)}${t}</span></button>`).join("");
    else html=AREAS.map(([id,nome,ic,its])=>{const ok=its.filter(x=>pode(x[3],x[4]));if(!ok.length)return"";
      if(ok.length===1)return`<button type="button" data-pagina="${ok[0][2]}" onclick="${ok[0][1]}"><span class="mi-l">${I(ic)}${ok[0][0]}</span></button>`;
      return`<div class="provider-menu-group"><button type="button" class="provider-menu-main" aria-expanded="false" onclick="elologGrupoPrestador('pm-${id}',this)"><span class="mi-l">${I(ic)}${nome}</span><span>⌄</span></button><div id="pm-${id}" class="provider-submenu">${ok.map(item).join("")}</div></div>`}).join("");
    if(box.dataset.feito===html)return;box.dataset.feito=html;box.innerHTML=html;box.classList.add("admin-menu-structure","prov-menu");box.style.display="block";
    const dash=document.getElementById("menuDashboard");if(dash)dash.style.display="none";document.body.classList.add("prov-lateral")}
  const orig=window.applyProviderPermissions;if(typeof orig==="function")window.applyProviderPermissions=function(){const r=orig.apply(this,arguments);try{construir()}catch(e){}return r};
  const conf=window.configureRole;if(typeof conf==="function")window.configureRole=function(){const r=conf.apply(this,arguments);if(currentUser?.role!=="prestador")document.body.classList.remove("prov-lateral");else try{construir()}catch(e){}return r};
})();
