# Elolog

**Versão de 26/10/2026 (v63).** Se esta pasta tem este ficheiro, é a versão nova.

Plataforma de intermediação logística: clientes simulam e comparam propostas; transitárias gerem encomendas, equipa e cobranças; a administração Elolog valida e acompanha a rede.

## Onde está cada coisa

```
elolog/
├─ index.html           entrada: abre site/inicio.html
├─ site/                site público
│  ├─ inicio.html       página inicial
│  ├─ simulador.html    simulador de preço
│  ├─ estilos/          CSS do site (inicio-*.css, simulador-*.css)
│  └─ scripts/          JS do site (inicio-*.js, simulador-*.js)
├─ app/                 Área de Cliente (aplicação)
│  ├─ area-cliente.html página da aplicação (cliente, prestador e administração)
│  ├─ prestador.html    porta de entrada do prestador
│  ├─ administracao.html porta de entrada da administração
│  ├─ comum/            o que todos os perfis usam: login, navegação, estado, painel, servidor
│  ├─ cliente/          só do cliente
│  ├─ prestador/        só da transitária (todas as funções)
│  ├─ administracao/    só da administração Elolog
│  └─ service-worker.js, manifest.webmanifest, offline.html (aplicação instalável)
├─ partilhado/          usado pelo site e pela aplicação
│  ├─ estilos/          botões, ícones, efeitos, assistente, camada «profissional»
│  ├─ scripts/          assistente ELO, idioma (PT/EN), botões, efeitos, dados de demonstração
│  ├─ imagens/          logótipos, fotografias, ícones da aplicação
│  └─ fontes/           Work Sans
├─ servidor/supabase/   base de dados (migrations/), funções (functions/), testes/
├─ documentacao/        arquitetura, produção, incidentes, modelos legais, histórico de versões
└─ ferramentas/         compactar.cjs (JS e CSS) e compactar-sql.py (SQL)
```

Cada pasta da aplicação junta o JS e o CSS do mesmo assunto. Os pormenores estão em `app/LEIA-ME.md`, `partilhado/LEIA-ME.md` e `servidor/supabase/LEIA-ME.md`.

## Regras do código

- **Nenhum ficheiro de código passa das 200 linhas** (HTML, CSS, JS e SQL). O código está **compacto**: sem espaços nem linhas em branco a mais (feito com `ferramentas/compactar.cjs`, que usa o esbuild e só muda de linha em sítios seguros; o SQL com `ferramentas/compactar-sql.py`). A primeira linha de cada ficheiro diz para que serve.
- Partes seguidas do mesmo assunto ficam no mesmo ficheiro; só quando passam das 200 linhas há partes numeradas (`base-1.css`, `base-2.css`…), carregadas pela ordem dos números.
- O corpo das páginas maiores está em partes que se escrevem no próprio sítio (`app/comum/pagina-1…5.js`, `site/scripts/inicio-pagina-1.js`, `site/scripts/simulador-pagina-1.js`). Para mudar um texto ou um botão da página, procure-o nesses ficheiros.
- Os scripts da aplicação são **clássicos** (âmbito global, `onclick="…"` no HTML): a ordem conta. Não acrescentar `defer`, `async` nem `type="module"`.
- Os endereços de CSS e JS levam `?v=63`: mudar o número a cada versão publicada para os navegadores carregarem os ficheiros novos.

## Servidor (Supabase)

**Esta versão já está ligada ao projeto de teste «Elolog T»** (`https://elkykihzgxxcdqhskoyx.supabase.co`, região da organização «Denivaldo da Costa»). O endereço e a chave pública estão em `app/comum/servidor-config.js`; a chave secreta (`service_role`) nunca vai para os ficheiros da aplicação.

- **Demonstração local**: acrescente `?demo=1` à morada (ex.: `app/area-cliente.html?demo=1`). Fica ativa nesse separador até o fechar (`?demo=0` desliga) e usa as contas de demonstração no navegador, sem tocar no servidor.
- **Voltar ao modo só local**: esvazie `supabaseUrl` e `supabaseAnonKey` em `servidor-config.js`.
- A biblioteca do Supabase é carregada do jsDelivr (versão fixa 2.45.4, `usarCdn: true`). Para não depender de outro site, coloque o ficheiro `supabase.js` em `app/comum/` e mude para `usarCdn: false`.

## v63 (domínio elolog.pt)

- Endereço principal `https://www.elolog.pt` (ficheiro `CNAME`); email de contacto `contacto@elolog.pt`. Passos de DNS, GitHub, Brevo e Supabase em `documentacao/PRODUCAO.md` › «Domínio elolog.pt».

