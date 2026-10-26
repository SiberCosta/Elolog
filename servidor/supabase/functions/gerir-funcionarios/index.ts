// Edge Function: gestão de funcionários da empresa (criar, atualizar, repor palavra-passe, eliminar).
// Deploy: supabase functions deploy gerir-funcionarios --no-verify-jwt
// (o token é validado no código com auth.getUser; --no-verify-jwt evita depender do formato de chaves do gateway)
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { tratar, type DepsEquipa, type FuncionarioBD } from './handler.ts';

const URL_PROJETO = Deno.env.get('SUPABASE_URL') ?? '';
const CHAVE_SERVICO = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const admin = createClient(URL_PROJETO, CHAVE_SERVICO, { auth: { persistSession: false, autoRefreshToken: false } });

// P0001 = exceção levantada de propósito pelas funções SQL (mensagens escritas por nós, seguras de mostrar).
function negocio(error: { code?: string; message: string }): { erro: string } {
  if (error.code === 'P0001') return { erro: error.message };
  console.error('gerir-funcionarios: erro da base de dados', error.code, error.message);
  throw new Error('db');
}

function dependencias(): DepsEquipa {
  return {
    async autenticar(jwt) {
      const { data, error } = await admin.auth.getUser(jwt);
      return error || !data.user ? null : data.user.id;
    },
    async limite(chave, max, janelaMin) {
      const { data, error } = await admin.rpc('servico_limite', { p_chave: chave, p_max: max, p_janela_min: janelaMin });
      if (error) throw error;
      return data === true;
    },
    async empresaDoAdmin(userId) {
      const { data, error } = await admin.rpc('servico_admin_empresa', { p_user: userId });
      if (error) throw error;
      return typeof data === 'string' ? data : null;
    },
    async verificarLimite(empresa) {
      const { error } = await admin.rpc('servico_verificar_limite_funcionarios', { p_empresa: empresa });
      return error ? negocio(error) : null;
    },
    async emailExiste(email) {
      const { data, error } = await admin.rpc('servico_utilizador_existe', { p_email: email });
      if (error) throw error;
      return data === true;
    },
    async criarUtilizador(email, senha, nome) {
      const { data, error } = await admin.auth.admin.createUser({ email, password: senha, email_confirm: true, user_metadata: { nome } });
      if (error || !data.user) {
        console.error('gerir-funcionarios: createUser falhou', error?.code, error?.status);
        if (error?.code === 'email_exists' || error?.code === 'user_already_exists') return { erro: 'existe' };
        if (error?.status === 422 || error?.code === 'weak_password' || error?.code === 'validation_failed') return { erro: 'invalido' };
        return { erro: 'falha' };
      }
      return { id: data.user.id };
    },
    async apagarUtilizador(id) {
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) throw error;
    },
    async criarFuncionario(a) {
      const { data, error } = await admin.rpc('servico_criar_funcionario', {
        p_empresa: a.empresa, p_user: a.userId, p_autor: a.autor, p_nome: a.nome, p_email: a.email, p_papel: a.papel,
        p_numero: a.numero, p_veiculo: a.veiculo, p_telefone: a.telefone, p_licenca: a.licenca,
        p_permissoes: a.permissoes, p_ativo: a.ativo,
      });
      return error ? negocio(error) : { funcionario: data as FuncionarioBD };
    },
    async obterFuncionario(empresa, alvo) {
      const { data, error } = await admin.rpc('servico_obter_funcionario', { p_empresa: empresa, p_alvo: alvo });
      if (error) throw error;
      const f = data as FuncionarioBD | null;
      return f && f.id ? f : null;
    },
    async atualizar(empresa, alvo, autor, alt) {
      const { data, error } = await admin.rpc('servico_atualizar_funcionario', { p_empresa: empresa, p_alvo: alvo, p_autor: autor, p_alt: alt });
      return error ? negocio(error) : { funcionario: data as FuncionarioBD };
    },
    async prepararRemocao(empresa, alvo, autor) {
      const { data, error } = await admin.rpc('servico_preparar_remocao', { p_empresa: empresa, p_alvo: alvo, p_autor: autor });
      return error ? negocio(error) : { funcionario: data as FuncionarioBD };
    },
    async eliminarUtilizador(id) {
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) console.warn('gerir-funcionarios: deleteUser recusado (provável histórico associado)', error.status);
      return !error;
    },
    async definirBan(id, banir) {
      const { error } = await admin.auth.admin.updateUserById(id, { ban_duration: banir ? '876000h' : 'none' });
      if (error) console.error('gerir-funcionarios: ban falhou', error.status);
      return !error;
    },
    async definirSenha(id, senha) {
      const { error } = await admin.auth.admin.updateUserById(id, { password: senha });
      if (error) console.error('gerir-funcionarios: alterar palavra-passe falhou', error.code, error.status);
      return !error;
    },
    async encerrarSessoes(id) {
      const { error } = await admin.rpc('servico_encerrar_sessoes', { p_alvo: id });
      if (error) throw error;
    },
    async auditar(empresa, user, acao, alvo, depois) {
      const { error } = await admin.rpc('servico_auditar', { p_empresa: empresa, p_user: user, p_acao: acao, p_entidade_id: alvo, p_depois: depois });
      if (error) console.error('gerir-funcionarios: auditoria falhou', error.code);
    },
  };
}

Deno.serve((req: Request) => tratar(req, dependencias()));
