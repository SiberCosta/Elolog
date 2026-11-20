# Redesign v2 da área interna — relatório (ramo `redesign`, 19-11-2026)

Só apresentação: HTML de páginas, ids, classes, Supabase, permissões, preços, comissões, pagamentos e integrações ficam iguais.
As poucas mudanças em JavaScript são de apresentação e estão listadas abaixo.

## O que mudou

| Área | Ficheiros | O quê |
|---|---|---|
| Base | `partilhado/estilos/v2/tokens.css` | Cores, letra, cantos e estados num só sítio; temas claro, escuro e sistema (`html[data-tema]`). As variáveis antigas apontam para os tokens. |
| Estrutura | `partilhado/estilos/v2/estrutura.css` | Menu lateral liso (sem capa, onda, assinatura nem «aba»), opção ativa com linha à esquerda, barra superior, botão de tema, fotografia de perfil. |
| Componentes | `partilhado/estilos/v2/componentes.css` | Uma família de botões (principal, secundário, sucesso, perigo) para 17 classes antigas; campos, tabelas, etiquetas de estado, cartões, janelas, campo de ficheiro. |
| Limpeza | 41 folhas antigas | ~300 regras e ~36 KB retirados: só declarações que a v2 substitui em todos os elementos onde se aplicavam (análise em 7 perfis, 57 páginas, computador e telemóvel). |
| Cores | 46 folhas | ~2 500 cores fixas e ~980 referências a variáveis antigas ligadas aos tokens conforme a propriedade (fundo, texto, contorno, estado), com a cor antiga como recurso. |
| Tema | `partilhado/scripts/tema.js` | Botão Claro → Escuro → Sistema na barra superior; escolha guardada só no navegador; «claro» por omissão. |
| Fotografia | `partilhado/scripts/foto-perfil.js` | A fotografia de perfil aparece no menu lateral em todos os perfis; no cliente e na administração clicar no avatar permite adicionar ou trocar. Mesmo armazenamento de `elologFoto`. |
| Painel do prestador | `app/prestador/painel.js` | Os alertas não repetem aprovações e pagamentos já listados em «Precisa da sua ação» (só quando essa lista aparece antes). |
| Recebimentos | `app/prestador/financeiro.js`, `estilos.css` | Pagamento por receber passa a âmbar (antes verde). |
| Ícones | 21 ficheiros JS | Emojis da interface trocados pelos ícones da aplicação (`ic-*`); textos e ações iguais. |
| Decoração | `centro.css`, `paineis.css`, `painel-vivo*.css` | Sem curva decorativa no «Próximo passo», sem faixa lateral nos alertas, sem padrão de pontos e gradientes no terreno, título do centro de comando à escala. |
| Aplicação instalável | `app/service-worker.js` | Novos ficheiros na cache; versão da cache subida. |

## Testes executados

Modo de demonstração local (`?demo=1`, sem servidor), clique real em cada entrada visível do menu:

- 630 verificações: 7 perfis (cliente, administrador do prestador, operador, terreno, armazém, financeiro, administração),
  tema claro a 1440 px e 390 px, tema escuro a 1440 px.
- Erros de JavaScript: 0. Páginas mais largas do que o ecrã: 0. Textos «undefined»/«NaN»: 0.
- Contraste de texto (< 2,6:1): 0 no tema claro; 0 no tema escuro depois das correções.
- `node ferramentas/auditoria.cjs`: 0 problemas. Nenhum ficheiro passa das 200 linhas.

## Por testar

- Com o servidor real (Supabase) e contas reais de cada perfil.
- Integrações externas (pagamentos, email, WhatsApp, mapas) — não foram tocadas.
- Atualização da aplicação instalada (service worker) num telemóvel com a versão anterior.
- Cores escritas diretamente no JavaScript (estilos em linha) fora das páginas testadas.

## Voltar atrás

Retirar as três folhas `v2/` e `tema.js`/`foto-perfil.js` do HTML não repõe o aspeto antigo, porque as declarações substituídas
foram apagadas das folhas antigas. Para voltar atrás, usar o `main` (o ramo `redesign` é independente).

## Sistema de design Elolog (v2) — referência

**Princípios.** A página não é um cartão: o ecrã é o cabeçalho (título, frase curta, ação principal à direita, fio por baixo) e o conteúdo.
Superfícies só para o que agrupa trabalho (listas, tabelas, formulários, painéis). Um registo = uma linha, não um cartão.
Cor só com significado (estado, ação principal). Sem sombras nas superfícies; sombra apenas em janelas e no cartão de entrada.

