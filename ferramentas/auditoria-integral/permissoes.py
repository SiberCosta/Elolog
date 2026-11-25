import asyncio,sys,json
sys.path.insert(0,__import__('os').path.dirname(__file__))
from perfis import entrar
from playwright.async_api import async_playwright
async def m():
  async with async_playwright() as p:
    b=await p.chromium.launch(executable_path='/usr/bin/google-chrome');out={}
    for perfil in ['cliente','terreno','prestador','admin']:
      pg=await b.new_page();await entrar(pg,perfil);await pg.wait_for_timeout(500)
      r=await pg.evaluate("""()=>{const ids=[...document.querySelectorAll('section.page,.page')].map(s=>s.id).filter(Boolean);const res={};
        const fns=['showPage','showProviderPage','showAdminPage'].filter(f=>typeof window[f]==='function');
        for(const id of ids){for(const f of fns){try{document.querySelectorAll('.page').forEach(p=>p.classList.remove('active'));window[f](id,null)}catch(e){}
          const a=document.querySelector('.page.active');if(a&&a.id===id&&a.offsetParent!==null){(res[id]=res[id]||[]).push(f)}}}
        return {total:ids.length,abre:res,visiveisMenu:[...document.querySelectorAll('#sidebar button')].filter(b=>b.offsetParent!==null).length}}""")
      out[perfil]=r;print(perfil,'páginas no DOM',r['total'],'abrem por função',len(r['abre']),'botões de menu visíveis',r['visiveisMenu'])
      await pg.close()
    json.dump(out,open('/home/claude/aud/integral/permissoes.json','w'),ensure_ascii=False,indent=1)
    await b.close()
asyncio.run(m())
