/* Elolog — simulações dos clientes no Centro de comando da administração.
   Mostra as últimas simulações (rascunhos, enviadas, pedidos de cotação, convertidas) com cliente, rota, prestador e valor.
   Dados: rpc simulacoes_administracao (só para o administrador da plataforma). Atualiza a cada 30 s com o painel visível. */
(function(){
  const I=()=>window.__ELOLOG_INTERNO?.["painel@administracao"]||{},esc=v=>String(v??"").replace(/[&<>"']/g,c=>"&#"+c.charCodeAt(0)+";");
  const ESTADO={rascunho:["Simulada","neutro"],enviada:["Enviada ao prestador","info"],respondida:["Respondida","info"],convertida:["Encomenda criada","ok"],cancelada:["Cancelada","mau"]};
  const eur=v=>v==null?"—":Number(v).toLocaleString("pt-PT",{style:"currency",currency:"EUR"});
  const quando=d=>{const m=Math.round((Date.now()-new Date(d))/6e4);return m<1?"agora":m<60?`há ${m} min`:m<1440?`há ${Math.round(m/60)} h`:new Date(d).toLocaleDateString("pt-PT")};
  const DEMO=[{codigo:"ELO_SM-000003",estado:"rascunho",origem:"Lisboa",destino:"São Tomé",volume_m3:.196,cliente:"Cliente de demonstração",created_at:new Date(Date.now()-9e5)},
    {codigo:"ELO_SM-000002",estado:"enviada",origem:"Leixões",destino:"Luanda",volume_m3:2.4,cliente:"Importadora Atlântico",prestador:"Luso Freight (demo)",created_at:new Date(Date.now()-72e5)},
    {codigo:"ELO_SM-000001",estado:"convertida",origem:"Lisboa",destino:"Praia",volume_m3:1.1,preco_estimado:640,cliente:"Casa Verde Lda",prestador:"Tejo Transitários (demo)",created_at:new Date(Date.now()-9e7)}];
  let linhas=null,erro="",filtro="todas";

  function html(){const l=(linhas||[]).filter(r=>filtro==="todas"||(filtro==="cotacao"?r.estado==="enviada"&&r.preco_estimado==null:r.estado===filtro));
    const n=k=>(linhas||[]).filter(r=>r.estado===k).length,chip=(k,t)=>`<button type="button" class="pa-periodo ${filtro===k?"ativo":""}" aria-pressed="${filtro===k}" data-simf="${k}">${t}</button>`;
    const corpo=linhas==null?`<p class="pa-vazio">${erro?"⚠ "+esc(erro):"A carregar simulações…"}</p>`:!l.length?'<p class="pa-vazio">Ainda não há simulações de clientes'+(filtro==="todas"?".":" neste filtro.")+"</p>":
      `<ul class="sa-lista">${l.slice(0,12).map(r=>{const[e,c]=ESTADO[r.estado]||[r.estado,"neutro"],cot=r.estado==="enviada"&&r.preco_estimado==null;
        return`<li><div class="sa-rota"><b>${esc(r.origem)} → ${esc(r.destino)}</b><small>${esc(r.codigo)} · ${quando(r.created_at)}</small></div>
        <div class="sa-quem"><span>${esc(r.cliente||"Cliente")}</span><small>${r.prestador?"para "+esc(r.prestador):"ainda sem prestador"}</small></div>
        <div class="sa-valor"><b>${cot?"Por cotação":eur(r.preco_estimado)}</b><small>${Number(r.volume_m3||0).toFixed(3)} m³</small></div>
        <span class="estado-pill sa-${c}">${cot?"Pedido de cotação":e}</span></li>`}).join("")}</ul>`;
    return`<section class="pa-cartao sa-cartao" id="paSimulacoes" aria-labelledby="saTitulo"><header class="sa-topo"><div><h4 id="saTitulo">Simulações dos clientes</h4>
      <p class="ct-sub">${linhas?`${linhas.length} recentes · ${n("rascunho")} só simuladas · ${n("enviada")} enviadas · ${n("convertida")} convertidas`:"últimas simulações registadas"}</p></div>
      <div class="sa-filtros" role="group" aria-label="Filtrar simulações">${chip("todas","Todas")}${chip("rascunho","Simuladas")}${chip("enviada","Enviadas")}${chip("cotacao","Cotação")}${chip("convertida","Convertidas")}</div></header>${corpo}</section>`}

  function inserir(){const p=document.querySelector("#adminDashboardProviders .painel-admin");if(!p||currentUser?.role!=="admin")return;const velho=document.getElementById("paSimulacoes"),novo=html();
    if(velho){velho.outerHTML=novo;return}document.querySelectorAll(".pw-s12:empty").forEach(x=>x.remove());const k=p.querySelector("#pw-kpis"),ref=p.querySelector(".pa-cabecalho");if(k)k.insertAdjacentHTML("afterend",`<div class="pw pw-s12">${novo}</div>`);else if(ref)ref.insertAdjacentHTML("afterend",novo);else p.insertAdjacentHTML("afterbegin",novo)}
  async function carregar(){if(currentUser?.role!=="admin")return;if(I().sessaoDemo?.()||!window.ELOLogServidor?.ativo?.()){linhas=DEMO;return inserir()}
    try{const c=await window.ELOLogServidor.cliente(),{data,error}=await c.rpc("simulacoes_administracao",{p_limite:60});if(error)throw error;linhas=data||[];erro=""}catch(e){erro=window.ELOLogServidor.mensagem?.(e)||e.message}inserir()}

  document.addEventListener("click",e=>{const b=e.target.closest("[data-simf]");if(!b)return;filtro=b.dataset.simf;inserir()});
  new MutationObserver(()=>{if(document.querySelector("#adminDashboardProviders .painel-admin")&&!document.getElementById("paSimulacoes"))inserir()})
    .observe(document.documentElement,{childList:true,subtree:true});
  setInterval(()=>{if(document.visibilityState==="visible"&&document.getElementById("dashboard")?.classList.contains("active"))carregar()},3e4);
  if(typeof startApp==="function"){const ini=startApp;startApp=async function(){const r=await ini.apply(this,arguments);carregar();return r}}
  window.elologSimulacoesAdmin={carregar};
})();
