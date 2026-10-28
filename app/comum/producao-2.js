/* Elolog — produção 2/3: faturas certificadas. A Elolog não emite faturas: a empresa carrega o PDF do seu programa
   certificado pela AT; aqui lê-se o código QR (Portaria 195/2020), mostra-se o resumo e só depois se regista.
   O servidor (registar_fatura) volta a validar tudo. Bibliotecas gratuitas carregadas só quando são precisas: pdf.js e jsQR. */
(function(){
  const P=()=>window.elologProducao;
  const LIB={qr:"https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.min.js",pdf:"https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js",
    worker:"https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js"};
  const TIPOS={FT:"Fatura",FR:"Fatura-recibo",FS:"Fatura simplificada",NC:"Nota de crédito",ND:"Nota de débito"};
  const carregar=(src,pronto)=>pronto()?Promise.resolve():new Promise((ok,ko)=>{const s=document.createElement("script");s.src=src;const erro=()=>ko(new Error("Sem ligação à internet para ler o código QR."));
    s.onload=()=>{let n=0;const ver=()=>pronto()?ok():++n>50?erro():setTimeout(ver,100);ver()};s.onerror=erro;document.head.appendChild(s)});

  /** NIF português: 9 dígitos com dígito de controlo. */
  function nifValido(n){n=String(n||"").replace(/^PT/i,"");if(n==="999999990")return true;if(!/^[1-9]\d{8}$/.test(n))return false;
    let s=0;for(let i=0;i<8;i++)s+=Number(n[i])*(9-i);let d=11-(s%11);if(d>=10)d=0;return d===Number(n[8])}
  /** Texto do QR da AT («A:…*B:…*…») → campos. */
  function lerCampos(qr){const m={};String(qr||"").split("*").forEach(p=>{const i=p.indexOf(":");if(i>0)m[p.slice(0,i).trim()]=p.slice(i+1).trim()});return m}
  /** Verifica os campos antes de enviar; devolve {dados, erros}. */
  function verificar(qr,nifEmpresa){const m=lerCampos(qr),erros=[];
    ["A","B","D","F","G","H","O"].forEach(k=>{if(!m[k])erros.push(`Falta o campo ${k} no QR.`)});
    const data=/^\d{8}$/.test(m.F||"")?`${m.F.slice(0,4)}-${m.F.slice(4,6)}-${m.F.slice(6)}`:"";const total=Number(m.O);
    if(m.A&&nifEmpresa&&m.A.replace(/^PT/i,"")!==String(nifEmpresa).replace(/^PT/i,""))erros.push(`O NIF do emitente (${m.A}) não é o da empresa.`);
    if(m.B&&!nifValido(m.B))erros.push(`O NIF do cliente (${m.B}) não é válido.`);
    if(m.D&&!TIPOS[m.D])erros.push(`Tipo de documento não aceite: ${m.D}.`);
    if(m.E==="A")erros.push("Esta fatura está anulada.");
    if(m.H&&!/^[A-Z0-9]{8,}-\d+$/.test(m.H))erros.push(`ATCUD inválido: ${m.H}.`);
    if(data&&new Date(data)>new Date())erros.push("A data da fatura é futura.");
    if(m.O&&!(total>=0))erros.push("Total ilegível.");
    return{dados:{tipo:TIPOS[m.D]||m.D||"—",numero:m.G||"—",atcud:m.H||"—",data,nifEmitente:m.A||"—",nifCliente:m.B||"—",iva:Number(m.N||0),total},erros}}

  function decifrar(canvas){const ctx=canvas.getContext("2d",{willReadFrequently:true});const d=ctx.getImageData(0,0,canvas.width,canvas.height);
    const r=window.jsQR(d.data,d.width,d.height,{inversionAttempts:"attemptBoth"});return r&&/(^|\*)A:/.test(r.data)?r.data:null}
  async function lerQr(file){await carregar(LIB.qr,()=>window.jsQR);
    if(file.type==="application/pdf"){await carregar(LIB.pdf,()=>window.pdfjsLib);window.pdfjsLib.GlobalWorkerOptions.workerSrc=LIB.worker;
      const pdf=await window.pdfjsLib.getDocument({data:await file.arrayBuffer()}).promise;
      for(let n=1;n<=Math.min(pdf.numPages,3);n++){const pg=await pdf.getPage(n);for(const escala of[2,3.2]){const vp=pg.getViewport({scale:escala}),c=document.createElement("canvas");
        c.width=vp.width;c.height=vp.height;await pg.render({canvasContext:c.getContext("2d"),viewport:vp}).promise;const r=decifrar(c);if(r)return r}}return null}
    const img=await createImageBitmap(file),c=document.createElement("canvas");c.width=img.width;c.height=img.height;c.getContext("2d").drawImage(img,0,0);return decifrar(c)}

  async function abrir(){const p=P(),j=p.janela({eyebrow:"FINANCEIRO",titulo:"Registar fatura certificada",passos:["Ficheiro","Confirmar","Concluído"]}),esc=p.esc;
    let ficheiro=null,qr="",nifEmpresa="",enc="";
    if(p.online()){try{const e=await p.minhaEmpresa();if(e){const c=await p.sb();const{data}=await c.from("empresas").select("nif").eq("id",e.empresa_id).maybeSingle();nifEmpresa=data?.nif||""}}catch(_){}}
    const passo1=(msg)=>{j.passo(0);j.mostrar(`<p class="pm-nota">Carregue o PDF (ou uma fotografia nítida) da fatura emitida pelo seu programa certificado. A plataforma lê o código QR e confirma o NIF, o ATCUD e o total.</p>
      <div class="pm-grelha"><label>Encomenda (código)<input id="pmFatEnc" maxlength="40" placeholder="Ex.: ELO_TRAN-000185" value="${esc(enc)}"></label><label>Ficheiro da fatura<input id="pmFatFich" type="file" accept="application/pdf,image/png,image/jpeg" required></label></div>
      ${msg?`<div class="pm-alerta">${esc(msg)}</div><label class="pm-largo">Texto do código QR (copie do seu programa de faturação)<textarea id="pmFatQr" rows="3" placeholder="A:123456789*B:…">${esc(qr)}</textarea></label>`:""}`,
      [{texto:"Cancelar",acao:j.fechar},{texto:"Ler fatura",principal:true,acao:async()=>{enc=document.getElementById("pmFatEnc").value.trim();
        const f=document.getElementById("pmFatFich").files[0]||ficheiro;if(!f&&!window.eloValidar(["pmFatFich"]))return;ficheiro=f;
        const manual=document.getElementById("pmFatQr")?.value.trim();if(manual){qr=manual;return passo2()}
        try{qr=await lerQr(ficheiro)||""}catch(e){return passo1(/internet/.test(e.message)?e.message+" Cole o texto do QR em baixo.":"Não conseguimos ler este ficheiro. Cole o texto do QR em baixo.")}
        if(!qr)return passo1("Não encontrámos o código QR no ficheiro. Cole o texto do QR em baixo.");passo2()}}])};
    const passo2=()=>{j.passo(1);const{dados:d,erros}=verificar(qr,nifEmpresa);
      j.mostrar(`<dl class="pm-resumo"><div><dt>Documento</dt><dd>${esc(d.tipo)} ${esc(d.numero)}</dd></div><div><dt>ATCUD</dt><dd>${esc(d.atcud)}</dd></div>
        <div><dt>Data</dt><dd>${esc(d.data||"—")}</dd></div><div><dt>NIF do emitente</dt><dd>${esc(d.nifEmitente)}</dd></div><div><dt>NIF do cliente</dt><dd>${esc(d.nifCliente)}</dd></div>
        <div><dt>Encomenda</dt><dd>${esc(enc||"sem encomenda")}</dd></div><div><dt>IVA</dt><dd>${p.euros(d.iva)}</dd></div><div class="pm-total"><dt>Total</dt><dd>${p.euros(d.total)}</dd></div></dl>
        ${erros.length?`<div class="pm-alerta" role="alert"><strong>Corrija antes de registar:</strong><ul>${erros.map(e=>`<li>${esc(e)}</li>`).join("")}</ul></div>`:`<p class="pm-nota">Confirme os dados. Depois de registada, a fatura fica visível para o cliente${enc?" na encomenda "+esc(enc):""}.</p>`}`,
        [{texto:"Voltar",acao:()=>passo1()},...(erros.length?[]:[{texto:"Registar fatura",principal:true,acao:registar}])])};
    const registar=async()=>{
      if(!p.online()){const doc={id:"DOC-"+Date.now(),operationId:enc,name:"Fatura "+lerCampos(qr).G,fileName:ficheiro.name,mimeType:ficheiro.type,category:"Fatura",uploadedByRole:"prestador",
        createdAt:new Date().toISOString(),status:"Fatura certificada",qr};try{doc.fileData=await new Promise((ok,ko)=>{const r=new FileReader;r.onload=()=>ok(r.result);r.onerror=ko;r.readAsDataURL(ficheiro)})}catch(_){}
        if(typeof documents!=="undefined"&&Array.isArray(documents)){documents.unshift(doc);try{saveAll()}catch(_){}}return concluido("Modo de demonstração: a fatura ficou guardada só neste navegador.")}
      try{const doc=await p.enviarDocumento(ficheiro,{encomenda:enc,categoria:"fatura",visibilidade:"interna"});const en=enc?await p.encomendaPorCodigo(enc):null;
        const c=await p.sb();const{error}=await c.rpc("registar_fatura",{p_documento:doc.id,p_qr:qr,p_encomenda:en?.id||null});if(error)throw new Error(error.message);
        concluido("A fatura ficou registada e o cliente recebeu um aviso.")}catch(e){p.aviso(e.message,"error")}};
    const concluido=msg=>{j.passo(2);j.mostrar(`<div class="pm-sucesso" role="status"><strong>Fatura registada</strong><p>${esc(msg)}</p></div>`,[{texto:"Registar outra",acao:()=>{ficheiro=null;qr="";passo1()}},{texto:"Concluir",principal:true,acao:j.fechar}]);
      try{window.renderProviderDocumentos?.()}catch(_){}};
    passo1()}
  window.elologFaturas={abrir,verificar,lerCampos,nifValido};
})();
