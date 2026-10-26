let volumeId=0;let prestadorSelecionado=null;let simulacaoAtual=null;const METODOS_COBRANCA={unidade:{label:"Por unidade",unidade:"unidade"},volume:{label:"Por volume",unidade:"m³"},peso:{label:"Por peso",unidade:"kg"},contentor:{label:"Por contentor",
unidade:"contentor"},dimensao:{label:"Por dimensão",unidade:"m³"},fixo:{label:"Preço fixo",unidade:"carga"}};function normalizarTexto(valor){return String(valor||"").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g,"")}
function metodoCobrancaAutomatico(tipo){const t=normalizarTexto(tipo);if(t.includes("veiculo")||t.includes("bidão")||t.includes("bidao"))return"unidade";return null}function obterPrestadoresRegistados(){let perfis=[];try{
perfis=JSON.parse(localStorage.getItem("elolog_profiles")||"[]")}catch(_){perfis=[]}return perfis.filter(p=>p.type==="prestador"&&(p.validationStatus==="approved"||p.status==="Ativo")&&!["Suspenso","Recusado",
"Expirado"].includes(p.status)&&(!p.subscription||p.subscriptionPayment?.status==="Pago")).map(p=>{const nome=p.name;const configurada=obterTarifaFinanceiraAtiva({nome},{},{});return{id:String(p.id||chaveFinanceiraPrestador(nome)).replace(/[^a-zA-Z0-9_-]/g,
"-"),profileId:p.id,nome,displayName:p.tradeName||p.name,financeName:p.name,tarifa:configurada?Number(configurada.value):null,armazem:[p.address,p.city,p.country].filter(Boolean).join(", "),registado:true}})}function obterPrestadoresDisponiveis(){
return obterPrestadoresRegistados()}function chaveFinanceiraPrestador(nome){const slug=normalizarTexto(nome).replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"")||"empresa";return`elolog_finance_${slug}`}function obterTarifaFinanceiraAtiva(prestador,rota,detalhes){
let dados;try{dados=JSON.parse(localStorage.getItem(chaveFinanceiraPrestador(prestador.financeName||prestador.nome))||"null")}catch(_){dados=null}if(!dados?.tariffs?.length)return null;const hoje=new Date().toISOString().slice(0,10);
const corresponde=(configurado,atual)=>!configurado||!atual||normalizarTexto(atual).includes(normalizarTexto(configurado))||normalizarTexto(configurado).includes(normalizarTexto(atual));
return dados.tariffs.filter(t=>t.status==="Ativa"&&(!t.startDate||t.startDate<=hoje)&&(!t.endDate||t.endDate>=hoje)&&corresponde(t.origin,rota.origem)&&corresponde(t.destination,rota.destino)&&corresponde(t.cargoType,detalhes.tipoCarga)).sort((a,
b)=>Boolean(b.origin)+Boolean(b.destination)+Boolean(b.cargoType)-(Boolean(a.origin)+Boolean(a.destination)+Boolean(a.cargoType)))[0]||null}const COORDENADAS_CONHECIDAS={};let distanciasPrestadores={};let pedidoDistancia=0;
async function obterCoordenadas(localizacao){const chave=normalizarTexto(localizacao).trim().replace(/\s+/g," ");if(COORDENADAS_CONHECIDAS[chave])return COORDENADAS_CONHECIDAS[chave];
const resposta=await fetch("https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&accept-language=pt&q="+encodeURIComponent(localizacao));if(!resposta.ok)throw new Error("Serviço de localização indisponível");const resultados=await resposta.json();
if(!resultados.length)throw new Error("Morada não encontrada");return{lat:Number(resultados[0].lat),lon:Number(resultados[0].lon)}}function distanciaEmKm(a,b){const r=6371,rad=Math.PI/180;const dLat=(b.lat-a.lat)*rad,dLon=(b.lon-a.lon)*rad;
const h=Math.sin(dLat/2)**2+Math.cos(a.lat*rad)*Math.cos(b.lat*rad)*Math.sin(dLon/2)**2;return Math.round(r*2*Math.atan2(Math.sqrt(h),Math.sqrt(1-h)))}async function atualizarDistanciaRecolha(){
const recolha=document.getElementById("pretende-recolha")?.value==="sim";const grupo=document.getElementById("distancia-group");const campo=document.getElementById("distancia");const status=document.getElementById("distancia-status");
if(grupo)grupo.hidden=!recolha;if(!recolha){distanciasPrestadores={};if(campo)campo.value="0";calcular();invalidarSimulacao();return}const morada=document.getElementById("morada-recolha")?.value.trim();if(!morada){if(campo)campo.value="0";if(status){
status.textContent="Indique a morada de recolha.";status.className="distance-status"}return}const idPedido=++pedidoDistancia;if(status){status.textContent="A calcular automaticamente…";status.className="distance-status is-calculating"}try{
const origem=await obterCoordenadas(morada);const prestadores=obterPrestadoresDisponiveis();const comArmazem=prestadores.filter(p=>p.armazem);if(!comArmazem.length){if(idPedido!==pedidoDistancia)return;
distanciasPrestadores=Object.fromEntries(prestadores.map(p=>[p.id,0]));if(campo)campo.value="0";if(status){status.textContent="Morada de recolha validada.";status.className="distance-status is-ready"}calcular();invalidarSimulacao();
atualizarProgressoSimulacao();return}const coordenadas=await Promise.all(comArmazem.map(p=>obterCoordenadas(p.armazem)));if(idPedido!==pedidoDistancia)return;distanciasPrestadores=Object.fromEntries(comArmazem.map((p,i)=>[p.id,distanciaEmKm(origem,
coordenadas[i])]));const menor=Math.min(...Object.values(distanciasPrestadores));if(campo)campo.value=String(menor);if(status){status.textContent=`Armazém mais próximo: ${menor} km`;status.className="distance-status is-ready"}calcular();invalidarSimulacao()}
catch(erro){if(idPedido!==pedidoDistancia)return;distanciasPrestadores={};if(campo)campo.value="0";if(status){status.textContent="Não foi possível calcular. Verifique a morada.";status.className="distance-status is-error"}}}
function adicionarVolume(descricao="",peso="",comprimento="",largura="",altura="",qtd=""){volumeId++;const container=document.getElementById("lista-volumes");const item=document.createElement("div");item.id=`volume-${volumeId}`;item.className="volume-item";
item.innerHTML=`
    <div><label class="vol-label">Carga / descrição</label><input type="text" value="${descricao}" class="carga vol-input" placeholder="Ex.: Bidão, carro, caixas..."></div>
    <div><label class="vol-label">Qtd.</label><input type="number" value="${qtd}" min="1" class="qtd vol-input" placeholder="1"></div>
    <div><label class="vol-label">Peso (kg)</label><input type="number" value="${peso}" min="0" step="0.01" class="peso vol-input" placeholder="0,00"></div>
    <div><label class="vol-label" title="Comprimento">Comp. (cm)</label><input type="number" value="${comprimento}" min="1" class="comp vol-input" placeholder="0"></div>
    <div><label class="vol-label" title="Largura">Larg. (cm)</label><input type="number" value="${largura}" min="1" class="larg vol-input" placeholder="0"></div>
    <div><label class="vol-label" title="Altura">Alt. (cm)</label><input type="number" value="${altura}" min="1" class="alt vol-input" placeholder="0"></div>
    <div><label class="vol-label">Volume</label><strong class="volume-row-total">0,000 m³</strong></div>
    <div><button type="button" onclick="removerVolume(${volumeId})" class="btn-delete" title="Remover volume" aria-label="Remover volume">✕</button></div>`;
container.appendChild(item);item.querySelectorAll("input").forEach(input=>input.addEventListener("input",()=>{calcular();atualizarCalculoVolumes();invalidarSimulacao();atualizarProgressoSimulacao()}));atualizarCalculoVolumes();atualizarProgressoSimulacao()}
function removerVolume(id){const item=document.getElementById(`volume-${id}`);if(item){item.remove();calcular();atualizarCalculoVolumes();invalidarSimulacao();atualizarProgressoSimulacao()}}function atualizarCalculoVolumes(){
const linhas=[...document.querySelectorAll("#lista-volumes > div")];const totalEl=document.getElementById("volume-total-inline");let total=0;linhas.forEach((linha,index)=>{const qtd=parseFloat(linha.querySelector(".qtd")?.value);
const comp=parseFloat(linha.querySelector(".comp")?.value);const larg=parseFloat(linha.querySelector(".larg")?.value);const alt=parseFloat(linha.querySelector(".alt")?.value);const resultado=linha.querySelector(".volume-row-total");if([qtd,comp,larg,
alt].every(v=>Number.isFinite(v)&&v>0)){const subtotal=comp/100*(larg/100)*(alt/100);total+=subtotal;if(resultado)resultado.textContent=`${subtotal.toFixed(3).replace(".",",")} m³`}else if(resultado){resultado.textContent="—"}});
if(totalEl)totalEl.textContent=`Volume total: ${total.toFixed(3).replace(".",",")} m³`}function obterDadosCarga(){const linhas=[...document.querySelectorAll("#lista-volumes > div")];let volumeTotalM3=0,totalPacotes=0,pesoTotalKg=0,completo=linhas.length>0;
const volumes=[];linhas.forEach(linha=>{const carga=linha.querySelector(".carga")?.value.trim()||"";const qtd=parseFloat(linha.querySelector(".qtd")?.value);const peso=parseFloat(linha.querySelector(".peso")?.value);
const comp=parseFloat(linha.querySelector(".comp")?.value);const larg=parseFloat(linha.querySelector(".larg")?.value);const alt=parseFloat(linha.querySelector(".alt")?.value);const dimensoesValidas=[qtd,comp,larg,alt].every(v=>Number.isFinite(v)&&v>0);
const pesoValido=Number.isFinite(peso)&&peso>=0;if(!carga||!dimensoesValidas||!pesoValido)completo=false;let volumeM3=0;if(dimensoesValidas){volumeM3=comp/100*(larg/100)*(alt/100);volumeTotalM3+=volumeM3;totalPacotes+=qtd}
if(Number.isFinite(peso)&&peso>=0&&Number.isFinite(qtd)&&qtd>0){pesoTotalKg+=peso*qtd}volumes.push({carga,quantidade:Number.isFinite(qtd)?qtd:0,pesoKgPorUnidade:Number.isFinite(peso)?peso:0,comprimentoCm:Number.isFinite(comp)?comp:0,
larguraCm:Number.isFinite(larg)?larg:0,alturaCm:Number.isFinite(alt)?alt:0,volumeM3})});return{volumeTotalM3,totalPacotes,pesoTotalKg,completo,volumes}}function obterDadosRota(){return{origem:document.getElementById("origem")?.value.trim()||"",
destino:document.getElementById("destino")?.value.trim()||"",moradaRecolha:document.getElementById("morada-recolha")?.value.trim()||"",cargo:document.getElementById("tipo-carga-detalhe")?.value||document.getElementById("tipo-carga")?.value||"",
data:document.getElementById("data-prevista")?.value||"",recolha:document.getElementById("pretende-recolha")?.value||"sim"}}function obterRemetente(){return{nome:document.getElementById("remetente-nome")?.value.trim()||"",
nif:document.getElementById("remetente-nif")?.value.trim()||"",telefone:document.getElementById("remetente-telefone")?.value.trim()||"",email:document.getElementById("remetente-email")?.value.trim()||"",
morada:document.getElementById("remetente-morada")?.value.trim()||""}}function obterDestinatario(){return{nome:document.getElementById("destinatario-nome")?.value.trim()||"",nif:document.getElementById("destinatario-nif")?.value.trim()||"",
telefone:document.getElementById("destinatario-telefone")?.value.trim()||"",email:document.getElementById("destinatario-email")?.value.trim()||"",morada:document.getElementById("destinatario-morada")?.value.trim()||""}}function obterDetalhesCarga(){
const tipoCarga=document.getElementById("tipo-carga-detalhe")?.value||document.getElementById("tipo-carga")?.value||"";const metodo=metodoCobrancaAutomatico(tipoCarga)||"volume";const{totalPacotes,pesoTotalKg,volumes}=obterDadosCarga();return{tipoCarga,
metodoCobranca:metodo,unidadeCobranca:METODOS_COBRANCA[metodo]?.unidade||"unidade",quantidadeUnidades:totalPacotes,pesoTotalKg,volumes,precoDeclarado:parseFloat(document.getElementById("preco-declarado")?.value)||0,
observacoes:document.getElementById("observacoes-carga")?.value.trim()||""}}function calcular(){const km=parseFloat(document.getElementById("distancia")?.value)||0;const{volumeTotalM3,totalPacotes}=obterDadosCarga();const pesoVolumetrico=volumeTotalM3*167;
document.getElementById("res-distancia").innerText=`${km} km`;document.getElementById("res-qtd-pacotes").innerText=totalPacotes;document.getElementById("res-volume-m3").innerText=`${volumeTotalM3.toFixed(3)} m³`;
document.getElementById("res-peso-vol").innerText=`${pesoVolumetrico.toFixed(1)} kg`;return{volumeTotalM3,totalPacotes}}function gerarNumeroSimulacao(){const agora=new Date;const data=agora.toISOString().slice(0,10).replace(/-/g,"");
return`SIM-${data}-${Math.floor(1e3+Math.random()*9e3)}`}function formatarDataHora(data){return new Intl.DateTimeFormat("pt-PT",{dateStyle:"short",timeStyle:"short"}).format(data)}function mostrarErroSimulacao(mensagem,campoId){
const aviso=document.getElementById("simulation-validation");if(aviso){aviso.hidden=false;aviso.innerHTML=`<strong>Verifique os dados</strong><span>${mensagem}</span>`;aviso.scrollIntoView({behavior:"smooth",block:"nearest"})}
const campo=campoId?document.getElementById(campoId):null;if(campo){campo.classList.add("field-invalid");campo.focus({preventScroll:true})}}function limparErroSimulacao(){const aviso=document.getElementById("simulation-validation");if(aviso){aviso.hidden=true;
aviso.innerHTML=""}document.querySelectorAll(".field-invalid").forEach(campo=>campo.classList.remove("field-invalid"))}function atualizarProgressoSimulacao(){const remetente=obterRemetente();const destinatario=obterDestinatario();const rota=obterDadosRota();
const carga=obterDadosCarga();const detalhes=obterDetalhesCarga();const estados=[Boolean(remetente.nome&&remetente.telefone&&remetente.morada),Boolean(destinatario.nome&&destinatario.telefone&&destinatario.morada),
Boolean(rota.origem&&rota.destino&&detalhes.tipoCarga&&carga.completo&&carga.volumeTotalM3>0),Boolean(simulacaoAtual)];let concluidas=0;estados.forEach((feito,indice)=>{if(feito)concluidas++;const etapa=document.querySelectorAll(".simulation-step")[indice];
etapa?.classList.toggle("is-complete",feito);etapa?.classList.toggle("is-active",!feito&&indice===estados.findIndex(valor=>!valor))});if(estados.every(Boolean))document.querySelector(".simulation-step:last-child")?.classList.add("is-active");
const fill=document.getElementById("simulation-progress-fill");if(fill)fill.style.width=`${Math.min(100,concluidas/estados.length*100)}%`}function criarSimulacao(){const{volumeTotalM3,completo,totalPacotes}=obterDadosCarga();const rota=obterDadosRota();
const remetente=obterRemetente();const destinatario=obterDestinatario();limparErroSimulacao();if(!remetente.nome||!remetente.telefone||!remetente.morada){mostrarErroSimulacao("Preencha o nome, telefone e morada do remetente.",
!remetente.nome?"remetente-nome":!remetente.telefone?"remetente-telefone":"remetente-morada");return}if(!destinatario.nome||!destinatario.telefone||!destinatario.morada){mostrarErroSimulacao("Preencha o nome, telefone e morada do destinatário.",
!destinatario.nome?"destinatario-nome":!destinatario.telefone?"destinatario-telefone":"destinatario-morada");return}if(!rota.origem||!rota.destino){mostrarErroSimulacao("Preencha a origem e o destino da operação.",!rota.origem?"origem":"destino");return}
if(rota.recolha==="sim"&&(!rota.moradaRecolha||!Object.keys(distanciasPrestadores).length)){mostrarErroSimulacao("Indique uma morada de recolha válida e aguarde o cálculo automático da distância.","morada-recolha");return}
const detalhesCarga=obterDetalhesCarga();if(!detalhesCarga.tipoCarga){mostrarErroSimulacao("Selecione o tipo de carga antes de criar a simulação.","tipo-carga-detalhe");return}if(!completo||volumeTotalM3<=0){
mostrarErroSimulacao("Preencha a descrição, quantidade, peso e dimensões de todos os volumes.");return}calcular();const agora=new Date;simulacaoAtual={numero:gerarNumeroSimulacao(),dataHora:agora,volumeTotalM3,totalPacotes,...rota,remetente,destinatario,
...detalhesCarga};mostrarResumoSimulacao();renderizarPrestadores(volumeTotalM3,rota);atualizarProgressoSimulacao()}function mostrarResumoSimulacao(){const resumo=document.getElementById("simulation-summary");resumo.hidden=false;
resumo.setAttribute("aria-hidden","false");document.getElementById("sim-registro").textContent=simulacaoAtual.numero;document.getElementById("sim-datahora").textContent=formatarDataHora(simulacaoAtual.dataHora);
document.getElementById("sim-volume").textContent=`${simulacaoAtual.volumeTotalM3.toFixed(3)} m³`;document.getElementById("sim-valor").textContent="A aguardar proposta";
document.getElementById("simulation-message").textContent=`Simulação efetuada em ${formatarDataHora(simulacaoAtual.dataHora)} · Registo ${simulacaoAtual.numero}`}function calcularPropostaPrestador(prestador,volumeTotalM3,rota){
const detalhes=simulacaoAtual||obterDetalhesCarga();const metodo=detalhes.metodoCobranca||"volume";const{totalPacotes}=obterDadosCarga();const configurada=obterTarifaFinanceiraAtiva(prestador,rota,detalhes);
const tarifa=Number(configurada?.value??prestador.tarifa);const metodoConfigurado=normalizarTexto(configurada?.method||"");let base=0;if(metodoConfigurado.includes("fixo")){base=tarifa}
else if(metodoConfigurado.includes("peso")&&!metodoConfigurado.includes("medida")){const pesoReal=Number(detalhes.pesoTotalKg||0);const pesoVolumetrico=volumeTotalM3*Number(configurada?.rules?.volumetricFactor||167);base=Math.max(pesoReal,
pesoVolumetrico)*tarifa}else if(metodoConfigurado.includes("unidade")||metodoConfigurado.includes("quantidade")||metodo==="unidade"){base=totalPacotes*tarifa}
else if(metodo==="volume"||metodo==="dimensao"||metodoConfigurado.includes("volume")||metodoConfigurado.includes("w/m")){base=volumeTotalM3*tarifa}else if(metodo==="fixo"){base=tarifa}else{base=volumeTotalM3*tarifa}base=Math.max(base,
Number(configurada?.minimumPrice||0));const custoRecolha=rota.recolha==="sim"?distanciasPrestadores[prestador.id]||0:0;return Number((base+custoRecolha).toFixed(2))}function renderizarPrestadores(volumeTotalM3,rota){
const section=document.getElementById("prestadores-section");const grid=document.getElementById("prestadores-grid");section.hidden=false;section.classList.add("visible");section.setAttribute("aria-hidden","false");
const prestadores=obterPrestadoresDisponiveis();prestadorSelecionado=null;window.prestadorSelecionado=null;const btnProposta=document.getElementById("btn-criar-proposta");const estadoProposta=document.getElementById("proposta-action-status");
if(btnProposta)btnProposta.disabled=true;if(estadoProposta)estadoProposta.textContent=prestadores.length?"Selecione um prestador para continuar.":"Nenhum prestador registado está disponível para esta simulação.";if(!prestadores.length){
grid.innerHTML='<div class="providers-empty"><strong>Sem prestadores disponíveis</strong><p>Ainda não existem prestadores registados, validados e ativos com acesso a esta simulação.</p></div>';section.scrollIntoView({behavior:"smooth",block:"start"});
atualizarProgressoSimulacao();return}grid.innerHTML=prestadores.map(p=>{const configurada=obterTarifaFinanceiraAtiva(p,rota,simulacaoAtual||obterDetalhesCarga());const semTarifa=p.registado&&!configurada;
if(semTarifa)return`<article class="provider-card provider-card-unavailable" data-provider="${p.id}" aria-disabled="true">
      <span class="provider-check">!</span>
      <div class="provider-name">${p.displayName||p.nome}</div>
      <div class="provider-price-label">Preço total</div>
      <div class="provider-price">A aguardar tarifa</div>
      <div class="provider-choice">Prestador disponível após configurar a rota</div>
    </article>`;
const valor=calcularPropostaPrestador(p,volumeTotalM3,rota);const valorFormatado=valor.toFixed(2).replace(".",",");
return`<article class="provider-card" data-provider="${p.id}" data-total="${valor}" onclick="selecionarPrestador('${p.id}', ${valor})" tabindex="0" onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();selecionarPrestador('${p.id}', ${valor})}">
      <span class="provider-check">✓</span>
      <div class="provider-name">${p.displayName||p.nome}</div>
      <div class="provider-price-label">Preço total</div>
      <div class="provider-price">${valorFormatado} €</div>
      <div class="provider-choice">Selecionar proposta <span>→</span></div>
    </article>`}
).join("");section.scrollIntoView({behavior:"smooth",block:"start"})}function selecionarPrestador(id,valor){const prestador=obterPrestadoresDisponiveis().find(p=>p.id===id);if(!prestador||!simulacaoAtual)return;prestadorSelecionado={...prestador,valor,
numeroSimulacao:simulacaoAtual.numero};window.prestadorSelecionado={...prestadorSelecionado,total:Number(valor)};document.querySelectorAll(".provider-card").forEach(card=>card.classList.toggle("selected",card.dataset.provider===id));
const valorFormatado=Number(valor).toFixed(2).replace(".",",");const resumoValor=document.getElementById("sim-valor");if(resumoValor)resumoValor.textContent=`${valorFormatado} €`;const aviso=document.getElementById("prestador-escolhido");aviso.hidden=false;
aviso.innerHTML=`<strong>${prestador.displayName||prestador.nome}</strong> selecionado para a simulação <strong>${simulacaoAtual.numero}</strong>. <span class="selected-total">Preço total: <strong>${valorFormatado} €</strong></span>`;
const btnProposta=document.getElementById("btn-criar-proposta");const estadoProposta=document.getElementById("proposta-action-status");if(btnProposta){btnProposta.disabled=false;btnProposta.textContent="Criar proposta ao prestador escolhido →"}
if(estadoProposta)estadoProposta.textContent=`${prestador.displayName||prestador.nome} selecionado · ${valorFormatado} €`}function invalidarSimulacao(){simulacaoAtual=null;prestadorSelecionado=null;window.prestadorSelecionado=null;
const resumo=document.getElementById("simulation-summary");const section=document.getElementById("prestadores-section");if(resumo){resumo.hidden=true;resumo.setAttribute("aria-hidden","true")}if(section){section.classList.remove("visible");section.hidden=true;
section.setAttribute("aria-hidden","true")}const grid=document.getElementById("prestadores-grid");const aviso=document.getElementById("prestador-escolhido");if(grid)grid.innerHTML="";if(aviso)aviso.hidden=true;
const btnProposta=document.getElementById("btn-criar-proposta");const estadoProposta=document.getElementById("proposta-action-status");if(btnProposta){btnProposta.disabled=true;btnProposta.textContent="Criar proposta ao prestador escolhido →"}
if(estadoProposta)estadoProposta.textContent="Selecione um prestador para continuar."}function iniciarNavegacao(){const navToggle=document.getElementById("nav-toggle");const navMenu=document.getElementById("nav-menu");
const servicesToggle=document.querySelector(".nav-dropdown-toggle");const servicesDropdown=document.querySelector(".nav-dropdown");if(!navToggle||!navMenu)return;navToggle.addEventListener("click",()=>{const aberto=navMenu.classList.toggle("open");
navToggle.setAttribute("aria-expanded",String(aberto))});if(servicesToggle&&servicesDropdown){servicesToggle.addEventListener("click",event=>{if(window.innerWidth<=900){event.preventDefault();const aberto=servicesDropdown.classList.toggle("mobile-open");
servicesToggle.setAttribute("aria-expanded",String(aberto))}})}navMenu.querySelectorAll("a").forEach(link=>link.addEventListener("click",()=>{navMenu.classList.remove("open");navToggle.setAttribute("aria-expanded","false");
if(servicesDropdown)servicesDropdown.classList.remove("mobile-open");if(servicesToggle)servicesToggle.setAttribute("aria-expanded","false")}))}window.addEventListener("DOMContentLoaded",()=>{const pedido=new URLSearchParams(location.search);const num=v=>{
const n=parseFloat(String(v||"").replace(",","."));return Number.isFinite(n)&&n>0?n:null};const pesoPedido=num(pedido.get("peso")),volumePedido=num(pedido.get("volume"));if(volumePedido){adicionarVolume("Carga",pesoPedido||"",100,100,
+(volumePedido*100).toFixed(1),1)}else{adicionarVolume(pesoPedido?"Carga":"",pesoPedido||"","","","",pesoPedido?1:"")}["origem","destino"].forEach(id=>{const v=pedido.get(id);const el=document.getElementById(id);if(v&&el)el.value=v.slice(0,120)});
if(pedido.get("origem")||pedido.get("destino"))setTimeout(()=>document.getElementById("origem")?.closest("section,.sim-card,form")?.scrollIntoView({behavior:"smooth",block:"start"}),300);calcular();atualizarCalculoVolumes();
document.querySelectorAll("#origem,#destino,#morada-recolha,#tipo-carga,#tipo-carga-detalhe,#data-prevista,#pretende-recolha,#distancia,#remetente-nome,#remetente-nif,#remetente-telefone,#remetente-email,#remetente-morada,#destinatario-nome,#destinatario-nif,#destinatario-telefone,#destinatario-email,#destinatario-morada,#preco-declarado,#observacoes-carga,#metodo-cobranca").forEach(el=>el.addEventListener("input",
()=>{limparErroSimulacao();invalidarSimulacao();atualizarProgressoSimulacao()}));const tipoRota=document.getElementById("tipo-carga");const tipoDetalhe=document.getElementById("tipo-carga-detalhe");if(tipoRota&&tipoDetalhe){tipoRota.addEventListener("change",
()=>{tipoDetalhe.value=tipoRota.value;invalidarSimulacao()});tipoDetalhe.addEventListener("change",()=>{tipoRota.value=tipoDetalhe.value;invalidarSimulacao()})}document.getElementById("distancia")?.addEventListener("input",invalidarSimulacao);
const seletorRecolha=document.getElementById("pretende-recolha");const moradaRecolha=document.getElementById("morada-recolha");let temporizadorMorada;seletorRecolha?.addEventListener("change",atualizarDistanciaRecolha);moradaRecolha?.addEventListener("input",
()=>{clearTimeout(temporizadorMorada);temporizadorMorada=setTimeout(atualizarDistanciaRecolha,650)});atualizarDistanciaRecolha();atualizarProgressoSimulacao();document.getElementById("criar-simulacao")?.addEventListener("click",criarSimulacao);
iniciarNavegacao()});const PRESTADORES_DEMO=[{id:"prestador-01",nome:"TransLog Atlântico",prazo:"2–3 dias",nota:"4,8"},{id:"prestador-02",nome:"EloTrans Cargo",prazo:"3–4 dias",nota:"4,7"},{id:"prestador-03",nome:"Global Freight",prazo:"4–5 dias",nota:"4,6"}];
function valorEstimadoPrestador(simulacao,index){const base=Math.max(85,(Number(simulacao.volumeTotalM3)||0)*180+(Number(simulacao.pesoTotalKg)||0)*.12+(Number(simulacao.precoDeclarado)||0)*.002);const fatores=[1,1.08,1.16];
return Math.round(base*fatores[index]*100)/100}function obterSimulacaoParaProposta(){if(typeof simulacaoAtual!=="undefined"&&simulacaoAtual)return simulacaoAtual;const dados=typeof obterDadosCarga==="function"?obterDadosCarga():{};
const detalhes=typeof obterDetalhesCarga==="function"?obterDetalhesCarga():{};return{...dados,...detalhes,criadoEm:new Date().toISOString()}}function apresentarPropostasPrestadores(simulacao){const sec=document.getElementById("propostas-prestadores");
const lista=document.getElementById("lista-propostas-prestadores");const count=document.getElementById("propostas-count");if(!sec||!lista)return;const propostas=PRESTADORES_DEMO.map((p,i)=>({...p,total:valorEstimadoPrestador(simulacao,i)})).sort((a,
b)=>a.total-b.total);lista.innerHTML=propostas.map((p,
i)=>`
    <article class="proposta-prestador-card ${i===0?"melhor-preco":""}" data-id="${p.id}">
      <div class="proposta-provider-main">
        <div class="provider-avatar">🚚</div>
        <div>
          <strong>${p.nome}</strong>
          <div class="provider-meta">Entrega estimada: ${p.prazo} · Avaliação ${p.nota}/5</div>
          ${i===0?'<span class="badge-melhor-preco">Melhor preço</span>':""}
        </div>
      </div>
      <div class="proposta-provider-price">
        <small>Preço total</small>
        <strong>${p.total.toLocaleString("pt-PT",
{style:"currency",currency:"EUR"}
)}</strong>
      </div>
      <button type="button" class="btn-selecionar-prestador" onclick="selecionarPrestadorParaProposta('${p.id}')">
        ${i===0?"Selecionar melhor preço":"Selecionar prestador"}
      </button>
    </article>
  `).join("");
count.textContent=`${propostas.length} prestadores`;sec.hidden=false;const acao=document.getElementById("acao-criar-proposta");if(acao)acao.hidden=false;window.propostasPrestadoresAtuais=propostas}window.selecionarPrestadorParaProposta=function(id){
const proposta=(window.propostasPrestadoresAtuais||[]).find(p=>p.id===id);if(!proposta)return;window.prestadorSelecionado=proposta;document.querySelectorAll(".proposta-prestador-card").forEach(card=>{card.classList.toggle("selecionada",card.dataset.id===id)});
const status=document.getElementById("proposta-action-status");const btn=document.getElementById("btn-criar-proposta");if(btn)btn.disabled=false;if(status)status.textContent=`${proposta.nome} selecionado · ${proposta.total.toLocaleString("pt-PT",{
style:"currency",currency:"EUR"})}`;const selected=document.getElementById("proposta-selecionada");if(selected){selected.hidden=false;selected.innerHTML=`<strong>Prestador escolhido:</strong> ${proposta.nome} · <strong>${proposta.total.toLocaleString("pt-PT",{
style:"currency",currency:"EUR"})}</strong>`}};function criarPropostaAoPrestador(){const prestador=window.prestadorSelecionado||prestadorSelecionado;if(!prestador){const status2=document.getElementById("proposta-action-status");
if(status2)status2.textContent="Selecione um prestador antes de criar a proposta.";return}const simulacao=obterSimulacaoParaProposta();const proposta={id:`PROP-${Date.now()}`,simulacaoId:simulacao.numero||simulacao.id||`SIM-${Date.now()}`,
prestadorId:prestador.id,prestador:prestador.nome,valorTotal:Number(prestador.total??prestador.valor??0),estado:"Enviada ao prestador",criadaEm:new Date().toISOString(),dadosSimulacao:simulacao};let propostasGuardadas=[];try{
propostasGuardadas=JSON.parse(localStorage.getItem("elolog_propostas")||"[]")}catch(erro){propostasGuardadas=[]}propostasGuardadas.unshift(proposta);localStorage.setItem("elolog_propostas",JSON.stringify(propostasGuardadas));let simulacoesPrestador=[];try{
simulacoesPrestador=JSON.parse(localStorage.getItem("elolog_client_simulations")||"[]")}catch(erro){simulacoesPrestador=[]}const registoPrestador={registro:proposta.simulacaoId,dataHora:proposta.criadaEm,volume:Number(simulacao.volumeTotalM3||0),
total:proposta.valorTotal.toLocaleString("pt-PT",{style:"currency",currency:"EUR"}),origin:simulacao.origem||"",destination:simulacao.destino||"",cargo:simulacao.tipoCarga||simulacao.cargo||"",
goods:(simulacao.volumes||[]).map(v=>`${v.carga} — ${v.quantidade}`).join("; "),date:simulacao.data||"",client:simulacao.remetente?.nome||"Cliente Elolog",provider:prestador.nome,providerId:prestador.id,proposalId:proposta.id,
sentToProviderAt:proposta.criadaEm,status:"Proposta enviada"};simulacoesPrestador=simulacoesPrestador.filter(item=>item.registro!==registoPrestador.registro);simulacoesPrestador.unshift(registoPrestador);localStorage.setItem("elolog_client_simulations",
JSON.stringify(simulacoesPrestador.slice(0,100)));const status=document.getElementById("proposta-action-status");if(status)status.textContent=`Proposta ${proposta.id} criada e enviada a ${prestador.nome}.`;
const btn=document.getElementById("btn-criar-proposta");if(btn){btn.disabled=true;btn.textContent="✓ Proposta enviada ao prestador"}if(typeof simulacaoAtual!=="undefined"&&simulacaoAtual){simulacaoAtual.propostaId=proposta.id;
simulacaoAtual.propostaPrestador=prestador.nome;simulacaoAtual.estado="Proposta enviada"}}document.addEventListener("DOMContentLoaded",()=>{const btn=document.getElementById("btn-criar-proposta");if(btn)btn.addEventListener("click",criarPropostaAoPrestador)});
document.addEventListener("DOMContentLoaded",()=>{const candidates=["btn-criar-simulacao","btn-realizar-simulacao"];candidates.forEach(id=>{const el=document.getElementById(id);if(el&&!el.dataset.propostasHook){el.dataset.propostasHook="1";
el.addEventListener("click",()=>{setTimeout(()=>{const simulacao=obterSimulacaoParaProposta();apresentarPropostasPrestadores(simulacao)},50)})}})});