| Elemento | Regra | Onde |
|---|---|---|
| Cor | Marinho `#0E2232` (menu, marca), azul `#1F5F8B` (ação), verde `#1F7A5C` (sucesso), âmbar `#875200` (pendente), vermelho `#A33326` (erro); neutros `--v2-texto*`, `--v2-fio*`, `--v2-sup*` | `tokens.css` |
| Letra | Work Sans (interface), algarismos tabulares em valores; título com serifa só no ecrã de entrada | `tokens.css`, `entrada.css` |
| Escala | Título de página 22 px/600 · secção 16 px/600 · corpo 14 px · etiqueta 12–13 px | `composicao.css` |
| Espaço | Base 4 px; 16 entre campos, 20 após cabeçalho, 28 entre secções | `composicao.css` |
| Cantos | 4 (etiquetas), 6 (botões, campos), 8 (superfícies); 22 só no cartão de entrada | `tokens.css` |
| Botões | Principal (azul), secundário (contorno), sucesso, perigo; altura 38 px | `componentes.css` |
| Separadores | Texto com sublinhado azul na opção ativa, deslizam no telemóvel | `composicao.css` |
| Listas | Uma superfície, linhas separadas por fio, realce ao passar | `composicao.css` |
| Indicadores | Régua única com divisórias (2 colunas no telemóvel) | `composicao.css` |
| Vazio | Linha com ícone, frase e ação, alinhada à esquerda, contorno tracejado | `composicao.css` |
| Estados | Etiqueta tingida: ok, informação, pendente, erro, neutro | `componentes.css` |
| Janelas | Superfície, fio no cabeçalho e no rodapé, sombra própria | `componentes.css` |
| Temas | Claro, escuro, sistema (`html[data-tema]`) | `tokens.css`, `tema.js` |
| Assistente ELO | Botão fixo sem animação contínua; painel ancorado com cabeçalho marinho, mensagens em balões com fio, sugestões em linha, ecrã inteiro no telemóvel | `sobreposicoes.css` |
| Notificações | Painel com título, ações em texto, separadores sublinhados, linhas com fio, vazio em linha; no telemóvel a toda a largura | `sobreposicoes.css` |
| Janelas | Fundo escurecido igual em todas; recuperação de palavra-passe com a mesma superfície | `sobreposicoes.css` |
| Navegação no telemóvel | Barra inferior com 4 destinos do perfil + «Menu» (abre o menu lateral). Cliente: Início, Simular, Encomendas, Pagamentos · Administração do prestador/operador: Painel, Pedidos, Aprovar, Quadro · Terreno: Painel, Recolhas, Entregas, Rota · Armazém: Painel, Quadro, Receção, Expedição · Financeiro: Painel, Pedidos, Receber, Histórico · Administração Elolog: Centro, Operações, Ao vivo, Clientes. Cada botão carrega no botão real do menu (mesmas permissões) | `scripts/barra-movel.js`, `sobreposicoes.css` |
| Painéis por perfil | Grelha sem buracos (um bloco sozinho numa linha alarga até ao fim); «Encomendas por etapa» passa a régua de colunas com número e nome, a etapa com encomendas marcada por cima; atalhos do terreno com ícone neutro e só o principal a azul | `scripts/grelha-painel.js`, `composicao.css` |
| Formulários longos | Passos numa linha com fio (no telemóvel só a etapa atual com nome); resumo fixo à vista no computador; campos mais próximos; sem caixas dentro de caixas (secções separadas por fio); títulos sempre à esquerda | `composicao.css` §10 |

## Revisão crítica independente (20-11-2026) — corrigido

Cantos das superfícies a 8 px; texto secundário com contraste AA (`--v2-texto-3` #5A6D7E); ícones dos indicadores neutros e sem gráficos vazios;
«Simular outro envio» como coluna separada por fio (sem caixa dentro de caixa); cabeçalho do terreno igual aos outros perfis (sem faixa escura);
botão de tema com ícone sol/lua/ecrã e alvo de 40 px; sino sem «0»; espaço no fim das páginas para o botão do assistente; «Alertas» vazio escondido.
Ficheiros: `v2/revisao.css`, `scripts/detalhes-v2.js`, `scripts/tema.js`, `v2/tokens.css`.

**Pendentes tratados (v173):** terreno — «O seu próximo passo» passa a «Os seus serviços de hoje» (`navegacao-viva.js`) e a página Ocorrências tem descrição própria (`equipa-terreno-1.js`, também Planeamento, Operadores, Viaturas);
centro de comando — frase mais urgente fixa, sem rotação automática (`painel-vivo.js`); datas aaaa-mm-dd mostradas como dd/mm/aaaa e título «Painel» genérico substituído pelo nome da entrada aberta (`scripts/detalhes-v2.js`, só texto visível);
terreno no telemóvel — próximos serviços logo a seguir ao cabeçalho, atalhos e números depois (`revisao.css`).

## Site público e ecrã de entrada (v174)

- **Site público renovado com a identidade v2** (`site/estilos/v2-site.css`, carregado por último nas 5 páginas): cantos 8/6 px, superfícies sem sombra com fio,
  campos e foco iguais à área interna, ações principais (Simular, Rastrear, Enviar mensagem, Área de Cliente, Obter propostas) em botão azul cheio, «Ver todos os serviços» em contorno.
  Páginas, textos, formulários e ligações iguais.
- **Entrada com mais marca** (`entrada.css`): logótipo grande sobre a fotografia, assinatura «Elolog · Intermediação e gestão logística» e selos de confiança na legenda,
  faixa azul→verde (cores do logótipo) no topo do cartão.
