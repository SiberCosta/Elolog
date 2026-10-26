import { tratar as registar, type DepsRegisto } from '../registar-prestador/handler.ts';
import { tratar as equipa, type DepsEquipa, type FuncionarioBD } from '../gerir-funcionarios/handler.ts';
import { validarSenha, validarRegisto, validarAlteracoes, validarNovoFuncionario, hashChave, ipDoPedido } from '../_shared/validar.ts';

let falhas = 0;
const ok = (c: unknown, m: string) => { console.log((c ? '✔ ' : '✘ ') + m); if (!c) falhas++; };
const U = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const post = (url: string, corpo: unknown, h: Record<string, string> = {}) =>
  new Request(url, { method: 'POST', headers: { 'content-type': 'application/json', ...h }, body: typeof corpo === 'string' ? corpo : JSON.stringify(corpo) });

// ============================================================ validações
ok(validarSenha('Abcdef12') === null, 'senha forte aceite');
ok(validarSenha('abcdefgh') !== null && validarSenha('Abc12') !== null, 'senha sem maiúscula/número ou curta recusada');
ok(validarSenha('a'.repeat(40) + 'A1' + 'é'.repeat(20)) !== null, 'senha com mais de 72 BYTES (acentos contam 2) recusada');
ok(validarSenha('123456', 'operador_terreno') === null && validarSenha('1234', 'operador_terreno') !== null && validarSenha('12a456', 'operador_terreno') !== null, 'PIN do terreno: 6–8 dígitos (4 dígitos e letras recusados)');
const regOk = {
  empresa: { nome: 'Transitária Nova, Lda', nif: '500123456', email: 'GERAL@nova.pt', telefone: '+351 210 000 000' }, senhaEmpresa: 'segredo-empresa-1',
  admin: { nome: 'Ana Admin', email: 'Ana@Nova.pt', senha: 'Admin1234' }, plano: 'Básico', pagamento: { metodo: 'Transferência', referencia: 'REF123' }, aceitouTermos: true,
};
const v = validarRegisto(regOk);
ok(v.ok && v.dados.adminEmail === 'ana@nova.pt' && v.dados.empresaEmail === 'geral@nova.pt', 'registo válido: e-mails normalizados para minúsculas');
ok(!validarRegisto({ ...regOk, aceitouTermos: false }).ok, 'registo sem aceitar termos recusado');
ok(!validarRegisto({ ...regOk, senhaEmpresa: 'Admin1234' }).ok, 'senha da empresa igual à do admin recusada');
ok(!validarRegisto({ ...regOk, empresa: { ...regOk.empresa, nif: '<script>' } }).ok, 'NIF com caracteres inválidos recusado');
ok(!validarRegisto({ ...regOk, pagamento: { metodo: '', referencia: 'x' } }).ok, 'registo sem método de pagamento recusado');
ok(!validarRegisto('texto').ok && !validarRegisto(null).ok && !validarRegisto([]).ok, 'corpo que não é objeto recusado');
ok(!validarAlteracoes({ papel: 'superadmin' }).ok && !validarAlteracoes({ empresa_id: U(9) }).ok && !validarAlteracoes({}).ok, 'alterações: função desconhecida, campo desconhecido (empresa_id) e vazio recusados');
ok(!validarAlteracoes({ permissoes: ['delete_everything'] }).ok && validarAlteracoes({ permissoes: ['capture_load', 'capture_load'] }).ok, 'permissões: só da lista fechada (duplicados removidos)');
ok(!validarNovoFuncionario({ nome: 'X Y', email: 'x@y.pt', papel: 'operador', senha: 'Abcdef12', permissoes: ['xpto'] }).ok, 'novo funcionário com permissão inventada recusado');
const h1 = await hashChave('reg:email:a@b.pt');
ok(h1.length === 64 && !h1.includes('a@b') && h1 === await hashChave('reg:email:a@b.pt'), 'chave de limite é SHA-256 estável (sem e-mail em claro)');
ok(ipDoPedido(new Headers({ 'x-forwarded-for': '1.2.3.4, 5.6.7.8' })) === '1.2.3.4' && ipDoPedido(new Headers()) === 'desconhecido', 'IP: 1.º do x-forwarded-for ou "desconhecido"');

