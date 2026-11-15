/* Dashboard do prestador (v135), com o mesmo desenho do painel do cliente: próximo passo com o percurso animado e criação rápida,
   indicadores com ícones de cor, encomendas em curso com o Fluxo Vivo, ações rápidas em mosaico, o que precisa de ação, alertas,
   pagamentos por receber e pesquisa. Blocos por função (administrador, operador, terreno, armazém, financeiro), personalizáveis e
   atualizados sozinhos (Painel.vigiar). Só mostra dados reais da empresa. */
(function(){const{ETAPAS,etapa}=EtapasPrestador,{pendentes,idade,abrir,botao,linhas,rota}=FilaPrestador,$=id=>document.getElementById(id);
const PADRAO={admin:["proximo","kpis","curso","atalhos","fila","alertas","pagamentos","historico"],operador:["proximo","kpis","curso","atalhos","fila","etapas"],
  field_operator:["recolhas","fila"],armazem:["proximo","etapas","curso","historico"],financeiro:["kpis","pagamentos","alertas","historico"]};
const FUNCOES={admin:"Administrador",operador:"Operador",field_operator:"Operador de terreno",armazem:"Armazém",financeiro:"Financeiro"};
const eur=v=>Number(v||0).toLocaleString("pt-PT",{style:"currency",currency:"EUR"}),esc=v=>escapeHtml(String(v??""));
const ops=()=>providerCompanyOperations(),funcao=()=>currentUser?.providerFunction||"admin";
const pode=k=>{try{return funcao()==="admin"||hasProviderPermission(k)}catch(e){return true}};
const porReceber=()=>payments.filter(p=>p.status!=="Pago"&&ops().some(o=>o.id===p.operationId));
const FECHADA=/levantad|entregue|conclu|cancel|rejeit|anulad/i,quando=x=>new Date(x.createdAt||x.created||x.date||0);
const novos=()=>{try{return providerDirectedSimulations({onlyNew:true}).length}catch(e){return 0}};
const SVG=(d,c="")=>`<svg class="${c}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
const IC={pedido:'<path d="M5 4h14v16l-3-2-2 2-2-2-2 2-2-2-3 2z"/><path d="M9 9h6M9 13h4"/>',check:'<circle cx="12" cy="12" r="9"/><path d="m8 12.5 2.8 2.8L16.5 9.5"/>',
  truck:'<path d="M3 6h11v10H3zM14 10h4l3 3v3h-7z"/><circle cx="7" cy="17.5" r="1.8"/><circle cx="17" cy="17.5" r="1.8"/>',card:'<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="M3 10h18M7 15h4"/>',
  plus:'<path d="M12 5v14M5 12h14"/>',calc:'<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 7h8M8 11h2M12 11h2M16 11h0M8 15h2M12 15h2"/>',box:'<path d="M21 8 12 3 3 8v8l9 5 9-5z"/><path d="m3 8 9 5 9-5M12 13v8"/>',
  doc:'<path d="M7 3h7l5 5v13H7z"/><path d="M14 3v5h5M10 13h6M10 17h4"/>',cal:'<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',navio:'<path d="M3 15h18l-2.5 4.5h-13z"/><path d="M6 15V9h12v6M10 9V5h4v4"/>'};
const MAPA=`<svg class="cn-mapa" viewBox="0 0 460 220" aria-hidden="true"><defs><pattern id="pnp" width="12" height="12" patternUnits="userSpaceOnUse"><circle cx="2" cy="2" r="1.3"/></pattern><radialGradient id="png" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#3FAE84" stop-opacity=".45"/><stop offset="1" stop-color="#3FAE84" stop-opacity="0"/></radialGradient></defs>
<rect class="cn-pontos" width="460" height="220" fill="url(#pnp)"/><ellipse cx="290" cy="110" rx="150" ry="80" fill="url(#png)"/><path id="pnr1" class="cn-rota" d="M60 150 C 150 40, 260 30, 380 70"/><path id="pnr2" class="cn-rota" d="M60 150 C 170 190, 280 170, 330 140"/><path id="pnr3" class="cn-rota" d="M330 140 C 370 110, 400 90, 425 50"/>
${[[60,150],[380,70],[330,140],[425,50]].map(([x,y],i)=>`<circle class="cn-no" cx="${x}" cy="${y}" r="5"/><circle class="cn-onda" cx="${x}" cy="${y}" r="5" style="animation-delay:${i*.7}s"/>`).join("")}
${["pnr1","pnr2","pnr3"].map((r,i)=>`<circle class="cn-carga" r="3.5"><animateMotion dur="${5+i}s" begin="${i*.8}s" repeatCount="indefinite"><mpath href="#${r}"/></animateMotion></circle>`).join("")}</svg>`;

/* próximo passo: o assunto mais urgente da empresa, por esta ordem */
function proximo(){const o=ops(),n=k=>o.filter(x=>etapa(x)===k).length,nv=novos(),apr=n("Aprovação"),rec=n("Recolha"),rl=porReceber(),atr=o.filter(x=>etapa(x)==="Aprovação"&&Date.now()-quando(x)>2*864e5).length;
  const p=nv&&pode("create_quote")?{t:`${nv} ${nv===1?"pedido espera":"pedidos esperam"} pela sua proposta`,d:"Os clientes recebem a resposta logo que a enviar. Quanto mais cedo, maior a hipótese de fechar.",cta:"Responder aos pedidos",ir:"showProviderProposalTab('new')"}
    :apr&&pode("approve")?{t:`${apr} ${apr===1?"encomenda espera":"encomendas esperam"} pela sua aprovação`,d:atr?`${atr} ${atr===1?"está parada":"estão paradas"} há mais de 2 dias.`:"Confirme os dados e encaminhe para agendamento.",cta:"Aprovar pedidos",ir:"showProviderPage('providerAprovacao')",urg:atr>0}
    :rec?{t:`${rec} ${rec===1?"recolha programada":"recolhas programadas"}`,d:"Atribua o motorista e a viatura, e acompanhe ao vivo.",cta:"Programar recolhas",ir:"showProviderPage('providerRecolha')"}
    :rl.length&&pode("manage_payments")?{t:`${eur(rl.reduce((s,x)=>s+Number(x.amount||0),0))} por receber`,d:`${rl.length} ${rl.length===1?"pagamento pendente":"pagamentos pendentes"}. Confirme os que já entraram.`,cta:"Ver recebimentos",ir:"showProviderFinanceTab('receipts')"}
    :{t:"Tudo em dia. Qual é a próxima carga?",d:"Indique a origem e o destino para criar a encomenda já com o preço calculado pelas suas tarifas.",cta:"",ir:""};
  return`<section class="client-next-step cn-v2"><div class="cn-texto"><span>Próximo passo</span><h2>${esc(p.t)}</h2><p>${esc(p.d)}</p>${p.cta?`<button type="button" class="${p.urg?"bt-ctx bt-urgente":"btn-primary"}" onclick="${p.ir}">${p.cta}</button>`:""}${pode("create_order")?rapida(!!p.cta):""}</div>${MAPA}</section>`}
const rapida=outro=>`<form class="sim-rapida" onsubmit="return elologPainelPrestador.criar(this)" aria-label="Criar encomenda rápida">${outro?"<b>Criar outra encomenda</b>":""}<label><span>Origem</span><input name="o" placeholder="Ex.: Lisboa" autocomplete="address-level2" required></label><label><span>Destino</span><input name="d" placeholder="Ex.: São Tomé" autocomplete="off" required></label><button type="submit" class="btn-primary">Criar encomenda</button></form>`;
function criar(f){const v=k=>f.elements[k].value.trim();openProviderDirectMode("order");setTimeout(()=>{const po=(id,x)=>{const c=$(id);if(c&&x){c.value=x;c.dispatchEvent(new Event("input",{bubbles:true}));c.dispatchEvent(new Event("change",{bubbles:true}))}};
  po("providerDirectOrigin",v("o"));po("providerDirectDestination",v("d"));$("providerDirectClient")?.focus()},250);return false}

/* indicadores */
function serie(){const h=new Date,m=[];for(let i=5;i>=0;i--){const d=new Date(h.getFullYear(),h.getMonth()-i,1);m.push(d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0"))}
  const c=m.map(k=>ops().filter(o=>{const d=quando(o);return!isNaN(d)&&(d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0"))===k}).length),max=Math.max(1,...c);
  return`<span class="ck-barras" title="Encomendas nos últimos 6 meses">${c.map(v=>`<i style="height:${Math.max(8,Math.round(v/max*100))}%"></i>`).join("")}</span>`}
const kpi=(cor,i,t,v,s,ir,extra="")=>`<button type="button" class="pw-kpi ck ck-${cor}" onclick="${ir}"><span class="ck-ic">${SVG(IC[i])}</span><span class="ck-txt"><small>${t}</small><strong>${v}</strong><em>${s}</em></span>${extra}</button>`;
function kpis(){const o=ops(),n=k=>o.filter(x=>etapa(x)===k).length,nv=novos(),tr=n("Em trânsito"),rl=porReceber(),tot=payments.filter(p=>o.some(x=>x.id===p.operationId)).length,pago=tot?Math.round((tot-rl.length)/tot*100):100;
  return`<div class="pw-kpis ck-grelha">${kpi("azul","pedido","Novos pedidos",nv,"Aguardam proposta","showProviderProposalTab('new')",serie())}${kpi("ambar","check","Por aprovar",n("Aprovação"),"Confirmar e encaminhar","showProviderPage('providerAprovacao')",n("Aprovação")?`<b class="ck-selo">${n("Aprovação")}</b>`:"")}
    ${kpi("verde","navio","Em trânsito",tr,"A caminho do destino","showProviderPage('providerTransito')")}${kpi("vermelho","card","Por receber",eur(rl.reduce((s,x)=>s+Number(x.amount||0),0)),`${rl.length} ${rl.length===1?"pagamento":"pagamentos"}`,"showProviderFinanceTab('receipts')",`<span class="ck-progresso" title="${pago}% recebido"><i style="width:${pago}%"></i></span>`)}</div>`}

/* encomendas em curso, as que precisam de atenção primeiro */
function curso(){const F=window.elologFluxo,R={erro:0,aviso:1,ok:2,neutro:3},l=ops().filter(x=>!FECHADA.test(x.status||x.stage||"")).map(x=>({x,s:F?F.saude(x,F.indice(x)):{k:"ok"}})).sort((a,b)=>R[a.s.k]-R[b.s.k]||quando(b.x)-quando(a.x));
  if(!l.length)return`<div class="ca-vazio"><span>${SVG(IC.box)}</span><div><b>Sem encomendas em curso</b></div>${pode("create_order")?`<button type="button" class="btn-secondary" onclick="openProviderDirectMode('order')">Criar encomenda</button>`:""}</div>`;
  return`<div class="ca-lista">${l.slice(0,5).map(({x})=>`<div class="ca-linha" role="button" tabindex="0" onclick="${abrir(esc(x.id||""))}" onkeydown="if(event.key==='Enter')this.click()"><div class="ca-id"><span class="ca-modo">${SVG(IC.navio)}</span><div><b>${esc(x.id||"—")}</b><small>${esc(x.client||"Cliente")}, ${esc(rota(x))}</small></div></div>
    ${F?F.compacto(x,"prestador"):""}<div class="ca-estado"><span class="pf-pill">${esc(etapa(x))}</span><small>${esc(x.date?"Previsão "+x.date:"")}</small></div></div>`).join("")}</div>`}

/* ações rápidas: só as que a função do funcionário pode usar */
const tile=(i,t,s,ir)=>`<button type="button" class="cr-tile" onclick="${ir}"><span class="cr-ic">${SVG(IC[i])}</span><span class="cr-txt"><b>${t}</b><small>${s}</small></span>${SVG('<path d="m9 6 6 6-6 6"/>',"cr-seta")}</button>`;
const ATALHOS=[["create_order","plus","Criar encomenda","Registo direto com preço","openProviderDirectMode('order')"],["create_order","calc","Simular encomenda","Calcular antes de criar","openProviderDirectMode('simulation')"],
  ["approve","check","Aprovar pedidos","Confirmar e encaminhar","showProviderPage('providerAprovacao')"],["view_loads","truck","Programar recolhas","Motorista e viatura","showProviderPage('providerRecolha')"],
  ["manage_payments","card","Recebimentos","Confirmar pagamentos","showProviderFinanceTab('receipts')"],["view_loads","doc","Centro documental","Guias e comprovativos","elologCentroDoc.abrir()"]];
const atalhos=()=>`<div class="cr-lista">${ATALHOS.filter(a=>pode(a[0])).map(a=>tile(a[1],a[2],a[3],a[4])).join("")}</div>`;

function alertas(){const o=ops(),q=pendentes(),atr=q.filter(x=>x.data&&Date.now()-new Date(x.data)>2*864e5).length,apr=o.filter(x=>etapa(x)==="Aprovação").length,nv=novos(),rl=porReceber();
  let oc=0;try{oc=getFieldJobs().reduce((s,j)=>s+(j.incidents||[]).filter(x=>x.status!=="Resolvida").length,0)}catch(e){}
  const l=[[atr,"danger","Encomendas paradas",`${atr} há mais de 2 dias à espera`,"abrirQuadro()"],[apr,"attention","Aprovações em espera",`${apr} por aprovar`,"showProviderPage('providerAprovacao')"],
    [nv,"attention","Pedidos sem resposta",`${nv} pedido(s) dirigidos à empresa`,"showProviderProposalTab('new')"],[rl.length,"attention","Pagamentos por receber",`${rl.length} pagamento(s)`,"showProviderFinanceTab('receipts')"],
    [oc,"danger","Ocorrências abertas",`${oc} no terreno`,"showProviderFieldPage('incidents')"]].filter(x=>x[0]);
  return l.length?`<div class="field-board-list">${l.map(([,c,t,s,ir])=>`<button class="field-board-item pd-alerta ${c}" onclick="${ir}"><span class="pd-ponto"></span><span><strong>${t}</strong><em>${s}</em></span><b>›</b></button>`).join("")}</div>`:'<p class="pf-vazio">Sem alertas. Está tudo a correr como previsto.</p>'}

const dia=d=>{const x=new Date(d);return isNaN(x)?"":x.toISOString().slice(0,10)};
function recolhas(){const eu=typeof fieldCurrentOperator==="function"?fieldCurrentOperator():null,hoje=dia(Date.now());const r=eu?getFieldJobs().filter(j=>j.type==="Recolha"&&j.operatorId===eu.id&&dia(j.scheduledAt)===hoje&&!["Concluída","Concluída com ocorrência","Cancelada"].includes(j.status)):[];
  return r.length?linhas(["Hora","Operação","Recolher em","Cliente","Estado",""],r.map(j=>{const od=fieldJobOperation(j);return`<tr><td><b>${j.scheduledAt?new Date(j.scheduledAt).toLocaleTimeString("pt-PT",{hour:"2-digit",minute:"2-digit"}):"—"}</b></td><td>${esc(j.code||j.operationId||"—")}</td><td>${esc(od?.pickupAddress||od?.origin||"—")}</td><td>${esc(od?.client||"—")}</td><td><span class="pf-pill">${esc(j.status||"Por iniciar")}</span></td><td>${botao("Abrir",`openFieldTask('${esc(j.id)}')`)}</td></tr>`}).join("")):'<p class="pf-vazio">Sem recolhas atribuídas para hoje.</p>'}
const ICE={"Aprovação":"clipboard","Agendamento":"calendar","Recolha":"truck","Armazém":"warehouse","Expedição":"box","Em trânsito":"ship","No destino":"pin","Disponível":"bell","Levantada":"user","Entregue":"check"};
function etapas(){const o=ops(),pl=ETAPAS.map(([,e])=>o.filter(x=>etapa(x)===e).length),max=Math.max(1,...pl);return`<ol class="ct-fluxo ct-fluxo10">${ETAPAS.map(([,e],i)=>`<li class="ct-etapa ${e==="Entregue"?"fim":""} ${pl[i]?"":"pa-zero"}" style="--i:${i}" role="link" tabindex="0" title="${e}: ${pl[i]}, abrir o quadro" onclick="abrirQuadro('${e}')" onkeydown="if(event.key==='Enter')abrirQuadro('${e}')"><span class="ct-bola"><i class="ic ic-${ICE[e]||"box"}" aria-hidden="true"></i></span><b>${e}</b><strong class="pa-etapa-n">${pl[i]}</strong><span class="ct-barra"><i style="width:${pl[i]?Math.max(8,Math.round(pl[i]*100/max)):0}%"></i></span></li>`).join("")}</ol>`}
function procurar(){const i=$("pdashPesquisa"),q=String(i?.value||"").trim().toLowerCase(),out=$("pdashResultado");if(!out)return;if(!q){out.innerHTML="";return}
  const l=ops().filter(o=>[o.id,o.client,o.origin,o.destination].some(v=>String(v||"").toLowerCase().includes(q))).slice(0,6);
  out.innerHTML=l.length?l.map(o=>`<div class="pw-linha"><div><b>${esc(o.id)}</b><small>${esc(o.client||"—")}, ${esc(rota(o))}</small></div><span class="pf-pill">${esc(etapa(o))}</span>${botao("Abrir",abrir(esc(o.id||"")))}</div>`).join(""):`<p class="pf-vazio">Nenhuma encomenda encontrada para «${esc(q)}».</p>`}
const tabela=()=>{const l=[...ops()].sort((a,b)=>quando(b)-quando(a)).slice(0,6);return l.length?linhas(["Encomenda","Cliente","Rota","Etapa",""],l.map(o=>`<tr><td><b>${esc(o.id||"—")}</b></td><td>${esc(o.client||"—")}</td><td>${esc(rota(o))}</td><td><span class="pf-pill">${esc(etapa(o))}</span></td><td>${botao("Abrir",abrir(esc(o.id||"")))}</td></tr>`).join("")):'<p class="pf-vazio">Ainda não existem encomendas.</p>'};

const widgets=()=>[{id:"proximo",titulo:"Próximo passo",span:12,cru:true,render:proximo},{id:"kpis",titulo:"Indicadores",span:12,cru:true,render:kpis},
  {id:"curso",titulo:"Encomendas em curso",sub:"as que precisam de atenção primeiro",span:8,render:curso},{id:"atalhos",titulo:"Ações rápidas",span:4,render:atalhos},
  {id:"recolhas",titulo:"As minhas recolhas de hoje",sub:"atribuídas a si",span:12,render:recolhas},
  {id:"fila",titulo:"Precisa da sua ação",sub:"mais antigos primeiro",span:12,render:()=>{const q=pendentes();return q.length?linhas(["Tipo","Encomenda / pedido","Rota","Cliente","Desde",""],q.slice(0,8).map(x=>`<tr><td><span class="pf-pill">${x.tipo}</span></td><td><b>${esc(x.ref)}</b></td><td>${esc(x.rota)}</td><td>${esc(x.cli)}</td><td>${idade(x.data)}</td><td>${x.btn}</td></tr>`).join("")):'<p class="pf-vazio">Nada à sua espera. Quando algo precisar de si, aparece aqui.</p>'}},
  {id:"alertas",titulo:"Alertas",span:6,render:alertas},{id:"pagamentos",titulo:"Pagamentos por receber",span:6,render:()=>{const o=ops(),l=porReceber();return l.length?l.slice(0,5).map(p=>`<div class="pw-linha"><div><b>${esc(p.operationId)}</b><small>${esc((o.find(x=>x.id===p.operationId)||{}).client||"—")}, ${eur(p.amount||0)}</small></div><button type="button" class="pf-acao" onclick="showProviderFinanceTab('receipts')">Confirmar</button></div>`).join(""):'<p class="pf-vazio">Sem pagamentos por receber.</p>'}},
  {id:"etapas",titulo:"Encomendas por etapa",sub:"clique numa etapa para abrir o quadro",span:12,render:etapas},
  {id:"historico",titulo:"Encomendas recentes",sub:"pesquise por código, cliente ou destino",span:12,render:()=>`<div class="pw-pesquisa ch-pesquisa"><label class="pw-oculto" for="pdashPesquisa">Pesquisar encomenda</label><input id="pdashPesquisa" type="search" placeholder="Pesquisar, ex.: ELO_SOIM-000001 ou São Tomé" oninput="elologPainelPrestador.procurar()"><button type="button" class="btn-secondary" onclick="elologPainelPrestador.procurar()">Pesquisar</button></div><div id="pdashResultado" aria-live="polite"></div>${tabela()}`}];

function desenhar(){const a=$("pdash");if(!a||currentUser?.role!=="prestador")return;const h=new Date().getHours(),q=$("pdashPesquisa")?.value||"";
  a.innerHTML=`<section class="painel-admin pa-centro"><header class="pa-cabecalho"><div><h3>${h<12?"Bom dia":h<19?"Boa tarde":"Boa noite"}, ${esc(String(currentUser.name||"").split(" ")[0])}</h3><p>${esc(currentProviderCompanyName()||"Empresa prestadora")}, ${FUNCOES[funcao()]||"Operador"}, ${new Date().toLocaleDateString("pt-PT",{weekday:"long",day:"numeric",month:"long"})}</p></div><div class="pa-acoes">${Painel.botao("prestador")}</div></header>${Painel.corpo("prestador")}</section>`;
  if(q&&$("pdashPesquisa")){$("pdashPesquisa").value=q;procurar()}}
window.elologPainelPrestador={criar,procurar,desenhar};
const casa=$("providerDashboardHome");if(casa){casa.classList.add("pnovo");const d=document.createElement("div");d.id="pdash";casa.prepend(d)}
Painel.registar("prestador",{alvo:()=>$("pdash"),widgets,padrao:()=>PADRAO[funcao()]||PADRAO.admin,desenhar});
const original=renderProviderDashboard;renderProviderDashboard=function(){const r=original.apply(this,arguments);desenhar();return r};Painel.vigiar("prestador",3e4)})();
