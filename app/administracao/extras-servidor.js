/* Elolog — última fase dos testes reais, administração (v148).
   As páginas antigas da administração continuam a validar os formulários como antes, mas, com sessão real, o que gravavam
   no navegador vai para o servidor e a lista que mostram passa a vir do servidor:
   - planos (planos), regras de conformidade (regras_conformidade),
   - faturas e notas de crédito da plataforma (faturas_plataforma; o PDF licenciado continua a ser emitido no programa
     de faturação certificado e não fica guardado aqui).
   Os campos que o servidor não tem (ex.: cupões de plano, alertas da regra) não se guardam; o essencial sim. */
(function(){"use strict";
const P=()=>window.elologProducao;
const real=()=>{try{return currentUser?.role==="admin"&&!!window.elologSoServidor?.real?.()&&!!P()?.online?.()}catch(_){return false}};
const aviso=(t,k)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,k):console.warn(t);
const erro=e=>String(e?.message||e||"").replace(/^.*?ERROR:\s*/,"");
const K={planos:"elolog_admin_plans",conf:"elolog_admin_compliance_rules",fat:"elolog_admin_billing",nc:"elolog_admin_credit_notes"};
const gravarOriginal=Storage.prototype.setItem;let faturas=[],aEscrever=false;
const num=v=>{const n=parseFloat(String(v??"").replace(/\./g,"").replace(",","."));return Number.isFinite(n)?n:null};
const escrever=(k,v)=>{aEscrever=true;try{gravarOriginal.call(localStorage,k,JSON.stringify(v))}finally{aEscrever=false}};

/* ---------- servidor → cópia local que as páginas leem ---------- */
async function ler(){if(!real())return;try{const sb=await P().sb();
    const[pl,cf,fp]=await Promise.all([sb.from("planos").select("*").order("preco_mensal"),sb.from("regras_conformidade").select("*").order("created_at",{ascending:false}),
      sb.from("faturas_plataforma").select("id,empresa_id,tipo,numero_fiscal,fatura_origem_id,valor,estado,emitida_em").order("emitida_em",{ascending:false}).limit(300)]);
    if(pl.data)escrever(K.planos,pl.data.map(p=>({srvId:p.id,name:p.nome,status:p.ativo?"Ativo":"Inativo",monthlyPrice:Number(p.preco_mensal||0),price:p.personalizado||!Number(p.preco_mensal)?"Personalizado":`${Number(p.preco_mensal).toLocaleString("pt-PT")} €/mês`,
      trial:p.trial_dias||0,employees:p.max_funcionarios||"Ilimitados",operations:p.max_operacoes?Number(p.max_operacoes).toLocaleString("pt-PT"):"Personalizadas",storage:p.armazenamento_gb?`${p.armazenamento_gb} GB`:"Personalizado",support:p.suporte||""})));
    if(cf.data)escrever(K.conf,cf.data.map(r=>({id:r.id,srvId:r.id,name:r.nome,documentType:r.nome,status:r.ativa?"Ativa":"Inativa",required:r.obrigatorio?"yes":"no",scope:r.escopo,target:r.empresa_id||"",
      hasExpiry:!!r.exige_validade,validityMonths:r.validade_dias?Math.round(r.validade_dias/30):0,updatedAt:r.updated_at})));
    if(fp.data){faturas=fp.data;escrever(K.nc,fp.data.filter(f=>f.tipo==="nota_credito").map(f=>({id:f.id,srvId:f.id,number:f.numero_fiscal,providerId:f.empresa_id,total:Number(f.valor),status:f.estado,issueDate:String(f.emitida_em||"").slice(0,10)})))}}
  catch(e){console.warn("Administração (servidor):",erro(e))}}

/* ---------- cópia local → servidor ---------- */
async function planos(lista){const sb=await P().sb();for(const p of lista){const reg={nome:p.name,preco_mensal:Number(p.monthlyPrice??num(p.price)??0),trial_dias:Number(p.trial||0),
    max_funcionarios:num(p.employees),max_operacoes:num(p.operations),armazenamento_gb:num(p.storage),suporte:p.support||null,ativo:!/inativ|suspens/i.test(p.status||""),personalizado:!Number(p.monthlyPrice??num(p.price))};
  const{error}=p.srvId?await sb.from("planos").update(reg).eq("id",p.srvId):await sb.from("planos").upsert(reg,{onConflict:"nome"});if(error)throw error}}
async function conformidade(lista){const sb=await P().sb();for(const r of lista){const reg={nome:r.name||r.documentType,escopo:r.scope||"global",empresa_id:r.scope==="provider"&&/^[0-9a-f-]{36}$/.test(r.target||"")?r.target:null,
    obrigatorio:r.required!=="no",exige_validade:!!r.hasExpiry,validade_dias:r.hasExpiry?Number(r.validityMonths||0)*30:null,ativa:!/inativ/i.test(r.status||"")};
  const{error}=r.srvId?await sb.from("regras_conformidade").update(reg).eq("id",r.srvId):await sb.from("regras_conformidade").insert(reg);if(error)throw error}}
async function faturar(lista){const sb=await P().sb(),u=await P().utilizador();for(const f of lista.filter(x=>x.invoice&&!/^REC-/.test(x.invoice)&&!faturas.some(y=>y.numero_fiscal===x.invoice))){
    const{error}=await sb.from("faturas_plataforma").insert({empresa_id:f.providerId,tipo:"fatura",numero_fiscal:f.invoice,valor:Number(f.amount||0),estado:/pago/i.test(f.status||"")?"paga":"emitida",
      emitida_em:f.issueDate?new Date(f.issueDate+"T12:00").toISOString():new Date().toISOString(),criado_por:u?.id});if(error)throw error}}
async function notas(lista){const sb=await P().sb(),u=await P().utilizador();for(const n of lista.filter(x=>!x.srvId)){
    const orig=faturas.find(f=>f.numero_fiscal===n.invoice||("REC-"+String(f.id).slice(0,8).toUpperCase())===n.invoice);
    const{error}=await sb.from("faturas_plataforma").insert({empresa_id:n.providerId||orig?.empresa_id,tipo:"nota_credito",numero_fiscal:n.number,fatura_origem_id:orig?.id||null,valor:Number(n.total||0),estado:"emitida",
      emitida_em:n.issueDate?new Date(n.issueDate+"T12:00").toISOString():new Date().toISOString(),criado_por:u?.id});if(error)throw error}}
const PARA={[K.planos]:planos,[K.conf]:conformidade,[K.fat]:faturar,[K.nc]:notas};

Storage.prototype.setItem=function(k,v){if(this===window.localStorage&&!aEscrever&&PARA[k]&&real()){let l=null;try{l=JSON.parse(v)}catch(_){}
    if(Array.isArray(l))PARA[k](l).then(()=>{aviso("Gravado no servidor.","success");return ler()}).then(()=>{try{window.renderAdminPlatformPages?.()}catch(_){}})
      .catch(e=>{aviso("O servidor não aceitou: "+erro(e),"error");ler()})}
  return gravarOriginal.apply(this,arguments)};

const sp=window.showAdminPage;if(typeof sp==="function"&&!sp.__extras){window.showAdminPage=function(){const r=sp.apply(this,arguments);if(real())ler().then(()=>{try{window.renderAdminPlatformPages?.()}catch(_){}});return r};window.showAdminPage.__extras=1}
window.addEventListener("load",()=>setTimeout(()=>{if(real())ler()},2500));
window.elologAdminExtras={ler};
})();
