// Validação de entradas das Edge Functions. Sem dependências: corre igual em Deno e em Node (testes).
// As mensagens são para o utilizador final (português) e nunca incluem erros internos.

export type Papel = 'admin_empresa' | 'operador' | 'operador_terreno' | 'armazem' | 'financeiro';
export const PAPEIS: readonly Papel[] = ['admin_empresa', 'operador', 'operador_terreno', 'armazem', 'financeiro'];

// Lista fechada. Tem de coincidir com private.permissoes_validas() em 0006_funcoes_servico.sql.
export const PERMISSOES: readonly string[] = [
  'view_assigned_jobs', 'update_assigned_jobs', 'capture_load', 'register_signature',
  'create_incident', 'confirm_field_prepayment', 'delete_order_history',
];

export type Resultado<T> = { ok: true; dados: T } | { ok: false; erro: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const ehUuid = (v: unknown): v is string => typeof v === 'string' && UUID.test(v);

const registo = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);

export const texto = (v: unknown): string => (typeof v === 'string' ? v.trim() : '');
export const normalizarEmail = (v: unknown): string => texto(v).toLowerCase();
export const emailValido = (s: string): boolean => s.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
export const nifValido = (s: string): boolean => /^[A-Za-z0-9][A-Za-z0-9.\-/ ]{3,18}[A-Za-z0-9]$/.test(s);
export const telefoneValido = (s: string): boolean => /^[0-9+()\-. ]{6,25}$/.test(s);

const bytes = (s: string): number => new TextEncoder().encode(s).length;

/** Palavra-passe de um funcionário. O operador de terreno usa PIN numérico (6–8 dígitos). */
export function validarSenha(senha: unknown, papel?: Papel): string | null {
  if (typeof senha !== 'string' || senha === '') return 'Indique a palavra-passe.';
  if (bytes(senha) > 72) return 'A palavra-passe não pode ter mais de 72 caracteres.';
  if (papel === 'operador_terreno') {
    return /^\d{6,8}$/.test(senha) ? null : 'O PIN do operador de terreno deve ter entre 6 e 8 dígitos.';
  }
  if (senha.length < 8 || !/[a-z]/.test(senha) || !/[A-Z]/.test(senha) || !/\d/.test(senha)) {
    return 'A palavra-passe deve ter pelo menos 8 caracteres, incluindo maiúscula, minúscula e número.';
  }
  return null;
}

export function validarSenhaEmpresa(senha: unknown): string | null {
  if (typeof senha !== 'string' || senha.length < 8) return 'A palavra-passe da empresa deve ter pelo menos 8 caracteres.';
  if (bytes(senha) > 72) return 'A palavra-passe da empresa não pode ter mais de 72 caracteres.';
  return null;
}

// ---------------------------------------------------------------- registo de prestador
export interface DadosRegisto {
  empresaNome: string; nif: string; empresaEmail: string; telefone: string; senhaEmpresa: string;
  adminNome: string; adminEmail: string; adminSenha: string;
  plano: string; metodo: string; referencia: string;
}

export function validarRegisto(corpo: unknown): Resultado<DadosRegisto> {
  if (!registo(corpo)) return { ok: false, erro: 'Pedido inválido.' };
  const e = registo(corpo.empresa) ? corpo.empresa : {};
  const a = registo(corpo.admin) ? corpo.admin : {};
  const p = registo(corpo.pagamento) ? corpo.pagamento : {};

  const d: DadosRegisto = {
    empresaNome: texto(e.nome), nif: texto(e.nif), empresaEmail: normalizarEmail(e.email), telefone: texto(e.telefone),
    senhaEmpresa: typeof corpo.senhaEmpresa === 'string' ? corpo.senhaEmpresa : '',
    adminNome: texto(a.nome), adminEmail: normalizarEmail(a.email), adminSenha: typeof a.senha === 'string' ? a.senha : '',
    plano: texto(corpo.plano), metodo: texto(p.metodo), referencia: texto(p.referencia),
  };

  if (d.empresaNome.length < 2 || d.empresaNome.length > 120) return { ok: false, erro: 'Indique o nome da empresa (2 a 120 caracteres).' };
  if (!nifValido(d.nif)) return { ok: false, erro: 'Indique um NIF válido.' };
  if (!emailValido(d.empresaEmail)) return { ok: false, erro: 'Indique um e-mail da empresa válido.' };
  if (!telefoneValido(d.telefone)) return { ok: false, erro: 'Indique um telefone válido.' };
  const erroEmpresa = validarSenhaEmpresa(d.senhaEmpresa);
  if (erroEmpresa) return { ok: false, erro: erroEmpresa };
  if (d.adminNome.length < 2 || d.adminNome.length > 100) return { ok: false, erro: 'Indique o nome do administrador (2 a 100 caracteres).' };
  if (!emailValido(d.adminEmail)) return { ok: false, erro: 'Indique um e-mail válido para o administrador.' };
  const erroAdmin = validarSenha(d.adminSenha);
  if (erroAdmin) return { ok: false, erro: erroAdmin.replace('A palavra-passe', 'A palavra-passe do administrador') };
  if (d.senhaEmpresa === d.adminSenha) return { ok: false, erro: 'A palavra-passe da empresa tem de ser diferente da do administrador.' };
  if (d.plano.length < 1 || d.plano.length > 60) return { ok: false, erro: 'Escolha um plano.' };
  if (d.metodo.length < 1 || d.metodo.length > 40) return { ok: false, erro: 'Indique o método de pagamento.' };
  if (d.referencia.length < 1 || d.referencia.length > 80) return { ok: false, erro: 'Indique a referência do pagamento.' };
  if (corpo.aceitouTermos !== true) return { ok: false, erro: 'Aceite os termos de utilização para continuar.' };
  return { ok: true, dados: d };
}

