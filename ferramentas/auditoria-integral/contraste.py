"""Contraste de texto (WCAG 2.1 AA) sem axe-core: para cada elemento com texto visível calcula a cor do texto e o fundo
efetivo (sobe nos pais até achar cor opaca; fundos com imagem/gradiente ficam «indeterminado»). Mínimo 4,5:1; 3:1 em texto grande."""
import asyncio, json, sys
sys.path.insert(0, '/home/claude/aud')
from perfis import entrar
from playwright.async_api import async_playwright
JS = r"""()=>{const rgb=s=>{const m=s.match(/rgba?\(([^)]+)\)/);if(!m)return null;const v=m[1].split(/[ ,\/]+/).filter(Boolean).map(Number);return{r:v[0],g:v[1],b:v[2],a:v[3]===undefined?1:v[3]}};
 const lum=c=>{const f=x=>{x/=255;return x<=0.03928?x/12.92:Math.pow((x+0.055)/1.055,2.4)};return 0.2126*f(c.r)+0.7152*f(c.g)+0.0722*f(c.b)};
 const mix=(a,b)=>({r:a.r*a.a+b.r*(1-a.a),g:a.g*a.a+b.g*(1-a.a),b:a.b*a.a+b.b*(1-a.a),a:1});
 const fundo=e=>{let camadas=[];for(let x=e;x;x=x.parentElement){const cs=getComputedStyle(x);if(/url\(/.test(cs.backgroundImage))return null;let c=rgb(cs.backgroundColor);if((!c||c.a===0)&&/gradient/.test(cs.backgroundImage)){const cs2=[...cs.backgroundImage.matchAll(/rgba?\([^)]+\)/g)].map(m=>rgb(m[0])).filter(Boolean);if(cs2.length){const lums=cs2.map(lum);c=cs2[lums.indexOf(Math.max(...lums))];window.__grad=1}}if(c&&c.a>0){camadas.push(c);if(c.a>=1)break}}
   let f={r:255,g:255,b:255,a:1};for(let i=camadas.length-1;i>=0;i--)f=mix(camadas[i],f);return f};
 const root=document.querySelector('.page.active')||document.body;const out=[];
 root.querySelectorAll('*').forEach(e=>{if(![...e.childNodes].some(n=>n.nodeType===3&&n.textContent.trim().length>1))return;
  const r=e.getBoundingClientRect();if(!r.width||!r.height)return;const cs=getComputedStyle(e);if(cs.visibility==='hidden'||+cs.opacity===0)return;
  if(e.closest('[disabled],[aria-disabled="true"]'))return;
  const c=rgb(cs.color);const f=fundo(e);if(!c||!f||c.a===0)return;const t=c.a<1?mix(c,f):c;const L1=lum(t),L2=lum(f);const ratio=(Math.max(L1,L2)+0.05)/(Math.min(L1,L2)+0.05);
  const px=parseFloat(cs.fontSize),bold=+cs.fontWeight>=700;const grande=px>=24||(bold&&px>=18.66);const min=grande?3:4.5;
  window.__vistos=(window.__vistos||0)+1;if(ratio<min)out.push({txt:e.textContent.replace(/\s+/g,' ').trim().slice(0,40),ratio:Math.round(ratio*100)/100,min,cor:cs.color,fundo:`rgb(${Math.round(f.r)},${Math.round(f.g)},${Math.round(f.b)})`,sel:e.tagName.toLowerCase()+(e.className&&typeof e.className==='string'?'.'+e.className.trim().split(/\s+/).slice(0,2).join('.'):'')})});
 return out}"""
async def main():
    alc = json.load(open('/home/claude/elolog/ferramentas/auditoria-integral/alcance.json'))
    res = {}; vistos = 0
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path='/usr/bin/google-chrome')
        for perfil, d in alc.items():
            ctx = await b.new_context(viewport={'width': 1280, 'height': 900}); pg = await ctx.new_page()
            await entrar(pg, perfil)
            for pag in sorted(set(d['paginas'])):
                try:
                    await pg.evaluate(f"()=>showPage({json.dumps(pag)})"); await pg.wait_for_timeout(500)
                    for f in await pg.evaluate(JS): res.setdefault(f['sel'] + ' | ' + f['cor'] + ' on ' + f['fundo'], []).append((perfil, pag, f['txt'], f['ratio'], f['min']))
                except Exception as e: print('falhou', perfil, pag, str(e)[:80])
            vistos += await pg.evaluate('()=>window.__vistos||0')
            await ctx.close()
        await b.close()
    json.dump(res, open('/home/claude/aud/integral/contraste.json', 'w'), ensure_ascii=False, indent=1)
    print('elementos de texto verificados (aprox.):', vistos)
    print('combinações com contraste insuficiente:', len(res), ' ocorrências:', sum(len(v) for v in res.values()))
    for k, v in sorted(res.items(), key=lambda kv: -len(kv[1]))[:40]: print(len(v), k, '|', v[0])
if __name__=="__main__": asyncio.run(main())
