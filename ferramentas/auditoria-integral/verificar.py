"""Revê cada botão marcado «sem efeito visível»: página aberta de novo, clique, espera 900 ms; compara o ecrã inteiro
(HTML do corpo), escuta janelas de ficheiro, transferências, novas páginas e diálogos."""
import asyncio,json,sys,re,hashlib
sys.path.insert(0,__import__('os').path.dirname(__file__))
from perfis import entrar
from playwright.async_api import async_playwright
async def main():
  pf=sys.argv[1];r=json.load(open(f'/home/claude/aud/integral/acoes_{pf}.json'))
  perm=json.load(open('/home/claude/aud/integral/permissoes.json'))
  okp=set(perm[pf]['abre']) if pf!='admin' else None
  alvo={}
  for x in r:
    if okp is not None and x.get('pagina') not in okp: continue
    k=(x.get('pagina'),x.get('botao'))
    if x.get('resultado','').startswith('funciona'): alvo.pop(k,None); alvo[k]='ok'
    elif x.get('resultado','').startswith('sem') and alvo.get(k)!='ok': alvo[k]='sem'
  casos=[k for k,v in alvo.items() if v=='sem']
  out=[]
  async with async_playwright() as p:
    b=await p.chromium.launch(executable_path='/usr/bin/google-chrome');ctx=await b.new_context(viewport={'width':1280,'height':900});pg=await ctx.new_page()
    ev=[];pg.on('filechooser',lambda f:ev.append('janela de ficheiro'));pg.on('download',lambda d:ev.append('transferência'));ctx.on('page',lambda q:ev.append('nova página'));pg.on('dialog',lambda d:(ev.append('diálogo'),asyncio.ensure_future(d.dismiss())))
    await entrar(pg,pf);await pg.wait_for_timeout(500)
    for pid,txt in casos:
      ev.clear()
      try:
        await pg.evaluate(f"()=>{{const f=window.showAdminPage&&/^admin/.test('{pid}')?showAdminPage:(window.showProviderPage&&/^(provider|prov|terreno)/.test('{pid}')?showProviderPage:showPage);f('{pid}',null)}}");await pg.wait_for_timeout(500)
        h=await pg.evaluate("()=>document.body.innerHTML.length+':'+document.querySelectorAll('*').length+':'+(document.activeElement?.id||'')")
        n=await pg.evaluate("(t)=>{const norm=s=>s.replace(/\\s+/g,' ').replace(/\\d+/g,'#').trim();const alvo=norm(t);const l=[...document.querySelectorAll('.page.active button,.page.active [role=button],.page.active a[href^=\"#\"]')].filter(e=>e.offsetWidth&&norm((e.getAttribute('aria-label')||e.textContent||e.title||'')).slice(0,45)===alvo.slice(0,45));if(!l.length)return 0;l[0].click();return l.length}",txt)
        await pg.wait_for_timeout(900)
        h2=await pg.evaluate("()=>document.body.innerHTML.length+':'+document.querySelectorAll('*').length+':'+(document.activeElement?.id||'')")
        res='não encontrado' if not n else ('funciona ('+', '.join(ev)+')' if ev else ('funciona (ecrã mudou)' if h!=h2 else 'SEM EFEITO'))
      except Exception as e: res='erro de teste '+str(e)[:60]
      out.append({'pagina':pid,'botao':txt,'resultado':res})
      try:
        await pg.keyboard.press('Escape')
        if 'area-cliente.html' not in pg.url: await pg.goto('http://127.0.0.1:8772/app/area-cliente.html');await pg.wait_for_timeout(1200)
      except Exception: pass
    await b.close()
  json.dump(out,open(f'/home/claude/aud/integral/verif_{pf}.json','w'),ensure_ascii=False,indent=1)
  for o in out:
    if not o['resultado'].startswith('funciona'):print(pf,o['pagina'],'|',o['botao'][:40],'|',o['resultado'])
  print(pf,'revistos',len(out),'funcionam',sum(o['resultado'].startswith('funciona') for o in out))
asyncio.run(main())
