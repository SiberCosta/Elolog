/* Elolog — equipa da plataforma: funcionários Elolog que gerem o portal (Funcionários e acessos).
   Funções: administrador (gere tudo, incluindo a equipa), operador (operações, pedidos e prestadores) e apoio (clientes e reclamações).
   Servidor: rpc equipa_plataforma (lista) e Edge Function gerir-equipa (criar, ativar/desativar, mudar função, repor palavra-passe).
   No modo de demonstração a lista fica no navegador. */
(function(){
  const P=()=>window.elologProducao,esc=v=>P()?.esc(v)??String(v??"");
  const FUNCOES={admin:["Administrador","Gere todo o portal e a equipa"],operador:["Operador","Pedidos, operações e prestadores"],apoio:["Apoio","Clientes, apoio e reclamações"]};
  const CHAVE="elolog_equipa_demo";
  const demoLer=()=>{try{const l=JSON.parse(localStorage.getItem(CHAVE)||"null");if(Array.isArray(l))return l}catch(_){}return[{user_id:"demo-1",nome:"Administrador Elolog Demo",email:"admin@demo.elolog.pt",papel:"admin",ativo:true,sou_eu:true,created_at:new Date().toISOString()}]};
  const demoGravar=l=>{try{localStorage.setItem(CHAVE,JSON.stringify(l))}catch(_){}};
  let lista=null,erro="";

  async function carregar(){erro="";try{if(!P()?.online()){lista=demoLer();return}const c=await P().sb(),{data,error}=await c.rpc("equipa_plataforma");if(error)throw error;lista=data||[]}
    catch(e){erro=window.ELOLogServidor?.mensagem?.(e)||e.message;lista=lista||[]}}
  async function pedir(corpo){if(!P()?.online()){const l=demoLer();if(corpo.acao==="criar"){if(l.some(x=>x.email===corpo.email.toLowerCase()))throw new Error("Já existe uma conta com este email.");
      l.push({user_id:"demo-"+Date.now(),nome:corpo.nome,email:corpo.email.toLowerCase(),papel:corpo.papel,ativo:true,created_at:new Date().toISOString()})}
    else{const f=l.find(x=>x.user_id===corpo.alvo);if(f&&corpo.acao==="alterar"){if(corpo.ativo!=null)f.ativo=corpo.ativo;if(corpo.papel)f.papel=corpo.papel}}demoGravar(l);return{ok:true}}
    return window.ELOLogServidor.chamarFuncao("gerir-equipa",corpo)}

  function html(){const souAdmin=(lista||[]).some(f=>f.sou_eu&&f.papel==="admin")||!P()?.online();
    const linhas=(lista||[]).map(f=>`<li class="eq-linha${f.ativo?"":" eq-inativo"}"><span class="eq-avatar" aria-hidden="true">${esc((f.nome||"?").split(/\s+/).map(x=>x[0]).slice(0,2).join("").toUpperCase())}</span>
      <div class="eq-quem"><b>${esc(f.nome)}${f.sou_eu?' <small class="eq-eu">(você)</small>':""}</b><small>${esc(f.email||"")}</small></div>
      <div class="eq-funcao"><span class="estado-pill ${f.ativo?"sa-info":"sa-mau"}">${f.ativo?esc(FUNCOES[f.papel]?.[0]||f.papel):"Desativado"}</span><small>${esc(FUNCOES[f.papel]?.[1]||"")}</small></div>
      ${souAdmin&&!f.sou_eu?`<div class="eq-acoes"><button type="button" class="btn-secondary" data-eq="papel" data-id="${esc(f.user_id)}">Função</button><button type="button" class="btn-secondary" data-eq="senha" data-id="${esc(f.user_id)}">Palavra-passe</button>
      <button type="button" class="${f.ativo?"btn-danger":"btn-secondary"}" data-eq="ativo" data-id="${esc(f.user_id)}">${f.ativo?"Desativar":"Ativar"}</button></div>`:"<div></div>"}</li>`).join("");
    return`<section class="card eq-cartao" id="eqEquipa" aria-labelledby="eqTitulo"><div class="eq-topo"><div><h3 id="eqTitulo">Equipa Elolog</h3><p class="ct-sub">Funcionários que gerem o portal. Cada um entra com o seu email, palavra-passe e código de autenticação (2.º fator).</p></div>
      ${souAdmin?'<button type="button" class="btn-primary" data-eq="novo">+ Novo funcionário</button>':""}</div>
      ${erro?`<p class="campo-erro" role="alert">${esc(erro)}</p>`:""}${lista==null?'<p class="pa-vazio">A carregar a equipa…</p>':`<ul class="eq-lista">${linhas||'<li class="pa-vazio">Ainda não há funcionários.</li>'}</ul>`}</section>`}
  async function desenhar(recarregar){const pag=document.getElementById("adminAccess");if(!pag)return;const box=pag.querySelector("#eqEquipa");
    if(box)box.outerHTML=html();else pag.insertAdjacentHTML("afterbegin",html());if(recarregar){await carregar();desenhar(false)}}

  const campo=(id,rotulo,tipo="text",extra="")=>`<label for="${id}">${rotulo}</label><input id="${id}" type="${tipo}" ${extra}>`;
  const funcoes=sel=>Object.entries(FUNCOES).map(([k,[n,d]])=>`<option value="${k}"${k===sel?" selected":""}>${n} — ${d}</option>`).join("");
  const senhaOk=s=>s.length>=10&&/[a-z]/.test(s)&&/[A-Z]/.test(s)&&/\d/.test(s);
  function novo(){const j=P().janela({eyebrow:"EQUIPA ELOLOG",titulo:"Novo funcionário",passos:["Dados","Acesso"]});j.passo(0);
    j.mostrar(`${campo("eqNome","Nome completo","text",'autocomplete="off" required')}${campo("eqEmail","Email de trabalho","email",'autocomplete="off" required')}
      <label for="eqPapel">Função</label><select id="eqPapel">${funcoes("operador")}</select>
      ${campo("eqSenha","Palavra-passe temporária","password",'autocomplete="new-password" required')}<p class="campo-ajuda">10+ caracteres com maiúscula, minúscula e número. Entregue-a pessoalmente; no 1.º acesso o funcionário configura o código de autenticação.</p>`,
      [{texto:"Cancelar",acao:j.fechar},{texto:"Criar funcionário",principal:true,acao:async()=>{const v=id=>document.getElementById(id).value.trim();
        if(!window.eloValidar?.(["eqNome","eqEmail","eqSenha"])&&window.eloValidar)return;if(v("eqNome").length<2)return P().aviso("Indique o nome.","warning");
        if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v("eqEmail")))return P().aviso("Indique um email válido.","warning");if(!senhaOk(document.getElementById("eqSenha").value))return P().aviso("A palavra-passe deve ter 10+ caracteres com maiúscula, minúscula e número.","warning");
        j.passo(1);try{await pedir({acao:"criar",nome:v("eqNome"),email:v("eqEmail"),papel:v("eqPapel"),senha:document.getElementById("eqSenha").value});j.fechar();P().aviso("Funcionário criado. Já pode entrar na administração.","success");desenhar(true)}
        catch(e){j.passo(0);P().aviso(e.message,"error")}}}]);setTimeout(()=>document.getElementById("eqNome")?.focus(),40)}
  function papel(f){const j=P().janela({eyebrow:"EQUIPA ELOLOG",titulo:"Função de "+f.nome});j.mostrar(`<label for="eqPapel2">Função</label><select id="eqPapel2">${funcoes(f.papel)}</select>`,
    [{texto:"Cancelar",acao:j.fechar},{texto:"Guardar",principal:true,acao:async()=>{try{await pedir({acao:"alterar",alvo:f.user_id,papel:document.getElementById("eqPapel2").value});j.fechar();P().aviso("Função atualizada.","success");desenhar(true)}catch(e){P().aviso(e.message,"error")}}}])}
  function senha(f){const j=P().janela({eyebrow:"EQUIPA ELOLOG",titulo:"Nova palavra-passe · "+f.nome});j.mostrar(`${campo("eqSenha2","Nova palavra-passe temporária","password",'autocomplete="new-password"')}<p class="campo-ajuda">10+ caracteres com maiúscula, minúscula e número.</p>`,
    [{texto:"Cancelar",acao:j.fechar},{texto:"Alterar",principal:true,acao:async()=>{const s=document.getElementById("eqSenha2").value;if(!senhaOk(s))return P().aviso("Palavra-passe fraca.","warning");
      try{await pedir({acao:"senha",alvo:f.user_id,senha:s});j.fechar();P().aviso("Palavra-passe alterada.","success")}catch(e){P().aviso(e.message,"error")}}}])}
  function ativo(f){const j=P().janela({eyebrow:"EQUIPA ELOLOG",titulo:(f.ativo?"Desativar ":"Ativar ")+f.nome});
    j.mostrar(`<p>${f.ativo?"O funcionário deixa de conseguir entrar e as sessões abertas terminam. O histórico fica guardado.":"O funcionário volta a poder entrar na administração."}</p>`,
    [{texto:"Cancelar",acao:j.fechar},{texto:f.ativo?"Desativar":"Ativar",principal:true,acao:async()=>{try{await pedir({acao:"alterar",alvo:f.user_id,ativo:!f.ativo});j.fechar();P().aviso(f.ativo?"Funcionário desativado.":"Funcionário ativado.","success");desenhar(true)}catch(e){P().aviso(e.message,"error")}}}])}

  document.addEventListener("click",e=>{const b=e.target.closest("[data-eq]");if(!b||!P())return;const f=(lista||[]).find(x=>x.user_id===b.dataset.id);
    ({novo,papel:()=>f&&papel(f),senha:()=>f&&senha(f),ativo:()=>f&&ativo(f)})[b.dataset.eq]?.()});
  if(typeof showAdminPage==="function"){const orig=showAdminPage;showAdminPage=function(page){const r=orig.apply(this,arguments);if(page==="adminAccess")desenhar(true);return r}}
  window.elologEquipa={desenhar,novo};
})();