// ---------------------------------------------------------------- funcionários
export interface NovoFuncionario {
  nome: string; email: string; papel: Papel; senha: string; numeroInterno: string; veiculo: string;
  telefone: string; licenca: string; permissoes: string[]; ativo: boolean;
}

function permissoesValidas(v: unknown): string[] | null {
  if (!Array.isArray(v) || v.length > PERMISSOES.length) return null;
  const lista = v.filter((x): x is string => typeof x === 'string');
  if (lista.length !== v.length || lista.some(x => !PERMISSOES.includes(x))) return null;
  return [...new Set(lista)];
}

export function validarNovoFuncionario(corpo: Record<string, unknown>): Resultado<NovoFuncionario> {
  const papel = texto(corpo.papel);
  if (!(PAPEIS as readonly string[]).includes(papel)) return { ok: false, erro: 'Escolha uma função válida.' };
  const d: NovoFuncionario = {
    nome: texto(corpo.nome), email: normalizarEmail(corpo.email), papel: papel as Papel,
    senha: typeof corpo.senha === 'string' ? corpo.senha : '',
    numeroInterno: texto(corpo.numeroInterno), veiculo: texto(corpo.veiculo), telefone: texto(corpo.telefone),
    licenca: texto(corpo.licenca), permissoes: [], ativo: corpo.ativo === undefined ? true : corpo.ativo === true,
  };
  if (d.nome.length < 2 || d.nome.length > 100) return { ok: false, erro: 'Indique o nome do funcionário (2 a 100 caracteres).' };
  if (!emailValido(d.email)) return { ok: false, erro: 'Indique um e-mail válido.' };
  const erroSenha = validarSenha(d.senha, d.papel);
  if (erroSenha) return { ok: false, erro: erroSenha };
  if (d.numeroInterno.length > 30 || d.veiculo.length > 30 || d.licenca.length > 30) return { ok: false, erro: 'Um dos campos excede 30 caracteres.' };
  if (d.telefone !== '' && !telefoneValido(d.telefone)) return { ok: false, erro: 'Indique um telefone válido.' };
  if (corpo.permissoes !== undefined) {
    const perm = permissoesValidas(corpo.permissoes);
    if (!perm) return { ok: false, erro: 'Permissões inválidas.' };
    d.permissoes = perm;
  }
  return { ok: true, dados: d };
}

/** Traduz as alterações (camelCase da API) para as chaves esperadas por servico_atualizar_funcionario(). */
export function validarAlteracoes(bruto: unknown): Resultado<Record<string, unknown>> {
  if (!registo(bruto)) return { ok: false, erro: 'Alterações inválidas.' };
  const mapa: Record<string, string> = {
    nome: 'nome', papel: 'papel', ativo: 'ativo', numeroInterno: 'numero_interno', veiculo: 'veiculo_habitual',
    telefone: 'telefone', licenca: 'licenca_conducao', permissoes: 'permissoes',
  };
  const alt: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(bruto)) {
    const destino = mapa[k];
    if (!destino) return { ok: false, erro: `Campo desconhecido: ${k.slice(0, 30)}.` };
    if (k === 'papel') {
      if (typeof v !== 'string' || !(PAPEIS as readonly string[]).includes(v)) return { ok: false, erro: 'Função inválida.' };
      alt[destino] = v;
    } else if (k === 'ativo') {
      if (typeof v !== 'boolean') return { ok: false, erro: 'Estado inválido.' };
      alt[destino] = v;
    } else if (k === 'permissoes') {
      const perm = permissoesValidas(v);
      if (!perm) return { ok: false, erro: 'Permissões inválidas.' };
      alt[destino] = perm;
    } else {
      const t = texto(v);
      if (t.length > (k === 'nome' ? 100 : 30)) return { ok: false, erro: `O campo ${k} é demasiado longo.` };
      if (k === 'nome' && t.length < 2) return { ok: false, erro: 'Indique o nome do funcionário.' };
      if (k === 'telefone' && t !== '' && !telefoneValido(t)) return { ok: false, erro: 'Indique um telefone válido.' };
      alt[destino] = t;
    }
  }
  if (Object.keys(alt).length === 0) return { ok: false, erro: 'Não há alterações a guardar.' };
  return { ok: true, dados: alt };
}

// ---------------------------------------------------------------- limites de pedidos
/** SHA-256 em hexadecimal: as chaves de limite não guardam e-mails, NIF nem IPs em claro. */
export async function hashChave(valor: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(valor));
  return Array.from(new Uint8Array(buf), b => b.toString(16).padStart(2, '0')).join('');
}

/** Melhor esforço: o 1.º IP de x-forwarded-for pode ser influenciado pelo cliente, por isso o limite por IP
 *  é só uma camada; os limites por NIF e por e-mail não dependem dele. */
export function ipDoPedido(h: Headers): string {
  const xff = h.get('x-forwarded-for');
  if (xff) return xff.split(',')[0].trim().slice(0, 64) || 'desconhecido';
  return (h.get('cf-connecting-ip') ?? 'desconhecido').slice(0, 64);
}
