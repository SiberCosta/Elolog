/* Elolog — distância da recolha no simulador do cliente (v116; substitui a versão em linha reta).
   Mede por estrada desde o armazém de cada prestador até à morada de recolha (comum/distancia.js) e guarda os km de cada prestador,
   para o preço de cada um usar a SUA distância. Sem armazéns configurados: mede até à origem do envio, como antes. */
(function(){"use strict";
const D=()=>window.elologDistancia;
const escolhido=()=>{const c=document.querySelector('.sim-provider-proposal[aria-pressed="true"]');return c?(c.dataset.empresaId||c.dataset.provider||""):""};
window.elologRecolha=null;
let pedido=0;
window.atualizarDistanciaRecolhaCliente=async function(){const pickup=document.getElementById("clientSimPickup")?.value==="sim",morada=document.getElementById("clientSimPickupLocation")?.value.trim();
  const input=document.getElementById("clientSimDistance"),status=document.getElementById("clientSimDistanceStatus");
  const dizer=(t,c)=>{if(status){status.textContent=t;status.className="sim-distance-status"+(c?" "+c:"")}},recalcular=()=>{try{calcularSimulacaoCliente()}catch(_){}};
  window.elologRecolha=null;
  if(!pickup){if(input)input.value="0";kmManual(false);dizer("Sem recolha, distância não aplicável.");return recalcular()}
  if(!morada){if(input)input.value="0";dizer("Indique a morada onde vamos buscar a carga.","is-error");return recalcular()}
  const id=++pedido;dizer("A procurar a morada…");
  try{const a=await obterCoordenadas(morada);if(id!==pedido)return;dizer("A medir a distância por estrada…");
    const r=D()?await D().recolha(a):null;if(id!==pedido)return;
    if(r&&r.melhor){const sel=escolhido(),meu=sel&&r.porEmpresa[sel],km=meu?meu.km:r.melhor.km,arm=meu?meu.armazem:r.melhor.armazem;
      window.elologRecolha={lat:a.lat,lon:a.lon,kms:r.kms};kmManual(false);if(input)input.value=String(km);
      dizer(`Cerca de ${km.toLocaleString("pt-PT")} km ${r.metodo==="estrada"?"por estrada":"(aproximado)"} desde ${meu?"o armazém do prestador escolhido":"o armazém mais próximo"} (${arm}).${Object.keys(r.kms).length>1&&!meu?" Cada prestador calcula a partir do seu armazém.":""}`,"is-ready");return recalcular()}
    const ponto=pontoDeRecolha();if(!ponto){dizer("Indique primeiro a origem do envio: sem armazém configurado, a distância é medida até lá.","is-error");return}
    const b=await obterCoordenadas(ponto.local);if(id!==pedido)return;const e=D()?await D().estrada(a,b):{km:calcularDistanciaKm(a,b),metodo:"aproximada"};if(id!==pedido)return;
    window.elologRecolha={lat:a.lat,lon:a.lon,kms:{}};kmManual(false);if(input)input.value=String(e.km);
    dizer(e.km?`Cerca de ${e.km.toLocaleString("pt-PT")} km ${e.metodo==="estrada"?"por estrada":"(aproximado)"} até ${ponto.nome}.`:`A recolha é na própria localidade de ${ponto.nome}.`,"is-ready");recalcular()}
  catch(error){if(id!==pedido)return;kmManual(true);if(input)input.value="";
    dizer(/indispon/i.test(error.message)?"O serviço de mapas não respondeu. Escreva a distância aproximada em km, ou tente outra vez daqui a pouco."
      :"Não encontrámos esta morada. Experimente só a localidade e o código postal, ou escreva a distância aproximada em km.","is-error");recalcular()}};
/* ao escolher outro prestador, a distância passa a ser a do armazém dele */
document.addEventListener("click",e=>{if(!e.target.closest?.(".sim-provider-proposal")||!window.elologRecolha)return;setTimeout(()=>{const r=window.elologRecolha,sel=escolhido(),input=document.getElementById("clientSimDistance");
  if(sel&&r.kms[sel]!=null&&input&&input.value!==String(r.kms[sel])){input.value=String(r.kms[sel]);const s=document.getElementById("clientSimDistanceStatus");if(s)s.textContent=`Cerca de ${r.kms[sel].toLocaleString("pt-PT")} km por estrada desde o armazém do prestador escolhido.`}},0)});
})();
