/* Elolog — Integrações (v127): o administrador da empresa liga a Elolog ao seu ERP/WMS por webhooks.
   Grava o endereço https:// e os eventos, gera o segredo (mostrado UMA vez), envia um evento de teste e vê os últimos envios.
   Servidor: configurar_webhook, ver_webhook, gerar_segredo_webhook, testar_webhook e a tabela eventos_saida (RLS). */
(function(){"use strict";
const P=()=>window.elologProducao,online=()=>!!P()?.online?.(),esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const erroTexto=e=>String(e?.message||e||"").replace(/^.*?ERROR:\s*/,"");
const EVENTOS=[["encomenda.criada","Encomenda criada"],["encomenda.estado","Mudança de estado da encomenda"],["documento.emitido","Documento emitido (guia, receção, comprovativo)"],
  ["percurso.iniciado","Motorista iniciou o percurso"],["atraso.previsto","Atraso previsto na recolha ou entrega"],["terreno.comprovativo","Comprovativo registado no terreno"]];
const ESTADO={pendente:"Por enviar",enviado:"Entregue",falhou:"Falhou"};
const quando=v=>v?new Date(v).toLocaleString("pt-PT",{dateStyle:"short",timeStyle:"short"}):"—";
const rpc=async(n,a)=>{const sb=await P().sb();const{data,error}=await sb.rpc(n,a||{});if(error)throw error;return data};

async function abrir(botao){const s=window.elologPaginaPropria("integracoesPagina","Integrações",botao);if(!s)return;s.innerHTML='<div class="card tv"><p role="status">A carregar…</p></div>';await desenhar()}
async function desenhar(segredo){const s=document.getElementById("integracoesPagina");if(!s)return;let w={},ev=[];
  if(online()){try{w=await rpc("ver_webhook")||{};const sb=await P().sb();const{data}=await sb.from("eventos_saida").select("id,tipo,encomenda_codigo,estado,tentativas,ultimo_erro,criado_em,enviado_em").order("id",{ascending:false}).limit(20);ev=data||[]}catch(e){w={erro:erroTexto(e)}}}
  const marcados=new Set(w.eventos||EVENTOS.map(e=>e[0]));
  s.innerHTML=`<div class="card tv ig"><div class="tv-topo"><div><h2>Integrações</h2><p>Envie automaticamente as mudanças das encomendas para o seu sistema (ERP, WMS, faturação). A Elolog faz um pedido POST ao seu endereço sempre que algo muda.</p></div></div>
    ${!online()?'<p class="tv-nota"><b>Demonstração:</b> as integrações só funcionam ligadas ao servidor.</p>':""}${w.erro?`<p class="tv-erro">${esc(w.erro)}</p>`:""}
    ${segredo?`<section class="ig-segredo" role="alert"><b>Guarde este segredo agora: não volta a ser mostrado.</b><code id="igSeg">${esc(segredo)}</code><button type="button" class="btn-secondary" id="igCopiar">Copiar</button></section>`:""}
    <form id="igForm" class="ig-form" novalidate><label>Endereço que recebe os eventos<input id="igUrl" type="url" inputmode="url" placeholder="https://o-seu-sistema.pt/elolog" value="${esc(w.url||"")}" required></label>
      <fieldset><legend>Eventos a enviar</legend>${EVENTOS.map(([k,t])=>`<label class="ig-ev"><input type="checkbox" value="${k}"${marcados.has(k)?" checked":""}> ${t} <code>${k}</code></label>`).join("")}</fieldset>
      <label class="ig-ev"><input type="checkbox" id="igAtivo"${w.ativo===false?"":" checked"}> Integração ativa</label>
      <div class="tv-acoes"><button type="submit" class="btn-primary">Guardar</button>${w.url?`<button type="button" class="btn-secondary" data-ig="segredo">${w.tem_segredo?"Gerar novo segredo":"Gerar segredo"}</button><button type="button" class="btn-secondary" data-ig="teste">Enviar evento de teste</button>`:""}</div>
      <p class="tv-msg" id="igMsg" role="status"></p></form>
    ${w.url?`<p class="tv-nota">Último envio: ${w.ultimo_em?`${esc(w.ultimo_estado)} (${quando(w.ultimo_em)})`:"ainda nenhum"} · ${esc(w.pendentes??0)} por enviar · segredo ${w.tem_segredo?`gerado a ${quando(w.segredo_gerado_em)}`:"<b>ainda não gerado</b> (os envios esperam por ele)"}.</p>`:""}
    ${ev.length?`<h3>Últimos eventos</h3><div class="ig-tab-envolve"><table class="ig-tab"><thead><tr><th>Evento</th><th>Encomenda</th><th>Estado</th><th>Tentativas</th><th>Criado</th></tr></thead><tbody>${ev.map(e=>`<tr><td><code>${esc(e.tipo)}</code></td><td>${esc(e.encomenda_codigo||"—")}</td>
      <td class="ig-${esc(e.estado)}">${ESTADO[e.estado]||esc(e.estado)}${e.ultimo_erro?` · ${esc(e.ultimo_erro)}`:""}</td><td>${esc(e.tentativas)}</td><td>${quando(e.criado_em)}</td></tr>`).join("")}</tbody></table></div>`:""}
    <details class="ig-ajuda"><summary>Como verificar que o pedido vem da Elolog</summary><p>Cada pedido traz <code>X-Elolog-Assinatura: t=…,v1=…</code>. Calcule o HMAC-SHA256 de <code>t + "." + corpo</code> com o seu segredo e compare com <code>v1</code>. Recuse pedidos com <code>t</code> mais antigo do que 5 minutos. Responda 2xx em menos de 8 segundos; sem resposta, a Elolog repete até 8 vezes com espera crescente.</p>
<pre class="ig-codigo">const [t, v1] = cab.split(",").map(p => p.split("=")[1]);
const esperado = crypto.createHmac("sha256", SEGREDO).update(t + "." + corpo).digest("hex");
const valido = crypto.timingSafeEqual(Buffer.from(esperado), Buffer.from(v1));</pre></details></div>`;
  ligar(s)}
function ligar(s){const msg=document.getElementById("igMsg"),dizer=(t,c)=>{msg.className="tv-msg "+(c||"");msg.textContent=t};
  document.getElementById("igCopiar")?.addEventListener("click",async ev=>{try{await navigator.clipboard.writeText(document.getElementById("igSeg").textContent);ev.target.textContent="Copiado"}catch(_){getSelection().selectAllChildren(document.getElementById("igSeg"))}});
  document.getElementById("igForm").onsubmit=async e=>{e.preventDefault();if(!online())return dizer("Disponível quando a empresa estiver ligada ao servidor.","erro");
    const eventos=[...s.querySelectorAll('fieldset input:checked')].map(i=>i.value);try{await rpc("configurar_webhook",{p_url:document.getElementById("igUrl").value,p_eventos:eventos,p_ativo:document.getElementById("igAtivo").checked});
      await desenhar();document.getElementById("igMsg").textContent="Integração guardada."}catch(er){dizer(erroTexto(er),"erro")}};
  s.querySelectorAll("[data-ig]").forEach(b=>b.onclick=async()=>{b.disabled=true;try{if(b.dataset.ig==="segredo"){const seg=await rpc("gerar_segredo_webhook");await desenhar(seg)}
      else{await rpc("testar_webhook");dizer("Evento de teste na fila. Chega ao seu sistema em até 2 minutos.","ok")}}catch(er){dizer(erroTexto(er),"erro")}finally{b.disabled=false}})}
window.elologIntegracoes={abrir};
})();
