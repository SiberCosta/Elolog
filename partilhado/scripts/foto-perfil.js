/* Elolog v2 — fotografia de perfil no menu lateral para todos os perfis (cliente, prestador, administração).
   Usa o mesmo armazenamento de elologFoto (acesso-por-funcao.js). No prestador mantém o comportamento existente (abre o perfil);
   no cliente e na administração, clicar na fotografia permite escolher ou trocar a imagem. Carregar depois de acesso-por-funcao.js. */
(function(){
  const $=id=>document.getElementById(id);
  function pintar(){
    const F=window.elologFoto,u=typeof currentUser!=="undefined"?currentUser:null,el=$("fieldSidebarAvatar");
    if(!F||!u||!u.email||!el)return;
    if(u.role==="prestador"){F.pintar();return}
    const url=F.get(u.email);
    el.classList.toggle("tem-foto",!!url);el.style.backgroundImage=url?`url('${url}')`:"";
    if(el.dataset.fotoV2)return;
    el.dataset.foto="1";el.dataset.fotoV2="1";el.classList.add("foto-editavel");
    el.setAttribute("role","button");el.setAttribute("tabindex","0");el.removeAttribute("aria-hidden");
    el.setAttribute("aria-label","Fotografia de perfil: adicionar ou alterar");el.title="Adicionar ou alterar a fotografia de perfil";
    const abrir=e=>{e.preventDefault();e.stopPropagation();F.escolher(pintar)};
    el.addEventListener("click",abrir);
    el.addEventListener("keydown",e=>{if(e.key==="Enter"||e.key===" ")abrir(e)});
  }
  const envolver=n=>{const o=window[n];if(typeof o!=="function"||o.__fotoV2)return;const w=function(){const r=o.apply(this,arguments);try{setTimeout(pintar,0)}catch(e){}return r};w.__fotoV2=1;window[n]=w};
  envolver("startApp");envolver("showPage");
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",()=>setTimeout(pintar,300));else setTimeout(pintar,300);
  window.elologFotoPerfil={pintar};
})();
