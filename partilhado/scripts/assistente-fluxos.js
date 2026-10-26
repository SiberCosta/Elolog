/* Elolog — fluxos automáticos do ELO (assistente virtual), por perfil.
   Cada fluxo reconhece um pedido escrito por palavras do utilizador (ou um atalho) e executa o passo certo da plataforma:
   abre a página, a janela em etapas ou o formulário já preparado. O assistente (assistente.js) consulta window.eloFluxos
   antes das respostas genéricas; window.eloChips define os atalhos de cada perfil. */
(function(){
  const chama=(nome,...a)=>()=>{try{const f=nome.split(".").reduce((o,k)=>o?.[k],window);if(typeof f==="function")f(...a)}catch(_){}};
  const pagina=(papel,id,depois)=>()=>{try{const b=document.querySelector(`[onclick*="'${id}'"]`);
    if(papel==="admin")showAdminPage(id,b);else if(papel==="prestador")showProviderPage(id,b);else showPage(id,b||document.querySelector(`[onclick*="${id}"]`))}catch(_){}if(depois)setTimeout(depois,350)};
  const ir=id=>()=>{const el=document.getElementById(id);if(el){el.scrollIntoView({behavior:"smooth",block:"start"});el.classList.add("elo-realce");setTimeout(()=>el.classList.remove("elo-realce"),2500)}};
  const servidor=()=>!!window.elologProducao?.online();

  window.eloChips={
    admin:["Pedido por contacto","Simulações dos clientes","Novo funcionário","Pedidos de inscrição","Resumo"],
    prestador:["Pedidos de cotação","Nova tarifa","Registar fatura","Navios em tempo real","Resumo"],
    cliente:["Nova simulação","Última encomenda","Pagar encomenda","Os meus documentos","Falar com um humano"]};

  window.eloFluxos=[
    /* ---------- administração ---------- */
    {papeis:["admin"],re:/pedido por contacto|cliente (ligou|telefonou|escreveu|contactou)|criar (uma )?encomenda para|registar pedido|em nome do cliente|simular para (um )?cliente/,
      fazer:()=>({texto:"Abri o pedido por contacto em 4 etapas: cliente, rota e carga, escolha do prestador e confirmação. O prestador escolhido é notificado logo que confirmar.",go:chama("elologPedidoContacto")})},
    {papeis:["admin"],re:/simulac\w* dos clientes|cotac\w*|simulac\w* (recentes|registadas)|ver simulac/,
      fazer:()=>({texto:"Estas são as simulações dos clientes no Centro de comando. Use os filtros «Simuladas», «Enviadas», «Cotação» e «Convertidas».",go:pagina("admin","dashboard",ir("paSimulacoes"))})},
    {papeis:["admin"],re:/(novo|criar|adicionar) (funcionario|colaborador|membro)|equipa elolog|gerir equipa/,
      fazer:()=>({texto:"A abrir «Funcionários e acessos» com o formulário de novo funcionário. Escolha a função: administrador, operador ou apoio. No 1.º acesso o funcionário configura o código de autenticação.",
        go:pagina("admin","adminAccess",chama("elologEquipa.novo"))})},
    /* ---------- prestador ---------- */
    {papeis:["prestador"],re:/pedidos? de cotac|cotac\w* (pendentes|recebidas)|simulac\w* recebidas/,
      fazer:()=>({texto:"A abrir as cotações recebidas. Nos pedidos sem tarifa, use «Indicar preço e aceitar»; para não voltar a receber pedidos sem preço, crie a tarifa da rota.",go:pagina("prestador","providerCotacao")})},
    {papeis:["prestador"],re:/(nova|criar|adicionar|configurar) tarifa|tabela de precos|definir precos?/,
      fazer:()=>({texto:"A abrir «Nova tarifa». Indique nome, rota (origem e destino), tipo de carga, método (peso, volume, unidade ou fixo) e valor. Ao guardar, passa logo a aparecer no simulador dos clientes.",
        go:()=>{try{showProviderFinanceTab("prices",document.querySelector(`[onclick*="showProviderFinanceTab('prices'"]`))}catch(_){}setTimeout(chama("openFinanceTariff",""),400)}})},
    {papeis:["prestador"],re:/registar fatura|fatura certificada|emitir fatura/,
      fazer:()=>({texto:"Abri o registo de fatura certificada: carregue o PDF do seu programa certificado, eu leio o código QR e mostro o resumo para confirmar.",go:chama("elologFaturas.abrir")})},
    {papeis:["prestador"],re:/navios?( em tempo real)?|onde (esta|anda) o navio|\bais\b/,
      fazer:()=>servidor()?{texto:"A abrir os navios em tempo real (posição, velocidade e ETA atualizados a cada 30 minutos).",go:chama("elologNavios.abrir")}:{texto:"No modo de demonstração use o Mapa marítimo; os navios em tempo real precisam do servidor.",go:pagina("prestador","providerMaritimeCalendar")}},
    {papeis:["prestador"],re:/pagamentos? online|multibanco|mb ?way|ifthenpay/,
      fazer:()=>({texto:"A abrir a configuração dos pagamentos online (Multibanco e MB WAY pela ifthenpay).",go:chama("elologPagamentos.config")})},
    /* ---------- cliente ---------- */
    {papeis:["cliente"],re:/^nova simulac|^simular$|quero simular|fazer (uma )?simulac/,
      fazer:()=>({texto:"A abrir a simulação. Preencha rota, destinatário e volumes; o resumo e as propostas aparecem à direita. Se um prestador ainda não tiver preço para a rota, pode pedir-lhe cotação.",go:pagina("cliente","clientSimulation")})},
    {papeis:["cliente"],re:/pagar (a )?encomenda|pagar agora|referencia multibanco/,
      fazer:()=>({texto:"A abrir os pagamentos. Escolha a encomenda e pague por Multibanco ou MB WAY; o valor é sempre o calculado pelo servidor.",go:pagina("cliente","payments")})},
    {papeis:["cliente"],re:/(os meus |meus )?documentos|faturas?$|ver fatura/,
      fazer:()=>({texto:"A abrir os seus documentos: faturas certificadas e ficheiros das encomendas.",go:pagina("cliente","documents")})},
    {papeis:["cliente"],re:/pedir cotac|sem preco|aguardar tarifa/,
      fazer:()=>({texto:"Na simulação, os prestadores sem tarifa aparecem com «Pedir cotação». Escolha-o e crie o envio: o prestador indica o preço e é notificado quando aceitar."})}
  ];
})();
