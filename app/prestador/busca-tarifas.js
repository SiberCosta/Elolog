/* Elolog — tarifa de cada linha de carga na simulação direta do prestador (v143).
   Antes a «Carga / descrição» era usada para adivinhar a tarifa: escrever «CARGA VL» aplicava a tarifa com esse nome. Isso
   misturava duas coisas diferentes e criava dúvidas. Agora:
   - a descrição é só o que a carga é (ex.: «Bidão 200 L»), e nunca muda o preço;
   - cada linha tem um campo «Tarifa» com as tarifas criadas pela empresa (ativas, sem as de recolha), ou «Sem tarifa: preço à mão»;
   - escolher a tarifa preenche a tarifação e o preço unitário; mudar o preço à mão desliga a tarifa dessa linha (fica dito na linha);
   - se a descrição se parecer com o nome de uma tarifa, aparece só uma sugestão com o botão «Usar esta tarifa», nada é aplicado sozinho. */
(function(){"use strict";
const T=()=>window.elologTarifarios,esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const ativas=()=>{try{return(typeof providerDirectActiveTariffs==="function"?providerDirectActiveTariffs():[]).filter(t=>t.application!=="pickup"&&!(typeof isProviderPickupTariff==="function"&&isProviderPickupTariff(t)))}catch(_){return[]}};
const metodo=t=>typeof providerDirectMethodFromTariff==="function"?providerDirectMethodFromTariff(t.method):"unit";
const preco=t=>Number(t.value||0).toLocaleString("pt-PT",{style:"currency",currency:t.currency||"EUR"});
const rotulo=t=>`${t.name}: ${preco(t)} ${String(t.method||"").toLowerCase()}`.trim();
const porId=id=>ativas().find(t=>String(t.id)===String(id));

/** tarifa ativa cujo nome (ou palavra) aparece na descrição: serve só para sugerir */
function procurar(desc){if(!T()?.procura||!String(desc||"").trim())return null;let melhor=null,termo="";
  for(const t of ativas()){const p=T().procura(desc,t.name,t.rules?.palavras);if(p&&p.length>termo.length){melhor=t;termo=p}}
  return melhor?{tarifa:melhor,termo}:null}

function dica(row,html){let d=row.querySelector(".pdv-busca");if(!d){d=document.createElement("small");d.className="pdv-busca";d.setAttribute("aria-live","polite");
    row.appendChild(d)}d.innerHTML=html||"";d.hidden=!html}

/* campo «Tarifa» na linha */
function opcoes(sel,atual){const l=ativas();
  sel.innerHTML=`<option value="">Sem tarifa: preço à mão</option>`+l.map(t=>`<option value="${esc(t.id)}">${esc(rotulo(t))}</option>`).join("")+
    (atual&&!porId(atual)?`<option value="${esc(atual)}">Tarifa já não ativa</option>`:"");sel.value=atual||""}
function preparar(row){if(!row||row.querySelector(".pdv-tariff"))return;const desc=row.querySelector(".pdv-description")?.closest("label");if(!desc)return;
  const lab=document.createElement("label");lab.className="pdv-tarifa-campo";lab.innerHTML=`<span>Tarifa</span><select class="pdv-tariff" aria-label="Tarifa desta linha"></select>`;
  desc.after(lab);const span=desc.querySelector("span");if(span)span.textContent="Descrição da carga";const met=row.querySelector(".pdv-method")?.closest("label")?.querySelector("span");if(met)met.textContent="Forma de cobrança";
  const sel=lab.querySelector("select");opcoes(sel,row.dataset.tariffId||"");if(row.dataset.tariffId)marcar(row,porId(row.dataset.tariffId),false)}

function marcar(row,t,aplicarPreco=true){const sel=row.querySelector(".pdv-tariff");
  if(!t){delete row.dataset.tariffId;delete row.dataset.busca;row.classList.remove("financial-tariff-row");row.removeAttribute("title");if(sel){sel.value="";sel.title=""}return}
  row.dataset.tariffId=t.id;delete row.dataset.manual;row.dataset.volumetricFactor=String(t.rules?.volumetricFactor||167);row.classList.add("financial-tariff-row");row.title=`Tarifa: ${t.name}`;
  if(sel){if(![...sel.options].some(o=>o.value===String(t.id)))opcoes(sel,String(t.id));sel.value=String(t.id);sel.title=rotulo(t)}
  if(aplicarPreco){row.querySelector(".pdv-method").value=metodo(t);row.querySelector(".pdv-unit-price").value=Number(t.value||0)}
  dica(row,`Preço da tarifa: ${esc(preco(t))} ${esc(String(t.method||"").toLowerCase())}.`)}

function escolher(row,id){const t=id?porId(id):null;
  if(id&&!t){dica(row,"Esta tarifa já não está ativa. Escolha outra ou indique o preço à mão.");return}
  marcar(row,t);if(!t){row.dataset.manual="1";dica(row,"Sem tarifa: indique a tarifação e o preço unitário.")}
  if(typeof updateProviderDirectTotals==="function")updateProviderDirectTotals()}

function sugerir(row){if(row.dataset.tariffId)return;const r=procurar(row.querySelector(".pdv-description")?.value);
  dica(row,r?`A descrição parece-se com a tarifa «${esc(r.tarifa.name)}». <button type="button" class="pdv-usar" data-usar="${esc(r.tarifa.id)}">Usar esta tarifa</button>`:
    ativas().length?"Escolha a tarifa desta linha ou indique o preço à mão.":"Ainda não há tarifas ativas: indique a tarifação e o preço à mão.")}

/* compatibilidade: outras partes chamavam aplicar(row) para procurar pela descrição; agora só sugere */
function aplicar(row){preparar(row);sugerir(row)}

function cabecalho(){const h=document.querySelector("#providerDirectSimulation .client-volume-table-head");if(!h||h.dataset.tarifa)return;h.dataset.tarifa="1";
  const sp=[...h.children];if(sp[0])sp[0].textContent="Descrição da carga";if(sp[2])sp[2].textContent="Cobrança";const t=document.createElement("span");t.textContent="Tarifa";sp[0]?.after(t)}
function todas(){const box=document.getElementById("providerDirectVolumes");if(!box)return;cabecalho();
  box.querySelectorAll(".sim-volume-row").forEach(row=>{preparar(row);const sel=row.querySelector(".pdv-tariff");if(sel&&sel.options.length!==ativas().length+1+(row.dataset.tariffId&&!porId(row.dataset.tariffId)?1:0))opcoes(sel,row.dataset.tariffId||"")})}

/* novas linhas (manuais ou criadas a partir de uma tarifa) recebem o campo «Tarifa» já com a tarifa certa */
let vigia=null;
function vigiar(){const box=document.getElementById("providerDirectVolumes");if(!box||box.__tarifas)return;box.__tarifas=1;
  vigia=new MutationObserver(ms=>ms.forEach(m=>m.addedNodes.forEach(n=>{if(n.nodeType===1&&n.classList.contains("sim-volume-row"))preparar(n)})));
  vigia.observe(box,{childList:true});todas()}

document.addEventListener("change",e=>{const el=e.target;if(!el.classList?.contains("pdv-tariff"))return;const row=el.closest(".sim-volume-row");if(row)escolher(row,el.value)});
let espera;
document.addEventListener("input",e=>{const el=e.target;if(!el.closest?.("#providerDirectVolumes"))return;const row=el.closest(".sim-volume-row");if(!row)return;
  if(el.classList.contains("pdv-unit-price")||el.classList.contains("pdv-method")){const t=row.dataset.tariffId&&porId(row.dataset.tariffId);
    if(t&&(Number(row.querySelector(".pdv-unit-price").value)!==Number(t.value||0)||row.querySelector(".pdv-method").value!==metodo(t))){
      marcar(row,null);row.dataset.manual="1";dica(row,`Preço alterado à mão: a tarifa «${esc(t.name)}» deixou de se aplicar a esta linha.`)}return}
  if(el.classList.contains("pdv-description")){clearTimeout(espera);espera=setTimeout(()=>sugerir(row),300)}});
document.addEventListener("click",e=>{const x=e.target.closest?.(".pdv-usar");if(!x)return;const row=x.closest(".sim-volume-row");if(row)escolher(row,x.dataset.usar)});
document.addEventListener("focusin",e=>{if(e.target.closest?.("#providerDirectVolumes")){vigiar();todas()}});
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",vigiar);else vigiar();
window.addEventListener("load",()=>setTimeout(vigiar,500));
window.elologBuscaTarifas={procurar,aplicar,escolher,todas};
})();
