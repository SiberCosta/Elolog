/* Elolog — página «Deixar de receber» dos emails de seguimento (v109). Envia o token da ligação à função «seguimento». */
(function () {
  "use strict";
  const t = new URLSearchParams(location.search).get("t") || "";
  const bt = document.getElementById("segSair"), msg = document.getElementById("segMsg");
  const cfg = window.ELOLOG_SERVIDOR || {};
  const mostrar = (texto, tipo) => { msg.className = "msg " + tipo; msg.textContent = texto; };
  if (!/^[0-9a-f-]{36}$/i.test(t)) {
    bt.disabled = true;
    mostrar("Esta ligação não está completa. Abra-a de novo a partir do email que recebeu.", "erro");
    return;
  }
  bt.addEventListener("click", async () => {
    bt.disabled = true; bt.textContent = "A registar…";
    try {
      const r = await fetch(String(cfg.supabaseUrl || "").replace(/\/+$/, "") + "/functions/v1/seguimento", {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ acao: "sair", t })
      });
      const j = await r.json().catch(() => ({}));
      if (!r.ok || !j.ok) throw new Error(j?.erro?.mensagem || "Não conseguimos registar o pedido. Tente outra vez daqui a pouco.");
      document.getElementById("segTitulo").textContent = "Pronto, não voltamos a escrever sobre esta simulação.";
      document.getElementById("segTexto").textContent = "Se mudar de ideias, pode pedir o seguimento de novo quando enviar a próxima simulação.";
      bt.remove();
      mostrar("Pedido registado.", "ok");
    } catch (e) {
      bt.disabled = false; bt.textContent = "Tentar outra vez";
      mostrar(e.message, "erro");
    }
  });
})();
