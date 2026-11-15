/* Elolog — manifestos e declarações de carga no servidor (v147).
   Com sessão real de prestador:
   - manifestos: tabela manifestos (campos principais + «detalhes» com contentor, selo, viatura, notas, anexos e registo) e
     manifesto_encomendas (as encomendas de cada manifesto). Todos os funcionários veem os mesmos; as encomendas ficam
     marcadas com o manifesto em todos os aparelhos. Só o administrador da empresa confirma ou anula (regra do servidor);
     um manifesto confirmado não muda: cria-se uma nova versão.
   - declarações de carga (com assinatura do declarante): guardadas com as declarações da encomenda (declaracoes_gravar),
     lidas quando se abre a encomenda. */
(function(){"use strict";
const P=()=>window.elologProducao,ativo=()=>typeof currentUser!=="undefined"&&currentUser?.role==="prestador"&&currentUser?.providerCompany?.server===true&&!!P()?.online?.();
const aviso=(t,k)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,k):console.warn(t);
const erro=e=>String(e?.message||e||"").replace(/^.*?ERROR:\s*/,"");
const ops=()=>typeof operations!=="undefined"?operations:[];
const PARA={"Rascunho":"rascunho","Confirmado":"confirmado","Em trânsito":"em_transito","Concluído":"concluido","Anulado":"cancelado"};
const DE={rascunho:"Rascunho",confirmado:"Confirmado",em_transito:"Em trânsito",concluido:"Concluído",cancelado:"Anulado"};
const NUCLEO=["id","srvId","number","version","status","origin","destination","voyageNumber","departureDate","arrivalDate","carrier","totalUnits","totalWeight","totalVolume","orderIds"];
let manifestos=[],foto=new Map(),empresa=null,pronto=false,decl=[],fotoD=new Map();
const MK="elolog_cargo_manifests",DK="elolog_cargo_declarations";

/* ---------- manifestos ---------- */
const encDe=id=>ops().find(o=>String(o.id)===String(id))?.servidor?.id||null;
function local(m,ligacoes){const ids=ligacoes.filter(l=>l.manifesto_id===m.id).map(l=>ops().find(o=>o.servidor?.id===l.encomenda_id)?.id||l.encomenda?.codigo).filter(Boolean);
  return{...(m.detalhes||{}),id:m.id,srvId:m.id,number:m.numero,version:m.versao||1,status:DE[m.estado]||"Rascunho",origin:m.origem||"",destination:m.destino||"",voyageNumber:m.numero_viagem||"",
    departureDate:m.partida||"",arrivalDate:m.chegada||"",carrier:m.transportador||"",totalUnits:m.total_unidades||0,totalWeight:Number(m.total_peso_kg||0),totalVolume:Number(m.total_volume_m3||0),orderIds:ids,
    confirmedAt:m.confirmado_em||m.detalhes?.confirmedAt||"",updatedAt:m.updated_at,provider:typeof currentProviderCompanyName==="function"?currentProviderCompanyName():""}}
const detalhes=r=>{const d={};Object.keys(r).forEach(k=>{if(!NUCLEO.includes(k)&&k!=="provider")d[k]=r[k]});return d};
const linha=r=>({numero:String(r.number||"").trim(),versao:Number(r.version||1),estado:PARA[r.status]||"rascunho",origem:r.origin||null,destino:r.destination||null,numero_viagem:r.voyageNumber||null,
  partida:r.departureDate||null,chegada:r.arrivalDate||null,transportador:r.carrier||null,total_unidades:Math.round(Number(r.totalUnits||0)),total_peso_kg:Number(r.totalWeight||0),total_volume_m3:Number(r.totalVolume||0),detalhes:detalhes(r)});

async function ler(){if(!ativo())return false;try{const sb=await P().sb();empresa=empresa||(await P().minhaEmpresa())?.empresa_id;if(!empresa)return false;
    const{data:ms,error}=await sb.from("manifestos").select("id,numero,versao,estado,origem,destino,numero_viagem,partida,chegada,transportador,total_unidades,total_peso_kg,total_volume_m3,confirmado_em,detalhes,updated_at").eq("empresa_id",empresa).order("created_at",{ascending:false}).limit(300);
    if(error)throw error;const ids=(ms||[]).map(m=>m.id);let lig=[];
    if(ids.length){const r=await sb.from("manifesto_encomendas").select("manifesto_id,encomenda_id,encomenda:encomendas(codigo)").in("manifesto_id",ids);if(r.error)throw r.error;lig=r.data||[]}
    manifestos=(ms||[]).map(m=>local(m,lig));foto=new Map(manifestos.map(m=>[m.srvId,JSON.stringify(linha(m))+"|"+m.orderIds.join(",")]));
    try{localStorage.setItem(MK,JSON.stringify(manifestos))}catch(_){}
    /* as encomendas ficam marcadas com o manifesto ativo em todos os aparelhos */
    let mudou=false;manifestos.filter(m=>m.status!=="Anulado").forEach(m=>m.orderIds.forEach(id=>{const o=ops().find(x=>String(x.id)===String(id));
      if(o&&o.manifestId!==m.id){Object.assign(o,{manifestId:m.id,manifestNumber:m.number,voyageNumber:m.voyageNumber,containerNumber:m.containerNumber||"",sealNumber:m.sealNumber||"",manifestStatus:m.status});mudou=true}}));
    if(mudou)window.saveAll?.();pronto=true;return true}
  catch(e){aviso("Não foi possível ler os manifestos do servidor: "+erro(e),"warning");return false}}

async function gravarManifestos(lista){const sb=await P().sb();let n=0;
  for(const r of lista){const encs=(r.orderIds||[]).map(encDe);if(encs.some(x=>!x)){aviso(`O manifesto ${r.number} tem encomendas que não estão no servidor.`,"warning");continue}
    const reg=linha(r);let id=r.srvId;
    if(!id){const{data,error}=await sb.from("manifestos").insert({empresa_id:empresa,criado_por:(await P().utilizador())?.id,...reg}).select("id").single();if(error)throw error;id=data.id;r.srvId=r.id=id}
    else{const antes=foto.get(id);if(antes===JSON.stringify(reg)+"|"+(r.orderIds||[]).join(","))continue;
      const{error}=await sb.from("manifestos").update(reg).eq("id",id);if(error)throw error}
    const atuais=new Set(encs),{data:ja}=await sb.from("manifesto_encomendas").select("encomenda_id").eq("manifesto_id",id),tinha=new Set((ja||[]).map(x=>x.encomenda_id));
    const novos=[...atuais].filter(x=>!tinha.has(x)).map(e=>({manifesto_id:id,encomenda_id:e}));if(novos.length){const{error}=await sb.from("manifesto_encomendas").insert(novos);if(error)throw error}
    const sair=[...tinha].filter(x=>!atuais.has(x));if(sair.length&&reg.estado==="rascunho"){const{error}=await sb.from("manifesto_encomendas").delete().eq("manifesto_id",id).in("encomenda_id",sair);if(error)throw error}
    n++}
  return n}

/* ---------- declarações de carga ---------- */
async function lerDeclaracoes(codigo){const sb=await P().sb();const{data,error}=await sb.rpc("declaracoes_ler",{p_codigo:codigo});if(error)throw error;return data}
async function abrirEncomenda(id){const o=ops().find(x=>String(x.id)===String(id));if(!o?.servidor?.codigo)return;
  try{const r=await lerDeclaracoes(o.servidor.codigo),l=(r?.dados?.declaracoes_carga||[]).map(d=>({...d,orderId:o.id}));
    decl=decl.filter(d=>String(d.orderId)!==String(o.id)).concat(l);l.forEach(d=>fotoD.set(d.id,JSON.stringify(d)));try{localStorage.setItem(DK,JSON.stringify(decl))}catch(_){}}
  catch(e){aviso("Não foi possível ler as declarações de carga: "+erro(e),"warning")}}
async function gravarDeclaracoes(lista){const porEnc=new Map();lista.filter(d=>fotoD.get(d.id)!==JSON.stringify(d)).forEach(d=>porEnc.set(String(d.orderId),1));
  const sb=await P().sb();
  for(const id of porEnc.keys()){const o=ops().find(x=>String(x.id)===id);if(!o?.servidor?.codigo){aviso(`A encomenda ${id} não está no servidor: a declaração não foi gravada.`,"warning");continue}
    const atual=await lerDeclaracoes(o.servidor.codigo),dados={...(atual?.dados||{}),declaracoes_carga:lista.filter(d=>String(d.orderId)===id)};
    const{error}=await sb.rpc("declaracoes_gravar",{p_codigo:o.servidor.codigo,p_dados:dados});if(error)throw error;dados.declaracoes_carga.forEach(d=>fotoD.set(d.id,JSON.stringify(d)))}
  return porEnc.size}

function ligar(){const gM=window.getCargoManifests,sM=window.saveCargoManifests,gD=window.getCargoDeclarations,sD=window.saveCargoDeclarations,abr=window.openProviderHistoryOrder;if(typeof gM!=="function"||gM.__srv)return;
  window.getCargoManifests=Object.assign(function(){return ativo()?manifestos:gM.apply(this,arguments)},{__srv:1});
  window.saveCargoManifests=function(lista){if(!ativo())return sM.apply(this,arguments);if(!pronto)return aviso("Os manifestos ainda estão a carregar do servidor. Tente outra vez.","warning");
    manifestos=lista;gravarManifestos(lista).then(n=>{if(n)aviso("Manifesto gravado no servidor: todos os funcionários o veem.","success")})
      .catch(e=>aviso("O servidor não aceitou o manifesto: "+erro(e),"error")).finally(()=>ler().then(()=>{try{window.renderProviderManifestos?.()}catch(_){}}))};
  window.getCargoDeclarations=function(){return ativo()?decl:gD.apply(this,arguments)};
  window.saveCargoDeclarations=function(lista){if(!ativo())return sD.apply(this,arguments);decl=lista;
    gravarDeclaracoes(lista).then(n=>{if(n)aviso("Declaração de carga gravada no servidor.","success")}).catch(e=>aviso("O servidor não aceitou a declaração: "+erro(e),"error"))};
  if(typeof abr==="function")window.openProviderHistoryOrder=function(id){if(!ativo())return abr.apply(this,arguments);const a=arguments,t=this;abrirEncomenda(id).finally(()=>abr.apply(t,a))}}
ligar();window.addEventListener("load",()=>{ligar();setTimeout(()=>ler(),3000)});
const sp=window.showProviderPage;if(typeof sp==="function")window.showProviderPage=function(page){const r=sp.apply(this,arguments);if(ativo()&&/Manifest|Expedicao/i.test(page||""))ler().then(ok=>{if(ok)try{window.renderProviderManifestos?.();window.renderProviderExpeditionManifestSelection?.()}catch(_){}});return r};
setInterval(()=>{if(ativo())ler()},90000);
window.elologManifestosServidor={ler,abrirEncomenda};
})();
