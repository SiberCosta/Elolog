/* Elolog — ELO: simulação feita na conversa (v167).
   O ELO pergunta só o essencial — origem, destino, tipo de carga, peso e tamanho — tirando da primeira frase tudo o que já
   lá estiver («de Lisboa para São Tomé, 200 kg»). Depois:
   · cliente com sessão → pede os preços ao servidor (precos_simulacao, as tarifas reais dos prestadores aprovados) e mostra-os
     no chat; «Escolher e enviar pedido» abre a simulação já preenchida para escolher o prestador;
   · visitante → os preços só existem depois de entrar (regra do servidor): «Ver preços» leva à área de cliente com tudo preenchido.
   Os valores são sempre os da plataforma; a recolha conta a partir do armazém mais próximo de cada prestador (sem armazém, fica por juntar). Nada fica gravado. */
(function(){"use strict";
const K="elo_simulacao",CHAVE_SITE="simulacao_site_eloLog";
const norm=v=>String(v||"").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"").replace(/\s+/g," ").trim();
const ler=()=>{try{return JSON.parse(sessionStorage.getItem(K)||"null")}catch(_){return null}},gravar=d=>{try{d?sessionStorage.setItem(K,JSON.stringify(d)):sessionStorage.removeItem(K)}catch(_){}};
const num=v=>Number(String(v).replace(",","."));
const CARGAS=[[/mudanc|moveis|mobilia|recheio/,"Mudança"],[/veiculo|carro|mota|moto|viatura/,"Veículo"],[/aliment|comida|mercearia/,"Alimentar"],[/construc|cimento|azulejo/,"Materiais de construção"],
  [/maquina|equipamento|gerador/,"Máquinas e equipamentos"],[/refriger|congelad/,"Refrigerada"],[/comercial|mercadoria|stock|loja|roupa|calcado/,"Comercial"],[/document|papeis/,"Outro"]];
const limpo=v=>String(v||"").trim().replace(/[,;:.!?]+$/,"").replace(/\s+(com|de)$/i,"");
/** Tira da frase tudo o que der: rota, carga, peso, volume, medidas e número de volumes. */
function extrair(t,d){const n=norm(t);
  const r=t.match(/(?:\bde|\bdesde)\s+([^,;\d]+?)\s+(?:para|at[eé]|a)\s+([^,;\d]+?)(?=\s+(?:com|carga|de\s+\d|\d)|[,;.!?]|$)/i);
  if(r){d.origem=d.origem||limpo(r[1]);d.destino=d.destino||limpo(r[2])}
  else{const p=t.match(/\bpara\s+([^,;\d]+?)(?=\s+(?:com|carga|\d)|[,;.!?]|$)/i);if(p&&!d.destino&&d.origem!==undefined)d.destino=limpo(p[1])}
  const kg=n.match(/(\d+(?:[.,]\d+)?)\s*(kg|quilos?|kilos?)\b/),ton=n.match(/(\d+(?:[.,]\d+)?)\s*(t|ton|toneladas?)\b/);if(kg)d.peso=num(kg[1]);else if(ton)d.peso=num(ton[1])*1000;
  const m3=n.match(/(\d+(?:[.,]\d+)?)\s*(m3|m³|metros? cubicos?)/);if(m3)d.volume=num(m3[1]);
  const dim=n.match(/(\d+(?:[.,]\d+)?)\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*(cm|m)?/);
  if(dim){const f=dim[4]==="m"?100:1;d.dims=[num(dim[1])*f,num(dim[2])*f,num(dim[3])*f]}
  const q=n.match(/(\d+)\s*(caixas?|volumes?|paletes?|malas?|bidoes?|sacos?|embalagens?)/);if(q)d.qtd=+q[1];
  const c=CARGAS.find(([re])=>re.test(n));if(c&&!d.carga)d.carga=c[1];return d}
const volume=d=>d.volume||(d.dims?(d.qtd||1)*d.dims[0]*d.dims[1]*d.dims[2]/1e6:0);
const eur=v=>Number(v||0).toLocaleString("pt-PT",{style:"currency",currency:"EUR"});
const resumo=d=>[`${d.origem} → ${d.destino}`,d.carga,d.recolha?"com recolha":"",d.peso?`${d.peso} kg`:"",volume(d)?`${(Math.round(volume(d)*100)/100).toLocaleString("pt-PT")} m³`:"",d.qtd>1?`${d.qtd} volumes`:""].filter(Boolean).join(" · ");
/** Pergunta só o que falta, pela ordem que importa para o preço. */
function proxima(d){
  if(!d.origem)return{campo:"origem",texto:"Vamos simular. De onde sai a carga? (cidade e país)",chips:["Lisboa","Porto"]};
  if(!d.destino)return{campo:"destino",texto:`Saída de ${d.origem}. Para onde vai?`,chips:["São Tomé","Luanda"]};
  if(!d.carga)return{campo:"carga",texto:"Que tipo de carga é?",chips:["Comercial","Mudança","Veículo","Outra"]};
  if(!d.peso)return{campo:"peso",texto:"Quanto pesa, mais ou menos? Ex.: 200 kg. Se souber, junte as medidas (ex.: 3 caixas 60x40x40).",chips:[]};
  if(!volume(d)&&!d.semVolume)return{campo:"volume",texto:"E o tamanho? Ex.: 1 m³ ou 3 caixas 60x40x40. Se não souber, escreva «não sei».",chips:["Não sei"]};
  if(d.recolha===undefined)return{campo:"recolha",texto:"Vamos buscar a carga a uma morada? Se sim, escreva a morada (rua, código postal e cidade). Se a leva ao armazém, escreva «não».",chips:["Não, levo ao armazém"]};
  return null}
function paraSite(d){const v=volume(d),lado=v?Math.round(Math.cbrt(v/(d.qtd||1))*100):0,dm=d.dims||[lado,lado,lado];
  return{em:Date.now(),origem:d.origem,destino:d.destino,recolha:d.recolha?"sim":"nao",moradaRecolha:d.recolha?d.morada:"",carga:d.carga==="Outra"?"":d.carga,observacoes:"Simulação feita com o assistente ELO.",
    volumes:[{descricao:d.carga||"Carga",qtd:d.qtd||1,peso:d.peso?Math.round(d.peso/(d.qtd||1)*100)/100:0,comp:dm[0],larg:dm[1],alt:dm[2]}],destinatario:{}}}
/** Recolha: cada prestador a partir do SEU armazém mais próximo (um só armazém → esse); sem armazém, fica por juntar ao preço. */
async function prepararRecolha(d){if(!d.recolha||!d.morada)return{ok:false};
  try{const a=typeof window.obterCoordenadas==="function"?await window.obterCoordenadas(d.morada):null;if(!a)return{ok:false,erro:true};
    const r=window.elologDistancia?await window.elologDistancia.recolha(a):null;return{ok:true,lat:a.lat,lon:a.lon,kms:r?.kms||{},porEmpresa:r?.porEmpresa||{}}}catch(_){return{ok:false,erro:true}}}
const linhaRecolha=(x,rc)=>{if(!rc.ok)return"";const km=Number(x.recolha_km)||0,a=rc.porEmpresa[x.prestador_id];
  return km>0?` (com recolha: ${km.toLocaleString("pt-PT")} km${a?` desde o armazém ${a.armazem}`:""})`:" + recolha por juntar (sem armazém registado)"};
async function precos(d,papel){const diz=t=>window.eloRegras?.dizer?.(t),S=window.ELOLogServidor;
  const rc=await prepararRecolha(d),antes=window.elologRecolha;
  try{if(rc.ok)window.elologRecolha={lat:rc.lat,lon:rc.lon,kms:rc.kms};
    const l=await S.calcularPropostas({origem:d.origem,destino:d.destino,tipoCarga:d.carga==="Outra"?null:d.carga,quantidade:d.qtd||1,pesoKg:d.peso||0,volumeM3:volume(d),recolha:rc.ok,km:0});
    window.elologRecolha=antes;
    const ok=l.filter(x=>x.disponivel&&Number(x.preco_final)>0).sort((a,b)=>a.preco_final-b.preco_final),sem=l.length-ok.length;
    if(!ok.length)return diz(`${resumo(d)}\n\nAinda nenhum prestador tem tarifa para esta rota e carga.${sem?` Há ${sem} que pode${sem>1?"m":""} responder com uma cotação:`:""} toque em «Escolher e enviar pedido» para lhes pedir preço.`);
    diz([resumo(d),"",rc.ok?"Preços dos prestadores aprovados:":`Preços dos prestadores aprovados (sem recolha${rc.erro?": não encontrei a morada indicada":""}):`,...ok.slice(0,4).map(x=>`• ${x.prestador_nome} — ${eur(x.preco_final)}${linhaRecolha(x,rc)}`),
      ok.length>4?`e mais ${ok.length-4}.`:"",sem?`${sem} sem tarifa para esta rota (pode pedir-lhes cotação).`:"","","Para avançar, toque em «Escolher e enviar pedido»: abro a simulação já preenchida."].filter((x,i,a)=>x||a[i-1]).join("\n"))}
  catch(_){window.elologRecolha=antes;diz("Não consegui calcular os preços agora. Toque em «Escolher e enviar pedido» e faça a simulação completa, ou tente daqui a pouco.")}}
/** Chamado pelo ELO a cada mensagem. Devolve null quando a mensagem não é sobre simular. */
function responder(texto,papel){let d=ler();const n=norm(texto);
  if(d&&/^(cancelar|parar|menu|sair)$/.test(n)){gravar(null);return null}
  if(d&&/^(escolher e enviar pedido|ver precos)$/.test(n)){const s=paraSite(d);gravar(null);try{localStorage.setItem(CHAVE_SITE,JSON.stringify(s))}catch(_){}
    if(papel==="cliente"&&window.elologSimulacaoSite?.aplicar)return{texto:"Abri a simulação com estes dados. Escolha o prestador e envie o pedido.",go:()=>window.elologSimulacaoSite.aplicar()};
    return{texto:"Vou abrir a sua área de cliente com estes dados já preenchidos. Entre ou crie conta grátis e vê logo os preços reais.",go:()=>{location.href=(location.pathname.includes("/app/")?"":"../app/")+"area-cliente.html?simulacao=site"}}}
  if(/^nova simulac/.test(n)&&["cliente","visitante"].includes(papel)){d={};gravar(d);return proxima(d)}
  if(d&&(/\b(pessoa|humano|atendente|terminar|resumo|privacidade)\b/.test(n)||/\belo[_ -]?[a-z]{2,8}[ -]?\d{6}\b/.test(n)))return null;
  if(!d){if(!["cliente","visitante"].includes(papel))return null;
    if(/document|prazo|demora|alfandeg|quanto tempo|rastre|estado|codigo|barco|navio|saida|partida/.test(n))return null;
    const quer=/\b(simul\w*|orcament\w*|cotac\w*|quanto custa|preco|precos|enviar|mandar|expedir)\b/.test(n)||/\bde\s+\S.+\s+para\s+\S/.test(n);if(!quer)return null;d={}}
  const antes=proxima(d);extrair(texto,d);
  /* resposta simples à pergunta feita («São Tomé», «200», «Comercial», «não sei») */
  if(antes&&!d[antes.campo]){const so=limpo(texto),nr=n.match(/^(\d+(?:[.,]\d+)?)$/);
    if(antes.campo==="origem"&&so)d.origem=so;else if(antes.campo==="destino"&&so)d.destino=so.replace(/^para\s+/i,"");
    else if(antes.campo==="carga")d.carga=/^outr[ao]$/.test(n)?"Outra":so||"Outra";else if(antes.campo==="peso"&&nr)d.peso=num(nr[1]);
    else if(antes.campo==="volume"){if(nr)d.volume=num(nr[1]);else if(/nao sei|sei la|nao faco ideia/.test(n))d.semVolume=true}
    else if(antes.campo==="recolha"){if(/^(nao|n|sem recolha|levo)\b/.test(n))d.recolha=false;else if(so.length>=6){d.recolha=true;d.morada=so}}}
  const falta=proxima(d);gravar(d);if(falta)return falta;
  if(papel==="cliente"&&window.ELOLogServidor?.ativo?.()&&window.eloRegras?.servidor?.()){setTimeout(()=>precos(d,papel),200);
    return{texto:"A calcular os preços com as tarifas reais dos prestadores…",chips:["Escolher e enviar pedido","Nova simulação","Falar com uma pessoa"]}}
  if(papel==="cliente")return{texto:`${resumo(d)}\n\nNa demonstração não há tarifas reais. Toque em «Escolher e enviar pedido» e abro a simulação preenchida.`,chips:["Escolher e enviar pedido","Nova simulação"]};
  return{texto:`${resumo(d)}\n\nOs preços reais das transportadoras aparecem depois de entrar (é grátis e os dados passam preenchidos). Toque em «Ver preços».`,chips:["Ver preços","Nova simulação","Falar com uma pessoa"]}}
window.eloSimular={responder,extrair,limpar:()=>gravar(null)};
})();
