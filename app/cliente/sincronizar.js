/* Elolog — cliente: encomendas e pedidos sempre atualizados a partir do servidor (v70).
   A cada 30 s (e ao voltar à página) lê as simulações enviadas e as encomendas do cliente (o RLS só devolve as dele),
   junta-as às «operações» que os ecrãs do cliente já usam e redesenha. Quando um estado muda, mostra um aviso.
   Sem servidor (modo de demonstração) não faz nada. */
(function(){const S=()=>window.ELOLogServidor;
  const ETAPA={aprovacao:"Aprovação",agendamento:"Recolha",recolha:"Recolha",armazenamento:"Armazenamento",expedicao:"Expedição",em_transito:"Em trânsito",destino:"Destino",entregue:"Levantado",cancelada:"Cancelada"};
  const NOME={aprovacao:"em aprovação pelo prestador",agendamento:"recolha agendada",recolha:"em recolha",armazenamento:"no armazém",expedicao:"em expedição",em_transito:"em trânsito",destino:"chegou ao destino",entregue:"entregue",cancelada:"cancelada"};
  const eur=v=>v==null?"Por cotação":Number(v).toLocaleString("pt-PT",{style:"currency",currency:"EUR"});
  let assinatura="",estados=null,ocupado=false,temporizador=null;
  const ativo=()=>currentUser?.role==="cliente"&&currentUser?.authenticatedBy!=="local-demo"&&!!S()?.ativo?.();

  function juntar(sims,encs){const porSim={};encs.forEach(e=>{if(e.simulacao_id)porSim[e.simulacao_id]=e});
    const linhas=[...encs.map(e=>({codigo:e.codigo,antigo:sims.find(x=>x.id===e.simulacao_id)?.codigo,origem:e.origem,destino:e.destino,carga:e.tipo_carga,peso:e.peso_kg,volume:e.volume_m3,data:e.data_prevista,
        total:eur(e.preco_total),etapa:ETAPA[e.estado]||e.estado,status:e.estado==="cancelada"?"Cancelada":e.suspensa?"Suspensa":ETAPA[e.estado]||e.estado,criado:e.created_at,estado:e.estado,suspensa:!!e.suspensa})),
      ...sims.filter(x=>!porSim[x.id]&&x.estado!=="rascunho").map(x=>({codigo:x.codigo,origem:x.origem,destino:x.destino,carga:x.tipo_carga,peso:x.peso_kg,volume:x.volume_m3,data:x.data_prevista,
        total:x.preco_estimado==null?"Por cotação":eur(x.preco_estimado),etapa:"Cotação",status:x.estado==="cancelada"?"Cancelada":"Cotação",criado:x.created_at,estado:"sim_"+x.estado}))];
    linhas.forEach(l=>{let o=operations.find(x=>x.id===l.codigo)||(l.antigo&&operations.find(x=>x.id===l.antigo));
      if(!o){o={id:l.codigo,client:currentUser.name,createdAt:l.criado};operations.unshift(o)}
      Object.assign(o,{id:l.codigo,client:o.client||currentUser.name,origin:l.origem,destination:l.destino,cargo:o.cargo||l.carga||"",weight:l.peso!=null?`${Number(l.peso)} kg`:o.weight,
        volume:l.volume!=null?Number(l.volume):o.volume,date:l.data||o.date,total:l.total,stage:l.etapa,status:l.status,suspended:!!l.suspensa,servidor:true})});
    return linhas}

  function avisar(linhas){const agora={};linhas.forEach(l=>agora[l.codigo]=l.estado);
    if(estados)linhas.forEach(l=>{const antes=estados[l.codigo];if(antes&&antes!==l.estado&&NOME[l.estado])showPlatformNotice?.(`Encomenda ${l.codigo}: ${NOME[l.estado]}.`,"success");
      else if(!antes&&l.antigo&&estados[l.antigo])showPlatformNotice?.(`O prestador aceitou o seu pedido: encomenda ${l.codigo} criada.`,"success")});
    estados=agora}

  function redesenhar(){try{renderClientTracking?.()}catch(e){}try{renderClientDashboard?.()}catch(e){}}

  async function atualizar(forcar){if(ocupado||!ativo())return;ocupado=true;
    try{const c=await S().cliente(),{data:u}=await c.auth.getUser();if(!u?.user)return;
      const [s,e]=await Promise.all([c.from("simulacoes").select("id,codigo,origem,destino,tipo_carga,peso_kg,volume_m3,estado,preco_estimado,data_prevista,created_at,updated_at").eq("cliente_id",u.user.id).order("created_at",{ascending:false}).limit(100),
        c.from("encomendas").select("id,codigo,simulacao_id,origem,destino,tipo_carga,peso_kg,volume_m3,estado,suspensa,preco_total,data_prevista,created_at,updated_at").eq("cliente_id",u.user.id).order("created_at",{ascending:false}).limit(200)]);
      if(s.error||e.error)throw s.error||e.error;
      const nova=JSON.stringify([s.data.map(x=>[x.codigo,x.estado,x.updated_at]),e.data.map(x=>[x.codigo,x.estado,x.updated_at])]);
      if(!forcar&&nova===assinatura)return;assinatura=nova;const linhas=juntar(s.data,e.data);avisar(linhas);try{saveAll?.()}catch(_){}redesenhar()}
    catch(err){console.warn("Elolog: atualização das encomendas falhou.",err?.message||err)}finally{ocupado=false}}

  function iniciar(){clearInterval(temporizador);if(!ativo())return;atualizar(true);temporizador=setInterval(()=>{if(document.visibilityState==="visible")atualizar(false)},3e4)}
  document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="visible")atualizar(false)});
  if(typeof startApp==="function"){const ini=startApp;startApp=async function(){const r=await ini.apply(this,arguments);iniciar();return r}}
  window.elologAtualizarCliente=()=>atualizar(true);
})();
