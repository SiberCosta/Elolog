// Lógica de "registar-prestador", separada do arranque (index.ts) para poder ser testada sem Deno nem rede.
import { erro, lerJson, preflight, resposta } from '../_shared/http.ts';
import { hashChave, ipDoPedido, validarRegisto, type DadosRegisto } from '../_shared/validar.ts';

export type FalhaUtilizador = { erro: 'existe' | 'invalido' | 'falha' };
export type FalhaRegisto = { erro: 'nif_duplicado' | 'plano' | 'falha' };

export interface DepsRegisto {
  /** Janela deslizante por chave (já hasheada). false = excedido. Lança se a base de dados falhar. */
  limite(chave: string, max: number, janelaMin: number): Promise<boolean>;
  utilizadorExiste(email: string): Promise<boolean>;
  /** Cria o utilizador de autenticação do administrador (envia confirmação por e-mail se o projeto o exigir). */
  criarUtilizador(email: string, senha: string, nome: string): Promise<{ id: string; exigeConfirmacao: boolean } | FalhaUtilizador>;
  /** Chama servico_registar_prestador (atómico). */
  registar(d: DadosRegisto & { userId: string }): Promise<{ empresaId: string } | FalhaRegisto>;
  apagarUtilizador(id: string): Promise<void>;
}

export async function tratar(req: Request, deps: DepsRegisto): Promise<Response> {
  if (req.method === 'OPTIONS') return preflight();
  if (req.method !== 'POST') return erro(405, 'metodo', 'Método não permitido.');

  try {
    const corpo = await lerJson(req);
    if (!corpo.ok) return corpo.resp;
    const v = validarRegisto(corpo.valor);
    if (!v.ok) return erro(400, 'dados_invalidos', v.erro);
    const d = v.dados;

    // Limites: o IP é só uma camada (pode ser influenciado); NIF e e-mail não dependem dele.
    const chaves: [string, number][] = [
      [`reg:ip:${ipDoPedido(req.headers)}`, 10],
      [`reg:nif:${d.nif.toLowerCase().replace(/\s+/g, '')}`, 5],
      [`reg:email:${d.adminEmail}`, 5],
    ];
    for (const [chave, max] of chaves) {
      if (!(await deps.limite(await hashChave(chave), max, 60))) {
        return erro(429, 'demasiadas_tentativas', 'Demasiadas tentativas. Tente novamente dentro de uma hora.');
      }
    }

    if (await deps.utilizadorExiste(d.adminEmail)) {
      return erro(409, 'email_existe', 'Este e-mail já está associado a uma conta. Use outro e-mail para o administrador.');
    }

    const criado = await deps.criarUtilizador(d.adminEmail, d.adminSenha, d.adminNome);
    if ('erro' in criado) {
      if (criado.erro === 'existe') return erro(409, 'email_existe', 'Este e-mail já está associado a uma conta. Use outro e-mail para o administrador.');
      if (criado.erro === 'invalido') return erro(400, 'conta_recusada', 'O servidor de contas recusou o e-mail ou a palavra-passe do administrador.');
      return erro(500, 'falha', 'Não foi possível criar a conta. Tente novamente.');
    }

    const reg = await deps.registar({ ...d, userId: criado.id });
    if ('erro' in reg) {
      // Sem registo da empresa não pode ficar uma conta de autenticação "órfã".
      try { await deps.apagarUtilizador(criado.id); } catch (e) { console.error('registar-prestador: não foi possível apagar o utilizador órfão', criado.id, e); }
      if (reg.erro === 'nif_duplicado') return erro(409, 'nif_existe', 'Já existe uma empresa registada com este NIF.');
      if (reg.erro === 'plano') return erro(400, 'plano_indisponivel', 'O plano escolhido não está disponível. Escolha outro plano.');
      return erro(500, 'falha', 'Não foi possível concluir o registo. Tente novamente.');
    }

    return resposta(201, { ok: true, pendente: true, confirmarEmail: criado.exigeConfirmacao });
  } catch (e) {
    console.error('registar-prestador: erro inesperado', e);
    return erro(503, 'indisponivel', 'Serviço temporariamente indisponível. Tente novamente.');
  }
}
