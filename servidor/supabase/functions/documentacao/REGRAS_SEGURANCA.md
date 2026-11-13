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

## Navegador (v120)

- Todas as páginas HTML têm `Content-Security-Policy` (só a Elolog, o Supabase do projeto e os CDN jsDelivr/cdnjs) e `referrer` `strict-origin-when-cross-origin`. Ao acrescentar um serviço externo, acrescentá-lo à política nas 14 páginas, senão o navegador bloqueia-o.
- No front-end só existe a chave pública (anon). A chave `service_role` e as chaves de API ficam apenas nos segredos das Edge Functions. `node ferramentas/auditoria.cjs` falha se encontrar uma página sem CSP ou uma chave `service_role` no código.
- Campos de palavra-passe nova com `autocomplete="new-password"`; nenhuma palavra-passe nem código é guardado no navegador.

## Centro Documental (v123)

- Um documento emitido nunca é alterado nem apagado (gatilhos no servidor): uma correção cria nova versão com o mesmo número e a anterior fica «substituída», sempre consultável.
- Cada documento tem um código de validação aleatório (96 bits). A validação pública passa pela função `validar-documento` (60 pedidos por hora por IP), que chama `servico_validar_documento` com a chave de serviço; o público continua a executar só `validar_empresa`.
- A validação mostra só o que não é confidencial: tipo, número, versão, estado, data, encomenda e empresa emissora. Nunca nomes, moradas, contactos nem valores.
- Quem vê: a empresa emissora (os comprovativos de pagamento só administração, financeiro e operador), o cliente da encomenda e a administração Elolog. Quem emite: guia (administração, operador), receção (+ armazém), comprovativo (administração, financeiro).
- O comprovativo de pagamento é operacional e diz em letra visível que não é recibo nem fatura fiscal.

## Terreno ao vivo e integrações (v127)

- **Posição do motorista**: guarda-se só a última posição de cada serviço em curso (nunca o percurso), só enquanto o motorista partilha, no máximo uma a cada 15 segundos. O cliente vê apenas a SUA entrega e só com sinal de menos de 30 minutos; a partilha termina com o comprovativo ou com «Parar partilha».
- **Comprovativo no terreno**: nunca se altera nem se apaga; o código local (id_local) impede gravações duplicadas quando o telemóvel reenvia sem rede; fotografias limitadas pelo prestador (limite_fotos) e por tamanho; o motorista só regista serviços que lhe estão atribuídos.
- **Webhooks**: só endereços https:// públicos (recusados localhost, IP internos, .local/.internal, outras portas e credenciais no endereço — validado na base de dados e outra vez na função). O segredo vive no cofre (vault), é mostrado uma única vez e assina cada pedido com HMAC-SHA256 (`X-Elolog-Assinatura: t=…,v1=…`). Os eventos levam códigos, estados e datas — nunca nomes, moradas, contactos nem imagens. Sem redirecionamentos; 8 s de limite; até 8 tentativas.
