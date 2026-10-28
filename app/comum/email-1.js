/* Elolog — painel de email 1/2: abrir, caixas, pastas, lista de mensagens e leitura.
   Só para o administrador da plataforma (caixas da Elolog) e o administrador de cada prestador (caixas da empresa).
   Servidor: Edge Function «email-caixa» (IMAP/SMTP). A palavra-passe da caixa fica no cofre do servidor e nunca chega ao navegador.
   Sem servidor (modo de demonstração) usa uma caixa de exemplo guardada só nesta página. */
(function(){
  const P=()=>window.elologProducao,esc=v=>P().esc(v);
  const E=window.__elologEmail={caixas:[],caixa:"",pasta:"entrada",pagina:0,pesquisa:"",lista:null,aberta:null,erro:"",j:null,elolog:false,empresa:false};
  const PASTAS=[["entrada","Entrada"],["enviados","Enviados"],["lixo","Lixo"]];
  const agora=Date.now(),h=n=>new Date(agora-n*36e5).toISOString();
  const DEMO={caixas:[{id:"demo",email:"contacto@elolog.pt",nome:"Elolog — Contacto",imap_host:"imap.correio.pt",smtp_host:"smtp.correio.pt",utilizador:"contacto@elolog.pt",elolog:true,tem_senha:true}],
    entrada:[{uid:3,de:"Importadora Atlântico <compras@atlantico.ao>",para:"contacto@elolog.pt",assunto:"Pedido de cotação Leixões → Luanda",data:h(1),lida:false,anexos:true,
        texto:"Bom dia,\n\nPrecisamos de enviar 2 paletes (1,8 m³) de Leixões para Luanda até ao fim do mês.\nPodem indicar prazo e preço?\n\nObrigado,\nMarta Silva",anexos_l:[{indice:0,nome:"lista-de-carga.pdf",tipo:"application/pdf",tamanho:48213}]},
      {uid:2,de:"Luso Freight <ops@lusofreight.pt>",para:"contacto@elolog.pt",assunto:"Documentação do navio MSC Lisboa",data:h(20),lida:true,texto:"Olá equipa Elolog,\n\nO manifesto já foi enviado pela plataforma.\n\nCumprimentos,\nLuso Freight"},
      {uid:1,de:"Cliente de demonstração <cliente@exemplo.pt>",para:"contacto@elolog.pt",assunto:"Obrigado pela entrega",data:h(60),lida:true,html:"<p>A encomenda <b>TR-2026-000123</b> chegou em perfeitas condições.</p><p>Obrigado!</p>"}],enviados:[],lixo:[]};
  const online=()=>P()?.online();
  E.chamar=async(acao,dados={})=>window.ELOLogServidor.chamarFuncao("email-caixa",{acao,...dados});
  E.demo=DEMO;E.online=online;

  const quando=d=>{if(!d)return"";const t=new Date(d),hoje=new Date();return t.toDateString()===hoje.toDateString()?t.toLocaleTimeString("pt-PT",{hour:"2-digit",minute:"2-digit"}):t.toLocaleDateString("pt-PT",{day:"2-digit",month:"short"})};
  E.nome=s=>{const m=String(s||"").match(/^\s*"?([^"<]*?)"?\s*<([^>]+)>/);return m?(m[1]||m[2]):String(s||"")};
  E.endereco=s=>(String(s||"").match(/<([^>]+)>/)?.[1]||String(s||"").match(/[^\s<>",;]+@[^\s<>",;]+/)?.[0]||"").toLowerCase();
  E.quando=quando;

  function lado(){const c=E.caixas.find(x=>x.id===E.caixa),l=E.lista;
    const itens=!E.caixas.length?"":l==null?`<li class="em-vazio">${E.erro?"⚠ "+esc(E.erro):"A carregar…"}</li>`:!l.mensagens.length?`<li class="em-vazio">${E.pesquisa?"Nada encontrado.":"Sem mensagens nesta pasta."}</li>`:
      l.mensagens.map(m=>`<li><button type="button" class="em-item${m.lida?"":" em-nova"}${E.aberta?.uid===m.uid?" em-atual":""}" data-em-abrir="${m.uid}">
        <span class="em-quem">${esc(E.nome(E.pasta==="enviados"?"Para: "+m.para:m.de))}</span><time>${quando(m.data)}</time>
        <span class="em-assunto">${m.respondida?'<i title="Respondida">↩</i> ':""}${esc(m.assunto||"(sem assunto)")}${m.anexos?' <i title="Tem anexos">📎</i>':""}</span></button></li>`).join("");
    const pags=l&&l.total>25?`<div class="em-pags"><button type="button" class="btn-secondary" data-em-pag="-1" ${E.pagina?"":"disabled"}>‹ Mais recentes</button><small>${E.pagina*25+1}–${Math.min(l.total,E.pagina*25+25)} de ${l.total}</small><button type="button" class="btn-secondary" data-em-pag="1" ${(E.pagina+1)*25<l.total?"":"disabled"}>Mais antigas ›</button></div>`:"";
    return`<div class="em-caixas">${E.caixas.length?`<label class="sr-only" for="emCaixa">Caixa de email</label><select id="emCaixa">${E.caixas.map(x=>`<option value="${esc(x.id)}"${x.id===E.caixa?" selected":""}>${esc(x.email)}</option>`).join("")}</select>`:""}
      <button type="button" class="btn-secondary" data-em="config" title="Configurar caixas" aria-label="Configurar caixas de email">⚙</button></div>
      ${c?`<div class="em-pastas" role="tablist" aria-label="Pastas">${PASTAS.map(([k,t])=>`<button type="button" role="tab" aria-selected="${E.pasta===k}" class="${E.pasta===k?"ativo":""}" data-em-pasta="${k}">${t}</button>`).join("")}</div>
      <form class="em-procura" role="search"><input type="search" id="emProcura" placeholder="Procurar no email" aria-label="Procurar no email" value="${esc(E.pesquisa)}"></form>
      <ul class="em-lista" aria-label="Mensagens">${itens}</ul>${pags}`:`<p class="em-vazio">Ainda não há caixas ligadas. Use <b>⚙</b> para ligar a primeira.</p>`}`}

  E.desenhar=function(){if(!E.j)return;const raiz=E.j.corpo.querySelector(".em");if(!raiz)return;
    raiz.querySelector(".em-lado").innerHTML=lado();raiz.classList.toggle("em-a-ler",!!E.vista);
    const d=raiz.querySelector(".em-ler");if(!E.vista){d.innerHTML=`<div class="em-boas"><span aria-hidden="true">✉</span><p>${E.caixas.length?"Escolha uma mensagem para ler ou escreva um novo email.":"Ligue uma caixa de email para começar."}</p></div>`;return}
    window.elologEmail2?.vista(d)};

  E.carregarLista=async function(){E.lista=null;E.erro="";E.desenhar();
    if(!online()){const t=E.pesquisa.toLowerCase(),l=DEMO[E.pasta].filter(m=>!t||(m.de+m.assunto+(m.texto||"")).toLowerCase().includes(t));E.lista={total:l.length,mensagens:l};return E.desenhar()}
    try{E.lista=await E.chamar("listar",{caixa:E.caixa,pasta:E.pasta,pagina:E.pagina,pesquisa:E.pesquisa})}catch(e){E.erro=e.message;E.lista=null}E.desenhar()};
  E.carregarCaixas=async function(){
    if(!online()){E.caixas=DEMO.caixas;E.elolog=currentUser?.role==="admin";E.empresa=!E.elolog}
    else{try{const r=await E.chamar("caixas");E.caixas=r.caixas||[];E.elolog=r.elolog;E.empresa=r.empresa}catch(e){E.caixas=[];E.erro=e.message;E.desenhar();return false}}
    if(!E.caixas.some(x=>x.id===E.caixa))E.caixa=E.caixas[0]?.id||"";return true};
  E.abrirMensagem=async function(uid){const m=E.lista?.mensagens.find(x=>x.uid===uid);if(!m)return;E.vista="ler";E.aberta={uid,carregando:true,assunto:m.assunto,de:m.de};E.desenhar();
    if(!online()){m.lida=true;E.aberta={...m,cc:"",anexos:m.anexos_l||[],message_id:`<demo-${uid}@exemplo.pt>`};return E.desenhar()}
    try{const r=await E.chamar("ler",{caixa:E.caixa,pasta:E.pasta,uid});E.aberta=r.mensagem;m.lida=true}catch(e){E.aberta={uid,erro:e.message,assunto:m.assunto,de:m.de}}E.desenhar()};

  async function abrir(){if(!["admin","prestador"].includes(currentUser?.role))return P().aviso("O email está disponível só para administradores.","warning");
    E.j=P().janela({eyebrow:currentUser.role==="admin"?"ADMINISTRAÇÃO ELOLOG":"PRESTADOR",titulo:"Email"});E.j.corpo.closest(".pm-caixa").classList.add("em-janela");
    const topo=E.j.corpo.closest(".pm-caixa").querySelector(".pm-topo");topo.querySelector(".pm-fechar").insertAdjacentHTML("beforebegin",'<button type="button" class="btn-primary em-novo" data-em="novo">✎ Novo email</button>');
    E.j.mostrar('<div class="em"><aside class="em-lado"></aside><section class="em-ler" aria-live="polite"></section></div>',[]);E.vista=null;E.aberta=null;E.lista=null;E.desenhar();
    if(!(await E.carregarCaixas()))return;if(!E.caixas.length){E.vista="config";return E.desenhar()}E.carregarLista()}

  document.addEventListener("click",e=>{if(!e.target.closest?.("#pmJanela .em-janela"))return;const b=e.target.closest("[data-em-abrir],[data-em-pasta],[data-em-pag],[data-em]");if(!b)return;
    if(b.dataset.emAbrir)return E.abrirMensagem(Number(b.dataset.emAbrir));
    if(b.dataset.emPasta){E.pasta=b.dataset.emPasta;E.pagina=0;E.vista=null;E.aberta=null;return E.carregarLista()}
    if(b.dataset.emPag){E.pagina=Math.max(0,E.pagina+Number(b.dataset.emPag));return E.carregarLista()}
    window.elologEmail2?.acao(b.dataset.em,b)});
  document.addEventListener("change",e=>{if(e.target.id==="emCaixa"){E.caixa=e.target.value;E.pagina=0;E.vista=null;E.aberta=null;E.carregarLista()}});
  document.addEventListener("submit",e=>{if(e.target.matches?.(".em-procura")){e.preventDefault();E.pesquisa=document.getElementById("emProcura").value.trim();E.pagina=0;E.carregarLista()}});
  window.elologEmail={abrir};
})();
