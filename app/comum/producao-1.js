/* Elolog — produção 1/3: janela em etapas (comum), documentos no armazenamento do servidor e navios em tempo real (AIS).
   Sem servidor configurado (modo de demonstração) tudo continua a funcionar como antes, no navegador. */
(function(){
  const S=()=>window.ELOLogServidor, online=()=>!!(S()&&S().ativo&&S().ativo()&&S().cliente);
  const esc=v=>String(v==null?"":v).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
  const aviso=(m,t)=>typeof showPlatformNotice==="function"?showPlatformNotice(m,t||"info"):alert(m);
  const euros=v=>Number(v||0).toLocaleString("pt-PT",{style:"currency",currency:"EUR"});

  /* ---------- janela em etapas: passos visíveis, foco preso, Esc fecha ---------- */
  function janela({eyebrow,titulo,passos}){
    document.getElementById("pmJanela")?.remove();
    const f=document.createElement("div");f.id="pmJanela";f.className="pm-fundo";
    f.innerHTML=`<div class="pm-caixa" role="dialog" aria-modal="true" aria-labelledby="pmTitulo"><header class="pm-topo"><div><small>${esc(eyebrow)}</small><h3 id="pmTitulo" tabindex="-1">${esc(titulo)}</h3></div><button type="button" class="pm-fechar" aria-label="Fechar">×</button></header>${passos?`<ol class="pm-passos">${passos.map((p,i)=>`<li data-i="${i}"><b>${i+1}</b>${esc(p)}</li>`).join("")}</ol>`:""}<div class="pm-corpo"></div><footer class="pm-rodape"></footer></div>`;
    document.body.appendChild(f);const antes=document.activeElement;
    const fechar=()=>{f.remove();document.removeEventListener("keydown",tecla);antes?.focus?.()};
    const tecla=e=>{if(e.key==="Escape")fechar();if(e.key==="Tab"){const it=[...f.querySelectorAll("button,input,select,textarea,a[href]")].filter(x=>!x.disabled&&x.offsetParent);if(!it.length)return;
      const a=it[0],z=it[it.length-1];if(e.shiftKey&&document.activeElement===a){e.preventDefault();z.focus()}else if(!e.shiftKey&&document.activeElement===z){e.preventDefault();a.focus()}}};
    document.addEventListener("keydown",tecla);f.querySelector(".pm-fechar").onclick=fechar;f.addEventListener("click",e=>{if(e.target===f)fechar()});
    const api={fechar,corpo:f.querySelector(".pm-corpo"),
      passo(i){f.querySelectorAll(".pm-passos li").forEach((li,k)=>{li.className=k<i?"feito":k===i?"agora":"";li.toggleAttribute("aria-current",k===i)})},
      mostrar(html,botoes){api.corpo.innerHTML=html;const r=f.querySelector(".pm-rodape");r.innerHTML="";(botoes||[]).forEach(b=>{const x=document.createElement("button");x.type="button";
        x.className=b.principal?"btn-primary":"btn-secondary";x.textContent=b.texto;x.onclick=async()=>{if(x.disabled)return;x.disabled=true;window.elologBotao?.carregar(x,true);try{await b.acao(x)}finally{if(x.isConnected){x.disabled=false;window.elologBotao?.carregar(x,false)}}};r.appendChild(x)});
        setTimeout(()=>(api.corpo.querySelector("input:not([type=radio]):not([readonly]),select,textarea")||f.querySelector("#pmTitulo"))?.focus({preventScroll:true}),30)}};
    return api}

  /* ---------- servidor: utilidades partilhadas ---------- */
  async function sb(){return S().cliente()}
  async function utilizador(){const c=await sb();const{data}=await c.auth.getUser();return data.user||null}
  async function minhaEmpresa(){const c=await sb(),u=await utilizador();if(!u)return null;const{data}=await c.from("funcionarios").select("empresa_id,papel").eq("id",u.id).maybeSingle();return data}
  async function encomendaPorCodigo(codigo){if(!codigo)return null;const c=await sb();const{data}=await c.from("encomendas").select("id,codigo,cliente_id,cliente_nif,preco_total,empresa_id").eq("codigo",codigo).maybeSingle();return data}
  const nomeSeguro=n=>String(n||"documento").normalize("NFD").replace(/[̀-ͯ]/g,"").replace(/[^\w.-]+/g,"_").slice(-80);
  /** Envia o ficheiro para o armazenamento privado e regista-o em «documentos». Devolve a linha criada. */
  async function enviarDocumento(file,{encomenda,categoria,visibilidade}={}){
    if(!file)throw new Error("Escolha um ficheiro.");if(file.size>20*1024*1024)throw new Error("O ficheiro passa de 20 MB.");
    const c=await sb(),u=await utilizador();if(!u)throw new Error("Inicie sessão novamente.");const emp=await minhaEmpresa();const en=await encomendaPorCodigo(encomenda);
    if(encomenda&&!en)throw new Error("Não encontrámos a encomenda "+encomenda+".");
    const dono=emp?.empresa_id||u.id,caminho=`${dono}/${en?en.codigo+"/":""}${Date.now()}-${nomeSeguro(file.name)}`;
    const up=await c.storage.from("documentos").upload(caminho,file,{contentType:file.type||"application/octet-stream",upsert:false});if(up.error)throw new Error(/row-level security|policy|403|Unauthorized/i.test(up.error.message||"")?"O espaço de ficheiros do plano está esgotado. Peça à equipa Elolog para mudar de plano.":"O ficheiro não foi aceite: "+(up.error.message||"formato ou tamanho"));window.elologEspaco?.atualizar?.();
    const linha={categoria:categoria||"outro",nome:file.name.slice(0,200),visibilidade:visibilidade||(emp?"interna":"cliente"),storage_path:caminho,mime:file.type||null,tamanho_bytes:file.size,enviado_por:u.id,encomenda_id:en?.id||null};
    if(emp)linha.empresa_id=emp.empresa_id;else linha.cliente_id=u.id;
    const{data,error}=await c.from("documentos").insert(linha).select().single();if(error)throw new Error("O documento não ficou registado: "+error.message);return data}
  async function abrirDocumento(caminho,nome){const c=await sb();const{data,error}=await c.storage.from("documentos").createSignedUrl(caminho,120,{download:nome||true});
    if(error)throw new Error("Não foi possível abrir o documento.");const a=document.createElement("a");a.href=data.signedUrl;a.rel="noopener";document.body.appendChild(a);a.click();a.remove()}
  window.elologProducao={online,janela,esc,aviso,euros,sb,utilizador,minhaEmpresa,encomendaPorCodigo,enviarDocumento,abrirDocumento};

  /* ---------- documentos do cliente: com servidor vão para o armazenamento ---------- */
  function ligarDocumentos(){
    const enviar=window.enviarDocumentoCliente;if(typeof enviar==="function")window.enviarDocumentoCliente=async function(){if(!online())return enviar.apply(this,arguments);
      const file=document.getElementById("clientDocumentFile")?.files?.[0],cod=document.getElementById("clientDocumentOrder")?.value.trim();
      if(!window.eloValidar?.(["clientDocumentOrder"]))return;if(!file)return aviso("Escolha o ficheiro a enviar.","warning");
      try{await enviarDocumento(file,{encomenda:cod,categoria:"cliente",visibilidade:"cliente"});document.getElementById("clientDocumentFile").value="";aviso("Documento enviado e guardado em segurança.","success");listaServidor()}catch(e){aviso(e.message,"error")}};
    const desenhar=window.renderDocuments;if(typeof desenhar==="function")window.renderDocuments=function(){const r=desenhar.apply(this,arguments);if(online())listaServidor();return r}}
  async function listaServidor(){const alvo=document.getElementById("documentsList");if(!alvo)return;
    try{const c=await sb();const{data}=await c.from("documentos").select("id,nome,categoria,storage_path,created_at,encomenda_id").order("created_at",{ascending:false}).limit(50);
      let box=document.getElementById("pmDocsServidor");if(!box){box=document.createElement("section");box.id="pmDocsServidor";box.className="pm-lista";alvo.after(box)}
      box.innerHTML=`<h4>Documentos guardados</h4>${(data||[]).length?(data||[]).map(d=>`<div class="pm-linha"><div><strong>${esc(d.nome)}</strong><small>${d.categoria==="fatura"?"Fatura certificada · ":""}${new Date(d.created_at).toLocaleDateString("pt-PT")}</small></div><button type="button" class="btn-secondary" data-caminho="${esc(d.storage_path)}" data-nome="${esc(d.nome)}">Descarregar</button></div>`).join(""):'<p class="pm-vazio">Ainda não há documentos guardados no servidor.</p>'}`;
      box.querySelectorAll("[data-caminho]").forEach(b=>b.onclick=()=>abrirDocumento(b.dataset.caminho,b.dataset.nome).catch(e=>aviso(e.message,"error")))}catch(e){}}

  /* ---------- navios em tempo real ---------- */
  async function navios(){const j=janela({eyebrow:"ARMAZÉM · TRANSPORTE MARÍTIMO",titulo:"Navios em tempo real"});
    if(!online()){j.mostrar('<p>Os navios em tempo real precisam do servidor. No modo de demonstração use o <b>Mapa marítimo</b>.</p>',[{texto:"Fechar",acao:j.fechar}]);return}
    const c=await sb(),emp=await minhaEmpresa();
    const desenhar=async()=>{const[{data:seg},{data:pos}]=await Promise.all([c.from("navios_seguidos").select("*").order("nome"),c.from("navios_posicoes").select("*")]);const P=Object.fromEntries((pos||[]).map(p=>[p.mmsi,p]));
      const lin=(seg||[]).map(s=>{const p=P[s.mmsi]||{},mapa=p.latitude!=null?`https://www.openstreetmap.org/?mlat=${p.latitude}&mlon=${p.longitude}#map=7/${p.latitude}/${p.longitude}`:"";
        return`<tr><td data-label="Navio"><strong>${esc(s.nome)}</strong><small>MMSI ${esc(s.mmsi)}${s.viagem?" · "+esc(s.viagem):""}</small></td><td data-label="Posição">${p.latitude!=null?`${p.latitude.toFixed(3)}, ${p.longitude.toFixed(3)}`:"à espera do 1.º sinal"}</td><td data-label="Velocidade">${p.velocidade_nos!=null?p.velocidade_nos+" nós":"—"}</td><td data-label="Destino">${esc(p.destino||"—")}</td><td data-label="ETA">${p.eta?new Date(p.eta).toLocaleString("pt-PT",{dateStyle:"short",timeStyle:"short"}):"—"}</td><td data-label="Atualizado">${p.atualizado_em?new Date(p.atualizado_em).toLocaleString("pt-PT",{dateStyle:"short",timeStyle:"short"}):"—"}</td><td>${mapa?`<a class="btn-secondary" href="${mapa}" target="_blank" rel="noopener">Ver no mapa</a>`:""} <button type="button" class="btn-secondary" data-tirar="${esc(s.mmsi)}">Deixar de seguir</button></td></tr>`}).join("");
      j.mostrar(`<p class="pm-nota">Dados AIS do aisstream.io, atualizados a cada 30 minutos. O MMSI (9 dígitos) está no certificado do navio ou em sites de rastreio.</p>
        <div class="pm-grelha"><label>Nome do navio<input id="pmNavNome" maxlength="80" placeholder="Ex.: Sao Tome Express"></label><label>MMSI<input id="pmNavMmsi" inputmode="numeric" maxlength="9" placeholder="9 dígitos"></label><label>Viagem (opcional)<input id="pmNavViagem" maxlength="40"></label></div>
        ${lin?`<table class="pm-tabela"><thead><tr><th>Navio</th><th>Posição</th><th>Velocidade</th><th>Destino</th><th>ETA</th><th>Atualizado</th><th></th></tr></thead><tbody>${lin}</tbody></table>`:'<p class="pm-vazio">Ainda não segue nenhum navio.</p>'}`,
        [{texto:"Fechar",acao:j.fechar},{texto:"Seguir navio",principal:true,acao:async()=>{const nome=document.getElementById("pmNavNome").value.trim(),mmsi=document.getElementById("pmNavMmsi").value.replace(/\D/g,"");
          if(!window.eloValidar(["pmNavNome","pmNavMmsi"]))return;if(!/^\d{9}$/.test(mmsi))return aviso("O MMSI tem 9 dígitos.","warning");
          const{error}=await c.from("navios_seguidos").insert({empresa_id:emp?.empresa_id,mmsi,nome,viagem:document.getElementById("pmNavViagem").value.trim()||null});
          if(error)return aviso(error.code==="23505"?"Este navio já está a ser seguido.":"Não foi possível seguir o navio.","error");aviso("Navio adicionado. A posição aparece na próxima atualização.","success");desenhar()}}]);
      j.corpo.querySelectorAll("[data-tirar]").forEach(b=>b.onclick=async()=>{await c.from("navios_seguidos").delete().eq("mmsi",b.dataset.tirar);desenhar()})};
    try{await desenhar()}catch(e){j.mostrar('<p>Não foi possível ler os navios.</p>',[{texto:"Fechar",acao:j.fechar}])}}
  window.elologNavios={abrir:navios};
  /* ---------- regresso do email de confirmação da conta ---------- */
  function confirmacao(){const r=window.ELOLOG_RETORNO||location,h=new URLSearchParams(String(r.hash||"").replace(/^#/,"")),q=new URLSearchParams(r.search||"");
    if(h.get("error")||h.get("error_code"))aviso(/expired/i.test(h.get("error_code")||h.get("error_description")||"")?"O link de confirmação expirou. Peça um novo email ao iniciar sessão.":"Não foi possível confirmar a conta com este link.","error");
    else if(q.get("confirmado")==="1"||h.get("type")==="signup")aviso("Email confirmado. Já pode iniciar sessão com o seu email e palavra-passe.","success");else return;
    if(location.search||location.hash)history.replaceState(null,"",location.pathname)}
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",()=>{ligarDocumentos();confirmacao()});else{ligarDocumentos();confirmacao()}
})();
