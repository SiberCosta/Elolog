/* Elolog — tarifas do prestador no servidor (v114: Centro de Gestão de Tarifários).
   Com servidor ligado, guardar publica a tarifa (rpc tarifa_guardar, validado no servidor): entra logo nas simulações, sem esperar pela Elolog (v116)
   depois de aprovada. Uma alteração cria uma nova versão; a anterior continua em vigor até a nova ser aprovada.
   Sem servidor (modo de demonstração) fica tudo como antes, no navegador. */
(function(){
  const P=()=>window.elologProducao,online=()=>!!P()?.online()&&currentUser?.role==="prestador";
  const METODO={"por peso":"peso","por volume":"volume","por quantidade":"unidade","por unidade":"unidade","preço fixo":"fixo","preco fixo":"fixo"};
  const DE_METODO={peso:"Por peso",volume:"Por volume",unidade:"Por quantidade",fixo:"Preço fixo",wm:"Por volume",contentor:"Por quantidade"};
  const APL={cargo:"carga",pickup:"recolha",additional:"adicional"},DE_APL={carga:"cargo",recolha:"pickup",adicional:"additional"};
  const norm=v=>String(v||"").trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"");
  const chave=()=>"elolog_finance_"+(norm(typeof currentProviderCompanyName==="function"?currentProviderCompanyName():"").replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"")||"prestador");
  const aviso=(m,t)=>P()?.aviso(m,t);
  const ESTADO={rascunho:"Rascunho",pendente:"Por aprovar",alteracoes_pedidas:"Alterações pedidas",aprovada:"Ativa",rejeitada:"Rejeitada",suspensa:"Suspensa pela Elolog",inativa:"Inativa",substituida:"Substituída"};
  const ler=()=>{try{return JSON.parse(localStorage.getItem(chave())||"null")||{}}catch(_){return{}}};

  /** Formulário «Nova tarifa» → linha da tabela tarifas. */
  function linha(){const v=id=>document.getElementById(id)?.value||"",tipo=v("finTariffCargo").trim();
    return{nome:v("finTariffName").trim(),aplicacao:APL[v("finTariffApplication")]||"carga",tipo_carga:!tipo||/^tod/i.test(tipo)?null:tipo,
      metodo:METODO[norm(v("finTariffMethod")).replace("preco","preço")]||METODO[v("finTariffMethod").toLowerCase()]||"volume",valor:Number(v("finTariffValue")),
      moeda:v("finTariffCurrency")||"EUR",quantidade_minima:Number(v("finTariffMinQty"))||0,preco_minimo:Number(v("finTariffMinPrice"))||0,
      origem:v("finTariffOrigin").trim()||null,destino:v("finTariffDestination").trim()||null,validade_inicio:v("finTariffStart")||null,validade_fim:v("finTariffEnd")||null,
      ativa:v("finTariffStatus")!=="Inativa",regras:{volumetricFactor:Number(v("finTariffVolumetricFactor"))||167,unitLabel:v("finTariffUnitLabel")||null,palavras:v("finTariffKeywords").split(",").map(x=>x.trim()).filter(Boolean).slice(0,12),so_descricao:!!document.getElementById("finTariffOnlyDesc")?.checked},notas:v("finTariffNotes").trim()||null}}

  /** Traz as tarifas do servidor para a lista do Financeiro (o servidor manda). */
  async function sincronizar(){if(!online())return;try{const c=await P().sb(),emp=await P().minhaEmpresa();if(!emp)return;
    const{data,error}=await c.from("tarifas").select("*").eq("empresa_id",emp.empresa_id).order("created_at",{ascending:false}).limit(300);if(error)throw error;
    const d=ler();d.tariffs=(data||[]).map(t=>({id:"SRV-"+t.id,serverId:t.id,parentId:t.tarifa_pai_id?"SRV-"+t.tarifa_pai_id:"",version:t.versao,name:t.nome,application:DE_APL[t.aplicacao]||"cargo",
      cargoType:t.tipo_carga||"",method:DE_METODO[t.metodo]||"Por volume",value:Number(t.valor),currency:(t.moeda||"EUR").trim(),minimumQuantity:Number(t.quantidade_minima),minimumPrice:Number(t.preco_minimo),
      transport:t.transporte||"",origin:t.origem||"",destination:t.destino||"",startDate:t.validade_inicio||"",endDate:t.validade_fim||"",status:ESTADO[t.estado]||(t.ativa?"Ativa":"Inativa"),estado:t.estado,
      notes:[t.motivo_decisao&&["alteracoes_pedidas","rejeitada","suspensa"].includes(t.estado)?`Elolog: ${t.motivo_decisao}`:"",t.notas||""].filter(Boolean).join(" · "),rules:t.regras||{},unitLabel:t.regras?.unitLabel||"",createdAt:t.created_at,createdBy:"Servidor"}));
    localStorage.setItem(chave(),JSON.stringify(d));window.renderProviderFinance?.()}catch(e){console.warn("Tarifas do servidor indisponíveis",e?.message)}}
  const serverId=id=>ler().tariffs?.find(t=>t.id===id)?.serverId;

  function ligar(){const guardar=window.saveFinanceTariff,alternar=window.toggleFinanceTariff,apagar=window.deleteFinanceTariff,abrir=window.showProviderFinanceTab;
    if(typeof guardar!=="function")return;
    window.saveFinanceTariff=async function(event,id=""){if(!online())return guardar.apply(this,arguments);event.preventDefault();
      const r=linha();if(!r.nome||!(r.valor>=0)||document.getElementById("finTariffValue")?.value==="")return aviso("Preencha o nome e um valor válido.","warning");
      if(r.validade_inicio&&r.validade_fim&&r.validade_fim<r.validade_inicio)return aviso("A data «válida até» é anterior à data de início.","warning");
      const btn=event.submitter;window.elologBotao?.carregar(btn,true);
      try{const c=await P().sb();const antigo=serverId(id);const{estado,ativa,...dados}=r;
        const{error}=await c.rpc("tarifa_guardar",{p_dados:dados,p_base:antigo||null,p_submeter:ativa,p_motivo:antigo?"Nova versão publicada pelo prestador":null});
        if(error)throw new Error(error.code==="42501"?"Só o administrador ou o financeiro podem gravar tarifas.":"O servidor não aceitou a tarifa: "+String(error.message).replace(/^.*?ERROR:\s*/,""));
        document.getElementById("platformRecordDrawer")&&window.closeProviderDrawer?.("platformRecordDrawer");
        aviso(ativa?"Tarifa em vigor: já entra nas simulações."+(antigo?" A versão anterior ficou guardada no histórico (as encomendas já aceites mantêm o preço).":""):"Tarifa guardada como rascunho: não entra nas simulações enquanto não a ativar.","success");await sincronizar()}catch(e){aviso(e.message,"error")}finally{window.elologBotao?.carregar(btn,false)}};
    window.toggleFinanceTariff=async function(id){const s=online()&&serverId(id);if(!s)return alternar.apply(this,arguments);
      const e=ler().tariffs.find(t=>t.id===id)?.estado;if(["suspensa","substituida"].includes(e))return aviso(e==="suspensa"?"Esta tarifa foi suspensa pela Elolog. Fale com a equipa Elolog para a reativar.":"Esta versão já foi substituída por uma mais recente.","info");
      const novo=e==="aprovada"?"inativa":"aprovada";const c=await P().sb();const{error}=await c.from("tarifas").update({estado:novo}).eq("id",s);
      if(error)return aviso("Não foi possível alterar a tarifa: "+String(error.message).replace(/^.*?ERROR:\s*/,""),"error");aviso(novo==="inativa"?"Tarifa desativada: deixa de entrar nas simulações.":"Tarifa ativada: já entra nas simulações.","success");sincronizar()};
    window.deleteFinanceTariff=async function(id){const s=online()&&serverId(id);if(!s)return apagar.apply(this,arguments);
      if(!confirm("Apagar esta tarifa? Se já foi usada em propostas, fica apenas desativada."))return;const c=await P().sb();
      let{error}=await c.from("tarifas").delete().eq("id",s);if(error){({error}=await c.from("tarifas").update({estado:"inativa"}).eq("id",s));if(!error)aviso("A tarifa já foi usada: ficou desativada.","info")}
      else aviso("Tarifa apagada.","success");sincronizar()};
    if(typeof abrir==="function")window.showProviderFinanceTab=function(tab){const r=abrir.apply(this,arguments);if(tab==="prices"||tab==="overview")sincronizar();return r}}
  /* toda a equipa (operadores, armazém, terreno) recebe as tarifas em vigor da empresa: ao entrar e ao abrir páginas (no máximo 1 vez por minuto) */
  let ultima=0;const talvez=()=>{if(!online()||Date.now()-ultima<60000)return;ultima=Date.now();sincronizar()};
  const ir=window.showProviderPage;if(typeof ir==="function"&&!ir.__tarifas){const n=function(){const r=ir.apply(this,arguments);talvez();return r};n.__tarifas=1;window.showProviderPage=n}
  setTimeout(talvez,3000);
  window.elologTarifas={sincronizar};
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);else ligar();
})();