## v62 (simulação com o desenho do site)

- As simulações da aplicação (cliente, «Criar encomenda» do prestador e pedido pela administração) usam o desenho do simulador do site: cada bloco é um cartão com ícone, título, descrição curta e «ETAPA 0n»; o resumo lateral mostra cada valor numa linha própria e o total destacado. Só muda a apresentação: campos e cálculos ficam iguais (`app/comum/simulacao-site.js` + regras «v62» em `app/comum/paineis.css`).

## v61 (equipa Elolog, pedidos por contacto e ELO automático)

- **Equipa Elolog** (Conformidade e segurança › Funcionários e acessos): o administrador cria funcionários do portal com função *Administrador*, *Operador* ou *Apoio*, muda a função, repõe a palavra-passe e desativa (as sessões terminam). No 1.º acesso cada funcionário configura o código de autenticação. Servidor: Edge Function `gerir-equipa` e rpc `equipa_plataforma` (`app/administracao/equipa.js`).
- **Pedido por contacto** (botão no Centro de comando e em Operações e clientes): quando um cliente liga, escreve ou vem ao balcão, a administração faz a simulação em 4 etapas (cliente, rota e carga, prestador, confirmação), escolhe o prestador e pode indicar o preço combinado. O prestador recebe o pedido com a indicação «Registado pela Elolog»; se o cliente não tiver conta, a administração é avisada quando o prestador aceitar (`app/administracao/pedido-contacto.js`, rpc `admin_registar_pedido`, migração `00135`).
- **ELO automático**: atalhos e fluxos por perfil (`partilhado/scripts/assistente-fluxos.js`). Administração: pedido por contacto, simulações dos clientes, novo funcionário. Prestador: pedidos de cotação, nova tarifa, registar fatura, navios, pagamentos online. Cliente: nova simulação, pagar encomenda, documentos, pedir cotação. Basta escrever o pedido por palavras próprias (ex.: «o cliente ligou, quero criar uma encomenda»).

## v60 (tarifas, simulações e painel de simulação)

- **Tarifas**: «Guardar tarifa» volta a funcionar e a tarifa fica no servidor (tabela `tarifas`), com nova versão a cada alteração. Passa logo a aparecer nas propostas do simulador do cliente (`app/prestador/tarifas-servidor.js`). «Tipo de carga» passou a ser uma lista.
- **Simulações na administração**: a simulação fica registada no servidor logo que o cliente a efetua (rascunho). O Centro de comando mostra «Simulações dos clientes» com filtros: simuladas, enviadas, cotação e convertidas (`app/administracao/simulacoes.js`, rpc `simulacoes_administracao`).
- **Pedido de cotação**: o cliente pode escolher um prestador sem tarifa para a rota. O prestador recebe «Novo pedido de cotação» e aceita indicando o preço (migração `00134_pedido_cotacao.sql`).
- **Painel de simulação**: resumo lateral mais largo (2 colunas, sem barra de deslocamento) e propostas em linhas largas. As secções empilham até 1500 px e os volumes aparecem em cartões, sem tabela a cortar.
- **Perfil na barra lateral**: avatar com as iniciais certas, nome em até 2 linhas e função, igual em todos os painéis.
- **Simulação com o desenho do site**: cartões brancos por bloco, títulos com ícone e resumo em linhas «rótulo · valor», como em `site/simulador.html`.
- **Botões de submeter**: os formulários voltam a enviar (correção em `partilhado/scripts/componentes.js`).

## v59 (pronto para produção)

