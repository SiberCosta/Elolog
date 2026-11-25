"""Auditoria do ecrã «Site público» (administração): menu, 4 abas, ações e formulários, com servidor simulado (nada chega à base real)."""
import asyncio, json, sys
sys.path.insert(0, '/home/claude/aud')
from perfis import entrar
from playwright.async_api import async_playwright
MOCK = r"""()=>{const hoje=new Date(),d=n=>new Date(hoje.getTime()+n*864e5).toISOString().slice(0,10);
 const DB={site_definicoes:[{chave:'saidas',valor:{mostrar:true,max:6}},{chave:'feed',valor:{faixa:true}}],
  viagens_maritimas:[{id:'v1',navio:'Monte Cara',viagem:'54',porto_origem:'Lisboa',porto_destino:'São Tomé',partida:d(5),fecho_carga:d(2),estado:'aberta',publicada:true,empresa_id:'e1'},{id:'v2',navio:'Atlântico Sul',porto_origem:'Leixões',porto_destino:'Praia',partida:d(12),estado:'planeada',publicada:false,empresa_id:'e2'}],
  empresas:[{id:'e1',nome:'Transatlântico, Lda',cidade:'Lisboa'},{id:'e2',nome:'Mar Azul',cidade:'Porto'}],
  site_publicacoes:[{id:'p1',tipo:'novidade',titulo:'Estamos a melhorar a sua experiência.',ativo:true,cor:'verde',fundo:'#1F7A5C',publico:'site'},{id:'p2',tipo:'aviso',titulo:'Porto fechado',texto:'Greve até sexta',ativo:true,cor:'vermelho',publico:'ambos',para:'clientes',inicio:d(0),fim:d(3)}]};
 window.__ops=[];const q=t=>{const o={_t:t,_op:'select',_v:null,_f:[]};const p=new Proxy(o,{get(x,k){if(k==='then'){const r={data:x._op==='select'?DB[t]||[]:null,error:null};window.__ops.push([t,x._op,x._v,x._f]);return f=>Promise.resolve(r).then(f)}
   if(['insert','update','upsert','delete'].includes(k))return v=>{x._op=k;x._v=v;return p};if(['eq','gte','order','limit','select','in','maybeSingle'].includes(k))return(...a)=>{if(k==='eq')x._f.push(a);return p};return x[k]}});return p};
 const cli={from:q,rpc:async n=>({data:{saidas:[1],prestadores:[1,2],feed:[1],avisos:[1]},error:null})};
 window.ELOLogServidor=Object.assign(window.ELOLogServidor||{},{ativo:()=>true,cliente:async()=>cli,mensagem:e=>e.message});}"""
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path='/usr/bin/google-chrome'); R = {}
        for w in (390,):
            pg = await b.new_page(viewport={'width': w, 'height': 900}); erros = []; dl = []
            pg.on('pageerror', lambda e: erros.append(str(e)[:150])); pg.on('dialog', lambda d: (dl.append(d.message), asyncio.ensure_future(d.accept())))
            await entrar(pg, 'admin'); await pg.wait_for_timeout(1200); await pg.evaluate(MOCK)
            r = {}
            await pg.evaluate("()=>elologSitePublico.abrir('saidas')"); await pg.wait_for_timeout(500)
            for k in ['saidas', 'prestadores', 'novidades', 'auto']:
                await pg.evaluate(f"()=>document.querySelector('#adminSiteContent [data-aba={k}]').click()"); await pg.wait_for_timeout(300)
                r[k] = await pg.evaluate("""()=>{const c=document.getElementById('adminSiteContent'),m=[...document.querySelectorAll('#adminGrpSite button')].filter(b=>b.classList.contains('active')||b.getAttribute('aria-current')==='page').map(b=>b.textContent.trim());
                  const sem=[...c.querySelectorAll('input:not([type=hidden]),select,textarea')].filter(i=>!(i.labels&&i.labels.length)&&!i.getAttribute('aria-label')).map(i=>i.id||i.className||i.type);
                  const fora=[...c.querySelectorAll('*')].filter(e=>e.getBoundingClientRect().right>innerWidth+1).length;
                  return{menu_marcado:m,sem_rotulo:sem.slice(0,8),n_sem_rotulo:sem.length,fora_do_ecra:fora,scroll:document.documentElement.scrollWidth>innerWidth}}""")
                await pg.screenshot(path=f'/home/claude/aud/sp_{k}_{w}.png', full_page=False)
            # ações
            await pg.evaluate("()=>document.querySelector('#adminSiteContent [data-aba=saidas]').click()"); await pg.wait_for_timeout(200)
            await pg.evaluate("()=>window.__ops=[]")
            await pg.evaluate("()=>{const t=document.querySelector('[data-saida=v1]');t.checked=false;t.dispatchEvent(new Event('change',{bubbles:true}))}"); await pg.wait_for_timeout(300)
            r['acao_ocultar_saida'] = await pg.evaluate("()=>JSON.stringify(window.__ops.filter(o=>o[1]!=='select'))")
            await pg.evaluate("()=>document.querySelector('#adminSiteContent [data-aba=novidades]').click()"); await pg.wait_for_timeout(200)
            await pg.evaluate("()=>window.__ops=[]")
            # publicar com datas trocadas
            await pg.fill('#spTitulo', 'Teste de auditoria'); await pg.fill('#spIni', '2026-12-10'); await pg.fill('#spFim', '2026-12-01')
            await pg.evaluate("()=>document.querySelector('#spForm button[type=submit]').click()"); await pg.wait_for_timeout(300)
            r['publicar_datas_trocadas'] = await pg.evaluate("()=>window.__ops.filter(o=>o[1]==='insert').length")
            r['para_quem_desligado_em_site'] = await pg.evaluate("()=>document.getElementById('spPara').disabled")
            await pg.select_option('#spOnde','ambos'); r['para_quem_ligado_em_ambos'] = await pg.evaluate("()=>!document.getElementById('spPara').disabled")
            # editar p2
            await pg.evaluate("()=>document.querySelector('[data-editar=p2]').click()"); await pg.wait_for_timeout(300)
            r['editar_preenche'] = await pg.evaluate("()=>[document.getElementById('spTitulo').value,document.getElementById('spTipo').value,document.getElementById('spOnde').value,document.getElementById('spPara').value,document.getElementById('spSubmeter').textContent,!document.getElementById('spCancelarEd').hidden]")
            await pg.fill('#spTitulo','Porto fechado até sábado'); await pg.evaluate("()=>window.__ops=[]")
            await pg.evaluate("()=>document.querySelector('#spForm button[type=submit]').click()"); await pg.wait_for_timeout(400)
            r['editar_grava'] = await pg.evaluate("()=>JSON.stringify(window.__ops.filter(o=>o[1]!=='select').map(o=>[o[1],o[2]&&o[2].titulo,o[3]]))")
            r['form_volta_a_publicar'] = await pg.evaluate("()=>document.getElementById('spSubmeter').textContent")
            r['resumo_auto'] = None
            await pg.evaluate("()=>window.__ops=[]")
            await pg.evaluate("()=>document.querySelector('[data-apagar=p1]').click()"); await pg.wait_for_timeout(300)
            r['apagar_pede_confirmacao'] = dl[-1] if dl else None
            r['apagar_operacao'] = await pg.evaluate("()=>JSON.stringify(window.__ops.filter(o=>o[1]!=='select'))")
            await pg.evaluate("()=>document.querySelector('#adminSiteContent [data-aba=auto]').click()"); await pg.wait_for_timeout(200)
            r['resumo_auto'] = await pg.evaluate("()=>document.querySelector('.sp-resumo').innerText")
            r['erros'] = erros; R[w] = r; await pg.close()
        print(json.dumps(R, ensure_ascii=False, indent=1)); await b.close()
asyncio.run(main())
