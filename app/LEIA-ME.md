# Área de Cliente (`app/`)

Uma só página, `area-cliente.html`, serve os três perfis: cliente, transitária (prestador) e administração Elolog. O perfil decide o que aparece.

## Pastas

| Pasta | O que tem |
|---|---|
| `comum/` | Usado por todos: `servidor-config.js` (**o único ficheiro a editar para ligar ao Supabase**), `servidor-adaptador.js`, `estado.js` (dados locais e demonstração), `permissoes.js`, `navegacao.js`, `operacoes-*.js`, `plataforma.js`, `operacional.js`, `pwa.js`, `login.js`, `registo.js`, `painel-motor.js` (motor dos painéis), `avisos.js`, `notificacoes.js`, `acesso-por-funcao.js`; estilos `base-1…10.css`, `tema.css`, `registo.css`, `painel*.css`; e o corpo da página em `pagina-1…8.js` |
| `cliente/` | Simulação, menu de 5 áreas, passos, apoio e acompanhamento, documentos e pagamentos, painel do cliente, ligação ao servidor; `simulacao.css`, `fluxo.css` |
| `prestador/` | Encomendas, propostas, manifestos, simulação direta, equipa e terreno, financeiro, calendário e mapa marítimo, automação, fila de trabalho, painel do prestador, ligação ao servidor; estilos em `estilos.css` e `fila.css` |
| `administracao/` | Páginas da administração, auditoria de prestador, centro de comando (`painel.js`, `centro.js`), ligação ao servidor; `centro.css` (com a auditoria), `painel.css` |

## Ordem de carregamento

A ordem é a do HTML e das partes `comum/pagina-1…5.js` (onde estão as etiquetas `<script>` da aplicação, no mesmo sítio em que estavam). **Não reordenar**: os scripts são clássicos e partilham o âmbito global.

Ficheiros divididos em partes (`nome-1.js`, `nome-2.js`…) carregam sempre seguidos e pela ordem dos números. Quando um bloco grande foi dividido, a parte 1 passa à seguinte as funções de que ela precisa através de `window.__ELOLOG_INTERNO` (só para isso; não usar noutros sítios).

## Biblioteca do Supabase

Quando liga ao servidor, a aplicação precisa do cliente JavaScript do Supabase em `app/comum/supabase.js` (não vem no projeto). Para o obter, num computador com internet:

```bash
npm pack @supabase/supabase-js@2.45.4
tar -xzf supabase-supabase-js-2.45.4.tgz package/dist/umd/supabase.js
cp package/dist/umd/supabase.js app/comum/supabase.js
```

Licença MIT: guardar também `package/LICENSE` junto. Sem o ficheiro, a aplicação continua em modo local; com o servidor configurado e o ficheiro em falta, o ecrã avisa. Para usar o jsDelivr como alternativa, pôr `usarCdn: true` em `comum/servidor-config.js`.

## Aplicação instalável

`service-worker.js` vai primeiro à rede e guarda uma cópia para usar sem internet (`offline.html` quando nem a cópia existe). A lista de ficheiros guardados à partida está no próprio service worker: ao criar ou dividir ficheiros, acrescentá-los lá e subir a versão da cache.

- `prestador/menu-lateral.js` — menu lateral do prestador (12 áreas, permissões por função). Para mudar uma entrada, edite a lista `AREAS` no topo do ficheiro.
