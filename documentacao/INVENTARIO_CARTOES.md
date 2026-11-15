# Inventário dos cartões (v148, 15/11/2026; estado atualizado em v150)

Estado em v151: fases 1 e 2 concluídas (prestador, operador de terreno, cliente e site público). 396 «Migrado», 43 «Sem cartão próprio» (estruturas sem cartão, cobertas pelo contentor), 5 «Mantido de propósito» (capas com fotografia, linha temporal do início e «O seu próximo passo» no menu lateral). Faltam administração e janelas comuns: 205 «Por migrar».

Base do redesign global dos cartões. «100%» = todos os componentes desta lista, em toda a plataforma.

- Folha para aprovação: «Inventário dos cartões da Elolog» (Claude Sheets), com o resumo e a lista completa.
- Lista em texto: `documentacao/INVENTARIO_CARTOES.csv` (649 linhas).
- Ferramenta que refaz o inventário: `ferramentas/inventario-cartoes.cjs` (usada também na validação final).

## Números
| Área | Páginas percorridas | Vistos no ecrã | Só no código | Total |
|---|---|---|---|---|
| Área de cliente | 38 | 82 | 37 | 119 |
| Área do prestador | 52 | 132 | 74 | 206 |
| Operador de terreno | 28 | 66 | 0 | 66 |
| Administração Elolog | 41 | 120 | 35 | 155 |
| Site público | 4 | 19 | 34 | 53 |
| Comum (várias áreas) | — | 0 | 50 | 50 |
| **Total** | **163** | **419** | **230** | **649** |

«Só no código»: componentes que só aparecem com dados reais, em janelas (22 painéis laterais e janelas fixas, 28 janelas geradas, 45 registos em painel), em estados (vazio, erro, cancelada) ou noutra largura.

## Método
1. Cada perfil (cliente, prestador administrador, operador de terreno, administração Elolog) em modo de demonstração, 1280 px; todas as páginas da aplicação abertas uma a uma; registado cada elemento com borda ou sombra, fundo e tamanho de cartão.
2. Site público: início, simulador, validar, seguimento e legal.
3. Análise do código para as classes de cartão que não apareceram no ecrã.
4. Classificação automática em 18 tipos, a rever na aprovação.

## Limites conhecidos
- A classificação é por nome de classe: a coluna «Tipo de cartão» deve ser revista.
- «Contentor de página («card»)» são as caixas brancas que envolvem cada página: entram no redesign como base comum.
- Linhas «Secção de página / formulário» incluem blocos que não são cartões; na aprovação marcam-se como «Não é cartão».
