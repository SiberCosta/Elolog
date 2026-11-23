/* Elolog — Encomendas diretas (v98): dados e regras partilhados pelo cliente, administração e prestador.
   Com servidor usa a ligação Supabase existente (elologProducao.sb) e as funções da migração 00160; sem servidor guarda uma
   demonstração neste navegador com o mesmo fluxo. Nunca elimina uma encomenda; só o cliente troca de prestador. */
(function(){"use strict";
const P=()=>window.elologProducao;
const online=()=>{try{return!!P()?.online?.()}catch(_){return false}};
const esc=v=>String(v??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const ESTADOS={pendente_validacao:["Pendente de validação","Cliente","amb"],em_analise_admin:["Em análise","Administração","azul"],validada:["Validada","Administração","verde"],
  nao_validada:["Não validada","Administração","verm"],enviada_prestador:["Enviada ao prestador","Administração","azul"],em_analise_prestador:["Em análise pelo prestador","Prestador","azul"],
  aceite:["Aceite","Prestador","verde"],recusada:["Recusada","Prestador","verm"],cancelada:["Cancelada","Cliente","cinza"]};
const MOTIVOS={rota:"Não realiza aquela rota",espaco:"Não dispõe de espaço",preco:"Preço ou condições não confirmados",documentacao:"Documentação insuficiente",
  mercadoria:"Mercadoria não aceite",outro:"Outro motivo"};
const PAPEL={cliente:"Cliente",administracao:"Administração",prestador:"Prestador"};
const rotulo=e=>ESTADOS[e]?.[0]||e;
const etiqueta=(e,o)=>`<span class="ed-estado ed-${o?.pedido_documentos?"amb":ESTADOS[e]?.[2]||"cinza"}">${esc(o?.pedido_documentos?"Documentos pedidos":rotulo(e))}</span>`;
const data=d=>d?new Date(d).toLocaleDateString("pt-PT"):"—";
const quando=d=>d?new Date(d).toLocaleString("pt-PT",{day:"2-digit",month:"2-digit",hour:"2-digit",minute:"2-digit"}):"";
const erro=e=>window.ELOLogServidor?.mensagem?.(e)||e?.message||String(e);

/* ---------- demonstração (localStorage) ---------- */
const K="elolog_encomendas_diretas_demo";
const ler=()=>{try{return JSON.parse(localStorage.getItem(K)||"[]")}catch(_){return[]}};
const gravar=l=>{try{localStorage.setItem(K,JSON.stringify(l))}catch(_){}};
const eu=()=>(typeof currentUser!=="undefined"&&currentUser)||{};
const DEMO_PREST=[{id:"demo-transatlantico",nome:"Transatlântico Demo, Lda.",cidade:"Lisboa",pais:"Portugal"},{id:"demo-luso",nome:"Luso Freight (demo)",cidade:"Porto",pais:"Portugal"}];
function prestDemo(){let l=[];try{l=(JSON.parse(localStorage.getItem("elolog_profiles")||"[]")||[]).filter(p=>p.type==="prestador"&&/ativo|aprovad/i.test(p.status||""))
  .map(p=>({id:"p-"+(p.id||p.name),nome:p.tradeName||p.name,cidade:p.city||"",pais:p.country||""}))}catch(_){}return l.length?l:DEMO_PREST}
function minhaEmpresaDemo(){const c=eu().providerCompany;return c?.name||c?.tradeName||""}
function visiveisDemo(){const u=eu(),l=ler();if(u.role==="admin")return l;if(u.role==="prestador"){const n=minhaEmpresaDemo();
  return l.filter(e=>e.prestador===n&&["enviada_prestador","em_analise_prestador","aceite","recusada"].includes(e.estado)).map(e=>e.estado==="aceite"?e:{...e,cliente_email:null,cliente_telefone:null})}
  return l.filter(e=>e.cliente_email===u.email)}
function mudarDemo(id,estado,papel,nota,extra){const l=ler(),e=l.find(x=>x.id===id);if(!e)throw new Error("Encomenda direta não encontrada.");
  Object.assign(e,extra||{},{estado,updated_at:new Date().toISOString()});e.historico.push({estado,papel,nota:nota||null,em:new Date().toISOString()});gravar(l);
  try{const aud=papel==="prestador"||papel==="cliente"?"admin":"client";window.addOperationNotification?.({title:"Encomenda direta "+e.codigo,message:rotulo(estado)+(nota?", "+nota:""),
    type:estado==="recusada"||estado==="nao_validada"?"warning":"info",audience:aud,to:aud==="client"?e.cliente_email:"",actor:PAPEL[papel]})}catch(_){}return e}
const TRANS={admin:{analisar:[["pendente_validacao"],"em_analise_admin"],validar:[["pendente_validacao","em_analise_admin"],"validada"],
  nao_validar:[["pendente_validacao","em_analise_admin"],"nao_validada"],enviar:[["validada"],"enviada_prestador"],
  pedir_documentos:[["pendente_validacao","em_analise_admin","validada"],"em_analise_admin"],validar_enviar:[["pendente_validacao","em_analise_admin"],"validada"]},
  prestador:{analisar:[["enviada_prestador"],"em_analise_prestador"],aceitar:[["enviada_prestador","em_analise_prestador"],"aceite"],recusar:[["enviada_prestador","em_analise_prestador"],"recusada"]}};

const lerUrl=f=>new Promise(r=>{if(!f||f.size>1.5e6)return r(null);const x=new FileReader();x.onload=()=>r(x.result);x.onerror=()=>r(null);x.readAsDataURL(f)});
const CAMPOS={origem:"origem",destino:"destino",mercadoria:"mercadoria",volumes:"volumes",peso_kg:"peso",volume_m3:"volume",valor_acordado:"valor",data_prevista:"data",observacoes:"observações"};

/* ---------- API ---------- */
async function sb(){return P().sb()}
async function rpc(nome,args){const c=await sb();const{data,error}=await c.rpc(nome,args);if(error)throw new Error(erro(error));return data}
const API={ESTADOS,MOTIVOS,PAPEL,rotulo,etiqueta,esc,data,quando,erro,online,
  async prestadores(origem,destino){if(!online())return prestDemo();return await rpc("prestadores_encomenda_direta",{p_origem:origem||null,p_destino:destino||null})||[]},
  async listar(){if(!online())return visiveisDemo().slice().sort((a,b)=>String(b.created_at).localeCompare(String(a.created_at)));return await rpc("encomendas_diretas_lista",{})||[]},
  async criar(d,ficheiro){if(!ficheiro)throw new Error("Anexe o comprovativo da negociação (proposta, orçamento, recibo ou documento de transporte).");
    if(!online()){const l=ler(),n=l.length+1,agora=new Date().toISOString(),pr=prestDemo().find(p=>p.id===d.empresa);if(!pr)throw new Error("Escolha um prestador da lista.");
      const e={id:"ed-"+Date.now(),codigo:`ED-${new Date().getFullYear()}-${String(n).padStart(6,"0")}`,empresa_id:pr.id,prestador:pr.nome,origem:d.origem,destino:d.destino,mercadoria:d.mercadoria,
        volumes:d.volumes,peso_kg:d.peso_kg,volume_m3:d.volume_m3,valor_acordado:d.valor,data_prevista:d.data,observacoes:d.observacoes,estado:"pendente_validacao",created_at:agora,updated_at:agora,
        cliente_nome:eu().name||eu().email,cliente_email:eu().email,documento:{nome:ficheiro.name,demo:true,mime:ficheiro.type,url:await lerUrl(ficheiro)},anexos:[],historico:[]};
      l.push(e);gravar(l);mudarDemo(e.id,"pendente_validacao","cliente",null);return{codigo:e.codigo}}
    const doc=await P().enviarDocumento(ficheiro,{categoria:"comprovativo",visibilidade:"cliente"});
    return await rpc("criar_encomenda_direta",{p_empresa:d.empresa,p_origem:d.origem,p_destino:d.destino,p_mercadoria:d.mercadoria,p_volumes:d.volumes,p_peso_kg:d.peso_kg,
      p_volume_m3:d.volume_m3,p_valor:d.valor,p_data:d.data||null,p_documento:doc.id,p_observacoes:d.observacoes||null})},
  async cliente(id,acao,empresa){if(online())return rpc("cliente_encomenda_direta",{p_id:id,p_acao:acao,p_empresa:empresa||null});
    const e=ler().find(x=>x.id===id);if(!e)throw new Error("Encomenda direta não encontrada.");
    if(acao==="trocar_prestador"){if(!["recusada","nao_validada"].includes(e.estado))throw new Error("Só pode trocar de prestador depois de uma recusa ou de uma não validação.");
      const pr=prestDemo().find(p=>p.id===empresa);if(!pr)throw new Error("Escolha um prestador da lista.");
      return mudarDemo(id,"pendente_validacao","cliente","Novo prestador escolhido pelo cliente.",{empresa_id:pr.id,prestador:pr.nome,motivo:null,motivo_tipo:null})}
    if(acao==="cancelar"){if(!["pendente_validacao","em_analise_admin","nao_validada","recusada"].includes(e.estado))throw new Error("Esta encomenda já não pode ser cancelada pelo cliente.");return mudarDemo(id,"cancelada","cliente",null)}},
  async admin(id,acao,nota){if(online())return rpc("admin_encomenda_direta",{p_id:id,p_acao:acao,p_nota:nota||null});
    const e=ler().find(x=>x.id===id),t=TRANS.admin[acao];if(!e||!t||!t[0].includes(e.estado))throw new Error("Esta ação não é possível no estado atual.");
    if(acao==="nao_validar"&&String(nota||"").trim().length<5)throw new Error("Indique ao cliente o motivo da não validação.");
    if(acao==="pedir_documentos"){if(String(nota||"").trim().length<5)throw new Error("Indique ao cliente que documentos são precisos.");
      return mudarDemo(id,t[1],"administracao","Documentos pedidos: "+nota.trim(),{pedido_documentos:nota.trim(),pedido_documentos_em:new Date().toISOString()})}
    if(/^validar/.test(acao)){if(!e.comprovativo_visto_em)throw new Error("Abra e analise o comprovativo antes de validar.");if(e.pedido_documentos)throw new Error("Há documentos pedidos ao cliente ainda por receber.")}
    const r=mudarDemo(id,t[1],"administracao",nota,acao==="nao_validar"?{motivo:nota.trim(),motivo_tipo:null,pedido_documentos:null}:null);
    return acao==="validar_enviar"?mudarDemo(id,"enviada_prestador","administracao",null):r},
  async visto(id){if(online())return rpc("admin_comprovativo_visto",{p_id:id});const l=ler(),e=l.find(x=>x.id===id);if(e&&!e.comprovativo_visto_em){e.comprovativo_visto_em=new Date().toISOString();gravar(l)}},
  async corrigir(id,dados,nota){if(online())return rpc("admin_corrigir_encomenda_direta",{p_id:id,p_dados:dados,p_nota:nota||null});
    const e=ler().find(x=>x.id===id);if(!e)throw new Error("Encomenda direta não encontrada.");if(!["pendente_validacao","em_analise_admin","validada"].includes(e.estado))throw new Error("Só pode corrigir antes de encaminhar ao prestador.");
    const dif=Object.keys(CAMPOS).filter(k=>k in dados&&String(dados[k]??"")!==String(e[k]??"")).map(k=>k==="mercadoria"||k==="observacoes"?CAMPOS[k]+" atualizada":`${CAMPOS[k]}: ${e[k]??"—"} → ${dados[k]??"—"}`);
    if(!dif.length)throw new Error("Não há alterações.");const nv={};Object.keys(CAMPOS).forEach(k=>{if(k in dados)nv[k]=dados[k]});
    return mudarDemo(id,e.estado,"administracao","Dados corrigidos, "+dif.join("; ")+(nota?". "+nota:""),nv)},
  async anexar(id,ficheiro,nota){if(!ficheiro)throw new Error("Escolha o ficheiro.");
    if(online()){const doc=await P().enviarDocumento(ficheiro,{categoria:"comprovativo",visibilidade:"cliente"});return rpc("cliente_anexo_encomenda_direta",{p_id:id,p_documento:doc.id,p_nota:nota||null})}
    const l=ler(),e=l.find(x=>x.id===id);if(!e)throw new Error("Encomenda direta não encontrada.");if(!["pendente_validacao","em_analise_admin","validada","nao_validada"].includes(e.estado))throw new Error("Já não é possível juntar documentos a esta encomenda.");
    (e.anexos=e.anexos||[]).push({nome:ficheiro.name,mime:ficheiro.type,url:await lerUrl(ficheiro),nota:nota||null,em:new Date().toISOString(),demo:true});gravar(l);
    return mudarDemo(id,e.estado==="nao_validada"?"em_analise_admin":e.estado,"cliente","Documento adicional enviado"+(nota?": "+nota:"."),{pedido_documentos:null,pedido_documentos_em:null})},
  /* pré-visualização de um documento (PDF ou imagem) — link temporário de 5 minutos */
  async url(doc){if(!doc)throw new Error("Sem documento.");if(doc.demo||!online())return doc.url||null;
    const c=await sb();const{data,error}=await c.storage.from("documentos").createSignedUrl(doc.caminho,300);if(error)throw new Error("Não foi possível abrir o documento.");return data.signedUrl},
  async previsao(doc){const u=await API.url(doc);if(!u)return`<div class="ed-prev ed-prev-vazio">Demonstração: «${esc(doc?.nome)}» não fica guardado neste modo.</div>`;
    const img=/^image\//.test(doc.mime||"")||/\.(png|jpe?g)$/i.test(doc.nome||"");
    return`<div class="ed-prev">${img?`<img src="${esc(u)}" alt="${esc(doc.nome)}">`:`<iframe src="${esc(u)}" title="${esc(doc.nome)}"></iframe>`}</div><p class="ed-prev-link"><a href="${esc(u)}" target="_blank" rel="noopener">Abrir «${esc(doc.nome)}» noutra janela</a></p>`},
  async ver(doc,titulo){const j=P().janela({eyebrow:"DOCUMENTO",titulo:titulo||doc?.nome||"Documento"});j.mostrar('<p class="ed-vazio">A abrir…</p>',[{texto:"Fechar",acao:()=>j.fechar()}]);
    try{j.corpo.innerHTML=await API.previsao(doc)}catch(x){j.corpo.innerHTML=`<p class="campo-erro">${esc(erro(x))}</p>`}},
  async prestador(id,acao,tipo,motivo){if(online())return rpc("prestador_encomenda_direta",{p_id:id,p_acao:acao,p_motivo_tipo:tipo||null,p_motivo:motivo||null});
    const e=ler().find(x=>x.id===id),t=TRANS.prestador[acao];if(!e||!t||!t[0].includes(e.estado))throw new Error("Esta ação não é possível no estado atual.");
    if(acao==="recusar"){if(!MOTIVOS[tipo])throw new Error("Escolha o motivo da recusa.");if(tipo==="outro"&&String(motivo||"").trim().length<5)throw new Error("Descreva o motivo da recusa.")}
    return mudarDemo(id,t[1],"prestador",acao==="recusar"?MOTIVOS[tipo]+(motivo?": "+motivo:""):null,acao==="recusar"?{motivo_tipo:tipo,motivo:motivo||null}:null)},
  async comprovativo(e,i){const d=i==null?e?.documento:(e?.anexos||[])[i];if(!d)throw new Error("Sem documento.");return API.ver(d,i==null?"Comprovativo "+e.codigo:"Documento adicional, "+e.codigo)},
  /* cartão com o percurso (igual para os três perfis) */
  cartao(e,acoes){const h=(e.historico||[]).map(x=>`<li><b>${esc(rotulo(x.estado))}</b> <small>${esc(PAPEL[x.papel]||x.papel)}, ${esc(quando(x.em))}</small>${x.nota?`<p>${esc(x.nota)}</p>`:""}</li>`).join("");
    const mot=["recusada","nao_validada"].includes(e.estado)&&(e.motivo||e.motivo_tipo)?`<p class="ed-motivo"><b>Motivo:</b> ${esc(e.motivo_tipo?MOTIVOS[e.motivo_tipo]+(e.motivo?", "+e.motivo:""):e.motivo)}</p>`:"";
    return`<article class="ed-cartao" data-id="${esc(e.id)}"><header><div><strong>${esc(e.codigo)}</strong> ${etiqueta(e.estado,e)}</div><small>${esc(data(e.created_at))}</small></header>
      <p class="ed-rota">${esc(e.origem)} <i>→</i> ${esc(e.destino)}</p>
      <dl class="ed-dados"><div><dt>Prestador</dt><dd>${esc(e.prestador)}</dd></div><div><dt>Mercadoria</dt><dd>${esc(e.mercadoria)}</dd></div>
        <div><dt>Volumes</dt><dd>${esc(e.volumes)}${e.peso_kg?`, ${esc(e.peso_kg)} kg`:""}${e.volume_m3?`, ${esc(e.volume_m3)} m³`:""}</dd></div>
        <div><dt>Valor acordado</dt><dd>${Number(e.valor_acordado||0).toLocaleString("pt-PT",{style:"currency",currency:"EUR"})}</dd></div>
        <div><dt>Data prevista</dt><dd>${esc(data(e.data_prevista))}</dd></div>${e.cliente_nome&&eu().role!=="cliente"?`<div><dt>Cliente</dt><dd>${esc(e.cliente_nome)}${e.cliente_email?`, ${esc(e.cliente_email)}`:""}${e.cliente_telefone?`, ${esc(e.cliente_telefone)}`:""}</dd></div>`:""}</dl>
      ${e.observacoes?`<p class="ed-obs">${esc(e.observacoes)}</p>`:""}${mot}
      ${e.pedido_documentos?`<p class="ed-pedido"><b>Documentos pedidos pela administração:</b> ${esc(e.pedido_documentos)}</p>`:""}
      ${(e.anexos||[]).length?`<ul class="ed-anexos">${e.anexos.map((a,i)=>`<li><button type="button" class="ed-link" data-ed="anexo" data-i="${i}">📎 ${esc(a.nome)}</button>${a.nota?` <small>${esc(a.nota)}</small>`:""}</li>`).join("")}</ul>`:""}
      <details class="ed-hist"><summary>Percurso (${(e.historico||[]).length})</summary><ol>${h}</ol></details>
      <div class="ed-acoes">${e.documento?`<button type="button" class="btn-secondary" data-ed="comprovativo">Ver comprovativo</button>`:""}${acoes||""}</div></article>`}};
window.elologED=API;
})();
