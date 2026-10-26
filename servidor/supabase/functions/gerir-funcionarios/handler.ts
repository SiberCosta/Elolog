// Lógica de "gerir-funcionarios", separada do arranque (index.ts) para poder ser testada sem Deno nem rede.
// Só o ADMINISTRADOR da empresa, com a sessão de empresa aberta, pode usar esta função. A empresa vem SEMPRE
// da sessão do chamador, nunca do pedido.
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';
import {
  ehUuid, hashChave, validarAlteracoes, validarNovoFuncionario, validarSenha, type Papel,
} from '../_shared/validar.ts';

export interface FuncionarioBD {
  id: string; nome: string; email: string; papel: Papel; ativo: boolean;
  numero_interno: string | null; veiculo_habitual: string | null; telefone: string | null;
  licenca_conducao: string | null; permissoes: string[] | null;
}
export type FalhaNegocio = { erro: string };       // mensagem segura para mostrar ao utilizador

export interface DepsEquipa {
  /** Valida o token e devolve o id do utilizador (ou null). */
  autenticar(jwt: string): Promise<string | null>;
  limite(chave: string, max: number, janelaMin: number): Promise<boolean>;
  /** Empresa do utilizador se for administrador ativo, de empresa aprovada, com sessão de empresa válida. */
  empresaDoAdmin(userId: string): Promise<string | null>;
  verificarLimite(empresa: string): Promise<FalhaNegocio | null>;
  emailExiste(email: string): Promise<boolean>;
  criarUtilizador(email: string, senha: string, nome: string): Promise<{ id: string } | { erro: 'existe' | 'invalido' | 'falha' }>;
  apagarUtilizador(id: string): Promise<void>;
  criarFuncionario(a: {
    empresa: string; userId: string; autor: string; nome: string; email: string; papel: Papel; numero: string;
    veiculo: string; telefone: string; licenca: string; permissoes: string[]; ativo: boolean;
  }): Promise<{ funcionario: FuncionarioBD } | FalhaNegocio>;
  obterFuncionario(empresa: string, alvo: string): Promise<FuncionarioBD | null>;
  atualizar(empresa: string, alvo: string, autor: string, alt: Record<string, unknown>): Promise<{ funcionario: FuncionarioBD } | FalhaNegocio>;
  /** Valida as regras (não é o próprio, não é o último administrador) e fecha as sessões de empresa. */
  prepararRemocao(empresa: string, alvo: string, autor: string): Promise<{ funcionario: FuncionarioBD } | FalhaNegocio>;
  eliminarUtilizador(id: string): Promise<boolean>;
  definirBan(id: string, banir: boolean): Promise<boolean>;
  definirSenha(id: string, senha: string): Promise<boolean>;
  encerrarSessoes(id: string): Promise<void>;
  auditar(empresa: string, user: string, acao: string, alvo: string, depois: Record<string, unknown>): Promise<void>;
}

const PERMISSOES_TERRENO = ['view_assigned_jobs', 'update_assigned_jobs', 'capture_load', 'register_signature', 'create_incident'];

function publico(f: FuncionarioBD) {
  return {
    id: f.id, nome: f.nome, email: f.email, papel: f.papel, ativo: f.ativo,
    numeroInterno: f.numero_interno ?? '', veiculo: f.veiculo_habitual ?? '', telefone: f.telefone ?? '',
    licenca: f.licenca_conducao ?? '', permissoes: f.permissoes ?? [],
  };
}

const MSG_EMAIL = 'Já existe uma conta com este e-mail.';

export async function tratar(req: Request, deps: DepsEquipa): Promise<Response> {
  if (req.method === 'OPTIONS') return preflight();
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');

  try {
    const auth = req.headers.get('authorization') ?? '';
    const jwt = /^Bearer\s+(\S+)$/i.exec(auth)?.[1] ?? '';
    if (!jwt) return erro(401, 'sem_sessao', 'Inicie sessão para continuar.');
    const userId = await deps.autenticar(jwt);
    if (!userId) return erro(401, 'sessao_invalida', 'A sessão expirou. Inicie sessão novamente.');

    if (!(await deps.limite(await hashChave(`equipa:${userId}`), 60, 10))) {
      return erro(429, 'demasiados_pedidos', 'Demasiados pedidos. Aguarde alguns minutos.');
    }

    const empresa = await deps.empresaDoAdmin(userId);
    if (!empresa) {
      return erro(403, 'sem_permissao', 'Só o administrador da empresa, com a sessão da empresa ativa, pode gerir funcionários.');
    }

    const lido = await lerJson(req);
    if (!lido.ok) return lido.resp;
    const corpo = lido.valor;
    if (typeof corpo !== 'object' || corpo === null || Array.isArray(corpo)) return erro(400, 'dados_invalidos', 'Pedido inválido.');
    const c = corpo as Record<string, unknown>;

    switch (c.acao) {
      case 'criar': return await criar(c, empresa, userId, deps);
      case 'atualizar': return await atualizar(c, empresa, userId, deps);
      case 'repor_senha': return await reporSenha(c, empresa, userId, deps);
      case 'eliminar': return await eliminar(c, empresa, userId, deps);
      default: return erro(400, 'acao_invalida', 'Ação desconhecida.');
    }
  } catch (e) {
    console.error('gerir-funcionarios: erro inesperado', e);
    return erro(503, 'indisponivel', 'Serviço temporariamente indisponível. Tente novamente.');
  }
}

