// Elolog — inventário automático dos cartões (v148). Uso: servir a pasta do projeto (python3 -m http.server 8792) e correr: node ferramentas/inventario-cartoes.cjs → inv.json
// Percorre todas as páginas de cada perfil (demonstração) e o site público e regista os elementos com aspeto de cartão.
const {chromium}=require('playwright');const fs=require('fs');(async()=>{const b=await chromium.launch();const ctx=await b.newContext({viewport:{width:1280,height:900}});
await ctx.route(u=>!/localhost/.test(new URL(u).hostname),r=>r.abort());const p=await ctx.newPage();const B='process.env.BASE||"http://localhost:8792"';const out=[];
const recolher=async(perfil,pagina,titulo)=>p.evaluate(([perfil,pagina,titulo])=>{const raiz=pagina?document.getElementById(pagina):document.body;if(!raiz)return[];const res={};
  const ok=e=>{const s=getComputedStyle(e),r=e.getBoundingClientRect();if(r.width<110||r.height<36||s.display==='none'||s.visibility==='hidden')return false;if(['INPUT','SELECT','TEXTAREA','TABLE','TBODY','THEAD','TR','TD','TH','IMG','SVG','LABEL','A'].includes(e.tagName))return false;
    const borda=parseFloat(s.borderTopWidth)>0&&s.borderTopStyle!=='none'||parseFloat(s.borderLeftWidth)>2,sombra=s.boxShadow!=='none',fundo=s.backgroundColor!=='rgba(0, 0, 0, 0)'&&s.backgroundColor!=='transparent';
    if(e.tagName==='BUTTON'&&!(r.width>=150&&r.height>=56))return false;return(borda||sombra)&&(fundo||sombra)&&parseFloat(s.borderTopLeftRadius)>=0};
  raiz.querySelectorAll('div,article,section,li,button,aside,header,details,form,dl,label').forEach(e=>{if(!ok(e))return;const cls=[...e.classList].filter(c=>!/^(active|open|show|ok|feito|agora|is-|visible|selected)$/.test(c));
    const chave=cls.length?cls.slice(0,2).join('.'):(e.id?'#'+e.id:e.tagName.toLowerCase()+' (sem classe)');const s=getComputedStyle(e);
    res[chave]=res[chave]||{perfil,pagina:pagina||'(global)',titulo,classe:chave,n:0,tag:e.tagName.toLowerCase(),clicavel:false,raio:s.borderTopLeftRadius,sombra:s.boxShadow!=='none',exemplo:''};
    const x=res[chave];x.n++;if(e.tagName==='BUTTON'||e.getAttribute('role')==='button'||e.onclick||e.getAttribute('onclick'))x.clicavel=true;if(!x.exemplo)x.exemplo=(e.innerText||'').replace(/\s+/g,' ').trim().slice(0,70)});
  return Object.values(res)},[perfil,pagina,titulo]);
const paginas=async()=>p.evaluate(()=>[...document.querySelectorAll('section.page,div.page')].filter(s=>s.id).map(s=>[s.id,(s.querySelector('h2,h3')?.textContent||'').trim().slice(0,50)]));
const perfis=[['cliente',{email:'c@x.pt',role:'cliente',name:'Ana Cliente'},'showPage'],
  ['prestador (admin)',{email:'p@x.pt',role:'prestador',name:'Paulo',providerCompany:{id:'demo1',name:'Atlântico Lda'},providerCompanyId:'demo1',providerFunction:'admin',employeeRole:'admin'},'showProviderPage'],
  ['operador de terreno',{email:'t@x.pt',role:'prestador',name:'Rui',providerCompany:{id:'demo1',name:'Atlântico Lda'},providerCompanyId:'demo1',providerFunction:'field_operator',employeeRole:'field_operator'},'showProviderPage'],
  ['administração',{email:'admin@elolog.pt',role:'admin',name:'Admin',authenticatedBy:'local-demo'},'showAdminPage']];
for(const [nome,u,fn] of perfis){await p.goto(B+'/app/area-cliente.html?demo'+(u.role==='admin'?'&acesso=administracao':''));await p.waitForTimeout(1500);
  await p.evaluate(u=>{localStorage.setItem('elolog_local_admin_v1',JSON.stringify({email:'admin@elolog.pt',salt:'',passwordHash:''}));currentUser=u;sessionStorage.setItem('th_user',JSON.stringify(u));try{startApp()}catch(e){}},u);await p.waitForTimeout(2200);
  out.push(...await recolher(nome,null,'Menu lateral e topo'));
  for(const [id,t] of await paginas()){await p.evaluate(([fn,id])=>{try{(window[fn]||window.showPage)(id)}catch(e){try{showPage(id)}catch(_){}}},[fn,id]);await p.waitForTimeout(350);
    const vis=await p.evaluate(id=>document.getElementById(id)?.offsetParent!==null,id);if(!vis)continue;out.push(...await recolher(nome,id,t))}}
for(const s of ['inicio','simulador','validar','seguimento','legal']){await p.goto(B+'/site/'+s+'.html');await p.waitForTimeout(900);out.push(...(await recolher('site público',null,s)).map(x=>({...x,pagina:s})))}
fs.writeFileSync('inv.json',JSON.stringify(out,null,1));console.log(out.length,'registos');await b.close()})();