// ============================================================ registar-prestador
function depsReg(sobre: Partial<DepsRegisto> = {}) {
  const log: string[] = [];
  const d: DepsRegisto = {
    async limite(c) { log.push('limite:' + c.length); return true; },
    async utilizadorExiste() { log.push('existe'); return false; },
    async criarUtilizador() { log.push('criarUtilizador'); return { id: U(1), exigeConfirmacao: true }; },
    async registar() { log.push('registar'); return { empresaId: U(100) }; },
    async apagarUtilizador(id) { log.push('apagar:' + id); },
    ...sobre,
  };
  return { d, log };
}
const URLR = 'http://localhost/registar-prestador';
{
  const { d, log } = depsReg();
  const r = await registar(post(URLR, regOk), d);
  const j = await r.json();
  ok(r.status === 201 && j.ok && j.pendente === true && j.confirmarEmail === true, 'registo: 201, pendente e pede confirmação de e-mail');
  ok(log.filter(x => x.startsWith('limite')).length === 3 && log.indexOf('existe') > 2 && log.indexOf('criarUtilizador') > log.indexOf('existe') && log.at(-1) === 'registar', 'registo: 3 limites (IP, NIF, e-mail) → e-mail livre → criar utilizador → registar');
  ok(r.headers.get('access-control-allow-origin') === '*', 'registo: cabeçalhos CORS presentes');
}
{
  const r = await registar(new Request(URLR, { method: 'OPTIONS' }), depsReg().d);
  ok(r.status === 204 && !!r.headers.get('access-control-allow-headers')?.includes('authorization'), 'registo: pré-voo CORS (OPTIONS) 204');
  ok((await registar(new Request(URLR, { method: 'GET' }), depsReg().d)).status === 405, 'registo: GET recusado (405)');
}
{
  const { d, log } = depsReg({ async limite(c) { return !c.length ? false : (log.push('l'), log.length < 2); } });
  const r = await registar(post(URLR, regOk), d);
  ok(r.status === 429 && !log.includes('criarUtilizador'), 'registo: limite excedido → 429 e NADA é criado');
}
{
  const { d, log } = depsReg({ async utilizadorExiste() { return true; } });
  const r = await registar(post(URLR, regOk), d);
  ok(r.status === 409 && (await r.json()).erro.codigo === 'email_existe' && !log.includes('criarUtilizador'), 'registo: e-mail já usado → 409 sem criar utilizador');
}
{
  const { d, log } = depsReg({ async registar() { return { erro: 'nif_duplicado' as const }; } });
  const r = await registar(post(URLR, regOk), d);
  ok(r.status === 409 && (await r.json()).erro.codigo === 'nif_existe', 'registo: NIF duplicado → 409');
  ok(log.includes('apagar:' + U(1)), 'registo: ROLLBACK — o utilizador de autenticação criado é apagado quando o registo da empresa falha');
}
{
  const { d } = depsReg({ async registar() { return { erro: 'falha' as const }; }, async apagarUtilizador() { throw new Error('boom'); } });
  const r = await registar(post(URLR, regOk), d);
  ok(r.status === 500, 'registo: falha ao apagar o órfão não rebenta a resposta (500 limpo, erro só no log)');
}
{
  const { d } = depsReg({ async limite() { throw new Error('postgres: connection refused 10.0.0.5'); } });
  const r = await registar(post(URLR, regOk), d);
  const t = await r.text();
  ok(r.status === 503 && !t.includes('postgres') && !t.includes('10.0.0.5'), 'registo: erro interno devolve 503 genérico, sem detalhes internos');
}
ok((await registar(post(URLR, '{não é json'), depsReg().d)).status === 400, 'registo: JSON inválido → 400');
ok((await registar(post(URLR, 'x'.repeat(30000)), depsReg().d)).status === 413, 'registo: corpo enorme → 413');
{
  const { d, log } = depsReg();
  const r = await registar(post(URLR, { ...regOk, aceitouTermos: false }), d);
  ok(r.status === 400 && log.length === 0, 'registo: dados inválidos → 400 antes de tocar em limites ou base de dados');
}

