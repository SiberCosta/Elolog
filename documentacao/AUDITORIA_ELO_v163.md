# Auditoria do ELO (assistente virtual) — 25-11-2026

Âmbito: assistente no site e na aplicação (`partilhado/scripts/assistente*.js`, `partilhado/estilos/assistente.css`) e no WhatsApp
(`servidor/supabase/functions/whatsapp-elo`). Testado com conversas reais em 4 perfis (visitante, cliente, prestador, administração),
em computador e telemóvel, e com testes unitários da lógica do WhatsApp.

## O que está bem
- Segurança: entrada validada (tamanho, caracteres invisíveis, limite de 15 mensagens/min); resposta verificada (só ligações
  para elolog.pt, sem HTML); tudo o que é mostrado passa por `escapeHtml`.
- Privacidade: cartões, IBAN, emails, telefones, NIF e palavras-passe são ocultados antes de guardar; a conversa só fica no
  aparelho 24 h; «apagar conversa» e «terminar conversa» funcionam.
- Regras: não inventa preços, prazos nem datas de navios; não recebe pagamentos; não aprova prestadores; apresenta-se como
  programa automático; passa para uma pessoa (resumo sem dados pessoais).
- WhatsApp: assinatura da Meta validada em tempo constante; limite de 30 mensagens/10 min por número; estado só para o
  telemóvel associado à encomenda.

## Problemas encontrados e corrigidos
| Prioridade | Problema | Correção |
|---|---|---|
| P1 | Os códigos reais (ELO_TRAN-000001) não eram reconhecidos no site/app; o cliente recebia «Confirme o e-mail ou NIF do destinatário» | Reconhece `ELO_<REF>-000000` (também escrito «elo tran 000001») e os antigos `TR-…` |
| P1 | Pesquisa de encomendas pelo email/NIF do destinatário (dados de terceiros), em contradição com a regra 5 | Retirada; «não sei o código» abre a lista das próprias encomendas |
| P2 | Visitante com código recebia «inicie sessão», embora o site tenha seguimento público | Abre o seguimento público do site com o código preenchido (também a partir de outras páginas) |
| P2 | Resposta sobre palavra-passe desatualizada («perfil selecionado», «validação da empresa») | Explica a entrada por email e «Esqueceu-se da palavra-passe?» |
| P2 | Respostas antigas que prometiam «o próximo barco e o valor estimado» e «5 ficheiros de 4 MB» | Alinhadas com as regras (sem prazos, sem limites fixos) |
| P2 | Estado «disponível» não traduzido (site e WhatsApp) | «disponível para levantamento» em PT/EN/FR e no WhatsApp |
| P2 | Acessibilidade: Esc não fechava; botão sem `aria-expanded`; no telemóvel o Tab saía do painel | Esc fecha e devolve o foco; `aria-expanded`/`aria-controls`; Tab fica no painel no telemóvel |
| P3 | Campo com 15 px (zoom no iPhone) | 16 px |
| P3 | 6 atalhos no telemóvel (metade do painel) | Máximo 4; «terminar» e «idioma» escrevem-se |
| P3 | «ELO_SM-…» (simulação) tratado como pedido genérico | Explica que é uma simulação e onde a ver |
| P3 | «Online» no cabeçalho; «Falar com um humano» vs «uma pessoa»; «Lda..»; datas 2026-11-26 | «Assistente automático»; «Falar com uma pessoa»; pontuação e datas dd/mm/aaaa |

## Por publicar
- `whatsapp-elo` com o estado «disponível» corrigido: está no repositório e testado, mas a publicação no Supabase foi
  bloqueada nesta sessão. Publicar com `supabase functions deploy whatsapp-elo --no-verify-jwt`.

## Fica como está (decisão de produto)
- A língua muda sozinha quando a pessoa escreve frases noutra língua e mantém-se até escrever «português».
- No modo de demonstração, «agendar» cria um pedido local; com servidor, o agendamento é sempre feito na encomenda.
