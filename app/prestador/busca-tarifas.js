/* Elolog — motor de busca das regras de cobrança na simulação direta do prestador (v115).
   Ao escrever a «Carga / descrição» de uma linha, procura uma tarifa ATIVA da empresa cujo nome (ou palavra da descrição) coincida
   e preenche a tarifação e o preço unitário com essa regra. É a mesma regra de procura que o motor de preços usa no servidor
   (início de palavra, sem acentos nem maiúsculas: «frigoríficos» encontra «Frigorífico»). Se o prestador mudar o preço à mão, respeita-o. */
(function(){"use strict";
const T=()=>window.elologTarifarios,esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);
const ativas=()=>{try{return typeof providerDirectActiveTariffs==="function"?providerDirectActiveTariffs():[]}catch(_){return[]}};
const metodo=t=>typeof providerDirectMethodFromTariff==="function"?providerDirectMethodFromTariff(t.method):"unit";

/** a tarifa ativa cujo nome (ou palavra) aparece na descrição; em empate, o termo mais longo e a mais recente */
function procurar(desc){if(!T()?.procura)return null;let melhor=null,termo="";
  for(const t of ativas()){if(t.application==="pickup")continue;const p=T().procura(desc,t.name,t.rules?.palavras);if(p&&p.length>termo.length){melhor=t;termo=p}}
  return melhor?{tarifa:melhor,termo}:null}

function dica(row,html){let d=row.querySelector(".pdv-busca");if(!d){d=document.createElement("small");d.className="pdv-busca";d.setAttribute("aria-live","polite");row.querySelector(".pdv-description")?.closest("label")?.appendChild(d)}d.innerHTML=html}

function aplicar(row){const input=row.querySelector(".pdv-description");if(!input)return;const r=procurar(input.value);
  if(!r){if(row.dataset.busca){delete row.dataset.busca;delete row.dataset.tariffId;row.classList.remove("financial-tariff-row");row.removeAttribute("title")}
    dica(row,input.value.trim().length>=3&&ativas().length?"Nenhuma tarifa com este nome: indique a tarifação e o preço.":"");return}
  const t=r.tarifa;if(row.dataset.tariffId===String(t.id)&&row.dataset.busca)return;
  if(row.dataset.manual==="1"&&row.dataset.tariffId&&row.dataset.tariffId!==String(t.id))return dica(row,`Coincide com a tarifa «${esc(t.name)}». <button type="button" class="pdv-usar" data-usar="${esc(t.id)}">Usar esta tarifa</button>`);
  row.dataset.tariffId=t.id;row.dataset.busca="1";delete row.dataset.manual;row.dataset.volumetricFactor=String(t.rules?.volumetricFactor||167);row.classList.add("financial-tariff-row");row.title=`Tarifa: ${t.name}`;
  row.querySelector(".pdv-method").value=metodo(t);row.querySelector(".pdv-unit-price").value=Number(t.value||0);
  dica(row,`Tarifa encontrada pela descrição: <strong>${esc(t.name)}</strong>, ${Number(t.value||0).toLocaleString("pt-PT",{style:"currency",currency:t.currency||"EUR"})} ${esc(String(t.method||"").toLowerCase())}.`);
  if(typeof updateProviderDirectTotals==="function")updateProviderDirectTotals()}

/* sugestões enquanto escreve: os nomes das tarifas ativas */
function sugestoes(){let l=document.getElementById("pdvTarifasNomes");if(!l){l=document.createElement("datalist");l.id="pdvTarifasNomes";document.body.appendChild(l)}
  l.innerHTML=ativas().filter(t=>t.application!=="pickup").map(t=>`<option value="${esc(t.name)}"></option>`).join("")}

let espera;
document.addEventListener("input",e=>{const el=e.target;if(!el.closest?.("#providerDirectVolumes"))return;const row=el.closest(".sim-volume-row");if(!row)return;
  if(el.classList.contains("pdv-unit-price")||el.classList.contains("pdv-method")){if(row.dataset.busca){row.dataset.manual="1";delete row.dataset.busca;dica(row,"Preço alterado à mão nesta linha.")}return}
  if(!el.classList.contains("pdv-description"))return;el.setAttribute("list","pdvTarifasNomes");clearTimeout(espera);espera=setTimeout(()=>aplicar(row),250)});
document.addEventListener("focusin",e=>{if(e.target.classList?.contains("pdv-description")&&e.target.closest("#providerDirectVolumes")){sugestoes();e.target.setAttribute("list","pdvTarifasNomes")}});
document.addEventListener("click",e=>{const x=e.target.closest?.(".pdv-usar");if(!x)return;const row=x.closest(".sim-volume-row");if(!row)return;delete row.dataset.manual;delete row.dataset.tariffId;aplicar(row)});
window.elologBuscaTarifas={procurar,aplicar};
})();
