/* Elolog — EloLog Maritime Search 2/2 (v87): o prestador publica e atualiza as suas viagens (navio, datas, portos e espaço livre).
   Grava na tabela viagens_maritimas pela ligação Supabase já existente; as regras (só a própria empresa, datas coerentes,
   limites e auditoria) são garantidas na base de dados (migração 00153). */
(function(){"use strict";
const P=()=>window.elologProducao,esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const CAMPOS="navio,imo,mmsi,linha,viagem,sentido,porto_origem,porto_destino,partida,chegada,fecho_carga,estado,cont20_livres,cont40_livres,grupagem_m3,aceita_viaturas,notas,publicada".split(",");

function formulario(x){const M=window.elologMaritimo,v=k=>esc(x?.[k]??""),PT=M.PORTOS.PT,ST=M.PORTOS.STP,s=x?.sentido||"PT-STP";
  const op=(lista,atual)=>lista.map(p=>`<option ${p===atual?"selected":""}>${esc(p)}</option>`).join("");
  const est=Object.entries(M.ESTADOS).map(([k,[t]])=>`<option value="${k}" ${(x?.estado||"aberta")===k?"selected":""}>${t}</option>`).join("");
  return`<form class="mm-form" novalidate>
  <fieldset><legend>Navio</legend><label>Nome do navio *<input name="navio" required maxlength="80" value="${v("navio")}"></label>
    <label>Linha / armador<input name="linha" maxlength="80" value="${v("linha")}"></label><label>N.º da viagem<input name="viagem" maxlength="30" value="${v("viagem")}"></label>
    <label>IMO (7 dígitos)<input name="imo" inputmode="numeric" maxlength="7" pattern="[0-9]{7}" value="${v("imo")}"></label>
    <label>MMSI (9 dígitos) <small>para ver a posição real</small><input name="mmsi" inputmode="numeric" maxlength="9" pattern="[0-9]{9}" value="${v("mmsi")}"></label></fieldset>
  <fieldset><legend>Rota e datas</legend><label>Sentido *<select name="sentido"><option value="PT-STP" ${s==="PT-STP"?"selected":""}>Portugal → São Tomé</option><option value="STP-PT" ${s==="STP-PT"?"selected":""}>São Tomé → Portugal</option></select></label>
    <label>Porto de origem *<select name="porto_origem" data-lado="origem">${op(s==="PT-STP"?PT:ST,x?.porto_origem)}</select></label>
    <label>Porto de destino *<select name="porto_destino" data-lado="destino">${op(s==="PT-STP"?ST:PT,x?.porto_destino)}</select></label>
    <label>Partida *<input type="date" name="partida" required value="${v("partida")}"></label><label>Chegada prevista<input type="date" name="chegada" value="${v("chegada")}"></label>
    <label>Entrega da carga até<input type="date" name="fecho_carga" value="${v("fecho_carga")}"></label><label>Estado<select name="estado">${est}</select></label></fieldset>
  <fieldset><legend>Espaço disponível</legend><label>Contentores 20' livres<input type="number" name="cont20_livres" min="0" max="9999" value="${v("cont20_livres")}"></label>
    <label>Contentores 40' livres<input type="number" name="cont40_livres" min="0" max="9999" value="${v("cont40_livres")}"></label>
    <label>Grupagem (m³)<input type="number" name="grupagem_m3" min="0" max="99999" step="0.1" value="${v("grupagem_m3")}"></label>
    <label class="mm-check"><input type="checkbox" name="aceita_viaturas" ${x?.aceita_viaturas?"checked":""}> Aceita viaturas</label>
    <label class="mm-largo">Notas <small>(máx. 300)</small><textarea name="notas" maxlength="300" rows="2">${v("notas")}</textarea></label>
    <label class="mm-check"><input type="checkbox" name="publicada" ${x?.publicada===false?"":"checked"}> Visível na pesquisa para clientes e outros prestadores</label></fieldset>
  <p class="mm-erro" role="alert"></p></form>`}

function ler(f){const d=new FormData(f),o={},t=k=>String(d.get(k)||"").trim();
  CAMPOS.forEach(k=>{o[k]=["aceita_viaturas","publicada"].includes(k)?d.get(k)==="on":t(k)||null});
  ["cont20_livres","cont40_livres"].forEach(k=>{o[k]=o[k]==null?null:parseInt(o[k],10)});o.grupagem_m3=o.grupagem_m3==null?null:Number(o.grupagem_m3);
  if(!o.navio||o.navio.length<2)return"Indique o nome do navio.";if(o.imo&&!/^\d{7}$/.test(o.imo))return"O IMO tem 7 dígitos.";if(o.mmsi&&!/^\d{9}$/.test(o.mmsi))return"O MMSI tem 9 dígitos.";
  if(!o.partida)return"Indique a data de partida.";if(o.chegada&&o.chegada<o.partida)return"A chegada não pode ser antes da partida.";
  if(o.fecho_carga&&o.fecho_carga>o.partida)return"A entrega da carga tem de ser até ao dia da partida.";
  if([o.cont20_livres,o.cont40_livres,o.grupagem_m3].some(n=>n!=null&&(!Number.isFinite(n)||n<0)))return"Os valores de espaço livre têm de ser números positivos.";return o}

async function abrir(x){const p=P();if(!p)return;
  if(x?.id&&p.online()){try{const sb=await p.sb(),{data}=await sb.from("viagens_maritimas").select("*").eq("id",x.id).maybeSingle();if(data)x=data}catch(_){}}const j=p.janela({eyebrow:"ELOLOG MARITIME SEARCH",titulo:x?"Editar viagem":"Publicar viagem"});j.corpo.closest(".pm-caixa").classList.add("mm-janela");
  const guardar=async()=>{const f=j.corpo.querySelector("form"),erro=j.corpo.querySelector(".mm-erro"),o=ler(f);if(typeof o==="string"){erro.textContent=o;return}
    if(!p.online()){erro.textContent="No modo de demonstração as viagens não são gravadas.";return}
    try{const sb=await p.sb();let r;if(x?.id)r=await sb.from("viagens_maritimas").update(o).eq("id",x.id);
      else{const emp=await p.minhaEmpresa();if(!emp?.empresa_id)throw new Error("Abra a sessão da empresa para publicar viagens.");r=await sb.from("viagens_maritimas").insert({...o,empresa_id:emp.empresa_id})}
      if(r.error)throw r.error;p.aviso(x?"Viagem atualizada.":"Viagem publicada na pesquisa marítima.","success");j.fechar();window.elologMaritimo?.abrir()}
    catch(e){erro.textContent=/LIMITE_EXCEDIDO/.test(e.message||"")?"Demasiadas alterações seguidas. Aguarde alguns minutos.":window.ELOLogServidor?.mensagem?.(e)||e.message}};
  const botoes=[{texto:"Cancelar",acao:()=>{j.fechar();window.elologMaritimo?.abrir()}},{texto:x?"Guardar alterações":"Publicar viagem",principal:true,acao:guardar}];
  if(x?.id)botoes.splice(1,0,{texto:"Cancelar viagem",acao:async()=>{j.corpo.querySelector("[name=estado]").value="cancelada";await guardar()}});
  j.mostrar(formulario(x),botoes);
  j.corpo.querySelector("[name=sentido]").onchange=e=>{const M=window.elologMaritimo,pt=e.target.value==="PT-STP",op=l=>l.map(p=>`<option>${esc(p)}</option>`).join("");
    j.corpo.querySelector("[name=porto_origem]").innerHTML=op(pt?M.PORTOS.PT:M.PORTOS.STP);j.corpo.querySelector("[name=porto_destino]").innerHTML=op(pt?M.PORTOS.STP:M.PORTOS.PT)}}
window.elologMaritimoForm={abrir,ler};
})();