// ============================================================ gerir-funcionarios
const EMP = U(500), ADMIN = U(10), OUTRO = U(20), ADMIN2 = U(11);
const fn = (id: string, papel: FuncionarioBD['papel'], ativo = true, extra: Partial<FuncionarioBD> = {}): FuncionarioBD =>
  ({ id, nome: 'Nome ' + id.slice(-2), email: `u${id.slice(-2)}@x.pt`, papel, ativo, numero_interno: null, veiculo_habitual: null, telefone: null, licenca_conducao: null, permissoes: [], ...extra });

function depsEq(sobre: Partial<DepsEquipa> = {}) {
  const log: string[] = [];
  const base: FuncionarioBD[] = [fn(ADMIN, 'admin_empresa'), fn(OUTRO, 'operador'), fn(ADMIN2, 'admin_empresa')];
  const d: DepsEquipa = {
    async autenticar(jwt) { log.push('auth'); return jwt === 'token-admin' ? ADMIN : jwt === 'token-operador' ? OUTRO : null; },
    async limite() { return true; },
    async empresaDoAdmin(u) { log.push('empresaDoAdmin'); return u === ADMIN ? EMP : null; },
    async verificarLimite() { log.push('verificarLimite'); return null; },
    async emailExiste() { return false; },
    async criarUtilizador() { log.push('criarUtilizador'); return { id: U(30) }; },
    async apagarUtilizador(id) { log.push('apagar:' + id); },
    async criarFuncionario(a) { log.push('criarFuncionario:' + a.empresa + ':' + a.permissoes.join('|')); return { funcionario: fn(a.userId, a.papel, a.ativo, { email: a.email, nome: a.nome, permissoes: a.permissoes }) }; },
    async obterFuncionario(empresa, alvo) { log.push('obter:' + empresa); return empresa === EMP ? base.find(f => f.id === alvo) ?? null : null; },
    async atualizar(empresa, alvo, autor, alt) { log.push('atualizar:' + JSON.stringify(alt)); const f = base.find(x => x.id === alvo); return f ? { funcionario: { ...f, ...(typeof alt.ativo === 'boolean' ? { ativo: alt.ativo } : {}) } } : { erro: 'Funcionário não encontrado nesta empresa.' }; },
    async prepararRemocao(empresa, alvo) { log.push('preparar'); const f = base.find(x => x.id === alvo); return f ? { funcionario: f } : { erro: 'Funcionário não encontrado nesta empresa.' }; },
    async eliminarUtilizador() { log.push('eliminarUtilizador'); return true; },
    async definirBan(id, b) { log.push(`ban:${b}`); return true; },
    async definirSenha(id) { log.push('definirSenha'); return true; },
    async encerrarSessoes() { log.push('encerrarSessoes'); },
    async auditar(e, u, acao) { log.push('auditar:' + acao); },
    ...sobre,
  };
  return { d, log };
}
const URLE = 'http://localhost/gerir-funcionarios';
const pedir = (corpo: unknown, token = 'token-admin') => post(URLE, corpo, token ? { authorization: 'Bearer ' + token } : {});
const novo = { acao: 'criar', nome: 'Rui Operador', email: 'Rui@Empresa.pt', papel: 'operador', senha: 'Operador123', numeroInterno: 'OP-1' };

