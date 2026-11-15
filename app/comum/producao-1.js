/* Elolog — produção 1/3: janela em etapas (comum), documentos no armazenamento do servidor.
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
    f.innerHTML=`<div class="pm-caixa" role="dialog" aria-modal="true" aria-labelledby="pmTitulo"><header class="pm-topo"><div>${eyebrow?`<small>${esc(/[a-zà-ú]/.test(eyebrow)?eyebrow:eyebrow.charAt(0)+eyebrow.slice(1).toLocaleLowerCase("pt-PT"))}</small>`:""}<h3 id="pmTitulo" tabindex="-1">${esc(titulo)}</h3></div><button type="button" class="pm-fechar" aria-label="Fechar">×</button></header>${passos?`<ol class="pm-passos">${passos.map((p,i)=>`<li data-i="${i}"><b>${i+1}</b>${esc(p)}</li>`).join("")}</ol>`:""}<div class="pm-corpo"></div><footer class="pm-rodape"></footer></div>`;
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
  // Regra de segurança: ficheiro não permitido = rejeitar (tem de coincidir com private.tipos_ficheiro(), migração 00151).
  const TIPOS={pdf:"application/pdf",jpg:"image/jpeg",jpeg:"image/jpeg",png:"image/png",webp:"image/webp",doc:"application/msword",xls:"application/vnd.ms-excel",
    docx:"application/vnd.openxmlformats-officedocument.wordprocessingml.document",xlsx:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"};
  const ASSIN={pdf:[[0x25,0x50,0x44,0x46,0x2d]],jpg:[[0xff,0xd8,0xff]],png:[[0x89,0x50,0x4e,0x47]],webp:[[0x52,0x49,0x46,0x46],[0x57,0x45,0x42,0x50],8],doc:[[0xd0,0xcf,0x11,0xe0]],docx:[[0x50,0x4b,0x03,0x04]]};
  ASSIN.jpeg=ASSIN.jpg;ASSIN.xls=ASSIN.doc;ASSIN.xlsx=ASSIN.docx;
  async function verificarFicheiro(file){const ext=(String(file.name).match(/\.([A-Za-z0-9]{1,5})$/)||[])[1]?.toLowerCase()||"";
    if(!TIPOS[ext])throw new Error("Ficheiro não permitido. Use PDF, JPG, PNG, WEBP, DOC, DOCX, XLS ou XLSX.");
    if(file.size<1||file.size>20*1024*1024)throw new Error("O ficheiro tem de ter entre 1 byte e 20 MB.");
    const b=new Uint8Array(await file.slice(0,16).arrayBuffer()),[s1,s2,pos]=ASSIN[ext],igual=(s,d)=>s.every((x,i)=>b[d+i]===x);
    if(!igual(s1,0)||(s2&&!igual(s2,pos)))throw new Error("Ficheiro recusado: o conteúdo não corresponde à extensão ."+ext+".");return TIPOS[ext]}
  /** Envia o ficheiro para o armazenamento privado e regista-o em «documentos». Só fica visível depois de verificado no servidor. */
  async function enviarDocumento(file,{encomenda,categoria,visibilidade}={}){
    if(!file)throw new Error("Escolha um ficheiro.");const mime=await verificarFicheiro(file);
    const c=await sb(),u=await utilizador();if(!u)throw new Error("Inicie sessão novamente.");const emp=await minhaEmpresa();const en=await encomendaPorCodigo(encomenda);
    if(encomenda&&!en)throw new Error("Não encontrámos a encomenda "+encomenda+".");
    const dono=emp?.empresa_id||u.id,caminho=`${dono}/${en?en.codigo+"/":""}${Date.now()}-${nomeSeguro(file.name)}`;
    const up=await c.storage.from("documentos").upload(caminho,file,{contentType:mime,upsert:false});if(up.error)throw new Error(/row-level security|policy|403|Unauthorized/i.test(up.error.message||"")?"O espaço de ficheiros do plano está esgotado. Peça à equipa Elolog para mudar de plano.":"O ficheiro não foi aceite: "+(up.error.message||"formato ou tamanho"));window.elologEspaco?.atualizar?.();
    const linha={categoria:categoria||"outro",nome:file.name.slice(0,200),visibilidade:visibilidade||(emp?"interna":"cliente"),storage_path:caminho,mime,tamanho_bytes:file.size,enviado_por:u.id,encomenda_id:en?.id||null};
    if(emp)linha.empresa_id=emp.empresa_id;else linha.cliente_id=u.id;
    const{data,error}=await c.from("documentos").insert(linha).select().single();if(error)throw new Error(/FICHEIRO_RECUSADO|LIMITE_EXCEDIDO/.test(error.message)?error.message.replace(/^[A-Z_]+:\s*/,""):"O documento não ficou registado: "+error.message);
    try{await window.ELOLogServidor.chamarFuncao("verificar-ficheiro",{documento_id:data.id})}catch(e){throw new Error(/recusado/i.test(e?.message||"")?e.message:"O ficheiro não pôde ser verificado e ficou bloqueado. Tente novamente mais tarde.")}
    data.verificado=true;return data}
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
      box.innerHTML=`<h4>Documentos guardados</h4>${(data||[]).length?(data||[]).map(d=>`<div class="pm-linha"><div><strong>${esc(d.nome)}</strong><small>${d.categoria==="fatura"?"Fatura certificada, ":""}${new Date(d.created_at).toLocaleDateString("pt-PT")}</small></div><button type="button" class="btn-secondary" data-caminho="${esc(d.storage_path)}" data-nome="${esc(d.nome)}">Descarregar</button></div>`).join(""):'<p class="pm-vazio">Ainda não há documentos guardados no servidor.</p>'}`;
      box.querySelectorAll("[data-caminho]").forEach(b=>b.onclick=()=>abrirDocumento(b.dataset.caminho,b.dataset.nome).catch(e=>aviso(e.message,"error")))}catch(e){}}

  /* v135: «Navios em tempo real» retirado da plataforma (pedido do dono). As tabelas navios_* ficam no servidor, sem uso. */
  /* ---------- regresso do email de confirmação da conta ---------- */
  function confirmacao(){const r=window.ELOLOG_RETORNO||location,h=new URLSearchParams(String(r.hash||"").replace(/^#/,"")),q=new URLSearchParams(r.search||"");
    if(h.get("error")||h.get("error_code"))aviso(/expired/i.test(h.get("error_code")||h.get("error_description")||"")?"O link de confirmação expirou. Peça um novo email ao iniciar sessão.":"Não foi possível confirmar a conta com este link.","error");
    else if(q.get("confirmado")==="1"||h.get("type")==="signup")aviso("Email confirmado. Já pode iniciar sessão com o seu email e palavra-passe.","success");else return;
    if(location.search||location.hash)history.replaceState(null,"",location.pathname)}
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",()=>{ligarDocumentos();confirmacao()});else{ligarDocumentos();confirmacao()}
})();
