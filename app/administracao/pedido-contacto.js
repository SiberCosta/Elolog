/* Elolog — pedido por contacto: quando um cliente liga, escreve ou vem ao balcão, a administração faz a simulação,
   escolhe o prestador e regista o pedido em nome do cliente (4 etapas com validação e resumo).
   Servidor: clientes_administracao, calcular_propostas e admin_registar_pedido. O prestador recebe o pedido e aceita
   ao preço da tarifa, ao preço combinado indicado aqui, ou indica o preço (pedido de cotação). */
(function(){
  const P=()=>window.elologProducao,esc=v=>P()?.esc(v)??String(v??""),eur=v=>P().euros(v);
  const CARGAS=["Comercial","Mudança","Alimentar","Veículo","Materiais de construção","Máquinas e equipamentos","Refrigerada","Volumosa","Carga especial","Documentos/pequena encomenda","Outro"];
  const CANAIS={telefone:"Telefone",email:"Email",balcao:"Balcão",outro:"Outro"};
  const DEMO_PREST=[{prestador_id:"d1",prestador_nome:"Transatlântico Demo, Lda.",disponivel:true,f:180},{prestador_id:"d2",prestador_nome:"Luso Freight (demo)",disponivel:true,f:210},{prestador_id:"d3",prestador_nome:"Tejo Transitários (demo)",disponivel:false}];
  const campo=(id,r,t="text",x="")=>`<div class="pc-campo"><label for="${id}">${r}</label><input id="${id}" type="${t}" ${x}></div>`;
  const v=id=>(document.getElementById(id)?.value||"").trim(),n=id=>Number(v(id).replace(",","."))||0;

  function abrir(){if(!P())return;const d={cliente:null,contacto:{},canal:"telefone"};let propostas=[],escolha=null;
    const j=P().janela({eyebrow:"PEDIDO POR CONTACTO",titulo:"Simular e criar pedido para um cliente",passos:["Cliente","Rota e carga","Prestador","Confirmar"]});

    function passo1(){j.passo(0);j.mostrar(`<p class="campo-ajuda">Procure um cliente registado ou indique o contacto de quem ligou.</p>
      <div class="pc-grelha"><div class="pc-campo"><label for="pcCanal">Como contactou</label><select id="pcCanal">${Object.entries(CANAIS).map(([k,t])=>`<option value="${k}"${k===d.canal?" selected":""}>${t}</option>`).join("")}</select></div>
      ${campo("pcProcura","Procurar cliente registado","search",'placeholder="Nome, email ou telefone" autocomplete="off"')}</div><div id="pcResultados" class="pc-lista" role="listbox" aria-label="Clientes"></div>
      <fieldset class="pc-novo"><legend>${d.cliente?"Cliente selecionado":"Ou cliente sem conta"}</legend>${d.cliente?`<p><b>${esc(d.cliente.nome)}</b> · ${esc(d.cliente.email||"")} ${esc(d.cliente.telefone||"")} <button type="button" class="btn-secondary" id="pcLimpar">Trocar</button></p>`:
      `<div class="pc-grelha">${campo("pcNome","Nome / empresa","text",`value="${esc(d.contacto.nome||"")}"`)}${campo("pcTel","Telefone","tel",`value="${esc(d.contacto.telefone||"")}"`)}${campo("pcEmail","Email","email",`value="${esc(d.contacto.email||"")}"`)}${campo("pcNif","NIF (opcional)","text",`value="${esc(d.contacto.nif||"")}"`)}</div>`}</fieldset>`,
      [{texto:"Cancelar",acao:j.fechar},{texto:"Continuar",principal:true,acao:()=>{d.canal=v("pcCanal");if(!d.cliente){d.contacto={nome:v("pcNome"),telefone:v("pcTel"),email:v("pcEmail"),nif:v("pcNif")};
        if(d.contacto.nome.length<2)return P().aviso("Indique o nome do cliente ou escolha um cliente registado.","warning");if(!d.contacto.telefone&&!d.contacto.email)return P().aviso("Indique o telefone ou o email do cliente.","warning")}passo2()}}]);
      document.getElementById("pcLimpar")?.addEventListener("click",()=>{d.cliente=null;passo1()});let t;document.getElementById("pcProcura").addEventListener("input",e=>{clearTimeout(t);t=setTimeout(()=>procurar(e.target.value.trim()),250)})}
    async function procurar(q){const box=document.getElementById("pcResultados");if(!box)return;if(q.length<2){box.innerHTML="";return}
      if(!P().online()){box.innerHTML='<p class="campo-ajuda">No modo de demonstração não há clientes do servidor; use «cliente sem conta».</p>';return}
      try{const c=await P().sb(),{data,error}=await c.rpc("clientes_administracao",{p_texto:q});if(error)throw error;
        box.innerHTML=(data||[]).map((c,i)=>`<button type="button" class="pc-opcao" data-i="${i}"><b>${esc(c.nome)}</b><small>${esc(c.email)} ${esc(c.telefone||"")}</small></button>`).join("")||'<p class="campo-ajuda">Nenhum cliente encontrado.</p>';
        box.querySelectorAll(".pc-opcao").forEach(b=>b.onclick=()=>{d.cliente=data[+b.dataset.i];d.canal=v("pcCanal");passo1()})}catch(e){box.innerHTML=`<p class="campo-erro">${esc(e.message)}</p>`}}

    function passo2(){j.passo(1);const c=d.carga||{};j.mostrar(`<div class="pc-grelha">${campo("pcOrigem","Origem","text",`value="${esc(c.origem||"")}" placeholder="Cidade, país"`)}${campo("pcDestino","Destino","text",`value="${esc(c.destino||"")}" placeholder="Cidade, país"`)}
      <div class="pc-campo"><label for="pcTipo">Tipo de carga</label><select id="pcTipo"><option value="">Selecionar</option>${CARGAS.map(x=>`<option${x===c.tipo_carga?" selected":""}>${x}</option>`).join("")}</select></div>${campo("pcData","Data prevista","date",`value="${esc(c.data_prevista||"")}"`)}
      ${campo("pcDescricao","Descrição da carga","text",`value="${esc(c.descricao||"")}" placeholder="Ex.: 3 caixas de roupa"`)}${campo("pcQtd","Quantidade (volumes)","number",`min="1" value="${c.quantidade||1}"`)}
      ${campo("pcPeso","Peso total (kg)","number",`min="0" step="0.1" value="${c.peso_kg||""}"`)}${campo("pcVolume","Volume total (m³)","number",`min="0" step="0.001" value="${c.volume_m3||""}"`)}</div>
      <p class="campo-ajuda">Sem o volume? Indique as medidas de um volume (cm) e eu calculo:</p><div class="pc-dims">${campo("pcC","Comprimento","number",'min="0"')}${campo("pcL","Largura","number",'min="0"')}${campo("pcA","Altura","number",'min="0"')}</div>
      <div class="pc-grelha"><div class="pc-campo"><label for="pcRecolha">Recolha na morada?</label><select id="pcRecolha"><option value="nao">Não, entrega no armazém</option><option value="sim"${c.recolha?" selected":""}>Sim</option></select></div>${campo("pcKm","Distância da recolha (km)","number",`min="0" value="${c.km||""}"`)}
      ${campo("pcMoradaRec","Morada de recolha","text",`value="${esc(c.morada_recolha||"")}"`)}${campo("pcDestNome","Destinatário","text",`value="${esc(c.destinatario?.nome||"")}"`)}${campo("pcDestTel","Telefone do destinatário","tel",`value="${esc(c.destinatario?.telefone||"")}"`)}${campo("pcDestMorada","Morada de entrega","text",`value="${esc(c.destinatario?.morada||"")}"`)}</div>
      <div class="pc-campo"><label for="pcObs">Observações</label><textarea id="pcObs" rows="2">${esc(c.observacoes||"")}</textarea></div>`,
      [{texto:"Voltar",acao:passo1},{texto:"Ver prestadores",principal:true,acao:async()=>{const dims=[n("pcC"),n("pcL"),n("pcA")];let vol=n("pcVolume");if(!vol&&dims.every(x=>x>0))vol=+(dims[0]*dims[1]*dims[2]/1e6*Math.max(1,n("pcQtd"))).toFixed(3);
        if(!v("pcOrigem")||!v("pcDestino"))return P().aviso("Indique a origem e o destino.","warning");if(!v("pcTipo"))return P().aviso("Escolha o tipo de carga.","warning");if(!vol&&!n("pcPeso"))return P().aviso("Indique o peso ou o volume da carga.","warning");
        d.carga={origem:v("pcOrigem"),destino:v("pcDestino"),tipo_carga:v("pcTipo"),data_prevista:v("pcData"),descricao:v("pcDescricao"),quantidade:Math.max(1,Math.round(n("pcQtd"))),peso_kg:n("pcPeso"),volume_m3:vol,
          recolha:v("pcRecolha")==="sim",km:n("pcKm"),morada_recolha:v("pcMoradaRec"),destinatario:{nome:v("pcDestNome"),telefone:v("pcDestTel"),morada:v("pcDestMorada")},observacoes:v("pcObs")};await passo3()}}])}

    async function passo3(){j.passo(2);j.mostrar('<p class="pa-vazio">A calcular as propostas dos prestadores…</p>',[]);const c=d.carga;
      try{if(P().online()){const s=await P().sb(),{data,error}=await s.rpc("calcular_propostas",{p_origem:c.origem,p_destino:c.destino,p_tipo_carga:c.tipo_carga,p_quantidade:c.quantidade,p_peso_kg:c.peso_kg,p_volume_m3:c.volume_m3,p_recolha_km:c.recolha?c.km:0});
          if(error)throw error;propostas=data||[]}else propostas=DEMO_PREST.map(p=>({...p,preco_total:p.disponivel?+(p.f*Math.max(c.volume_m3,c.peso_kg/167,.1)).toFixed(2):null}))}
      catch(e){j.mostrar(`<p class="campo-erro">${esc(window.ELOLogServidor?.mensagem?.(e)||e.message)}</p>`,[{texto:"Voltar",acao:passo2}]);return}
      j.mostrar(propostas.length?`<div class="pc-lista" role="radiogroup" aria-label="Prestadores">${propostas.map((p,i)=>`<label class="pc-prestador"><input type="radio" name="pcPrest" value="${i}"${escolha===p.prestador_id?" checked":""}>
        <span><b>${esc(p.prestador_nome)}</b><small>${p.disponivel?"Preço pela tarifa do prestador":"Sem tarifa para esta rota · pedido de cotação"}</small></span><strong>${p.disponivel?eur(p.preco_total):"Por cotação"}</strong></label>`).join("")}</div>
        ${campo("pcPreco","Preço combinado com o cliente (€, opcional)","number",'min="0.01" step="0.01" placeholder="Deixe vazio para usar a tarifa"')}<p class="campo-ajuda">Se indicar um preço, o prestador recebe o pedido com esse valor.</p>`
        :'<p class="pa-vazio">Não há prestadores ativos disponíveis.</p>',[{texto:"Voltar",acao:passo2},{texto:"Rever pedido",principal:true,acao:()=>{const r=document.querySelector('input[name="pcPrest"]:checked');
          if(!r)return P().aviso("Escolha o prestador que vai realizar o serviço.","warning");const p=propostas[+r.value];escolha=p.prestador_id;d.prestador=p;d.preco=n("pcPreco")||null;passo4()}}])}

    function passo4(){j.passo(3);const c=d.carga,cli=d.cliente||d.contacto,preco=d.preco||d.prestador.preco_total;
      j.mostrar(`<dl class="pm-resumo"><div><dt>Cliente</dt><dd>${esc(cli.nome)} · ${esc(cli.telefone||cli.email||"")}${d.cliente?" (registado)":" (sem conta)"}</dd></div><div><dt>Contacto</dt><dd>${CANAIS[d.canal]}</dd></div>
        <div><dt>Rota</dt><dd>${esc(c.origem)} → ${esc(c.destino)}${c.data_prevista?" · "+esc(c.data_prevista):""}</dd></div><div><dt>Carga</dt><dd>${esc(c.tipo_carga)} · ${c.quantidade} vol. · ${c.peso_kg} kg · ${c.volume_m3} m³${c.recolha?" · recolha "+c.km+" km":""}</dd></div>
        <div><dt>Prestador</dt><dd>${esc(d.prestador.prestador_nome)}</dd></div><div><dt>Preço</dt><dd><b>${preco?eur(preco):"Por cotação (o prestador indica)"}</b>${d.preco?" · combinado com o cliente":""}</dd></div></dl>`,
        [{texto:"Voltar",acao:passo3},{texto:"Criar pedido e enviar ao prestador",principal:true,acao:enviar}])}
    async function enviar(){const c=d.carga,dados={...c,cliente_id:d.cliente?.id||"",remetente:d.cliente?{nome:d.cliente.nome,email:d.cliente.email,telefone:d.cliente.telefone,nif:d.cliente.nif,morada:d.cliente.morada}:d.contacto,canal:d.canal,volumes:[]};
      try{let cod;if(P().online()){const s=await P().sb(),{data,error}=await s.rpc("admin_registar_pedido",{p_dados:dados,p_empresa:d.prestador.prestador_id,p_preco:d.preco});if(error)throw error;cod=(Array.isArray(data)?data[0]:data)?.codigo}
        else cod="SIM-DEMO-"+String(Date.now()).slice(-4);
        j.mostrar(`<div class="pm-valor"><span>Pedido registado</span><strong>${esc(cod||"")}</strong></div><p>${esc(d.prestador.prestador_nome)} foi notificado${d.cliente?" e o cliente vê o pedido na sua área":""}. Acompanhe em «Simulações dos clientes».</p>`,
          [{texto:"Novo pedido",acao:()=>{j.fechar();abrir()}},{texto:"Concluir",principal:true,acao:j.fechar}]);window.elologSimulacoesAdmin?.carregar()}
      catch(e){P().aviso(window.ELOLogServidor?.mensagem?.(e)||e.message,"error")}}
    passo1()}

  /* Botão no Centro de comando e item no menu «Operações e clientes». */
  function ligar(){const a=document.querySelector("#adminDashboardProviders .pa-acoes");if(a&&!a.querySelector(".pc-botao"))a.insertAdjacentHTML("afterbegin",'<button type="button" class="pa-botao pa-botao-forte pc-botao" onclick="elologPedidoContacto()">+ Pedido por contacto</button>');
    const g=document.getElementById("adminGrpOp");if(g&&!g.querySelector(".pc-menu"))g.insertAdjacentHTML("beforeend",'<button type="button" class="pc-menu" onclick="elologPedidoContacto()">Pedido por contacto</button>')}
  new MutationObserver(ligar).observe(document.documentElement,{childList:true,subtree:true});
  window.elologPedidoContacto=abrir;
})();
