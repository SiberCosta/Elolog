# Regra de trabalho da Elolog

Todas as alterações seguem cinco passos, por esta ordem:

**identificar → analisar → alterar → verificar → validar a página completa**

1. **Identificar.** Encontrar a página, o menu, a secção e o componente exatos: o id, a classe e o ficheiro. Nunca assumir que o primeiro cartão parecido é o pedido. Se houver dúvida, perguntar antes de mexer.
2. **Analisar.** Ler o HTML, o CSS e o JavaScript ligados ao elemento e ver quem mais os usa (outras páginas, perfis, servidor). Apresentar o que vai mudar e o que fica igual.
3. **Alterar.** Mudar só o necessário, com seletores próprios do componente. Não apagar funcionalidades, cartões, menus ou regras de negócio sem autorização. Não alterar dados, permissões nem a ligação ao Supabase sem autorização. Migrações de base de dados e alterações destrutivas precisam de autorização expressa.
4. **Verificar.** Correr `node ferramentas/auditoria.cjs` (sintaxe, ficheiros em falta, versões, tamanho dos ficheiros, português do Brasil). Abrir a página no computador (1280 px) e no telemóvel (390 px). Confirmar que não há erros de JavaScript, ids repetidos, textos «undefined», imagens partidas nem páginas mais largas do que o ecrã. Confirmar ainda que os botões fazem o que dizem.
5. **Validar a página completa.** Rever do cabeçalho ao rodapé, com os estados vazio, a carregar e de erro. Comparar com o antes e confirmar que o resto da página e dos perfis continua igual. Correr os testes da base de dados quando o servidor muda (`servidor/supabase/testes`).

## O relatório de cada alteração diz

- a página alterada;
- os componentes e os ficheiros modificados;
- o que ficou preservado;
- os testes feitos;
- os problemas encontrados;
- o que ficou por testar, por exemplo integrações externas ainda não ativas.

Não se declara concluído nada que não tenha sido verificado.
