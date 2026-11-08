/* Elolog — Centro de Gestão de Tarifários: acesso aos dados (v114).
   Com servidor: lê e grava só pelo Supabase (regras de acesso e validações no servidor; o motor de preços é private.motor_preco).
   Sem servidor (demonstração): mostra exemplos só de leitura. Nunca calcula preços no navegador: o preço vem sempre do motor. */
(function(){"use strict";
const P=()=>window.elologProducao,online=()=>!!P()?.online?.();
async function sb(){const c=await P().sb();if(!c)throw new Error("Sem ligação ao servidor.");return c}
const erro=e=>{const m=String(e?.message||e||"");if(/42501|permission|Sem permiss|Só a administração/i.test(m)&&!/Só a administração Elolog (decide|pode testar)/.test(m))return new Error("Sem permissão. Confirme que entrou com o código de 2 passos.");return new Error(m.replace(/^.*?ERROR:\s*/,""))};
async function q(p){const{data,error}=await p;if(error)throw erro(error);return data}

/* exemplos da demonstração (só para ver o ecrã; não entram em nenhum cálculo) */
const hoje=new Date(),d=n=>new Date(hoje-n*864e5).toISOString();
const DEMO={empresas:[{id:"e1",nome:"Atlântico Cargo Lda"},{id:"e2",nome:"Rotas do Golfo"}],
  tarifas:[{id:"t1",empresa_id:"e1",empresas:{nome:"Atlântico Cargo Lda"},nome:"Lisboa a São Tomé, por peso",versao:2,tarifa_pai_id:"t0",metodo:"peso",valor:2.4,moeda:"EUR",preco_minimo:60,limite_max:2000,origem:"Lisboa",destino:"São Tomé",estado:"pendente",submetida_em:d(1),regras:{}},
    {id:"t0",empresa_id:"e1",empresas:{nome:"Atlântico Cargo Lda"},nome:"Lisboa a São Tomé, por peso",versao:1,metodo:"peso",valor:2.1,moeda:"EUR",preco_minimo:60,limite_max:2000,origem:"Lisboa",destino:"São Tomé",estado:"aprovada",decidida_em:d(40),regras:{}},
    {id:"t2",empresa_id:"e2",empresas:{nome:"Rotas do Golfo"},nome:"Porto a Luanda, contentor",versao:1,metodo:"unidade",valor:1850,moeda:"EUR",preco_minimo:0,origem:"Porto",destino:"Luanda",estado:"aprovada",decidida_em:d(12),regras:{}}],
  gerais:[{id:"g1",codigo:"TG-0001",nome:"Referência Lisboa a São Tomé",uso:"referencia",metodo:"peso",valor:2.2,moeda:"EUR",preco_minimo:50,origem:"Lisboa",destino:"São Tomé",estado:"ativa",versao:3,prestadores:[]}],
  comissoes:[{id:"c1",nome:"Comissão geral",empresa_id:null,tipo_valor:"percentagem",valor:8,apresentacao:"incluida",ativa:true,promocional:false,prioridade:0},
    {id:"c2",nome:"Lançamento Bissau",empresa_id:null,rota_destino:"Bissau",tipo_valor:"percentagem",valor:4,apresentacao:"incluida",ativa:true,promocional:true,fim:new Date(Date.now()+30*864e5).toISOString().slice(0,10),prioridade:1}],
  suplementos:[{id:"s1",empresa_id:null,nome:"Recolha na morada",chave:"recolha_km",tipo:"por_km",valor:1,estado:"aprovado"},{id:"s2",empresa_id:"e1",empresas:{nome:"Atlântico Cargo Lda"},nome:"Seguro da carga",chave:"seguro",tipo:"percentual",valor:1.5,estado:"pendente"}],
  historico:[{id:1,entidade:"tarifas",estado_anterior:null,estado_novo:"pendente",motivo:"Subida do combustível",user_nome:"Rita Lopes",created_at:d(1),antes:null,depois:{nome:"Lisboa a São Tomé, por peso",valor:2.4,versao:2}},
    {id:2,entidade:"tarifas_gerais",estado_anterior:"ativa",estado_novo:"ativa",motivo:"Atualização anual",user_nome:"Equipa Elolog",created_at:d(9),antes:{nome:"Referência Lisboa a São Tomé",valor:2.1},depois:{nome:"Referência Lisboa a São Tomé",valor:2.2,versao:3}}]};

const API={
  online,
  async empresas(){if(!online())return DEMO.empresas;return q((await sb()).from("empresas").select("id,nome").eq("estado","aprovada").order("nome"))},
  async tarifas(){if(!online())return DEMO.tarifas;return q((await sb()).from("tarifas").select("*, empresas(nome)").order("created_at",{ascending:false}).limit(500))},
  async gerais(){if(!online())return DEMO.gerais;return q((await sb()).from("tarifas_gerais").select("*").order("created_at",{ascending:false}).limit(300))},
  async comissoes(){if(!online())return DEMO.comissoes;return q((await sb()).from("regras_comissao").select("*, empresas(nome)").order("updated_at",{ascending:false}))},
  async suplementos(){if(!online())return DEMO.suplementos;return q((await sb()).from("tarifa_suplementos").select("*, empresas(nome)").order("created_at",{ascending:false}))},
  async historico(){if(!online())return DEMO.historico;return q((await sb()).from("tarifas_historico").select("*").order("created_at",{ascending:false}).limit(200))},
  async decidir(id,decisao,motivo){exigir();return q((await sb()).rpc("tarifa_decidir",{p_tarifa:id,p_decisao:decisao,p_motivo:motivo||null}))},
  async decidirSuplemento(id,decisao,motivo){exigir();return q((await sb()).rpc("suplemento_decidir",{p_suplemento:id,p_decisao:decisao,p_motivo:motivo||null}))},
  async guardarGeral(dados,id){exigir();const c=await sb();return q(id?c.from("tarifas_gerais").update(dados).eq("id",id).select().single():c.from("tarifas_gerais").insert(dados).select().single())},
  async guardarComissao(dados,id){exigir();const c=await sb();const base={escopo:"encomenda",evento:"aprovacao",...dados};
    return q(id?c.from("regras_comissao").update({...dados,updated_at:new Date().toISOString()}).eq("id",id).select().single():c.from("regras_comissao").insert(base).select().single())},
  async guardarSuplemento(dados,id){exigir();const c=await sb();return q(id?c.from("tarifa_suplementos").update(dados).eq("id",id).select().single():c.from("tarifa_suplementos").insert({...dados,estado:"aprovado"}).select().single())},
  async testar(p){exigir();return q((await sb()).rpc("testar_preco",p))}};
function exigir(){if(!online())throw new Error("Na demonstração os tarifários são só de leitura. Com o servidor ligado, esta ação grava e fica no histórico.")}

/* textos partilhados pelos ecrãs */
const METODO={peso:"por kg",volume:"por m³",unidade:"por unidade",fixo:"preço fixo",wm:"peso ou volume",contentor:"por contentor"};
const ESTADO={rascunho:["Rascunho","neutro"],pendente:["Por aprovar","aviso"],alteracoes_pedidas:["Alterações pedidas","aviso"],aprovada:["Aprovada","ok"],rejeitada:["Rejeitada","erro"],
  suspensa:["Suspensa","erro"],inativa:["Desativada","neutro"],substituida:["Substituída","neutro"],ativa:["Em vigor","ok"],aprovado:["Aprovado","ok"],rejeitado:["Rejeitado","erro"],suspenso:["Suspenso","erro"],inativo:["Desativado","neutro"]};
const eur=(v,m)=>v==null||v===""?"—":Number(v).toLocaleString("pt-PT",{style:"currency",currency:(m||"EUR").trim()||"EUR",maximumFractionDigits:2});
const rota=t=>t.origem||t.destino?`${t.origem||"qualquer origem"} para ${t.destino||"qualquer destino"}`:"Todas as rotas";
const expirada=t=>t.validade_fim&&t.validade_fim<new Date().toISOString().slice(0,10);
window.elologTarifarios={API,METODO,ESTADO,eur,rota,expirada};
})();
