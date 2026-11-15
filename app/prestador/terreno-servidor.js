/* Elolog — equipa de terreno do escritório ligada ao servidor (v146).
   Com sessão real de prestador, os serviços de recolha e entrega e as viaturas deixam de ficar só neste navegador:
   - serviços: trabalhos_terreno (o mesmo que o operador vê no telemóvel em «Serviços ao vivo»);
   - viaturas: veiculos; operadores: funcionarios (já vinham do servidor).
   getFieldJobs/getFieldVehicles devolvem o que veio do servidor; saveFieldJobs/saveFieldVehicles gravam as diferenças.
   Fotografias, assinaturas e conferência registam-se no telemóvel do operador (comprovativos no servidor). */
(function(){"use strict";
const P=()=>window.elologProducao,ativo=()=>typeof currentUser!=="undefined"&&currentUser?.role==="prestador"&&currentUser?.providerCompany?.server===true&&!!P()?.online?.();
const aviso=(t,k)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,k):console.warn(t);
const erro=e=>String(e?.message||e||"").replace(/^.*?ERROR:\s*/,"");
const PARA_SRV={"Por atribuir":"planeada","Agendada":"planeada","Em serviço":"em_curso","No local":"em_curso","Ocorrência aberta":"em_curso","Concluída":"concluida","Concluída com ocorrência":"concluida","Cliente ausente":"cliente_ausente","Cancelada":"cancelada"};
const DO_SRV=(e,op)=>({planeada:op?"Agendada":"Por atribuir",em_curso:"Em serviço",concluida:"Concluída",cliente_ausente:"Cliente ausente",cancelada:"Cancelada"}[e]||"Agendada");
const aEnviar=new Set();let jobs=[],foto=new Map(),veiculos=[],fotoV=new Map(),empresa=null,pronto=false,aLer=null;

/* hora guardada no início das notas («às 10:30. …»): o servidor guarda só o dia */
const partir=n=>{const m=/^às (\d{2}:\d{2})\.\s?/.exec(n||"");return m?{hora:m[1],texto:(n||"").slice(m[0].length)}:{hora:"",texto:n||""}};
const juntar=(hora,texto)=>[hora?`às ${hora}.`:"",texto||""].filter(Boolean).join(" ")||null;
const opDe=id=>(typeof operations!=="undefined"?operations:[]).find(o=>o.servidor?.id===id)||null;
const chave=j=>JSON.stringify([j.operatorId||"",j.scheduledAt||"",j.instructions||"",PARA_SRV[j.status]||"planeada",j.vehicle||""]);

function local(t){const n=partir(t.notas),o=opDe(t.encomenda_id),v=veiculos.find(x=>x.id===t.veiculo_id);
  return{id:t.id,srvId:t.id,code:`${t.tipo==="entrega"?"ENT":"REC"}-${String(t.id).slice(0,5).toUpperCase()}`,operationId:o?.id||t.encomenda?.codigo||"",type:t.tipo==="entrega"?"Entrega":"Recolha",
    scheduledAt:t.data?`${t.data}T${n.hora||"09:00"}`:"",operatorId:t.operador_id||"",vehicle:v?.plate||"",instructions:n.texto,status:DO_SRV(t.estado,t.operador_id),incidents:[],history:[],createdAt:t.created_at}}
const vLocal=v=>({id:v.id,srvId:v.id,plate:v.matricula,type:v.descricao||"Viatura",status:v.ativo?"Disponível":"Inativa"});

async function ler(){if(!ativo())return false;if(aLer)return aLer;aLer=(async()=>{try{const sb=await P().sb();empresa=empresa||(await P().minhaEmpresa())?.empresa_id;if(!empresa)return false;
    const desde=new Date(Date.now()-60*864e5).toISOString().slice(0,10);
    const[v,t]=await Promise.all([sb.from("veiculos").select("id,matricula,descricao,ativo").eq("empresa_id",empresa).order("matricula"),
      sb.from("trabalhos_terreno").select("id,encomenda_id,tipo,operador_id,veiculo_id,data,estado,notas,created_at,encomenda:encomendas(codigo)").eq("empresa_id",empresa).in("tipo",["recolha","entrega"]).gte("data",desde).order("data",{ascending:false}).limit(300)]);
    if(v.error)throw v.error;if(t.error)throw t.error;
    veiculos=(v.data||[]).map(vLocal);fotoV=new Map(veiculos.map(x=>[x.id,JSON.stringify(x)]));
    jobs=(t.data||[]).map(local);foto=new Map(jobs.map(j=>[j.id,chave(j)]));pronto=true;return true}
  catch(e){aviso("Não foi possível ler a equipa de terreno do servidor: "+erro(e),"warning");return false}finally{setTimeout(()=>{aLer=null},200)}})();return aLer}
const redesenhar=()=>{["renderProviderFieldTeam","renderProviderDashboardForCompany"].forEach(f=>{try{window[f]?.()}catch(_){}})};

async function gravarServicos(lista){const sb=await P().sb();let n=0;
  for(const j of lista){const o=(typeof operations!=="undefined"?operations:[]).find(x=>String(x.id)===String(j.operationId));
    const enc=o?.servidor?.id;if(!enc){aviso(`A encomenda ${j.operationId||""} ainda não está no servidor: o serviço não foi gravado.`,"warning");continue}
    const[dia,hora]=String(j.scheduledAt||"").split("T"),v=veiculos.find(x=>x.plate===j.vehicle);
    const reg={operador_id:j.operatorId||null,data:dia||null,notas:juntar((hora||"").slice(0,5),j.instructions),estado:PARA_SRV[j.status]||"planeada",veiculo_id:v?.srvId||null};
    if(!j.srvId&&jobs.some(x=>x.srvId&&x.operationId===j.operationId&&x.type===j.type&&!/Conclu|Cancel/.test(x.status))){aviso(`A encomenda ${j.operationId} já tem um serviço de ${j.type.toLowerCase()} ativo: edite esse.`,"warning");continue}
    if(!j.srvId){if(aEnviar.has(j.id))continue;aEnviar.add(j.id);try{const{error}=await sb.from("trabalhos_terreno").insert({empresa_id:empresa,encomenda_id:enc,tipo:j.type==="Entrega"?"entrega":"recolha",...reg});if(error)throw error;n++}
      catch(e){aEnviar.delete(j.id);throw e}}
    else if(foto.get(j.srvId)!==chave(j)){const{error}=await sb.from("trabalhos_terreno").update(reg).eq("id",j.srvId);if(error)throw error;n++}}
  return n}

async function gravarViaturas(lista){const sb=await P().sb();
  for(const v of lista){const reg={matricula:String(v.plate||"").trim().toUpperCase(),descricao:v.type||null,ativo:!/inativ|fora|abatid/i.test(v.status||"")};if(!reg.matricula)continue;
    if(!v.srvId){const{error}=await sb.from("veiculos").insert({empresa_id:empresa,...reg});if(error)throw error}
    else if(fotoV.get(v.srvId)!==JSON.stringify(v)){const{error}=await sb.from("veiculos").update(reg).eq("id",v.srvId);if(error)throw error}}}

function ligar(){const gJ=window.getFieldJobs,sJ=window.saveFieldJobs,gV=window.getFieldVehicles,sV=window.saveFieldVehicles,acao=window.fieldJobAction;if(typeof gJ!=="function"||gJ.__srv)return;
  window.getFieldJobs=Object.assign(function(){return ativo()?jobs:gJ.apply(this,arguments)},{__srv:1});
  window.saveFieldJobs=function(lista){if(!ativo())return sJ.apply(this,arguments);const pend=(lista||[]).filter(j=>!j.srvId&&!aEnviar.has(j.id)||j.srvId&&foto.get(j.srvId)!==chave(j));if(!pend.length)return;if(!pronto){aviso("A equipa de terreno ainda está a carregar do servidor. Tente outra vez dentro de segundos.","warning");return}
    gravarServicos(pend).then(n=>{if(n)aviso(n===1?"Serviço de terreno gravado no servidor: o operador já o vê no telemóvel.":`${n} serviços de terreno gravados no servidor.`,"success")})
      .catch(e=>aviso("O servidor não aceitou o serviço de terreno: "+erro(e),"error")).finally(()=>ler().then(redesenhar))};
  window.getFieldVehicles=function(){return ativo()?veiculos:gV.apply(this,arguments)};
  window.saveFieldVehicles=function(lista){if(!ativo())return sV.apply(this,arguments);if(!(lista||[]).some(v=>!v.srvId||fotoV.get(v.srvId)!==JSON.stringify(v)))return;if(!pronto)return aviso("As viaturas ainda estão a carregar. Tente outra vez.","warning");
    gravarViaturas(lista).then(()=>aviso("Viaturas gravadas no servidor.","success")).catch(e=>aviso("O servidor não aceitou a viatura: "+erro(e),"error")).finally(()=>ler().then(redesenhar))};
  if(typeof acao==="function")window.fieldJobAction=function(id,a){if(ativo()&&["photo","signature","check","incident"].includes(a))
      return aviso(a==="incident"?"Registe a ocorrência na ficha da encomenda (Ocorrências): fica no servidor e todos a veem.":"Fotografias, assinatura e conferência registam-se no telemóvel do operador, em «Serviços ao vivo»: ficam no servidor com o comprovativo.","info");
    return acao.apply(this,arguments)}}

ligar();if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);
window.addEventListener("load",()=>{ligar();setTimeout(()=>ler().then(ok=>{if(ok)redesenhar()}),2500)});
setInterval(()=>{if(ativo())ler().then(ok=>{if(ok&&document.getElementById("providerFieldTeam")?.classList.contains("active"))redesenhar()})},60000);
const sp=window.showProviderFieldPage;if(typeof sp==="function")window.showProviderFieldPage=function(){const r=sp.apply(this,arguments);if(ativo())ler().then(ok=>{if(ok)redesenhar()});return r};
window.elologTerrenoServidor={ler,servicos:()=>jobs,viaturas:()=>veiculos};
})();
