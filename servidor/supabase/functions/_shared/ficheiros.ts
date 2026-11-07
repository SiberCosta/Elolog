// Verificação de ficheiros pelo conteúdo (assinatura dos primeiros bytes), não pelo nome. Sem dependências.
// R5/R11: nenhum ficheiro é aceite sem verificação; tipo não permitido = recusado.

export const MAX_BYTES = 20 * 1024 * 1024;

/** Tipos permitidos e respetivas extensões. Tem de coincidir com private.tipos_ficheiro() (migração 00151). */
export const TIPOS: Record<string, string[]> = {
  'application/pdf': ['pdf'], 'image/jpeg': ['jpg', 'jpeg'], 'image/png': ['png'], 'image/webp': ['webp'],
  'application/msword': ['doc'], 'application/vnd.ms-excel': ['xls'],
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': ['docx'],
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': ['xlsx'],
};

const comeca = (b: Uint8Array, sig: number[], desde = 0) => sig.every((x, i) => b[desde + i] === x);
const OLE = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];   // .doc / .xls antigos
const ZIP = [0x50, 0x4b, 0x03, 0x04];                            // .docx / .xlsx

/** Confirma que os primeiros bytes correspondem ao tipo declarado. */
export function assinaturaValida(mime: string, b: Uint8Array): boolean {
  switch (mime) {
    case 'application/pdf': return comeca(b, [0x25, 0x50, 0x44, 0x46, 0x2d]);                 // %PDF-
    case 'image/jpeg': return comeca(b, [0xff, 0xd8, 0xff]);
    case 'image/png': return comeca(b, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    case 'image/webp': return comeca(b, [0x52, 0x49, 0x46, 0x46]) && comeca(b, [0x57, 0x45, 0x42, 0x50], 8); // RIFF....WEBP
    case 'application/msword': case 'application/vnd.ms-excel': return comeca(b, OLE);
    case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
    case 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': return comeca(b, ZIP);
    default: return false;
  }
}

/** Verifica tipo, extensão, tamanho e conteúdo. Devolve null se estiver tudo certo, ou o motivo da recusa. */
export function verificarFicheiro(nome: string, mime: string, tamanho: number, inicio: Uint8Array): string | null {
  const ext = (nome.match(/\.([A-Za-z0-9]{1,5})$/)?.[1] ?? '').toLowerCase();
  if (!TIPOS[mime]) return 'tipo de ficheiro não permitido';
  if (!TIPOS[mime].includes(ext)) return 'a extensão não corresponde ao tipo';
  if (!(tamanho > 0) || tamanho > MAX_BYTES) return 'tamanho inválido (máximo 20 MB)';
  if (!assinaturaValida(mime, inicio)) return 'o conteúdo não corresponde ao tipo declarado';
  return null;
}