async function criar(c: Record<string, unknown>, empresa: string, autor: string, deps: DepsEquipa): Promise<Response> {
  const v = validarNovoFuncionario(c);
  if (!v.ok) return erro(400, 'dados_invalidos', v.erro);
  const d = v.dados;
  const permissoes = c.permissoes === undefined && d.papel === 'operador_terreno' ? PERMISSOES_TERRENO : d.permissoes;

  if (d.ativo) {
    const cheio = await deps.verificarLimite(empresa);                  // antes de criar o utilizador
    if (cheio) return erro(409, 'limite_plano', cheio.erro);
  }
  if (await deps.emailExiste(d.email)) return erro(409, 'email_existe', MSG_EMAIL);

  const u = await deps.criarUtilizador(d.email, d.senha, d.nome);
  if ('erro' in u) {
    if (u.erro === 'existe') return erro(409, 'email_existe', MSG_EMAIL);
    if (u.erro === 'invalido') return erro(400, 'conta_recusada', 'O servidor de contas recusou o e-mail ou a palavra-passe.');
    return erro(500, 'falha', 'Não foi possível criar a conta. Tente novamente.');
  }

  const f = await deps.criarFuncionario({
    empresa, userId: u.id, autor, nome: d.nome, email: d.email, papel: d.papel, numero: d.numeroInterno,
    veiculo: d.veiculo, telefone: d.telefone, licenca: d.licenca, permissoes, ativo: d.ativo,
  });
  if ('erro' in f) {
    try { await deps.apagarUtilizador(u.id); } catch (e) { console.error('gerir-funcionarios: utilizador órfão', u.id, e); }
    return erro(409, 'regra', f.erro);
  }
  let aviso: string | undefined;
  if (!d.ativo && !(await deps.definirBan(u.id, true))) aviso = 'A conta ficou inativa, mas não foi possível bloquear o início de sessão.';
  return resposta(201, { ok: true, funcionario: publico(f.funcionario), aviso });
}

async function atualizar(c: Record<string, unknown>, empresa: string, autor: string, deps: DepsEquipa): Promise<Response> {
  if (!ehUuid(c.id)) return erro(400, 'dados_invalidos', 'Funcionário inválido.');
  const v = validarAlteracoes(c.alteracoes);
  if (!v.ok) return erro(400, 'dados_invalidos', v.erro);

  const r = await deps.atualizar(empresa, c.id, autor, v.dados);
  if ('erro' in r) return erro(409, 'regra', r.erro);

  let aviso: string | undefined;
  if (typeof v.dados.ativo === 'boolean') {
    // A base de dados já bloqueia o acesso (ativo=false). O ban é uma 2.ª barreira no serviço de contas.
    const ok = await deps.definirBan(c.id, !v.dados.ativo);
    if (!ok) aviso = 'O estado foi guardado, mas não foi possível atualizar o bloqueio da conta de autenticação.';
  }
  return resposta(200, { ok: true, funcionario: publico(r.funcionario), aviso });
}

async function reporSenha(c: Record<string, unknown>, empresa: string, autor: string, deps: DepsEquipa): Promise<Response> {
  if (!ehUuid(c.id)) return erro(400, 'dados_invalidos', 'Funcionário inválido.');
  if (c.id === autor) {
    return erro(403, 'propria_conta', 'Não pode redefinir a sua própria palavra-passe aqui. Peça a outro administrador ou use a recuperação de conta.');
  }
  const alvo = await deps.obterFuncionario(empresa, c.id);
  if (!alvo) return erro(404, 'nao_encontrado', 'Funcionário não encontrado nesta empresa.');
  const falha = validarSenha(c.senha, alvo.papel);
  if (falha) return erro(400, 'dados_invalidos', falha);

  if (!(await deps.definirSenha(c.id, c.senha as string))) {
    return erro(500, 'falha', 'Não foi possível alterar a palavra-passe. Tente novamente.');
  }
  await deps.encerrarSessoes(c.id);                    // obriga a novo login completo
  await deps.auditar(empresa, autor, 'repor_senha_funcionario', c.id, { email: alvo.email });
  return resposta(200, { ok: true });
}

async function eliminar(c: Record<string, unknown>, empresa: string, autor: string, deps: DepsEquipa): Promise<Response> {
  if (!ehUuid(c.id)) return erro(400, 'dados_invalidos', 'Funcionário inválido.');
  const prep = await deps.prepararRemocao(empresa, c.id, autor);
  if ('erro' in prep) return erro(409, 'regra', prep.erro);

  if (await deps.eliminarUtilizador(c.id)) {
    await deps.auditar(empresa, autor, 'eliminar_funcionario', c.id, { email: prep.funcionario.email, papel: prep.funcionario.papel });
    return resposta(200, { ok: true, eliminado: true });
  }
  // Quem já criou encomendas, propostas, etc. não pode ser apagado (o histórico tem de manter o autor):
  // fica desativado e bloqueado, sem acesso.
  const arq = await deps.atualizar(empresa, c.id, autor, { ativo: false });
  if ('erro' in arq) return erro(409, 'regra', arq.erro);
  const banido = await deps.definirBan(c.id, true);
  await deps.auditar(empresa, autor, 'arquivar_funcionario', c.id, { email: prep.funcionario.email, banido });
  return resposta(200, { ok: true, eliminado: false, desativado: true, funcionario: publico(arq.funcionario) });
}
