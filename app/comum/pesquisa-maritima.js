/* Elolog — EloLog Maritime Search 1/2 (v87): pesquisar navios, partidas, chegadas e espaço disponível Portugal ⇄ São Tomé e Príncipe.
   Usa a ligação Supabase JÁ EXISTENTE da plataforma (window.elologProducao.sb → ELOLogServidor.cliente). Não cria clientes nem altera a configuração.
   Dados: tabela viagens_maritimas (publicadas pelos prestadores) + posição AIS real (navios_posicoes), pela função pesquisa_maritima (migração 00153).
   Sem servidor (modo de demonstração) mostra viagens fictícias, identificadas como tal. A publicação/edição está em pesquisa-maritima-form.js. */
(function(){"use strict";
const P=()=>window.elologProducao,esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const PORTOS={PT:["Lisboa","Leixões","Setúbal","Sines","Aveiro","Figueira da Foz"],STP:["São Tomé","Neves"]};
const ESTADOS={planeada:["Planeada","cinza"],aberta:["Aberta a carga","ver"],lotada:["Lotada","verm"],partiu:["Partiu","azl"],chegou:["Chegou","ver"],atrasada:["Atrasada","amb"],cancelada:["Cancelada","verm"]};
const hoje=()=>new Date().toISOString().slice(0,10),mais=d=>{const x=new Date();x.setDate(x.getDate()+d);return x.toISOString().slice(0,10)};
const M={j:null,f:{vista:"partidas",sentido:"PT-STP",texto:"",porto:"",de:hoje(),ate:mais(120),livre:false},lista:[],erro:"",demo:false,carregando:false};

const dataPt=d=>d?new Date(d+"T12:00:00").toLocaleDateString("pt-PT",{day:"2-digit",month:"short",year:"numeric"}):"—";
const faltam=d=>{if(!d)return"";const n=Math.round((new Date(d+"T12:00:00")-new Date(hoje()+"T12:00:00"))/864e5);return n===0?"hoje":n===1?"amanhã":n>0?`daqui a ${n} dias`:n===-1?"ontem":`há ${-n} dias`};
const atras=t=>{const m=Math.round((Date.now()-new Date(t))/6e4);return m<60?`há ${Math.max(1,m)} min`:m<1440?`há ${Math.round(m/60)} h`:`há ${Math.round(m/1440)} dias`};
const podePublicar=()=>currentUser?.role==="prestador"&&["admin","operador"].includes(typeof providerFunction==="function"?providerFunction():"");

function demo(){const v=(id,navio,linha,viagem,s,o,d,p,c,f,est,c20,c40,m3,vt,ais)=>({id,navio,linha,viagem,sentido:s,porto_origem:o,porto_destino:d,partida:mais(p),chegada:mais(c),
  fecho_carga:mais(f),estado:est,cont20_livres:c20,cont40_livres:c40,grupagem_m3:m3,aceita_viaturas:vt,prestador:"Prestador de demonstração",...(ais||{})});
  return[v("d1","Navio Exemplo Atlântico","Linha Demo","D101","PT-STP","Lisboa","São Tomé",6,20,3,"aberta",3,1,18,true),
    v("d2","Navio Exemplo Equador","Linha Demo","D102","PT-STP","Leixões","São Tomé",19,34,15,"aberta",0,2,6,false),
    v("d3","Navio Exemplo Golfo","Linha Demo","D201","STP-PT","São Tomé","Lisboa",9,24,7,"planeada",5,0,30,false),
    v("d4","Navio Exemplo Atlântico","Linha Demo","D099","PT-STP","Lisboa","São Tomé",-8,6,-11,"partiu",0,0,0,false,{latitude:14.6,longitude:-21.4,velocidade_nos:13.2,posicao_em:new Date(Date.now()-42*6e4).toISOString()}),
    v("d5","Navio Exemplo Equador","Linha Demo","D103","PT-STP","Lisboa","São Tomé",40,54,36,"lotada",0,0,0,false)]}

async function carregar(){const f=M.f;M.carregando=true;M.erro="";desenhar();
  try{if(!P()?.online()){M.demo=true;const t=f.texto.toLowerCase(),por=f.vista==="chegadas"?"chegada":"partida";
      M.lista=demo().filter(x=>(!f.sentido||x.sentido===f.sentido)&&(!t||[x.navio,x.linha,x.viagem].join(" ").toLowerCase().includes(t))&&(!f.porto||[x.porto_origem,x.porto_destino].includes(f.porto))
        &&(!f.de||x[por]>=f.de)&&(!f.ate||x[por]<=f.ate)&&(!f.livre||(["aberta","planeada"].includes(x.estado)&&(x.cont20_livres+x.cont40_livres>0||x.grupagem_m3>0))))}
    else{M.demo=false;const sb=await P().sb();const{data,error}=await sb.rpc("pesquisa_maritima",{p_texto:f.texto||null,p_sentido:f.sentido||null,p_de:f.de||null,
      p_ate:f.ate||null,p_porto:f.porto||null,p_so_disponivel:f.vista==="disponibilidade"||f.livre,p_por:f.vista==="chegadas"?"chegada":"partida"});if(error)throw error;M.lista=data||[]}}
  catch(e){M.erro=window.ELOLogServidor?.mensagem?.(e)||e.message||"Não foi possível pesquisar.";M.lista=[]}
  finally{M.carregando=false;desenhar()}}

function espaco(x){const c=[];if(x.cont20_livres)c.push(`20' × ${x.cont20_livres}`);if(x.cont40_livres)c.push(`40' × ${x.cont40_livres}`);
  if(Number(x.grupagem_m3))c.push(`Grupagem ${Number(x.grupagem_m3).toLocaleString("pt-PT")} m³`);if(x.aceita_viaturas)c.push("Viaturas");
  return c.length?c.map(t=>`<span class="mm-chip ok">${esc(t)}</span>`).join(""):'<span class="mm-chip">Sem espaço indicado</span>'}

function cartao(x){const[est,cor]=ESTADOS[x.estado]||[x.estado,"cinza"];
  const ais=x.posicao_em?`<p class="mm-ais"><span class="mm-ponto"></span>Posição real (AIS) ${esc(atras(x.posicao_em))}${x.velocidade_nos!=null?` · ${esc(Number(x.velocidade_nos).toFixed(1))} nós`:""}${x.destino_ais?` · destino ${esc(x.destino_ais)}`:""}
    · <a href="https://www.openstreetmap.org/?mlat=${Number(x.latitude)}&mlon=${Number(x.longitude)}#map=6/${Number(x.latitude)}/${Number(x.longitude)}" target="_blank" rel="noopener">ver no mapa</a></p>`:"";
  const fecho=x.fecho_carga&&["aberta","planeada","atrasada"].includes(x.estado)?`<small class="mm-fecho">Entregar a carga até <b>${esc(dataPt(x.fecho_carga))}</b> (${esc(faltam(x.fecho_carga))})</small>`:"";
  const acoes=x.minha&&podePublicar()?`<button type="button" class="btn-secondary" data-editar="${esc(x.id)}">Editar</button>`:currentUser?.role==="cliente"&&["aberta","planeada","atrasada"].includes(x.estado)?`<button type="button" class="btn-primary" data-cotar="${esc(x.id)}">Pedir cotação</button>`:"";
  return`<li class="mm-viagem"><div class="mm-topo"><div><strong>${esc(x.navio)}</strong><small>${esc([x.linha,x.viagem&&"viagem "+x.viagem,x.imo&&"IMO "+x.imo].filter(Boolean).join(" · "))}</small></div><span class="work-status mm-est ${cor}">${esc(est)}</span></div>
    <div class="mm-rota"><div><small>Partida · ${esc(x.porto_origem)}</small><b>${esc(dataPt(x.partida))}</b><em>${esc(faltam(x.partida))}</em></div><span class="mm-seta" aria-hidden="true">⟶</span>
      <div><small>Chegada · ${esc(x.porto_destino)}</small><b>${esc(dataPt(x.chegada))}</b><em>${x.chegada?esc(faltam(x.chegada)):"por confirmar"}</em></div></div>
    ${fecho}<div class="mm-chips">${espaco(x)}</div>${ais}<div class="mm-rodape"><small>${esc(x.prestador||"")}${x.notas?" · "+esc(x.notas):""}</small>${acoes}</div></li>`}

function navios(){const g=new Map;M.lista.forEach(x=>{const k=x.navio.toLowerCase();const n=g.get(k)||{navio:x.navio,imo:x.imo,mmsi:x.mmsi,linha:x.linha,viagens:[],ais:null};
  n.viagens.push(x);if(x.posicao_em&&(!n.ais||x.posicao_em>n.ais.posicao_em))n.ais=x;g.set(k,n)});
  return[...g.values()].map(n=>{const prox=n.viagens.filter(v=>v.partida>=hoje()).sort((a,b)=>a.partida.localeCompare(b.partida))[0];
    return`<li class="mm-viagem mm-navio"><div class="mm-topo"><div><strong>🚢 ${esc(n.navio)}</strong><small>${esc([n.linha,n.imo&&"IMO "+n.imo,n.mmsi&&"MMSI "+n.mmsi].filter(Boolean).join(" · "))}</small></div><span class="mm-chip">${n.viagens.length} viage${n.viagens.length===1?"m":"ns"}</span></div>
      <p>${prox?`Próxima partida: <b>${esc(prox.porto_origem)} → ${esc(prox.porto_destino)}</b>, ${esc(dataPt(prox.partida))} (${esc(faltam(prox.partida))})`:"Sem partidas futuras no período."}</p>
      ${n.ais?`<p class="mm-ais"><span class="mm-ponto"></span>Última posição AIS ${esc(atras(n.ais.posicao_em))}${n.ais.velocidade_nos!=null?` · ${esc(Number(n.ais.velocidade_nos).toFixed(1))} nós`:""}</p>`:""}</li>`}).join("")}

function desenhar(){if(!M.j?.corpo?.isConnected)return;const f=M.f,c=M.j.corpo;
  const vistas=[["partidas","Partidas"],["chegadas","Chegadas"],["navios","Navios"],["disponibilidade","Com espaço"]].map(([k,t])=>`<button type="button" role="tab" aria-selected="${f.vista===k}" class="${f.vista===k?"ativo":""}" data-vista="${k}">${t}</button>`).join("");
  const sent=[["PT-STP","Portugal → São Tomé"],["STP-PT","São Tomé → Portugal"],["","Ambos"]].map(([k,t])=>`<option value="${k}" ${f.sentido===k?"selected":""}>${t}</option>`).join("");
  const portos=`<option value="">Todos os portos</option>`+[["Portugal",PORTOS.PT],["São Tomé e Príncipe",PORTOS.STP]].map(([g,l])=>`<optgroup label="${g}">${l.map(p=>`<option ${f.porto===p?"selected":""}>${p}</option>`).join("")}</optgroup>`).join("");
  const corpo=M.carregando?'<p class="mm-vazio">A pesquisar…</p>':M.erro?`<p class="mm-vazio erro">⚠ ${esc(M.erro)}</p>`:!M.lista.length?`<p class="mm-vazio">Nenhuma viagem encontrada com estes filtros.${M.demo?"":" As viagens aparecem quando os prestadores as publicarem."}</p>`
    :`<ul class="mm-lista">${f.vista==="navios"?navios():M.lista.map(cartao).join("")}</ul>`;
  c.innerHTML=`<div class="mm">${M.demo?'<p class="mm-demo">Dados fictícios de demonstração</p>':""}<div class="mm-vistas" role="tablist">${vistas}</div>
    <form class="mm-filtros" role="search"><label class="mm-q"><span>Navio, linha ou viagem</span><input type="search" name="texto" maxlength="60" value="${esc(f.texto)}" placeholder="Ex.: nome do navio"></label>
      <label><span>Sentido</span><select name="sentido">${sent}</select></label><label><span>Porto</span><select name="porto">${portos}</select></label>
      <label><span>${f.vista==="chegadas"?"Chegada":"Partida"} de</span><input type="date" name="de" value="${esc(f.de)}"></label><label><span>até</span><input type="date" name="ate" value="${esc(f.ate)}"></label>
      <label class="mm-livre"><input type="checkbox" name="livre" ${f.livre||f.vista==="disponibilidade"?"checked":""} ${f.vista==="disponibilidade"?"disabled":""}> Só com espaço disponível</label>
      <button type="submit" class="btn-primary">Pesquisar</button>${podePublicar()?'<button type="button" class="btn-secondary" data-publicar>+ Publicar viagem</button>':""}</form>
    <p class="mm-conta" aria-live="polite">${M.carregando?"":`${M.lista.length} ${M.lista.length===1?"viagem":"viagens"}`}</p>${corpo}</div>`}

function eventos(c){c.addEventListener("click",e=>{const b=e.target.closest("button");if(!b)return;
    if(b.dataset.vista){M.f.vista=b.dataset.vista;carregar()}else if(b.dataset.publicar!==undefined)window.elologMaritimoForm?.abrir(null,carregar);
    else if(b.dataset.editar)window.elologMaritimoForm?.abrir(M.lista.find(x=>x.id===b.dataset.editar),carregar);
    else if(b.dataset.cotar)cotar(M.lista.find(x=>x.id===b.dataset.cotar))});
  c.addEventListener("submit",e=>{e.preventDefault();const d=new FormData(e.target);Object.assign(M.f,{texto:String(d.get("texto")||"").trim(),sentido:String(d.get("sentido")||""),
    porto:String(d.get("porto")||""),de:String(d.get("de")||""),ate:String(d.get("ate")||""),livre:d.get("livre")==="on"});carregar()})}

function cotar(x){if(!x)return;M.j?.fechar();try{showPage("clientSimulation",document.getElementById("menuSimulation"))}catch(_){}
  const por=(id,v)=>{const el=document.getElementById(id);if(el&&v)el.value=v};por("clientSimOrigin",x.porto_origem);por("clientSimDestination",x.porto_destino);
  const n=document.getElementById("clientSimObservations");if(n&&!n.value)n.value=`Navio ${x.navio}${x.viagem?" (viagem "+x.viagem+")":""}, partida ${dataPt(x.partida)} — ${x.prestador||""}`;}

window.elologMaritimo={abrir(){if(!P())return;M.j=P().janela({eyebrow:"MARITIME SEARCH · PORTUGAL ⇄ SÃO TOMÉ E PRÍNCIPE",titulo:"Pesquisa marítima"});
  M.j.corpo.closest(".pm-caixa").classList.add("mm-janela");M.j.mostrar("",[]);eventos(M.j.corpo);carregar()},recarregar:carregar,PORTOS,ESTADOS};
})();
