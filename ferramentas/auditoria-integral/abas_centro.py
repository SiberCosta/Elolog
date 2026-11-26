import asyncio, json, sys
sys.path.insert(0, '/home/claude/aud')
from perfis import entrar
from playwright.async_api import async_playwright
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path='/usr/bin/google-chrome'); R = {}
        for w in (1280, 390):
            pg = await b.new_page(viewport={'width': w, 'height': 800}); erros = []; pg.on('pageerror', lambda e: erros.append(str(e)[:150]))
            await entrar(pg, 'admin'); await pg.wait_for_timeout(1800)
            est = "()=>({abas:[...document.querySelectorAll('#pvAbas [role=tab]')].map(b=>b.textContent.trim()+':'+b.getAttribute('aria-selected')),neg:!document.querySelector('#pvPainel .pv-negocio')?.hidden,sim:!document.getElementById('paSimulacoes')?.hidden,altura:document.querySelector('.page.active').scrollHeight,scroll:document.documentElement.scrollWidth>innerWidth})"
            r = {'inicio': await pg.evaluate(est)}
            await pg.click('#pvAba-simulacoes'); await pg.wait_for_timeout(200); r['clique_sim'] = await pg.evaluate(est)
            await pg.focus('#pvAba-simulacoes'); await pg.keyboard.press('ArrowRight'); await pg.wait_for_timeout(200); r['seta'] = await pg.evaluate(est)
            await pg.click('#pvAba-simulacoes'); await pg.evaluate("()=>document.querySelector('[data-pv-acao=atualizar]')?.click()"); await pg.wait_for_timeout(1500)
            r['apos_atualizar'] = await pg.evaluate(est)
            await pg.click('#pvAba-negocio'); await pg.wait_for_timeout(200)
            el = await pg.query_selector('#pvAbas'); await el.scroll_into_view_if_needed()
            await pg.screenshot(path=f'/home/claude/aud/abas_{w}.png')
            r['erros'] = erros; R[w] = r; await pg.close()
        print(json.dumps(R, ensure_ascii=False, indent=1)); await b.close()
asyncio.run(main())
