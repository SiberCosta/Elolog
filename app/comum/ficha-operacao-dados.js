/* Elolog — Ficha da operação (v100): dados e ações.
   Com servidor: encomenda_ficha (só leitura) e as funções de etapa avancar_encomenda, encomenda_rececao_armazem, encomenda_expedicao,
   encomenda_processamento_destino e encomenda_levantamento, pela ligação Supabase existente. As regras ficam no servidor: o ecrã só mostra
   o que falta e nunca deixa saltar etapas. Sem servidor (demonstração) a ficha é construída a partir das operações guardadas no navegador. */
(function(){"use strict";
const P=()=>window.elologProducao;
const online=()=>{try{return!!P()?.online?.()}catch(_){return false}};
const erro=e=>window.ELOLogServidor?.mensagem?.(e)||e?.message||String(e);
const ETAPAS=["Simulação","Cotação","Aprovação","Recolha","Pagamento","Armazenamento","Expedição","Em trânsito","Destino","Disponível","Levantado"];
const IDX={aprovacao:2,agendamento:3,recolha:3,armazenamento:5,expedicao:6,em_transito:7,destino:8,disponivel:9,entregue:10};
const NOME={aprovacao:"Aprovação",agendamento:"Agendamento da recolha",recolha:"Recolha",armazenamento:"Armazenamento",expedicao:"Expedição",em_transito:"Em trânsito",
  destino:"Destino",disponivel:"Disponível",entregue:"Levantado",cancelada:"Cancelada"};
const RESP=["Cliente / Operador","Operador","Administração / Cliente","Prestador","Financeiro","Armazém","Operador","Operador","Prestador / Operador","Operador","Prestador / Operador"];
const ACAO=["Registar pedido","Solicitar e comparar propostas","Validar proposta","Confirmar recolha","Registar e confirmar valores","Confirmar receção","Associar partida e carga",
  "Atualizar acompanhamento","Confirmar chegada","Avisar cliente","Confirmar entrega"];
const nomeEstado=e=>NOME[e]||e;

/* ---------- demonstração: a partir das operações do navegador ---------- */
const ler=k=>{try{return JSON.parse(localStorage.getItem(k)||"[]")||[]}catch(_){return[]}};
const norm=v=>String(v||"").normalize("NFD").replace(/[̀-ͯ]/g,"").toLowerCase();
function demo(codigo){const c=String(codigo).toUpperCase(),o=[...ler("th_operations"),...ler("elologClientShipments")].find(x=>String(x.id||x.code).toUpperCase()===c);
  const linha=!o&&(window.__ELOLOG_INTERNO?.painelDados?.()?.operacoes_recentes||[]).find(x=>String(x.ref).toUpperCase()===c);if(!o&&!linha)throw new Error("Encomenda não encontrada.");
  const etapa=o?.stage||o?.status||linha?.estado||"Aprovação",i=Math.max(0,ETAPAS.findIndex(x=>norm(x)===norm(etapa)));
  const hist=(o?(typeof getProviderOrderHistory==="function"?getProviderOrderHistory(o.id):[]).concat(o.history||[]):[]).map(h=>({de:h.previous||null,para:h.next||h.status,em:h.isoDate||h.dateTime||h.datetime,
    responsavel:h.employee,prestador:o?.provider,nota:h.note||h.observation,motivo_excecao:h.exception||null,documentos:null}));
  const pag=ler("th_payments").filter(p=>String(p.operationId)===c).map(p=>({codigo:p.id,tipo:"total",valor:p.amount,estado:/pago|confirm/i.test(p.status)?"pago":/parcial/i.test(p.status)?"parcial":"pendente",metodo:p.method,em:p.createdAt}));
  const preco=Number(o?.finalPrice||o?.estimatedPrice||0),pago=ler("th_payments").filter(p=>String(p.operationId)===c).reduce((t,p)=>t+Number(p.paidAmount||0),0);
  return{demo:true,etapa_idx:i,papel:"demonstracao",prestador:o?.provider||linha?.prestador,cliente:{nome:o?.client||linha?.cliente,nif:o?.clientNif},
    encomenda:{codigo:c,estado:null,etapa:etapa,origem:o?.origin||linha?.origem,destino:o?.destination||linha?.destino,morada_recolha:o?.pickupAddress,tipo_carga:o?.cargo,descricao:o?.goods,
      quantidade:o?.quantity,peso_kg:o?.weight,volume_m3:o?.volume,volumes:Array.isArray(o?.volumes)?o.volumes:[],valor_declarado:o?.declaredPrice,preco_total:preco,data_prevista:o?.date,
      remetente:{nome:o?.senderName,telefone:o?.senderPhone,email:o?.senderEmail,morada:o?.senderAddress},destinatario:{nome:o?.recipientName,telefone:o?.recipientPhone,email:o?.recipientEmail,morada:o?.deliveryAddress}},
    simulacao:o?.simulationId?{codigo:o.simulationId}:null,documentos:(o?.extraDocuments||[]).map(d=>({nome:d.name||d.nome,mime:d.type||""})),fotos:(o?.anomalyPhotos||[]),
    pagamentos:pag,financeiro:{preco,pago,em_divida:Math.max(preco-pago,0),comissao:null,pendentes:pag.filter(p=>p.estado!=="pago").length},historico:hist,ocorrencias:[],proximos:[],chegou_em:{}}}

/* ---------- servidor ---------- */
async function rpc(nome,args){const c=await P().sb();const{data,error}=await c.rpc(nome,args);if(error)throw new Error(erro(error));return data}
async function carregar(codigo){if(!online())return demo(codigo);const f=await rpc("encomenda_ficha",{p_codigo:codigo});f.etapa_idx=IDX[f.encomenda.estado]??0;return f}
async function documento(ficheiro,codigo,categoria){if(!ficheiro)return null;const d=await P().enviarDocumento(ficheiro,{encomenda:codigo,categoria:categoria||"outro",visibilidade:"interna"});return d.id}
const ACOES={
  avancar:async(f,para,nota,ficheiro,excecao)=>{const doc=await documento(ficheiro,f.encomenda.codigo,"comprovativo");
    return rpc("avancar_encomenda",{p_encomenda:f.encomenda.id,p_para:para,p_nota:nota||null,p_documentos:doc?[doc]:null,p_excecao:excecao||null})},
  rececao:(f,d)=>rpc("encomenda_rececao_armazem",{p_encomenda:f.encomenda.id,p_quantidade:d.quantidade,p_conferida:!!d.conferida,p_ocorrencias:d.ocorrencias||null,p_localizacao:d.localizacao||null,p_armazem:null}),
  expedicao:(f,d)=>rpc("encomenda_expedicao",{p_encomenda:f.encomenda.id,p_navio:d.navio,p_viagem:d.viagem,p_partida:d.partida,p_chegada:d.chegada||null}),
  processamento:(f,nota)=>rpc("encomenda_processamento_destino",{p_encomenda:f.encomenda.id,p_nota:nota||null}),
  levantamento:async(f,ident,ficheiro)=>{if(!ficheiro)throw new Error("Anexe o comprovativo de entrega assinado.");const doc=await documento(ficheiro,f.encomenda.codigo,"entrega");
    return rpc("encomenda_levantamento",{p_encomenda:f.encomenda.id,p_identificacao:ident,p_documento:doc})},
  url:async caminho=>{const c=await P().sb();const{data,error}=await c.storage.from("documentos").createSignedUrl(caminho,300);if(error)throw new Error("Não foi possível abrir o documento.");return data.signedUrl}};
window.elologFichaDados={ETAPAS,IDX,NOME,RESP,ACAO,nomeEstado,carregar,online,erro,...ACOES};
})();
