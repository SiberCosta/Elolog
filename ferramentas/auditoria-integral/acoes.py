"""Fase 1 — testa cada botão visível de cada ecrã (modo demonstração): clica e verifica se acontece alguma coisa
(alteração no ecrã, janela, navegação, diálogo). Não clica em ações destrutivas nem de saída. Escreve acoes.json."""
import asyncio, json, sys, re
sys.path.insert(0,__import__('os').path.dirname(__file__))
from perfis import entrar
from playwright.async_api import async_playwright
PERIGO=re.compile(r'(?i)apagar|eliminar|remover|suspender|recusar|rejeitar|cancelar encomenda|terminar sess|sair|logout|reset|repor dados|limpar|desativar|bloquear|revogar|pagar|confirmar pagamento|anular')
MENU="""()=>[...document.querySelectorAll('#sidebar .menu button, #sidebar nav button, #sidebar button[onclick]')].filter((b,i,a)=>a.indexOf(b)===i).map((b,i)=>({i,txt:b.textContent.replace(/\\s+/g,' ').replace(/[⌄⌃]/g,'').trim().slice(0,40),on:b.getAttribute('onclick')||''}))"""
ABRIR="""(i)=>{const b=[...document.querySelectorAll('#sidebar .menu button, #sidebar nav button, #sidebar button[onclick]')].filter((b,i,a)=>a.indexOf(b)===i)[i];b?.closest('.provider-submenu,.client-submenu')?.classList.add('open');b?.click()}"""
BOTOES="""()=>{const p=document.querySelector('.page.active');if(!p)return[];const vis=e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(e).visibility!=='hidden'};
 return [...p.querySelectorAll('button,[role=button],a[href^="#"],a[href^="javascript"]')].filter(vis).filter(b=>!b.disabled).map((b,k)=>{b.dataset.audK=k;return{k,txt:(b.getAttribute('aria-label')||b.textContent||b.title||'').replace(/\\s+/g,' ').trim().slice(0,45)}})}"""
OBS="""()=>{window.__mut=0;if(window.__obs)window.__obs.disconnect();window.__obs=new MutationObserver(l=>{window.__mut+=l.length});window.__obs.observe(document.body,{subtree:true,childList:true,attributes:true,characterData:true})}"""
async def correr(b,perfil):
  ctx=await b.new_context(viewport={'width':1280,'height':900});pg=await ctx.new_page();erros=[]
  pg.on('pageerror',lambda e:erros.append(str(e)[:160]));pg.on('dialog',lambda d:asyncio.ensure_future(d.dismiss()))
  await entrar(pg,perfil);await pg.wait_for_timeout(600)
  menu=[m for m in await pg.evaluate(MENU) if m['on'] and 'toggle' not in m['on'] and not PERIGO.search(m['txt']+m['on'])]
  res=[]
  for m in menu:
    try:
      await pg.evaluate(ABRIR,m['i']);await pg.wait_for_timeout(300)
      pid=await pg.evaluate("()=>document.querySelector('.page.active')?.id")
      bts=await pg.evaluate(BOTOES)
    except Exception as e: res.append({'menu':m['txt'],'erro':str(e)[:100]});continue
    for bt in bts[:25]:
      if PERIGO.search(bt['txt']): res.append({'menu':m['txt'],'pagina':pid,'botao':bt['txt'],'resultado':'não testado (ação sensível)'});continue
      try:
        await pg.evaluate(ABRIR,m['i']);await pg.wait_for_timeout(150)
        ok=await pg.evaluate(f"()=>!!document.querySelector('.page.active [data-aud-k=\"{bt['k']}\"]')")
        if not ok:
          await pg.evaluate(BOTOES)
        await pg.evaluate(OBS);await pg.wait_for_timeout(250);base=await pg.evaluate("()=>window.__mut")
        await pg.evaluate(OBS);url=pg.url;antes=len(erros)
        await pg.evaluate(f"()=>{{const e=document.querySelector('.page.active [data-aud-k=\"{bt['k']}\"]');if(!e)throw new Error('sumiu');e.click()}}")
        await pg.wait_for_timeout(250);mut=await pg.evaluate("()=>window.__mut")
        efeito=mut>base+0 or pg.url!=url
        r='funciona (há reação)' if efeito else 'sem efeito visível'
        if len(erros)>antes: r='erro: '+erros[-1]
        res.append({'menu':m['txt'],'pagina':pid,'botao':bt['txt'],'resultado':r,'mut':mut,'base':base})
      except Exception as e: res.append({'menu':m['txt'],'pagina':pid,'botao':bt['txt'],'resultado':'não testado ('+str(e)[:60]+')'})
      try:
        await pg.keyboard.press('Escape')
        if pg.url.split('?')[0].split('#')[0]!='http://127.0.0.1:8772/app/area-cliente.html':
          await pg.goto('http://127.0.0.1:8772/app/area-cliente.html');await pg.wait_for_timeout(1500)
        await pg.evaluate("()=>document.querySelectorAll('.modal.open,.drawer.open,[role=dialog]:not([hidden])').forEach(x=>{const f=x.querySelector('[aria-label^=Fechar],.close,[data-fechar]');f&&f.click()})")
      except Exception: pass
  await ctx.close();return res
async def main():
  perfis=sys.argv[1:] or ['admin','prestador','cliente','terreno']
  async with async_playwright() as p:
    b=await p.chromium.launch(executable_path='/usr/bin/google-chrome')
    for pf in perfis:
      r=await correr(b,pf);json.dump(r,open(f'/home/claude/aud/integral/acoes_{pf}.json','w'),ensure_ascii=False,indent=1)
      from collections import Counter
      print(pf,len(r),Counter(x.get('resultado','erro').split(' (')[0].split(':')[0] for x in r),flush=True)
    await b.close()
asyncio.run(main())
