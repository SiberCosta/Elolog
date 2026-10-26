/* Elolog — tarifas no servidor. Com servidor ligado, guardar, ativar/desativar e apagar uma tarifa grava-a na tabela
   «tarifas», que é a que o simulador do cliente usa (calcular_propostas). A lista do Financeiro passa a mostrar o que
   está no servidor. Uma alteração cria uma nova versão e desativa a anterior (as propostas antigas não mudam de preço).
   Sem servidor (modo de demonstração) fica tudo como antes, no navegador. */
(function(){
  const P=()=>window.elologProducao,online=()=>!!P()?.online()&&currentUser?.role==="prestador";
  const METODO={"por peso":"peso","por volume":"volume","por quantidade":"unidade","por unidade":"unidade","preço fixo":"fixo","preco fixo":"fixo"};
  const DE_METODO={peso:"Por peso",volume:"Por volume",unidade:"Por quantidade",fixo:"Preço fixo",wm:"Por volume",contentor:"Por quantidade"};
  const APL={cargo:"carga",pickup:"recolha",additional:"adicional"},DE_APL={carga:"cargo",recolha:"pickup",adicional:"additional"};
  const norm=v=>String(v||"").trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"");
  const chave=()=>"elolog_finance_"+(norm(typeof currentProviderCompanyName==="function"?currentProviderCompanyName():"").replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"")||"prestador");
  const aviso=(m,t)=>P()?.aviso(m,t);
  const ler=()=>{try{return JSON.parse(localStorage.getItem(chave())||"null")||{}}catch(_){return{}}};

  /** Formulário «Nova tarifa» → linha da tabela tarifas. */
  function linha(){const v=id=>document.getElementById(id)?.value||"",tipo=v("finTariffCargo").trim();
    return{nome:v("finTariffName").trim(),aplicacao:APL[v("finTariffApplication")]||"carga",tipo_carga:!tipo||/^tod/i.test(tipo)?null:tipo,
      metodo:METODO[norm(v("finTariffMethod")).replace("preco","preço")]||METODO[v("finTariffMethod").toLowerCase()]||"volume",valor:Number(v("finTariffValue")),
      moeda:v("finTariffCurrency")||"EUR",quantidade_minima:Number(v("finTariffMinQty"))||0,preco_minimo:Number(v("finTariffMinPrice"))||0,
      origem:v("finTariffOrigin").trim()||null,destino:v("finTariffDestination").trim()||null,validade_inicio:v("finTariffStart")||null,validade_fim:v("finTariffEnd")||null,
      ativa:v("finTariffStatus")!=="Inativa",regras:{volumetricFactor:Number(v("finTariffVolumetricFactor"))||167,unitLabel:v("finTariffUnitLabel")||null},notas:v("finTariffNotes").trim()||null}}

  /** Traz as tarifas do servidor para a lista do Financeiro (o servidor manda). */
  async function sincronizar(){if(!online())return;try{const c=await P().sb(),emp=await P().minhaEmpresa();if(!emp)return;
    const{data,error}=await c.from("tarifas").select("*").eq("empresa_id",emp.empresa_id).order("created_at",{ascending:false}).limit(300);if(error)throw error;
    const d=ler();d.tariffs=(data||[]).map(t=>({id:"SRV-"+t.id,serverId:t.id,parentId:t.tarifa_pai_id?"SRV-"+t.tarifa_pai_id:"",version:t.versao,name:t.nome,application:DE_APL[t.aplicacao]||"cargo",
      cargoType:t.tipo_carga||"",method:DE_METODO[t.metodo]||"Por volume",value:Number(t.valor),currency:(t.moeda||"EUR").trim(),minimumQuantity:Number(t.quantidade_minima),minimumPrice:Number(t.preco_minimo),
      transport:t.transporte||"",origin:t.origem||"",destination:t.destino||"",startDate:t.validade_inicio||"",endDate:t.validade_fim||"",status:t.ativa?"Ativa":"Inativa",
      notes:t.notas||"",rules:t.regras||{},unitLabel:t.regras?.unitLabel||"",createdAt:t.created_at,createdBy:"Servidor"}));
    localStorage.setItem(chave(),JSON.stringify(d));window.renderProviderFinance?.()}catch(e){console.warn("Tarifas do servidor indisponíveis",e?.message)}}
  const serverId=id=>ler().tariffs?.find(t=>t.id===id)?.serverId;

  function ligar(){const guardar=window.saveFinanceTariff,alternar=window.toggleFinanceTariff,apagar=window.deleteFinanceTariff,abrir=window.showProviderFinanceTab;
    if(typeof guardar!=="function")return;
    window.saveFinanceTariff=async function(event,id=""){if(!online())return guardar.apply(this,arguments);event.preventDefault();
      const r=linha();if(!r.nome||!(r.valor>=0)||document.getElementById("finTariffValue")?.value==="")return aviso("Preencha o nome e um valor válido.","warning");
      if(r.validade_inicio&&r.validade_fim&&r.validade_fim<r.validade_inicio)return aviso("A data «válida até» é anterior à data de início.","warning");
      const btn=event.submitter;window.elologBotao?.carregar(btn,true);
      try{const c=await P().sb(),emp=await P().minhaEmpresa(),u=await P().utilizador();if(!emp)throw new Error("Sessão da empresa expirada. Entre de novo.");
        const antigo=serverId(id),ant=ler().tariffs?.find(t=>t.id===id);
        const{error}=await c.from("tarifas").insert({...r,empresa_id:emp.empresa_id,tarifa_pai_id:antigo||null,versao:Number(ant?.version||0)+1,criado_por:u?.id||null});
        if(error)throw new Error(error.code==="42501"?"Só o administrador ou o financeiro podem gravar tarifas.":"O servidor não aceitou a tarifa: "+error.message);
        if(antigo)await c.from("tarifas").update({ativa:false}).eq("id",antigo);
        document.getElementById("platformRecordDrawer")&&window.closeProviderDrawer?.("platformRecordDrawer");
        aviso("Tarifa guardada no servidor. Já aparece nas propostas do simulador.","success");await sincronizar()}catch(e){aviso(e.message,"error")}finally{window.elologBotao?.carregar(btn,false)}};
    window.toggleFinanceTariff=async function(id){const s=online()&&serverId(id);if(!s)return alternar.apply(this,arguments);
      const atual=ler().tariffs.find(t=>t.id===id),ativa=atual?.status!=="Ativa";const c=await P().sb();const{error}=await c.from("tarifas").update({ativa}).eq("id",s);
      if(error)return aviso("Não foi possível alterar a tarifa.","error");aviso(ativa?"Tarifa ativada.":"Tarifa desativada.","success");sincronizar()};
    window.deleteFinanceTariff=async function(id){const s=online()&&serverId(id);if(!s)return apagar.apply(this,arguments);
      if(!confirm("Apagar esta tarifa? Se já foi usada em propostas, fica apenas desativada."))return;const c=await P().sb();
      let{error}=await c.from("tarifas").delete().eq("id",s);if(error){({error}=await c.from("tarifas").update({ativa:false}).eq("id",s));if(!error)aviso("A tarifa já foi usada: ficou desativada.","info")}
      else aviso("Tarifa apagada.","success");sincronizar()};
    if(typeof abrir==="function")window.showProviderFinanceTab=function(tab){const r=abrir.apply(this,arguments);if(tab==="prices"||tab==="overview")sincronizar();return r}}
  window.elologTarifas={sincronizar};
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);else ligar();
})();
