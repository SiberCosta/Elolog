/* Elolog — produção 3/3: pagamentos online pela ifthenpay (Multibanco e MB WAY).
   Cliente: escolher método → confirmar o resumo → referência ou pedido no telemóvel (o estado atualiza sozinho).
   Empresa: Empresa e configurações › Pagamentos online (chaves guardadas só no servidor; voltam mascaradas).
   Sem servidor, ou se a empresa ainda não aceita pagamentos online, fica o registo manual que já existia. */
(function(){
  const P=()=>window.elologProducao;
  const pagamentoLocal=id=>(typeof payments!=="undefined"?payments:[]).find(p=>p.id===id);
  const copiar=(t,b)=>{navigator.clipboard?.writeText(t).then(()=>{b.textContent="Copiado";setTimeout(()=>b.textContent="Copiar",1500)}).catch(()=>{})};

  function pagarOnline(id,original){const p=P(),esc=p.esc,pag=pagamentoLocal(id);if(!pag)return;
    const j=p.janela({eyebrow:"PAGAMENTO "+(pag.id||""),titulo:"Pagar a encomenda",passos:["Método","Confirmar","Pagar"]});let metodo="multibanco",tel="";
    const passo1=()=>{j.passo(0);j.mostrar(`<div class="pm-valor"><span>Encomenda ${esc(pag.operationId||"—")}</span><strong>${p.euros(pag.amount)}</strong></div>
      <fieldset class="pm-metodos"><legend>Como prefere pagar?</legend>
      <label><input type="radio" name="pmMetodo" value="multibanco" ${metodo==="multibanco"?"checked":""}><span><b>Multibanco</b><small>Entidade e referência para pagar no multibanco ou no banco online</small></span></label>
      <label><input type="radio" name="pmMetodo" value="mbway" ${metodo==="mbway"?"checked":""}><span><b>MB WAY</b><small>Recebe o pedido na app MB WAY do telemóvel</small></span></label>
      <label><input type="radio" name="pmMetodo" value="outro"><span><b>Outro método</b><small>Transferência ou numerário, confirmados pela empresa</small></span></label></fieldset>
      <label class="pm-largo" id="pmTelBloco" ${metodo==="mbway"?"":"hidden"}>Telemóvel MB WAY<input id="pmTel" type="tel" inputmode="numeric" maxlength="9" placeholder="9xx xxx xxx" value="${esc(tel)}" required></label>`,
      [{texto:"Cancelar",acao:j.fechar},{texto:"Continuar",principal:true,acao:()=>{metodo=j.corpo.querySelector('input[name="pmMetodo"]:checked').value;
        if(metodo==="outro"){j.fechar();return original(id)}
        if(metodo==="mbway"){tel=document.getElementById("pmTel").value.replace(/\D/g,"");if(!/^9[1236]\d{7}$/.test(tel)){document.getElementById("pmTel").setAttribute("aria-invalid","true");return p.aviso("Indique um telemóvel português com 9 dígitos (começa por 91, 92, 93 ou 96).","warning")}}
        passo2()}}]);
      j.corpo.querySelectorAll('input[name="pmMetodo"]').forEach(r=>r.onchange=()=>{document.getElementById("pmTelBloco").hidden=r.value!=="mbway"||!r.checked})};
    const passo2=()=>{j.passo(1);j.mostrar(`<dl class="pm-resumo"><div><dt>Encomenda</dt><dd>${esc(pag.operationId||"—")}</dd></div><div><dt>Método</dt><dd>${metodo==="mbway"?"MB WAY · "+esc(tel):"Multibanco (referência válida 3 dias)"}</dd></div>
      <div class="pm-total"><dt>Valor</dt><dd>${p.euros(pag.amount)}</dd></div></dl><p class="pm-nota">O valor final é confirmado pelo servidor com base na encomenda. O pagamento é processado pela ifthenpay.</p>`,
      [{texto:"Voltar",acao:passo1},{texto:metodo==="mbway"?"Enviar pedido MB WAY":"Gerar referência",principal:true,acao:pedir}])};
    const pedir=async()=>{try{const r=await window.ELOLogServidor.chamarFuncao("pagamentos",{acao:"pedir",encomenda:pag.operationId,metodo,telemovel:tel});const d=r.pedido;j.passo(2);
        if(d.metodo==="multibanco"){j.mostrar(`<div class="pm-ref"><div><small>Entidade</small><strong>${esc(d.entidade)}</strong><button type="button" class="btn-secondary" data-c="${esc(d.entidade)}">Copiar</button></div>
          <div><small>Referência</small><strong>${esc(String(d.referencia).replace(/(\d{3})(?=\d)/g,"$1 "))}</strong><button type="button" class="btn-secondary" data-c="${esc(d.referencia)}">Copiar</button></div>
          <div><small>Valor</small><strong>${p.euros(d.valor)}</strong></div></div><p class="pm-nota">${d.expira_em?"Pague até "+new Date(d.expira_em).toLocaleDateString("pt-PT")+". ":""}Quando pagar, a confirmação chega sozinha e recebe um email.</p>`,[{texto:"Concluir",principal:true,acao:j.fechar}]);
          j.corpo.querySelectorAll("[data-c]").forEach(b=>b.onclick=()=>copiar(b.dataset.c,b));marcar("Aguardando confirmação","Multibanco",d.referencia);return}
        marcar("Aguardando confirmação","MB WAY",tel);esperar(d.id,Date.now())}catch(e){p.aviso(e.message||"Não foi possível iniciar o pagamento.","error");
        if(/não aceita pagamentos online|não disponível|não encontrada/i.test(e.message||"")){j.fechar();original(id)}}};
    const esperar=(pedido,inicio)=>{const falta=Math.max(0,240-Math.round((Date.now()-inicio)/1000));
      j.mostrar(`<div class="pm-espera" role="status" aria-live="polite"><span class="pm-roda" aria-hidden="true"></span><strong>Confirme o pagamento na app MB WAY</strong><p>Tem ${Math.floor(falta/60)}:${String(falta%60).padStart(2,"0")} para aceitar no telemóvel ${esc(tel)}.</p></div>`,[{texto:"Fechar",acao:j.fechar}]);
      if(!document.getElementById("pmJanela"))return;
      setTimeout(async()=>{if(!document.getElementById("pmJanela"))return;try{const r=await window.ELOLogServidor.chamarFuncao("pagamentos",{acao:"estado",pedido});const e=r.pedido.estado;
        if(e==="pago"){marcar("Pago","MB WAY",tel);return j.mostrar('<div class="pm-sucesso" role="status"><strong>Pagamento recebido</strong><p>Obrigado. O comprovativo fica em Pagamentos e documentos.</p></div>',[{texto:"Concluir",principal:true,acao:j.fechar}])}
        if(e!=="pendente"||falta<=0)return j.mostrar(`<div class="pm-alerta" role="alert"><strong>${e==="recusado"?"O pedido foi recusado na app.":"O pedido expirou."}</strong><p>Pode tentar de novo ou escolher Multibanco.</p></div>`,[{texto:"Fechar",acao:j.fechar},{texto:"Tentar de novo",principal:true,acao:passo1}])}catch(_){}
        esperar(pedido,inicio)},5000)};
    const marcar=(estado,met,ref)=>{pag.status=estado;pag.method=met;pag.reference=ref;if(estado==="Pago")pag.confirmedAt=new Date().toISOString();try{saveAll();renderEverything()}catch(_){}};
    passo1()}

  async function configuracao(){const p=P(),esc=p.esc,j=p.janela({eyebrow:"EMPRESA E CONFIGURAÇÕES",titulo:"Pagamentos online (ifthenpay)"});
    if(!p.online())return j.mostrar('<p>Os pagamentos online precisam do servidor. No modo de demonstração os pagamentos são registados à mão.</p>',[{texto:"Fechar",acao:j.fechar}]);
    const c=await p.sb();let atual={};try{const{data,error}=await c.rpc("ver_config_pagamentos");if(error)throw error;atual=data||{}}catch(e){return j.mostrar(`<p>${esc(e.message||"Sem permissão.")}</p>`,[{texto:"Fechar",acao:j.fechar}])}
    const url=(window.ELOLOG_SERVIDOR?.supabaseUrl||"https://<projeto>.supabase.co")+"/functions/v1/pagamentos-aviso?key=[ANTI_PHISHING_KEY]&orderId=[ORDER_ID]&amount=[AMOUNT]&requestId=[REQUEST_ID]";
    j.mostrar(`<p class="pm-nota">Peça à ifthenpay as chaves de cada método e um endereço de aviso (callback). As chaves ficam só no servidor: aqui aparecem mascaradas e não voltam ao navegador.</p>
      <div class="pm-grelha"><label>Chave Multibanco (MB Key)<input id="pmMbKey" autocomplete="off" placeholder="${esc(atual.multibanco||"por definir")}"></label>
      <label>Chave MB WAY<input id="pmMbwKey" autocomplete="off" placeholder="${esc(atual.mbway||"por definir")}"></label>
      <label class="pm-largo">Chave anti-phishing (mín. 12 caracteres)<input id="pmAnti" type="password" autocomplete="new-password" placeholder="${atual.antiphishing?"guardada · deixe vazio para manter":"por definir"}"></label></div>
      <label class="pm-opcao"><input id="pmSandbox" type="checkbox" ${atual.sandbox!==false?"checked":""}> Modo de testes (sandbox) da ifthenpay</label>
      <label class="pm-opcao"><input id="pmAtivo" type="checkbox" ${atual.ativo?"checked":""}> Aceitar pagamentos online dos clientes</label>
      <label class="pm-largo">Endereço de aviso a dar à ifthenpay<input readonly value="${esc(url)}" onclick="this.select()"></label>`,
      [{texto:"Fechar",acao:j.fechar},{texto:"Guardar",principal:true,acao:async()=>{const v=id=>document.getElementById(id).value.trim();
        const anti=v("pmAnti");if(anti&&anti.length<12){document.getElementById("pmAnti").setAttribute("aria-invalid","true");return p.aviso("A chave anti-phishing deve ter pelo menos 12 caracteres.","warning")}
        const{error}=await c.rpc("guardar_config_pagamentos",{p_mb_key:v("pmMbKey"),p_mbway_key:v("pmMbwKey"),p_antiphishing:anti,p_ativo:document.getElementById("pmAtivo").checked,p_sandbox:document.getElementById("pmSandbox").checked});
        if(error)return p.aviso(error.message,"error");p.aviso("Configuração de pagamentos guardada.","success");j.fechar()}}])}
  window.elologPagamentos={config:configuracao};

  function ligar(){const original=window.pay;if(typeof original!=="function")return;
    window.pay=function(id){if(!P()?.online()||currentUser?.role!=="cliente")return original(id);return pagarOnline(id,original)}}
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);else ligar();
})();
