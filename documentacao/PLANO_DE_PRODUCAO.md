# Plano de produção e aceitação

## Implementado nesta entrega

- Correção do login da empresa para Nome + NIF + senha, sem e-mail corporativo.
- Remoção da implementação duplicada de tarifas.
- Esquema PostgreSQL multiempresa para utilizadores, clientes, simulações, propostas, encomendas, tarifas, pagamentos, documentos, manifestos, terreno, suporte, notificações e auditoria.
- API inicial com dois níveis de login, Argon2, JWT, autorização por função e isolamento por empresa.
- Transições críticas de encomenda dentro de transação e com histórico/auditoria.
- PWA instalável e cache do interface operacional.
- Testes unitários das regras críticas do fluxo.
- Modelos iniciais de termos, privacidade e resposta a incidentes.

## Integrações pendentes de fornecedor

| Área | Contratação/configuração necessária | Condição de aceitação |
|---|---|---|
| Pagamentos | PSP com webhooks e reembolsos | Idempotência, assinatura do webhook e reconciliação |
| Faturação | Software certificado para os países de operação | Fatura/nota de crédito com numeração fiscal válida |
| Documentos | Bucket privado S3 compatível | Antivírus, hash, versionamento e URL temporária |
| E-mail/SMS | Fornecedor transacional | Recuperação de conta e avisos com registo de entrega |
| Mapas | Google Maps, Mapbox ou equivalente | Consentimento, custos e limites configurados |
| Alfândega/porto | Serviço aplicável à rota | Validação documental pelas autoridades/consultor |

## Próximos endpoints

Implementar por recurso: simulações, propostas, clientes, documentos, manifestos, pagamentos, tarifas, notificações e suporte. Todos devem exigir `company_id` derivado do token; nunca aceitar a empresa enviada pelo navegador como autorização.

## Migração do protótipo

1. Congelar a estrutura do `localStorage` e exportar JSON.
2. Validar NIF, e-mail, códigos duplicados e estados inválidos.
3. Criar empresas e utilizadores com redefinição obrigatória de senha; não migrar passwords em texto simples.
4. Importar clientes, simulações, propostas e encomendas.
5. Importar documentos para armazenamento privado e guardar SHA-256.
6. Reconciliar pagamentos antes de os marcar como pagos.
7. Executar contagens, amostras e relatório de rejeições.

## Backups e continuidade

- Backup diário cifrado e retenção definida pela política legal.
- Cópia noutro local/região.
- Teste de restauro pelo menos trimestral.
- Objetivos iniciais sugeridos: RPO 24 horas e RTO 8 horas, a rever pelo negócio.
- Registo e alerta de falhas, latência, tentativas inválidas e webhooks rejeitados.
