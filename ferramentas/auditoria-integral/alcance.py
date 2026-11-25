import asyncio,sys,json
sys.path.insert(0,__import__('os').path.dirname(__file__))
from perfis import entrar
from playwright.async_api import async_playwright
async def m():
  async with async_playwright() as p:
    b=await p.chromium.launch(executable_path='/usr/bin/google-chrome');out={}
    for perfil in ['cliente','terreno','prestador','admin']:
      pg=await b.new_page(viewport={'width':1280,'height':900});await entrar(pg,perfil);await pg.wait_for_timeout(500)
      r=await pg.evaluate("""async()=>{const vis=e=>e.offsetParent!==null;const ids=new Set([document.querySelector('.page.active')?.id]);const menus=[];
        const grupos=[...document.querySelectorAll('#sidebar .provider-menu-main,#sidebar [aria-expanded]')].filter(vis);
        for(const g of grupos){try{g.click()}catch(e){}}
        document.querySelectorAll('#sidebar .provider-submenu,#sidebar .client-submenu').forEach(s=>s.classList.add('open'));
        const bts=[...document.querySelectorAll('#sidebar button')].filter(vis).filter(b=>(b.getAttribute('onclick')||'')&&!/toggle|logout|sair/i.test(b.getAttribute('onclick')));
        for(const b of bts){try{b.click()}catch(e){}await new Promise(r=>setTimeout(r,120));const a=document.querySelector('.page.active');if(a&&vis(a)){ids.add(a.id);menus.push([b.textContent.replace(/\\s+/g,' ').replace(/[⌄⌃]/g,'').trim().slice(0,40),a.id])}
          document.querySelectorAll('#sidebar .provider-submenu,#sidebar .client-submenu').forEach(s=>s.classList.add('open'))}
        return {paginas:[...ids].filter(Boolean),menus}}""")
      n=await pg.evaluate("()=>[...document.querySelectorAll(\"*\")].filter(e=>e.children.length==0&&/não está disponível para o seu perfil/.test(e.textContent)).length");out[perfil]=r;print(perfil,len(r["paginas"]),"avisos de bloqueio:",n)
      await pg.close()
    json.dump(out,open('/home/claude/aud/integral/alcance.json','w'),ensure_ascii=False,indent=1);await b.close()
asyncio.run(m())
