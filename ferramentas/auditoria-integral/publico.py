import asyncio,json,urllib.parse
from playwright.async_api import async_playwright
B="http://127.0.0.1:8772/"
PAGS=["site/inicio.html","site/simulador.html","site/legal.html","site/seguimento.html","site/validar.html","index.html","404.html","app/area-cliente.html"]
async def main():
  async with async_playwright() as p:
    b=await p.chromium.launch(executable_path='/usr/bin/google-chrome');res=[];links=set()
    for w in (1280,820,390):
      for u in PAGS:
        pg=await b.new_page(viewport={'width':w,'height':900});er=[];pg.on('pageerror',lambda e:er.append(str(e)[:150]));pg.on('console',lambda m:m.type=='error' and er.append('consola '+m.text[:150]))
        r=await pg.goto(B+u);await pg.wait_for_timeout(1500)
        d=await pg.evaluate("""()=>{const vis=e=>!!(e.offsetWidth||e.offsetHeight);const nome=b=>(b.getAttribute('aria-label')||b.textContent||b.title||'').trim();
          return {titulo:document.title,h1:[...document.querySelectorAll('h1')].filter(vis).length,desc:!!document.querySelector('meta[name=description]'),canon:document.querySelector('link[rel=canonical]')?.href||'',
          robots:document.querySelector('meta[name=robots]')?.content||'',lang:document.documentElement.lang,
          ov:document.documentElement.scrollWidth>innerWidth+1,semNome:[...document.querySelectorAll('button,a[href]')].filter(vis).filter(b=>!nome(b)).length,
          imgSemAlt:[...document.querySelectorAll('img:not([alt])')].length,semLabel:[...document.querySelectorAll('input:not([type=hidden]),select,textarea')].filter(vis).filter(i=>!(i.labels&&i.labels.length)&&!i.getAttribute('aria-label')&&!i.title).length,
          links:[...document.querySelectorAll('a[href]')].map(a=>a.href)}}""")
        for l in d.pop('links'):
          if l.startswith(B):links.add(l.split('#')[0])
        d.update(url=u,w=w,status=r.status if r else None,erros=er[:3]);res.append(d);await pg.close()
    # links internos
    partidos=[]
    pg=await b.new_page()
    for l in sorted(links):
      try:
        r=await pg.request.get(l)
        if r.status>=400:partidos.append((l,r.status))
      except Exception as e:partidos.append((l,str(e)[:60]))
    await b.close()
  json.dump({'paginas':res,'links':sorted(links),'partidos':partidos},open('/home/claude/aud/integral/publico.json','w'),ensure_ascii=False,indent=1)
  for d in res:
    if d['w']==1280 or d['ov'] or d['erros']:print(d['w'],d['url'],'| h1',d['h1'],'| ov',d['ov'],'| semNome',d['semNome'],'| semLabel',d['semLabel'],'| imgSemAlt',d['imgSemAlt'],'| robots',d['robots'],'| erros',d['erros'])
  print('links internos',len(links),'partidos',partidos)
asyncio.run(main())
