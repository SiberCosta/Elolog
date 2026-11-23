# Auditoria integral de interface — v159 (23-11-2026)

Base: v158 (a versão reposta no GitHub). Cores, letra, botões em contorno e identidade mantidos.

## Como foi feita

Servidor local + Playwright (Chrome) com os 4 perfis de demonstração (`?demo=1`): cliente, administrador do prestador,
operador de terreno e administração Elolog. Um robô abriu **todas as entradas do menu de cada perfil** (incluindo submenus)
em 3 ecrãs — computador 1280×850, tablet 820×1180 e telemóvel 390×844 — e mediu cada página: largura e transbordo, erros de
JavaScript, contraste (WCAG 2.2 AA), letra abaixo de 12 px, campos sem rótulo, botões sem nome, alvos de toque, títulos,
textos «undefined/NaN», ids repetidos. Cada página foi também revista em captura de ecrã. Páginas públicas medidas à parte.

| Área | Páginas verificadas |
|---|---|
| Cliente | 11 (Início, Nova simulação, Criar encomenda, Encomendas, Encomendas diretas, Pagamentos, Documentos, Centro documental, Apoio, Perfil, Personalizar) |
| Prestador (administrador) | 56 (todas as entradas das 12 áreas do menu) |
| Operador de terreno | 9 |
| Administração Elolog | 24 |
| Público e entrada | 9 (início, simulador, seguimento, validar, legal, 404, entrada cliente/prestador/administração) |

## Resultado (antes → depois, soma dos 3 ecrãs)

| Medida | Antes | Depois |
|---|---|---|
| Textos com contraste abaixo de AA (app, 1280 + 390 px) | 556 | 26 (só no prestador/admin, em pastilhas de estado) |
| Letra abaixo de 12 px | 49 | 16 (folha A4 do centro documental, de propósito) |
| Campos sem rótulo | 4 | 0 |
| Erros de JavaScript | 0 | 0 |
| Páginas mais largas do que o ecrã | 0 | 0 |

## Corrigido

**P1**
- Painel do terreno: os 6 indicadores sobrepunham rótulo, número e nota (botão em linha) → coluna e grelha adaptável.
- Perfil do operador de terreno: nome invisível (tinta escura sobre fundo escuro).
- Operador de terreno via «1 encomenda espera a sua aprovação» sem poder aprovar → o «próximo passo» respeita as permissões
  de cada função; o operador vê os seus serviços.
- Terreno › Ocorrências/Planeamento/Viaturas/Operadores mostravam a descrição da página anterior (ex.: «Valores pendentes…»).
  O operador de terreno deixou de ver «Agendar operação» (não tem essa permissão).
- Cliente › Encomendas diretas tinha o título «Painel» → o título vem do menu quando a página não tem título próprio.
- Prestador › Criar/Simular encomenda: Remetente e Destinatário lado a lado em ~260 px (campos cortados, botões sobrepostos)
  → empilhados até 1500 px.
- Contador de avisos mostrava «0» (o atributo `hidden` era anulado pelo CSS).
- Carregar fotografias/documentos não funcionava pelo teclado (etiqueta com campo escondido) → botão focável (Enter/Espaço).

**P2**
- Contraste: 1 token (`--e-suave`) e ~120 cinzentos soltos escurecidos para `#5c6e7b` (≥ 4,5:1 em branco e no fundo).
- Emojis e glifos usados como ícones (📸 🖼️ ✏️ 🗑️ ☎ ✉ 🚐 ▣ ↓ ＋ ✎ 💶 🏧 📱 🏦 🚢 👥 …) → ícones de traço do sistema (`ic-*`), ~90 sítios.
- Letra mínima 12 px (etapas da simulação, chat, centro documental, terreno, notas em tabelas).
- «Encomend-as ativas»: quebra de palavra a meio nos indicadores.
- Título de cada página anunciado como cabeçalho de nível 1 (também na administração, onde estava escondido); botão ☰ com nome.
- Foco do teclado visível e igual em toda a plataforma.
- Centro de comando: frase rotativa de 48–52 px → 22–28 px (na escala); indicadores da frase com alvo de 24 px.
- Telemóvel: o assistente flutuante deixou de tapar o fim das páginas; título da barra menos cortado.
- Site público e entrada: textos cinzentos e «Bem-vindo à Elolog» com contraste AA.

## Pendentes resolvidos na v160

- Títulos repetidos (barra + cartão): a repetição sai da vista e continua para leitores de ecrã; etiquetas curtas por cima («ATENDIMENTO») também.
- Cartões dentro de cartões na simulação (cliente, prestador, administração) → secções separadas por uma linha.
- Curva decorativa animada do «Próximo passo» retirada (cliente e prestador); bloco escuro «Serviços de hoje no terreno» → cabeçalho simples; ícones das ações do operador numa só cor.
- «Navios com carga Elolog»: dados de demonstração só Lisboa → São Tomé (sem Praia, Luanda, Maputo, Roterdão); a secção esconde-se quando não há viagens.
- Contraste: pastilhas, simulador, formulário de contacto e etapas → todos ≥ 4,5:1 (fica só o botão desativado da Expedição, que a norma dispensa).
- Alvos de toque ≥ 24 px (WCAG 2.2 AA): indicadores do «Como funciona», frases do centro de comando, ligações, «Novo grupo», telefone do terreno, remover volume, «Voltar ao topo».
- Telemóvel: separadores do Financeiro, filtros do Histórico e de Regras de cobrança passam à linha seguinte; as tabelas já estavam em fichas (os cabeçalhos ficam escondidos para leitores de ecrã).
- Volumes do prestador em fichas até 1500 px (sem tabela de 1020 px a deslizar dentro do formulário).

Medição final (100 páginas × 1280/820/390 px): 0 erros de JavaScript, 0 páginas mais largas do que o ecrã, 0 campos sem rótulo,
0 alvos abaixo de 24 px, letra < 12 px só na folha A4 do centro documental.

## Não testado

Fluxos com o servidor real (Supabase, pagamentos ifthenpay, emails Brevo, SMS), leitores de ecrã reais, Safari/iOS e
Android reais, perfis armazém e financeiro, e as ações dentro de cada página (só a navegação e o desenho foram percorridos).
