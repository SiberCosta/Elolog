/* Elolog — chat interno da equipa (v71): conversas e grupos entre funcionários da mesma organização.
   A equipa Elolog só fala entre si; cada prestador só dentro da sua empresa (a administração não vê o chat dos prestadores).
   Dentro da organização todos falam com todos e qualquer funcionário pode criar grupos e adicionar colegas.
   Servidor: rpc chat_contactos, chat_conversa, chat_enviar, chat_grupos, chat_grupo_criar/adicionar/sair/conversa/enviar, chat_por_ler.
   A conversa aberta atualiza-se a cada 4 s; o contador do menu a cada 30 s. Sem servidor usa dados de exemplo nesta página. */
(function(){
  const P=()=>window.elologProducao,esc=v=>P().esc(v);
  const FUNCAO={admin:"Administrador",operador:"Operador",apoio:"Apoio",admin_empresa:"Administrador",operador_terreno:"Terreno",armazem:"Armazém",financeiro:"Financeiro"};
  const C={j:null,contactos:null,grupos:[],atual:null,msgs:[],erro:"",eu:null,assin:"",form:null};let ultimo=null,parar=false;
  const online=()=>!!P()?.online()&&currentUser?.authenticatedBy!=="local-demo";
  const rpc=async(nome,args)=>{const c=await window.ELOLogServidor.cliente();if(!C.eu){const{data}=await c.auth.getUser();C.eu=data.user?.id}
    const{data,error}=await c.rpc(nome,args||{});if(error)throw new Error(window.ELOLogServidor.mensagem?.(error)||error.message);return data};
  const agora=Date.now(),iso=n=>new Date(agora-n).toISOString();
  const DEMO={admin:[{user_id:"d-ana",nome:"Ana Claudia Liima",papel:"operador",organizacao:"Elolog",por_ler:1,ultima:"A recolha de Leixões ficou para amanhã.",ultima_em:iso(9e5)},
      {user_id:"d-rui",nome:"Rui Apoio",papel:"apoio",organizacao:"Elolog",por_ler:0}],
    prestador:[{user_id:"d-adm",nome:"Administrador Transatlântico",papel:"admin_empresa",organizacao:"Transatlântico Demo, Lda.",por_ler:1,ultima:"Confirmem a recolha das 10h.",ultima_em:iso(6e5)},
      {user_id:"d-fin",nome:"Financeiro Transatlântico",papel:"financeiro",organizacao:"Transatlântico Demo, Lda.",por_ler:0},{user_id:"d-arm",nome:"Armazém Transatlântico",papel:"armazem",organizacao:"Transatlântico Demo, Lda.",por_ler:0}],
    grupos:{admin:[],prestador:[{id:"g-1",nome:"Recolhas Leixões",membros:3,por_ler:0,nomes:"Administrador Transatlântico, Armazém Transatlântico",ultima:"Camião sai às 9h.",ultima_em:iso(3e6)}]},
    msgs:{"p:d-adm":[{id:"m2",de:"d-adm",texto:"Confirmem a recolha das 10h.",created_at:iso(6e5)}],"p:d-ana":[{id:"m1",de:"d-ana",texto:"A recolha de Leixões ficou para amanhã.",created_at:iso(9e5)}],
      "g:g-1":[{id:"m3",de:"d-arm",nome_de:"Armazém Transatlântico",texto:"Camião sai às 9h.",created_at:iso(3e6)}]}};
  const perfil=()=>currentUser?.role==="prestador"?"prestador":"admin";
  const hora=d=>{const t=new Date(d);return t.toDateString()===new Date().toDateString()?t.toLocaleTimeString("pt-PT",{hour:"2-digit",minute:"2-digit"}):t.toLocaleString("pt-PT",{day:"2-digit",month:"short",hour:"2-digit",minute:"2-digit"})};
  const iniciais=n=>String(n||"?").split(/\s+/).map(x=>x[0]).slice(0,2).join("").toUpperCase();
  const chave=a=>a?(a.tipo==="grupo"?"g:":"p:")+a.id:"";

  const item=(k,nome,sub,n,grupo)=>`<li><button type="button" class="ch-contacto${chave(C.atual)===k?" ch-atual":""}" data-ch="${esc(k)}">
    <span class="ch-av${grupo?" ch-av-grupo":""}" aria-hidden="true">${grupo?"👥":esc(iniciais(nome))}</span><span class="ch-txt"><b>${esc(nome)}</b><small>${esc(sub)}</small></span>
    ${n?`<span class="em-contador" aria-label="${n} por ler">${n}</span>`:""}</button></li>`;
  function lista(){const l=C.contactos;if(l==null)return`<p class="em-vazio">${C.erro?"⚠ "+esc(C.erro):"A carregar a equipa…"}</p>`;
    const org=l[0]?.organizacao||"Equipa";
    return`<div class="ch-grupos-topo"><h5 class="ch-org">Grupos</h5><button type="button" class="btn-secondary ch-novo" data-ch-acao="novo">+ Novo grupo</button></div>
      ${C.grupos.length?`<ul class="ch-lista">${C.grupos.map(g=>item("g:"+g.id,g.nome,g.ultima||`${g.membros} membros`,g.por_ler,true)).join("")}</ul>`:'<p class="em-vazio ch-pouco">Ainda não pertence a nenhum grupo.</p>'}
      <h5 class="ch-org">${esc(org)}</h5>${l.length?`<ul class="ch-lista">${l.map(x=>item("p:"+x.user_id,x.nome,x.ultima||FUNCAO[x.papel]||x.papel,x.por_ler)).join("")}</ul>`:'<p class="em-vazio">Ainda não há colegas na equipa.</p>'}`}

  const minha=m=>C.atual?.tipo==="grupo"?(m.de===C.eu||m.de==="eu"):m.de!==C.atual?.id;
  const msgsHtml=()=>C.msgs.length?C.msgs.map(m=>`<div class="ch-msg${minha(m)?" ch-minha":""}">${C.atual?.tipo==="grupo"&&!minha(m)?`<b class="ch-autor">${esc(m.nome_de||"")}</b>`:""}<p>${esc(m.texto)}</p><time>${hora(m.created_at)}</time></div>`).join(""):'<p class="em-vazio">Ainda não há mensagens. Escreva a primeira.</p>';
  function formGrupo(){const f=C.form,ja=new Set(f.membros||[]),l=(C.contactos||[]).filter(x=>!ja.has(x.user_id));
    return`<div class="em-form ch-form-grupo"><button type="button" class="btn-secondary em-voltar-cfg" data-ch-acao="fechar">‹ Voltar</button><h4 class="em-titulo">${f.tipo==="novo"?"Novo grupo":"Adicionar ao grupo «"+esc(C.atual?.nome||"")+"»"}</h4>
      ${f.tipo==="novo"?'<label>Nome do grupo<input id="chGrupoNome" type="text" maxlength="80" placeholder="Ex.: Recolhas Leixões"></label>':""}
      <fieldset class="ch-membros"><legend>Colegas</legend>${l.length?l.map(x=>`<label class="pm-opcao"><input type="checkbox" value="${esc(x.user_id)}"> ${esc(x.nome)} <small>${esc(FUNCAO[x.papel]||x.papel)}</small></label>`).join(""):'<p class="em-vazio">Todos os colegas já estão no grupo.</p>'}</fieldset>
      <div class="em-acoes"><button type="button" class="btn-secondary" data-ch-acao="fechar">Cancelar</button><button type="button" class="btn-primary" data-ch-acao="${f.tipo==="novo"?"criar":"adicionar-ok"}">${f.tipo==="novo"?"Criar grupo":"Adicionar"}</button></div></div>`}
  function conversa(){if(C.form)return formGrupo();const a=C.atual;if(!a)return'<div class="em-boas"><span aria-hidden="true">💬</span><p>Escolha um colega ou um grupo para conversar.</p></div>';
    const g=a.tipo==="grupo";
    return`<header class="ch-topo"><button type="button" class="btn-secondary em-voltar" data-ch-voltar>‹ Voltar</button><span class="ch-av${g?" ch-av-grupo":""}" aria-hidden="true">${g?"👥":esc(iniciais(a.nome))}</span>
      <div><b>${esc(a.nome)}</b><small>${g?esc(`${a.membros} membros · ${a.nomes||""}`):esc(`${FUNCAO[a.papel]||a.papel} · ${a.organizacao}`)}</small></div>
      ${g?'<span class="ch-topo-acoes"><button type="button" class="btn-secondary" data-ch-acao="adicionar">+ Pessoas</button><button type="button" class="btn-danger" data-ch-acao="sair">Sair</button></span>':""}</header>
      <div class="ch-msgs" aria-live="polite">${msgsHtml()}</div>
      <form class="ch-form"><label class="sr-only" for="chTexto">Mensagem</label><textarea id="chTexto" rows="2" maxlength="2000" placeholder="Escreva uma mensagem… (Enter envia)"></textarea><button type="submit" class="btn-primary">Enviar</button></form>`}

  function desenhar(soMsgs){const r=C.j?.corpo.querySelector(".ch");if(!r)return;r.classList.toggle("em-a-ler",!!(C.atual||C.form));r.querySelector(".em-lado").innerHTML=lista();
    const d=r.querySelector(".em-ler");if(soMsgs&&!C.form&&d.querySelector(".ch-msgs"))d.querySelector(".ch-msgs").innerHTML=msgsHtml();else d.innerHTML=conversa();
    const m=d.querySelector(".ch-msgs");if(m)m.scrollTop=m.scrollHeight;if(!soMsgs)d.querySelector("#chTexto,#chGrupoNome")?.focus()}

  async function carregar(){try{if(online()){const[c,g]=await Promise.all([rpc("chat_contactos"),rpc("chat_grupos")]);C.contactos=c;C.grupos=g}
      else{C.contactos=DEMO[perfil()];C.grupos=DEMO.grupos[perfil()]}C.erro="";if(C.atual?.tipo==="grupo"){const g=C.grupos.find(x=>x.id===C.atual.id);if(g)Object.assign(C.atual,g)}}
    catch(e){C.erro=e.message;C.contactos=null}}
  async function abrirConversa(k,silencioso){const[t,id]=[k.slice(0,1),k.slice(2)],grupo=t==="g",a=grupo?C.grupos.find(x=>x.id===id):(C.contactos||[]).find(x=>x.user_id===id);if(!a)return;
    C.form=null;C.atual={...a,tipo:grupo?"grupo":"pessoa",id};
    if(!online()){a.por_ler=0;C.msgs=DEMO.msgs[k]||(DEMO.msgs[k]=[]);return desenhar(silencioso)}
    try{const m=grupo?await rpc("chat_grupo_conversa",{p_grupo:id}):await rpc("chat_conversa",{p_com:id}),s=m.map(x=>x.id).join();if(silencioso&&s===C.assin)return;C.assin=s;C.msgs=m;a.por_ler=0}
    catch(e){if(!silencioso)P().aviso(e.message,"error")}
    desenhar(silencioso);contar()}
  async function enviar(){const t=document.getElementById("chTexto"),texto=t?.value.trim(),a=C.atual;if(!texto||!a)return;t.value="";
    try{if(online())C.msgs.push(await rpc(a.tipo==="grupo"?"chat_grupo_enviar":"chat_enviar",a.tipo==="grupo"?{p_grupo:a.id,p_texto:texto}:{p_para:a.id,p_texto:texto}));
      else C.msgs.push({id:"m"+Date.now(),de:"eu",texto,created_at:new Date().toISOString()});
      const o=a.tipo==="grupo"?C.grupos.find(x=>x.id===a.id):C.contactos.find(x=>x.user_id===a.id);if(o)o.ultima=texto;C.assin=C.msgs.map(x=>x.id).join();desenhar(true)}
    catch(e){t.value=texto;P().aviso(e.message,"error")}}
  async function acaoGrupo(nome){const marcados=()=>[...document.querySelectorAll(".ch-membros input:checked")].map(x=>x.value);
    try{if(nome==="novo"){C.form={tipo:"novo"};return desenhar()}
      if(nome==="adicionar"){C.form={tipo:"adicionar",membros:[]};return desenhar()}
      if(nome==="fechar"){C.form=null;return desenhar()}
      if(nome==="criar"){const n=document.getElementById("chGrupoNome").value.trim(),m=marcados();if(!n)return P().aviso("Dê um nome ao grupo.","warning");if(!m.length)return P().aviso("Escolha pelo menos um colega.","warning");
        let id="g-"+Date.now();if(online())id=await rpc("chat_grupo_criar",{p_nome:n,p_membros:m});else DEMO.grupos[perfil()].unshift({id,nome:n,membros:m.length+1,por_ler:0,nomes:C.contactos.filter(x=>m.includes(x.user_id)).map(x=>x.nome).join(", ")});
        C.form=null;await carregar();P().aviso(`Grupo «${n}» criado.`,"success");return abrirConversa("g:"+id)}
      if(nome==="adicionar-ok"){const m=marcados();if(!m.length)return P().aviso("Escolha pelo menos um colega.","warning");
        if(online())await rpc("chat_grupo_adicionar",{p_grupo:C.atual.id,p_membros:m});else{const g=C.grupos.find(x=>x.id===C.atual.id);if(g)g.membros+=m.length}
        C.form=null;await carregar();P().aviso("Colegas adicionados ao grupo.","success");return abrirConversa("g:"+C.atual.id)}
      if(nome==="sair"){if(!confirm(`Sair do grupo «${C.atual.nome}»?`))return;if(online())await rpc("chat_grupo_sair",{p_grupo:C.atual.id});else{const l=DEMO.grupos[perfil()];l.splice(l.findIndex(x=>x.id===C.atual.id),1)}
        C.atual=null;await carregar();return desenhar()}}
    catch(e){P().aviso(e.message,"error")}}

  async function abrir(){if(!["admin","prestador"].includes(currentUser?.role))return;C.j=P().janela({eyebrow:"EQUIPA",titulo:"Chat da equipa"});
    C.j.corpo.closest(".pm-caixa").classList.add("em-janela","ch-janela");C.j.mostrar('<div class="em ch"><aside class="em-lado"></aside><section class="em-ler ch-ler"></section></div>',[]);
    C.atual=null;C.form=null;C.msgs=[];C.contactos=null;desenhar();await carregar();desenhar()}

  document.addEventListener("click",e=>{if(!e.target.closest?.("#pmJanela .ch-janela"))return;const b=e.target.closest("[data-ch],[data-ch-acao],[data-ch-voltar]");if(!b)return;
    if(b.dataset.ch)return abrirConversa(b.dataset.ch);if(b.dataset.chAcao)return acaoGrupo(b.dataset.chAcao);C.atual=null;C.form=null;desenhar()});
  document.addEventListener("submit",e=>{if(e.target.matches?.(".ch-form")){e.preventDefault();enviar()}});
  document.addEventListener("keydown",e=>{if(e.target.id==="chTexto"&&e.key==="Enter"&&!e.shiftKey){e.preventDefault();enviar()}});

  /* Contador do menu e atualização automática. */
  const aberto=()=>!!document.querySelector("#pmJanela .ch-janela");
  function marcar(n){document.querySelectorAll('button[onclick^="elologChat.abrir"]').forEach(b=>{let c=b.querySelector(".em-contador");if(!n){c?.remove();return}
    if(!c){c=document.createElement("span");c.className="em-contador";(b.querySelector(".mi-l")||b).appendChild(c)}c.textContent=n>99?"99+":String(n);c.setAttribute("aria-label",n+" mensagens por ler")})}
  async function contar(){if(parar||!["admin","prestador"].includes(currentUser?.role)||document.visibilityState!=="visible")return;
    try{const n=online()?await rpc("chat_por_ler"):[...DEMO[perfil()],...DEMO.grupos[perfil()]].reduce((t,x)=>t+(x.por_ler||0),0);
      if(ultimo!=null&&n>ultimo&&!aberto())P().aviso(`Nova mensagem no chat da equipa (${n} por ler).`,"info");ultimo=n;marcar(n)}
    catch(e){if(/permiss|sess/i.test(e.message))parar=true}}
  setInterval(()=>{if(aberto()&&C.atual&&!C.form&&document.visibilityState==="visible")abrirConversa(chave(C.atual),true)},4e3);
  setInterval(async()=>{if(aberto()&&!C.form&&document.visibilityState==="visible"){await carregar();const r=C.j?.corpo.querySelector(".ch .em-lado");if(r)r.innerHTML=lista()}},15e3);
  setInterval(contar,3e4);setInterval(()=>{if(ultimo)marcar(ultimo)},4e3);
  if(typeof startApp==="function"){const ini=startApp;startApp=async function(){const r=await ini.apply(this,arguments);parar=false;ultimo=null;C.eu=null;setTimeout(contar,2500);return r}}
  window.elologChat={abrir,contar};
})();
