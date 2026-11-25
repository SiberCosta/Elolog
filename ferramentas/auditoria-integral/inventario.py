"""Fase 1 — inventário de ecrãs por perfil (modo demonstração, sem servidor): menus, páginas, componentes,
acessibilidade básica, overflow a 390/820/1280 e erros de consola. Escreve inventario.json."""
import asyncio, json, sys
sys.path.insert(0,__import__('os').path.dirname(__file__))
from perfis import entrar
from playwright.async_api import async_playwright
PERFIS=['admin','prestador','cliente','terreno']
MENU="""()=>{document.querySelectorAll('#sidebar [aria-expanded=false]').forEach(b=>{try{b.click()}catch(e){}});
 return [...document.querySelectorAll('#sidebar .menu button, #sidebar nav button, #sidebar button[onclick]')].filter((b,i,a)=>a.indexOf(b)===i)
  .map((b,i)=>({i,txt:b.textContent.replace(/\\s+/g,' ').replace(/[⌄⌃]/g,'').trim().slice(0,50),onclick:b.getAttribute('onclick')||'',grupo:b.closest('.provider-submenu,.client-submenu')?.id||''}))}"""
ESTADO="""()=>{const p=[...document.querySelectorAll('.page.active, section.page.active')].find(x=>x.offsetParent!==null)||document.querySelector('.page.active');
 const vis=e=>!!(e.offsetWidth||e.offsetHeight||e.getClientRects().length);
 const q=s=>p?[...p.querySelectorAll(s)].filter(vis):[];
 const nome=b=>(b.getAttribute('aria-label')||b.textContent||b.title||b.querySelector('img')?.alt||'').trim();
 const semNome=q('button,a[href],[role=button]').filter(b=>!nome(b));
 const semLabel=q('input:not([type=hidden]):not([type=checkbox]):not([type=radio]),select,textarea').filter(i=>!(i.labels&&i.labels.length)&&!i.getAttribute('aria-label')&&!i.getAttribute('aria-labelledby')&&!i.title);
 const peq=q('button,a[href]').filter(b=>{const r=b.getBoundingClientRect();return r.width>0&&(r.height<32||r.width<32)});
 return {id:p?.id||null,titulo:document.getElementById('pageTitle')?.textContent?.trim()||'',
  botoes:q('button').length,links:q('a[href]').length,campos:q('input:not([type=hidden]),select,textarea').length,formularios:q('form').length,tabelas:q('table').length,
  vazios:q('.empty,.empty-state,.sp-vazio,[class*=vazio]').length,
  semNome:semNome.length,semNomeEx:semNome.slice(0,3).map(b=>b.outerHTML.slice(0,90)),semLabel:semLabel.length,semLabelEx:semLabel.slice(0,3).map(i=>i.id||i.name||i.placeholder||i.outerHTML.slice(0,60)),
  imgSemAlt:q('img:not([alt])').length,alvosPequenos:peq.length,
  overflow:document.documentElement.scrollWidth>innerWidth+1}}"""
async def perfil(b,nome,largura):
  pg=await b.new_page(viewport={'width':largura,'height':900});erros=[]
  pg.on('pageerror',lambda e:erros.append(str(e)[:160]))
  pg.on('console',lambda m:m.type=='error' and erros.append('consola: '+m.text[:160]))
  await entrar(pg,nome);await pg.wait_for_timeout(800)
  if largura<900: await pg.evaluate("()=>document.getElementById('sidebar')?.classList.add('open')")
  menu=await pg.evaluate(MENU);linhas=[]
  for m in menu:
    if not m['onclick'] or 'toggle' in m['onclick'] or 'logout' in m['onclick'].lower() or 'sair' in m['onclick'].lower(): continue
    antes=len(erros)
    try:
      await pg.evaluate(f"()=>{{if(innerWidth<900)document.getElementById('sidebar')?.classList.add('open');const b=[...document.querySelectorAll('#sidebar .menu button, #sidebar nav button, #sidebar button[onclick]')].filter((b,i,a)=>a.indexOf(b)===i)[{m['i']}];b?.closest('.provider-submenu,.client-submenu')?.classList.add('open');b?.click()}}")
      await pg.wait_for_timeout(350)
      e=await pg.evaluate(ESTADO)
    except Exception as ex: e={'erro_teste':str(ex)[:120]}
    e.update(menu=m['txt'],grupo=m['grupo'],acao=m['onclick'][:80],erros=erros[antes:][:3]);linhas.append(e)
    # fechar modais/drawers que a página tenha aberto
    await pg.keyboard.press('Escape')
  await pg.close();return {'perfil':nome,'largura':largura,'menu':len(menu),'paginas':linhas,'erros_totais':erros[:20]}
async def main():
  async with async_playwright() as p:
    b=await p.chromium.launch(executable_path='/usr/bin/google-chrome');res=[]
    for n in PERFIS:
      for w in (1280,820,390):
        r=await perfil(b,n,w);res.append(r);print(n,w,'menu',r['menu'],'páginas',len(r['paginas']),'erros',len(r['erros_totais']),flush=True)
    await b.close()
  json.dump(res,open('/home/claude/aud/integral/inventario.json','w'),ensure_ascii=False,indent=1)
asyncio.run(main())
