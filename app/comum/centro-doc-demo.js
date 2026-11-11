/* Elolog — Centro Documental (v123): documentos de EXEMPLO para a demonstração (sem servidor). Os dados são inventados e a página diz que são exemplos.
   Também liga o Centro Documental aos menus do cliente e da administração, e envia o logótipo do prestador para o servidor (definir_logotipo). */
(function(){"use strict";
const CHAVE="elolog_doc_demo";
const hex=n=>[...crypto.getRandomValues(new Uint8Array(n))].map(b=>b.toString(16).padStart(2,"0")).join("");
const empresaNome=()=>{try{return currentProviderCompanyName()||"Atlântico Lda"}catch(_){return"Atlântico Lda"}};
function base(ref){return{empresa:{id:"demo-empresa",nome:empresaNome(),nif:"509876543",morada:"Rua do Porto 12, 2800-001 Almada, Portugal",telefone:"+351 212 000 000",email:"geral@exemplo.pt"},
  cliente:{nome:"Ana Silva",nif:"123456789"},remetente:{nome:"Ana Silva",telefone:"+351 912 345 678",morada:"Rua Dom Francisco de Melo e Noronha 15, 2810-221 Almada"},
  destinatario:{nome:"Rui Mendes",telefone:"+239 990 1234",morada:"Bairro Riboque, São Tomé"},
  encomenda:{codigo:ref,origem:"Almada, Portugal",destino:"São Tomé, São Tomé e Príncipe",modalidade:"Marítimo",tipo_carga:"Mercadoria geral",descricao:"Bidões e caixas de roupa",quantidade:4,peso_kg:120,volume_m3:1.25,
    volumes:[{descricao:"Bidão 200 L",quantidade:2,peso:40,comprimento:60,largura:60,altura:90},{descricao:"Caixa de roupa",quantidade:2,peso:20,comprimento:60,largura:40,altura:40}],valor_declarado:850,
    data_prevista:"2026-11-20",morada_recolha:"Rua Dom Francisco de Melo e Noronha 15, 2810-221 Almada",navio:"Sao Tome Express",viagem:"ST-2611",partida_prevista:"2026-11-24",chegada_prevista:"2026-12-08",observacoes:"Frágil: caixas 3 e 4."},ocorrencias:[]}}
const extra={rececao:()=>({rececao:{em:"2026-11-18T10:42:00",por:"Pedro Costa",armazem:"Armazém Seixal",quantidade_esperada:4,quantidade_recebida:4,conferida:true,localizacao:"Corredor B, palete 12",ocorrencias:""}}),
  pagamento:()=>({pagamento:{codigo:"PAG-000045",valor:150,moeda:"EUR",metodo:"mbway",referencia:"912 *** 678",em:"2026-11-12T16:05:00",total_encomenda:300,total_pago:150,saldo:150,estado:"parcial"}})};
const SIG={guia:"GUI",rececao:"REC",pagamento:"RCP",entrega:"ENT"};
function novo(l,tipo,ref,versao=1,numero,motivo){const n=numero||`EL-${SIG[tipo]}-2026-${String(l.filter(d=>d.tipo===tipo&&d.versao===1).length+1).padStart(6,"0")}`;
  const d={id:"demo-"+hex(6),empresa_id:"demo-empresa",tipo,numero:n,versao,estado:"valido",referencia:ref,dados:{...base(ref),...(extra[tipo]?.()||{})},codigo_validacao:hex(12),sha256:hex(32),motivo:motivo||null,
    emitido_em:new Date().toISOString(),eventos:[{acao:versao>1?"reemitido":"emitido",detalhe:motivo||null,em:new Date().toISOString()}]};l.unshift(d);return d}
function ler(){try{const l=JSON.parse(localStorage.getItem(CHAVE)||"null");if(Array.isArray(l)&&l.length)return l}catch(_){}
  const l=[];novo(l,"guia","ELO-2026-000123");novo(l,"rececao","ELO-2026-000123");novo(l,"pagamento","ELO-2026-000123");gravar(l);return l}
const gravar=l=>{try{localStorage.setItem(CHAVE,JSON.stringify(l))}catch(_){}};
function logo(){try{return JSON.parse(localStorage.getItem("elolog_provider_settings_"+empresaNome())||"{}").logo||""}catch(_){return""}}
function emitir(ref,tipo){ref=String(ref||"").trim().toUpperCase();if(!/^[A-Z0-9-]{4,40}$/.test(ref))throw new Error("Escreva o código da encomenda (ex.: ELO-2026-000123).");
  const l=ler(),j=l.find(d=>d.referencia===ref&&d.tipo===tipo&&d.estado==="valido");if(j)return j;const d=novo(l,tipo,ref);gravar(l);return d}
function reemitir(d,motivo){if(String(motivo||"").trim().length<5)throw new Error("Indique o motivo da nova versão.");const l=ler(),a=l.find(x=>x.id===d.id);if(!a||a.estado!=="valido")throw new Error("Só a versão em vigor pode ser corrigida.");
  a.estado="substituido";const n=novo(l,a.tipo,a.referencia,a.versao+1,a.numero,motivo.trim());gravar(l);return n}
function historico(d){return ler().filter(x=>x.numero===d.numero).flatMap(x=>(x.eventos||[]).map(e=>({...e,versao:x.versao}))).sort((a,b)=>String(b.em).localeCompare(String(a.em)))}
/* entrega registada no terreno (demonstração): documento EL-ENT com quem recebeu, assinatura e fotografias */
function entrega(ref,p){const l=ler();if(l.some(d=>d.referencia===ref&&d.tipo==="entrega"&&d.estado==="valido"))return;const d=novo(l,"entrega",ref);
  d.dados.entrega={recebido_por:p.recebido_por,identificacao:p.identificacao,feito_em:p.feito_em,lat:p.lat,lon:p.lon,precisao_m:p.precisao,volumes_conferidos:p.volumes,notas:p.notas,assinatura:p.assinatura,motorista:"Mário Motorista",fotos:(p.fotos||[]).length};gravar(l);return d}
window.elologDocDemo={lista:ler,logo,emitir,reemitir,historico,entrega};

/* ---------- menus do cliente e da administração (o do prestador está em prestador/menu-lateral.js) ---------- */
function menus(){
  const cli=document.getElementById("clientFinanceSubmenu");if(cli&&!document.getElementById("menuCentroDoc")){const b=document.createElement("button");b.type="button";b.id="menuCentroDoc";b.textContent="Centro documental";
    b.onclick=()=>elologCentroDoc.abrir(b);cli.appendChild(b)}
  const adm=document.getElementById("adminGrpConf");if(adm&&!document.getElementById("adminMenuCentroDoc")){const b=document.createElement("button");b.type="button";b.id="adminMenuCentroDoc";b.textContent="Centro documental";
    b.onclick=()=>elologCentroDoc.abrir(b);adm.insertBefore(b,adm.firstChild)}}
function ligarMenus(){menus();const c=window.configureRole;if(typeof c==="function"&&!c.__cdoc){const n=function(){const x=c.apply(this,arguments);menus();return x};n.__cdoc=1;window.configureRole=n}}

/* ---------- logótipo do prestador: guardado também no servidor, para as duas marcas aparecerem nos documentos ---------- */
function reduzir(ficheiro){return new Promise((ok,falha)=>{if(!/^image\/(png|jpeg|webp)$/.test(ficheiro.type))return falha(new Error("O logótipo tem de ser uma imagem PNG, JPEG ou WebP."));
  const img=new Image(),url=URL.createObjectURL(ficheiro);img.onload=()=>{const k=Math.min(1,480/img.width,200/img.height),c=document.createElement("canvas");c.width=Math.round(img.width*k);c.height=Math.round(img.height*k);
    c.getContext("2d").drawImage(img,0,0,c.width,c.height);URL.revokeObjectURL(url);let d=c.toDataURL("image/png");if(d.length>380000)d=c.toDataURL("image/jpeg",0.85);d.length>390000?falha(new Error("O logótipo é demasiado grande.")):ok(d)};
  img.onerror=()=>falha(new Error("Não conseguimos ler esta imagem."));img.src=url})}
function ligarLogo(){const g=window.saveProviderSettings;if(typeof g!=="function"||g.__cdoc)return;const n=function(){const f=document.getElementById("providerSettingLogo")?.files?.[0],r=g.apply(this,arguments);
    if(f&&window.elologProducao?.online?.())reduzir(f).then(async d=>{const sb=await elologProducao.sb();const{error}=await sb.rpc("definir_logotipo",{p_logotipo:d});if(error)throw error;
      document.getElementById("providerSettingsFeedback")?.insertAdjacentHTML("beforeend",'<div class="sim-success" role="status">Logótipo guardado: aparece nos documentos ao lado da marca Elolog.</div>')})
      .catch(e=>document.getElementById("providerSettingsFeedback")?.insertAdjacentHTML("beforeend",`<div class="sim-warning" role="status">O logótipo não foi para os documentos: ${elologDocModelo.esc(String(e.message||e).replace(/^.*?ERROR:\s*/,""))}</div>`));return r};
  n.__cdoc=1;window.saveProviderSettings=n}
function iniciar(){ligarMenus();ligarLogo()}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",iniciar);else iniciar();
})();
