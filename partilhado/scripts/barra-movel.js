/* Elolog v2 — barra inferior no telemóvel. Só navegação: cada botão carrega no botão real do menu lateral
   (mesma função, mesmas permissões); se um perfil não tem essa entrada, ela não aparece. «Menu» abre o menu lateral completo. */
(function(){"use strict";
  const PREF={
    cliente:["Início","Nova simulação","Encomendas","Pagamentos"],
    admin:["Centro de comando","Operações","Acompanhamento","Clientes","Pedidos de inscrição"],
    terreno:["Painel","Recolhas","Entregas","Rota","Histórico"],
    prestador:["Painel","Pedidos recebidos","Aprovar pedidos","Quadro de encomendas","Receção e localização","Expedição","Recebimentos","Histórico"]
  };
  const CURTO={"Nova simulação":"Simular","Centro de comando":"Centro","Pedidos recebidos":"Pedidos","Aprovar pedidos":"Aprovar","Quadro de encomendas":"Quadro","Receção e localização":"Receção","Acompanhamento":"Ao vivo","Pedidos de inscrição":"Inscrições","Recebimentos":"Receber"};
  const P={pedidos:'<path d="M4 13h4l2 3h4l2-3h4"/><path d="M5 5h14l1 8v6H4v-6z"/>',aprovar:'<circle cx="12" cy="12" r="8.5"/><path d="m8.5 12.2 2.4 2.4 4.6-4.9"/>',quadro:'<rect x="3.5" y="4.5" width="17" height="15" rx="1.5"/><path d="M9.5 4.5v15M15 4.5v15"/>',rececao:'<path d="M12 4v10m-4-4 4 4 4-4"/><path d="M4 15v4h16v-4"/>',expedicao:'<path d="M3 7h11v9H3zM14 10h4l3 3v3h-7"/><circle cx="7" cy="17.5" r="1.6"/><circle cx="17" cy="17.5" r="1.6"/>',recebimentos:'<rect x="3.5" y="6" width="17" height="12" rx="1.5"/><path d="M3.5 10h17M7 14.5h3"/>',historico:'<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',clientes:'<circle cx="9" cy="9" r="3.2"/><path d="M3.5 19c.6-3 2.8-4.6 5.5-4.6s4.9 1.6 5.5 4.6"/><path d="M15.5 6.2a3 3 0 0 1 0 5.6M17.5 14.8c1.6.6 2.6 2 3 4.2"/>',vivo:'<circle cx="12" cy="12" r="2"/><path d="M7.8 7.8a6 6 0 0 0 0 8.4M16.2 7.8a6 6 0 0 1 0 8.4M5 5a10 10 0 0 0 0 14M19 5a10 10 0 0 1 0 14"/>',operacoes:'<path d="M12 3.5 20 8v8l-8 4.5L4 16V8z"/><path d="M4 8l8 4.5L20 8M12 12.5V20"/>',rota:'<circle cx="6" cy="18" r="2"/><circle cx="18" cy="6" r="2"/><path d="M8 18h7a3 3 0 0 0 0-6H9a3 3 0 0 1 0-6h7"/>'};
  const ICK=t=>{t=t.toLowerCase();return t.startsWith("pedidos")?"pedidos":t.startsWith("aprovar")?"aprovar":t.startsWith("quadro")?"quadro":t.startsWith("rece")&&t.includes("lo")?"rececao":t.startsWith("exped")?"expedicao":t.startsWith("recebimentos")?"recebimentos":t.startsWith("hist")?"historico":t.startsWith("clientes")?"clientes":t.startsWith("acompanhamento")?"vivo":t.startsWith("opera")?"operacoes":t.startsWith("rota")?"rota":""};
  const norm=s=>(s||"").replace(/\s+/g," ").trim();
  const txt=b=>norm([...b.childNodes].filter(n=>n.nodeType===3||(n.nodeType===1&&!n.matches("svg,i,.ic,.badge,.menu-badge,[class*=count],[class*=badge]"))).map(n=>n.textContent).join(" ")).replace(/\s+\d+$/,"");
  const conta=b=>{const m=norm(b.textContent).match(/\s(\d+)$/);return m?m[1]:""};
  let barra=null,alvos=[],chave="",atual=0;

  function modo(){const c=document.body.classList;if(c.contains("modo-cliente"))return"cliente";if(c.contains("modo-admin"))return"admin";if(c.contains("field-operator-mode"))return"terreno";if(c.contains("provider-user-mode"))return"prestador";return""}
  function folhas(){
    const sb=document.getElementById("sidebar");if(!sb)return[];
    const st=document.createElement("style");st.textContent="#sidebar .provider-submenu,#sidebar .client-submenu,#sidebar [class*=submenu]{display:block!important}";document.head.appendChild(st);
    const r=[...sb.querySelectorAll("nav.menu button")].filter(b=>!b.matches(".provider-menu-main,.client-group,.menu-personalizar")&&b.checkVisibility&&b.checkVisibility()).map(b=>({b,t:txt(b)}));
    st.remove();return r;
  }
  function escolher(){
    const m=modo();if(!m)return[];const fs=folhas(),usados=new Set(),out=[];
    for(const p of PREF[m]){if(out.length>=4)break;const f=fs.find(x=>!usados.has(x.b)&&x.t.toLowerCase()===p.toLowerCase())||fs.find(x=>!usados.has(x.b)&&x.t.toLowerCase().startsWith(p.toLowerCase()));if(f&&!out.some(o=>o.t===f.t)){usados.add(f.b);out.push(f)}}
    for(const f of fs){if(out.length>=4)break;if(!usados.has(f.b)&&!out.some(o=>o.t===f.t)){usados.add(f.b);out.push(f)}}
    return out;
  }
  function icone(b,t){const i=b.querySelector("svg,i.ic,.ic");if(i)return i.cloneNode(true);const k=ICK(t);const sp=document.createElement("span");if(k)sp.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true">'+P[k]+"</svg>";return sp}
  function montar(){
    const novo=escolher(),k=modo()+"|"+novo.map(x=>x.t).join("|");
    if(k===chave&&barra&&document.body.contains(barra)){marcar();return}
    chave=k;alvos=novo;atual=0;if(barra)barra.remove();barra=null;
    if(alvos.length<2){document.body.classList.remove("tem-barra-movel");return}
    barra=document.createElement("nav");barra.id="barraMovel";barra.className="barra-movel";barra.setAttribute("aria-label","Navegação principal");
    alvos.forEach((a,i)=>{const bt=document.createElement("button");bt.type="button";bt.dataset.i=i;bt.appendChild(icone(a.b,a.t));const s=document.createElement("span");s.textContent=CURTO[a.t]||a.t;bt.appendChild(s);const n=conta(a.b);if(n&&n!=="0"){const q=document.createElement("b");q.className="bm-n";q.textContent=n;bt.appendChild(q)}bt.setAttribute("aria-label",a.t);barra.appendChild(bt)});
    const mb=document.createElement("button");mb.type="button";mb.className="bm-menu";mb.setAttribute("aria-label","Abrir o menu completo");
    mb.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16"/></svg><span>Menu</span>';barra.appendChild(mb);
    barra.addEventListener("click",e=>{const bt=e.target.closest("button");if(!bt)return;
      if(bt.classList.contains("bm-menu")){if(typeof window.toggleSidebar==="function")window.toggleSidebar();return}
      const a=alvos[+bt.dataset.i];if(a&&a.b){atual=+bt.dataset.i;a.b.click();window.scrollTo(0,0);setTimeout(marcar,60)}});
    document.body.appendChild(barra);document.body.classList.add("tem-barra-movel");marcar();
  }
  function marcar(){
    if(!barra)return;
    const k=alvos.findIndex(a=>a.b.matches(".active,.ativo,[aria-current='page']"));if(k>=0)atual=k;
    barra.querySelectorAll("button[data-i]").forEach(bt=>{const on=+bt.dataset.i===atual;bt.classList.toggle("ativo",on);if(on)bt.setAttribute("aria-current","page");else bt.removeAttribute("aria-current")});
  }
  let espera=0;const agendar=()=>{clearTimeout(espera);espera=setTimeout(montar,250)};
  function iniciar(){
    agendar();
    new MutationObserver(agendar).observe(document.body,{attributes:true,attributeFilter:["class"]});
    const sb=document.getElementById("sidebar");
    if(sb)sb.addEventListener("click",e=>{const b=e.target.closest("nav.menu button");if(!b||b.matches(".provider-menu-main,.client-group,.menu-personalizar"))return;atual=alvos.findIndex(a=>a.b===b);setTimeout(marcar,60)});
    if(sb)new MutationObserver(m=>{if(m.some(x=>x.type==="childList"))agendar();else marcar()}).observe(sb,{subtree:true,childList:true,attributes:true,attributeFilter:["class"]});
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",iniciar);else iniciar();
})();
