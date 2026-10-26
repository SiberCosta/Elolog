# Testes da lógica das Edge Functions

Não precisam de Deno, de rede nem de um projeto Supabase: as dependências (base de dados, serviço de contas) são simuladas.

```bash
cd supabase/functions/_testes
npx tsx fn.test.mts        # registo de prestador e equipa
npx tsx emails.test.mts    # modelos de e-mail, Brevo e função de envio
```

Cobrem validação, limites de pedidos, rollback de contas órfãs, regras do último administrador, funcionário de outra empresa,
PIN do terreno e erros internos sem fuga de detalhes. **Não** testam o SQL (`0006`) nem a ligação real ao Supabase.
