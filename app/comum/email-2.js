/* Elolog — painel de email 2/2: ler (texto ou HTML isolado), responder, reencaminhar, apagar e configurar caixas.
   O HTML recebido é mostrado num iframe isolado (sem scripts) e com as imagens externas bloqueadas até o utilizador pedir. */
(function(){
  const P=()=>window.elologProducao,esc=v=>P().esc(v),E=()=>window.__elologEmail;
  const SERVIDORES={"elolog.pt":["imap.correio.pt","smtp.correio.pt"],"gmail.com":["imap.gmail.com","smtp.gmail.com"],"sapo.pt":["imap.sapo.pt","smtp.sapo.pt"],"outlook.com":["outlook.office365.com","smtp-mail.outlook.com"]};
  const kb=n=>n>1048576?(n/1048576).toFixed(1)+" MB":Math.max(1,Math.round(n/1024))+" KB";
  let imagens=false,rascunho=null,editar=null;
  const textoDe=m=>m.texto||(m.html?new DOMParser().parseFromString(m.html,"text/html").body.textContent.replace(/\n{3,}/g,"\n\n").trim():"");
  const citar=m=>`\n\n\nEm ${new Date(m.data||Date.now()).toLocaleString("pt-PT")}, ${m.de} escreveu:\n`+textoDe(m).split("\n").slice(0,400).map(l=>"> "+l).join("\n");
  const semPrefixo=s=>String(s||"").replace(/^((re|res|fw|fwd|enc)\s*:\s*)+/i,"");

  function iframe(m){const f=document.createElement("iframe");f.className="em-html";f.title="Conteúdo da mensagem";f.setAttribute("sandbox","allow-same-origin allow-popups allow-popups-to-escape-sandbox");f.setAttribute("referrerpolicy","no-referrer");
    f.srcdoc=`<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; font-src data:; img-src data: cid:${imagens?" https: http:":""}"><base target="_blank"><style>body{font:15px/1.5 system-ui,sans-serif;color:#0E2433;margin:4px;overflow-wrap:anywhere}img{max-width:100%;height:auto}table{max-width:100%}</style>${m.html}`;
    f.onload=()=>{try{f.style.height=Math.min(4000,f.contentDocument.documentElement.scrollHeight+20)+"px"}catch(_){f.style.height="60vh"}};return f}

  function ler(d){const m=E().aberta;if(!m)return;const c=E().caixas.find(x=>x.id===E().caixa);
    if(m.carregando||m.erro){d.innerHTML=`<button type="button" class="btn-secondary em-voltar" data-em="voltar">‹ Voltar</button><h4 class="em-titulo">${esc(m.assunto||"(sem assunto)")}</h4><p class="em-vazio">${m.erro?"⚠ "+esc(m.erro):"A abrir a mensagem…"}</p>`;return}
    const remotas=m.html&&/<img[^>]+src=["']?https?:/i.test(m.html);
    d.innerHTML=`<div class="em-acoes"><button type="button" class="btn-secondary em-voltar" data-em="voltar">‹ Voltar</button><button type="button" class="btn-primary" data-em="responder">↩ Responder</button>
      <button type="button" class="btn-secondary" data-em="todos">Responder a todos</button><button type="button" class="btn-secondary" data-em="reencaminhar">Reencaminhar</button>
      <button type="button" class="btn-secondary" data-em="naolida">Marcar não lida</button><button type="button" class="btn-danger" data-em="apagar">${E().pasta==="lixo"?"Apagar de vez":"Apagar"}</button></div>
      <h4 class="em-titulo">${esc(m.assunto||"(sem assunto)")}</h4>
      <dl class="em-cab"><dt>De</dt><dd>${esc(m.de)}</dd><dt>Para</dt><dd>${esc(m.para)}</dd>${m.cc?`<dt>Cc</dt><dd>${esc(m.cc)}</dd>`:""}<dt>Data</dt><dd>${m.data?new Date(m.data).toLocaleString("pt-PT"):"—"}</dd></dl>
      ${m.anexos?.length?`<ul class="em-anexos" aria-label="Anexos">${m.anexos.map(a=>`<li><button type="button" class="btn-secondary" data-em="anexo" data-i="${a.indice}">📎 ${esc(a.nome)} <small>${kb(a.tamanho)}</small></button></li>`).join("")}</ul>`:""}
      ${remotas&&!imagens?'<p class="em-aviso">Imagens externas bloqueadas para proteger a sua privacidade. <button type="button" class="btn-secondary" data-em="imagens">Mostrar imagens</button></p>':""}
      <div class="em-conteudo"></div>`;
    const box=d.querySelector(".em-conteudo");if(m.html)box.appendChild(iframe(m));else box.innerHTML=`<pre class="em-texto">${esc(m.texto||"(mensagem vazia)")}</pre>`;
    if(!c)d.querySelector('[data-em="responder"]').disabled=true}

  function escrever(d){const r=rascunho||{};
    d.innerHTML=`<form class="em-form" novalidate><h4 class="em-titulo">${esc(r.titulo||"Novo email")}</h4><p class="em-de">De: <b>${esc(E().caixas.find(x=>x.id===E().caixa)?.email||"")}</b></p>
      <label>Para<input id="emPara" type="text" autocomplete="off" value="${esc(r.para||"")}" placeholder="nome@empresa.pt, outro@empresa.pt"></label>
      <label>Cc<input id="emCc" type="text" autocomplete="off" value="${esc(r.cc||"")}"></label>
      <label>Assunto<input id="emAssunto" type="text" maxlength="300" value="${esc(r.assunto||"")}"></label>
      <label>Mensagem<textarea id="emTexto" rows="14">${esc(r.texto||"")}</textarea></label>
      ${r.anexosNota?'<p class="campo-ajuda">Os anexos da mensagem original não são reencaminhados.</p>':""}
      <div class="em-acoes"><button type="button" class="btn-secondary" data-em="cancelar">Cancelar</button><button type="button" class="btn-primary" data-em="enviar">Enviar</button></div></form>`;
    setTimeout(()=>{const t=document.getElementById(r.para?"emTexto":"emPara");t?.focus();if(t?.id==="emTexto")t.setSelectionRange(0,0)},30)}

  function config(d){const e=editar||{},cs=E().caixas,lista=cs.map(c=>`<li><div><b>${esc(c.email)}</b><small>${esc(c.nome||"")}${c.elolog?" · Elolog":""} · ${esc(c.imap_host)}</small></div>
      <button type="button" class="btn-secondary" data-em="editar" data-id="${esc(c.id)}">Editar</button><button type="button" class="btn-danger" data-em="remover" data-id="${esc(c.id)}">Remover</button></li>`).join("");
    d.innerHTML=`<div class="em-form"><h4 class="em-titulo">Caixas de email</h4>${cs.length?`<ul class="em-config">${lista}</ul>`:""}
      <h5>${e.id?"Editar "+esc(e.email):"Ligar uma caixa"}</h5><p class="campo-ajuda">Ligação segura: IMAP na porta 993 e SMTP na porta 465. A palavra-passe fica cifrada no servidor e não volta a ser mostrada.</p>
      <div class="pm-grelha"><label>Email<input id="emcEmail" type="email" autocomplete="off" value="${esc(e.email||"")}" placeholder="contacto@empresa.pt"></label>
      <label>Nome do remetente<input id="emcNome" type="text" value="${esc(e.nome||"")}" placeholder="Elolog"></label>
      <label>Servidor IMAP (receção)<input id="emcImap" type="text" autocomplete="off" value="${esc(e.imap_host||"")}" placeholder="imap.empresa.pt"></label>
      <label>Servidor SMTP (envio)<input id="emcSmtp" type="text" autocomplete="off" value="${esc(e.smtp_host||"")}" placeholder="smtp.empresa.pt"></label>
      <label>Utilizador<input id="emcUser" type="text" autocomplete="off" value="${esc(e.utilizador||"")}" placeholder="normalmente o próprio email"></label>
      <label>Palavra-passe${e.id?" (vazio = manter)":""}<input id="emcSenha" type="password" autocomplete="new-password"></label></div>
      ${E().elolog&&E().empresa&&!e.id?'<label class="pm-opcao"><input type="checkbox" id="emcEmpresa"> Caixa da minha empresa (e não da Elolog)</label>':""}
      <p class="campo-ajuda">Gmail e Outlook pedem uma «palavra-passe de aplicação». No Elolog (www.pt) use a palavra-passe da conta de email.</p>
      <div class="em-acoes">${cs.length?'<button type="button" class="btn-secondary" data-em="cancelar">Fechar</button>':""}${e.id?'<button type="button" class="btn-secondary" data-em="nova-caixa">Nova caixa</button>':""}<button type="button" class="btn-primary" data-em="gravar">Testar e guardar</button></div></div>`;
    const em=document.getElementById("emcEmail");em.addEventListener("change",()=>{const dom=em.value.split("@")[1]?.toLowerCase();if(!dom)return;const s=SERVIDORES[dom]||["imap."+dom,"smtp."+dom];
      const im=document.getElementById("emcImap"),sm=document.getElementById("emcSmtp"),us=document.getElementById("emcUser");if(!im.value)im.value=s[0];if(!sm.value)sm.value=s[1];if(!us.value)us.value=em.value.trim().toLowerCase()})}

  async function acao(nome,b){if(b?.disabled)return;if(b)b.disabled=true;try{await fazer(nome,b)}finally{if(b?.isConnected)b.disabled=false}}
  async function fazer(nome,b){const e=E(),m=e.aberta,v=id=>document.getElementById(id)?.value.trim()||"",c=e.caixas.find(x=>x.id===e.caixa);
    const ir=vista=>{e.vista=vista;e.desenhar()};
    try{
      if(nome==="novo"){if(!c)return ir("config");rascunho={};return ir("escrever")}
      if(nome==="config"){editar=null;return ir("config")}
      if(nome==="voltar"||nome==="cancelar"){rascunho=null;editar=null;e.aberta=null;return ir(null)}
      if(nome==="imagens"){imagens=true;return e.desenhar()}
      if(["responder","todos","reencaminhar"].includes(nome)&&m){const meu=c?.email||"",para=E().endereco(m.responder_a||m.de);
        const outros=[m.para,m.cc].join(",").split(/[,;]/).map(x=>E().endereco(x)).filter(x=>x&&x!==meu&&x!==para);
        rascunho=nome==="reencaminhar"?{titulo:"Reencaminhar",assunto:"Fw: "+semPrefixo(m.assunto),texto:"\n\n---------- Mensagem reencaminhada ----------\nDe: "+m.de+"\nAssunto: "+m.assunto+"\n\n"+textoDe(m),anexosNota:!!m.anexos?.length}
          :{titulo:"Responder",para:para===meu?E().endereco(m.para):para,cc:nome==="todos"?[...new Set(outros)].join(", "):"",assunto:"Re: "+semPrefixo(m.assunto),texto:citar(m),em_resposta:m.message_id,referencias:m.referencias,uid:m.uid,pasta:e.pasta};
        return ir("escrever")}
      if(nome==="enviar"){const d={para:v("emPara"),cc:v("emCc"),assunto:v("emAssunto"),texto:document.getElementById("emTexto").value};
        if(!E().endereco(d.para))return P().aviso("Indique pelo menos um destinatário.","warning");if(!d.assunto||!d.texto.trim())return P().aviso("Escreva o assunto e a mensagem.","warning");
        if(!e.online()){e.demo.enviados.unshift({uid:Date.now(),de:c.email,para:d.para,assunto:d.assunto,data:new Date().toISOString(),lida:true,texto:d.texto})}
        else{const r=await e.chamar("enviar",{caixa:e.caixa,...d,em_resposta:rascunho?.em_resposta||"",referencias:rascunho?.referencias||"",uid:rascunho?.uid||0,pasta:rascunho?.pasta||e.pasta});
          if(!r.guardada)P().aviso("Enviado. Não foi possível guardar a cópia na pasta Enviados.","warning")}
        P().aviso("Email enviado.","success");rascunho=null;e.aberta=null;e.vista=null;return e.carregarLista()}
      if(nome==="anexo"&&m){const a=m.anexos[Number(b.dataset.i)];if(!e.online())return P().aviso("No modo de demonstração os anexos não descarregam.","info");
        const r=await e.chamar("anexo",{caixa:e.caixa,pasta:e.pasta,uid:m.uid,indice:Number(b.dataset.i)}),bin=atob(r.base64),u8=Uint8Array.from(bin,x=>x.charCodeAt(0));
        const url=URL.createObjectURL(new Blob([u8],{type:"application/octet-stream"})),l=document.createElement("a");l.href=url;l.download=r.nome||a?.nome||"anexo";document.body.appendChild(l);l.click();l.remove();setTimeout(()=>URL.revokeObjectURL(url),5000);return}
      if((nome==="naolida"||nome==="apagar")&&m){if(nome==="apagar"&&e.pasta==="lixo"&&!confirm("Apagar esta mensagem de vez?"))return;
        if(!e.online()){const l=e.demo[e.pasta],i=l.findIndex(x=>x.uid===m.uid);if(nome==="naolida")l[i].lida=false;else{const[x]=l.splice(i,1);if(e.pasta!=="lixo")e.demo.lixo.unshift(x)}}
        else await e.chamar(nome==="apagar"?"apagar":"marcar",{caixa:e.caixa,pasta:e.pasta,uid:m.uid,lida:false});
        e.aberta=null;e.vista=null;return e.carregarLista()}
      if(nome==="editar"){editar=e.caixas.find(x=>x.id===b.dataset.id)||null;return ir("config")}
      if(nome==="nova-caixa"){editar=null;return ir("config")}
      if(nome==="remover"){const x=e.caixas.find(y=>y.id===b.dataset.id);if(!x||!confirm(`Desligar a caixa ${x.email} da plataforma? Os emails continuam no servidor de email.`))return;
        if(e.online())await e.chamar("remover",{caixa:x.id});else e.demo.caixas.splice(e.demo.caixas.indexOf(x),1);
        await e.carregarCaixas();editar=null;e.lista=null;P().aviso("Caixa desligada.","success");return ir("config")}
      if(nome==="gravar"){const d={email:v("emcEmail").toLowerCase(),nome:v("emcNome"),imap_host:v("emcImap").toLowerCase(),smtp_host:v("emcSmtp").toLowerCase(),utilizador:v("emcUser"),senha:document.getElementById("emcSenha").value,
          ambito:document.getElementById("emcEmpresa")?.checked?"empresa":"elolog"};
        if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(d.email))return P().aviso("Indique o endereço de email.","warning");if(!d.imap_host||!d.smtp_host)return P().aviso("Indique os servidores IMAP e SMTP.","warning");
        if(!editar&&!d.senha)return P().aviso("Indique a palavra-passe da caixa.","warning");
        if(!e.online()){if(editar)Object.assign(editar,d,{senha:undefined});else e.demo.caixas.push({...d,senha:undefined,id:"demo-"+Date.now(),elolog:d.ambito==="elolog",tem_senha:true})}
        else{const r=await e.chamar("gravar",{...d,caixa:editar?.id||null});e.caixa=r.caixa?.id||e.caixa}
        await e.carregarCaixas();if(!editar&&e.online())e.caixa=e.caixas.find(x=>x.email===d.email)?.id||e.caixa;editar=null;P().aviso("Ligação testada e caixa guardada.","success");e.vista=null;return e.carregarLista()}
    }catch(err){P().aviso(err.message||"Não foi possível concluir.","error")}}

  window.elologEmail2={acao,vista(d){const v=E().vista;if(v==="ler")ler(d);else if(v==="escrever")escrever(d);else if(v==="config")config(d)}};
})();
