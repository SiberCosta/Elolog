/* Elolog — Centro Documental (v123): imprimir em A4 e descarregar em PDF, a partir do MESMO HTML do modelo.
   Bibliotecas gratuitas, carregadas só quando são precisas (cdnjs, já permitido na política de conteúdo):
   qrcode-generator (QR), html2canvas (fotografia da página) e jsPDF (ficheiro PDF). O PDF é uma imagem da página: não se edita. */
(function(){"use strict";
const CDN="https://cdnjs.cloudflare.com/ajax/libs/";
const LIBS={qr:[CDN+"qrcode-generator/1.4.4/qrcode.min.js",()=>window.qrcode],canvas:[CDN+"html2canvas/1.4.1/html2canvas.min.js",()=>window.html2canvas],
  pdf:[CDN+"jspdf/2.5.1/jspdf.umd.min.js",()=>window.jspdf?.jsPDF]};
const pendentes={};
function carregar(nome){const[url,obter]=LIBS[nome];if(obter())return Promise.resolve(obter());
  return pendentes[nome]||=new Promise((ok,falha)=>{const s=document.createElement("script");s.src=url;s.async=true;s.crossOrigin="anonymous";
    s.onload=()=>obter()?ok(obter()):falha(new Error("Não conseguimos carregar a biblioteca "+nome+"."));
    s.onerror=()=>{delete pendentes[nome];s.remove();falha(new Error("Sem ligação para preparar o documento. Verifique a internet e tente outra vez."))};document.head.appendChild(s)})}
const qr=()=>carregar("qr").catch(()=>null);   // sem QR o documento abre na mesma, com o código escrito por extenso

const absoluto=u=>new URL(u,location.href).href;
const css=()=>absoluto("comum/centro-doc-folha.css?v=128");
const imagensProntas=raiz=>Promise.all([...raiz.querySelectorAll("img")].map(i=>i.complete&&i.naturalWidth?null:new Promise(r=>{i.onload=i.onerror=r;setTimeout(r,4000)})));

/* imprimir: uma moldura escondida só com as folhas A4; o diálogo de impressão do navegador também permite «Guardar como PDF» */
async function imprimir(paginas,titulo){await qr();const f=document.createElement("iframe");f.title="Impressão";f.setAttribute("aria-hidden","true");
  f.style.cssText="position:fixed;right:0;bottom:0;width:0;height:0;border:0;visibility:hidden";document.body.appendChild(f);
  const d=f.contentDocument;d.open();d.write(`<!doctype html><html lang="pt-PT"><head><meta charset="utf-8"><title>${window.elologDocModelo.esc(titulo)}</title><link rel="stylesheet" href="${css()}"></head><body>${paginas.join("")}</body></html>`);d.close();
  await new Promise(r=>{const l=d.querySelector("link");if(l.sheet)r();else{l.onload=l.onerror=r;setTimeout(r,3000)}});await imagensProntas(d);
  d.querySelectorAll(".edoc").forEach(f=>{const h=f.scrollHeight;if(h>1124)f.style.zoom=String(1123/h)});   // folha mais alta que o A4: reduz em vez de cortar
  const w=f.contentWindow,limpar=()=>{if(f.isConnected)f.remove()};w.addEventListener("afterprint",()=>setTimeout(limpar,300));w.focus();w.print();window.focus();setTimeout(limpar,60000)}

/* PDF: cada folha é desenhada a 2× (nítida em papel) e colocada numa página A4 */
async function pdf(paginas,nome){await qr();const[h2c,JsPDF]=await Promise.all([carregar("canvas"),carregar("pdf")]);
  const caixa=document.createElement("div");caixa.className="cdoc-render";caixa.setAttribute("aria-hidden","true");
  caixa.style.cssText="position:fixed;left:-12000px;top:0;width:794px;background:#fff;z-index:-1";caixa.innerHTML=paginas.join("");document.body.appendChild(caixa);
  try{await imagensProntas(caixa);if(document.fonts?.ready)await document.fonts.ready;
    const doc=new JsPDF({unit:"mm",format:"a4",orientation:"portrait",compress:true});const folhas=[...caixa.querySelectorAll(".edoc")];
    for(let i=0;i<folhas.length;i++){const c=await h2c(folhas[i],{scale:2,backgroundColor:"#ffffff",useCORS:true,logging:false,windowWidth:794,scrollX:0,scrollY:0});
      if(i)doc.addPage();const k=Math.min(1,1123/Math.max(1123,folhas[i].scrollHeight)),w=210*k;   // mais alta que o A4: reduz sem deformar
      doc.addImage(c.toDataURL("image/jpeg",0.92),"JPEG",(210-w)/2,0,w,297,undefined,"FAST")}
    doc.setProperties({title:nome.replace(/\.pdf$/i,""),creator:"Elolog",subject:"Documento emitido pela plataforma Elolog"});
    const blob=doc.output("blob"),a=document.createElement("a");a.href=URL.createObjectURL(blob);a.download=nome;document.body.appendChild(a);a.click();
    setTimeout(()=>{URL.revokeObjectURL(a.href);a.remove()},30000);return blob}
  finally{caixa.remove()}}

window.elologDocPdf={carregar,qr,imprimir,pdf};
})();
