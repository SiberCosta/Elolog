/* Elolog — página pública «Validar documento» (v123). Envia o código do QR à função «validar-documento» e mostra só o que não é confidencial:
   tipo, número, versão, estado, data de emissão, encomenda e empresa emissora, com as duas marcas (Elolog + prestador). */
(function () {
  "use strict";
  const cfg = window.ELOLOG_SERVIDOR || {};
  const form = document.getElementById("valForm"), campo = document.getElementById("valCodigo"), bt = document.getElementById("valBotao"), out = document.getElementById("resultado");
  const NOMES = { guia: "Guia de encomenda", rececao: "Guia de receção", pagamento: "Comprovativo de pagamento" };
  const limpo = v => String(v || "").toLowerCase().replace(/[^0-9a-f]/g, "");
  const el = (tag, props, filhos) => { const e = document.createElement(tag); Object.assign(e, props || {}); (filhos || []).forEach(f => e.append(f)); return e; };
  const par = (rotulo, valor) => el("div", {}, [el("dt", { textContent: rotulo }), el("dd", { textContent: valor })]);
  const data = v => { const d = new Date(v); return isNaN(d) ? "" : d.toLocaleString("pt-PT", { dateStyle: "long", timeStyle: "short" }); };

  function veredito(classe, titulo, texto) { return el("div", { className: "veredito " + classe }, [el("strong", { textContent: titulo }), el("p", { textContent: texto })]); }

  function mostrar(r) {
    out.replaceChildren();
    if (!r || !r.encontrado) {
      out.append(veredito("erro", "Documento não encontrado", "Este código não corresponde a nenhum documento emitido pela Elolog. Confirme o código impresso por baixo do QR. Se estiver certo, o documento pode ter sido falsificado: contacte o prestador indicado no papel."));
      return;
    }
    const atual = r.estado === "valido", antigo = Number(r.versao_atual) > Number(r.versao);
    if (atual) out.append(veredito("ok", "Documento autêntico e em vigor", `${NOMES[r.tipo] || "Documento"} ${r.numero}, versão ${r.versao}. Os dados deste documento foram registados na Elolog no momento da emissão.`));
    else if (r.estado === "anulado") out.append(veredito("erro", "Documento anulado", "Este documento foi emitido pela Elolog mas já não é válido. Peça ao prestador o documento correto."));
    else out.append(veredito("aviso", "Documento autêntico, mas substituído", `Existe uma versão mais recente (versão ${r.versao_atual}). Peça ao prestador ou ao cliente a versão em vigor antes de a usar.`));
    const marcas = el("div", { className: "duas" }, [el("img", { src: "../partilhado/imagens/elolog-logo.svg", alt: "Elolog" })]);
    if (typeof r.logotipo === "string" && /^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(r.logotipo)) marcas.append(el("img", { src: r.logotipo, alt: r.empresa || "Prestador" }));
    else if (r.empresa) marcas.append(el("strong", { textContent: r.empresa }));
    out.append(marcas, el("dl", {}, [par("Documento", NOMES[r.tipo] || r.tipo), par("Número", r.numero), par("Versão", antigo ? `${r.versao} (a mais recente é a ${r.versao_atual})` : String(r.versao)),
      par("Emitido em", data(r.emitido_em)), par("Encomenda", r.referencia || ""), par("Emitido por", r.empresa || ""), par("Impressão digital", String(r.sha256 || "").slice(0, 16))]),
      el("p", {}, [el("small", { textContent: "Compare com o papel: o número, a versão e a impressão digital têm de ser iguais." })]));
  }

  async function validar(codigo) {
    const c = limpo(codigo);
    if (c.length !== 24) { out.replaceChildren(veredito("erro", "Código incompleto", "O código tem 24 letras e números (de 0 a 9 e de a a f), impressos por baixo do QR.")); campo.focus(); return; }
    bt.disabled = true; bt.textContent = "A validar…"; out.replaceChildren(el("p", { textContent: "A confirmar o documento…" }));
    try {
      const r = await fetch(String(cfg.supabaseUrl || "").replace(/\/+$/, "") + "/functions/v1/validar-documento", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ c }) });
      const j = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(j?.erro?.mensagem || "Não conseguimos validar agora. Tente outra vez daqui a pouco.");
      mostrar(j);
    } catch (e) {
      out.replaceChildren(veredito("erro", "Não foi possível validar", /fetch|network|load failed/i.test(e.message) ? "Sem ligação à internet. Verifique a ligação e tente outra vez." : e.message));
    } finally { bt.disabled = false; bt.textContent = "Validar"; }
  }

  form.addEventListener("submit", e => { e.preventDefault(); validar(campo.value); });
  const inicial = new URLSearchParams(location.search).get("c");
  if (inicial) { campo.value = limpo(inicial).replace(/(.{4})(?=.)/g, "$1 "); validar(inicial); } else campo.focus();
})();
