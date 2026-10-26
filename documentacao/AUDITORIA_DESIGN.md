# Auditoria de design — v56 (25-10-2026)

Como foi feita: um robô (Playwright) entrou com 4 perfis (cliente, administrador do prestador, operador de terreno, administração Elolog), abriu **todas as páginas do menu** em 3 ecrãs — computador 1440×900, tablet 820×1180 e telemóvel 390×844 — e mediu cada página. As páginas públicas (início e simulador) foram medidas da mesma forma. Depois clicou em todos os botões de todos os perfis para garantir que nenhuma ação dá erro.

| Critério | Antes (v55) | Agora (v56) |
|---|---|---|
| Tamanhos de letra diferentes por página | até 20; textos de 6–11px | até 12, todos na escala; mínimo 12px |
| Largura do conteúdo | cliente/admin até 1400–1600px, prestador preso a 1180px | todos até 1640px, margem lateral igual (16–40px) |
| Página atual realçada no menu | cliente: nenhuma nas páginas de submenu; prestador: nenhuma quando a página abre por atalho; grupos abertos pareciam ativos | sempre a página atual + o seu grupo; os outros grupos fecham |
| Campos sem rótulo | 40 (pesquisas, filtros, definições, apoio) | 0 |
| Elementos fora do ecrã | campo de ficheiro dos Documentos (1860px) | 0 |
| Botões sem ação | 3 indicadores do operador de terreno; «Mais» só abria com foco | 0 |
| Validação | só aviso geral na simulação do cliente | campo a vermelho com mensagem, foco no primeiro em falta; email e telefone verificados ao sair do campo |
| Linhas com muitas ações (manifestos: 7 botões) | todas visíveis | principal + «Mais ações» |
| Tabelas no telemóvel | deslizavam na horizontal | cartões com o nome de cada coluna |
| Página inicial | 6 serviços de uma vez | 3 + «Ver todos os serviços» |
| Telemóvel | sombra do menu fechado na margem esquerda; pesquisa da administração esmagada; título a cortar os botões | corrigido |

## Sistema único

- **Tokens** (`partilhado/estilos/identidade.css`): azul `#236186`, azul escuro `#1a4d6c`, verde `#237E5F`, tinta `#0E2433`, texto `#4b5d6b`, fio `#e1e9ef`, fundo `#f3f6f8`; aviso `#b45309`, erro `#c2414b`. Letra Work Sans. Escala 12 · 13 · 14 · 15 · 16 · 18 · 20 · 24 · 28 · 32. Espaço 4 · 8 · 12 · 16 · 24 · 32 · 48. Cantos 10 (campos e botões) · 14 (menus) · 18 (cartões).
- **Componentes** (`partilhado/scripts/componentes.js`): botões (tipo, estado ocupado, onda, seta), rótulos, tabelas-cartão, «Mais ações», secção ativa, validação. Funciona sozinho em qualquer conteúdo novo (observa a página).
- **Regra da casa mantida**: botões em contorno em repouso; o preenchimento só aparece com o rato por cima.

## Fluxos em etapas

- Simulação do cliente: 4 passos visíveis (Rota e carga → Propostas → Criar envio → Pagamento), validação por campo, resumo do registo e do envio antes de confirmar.
- Simulador público: progresso por etapas, aviso com o campo em falta e «Resumo da simulação» antes de pedir propostas.

## Como repetir

Servidor local na pasta do projeto (`python3 -m http.server 8772`) e os scripts de teste com Playwright (perfis de demonstração com `?demo=1`). Medir: largura da página, elementos fora do ecrã, botões sem ação, campos sem rótulo, alvos de toque abaixo de 36px no telemóvel, tamanhos de letra e o realce do menu.
