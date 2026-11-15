/* Elolog — acessos da equipa vindos do servidor (v141).
   O «Histórico completo de login da empresa» e a coluna «Último acesso» dos funcionários liam só este navegador, por isso
   ficavam vazios noutro aparelho. Com servidor, o administrador da empresa vê as entradas registadas na auditoria
   (abrir sessão, entrar na área da empresa, códigos de reserva certos e errados) de todos os funcionários.
   A exportação usa a mesma lista. Sem servidor fica tudo como estava. */
(function(){"use strict";
const P=()=>window.elologProducao,$=id=>document.getElementById(id);
const esc=v=>typeof escapeHtml==="function"?escapeHtml(v):String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const ACOES={abrir_sessao_funcionario:["Sucesso","Início de sessão"],abrir_sessao_empresa:["Sucesso","Entrada na área da empresa"],
  codigo_reserva_usado:["Sucesso","Entrada com código de reserva"],codigo_reserva_errado:["Falhou","Código de reserva errado"],codigo_email_usado:["Sucesso","Código por email confirmado"]};
const PAPEL={admin_empresa:"Admin",operador:"Operador",operador_terreno:"Operador de recolha/entrega",armazem:"Armazém",financeiro:"Financeiro"};
const quando=v=>{const d=new Date(v);return isNaN(d)?"—":d.toLocaleString("pt-PT",{day:"2-digit",month:"2-digit",year:"numeric",hour:"2-digit",minute:"2-digit"})};
const relativo=v=>{const d=new Date(v),m=Math.round((Date.now()-d)/60000);if(isNaN(d))return"";if(m<1)return"agora mesmo";if(m<60)return`há ${m} min`;
  const h=Math.round(m/60);if(h<24)return`há ${h} h`;const dias=Math.round(h/24);return dias===1?"ontem":`há ${dias} dias`};
let cache=null,aLer=null;

async function ler(){if(!P()?.online?.())return null;if(aLer)return aLer;
  aLer=(async()=>{try{const emp=await P().minhaEmpresa?.().catch(()=>null);if(!emp?.empresa_id||emp.papel!=="admin_empresa")return null;const sb=await P().sb();
    const[a,f]=await Promise.all([sb.from("auditoria").select("acao,papel,user_id,entidade_id,motivo,created_at").eq("empresa_id",emp.empresa_id).in("acao",Object.keys(ACOES))
      .order("created_at",{ascending:false}).limit(300),sb.from("funcionarios").select("id,nome,email,papel").eq("empresa_id",emp.empresa_id)]);
    if(a.error)throw a.error;const pessoas=new Map((f.data||[]).map(x=>[x.id,x]));const empresa=emp.empresa_nome||emp.nome||(typeof currentProviderCompanyName==="function"?currentProviderCompanyName():"");
    const linhas=(a.data||[]).map(r=>{const p=pessoas.get(r.user_id)||pessoas.get(r.entidade_id)||{};const[res,o_que]=ACOES[r.acao];
      return{dateTime:r.created_at,name:p.nome||"Conta da empresa",email:p.email||"",role:PAPEL[r.papel||p.papel]||PAPEL[p.papel]||"—",company:empresa,result:res,reason:r.motivo||o_que,
        userId:r.user_id||r.entidade_id}});
    const ultimo=new Map();linhas.forEach(l=>{if(l.result==="Sucesso"&&l.email&&!ultimo.has(l.email.toLowerCase()))ultimo.set(l.email.toLowerCase(),l.dateTime)});
    cache={linhas,ultimo,em:Date.now()};return cache}
    catch(e){console.warn("Acessos da equipa:",String(e?.message||e));return null}finally{setTimeout(()=>{aLer=null},500)}})();return aLer}

function desenharHistorico(){const box=$("providerLoginHistoryList");if(!box||!cache)return;const l=cache.linhas;
  box.innerHTML=l.length?l.map(x=>`<div class="provider-login-row"><div>${esc(quando(x.dateTime))}<small>${esc(relativo(x.dateTime))}</small></div><div><strong>${esc(x.name)}</strong><small>${esc(x.email)}</small></div><div>${esc(x.role)}</div><div>${esc(x.company)}</div><div><span class="login-result ${x.result==="Sucesso"?"success":"failed"}">${esc(x.result)}</span><small>${esc(x.reason)}</small></div></div>`).join("")
    :'<div class="employee-empty">Ainda sem entradas registadas no servidor para esta empresa.</div>'}

function desenharUltimos(){if(!cache)return;document.querySelectorAll("#providerEmployeeList .provider-employee-row").forEach(row=>{
  const email=row.querySelector(".employee-email")?.textContent.trim().toLowerCase(),cel=row.querySelector(".employee-last");if(!cel||!email)return;
  const v=cache.ultimo.get(email);cel.innerHTML=v?`<strong>${esc(relativo(v))}</strong><small>${esc(quando(v))}</small>`:'<span class="employee-last-nunca">Ainda não entrou</span>'})}

async function atualizar(){const c=cache&&Date.now()-cache.em<30000?cache:await ler();if(!c)return;desenharHistorico();desenharUltimos()}

function envolver(nome,depois){const f=window[nome];if(typeof f!=="function"||f.__acessos)return;
  const n=function(){const r=f.apply(this,arguments);if(cache)depois();atualizar();return r};n.__acessos=1;window[nome]=n}
function ligar(){envolver("renderProviderLoginHistory",desenharHistorico);envolver("renderProviderEmployees",()=>{desenharUltimos();desenharHistorico()});
  const ex=window.exportProviderLoginHistory;if(typeof ex==="function"&&!ex.__acessos){const n=async function(){const c=await ler();if(!c)return ex.apply(this,arguments);
      const rows=[["Data e hora","Funcionário","E-mail","Função","Empresa","Resultado","Detalhe"],...c.linhas.map(x=>[quando(x.dateTime),x.name,x.email,x.role,x.company,x.result,x.reason])];
      const csv=rows.map(r=>r.map(v=>`"${String(v??"").replace(/"/g,'""')}"`).join(";")).join("\n");
      if(typeof downloadTextFile==="function")downloadTextFile("Historico-acessos-empresa.csv","﻿"+csv,"text/csv;charset=utf-8")};n.__acessos=1;window.exportProviderLoginHistory=n}}
ligar();if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);
window.addEventListener("load",()=>setTimeout(()=>{ligar();if($("providerLoginHistoryList")?.offsetParent)atualizar()},800));
window.elologAcessosEquipa={ler,atualizar};
})();