Guia passo a passo em `documentacao/PRODUCAO.md`; cópias em `documentacao/COPIAS_DE_SEGURANCA.md`.
- **Emails**: o envio corre sozinho a cada 5 minutos (pg_cron + pg_net). O segredo do agendador é gerado e guardado no cofre da base de dados, nunca em ficheiros. Falta só a conta Brevo (3 segredos).
- **Documentos**: ficheiros no armazenamento privado do Supabase (pasta por empresa ou por cliente, 20 MB, só PDF, imagens, Word e Excel); a empresa vê o que o cliente junta às encomendas dela; descarga por ligação de 2 minutos.
- **Faturas certificadas** (Financeiro › Registar fatura certificada, ou Documentos): carregar o PDF do programa certificado → a plataforma lê o QR da AT → resumo → confirmar. O servidor valida NIF, ATCUD, data, repetição e total; o cliente é avisado. Sem QR legível, cola-se o texto do QR.
- **Pagamentos ifthenpay**: Multibanco (entidade, referência, 3 dias) e MB WAY (pedido na app, 4 minutos, estado atualiza sozinho), em 3 passos com resumo. Chaves de cada empresa só no servidor (Empresa › Pagamentos online, voltam mascaradas); aviso automático com chave anti-phishing; verificação a cada 10 minutos. Sem chaves, fica o registo manual de antes.
- **Navios em tempo real** (Armazém): posição, velocidade, destino e ETA reais por AIS (aisstream.io, gratuito), a cada 30 minutos.
- **Cópias de segurança**: GitHub Actions diário, base de dados + ficheiros, cifrado AES-256, 30 dias.
- Servidor: migrações `00131`–`00133`, funções `pagamentos`, `pagamentos-aviso`, `navios-ais` (e `enviar-emails` atualizada). Testes: SQL `testes/05_producao.sql` (39/39), funções `_testes/producao.test.mts` (23/23), interface `prod` (21/21).

## v58 (área do prestador)

- **Menu lateral** igual ao do cliente e da administração (`app/prestador/menu-lateral.js`); a barra de navegação de cima deixou de aparecer. 12 áreas com submenus recolhíveis (só um aberto), a página atual e o seu grupo realçados e o título da barra igual ao item escolhido:
  Dashboard · Operações (quadro, criar encomenda, simular, atualizar estado, aprovar, programar recolhas, ocorrências, histórico, automação) · Clientes · Propostas (pedidos, criar cotação, enviadas, aceites, recusadas) · Armazém (receção, expedição, manifestos, calendário e mapa marítimo, trânsito, destino, disponível, saídas) · Equipa e transportes (agenda, painel do terreno, motoristas, viaturas, recolhas, entregas) · Financeiro (resumo, preços, faturação, recebimentos, reconciliação) · Documentos · Relatórios · Apoio ao cliente · Funcionários e acessos · Empresa e configurações.
  Cada função só vê o que as suas permissões deixam; o operador de terreno tem um menu próprio e curto. No telemóvel e no tablet o menu abre com ☰ e fecha ao escolher.
- **Dashboard** novo: cabeçalho discreto com «Simular» e «Criar encomenda»; 5 indicadores (operações do mês, encomendas pendentes, em armazém, por receber em €, alertas); 4 painéis: operações pendentes, expedições em curso, encomendas recentes e alertas calculados dos dados (atrasos, aprovações, pedidos sem resposta, pagamentos, ocorrências).
- Testes: os 46 itens do menu abertos no computador e no telemóvel sem erros; todos os botões dos 14 perfis sem erros; nenhuma página com scroll horizontal nem campos sem rótulo.

## v57 (menos caixas)

- **Validação de prestadores** e **Gestão de prestadores**: uma linha por empresa com colunas alinhadas e separadores, sem caixa à volta de cada registo; estado em etiqueta de cor (verde autorizado, âmbar pendente, vermelho suspenso/recusado). Na gestão ficam visíveis «Consultar» e «Mais ações» (as outras 6 ações; «Eliminar» a vermelho no fim).
- **Personalizar o painel**: lista em 3 colunas iguais, caixa de seleção + nome numa linha e setas pequenas lado a lado; blocos escondidos a cinzento.
- **Histórico de encomendas**: indicadores numa só faixa (sem barras de cor), separadores calmos (o escolhido em azul claro), filtros sem moldura e a lista com o cabeçalho dentro do mesmo cartão; lista vazia com ícone.
- Filtros das listas (prestadores, manifestos, clientes, histórico) deixam de ter uma caixa dentro do cartão.
- Menu lateral: quando um grupo está aberto, os itens deslizam e já não tapam «Sair».

## v56 (auditoria de design)

