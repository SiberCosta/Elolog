/* Elolog — calendário marítimo ligado ao servidor (v146).
   Com sessão real de prestador, as viagens vivem em viagens_maritimas (todos os funcionários veem as mesmas, e a previsão
   de chegada das encomendas usa-as). O calendário continua a ler a sua lista local, mas essa lista passa a ser só uma cópia
   do servidor, refeita a cada leitura; gravar e eliminar vão ao servidor. */
(function(){"use strict";
const P=()=>window.elologProducao,ativo=()=>typeof currentUser!=="undefined"&&currentUser?.role==="prestador"&&currentUser?.providerCompany?.server===true&&!!P()?.online?.();
const norm=v=>String(v||"").trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"");
const chave=()=>`elolog_maritime_calendar_${norm(typeof currentProviderCompanyName==="function"?currentProviderCompanyName():"Prestador").replace(/[^a-z0-9]+/g,"-")||"prestador"}`;
const aviso=(t,k)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,k):console.warn(t);
const erro=e=>String(e?.message||e||"").replace(/^.*?ERROR:\s*/,"");
const PARA={"Planeada":"planeada","Confirmada":"aberta","Em viagem":"partiu","Atrasada":"atrasada","Concluída":"chegou","Cancelada":"cancelada"};
const DE={planeada:"Planeada",aberta:"Confirmada",lotada:"Confirmada",partiu:"Em viagem",atrasada:"Atrasada",chegou:"Concluída",cancelada:"Cancelada"};
const stp=v=>/s[aã]o tom|stp|principe|príncipe/i.test(norm(v));
let empresa=null;

const local=v=>{const m=/^Encomendas: ([^\n]*)\n?/.exec(v.notas||"");return{id:v.id,srv:true,vessel:v.navio,voyage:v.viagem||"",carrier:v.linha||"",status:DE[v.estado]||"Planeada",origin:v.porto_origem,destination:v.porto_destino,
  departure:v.partida,arrival:v.chegada||"",cutoff:v.fecho_carga||"",capacity:v.grupagem_m3!=null?`${v.grupagem_m3} m³`:"",orderIds:m?m[1].split(",").map(x=>x.trim()).filter(Boolean):[],notes:m?(v.notas||"").slice(m[0].length):(v.notas||""),updatedAt:v.updated_at}};

async function ler(){if(!ativo())return false;try{const sb=await P().sb();empresa=empresa||(await P().minhaEmpresa())?.empresa_id;if(!empresa)return false;
    const{data,error}=await sb.from("viagens_maritimas").select("id,navio,viagem,linha,estado,porto_origem,porto_destino,partida,chegada,fecho_carga,grupagem_m3,notas,updated_at").eq("empresa_id",empresa).order("partida").limit(500);
    if(error)throw error;localStorage.setItem(chave(),JSON.stringify((data||[]).map(local)));return true}
  catch(e){aviso("Não foi possível ler o calendário marítimo do servidor: "+erro(e),"warning");return false}}
const desenhar=()=>{try{window.renderMaritimeCalendar?.()}catch(_){}};

async function gravar(id){const val=x=>document.getElementById(x)?.value.trim()||"";const partida=val("maritimeDeparture"),chegada=val("maritimeArrival"),origem=val("maritimeOrigin"),destino=val("maritimeDestination");
  if(chegada&&chegada<partida)throw new Error("A chegada prevista não pode ser anterior à saída.");
  const enc=val("maritimeOrders"),notas=[enc?`Encomendas: ${enc}`:"",val("maritimeNotes")].filter(Boolean).join("\n").slice(0,300),cap=parseFloat(String(val("maritimeCapacity")).replace(",","."));
  const fecho=val("maritimeCutoff").slice(0,10);
  const reg={navio:val("maritimeVessel"),viagem:val("maritimeVoyageNo").slice(0,30)||null,linha:val("maritimeCarrier").slice(0,80)||null,estado:PARA[val("maritimeVoyageStatus")]||"planeada",
    porto_origem:origem,porto_destino:destino,sentido:stp(origem)&&!stp(destino)?"STP-PT":"PT-STP",partida,chegada:chegada||null,fecho_carga:fecho&&fecho<=partida?fecho:null,
    grupagem_m3:Number.isFinite(cap)&&/m/i.test(val("maritimeCapacity"))?cap:null,notas:notas||null};
  const sb=await P().sb();const{error}=id?await sb.from("viagens_maritimas").update(reg).eq("id",id):await sb.from("viagens_maritimas").insert({empresa_id:empresa,...reg});if(error)throw error}

function ligar(){const sv=window.saveMaritimeVoyage,dl=window.deleteMaritimeVoyage;if(typeof sv!=="function"||sv.__srv)return;
  window.saveMaritimeVoyage=async function(event,id=""){if(!ativo())return sv.apply(this,arguments);event?.preventDefault?.();
    try{if(!empresa)await ler();await gravar(id);await ler();window.closeProviderDrawer?.("platformRecordDrawer");desenhar();aviso("Viagem gravada no servidor: todos os funcionários a veem.","success")}
    catch(e){aviso("O servidor não aceitou a viagem: "+erro(e),"error")}};window.saveMaritimeVoyage.__srv=1;
  window.deleteMaritimeVoyage=async function(id){if(!ativo())return dl.apply(this,arguments);if(!confirm("Eliminar esta viagem do calendário?"))return;
    try{const sb=await P().sb();const{error}=await sb.from("viagens_maritimas").update({estado:"cancelada"}).eq("id",id);if(error)throw error;await ler();window.closeProviderDrawer?.("platformRecordDrawer");desenhar();
      aviso("Viagem marcada como cancelada no servidor.","success")}catch(e){aviso("O servidor não aceitou: "+erro(e),"error")}}}

ligar();window.addEventListener("load",()=>{ligar();setTimeout(()=>ler().then(ok=>{if(ok)desenhar()}),2500)});
const sp=window.showProviderPage;if(typeof sp==="function")window.showProviderPage=function(page){const r=sp.apply(this,arguments);if(page==="providerMaritimeCalendar"&&ativo())ler().then(ok=>{if(ok)desenhar()});return r};
setInterval(()=>{if(ativo())ler()},120000);
window.elologCalendarioServidor={ler};
})();
