# Junta linhas de SQL até ~W caracteres sem mudar o significado: nunca junta depois de um comentário «--»,
# nem quando a quebra de linha está dentro de uma string '...' ou de um identificador "...".
# Tira linhas em branco. Uso: python3 ferramentas/compactar-sql.py <ficheiro> [max_linhas]
import sys, math
p = sys.argv[1]; MAXL = int(sys.argv[2]) if len(sys.argv) > 2 else 190
src = open(p, encoding='utf-8').read().split('\n')

def estado_fim(linha, q):
    """devolve (q no fim da linha, tem comentário --)"""
    i = 0
    while i < len(linha):
        c = linha[i]
        if q:
            if c == q:
                if i + 1 < len(linha) and linha[i + 1] == q: i += 2; continue
                q = None
        elif c in ("'", '"'): q = c
        elif linha.startswith('--', i): return q, True
        i += 1
    return q, False

def pack(W):
    out, cur, q, comentario = [], None, None, False
    for l in src:
        if not l.strip() and not q: continue
        if cur is None: cur = l.rstrip()
        elif q is None and not comentario and len(cur) + 1 + len(l.strip()) <= W: cur += ' ' + l.strip()
        else: out.append(cur); cur = l.rstrip()
        q, comentario = estado_fim(l, q)
        if q: comentario = False
    if cur is not None: out.append(cur)
    return out

W = 110
while True:
    o = pack(W)
    if len(o) <= MAXL or W > 4000: break
    W = int(W * 1.15)
open(p, 'w', encoding='utf-8').write('\n'.join(o) + '\n')
print(p, len(src), '→', len(o), 'linhas (largura', W, ')')
