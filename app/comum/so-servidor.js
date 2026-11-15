/* Elolog — testes reais: nada fica gravado só num aparelho (v146, revisto na v148).
   Com sessão real (servidor), todas as gravações vão ao servidor. As poucas ações que ficam aqui não gravam nada no
   navegador e dizem o que fazer em vez disso (por regra: no servidor nada se apaga, para manter histórico e auditoria).
   Em demonstração tudo funciona como antes. */
(function(){"use strict";
const S=()=>window.ELOLogServidor;
const real=()=>{try{const u=currentUser;if(!u||u.authenticatedBy==="local-demo"||!S()?.ativo?.())return false;
  if(u.role==="prestador")return u.providerCompany?.server===true;if(u.role==="admin")return u.authenticatedBy==="servidor";return u.role==="cliente"}catch(_){return false}};

const APAGAR="No servidor nada se apaga, para manter o histórico e a auditoria. Use «Reembolso» no pagamento ou cancele a encomenda na ficha da operação.";
const PROPOSTAS="As propostas respondem-se a partir do pedido do cliente, em Propostas › Novas simulações: o cliente recebe-as na área dele.";
const LISTA={
  prestador:[["openProviderPaymentDelete",APAGAR],["submitProviderPaymentDelete",APAGAR],["openProviderOrderDeleteDrawer",APAGAR],["submitProviderOrderHistoryDelete",APAGAR],
    ["providerCreateProposal",PROPOSTAS],["submitProviderProposalForm",PROPOSTAS],["submitProviderProposalCorrection",PROPOSTAS],["providerCancelProposal",PROPOSTAS],["deleteProviderSimulation",PROPOSTAS],
    ["saveFieldSupportRequest","Os pedidos de apoio da equipa fazem-se em Clientes e apoio › Apoio ao cliente › Novo pedido: ficam no servidor e a Elolog vê-os."],
    ["toggleAutomationRule","Com o servidor, a automação corre no próprio servidor (lembretes e alertas a cada hora). As regras deste aparelho não se aplicam."]],
  admin:[["adminSavePlatformSettings","As definições da plataforma (nome, domínio, estados) estão fixas durante os testes reais."],["saveAdminSetting","As definições da plataforma estão fixas durante os testes reais."],
    ["adminBlockClient","Para bloquear um cliente use Operações › Clientes: fica no servidor."],
    ["adminBlockEmployee","Cada empresa ativa e desativa os seus funcionários em Equipa › Funcionários. Para parar uma empresa, use «Suspender prestador»."],
    ["adminDeleteProvider","No servidor as empresas não se apagam (histórico e auditoria). Use «Suspender prestador»."],
    ["adminSaveProviderPassword","A palavra-passe é reposta pelo próprio prestador em «Recuperar acesso», com código enviado por email."],
    ["submitAdminSupportTicket","Os pedidos de apoio são criados pelos clientes e prestadores; responda-lhes na lista de Apoio."],["adminCreateTicket","Os pedidos de apoio são criados pelos clientes e prestadores; responda-lhes na lista de Apoio."],
    ["submitAdminSupportEscalation","Para escalar, abra o pedido na lista de Apoio e mude o estado."],
    ["submitAdminCommission","As comissões gerem-se em Tarifários › Comissões, que já gravam no servidor."],
    ["submitLicensedInvoiceUpload","O PDF da fatura certificada fica no programa de faturação. Aqui regista-se a fatura (número, valor e estado)."]],
  cliente:[]};

function aviso(t){if(typeof showPlatformNotice==="function")showPlatformNotice(t,"info");else alert(t)}

function ligar(){Object.entries(LISTA).forEach(([papel,l])=>l.forEach(([nome,msg])=>{const f=window[nome];if(typeof f!=="function"||f.__soServidor)return;
  const n=function(){if(real()&&currentUser?.role===papel){aviso(msg);return}return f.apply(this,arguments)};n.__soServidor=1;Object.keys(f).forEach(k=>{if(k!=="__soServidor")n[k]=f[k]});window[nome]=n}))}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);else ligar();
window.addEventListener("load",()=>setTimeout(ligar,600));
window.elologSoServidor={real,LISTA,ligar};
})();
