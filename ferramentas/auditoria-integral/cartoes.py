import asyncio, json, sys
sys.path.insert(0, '/home/claude/aud')
from perfis import entrar
from playwright.async_api import async_playwright
CONTA = r"""()=>{const p=document.querySelector('.page.active');const vis=e=>{const r=e.getBoundingClientRect();return r.width>40&&r.height>30&&getComputedStyle(e).visibility!=='hidden'};
 const cards=[...p.querySelectorAll('.pa-cartao,.pw,.card,.pw-kpi,.ck,.cr-tile,.pa-kpi,.ac-kpi,[class*=kpi]:not(strong):not(small)')].filter(vis);
 const topo=[...p.querySelectorAll('.pw-grelha>*')].filter(vis).map(e=>(e.querySelector('h3,h4,header')?.textContent||e.id||'').trim().slice(0,30));
 return{altura:Math.round(p.scrollHeight),ecras:+(p.scrollHeight/innerHeight).toFixed(1),blocos:topo,n_cartoes:cards.length,botoes:[...p.querySelectorAll('button')].filter(vis).length}}"""
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path='/usr/bin/google-chrome'); R = {}
        for perfil in ['cliente', 'prestador', 'admin', 'terreno']:
            for w in (1280, 390):
                pg = await b.new_page(viewport={'width': w, 'height': 800})
                await entrar(pg, perfil); await pg.wait_for_timeout(1500)
                R[f'{perfil}_{w}'] = await pg.evaluate(CONTA)
                await pg.screenshot(path=f'/home/claude/aud/c_{perfil}_{w}.png', full_page=True)
                await pg.close()
        print(json.dumps(R, ensure_ascii=False, indent=0)); await b.close()
asyncio.run(main())