Relatório completo em `documentacao/AUDITORIA_DESIGN.md`. Em resumo:
- **Identidade única** — `partilhado/estilos/identidade.css` (carrega em último lugar) define as cores, a escala de letra (12 · 13 · 14 · 15 · 16 · 18 · 20 · 24 · 28 · 32), o espaço (base 4), os cantos (10 · 14 · 18) e a grelha; as variáveis das folhas antigas apontam para estes tokens. Todos os tamanhos de letra soltos foram encaixados na escala: nenhum texto abaixo de 12px e, por página, de até 20 tamanhos diferentes para no máximo 12.
- **Grelha** — o conteúdo usa a largura do ecrã (até 1640px) com a mesma margem lateral em todos os perfis; as páginas do prestador já não ficam presas a 1180px.
- **Navegação** — só a secção aberta é realçada: no menu lateral, a página atual e o seu grupo (que fica aberto; os outros fecham). Na barra do prestador, a secção certa fica sublinhada mesmo quando a página se abre por um atalho; «Mais» abre com clique (também no Safari e em ecrãs táteis).
- **Componentes** — `partilhado/scripts/componentes.js` (substitui `botoes.js`): todos os campos têm rótulo; as tabelas passam a cartões no telemóvel; linhas com muitas ações mostram só as principais e o resto em «Mais ações»; validação ao sair do campo (email, telefone, obrigatórios) e `eloValidar([...])` para marcar e focar o primeiro campo em falta. A simulação do cliente já usa esta validação.
- **Página inicial** — mostra 3 serviços e «Ver todos os serviços»; o menu Serviços abre o serviço escolhido.
- **Ações reais** — os indicadores do operador de terreno que não faziam nada abrem agora a rota; botão de alerta em contorno; logótipo do rodapé com destino.
- **Ecrãs** — telemóvel: sem sombra do menu fechado na margem, pesquisa da administração numa linha própria, título da barra encurtado, indicadores em 2 colunas, ligações do rodapé com alvo de toque maior; ficheiro de documento já não sai do ecrã no computador.

## v55 (menos ficheiros, 200 linhas)

- Ficheiros de código: de 178 para 134; nenhum passa das 200 linhas.
- Código compacto, sem espaços nem linhas em branco a mais; nomes, lógica e comportamento iguais. As 36 capturas de ecrã de antes e de depois são iguais e cliquei em todos os menus dos 14 perfis sem erros.
- Juntos: estilos base da aplicação (10 → 4), partes da página (8 → 5), dicionário inglês (6 → 1, frases separadas por « ¦ »), simulador do site (4 JS → 1), e os pares de ficheiros do mesmo assunto (estado, login, adaptador do servidor, encomendas, simulação do cliente, painel e servidor da administração, estilos do prestador, painel e tema, registo, rodapé com acabamento…).
- SQL: linhas juntas onde é seguro (nunca a seguir a um comentário nem dentro de texto); só mudaram espaços. O teste 1 voltou a correr no projeto sem falhas.

## v54

- Painéis do prestador e da administração no mesmo estilo do cliente (`app/comum/paineis.css`): cabeçalho «Posto de operação» claro com pontos e brilho verde; atalhos e indicadores do prestador em faixas únicas com linhas a separar (ícones de cor nos atalhos, ponto âmbar ou vermelho nos indicadores que pedem atenção); indicadores da administração numa só faixa com ícones de cor; esferas do fluxo operacional com degradê; cartões com cantos de 18px.

## v53

- «Personalizar painel» passou para o menu da esquerda (cliente e administração); o cabeçalho do painel deixa de ter botão. O prestador, que não tem menu à esquerda, mantém «Opções › Personalizar o painel».
- Painel do cliente com menos caixas: os quatro indicadores numa só faixa com linhas a separar; «Ações rápidas» numa lista simples; a pesquisa de encomendas dentro do «Histórico recente»; «Pagamentos pendentes» só aparece quando há pagamentos por fazer.

## v51 (painel do cliente)

- Painel do cliente redesenhado (`app/cliente/painel.js` + `app/cliente/painel.css`): «Próximo passo» claro com ilustração animada de rotas; indicadores com ícones de cor (azul, âmbar, verde, vermelho), mini-gráfico das encomendas dos últimos 6 meses e barra do que já está pago; encomendas ativas com o percurso Recolha → Armazém → Trânsito → Destino; «Ações rápidas» em mosaico 2×2; cartões com cantos maiores e sombra suave.
- Menu lateral do cliente: cartão com iniciais, página atual destacada, submenus com pontos e «Sair» em cartão.
- Só dados reais da conta: sem encomendas, aparece um estado vazio com «Fazer uma simulação».

## v50

- Idioma: em vez de PT e EN sempre à vista, um só botão (globo + idioma atual + seta) que abre a lista Português / English; fecha ao escolher, ao clicar fora ou com Esc, e funciona com as setas do teclado.

## v49

- Rodapé mais compacto: menos espaço, logótipo e letra mais pequenos, sem a marca-d'água ELOLOG.

## v48

- Capa: retiradas as três caixas de informação (4 passos, 8 etapas, 6 serviços).

## v47 (capa e rodapé)

