"""Fase 1b — repete os pares ecrã/botão que ficaram por testar: procura o botão pelo texto depois de abrir o ecrã
(os painéis vivos redesenham-se e perdiam a marca) e, nas ações sensíveis, verifica que aparece uma confirmação e cancela-a.
Modo demonstração: os dados vivem só no navegador; nada chega ao servidor."""
import asyncio, json, re, sys
sys.path.insert(0, '/home/claude/aud')
from perfis import entrar
from playwright.async_api import async_playwright
SENS = re.compile(r'(?i)apagar|eliminar|remover|suspender|recusar|rejeitar|limpar|bloquear|anular|pagar|confirmar pagamentos')
ACHAR = """([pag,txt])=>{const n=s=>(s||'').replace(/\\s+/g,' ').trim().slice(0,45);const p=document.querySelector('.page.active');if(!p)return'sem página';
 const vis=e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(e).visibility!=='hidden'};
 const l=[...p.querySelectorAll('button,[role=button],a[href^="#"],a[href^="javascript"]')].filter(vis).filter(b=>n(b.getAttribute('aria-label')||b.textContent||b.title)===txt);
 if(!l.length)return'não encontrado';document.querySelectorAll('[data-aud-alvo]').forEach(e=>e.removeAttribute('data-aud-alvo'));l[0].dataset.audAlvo='1';
 return l[0].disabled?'desativado':'ok'}"""
OBS = """()=>{window.__mut=0;window.__obs?.disconnect();window.__obs=new MutationObserver(l=>{window.__mut+=l.length});window.__obs.observe(document.body,{subtree:true,childList:true,attributes:true,characterData:true})}"""
MODAL = """()=>[...document.querySelectorAll('[role=dialog],[role=alertdialog],.modal.open,.platform-confirm,.modal-overlay.open,#pmJanela')].filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0}).map(e=>(e.innerText||'').replace(/\\s+/g,' ').slice(0,90))"""
FECHAR = """()=>{const d=[...document.querySelectorAll('[role=dialog],[role=alertdialog],.modal.open,.platform-confirm,#pmJanela')];for(const m of d){const b=[...m.querySelectorAll('button')].find(b=>/cancelar|fechar|voltar|não|×/i.test(b.textContent+b.getAttribute('aria-label')));if(b){b.click();}}
 document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))}"""
async def main():
    fonte = {}
    for perfil in ['cliente', 'terreno', 'prestador', 'admin']:
        for r in json.load(open(f'/home/claude/aud/integral/acoes_{perfil}.json')):
            if r.get('resultado', '').startswith('não testado'):
                fonte.setdefault(perfil, {})[(r['pagina'], r['botao'])] = r['resultado']
    out = []
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path='/usr/bin/google-chrome')
        for perfil, itens in fonte.items():
            ctx = await b.new_context(viewport={'width': 1280, 'height': 900}); pg = await ctx.new_page(); erros = []; dialogos = []
            pg.on('pageerror', lambda e: erros.append(str(e)[:160]))
            pg.on('dialog', lambda d: (dialogos.append(d.message[:80]), asyncio.ensure_future(d.dismiss())))
            await entrar(pg, perfil)
            for (pag, txt), antes in itens.items():
                try:
                    await pg.evaluate(FECHAR); await pg.evaluate(f"()=>showPage({json.dumps(pag)})"); await pg.wait_for_timeout(500)
                    est = await pg.evaluate(ACHAR, [pag, txt])
                    if est != 'ok': out.append(dict(perfil=perfil, pagina=pag, botao=txt, resultado=est)); continue
                    await pg.evaluate(OBS); n0 = len(erros); d0 = len(dialogos); url = pg.url
                    await pg.click('[data-aud-alvo="1"]', timeout=3000); await pg.wait_for_timeout(500)
                    mut = await pg.evaluate('()=>window.__mut'); modal = await pg.evaluate(MODAL); dl = dialogos[d0:]
                    ativa = await pg.evaluate("()=>document.querySelector('.page.active')?.id")
                    if len(erros) > n0: res = 'ERRO: ' + erros[-1]
                    elif SENS.search(txt): res = 'pede confirmação' if (modal or dl) else ('abre ecrã/painel' if mut else 'SEM CONFIRMAÇÃO')
                    else: res = 'funciona' if (mut or modal or dl or pg.url != url or ativa != pag) else 'sem efeito visível'
                    out.append(dict(perfil=perfil, pagina=pag, botao=txt, resultado=res, janela=(modal or dl or [''])[0][:70], ecra=ativa))
                except Exception as e:
                    out.append(dict(perfil=perfil, pagina=pag, botao=txt, resultado='falhou: ' + str(e)[:80]))
            await ctx.close()
        await b.close()
    json.dump(out, open('/home/claude/aud/integral/pendentes.json', 'w'), ensure_ascii=False, indent=1)
    from collections import Counter
    print(len(out), Counter(o['resultado'].split(':')[0] for o in out))
    for o in out:
        if o['resultado'] not in ('funciona', 'pede confirmação'): print(o)
asyncio.run(main())
