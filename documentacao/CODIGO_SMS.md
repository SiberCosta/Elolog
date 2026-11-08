# Código de entrada por SMS (v118)

No 3.º passo da entrada, o administrador da empresa escolhe como recebe o código de 6 dígitos:

- **por email:** gratuito e sempre disponível;
- **por SMS:** enviado para o número de telemóvel da sua ficha, só quando o SMS está ativo.

Se o SMS falhar, a página volta à opção do email. A plataforma lembra-se da última escolha neste aparelho. O código vale 10 minutos, só funciona na sessão onde foi pedido e é de uso único, seja qual for o canal.

## Custo

Os SMS são enviados pela Brevo, o mesmo serviço que já envia os emails, e **cada SMS gasta créditos pagos** comprados na Brevo. Em Portugal são alguns cêntimos por SMS (confirmar a tabela atual da Brevo). Enquanto o SMS não estiver ativo, só aparece o email e nada é cobrado.

## Como ativar

1. **Comprar créditos.** Na Brevo, em Transactional › SMS, compre créditos.
2. **Definir o remetente.** No Supabase, em Edge Functions › Secrets, defina `SMS_REMETENTE` com o nome que aparece como remetente, até 11 caracteres (por exemplo, `Elolog`). A `BREVO_API_KEY` já existe.
3. **Registar o telemóvel.** Cada administrador precisa de ter o telemóvel na sua ficha, em Funcionários e acessos › Editar dados. Um número português de 9 dígitos recebe o indicativo +351 automaticamente.

## Segurança

- O número é sempre o da ficha do funcionário. Na entrada não se pode escrever outro número, para evitar o desvio do código.
- O email e o telemóvel aparecem parcialmente escondidos no ecrã de escolha.
- Os pedidos de código têm limite: no máximo 4 em cada 10 minutos por utilizador.