- Capa da página inicial refeita na linha de sites de transporte como «Norvik» (`site/estilos/inicio-capa.css`): fotografia a toda a altura, menu transparente por cima dela (fica branco ao descer), título curto e enorme em maiúsculas, rótulos em letra de máquina, três caixas de informação com cantos marcados (4 passos, 8 etapas, 6 serviços) e a simulação rápida em vidro escuro.
- Retirada a faixa de serviços em movimento por baixo da capa.
- Rodapé novo e igual nas três páginas (`partilhado/estilos/rodape.css`): marca com e-mail de contacto, três colunas (Plataforma, Para empresas, Apoio), linha de base com «Dados protegidos» e «Voltar ao topo», e o nome ELOLOG em marca-d'água.

## v46 (botões)

- Um só comportamento em todo o site e aplicação: em repouso, contorno azul sobre branco (nada parece carregado); com o rato por cima, a cor enche da esquerda para a direita e a seta avança; com o teclado, igual mais anel de foco. Cantos de 12px, alturas de 44px (aplicação) e 48px (site).
- Seta em ícone nos botões de ação (substitui o «→» escrito), acrescentada por `partilhado/scripts/botoes.js`.
- Botões de sucesso iguais, em verde; secundários com contorno cinzento que ganha o azul.
- Atalhos do painel em linhas de lista com seta, em vez de quatro botões iguais.

## v45

- Avisos redesenhados (`app/comum/avisos.js`): título pelo tipo (Concluído, Atenção, Não foi possível concluir, Informação), ícones em traço, barra de tempo que pára com o rato por cima, sem avisos repetidos; no telemóvel ocupam a largura no topo.
- **Página inicial dinâmica** (`site/scripts/inicio-dinamico.js` + `site/estilos/inicio-dinamico.css`): entrada encenada do topo com a fotografia em zoom lento e profundidade ao rolar, faixa de serviços em movimento que acelera e muda de sentido com o rolar, títulos que se revelam, cartões de serviço em cascata (com o rato por cima: imagem que flutua e «Simular →»; clicar abre o simulador), rota animada no rastreio e barra de progresso da leitura. Fotografia e imagens originais mantidas; tudo desliga com «reduzir movimento».
- Botões (`partilhado/estilos/acabamento.css`, carrega em último): primário e sucesso em cor lisa, «Área de Cliente» com ícone de pessoa e contorno que só enche ao passar o rato, PT | EN com a mesma altura.

## v44

- Entrada da administração: depois do e-mail e da palavra-passe certos, passa sempre ao passo do código de 6 dígitos (registar o QR na 1.ª vez, verificar nas seguintes). Só depois do código é que se confirma se a conta é de administração.

## v43

- Administração: um registo da verificação em dois passos deixado a meio (QR mostrado sem confirmar o código) já não impede o seguinte; a aplicação apaga-o e mostra um QR novo.

## v42 (ligação ao Supabase)

- Projeto «Elolog T» criado e as 18 migrações aplicadas pela ordem (a nova `00121_avisos_seguranca.sql` corrige os avisos do Supabase: vista `empresas_disponiveis` com as permissões de quem consulta, `search_path` fixo em 7 funções internas, tabelas internas sem privilégios para a API).
- Teste 1 (instalação) sem falhas; teste 2 (comportamento) **78 de 78** verificações passaram: isolamento entre empresas, preços calculados no servidor, simulação → encomenda, aprovação e suspensão de empresas, painel da administração, verificação em dois passos, fila de e-mails.
- Publicadas as 3 funções do servidor: `registar-prestador`, `gerir-funcionarios`, `enviar-emails`.
- `?demo=1` passa a ficar ativo no separador, para a demonstração continuar a funcionar com o servidor ligado.

## v41 (reorganização)

- 46 → 26 pastas, agrupadas por área. Nomes sem espaços nem prefixos repetidos (`assets/css/elolog-botoes.css` → `partilhado/estilos/botoes.css`).
- Todos os ficheiros de código com no máximo 250 linhas: 16 ficheiros grandes divididos em partes, o corpo de 3 páginas passado para partes, as migrações SQL divididas por instruções completas (renumeradas `00011_…` a `01111_…`, pela mesma ordem).
- Comportamento igual ao da v40: 36 capturas de ecrã idênticas antes e depois (computador e telemóvel, todos os perfis), sem erros a clicar em todos os menus, idioma EN, modo sem internet e simulação rápida verificados.
- O histórico das versões anteriores está em `documentacao/HISTORICO_VERSOES.md`.
