/* Elolog — guarda das páginas por perfil (v176, auditoria integral).
   Todas as páginas da aplicação estão no mesmo documento; até aqui, chamar showPage('adminSettings') ou
   showProviderPage('providerFinanceiro') a partir de outro perfil (consola, ligação ou botão de outro perfil) mostrava o ecrã.
   Os dados continuam protegidos pelo servidor (regras de acesso da base de dados), mas o ecrã não deve abrir.
   Regras: páginas admin* só para a administração; páginas do prestador (provider*, prov*, terreno*, centro documental,
   integrações) só para prestadores (e para a administração, que as usa no modo suporte); o operador de terreno não abre
   finanças, definições, segurança, funcionários, subscrição, relatórios nem integrações. Bloqueado → volta ao início com aviso. */
(function(){"use strict";
const ADMIN=/^admin/,PREST=/^(provider|prov[A-Z]|terreno|centroDocumental|integracoesPagina)/;
const SO_GESTAO=/^(providerFinanceiro|providerPagamentos|providerSettings|providerSecurity|providerEmployees|providerSubscription|providerReports|integracoesPagina|provAuditoria)$/;
function permitido(id){const u=typeof currentUser!=="undefined"?currentUser:null;if(!u||!id)return true;const r=u.role;
  if(ADMIN.test(id))return r==="admin";
  if(PREST.test(id)){if(r==="admin")return true;if(r!=="prestador")return false;if(u.providerFunction==="field_operator"&&SO_GESTAO.test(id))return false;return true}
  return true}
function recusar(){try{if(typeof showPlatformNotice==="function")showPlatformNotice("Esta área não está disponível para o seu perfil.","warning")}catch(_){}
  const ini=window.__guardaOriginal?.showPage;if(typeof ini==="function")try{ini("dashboard",document.getElementById("menuDashboard"))}catch(_){}}
function envolver(nome){const f=window[nome];if(typeof f!=="function"||f.__guarda)return;
  const g=function(id){if(!permitido(id)){recusar();return}return f.apply(this,arguments)};g.__guarda=1;
  (window.__guardaOriginal=window.__guardaOriginal||{})[nome]=f;window[nome]=g}
function ligar(){["showPage","showProviderPage","showAdminPage"].forEach(envolver)}
ligar();if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",ligar);addEventListener("load",()=>setTimeout(ligar,0));
window.elologGuardaPaginas={permitido};
})();
