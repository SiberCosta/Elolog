"""Escreve no HTML o corpo das páginas públicas que antes era escrito por JavaScript (document.write).
Assim o Google, o Bing, o DuckDuckGo e as pré-visualizações das redes sociais leem o texto sem precisar de correr JavaScript.
Linhas juntas até ~900 caracteres para cada ficheiro HTML continuar curto. Uso: python3 ferramentas/site/pre-render.py"""
import re, subprocess, json, pathlib, sys
RAIZ = pathlib.Path(__file__).resolve().parents[2]
BLOCO = re.compile(r'(</(?:p|section|li|h[1-6]|div|nav|header|footer|ul|ol|form|label|article|aside|table|tr)>)')
def compactar(s, quebrar):
    if quebrar: s = BLOCO.sub(r'\1\n', s)
    linhas = [l.strip() for l in s.split('\n') if l.strip()]
    out, cur = [], ''
    for l in linhas:
        if cur and len(cur) + len(l) > 900: out.append(cur); cur = l
        else: cur = (cur + ' ' + l) if cur else l
    if cur: out.append(cur)
    return '\n'.join(out)
def correr(js, fim):
    prog = r'''const fs=require("fs");const src=fs.readFileSync(process.argv[1],"utf8");const fim=process.argv[2];const i=fim?src.indexOf(fim)+fim.length:src.length;
let out="";new Function("document",src.slice(0,i))({write:s=>{out+=s}});process.stdout.write(JSON.stringify({html:out,resto:src.slice(i)}))'''
    return json.loads(subprocess.check_output(['node', '-e', prog, str(js), fim or '']))
for pag, fim, quebrar in [('inicio', None, False), ('simulador', None, False), ('legal', '].join(""));', True)]:
    js = RAIZ / f'site/scripts/{pag}-pagina-1.js'; html = RAIZ / f'site/{pag}.html'
    if not js.exists(): print('já feito:', pag); continue
    r = correr(js, fim); t = html.read_text()
    tag = re.search(r'(<!--[^>]*pagina-1\.js -->\s*)?<script src="scripts/' + pag + r'-pagina-1\.js\?v=\d+"></script>', t)
    if not tag: sys.exit('etiqueta não encontrada em ' + pag)
    novo = '<!-- corpo da página em HTML (antes era escrito por JavaScript; ver ferramentas/site/pre-render.py) -->\n' + compactar(r['html'], quebrar)
    resto = r['resto'].strip()
    if resto:
        extra = RAIZ / f'site/scripts/{pag}-navegacao.js'; extra.write_text(resto + '\n')
        v = re.search(r'\?v=(\d+)', tag.group(0)).group(1); novo += f'\n<script src="scripts/{pag}-navegacao.js?v={v}"></script>'
    html.write_text(t[:tag.start()] + novo + t[tag.end():]); js.unlink()
    print(pag, 'linhas:', len(html.read_text().splitlines()))
