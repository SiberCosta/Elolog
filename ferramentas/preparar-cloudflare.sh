#!/usr/bin/env bash
# Elolog — prepara a pasta «dist» para publicar no Cloudflare Pages (gratuito).
# Só copia o que o site e a aplicação usam: ficam de fora o servidor (SQL e funções), a documentação, as ferramentas e o LEIA-ME.
# No Cloudflare Pages (ligado ao GitHub): Comando de compilação «bash ferramentas/preparar-cloudflare.sh», Pasta de saída «dist».
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf dist && mkdir dist
cp -r app partilhado site admin prestador dist/
cp index.html 404.html favicon.ico robots.txt sitemap.xml dist/
cp ferramentas/cloudflare/_headers ferramentas/cloudflare/_redirects dist/
# nada de ficheiros internos no site publicado
find dist -name '*.md' -delete
echo "Pronto: $(find dist -type f | wc -l) ficheiros em dist/ ($(du -sh dist | cut -f1))."
