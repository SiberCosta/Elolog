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
