/* Elolog — palavras-passe divulgadas (v177, auditoria A-04).
   A proteção do Supabase Auth contra palavras-passe divulgadas só existe no plano pago; até lá, a plataforma verifica no
   aparelho, ao CRIAR ou MUDAR uma palavra-passe (registo de cliente e de prestador, primeiro acesso, recuperação, funcionários),
   se ela aparece em fugas de dados conhecidas (Have I Been Pwned, «k-anonimato»: só seguem os 5 primeiros caracteres do
   SHA-1; a palavra-passe nunca sai do aparelho). Se aparecer, o pedido é recusado com uma explicação. O início de sessão
   não é verificado (não se bloqueia quem já tem conta). Se o serviço não responder em 4 s, não bloqueia. */
(function(){"use strict";
const MSG="Esta palavra-passe já apareceu em fugas de dados na internet e não é segura. Escolha outra (por exemplo, três palavras com um número).";
async function vezes(senha){if(!senha||!crypto?.subtle)return 0;
  const h=[...new Uint8Array(await crypto.subtle.digest("SHA-1",new TextEncoder().encode(senha)))].map(b=>b.toString(16).padStart(2,"0")).join("").toUpperCase();
  const c=new AbortController(),t=setTimeout(()=>c.abort(),4000);
  try{const r=await fetch("https://api.pwnedpasswords.com/range/"+h.slice(0,5),{headers:{"Add-Padding":"true"},signal:c.signal,cache:"no-store"});if(!r.ok)return 0;
    const fim=h.slice(5);for(const l of (await r.text()).split("\n")){const[s,n]=l.trim().split(":");if(s===fim)return Number(n)||0}return 0}
  catch(_){return 0}finally{clearTimeout(t)}}
async function exigir(...senhas){for(const s of senhas){if(typeof s==="string"&&s&&(await vezes(s))>0)throw new Error(MSG)}}
/* campos que levam uma palavra-passe NOVA, por função do servidor (a entrada de funcionários fica de fora: é um login) */
const FUNCOES=new Set(["registar-prestador","criar-prestador","gerir-funcionarios","gerir-equipa","recuperar-acesso"]);
const CAMPO=/^(senha|senhaEmpresa|senha_empresa|senha_pessoal|senha_nova|nova_senha|password)$/;
function recolher(o,l=[]){if(o&&typeof o==="object")for(const[k,v]of Object.entries(o)){if(CAMPO.test(k)&&typeof v==="string")l.push(v);else if(v&&typeof v==="object")recolher(v,l)}return l}
function ligar(){const S=window.ELOLogServidor;if(!S||S.__senhaSegura)return false;S.__senhaSegura=1;
  const rc=S.registarCliente;if(typeof rc==="function")S.registarCliente=async function(d){await exigir(d?.password);return rc.apply(this,arguments)};
  const rp=S.registarPrestador;if(typeof rp==="function")S.registarPrestador=async function(d){await exigir(d?.senhaEmpresa,d?.adminSenha);return rp.apply(this,arguments)};
  const gf=S.gerirFuncionarios;if(typeof gf==="function")S.gerirFuncionarios=async function(acao,dados){await exigir(...recolher(dados));return gf.apply(this,arguments)};
  const cf=S.chamarFuncao;if(typeof cf==="function")S.chamarFuncao=async function(nome,corpo){
    if(FUNCOES.has(nome)&&!(nome==="recuperar-acesso"&&corpo?.acao!=="empresa_confirmar"))await exigir(...recolher(corpo));return cf.apply(this,arguments)};
  return true}
if(!ligar()){const t=setInterval(()=>{if(ligar())clearInterval(t)},200);setTimeout(()=>clearInterval(t),15000)}
window.elologSenhaSegura={exigir,vezes,mensagem:MSG};
})();