{
  const { d } = depsEq();
  ok((await equipa(post(URLE, novo), d)).status === 401, 'equipa: sem token → 401');
  ok((await equipa(pedir(novo, 'token-falso'), d)).status === 401, 'equipa: token inválido → 401');
  const r = await equipa(pedir(novo, 'token-operador'), d);
  ok(r.status === 403, 'equipa: utilizador que NÃO é administrador (ou sem sessão de empresa) → 403');
}
{
  const { d, log } = depsEq();
  const r = await equipa(pedir(novo), d); const j = await r.json();
  ok(r.status === 201 && j.funcionario.email === 'rui@empresa.pt' && j.funcionario.papel === 'operador', 'criar: 201 com e-mail em minúsculas');
  ok(log.indexOf('verificarLimite') < log.indexOf('criarUtilizador') && log.indexOf('criarUtilizador') < log.findIndex(x => x.startsWith('criarFuncionario')), 'criar: limite do plano verificado ANTES de criar o utilizador');
  ok(log.some(x => x.startsWith('criarFuncionario:' + EMP)), 'criar: empresa vem da sessão do administrador');
}
{
  const { d, log } = depsEq();
  await equipa(pedir({ ...novo, empresaId: U(999), empresa_id: U(999) }), d);
  ok(!log.some(x => x.includes(U(999))), 'criar: empresaId enviado no pedido é IGNORADO (nunca se confia no cliente)');
}
{
  const { d, log } = depsEq({ async verificarLimite() { return { erro: 'O plano da empresa permite 3 funcionários ativos e já estão todos em uso.' }; } });
  const r = await equipa(pedir(novo), d);
  ok(r.status === 409 && (await r.json()).erro.codigo === 'limite_plano' && !log.includes('criarUtilizador'), 'criar: plano cheio → 409 e nenhum utilizador criado');
}
{
  const { d, log } = depsEq({ async criarFuncionario() { return { erro: 'O plano da empresa permite 3 funcionários ativos e já estão todos em uso.' }; } });
  const r = await equipa(pedir(novo), d);
  ok(r.status === 409 && log.includes('apagar:' + U(30)), 'criar: falha na BD (ex.: corrida no limite) → utilizador criado é apagado (rollback)');
}
{
  const { d } = depsEq({ async emailExiste() { return true; } });
  ok((await equipa(pedir(novo), d)).status === 409, 'criar: e-mail já existente → 409');
}
{
  const { d, log } = depsEq();
  const r = await equipa(pedir({ ...novo, papel: 'operador_terreno', senha: '1234' }), d);
  ok(r.status === 400 && !log.includes('criarUtilizador'), 'criar: PIN de 4 dígitos recusado (mínimo 6)');
  const r2 = await equipa(pedir({ ...novo, papel: 'operador_terreno', senha: '123456' }), d);
  ok(r2.status === 201 && log.some(x => x.includes('view_assigned_jobs|update_assigned_jobs|capture_load|register_signature|create_incident')), 'criar: operador de terreno com PIN de 6 dígitos recebe as permissões de terreno por omissão');
}
{
  const { d, log } = depsEq();
  const r = await equipa(pedir({ ...novo, ativo: false }), d);
  ok(r.status === 201 && log.includes('ban:true'), 'criar: funcionário criado inativo fica logo bloqueado no serviço de contas');
}
{
  const { d, log } = depsEq();
  const r = await equipa(pedir({ acao: 'atualizar', id: OUTRO, alteracoes: { ativo: false } }), d);
  ok(r.status === 200 && log.includes('ban:true'), 'atualizar: desativar → ban no serviço de contas');
  await equipa(pedir({ acao: 'atualizar', id: OUTRO, alteracoes: { ativo: true } }), d);
  ok(log.includes('ban:false'), 'atualizar: reativar → remove o ban');
  log.length = 0;
  await equipa(pedir({ acao: 'atualizar', id: OUTRO, alteracoes: { nome: 'Novo Nome' } }), d);
  ok(!log.some(x => x.startsWith('ban')), 'atualizar: alterar só o nome não mexe no ban');
}
{
  const { d } = depsEq({ async atualizar() { return { erro: 'A empresa tem de manter pelo menos um administrador ativo.' }; } });
  const r = await equipa(pedir({ acao: 'atualizar', id: ADMIN2, alteracoes: { ativo: false } }), d);
  ok(r.status === 409 && (await r.json()).erro.mensagem.includes('pelo menos um administrador'), 'atualizar: regra do último administrador devolvida ao utilizador (409)');
}
{
  const { d } = depsEq({ async definirBan() { return false; } });
  const r = await equipa(pedir({ acao: 'atualizar', id: OUTRO, alteracoes: { ativo: false } }), d); const j = await r.json();
  ok(r.status === 200 && j.funcionario.ativo === false && /bloqueio/.test(j.aviso), 'atualizar: se o ban falhar, o estado fica guardado e há aviso');
}
ok((await equipa(pedir({ acao: 'atualizar', id: 'não-é-uuid', alteracoes: { ativo: false } }), depsEq().d)).status === 400, 'atualizar: id que não é UUID → 400');
{
  const { d, log } = depsEq();
  const r = await equipa(pedir({ acao: 'repor_senha', id: ADMIN, senha: 'NovaSenha123' }), d);
  ok(r.status === 403 && (await r.json()).erro.codigo === 'propria_conta' && !log.includes('definirSenha'), 'repor_senha: a própria conta não pode ser redefinida aqui (403)');
}
{
  const { d, log } = depsEq();
  const r = await equipa(pedir({ acao: 'repor_senha', id: OUTRO, senha: 'fraca' }), d);
  ok(r.status === 400 && !log.includes('definirSenha'), 'repor_senha: palavra-passe fraca recusada');
  const r2 = await equipa(pedir({ acao: 'repor_senha', id: OUTRO, senha: 'NovaSenha123' }), d);
  ok(r2.status === 200 && log.indexOf('definirSenha') < log.indexOf('encerrarSessoes') && log.includes('auditar:repor_senha_funcionario'), 'repor_senha: altera → fecha as sessões de empresa do funcionário → audita');
}
{
  const { d, log } = depsEq();
  const r = await equipa(pedir({ acao: 'repor_senha', id: U(77), senha: 'NovaSenha123' }), d);
  ok(r.status === 404 && !log.includes('definirSenha'), 'repor_senha: funcionário que não é da empresa → 404 e nada alterado');
}
{
  const { d, log } = depsEq({ async obterFuncionario() { return fn(U(40), 'operador_terreno'); } });
  const r = await equipa(pedir({ acao: 'repor_senha', id: U(40), senha: 'Operador123' }), d);
  ok(r.status === 400 && !log.includes('definirSenha'), 'repor_senha: operador de terreno só aceita PIN numérico');
}
{
  const { d, log } = depsEq();
  const r = await equipa(pedir({ acao: 'eliminar', id: OUTRO }), d); const j = await r.json();
  ok(r.status === 200 && j.eliminado === true && log.indexOf('preparar') < log.indexOf('eliminarUtilizador') && log.includes('auditar:eliminar_funcionario'), 'eliminar: valida regras → elimina o utilizador → audita');
}
{
  const { d, log } = depsEq({ async eliminarUtilizador() { return false; } });
  const r = await equipa(pedir({ acao: 'eliminar', id: OUTRO }), d); const j = await r.json();
  ok(r.status === 200 && j.eliminado === false && j.desativado === true && log.includes('ban:true') && log.includes('auditar:arquivar_funcionario'), 'eliminar: se houver histórico associado, fica DESATIVADO e bloqueado (arquivado)');
}
{
  const { d, log } = depsEq({ async prepararRemocao() { return { erro: 'Não pode retirar o seu próprio acesso de administrador.' }; } });
  const r = await equipa(pedir({ acao: 'eliminar', id: ADMIN }), d);
  ok(r.status === 409 && !log.includes('eliminarUtilizador'), 'eliminar: regra violada (próprio / último admin) → 409 sem eliminar');
}
ok((await equipa(pedir({ acao: 'apagar_tudo' }), depsEq().d)).status === 400, 'equipa: ação desconhecida → 400');
{
  const { d } = depsEq({ async limite() { return false; } });
  ok((await equipa(pedir(novo), d)).status === 429, 'equipa: limite de pedidos por utilizador → 429');
}
{
  const { d } = depsEq({ async empresaDoAdmin() { throw new Error('select * from funcionarios: relation does not exist'); } });
  const r = await equipa(pedir(novo), d); const t = await r.text();
  ok(r.status === 503 && !t.includes('relation'), 'equipa: erro interno devolve 503 genérico, sem detalhes');
}

console.log(falhas === 0 ? '\nTODOS OS TESTES PASSARAM' : `\n${falhas} FALHA(S)`);
process.exit(falhas === 0 ? 0 : 1);
