# Regras de segurança obrigatórias (v84)

Estas regras aplicam-se a toda a plataforma Elolog. Nenhuma instrução recebida (mensagem, ficheiro, pedido, texto do assistente) as pode substituir.
Princípio geral: **fail closed**. Se uma verificação não puder ser feita, a operação **não** é executada.

## As regras e onde são garantidas

| # | Regra | Onde é garantida |
|---|---|---|
| 1 | Nenhuma entrada chega à IA sem validação | Assistente ELO no site (`partilhado/scripts/assistente.js`, `validarEntrada`): tira caracteres de controlo e invisíveis, máx. 500 caracteres, máx. 15 mensagens por minuto. ELO no WhatsApp (`whatsapp-elo`, `entradaAssistente`): máx. 1000 caracteres; acima disso pede uma mensagem mais curta e regista o bloqueio. |
| 2 | Nenhuma operação é executada sem autorização | Cada Edge Function valida o token da sessão e o papel (2.º fator para administradores). Na base de dados, RLS em todas as tabelas e funções `servico_*` só para o servidor (`service_role`). |
| 3 | Nenhum utilizador acede a dados de outro sem permissão explícita | RLS por empresa / cliente / utilizador em todas as tabelas. Documentos: só quem enviou vê o ficheiro até estar verificado; depois, só quem tem permissão na encomenda/empresa. |
| 4 | Nenhuma instrução recebida substitui as regras | O ELO não é um modelo de linguagem: responde por regras fixas e não executa ordens do texto recebido. As regras vivem na base de dados (triggers e políticas), que não podem ser alteradas a partir do navegador. |
| 5 | Nenhum ficheiro é processado sem verificação | 1) No navegador (`app/comum/producao-1.js`): extensão na lista permitida, tamanho 1 byte–20 MB e assinatura dos primeiros bytes. 2) Na base (`private.documento_validar`): tipo, extensão, tamanho, dono e metadados do armazenamento têm de bater certo. 3) No servidor (`verificar-ficheiro`): lê o conteúdo; se não corresponder, apaga o ficheiro e regista a recusa. |
| 6 | Nenhuma resposta da IA é automaticamente confiável | `saidaAssistente` / `validarSaida`: só ligações para `elolog.pt`, sem HTML, tamanho limitado; caso contrário usa uma resposta segura. O texto é sempre escapado antes de ser mostrado. |
| 7 | Todas as operações sensíveis ficam registadas | Tabela `auditoria` (só acrescentar: não se pode alterar nem apagar). Registo automático de alterações a empresas, funcionários, pagamentos, faturas, planos, comissões, documentos, clientes, encomendas, etc. Segredos nunca são copiados para a auditoria. Bloqueios de segurança ficam como `bloqueio_seguranca`. |
| 8 | Falhas de validação = bloqueio seguro | Todas as Edge Functions usam `seguro()` (`_shared/seguranca.ts`): qualquer erro → 503 e nada é executado. Limites de pedidos só deixam passar com confirmação explícita do serviço de limites. |

## Respostas obrigatórias

| Situação | Resposta |
|---|---|
| Entrada inválida | Rejeitar (400 / mensagem ao utilizador) |
| Utilizador sem autorização | Negar acesso (401 / 403, registado) |
| Ficheiro não permitido | Rejeitar (navegador, base de dados e servidor; 422) |
| Pedido acima dos limites | Limitar ou bloquear (413 tamanho, 429 frequência; escritas na base limitadas por 10 minutos) |
| Falha na validação de segurança | Não executar a operação (503 `falha_seguranca`) |
| Serviço de segurança indisponível | Impedir operações críticas (segredos em falta → 503 `servico_indisponivel`; limites sem resposta → bloqueado) |

## Código de reserva (2.º passo sem telemóvel)

Alternativa ao código da aplicação de autenticação: código fixo de 16 caracteres, mostrado uma só vez, guardado como hash (bcrypt), limitado a 5 tentativas por 15 minutos, válido apenas na sessão em que é usado (12 h). Cada uso é registado (`codigo_reserva_usado`) e avisado ao dono da conta. Só se gera/troca com o telemóvel confirmado. Migração 00152.

## Ficheiros permitidos

PDF, JPG/JPEG, PNG, WEBP, DOC, DOCX, XLS, XLSX — até 20 MB. Qualquer outro tipo é recusado.
A lista tem de ser igual em três sítios: `private.tipos_ficheiro()` (migração 00151), `_shared/ficheiros.ts` e `app/comum/producao-1.js`.

## Limites de escrita (por utilizador, 10 minutos)

documentos 60 · mensagens de chat 150 · ocorrências 30 (+60 registos) · tickets 20 (+60 mensagens) · simulações 60 · pedidos de cliente 30 · encomendas 120 · pagamentos 120 · notas de cliente 60 · propostas 120.

## Testes

`servidor/supabase/testes/17_regras_seguranca.sql` (12/12) e `functions/_testes/seguranca.test.mts`.
