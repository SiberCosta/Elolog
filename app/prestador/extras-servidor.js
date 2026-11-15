/* Elolog — última fase dos testes reais, prestador (v148).
   - Notas internas do cliente: cliente_notas (só para clientes com conta; ficam visíveis à equipa da empresa).
   - Pedido de informação ao cliente: pedido de apoio do prestador ligado ao cliente da simulação (o cliente vê-o e responde
     em «Os meus pedidos»).
   - Pagamentos e pré-pagamentos recebidos no terreno: linha em pagamentos marcada «numerário no terreno». O administrador e o
     financeiro registam-na como paga; o operador de terreno regista-a como pendente para o escritório conferir. */
(function(){"use strict";
const P=()=>window.elologProducao,$=id=>document.getElementById(id);
const ativo=()=>typeof currentUser!=="undefined"&&currentUser?.role==="prestador"&&currentUser?.providerCompany?.server===true&&!!P()?.online?.();
const aviso=(t,k)=>typeof showPlatformNotice==="function"?showPlatformNotice(t,k):alert(t);
const erro=e=>String(e?.message||e||"").replace(/^.*?ERROR:\s*/,"").replace(/^LIMITE_EXCEDIDO:\s*/,"");
const eur=v=>Number(v||0).toLocaleString("pt-PT",{style:"currency",currency:"EUR"});

async function clientePorNome(nome){const sb=await P().sb(),emp=await P().minhaEmpresa();
  const{data}=await sb.from("encomendas").select("cliente_id").eq("empresa_id",emp?.empresa_id).ilike("cliente_nome",nome).not("cliente_id","is",null).limit(1);
  if(data?.[0]?.cliente_id)return{id:data[0].cliente_id,emp};const{data:c}=await sb.from("clientes").select("id").ilike("nome",nome).limit(1);return{id:c?.[0]?.id||null,emp}}

async function nota(){const nome=typeof providerSelectedClient!=="undefined"?providerSelectedClient:"";if(!nome)return aviso("Selecione primeiro um cliente.","warning");
  const txt=$("providerClientInternalNote")?.value.trim();if(!txt)return aviso("Escreva a observação.","warning");
  const{id,emp}=await clientePorNome(nome);if(!id)return aviso(`«${nome}» não tem conta na Elolog: as notas internas só se guardam para clientes com conta.`,"warning");
  const sb=await P().sb(),u=await P().utilizador();const{error}=await sb.from("cliente_notas").insert({empresa_id:emp.empresa_id,cliente_id:id,nota:txt.slice(0,2000),autor_id:u.id});if(error)throw error;
  $("providerClientInternalNote").value="";aviso("Observação interna guardada no servidor (só a equipa da empresa a vê).","success")}

async function pedidoInfo(event){event?.preventDefault?.();const id=$("providerInfoSimulationId")?.value,msg=$("providerInfoMessage")?.value.trim(),cat=$("providerInfoCategory")?.value||"Informação",prazo=$("providerInfoDeadline")?.value,el=$("providerInfoError");
  if(!msg){if(el){el.textContent="Escreva a informação solicitada.";el.classList.add("show")}return}
  const sb=await P().sb();const{data:s}=await sb.from("simulacoes").select("cliente_id,codigo").eq("codigo",id).maybeSingle();
  const cli=s?.cliente_id||(await clientePorNome(String(id||""))).id;if(!cli)return aviso("Não encontrámos o cliente desta simulação no servidor.","warning");
  const emp=await P().minhaEmpresa(),u=await P().utilizador();
  const{data:t,error}=await sb.from("tickets").insert({origem:"prestador",empresa_id:emp.empresa_id,cliente_id:cli,criado_por:u.id,assunto:`Pedido de informação: ${cat}${s?.codigo?` (${s.codigo})`:""}`.slice(0,200)}).select("id,codigo").single();if(error)throw error;
  const r=await sb.from("ticket_mensagens").insert({ticket_id:t.id,autor_id:u.id,corpo:msg+(prazo?`\n\nResponder até ${new Date(prazo+"T12:00").toLocaleDateString("pt-PT")}.`:"")});if(r.error)throw r.error;
  window.closeProviderDrawer?.("platformRecordDrawer");window.elologApoio?.ler?.().then(()=>window.elologApoio.desenhar());aviso(`Pedido ${t.codigo||""} enviado ao cliente: ele responde em «Os meus pedidos».`,"success")}

async function terreno(enc,valor,metodo,ref,descr){const sb=await P().sb(),emp=await P().minhaEmpresa(),u=await P().utilizador();const escritorio=["admin_empresa","financeiro"].includes(emp?.papel);
  const{data:l}=await sb.from("pagamentos").select("valor,estado,tipo").eq("encomenda_id",enc.servidor.id);const{data:e}=await sb.from("encomendas").select("preco_total").eq("id",enc.servidor.id).maybeSingle();
  const pago=(l||[]).filter(x=>x.estado==="pago"&&x.tipo!=="reembolso").reduce((t,x)=>t+Number(x.valor||0),0),falta=Math.max(0,Number(e?.preco_total||0)-pago),v=valor==null?falta:valor;
  if(!(v>0)||v>falta+0.005)throw new Error(`O valor tem de estar entre 0,01 € e o que falta pagar (${eur(falta)}).`);
  const{error}=await sb.from("pagamentos").insert({empresa_id:emp.empresa_id,encomenda_id:enc.servidor.id,tipo:v<falta?"prestacao":"total",valor:v,estado:escritorio?"pago":"pendente",metodo,referencia:ref||null,
    numerario_terreno:true,registado_por:u.id,pago_em:escritorio?new Date().toISOString():null});if(error)throw error;
  window.closeProviderDrawer?.("platformRecordDrawer");aviso(`${descr} de ${eur(v)} registado no servidor${escritorio?"":"; o escritório confirma quando receber o dinheiro"}.`,"success")}

function ligar(){const w=(n,f)=>{const o=window[n];if(typeof o!=="function"||o.__extra)return;const nv=function(){if(!ativo())return o.apply(this,arguments);return Promise.resolve(f.apply(this,arguments)).catch(e=>aviso(erro(e),"error"))};nv.__extra=1;window[n]=nv};
  w("saveProviderClientNote",nota);w("submitProviderInformationRequest",pedidoInfo);
  w("saveFieldCashPayment",ev=>{ev?.preventDefault?.();const o=operations.find(x=>x.id===$("fieldCashOrder")?.value);if(!o)return;if(!o.servidor?.id)return aviso(`A encomenda ${o.id} não está no servidor.`,"warning");
    const tipo=$("fieldCashType")?.value,m=$("fieldPaymentMethod")?.value||"Numerário",ref=$("fieldCashReference")?.value.trim();if(m!=="Numerário"&&!ref)return aviso("Indique a referência da transação.","warning");
    return terreno(o,tipo==="total"?null:Number($("fieldCashAmount")?.value||0),m,ref,"Pagamento no terreno")});
  w("saveFieldPrepayment",ev=>{ev?.preventDefault?.();const o=operations.find(x=>x.id===$("fieldPrepaymentOrder")?.value);if(!o)return aviso("Escolha a encomenda.","warning");if(!o.servidor?.id)return aviso(`A encomenda ${o.id} não está no servidor.`,"warning");
    return terreno(o,Number($("fieldPrepaymentAmount")?.value||0),$("fieldPrepaymentMethod")?.value||"Numerário",$("fieldPrepaymentReference")?.value.trim(),"Pré-pagamento")})}
ligar();window.addEventListener("load",()=>setTimeout(ligar,300));
})();
