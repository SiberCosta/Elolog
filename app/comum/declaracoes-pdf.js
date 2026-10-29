/* Elolog — os 6 modelos de declaração da encomenda, gerados em PDF no navegador (sem bibliotecas nem custos).
   Uso: elologDeclaracoesPdf.gerar(base, dados, ["viatura","bens",…]) → Blob PDF (uma página ou mais por modelo).
   base = {codigo, origem, destino, cliente:{…}, empresa:{…}} · dados = o que foi preenchido (ver declaracoes.js). */
(function(){"use strict";
/* ---- larguras Helvetica / Helvetica-Bold (1/1000), caracteres 32–126 ---- */
const W=s=>s.split(",").map(Number);
const HN=W("278,278,355,556,556,889,667,191,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,278,278,584,584,584,556,1015,667,667,722,722,667,611,778,722,278,500,667,556,833,722,778,667,778,722,667,611,722,667,944,667,667,611,278,278,278,469,556,333,556,556,500,556,556,278,556,556,222,222,500,222,833,556,556,556,556,333,500,278,556,500,722,500,500,500,334,260,334,584");
const HB=W("278,333,474,556,556,889,722,238,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,333,333,584,584,584,611,975,722,722,722,722,667,611,778,722,278,556,722,611,833,722,778,667,778,722,667,611,722,667,944,667,667,611,333,278,333,584,556,333,556,611,556,611,556,333,611,611,278,278,556,278,889,611,611,611,611,389,556,333,611,556,778,556,556,500,389,280,389,584");
const CP={"€":128,"‚":130,"„":132,"…":133,"‘":145,"’":146,"“":147,"”":148,"•":149,"–":150,"—":151,"™":153};
const byte=ch=>{const c=ch.charCodeAt(0);return c<256?c:(CP[ch]||63)};
function largura(t,tam,neg){let w=0;for(const ch of String(t)){const b=ch.normalize("NFD")[0].charCodeAt(0),tab=neg?HB:HN;w+=b>=32&&b<=126?tab[b-32]:(ch==="€"?556:500)}return w*tam/1000}
const pdfTxt=t=>Array.from(String(t),ch=>{const b=byte(ch);return b===40||b===41||b===92?"\\"+ch:String.fromCharCode(b)}).join("");

/* ---- documento: páginas A4, cursor vertical, quebra automática ---- */
function Doc(){const P=[];let ops=null,y=0;const M=50,L=495;
  const d={M,L,get y(){return y},
    pagina(){ops=[];P.push(ops);y=792},
    precisa(h){if(y-h<70)d.pagina()},
    txt(x,yy,t,tam=10,neg=false,cor="0.09 0.19 0.26"){ops.push(`BT ${cor} rg /${neg?"F2":"F1"} ${tam} Tf ${x.toFixed(1)} ${yy.toFixed(1)} Td (${pdfTxt(t)}) Tj ET`)},
    linha(x1,y1,x2,y2,cor="0.82 0.86 0.89",esp=0.6){ops.push(`${cor} RG ${esp} w ${x1} ${y1} m ${x2} ${y2} l S`)},
    ret(x,yy,w,h,cor){ops.push(`${cor} rg ${x} ${yy} ${w} ${h} re f`)},
    partir(t,tam,max,neg){const out=[];for(const par of String(t??"").split("\n")){let l="";for(const p of par.split(/\s+/)){const n=l?l+" "+p:p;if(l&&largura(n,tam,neg)>max){out.push(l);l=p}else l=n}out.push(l)}return out},
    par(t,{tam=10,neg=false,antes=4,entre=1.45}={}){y-=antes;for(const l of d.partir(t,tam,L,neg)){d.precisa(tam*entre);y-=tam*entre;d.txt(M,y,l,tam,neg)}},
    titulo(t,sub){d.precisa(60);y-=22;d.txt(M,y,t,16,true);if(sub){y-=16;d.txt(M,y,sub,9,false,"0.42 0.49 0.54")}y-=10;d.linha(M,y,M+L,y,"0.14 0.38 0.53",1.2);y-=6},
    seccao(t){d.precisa(40);y-=16;d.txt(M,y,t.toUpperCase(),8.5,true,"0.14 0.38 0.53");y-=5},
    campos(lista){const k=150;for(const[r,v]of lista){const ls=d.partir(v||"—",9.5,L-k-8,false),h=ls.length*13+6;d.precisa(h);y-=13;d.txt(M,y,r,9,true,"0.29 0.36 0.42");
      ls.forEach((l,i)=>d.txt(M+k,y-i*13,l,9.5));y-=h-13;d.linha(M,y+2,M+L,y+2)}},
    tabela(cab,larg,linhas,alinhar=[]){const x=[M];larg.forEach((w,i)=>x.push(x[i]+w));const cel=(vals,neg)=>{d.precisa(18);y-=14;vals.forEach((v,i)=>{let t=String(v??"");while(t.length>1&&largura(t,9,neg)>larg[i]-8)t=t.slice(0,-2)+"…";
      d.txt(alinhar[i]==="d"?x[i+1]-4-largura(t,9,neg):x[i]+4,y,t,9,neg)});y-=4;d.linha(M,y,M+L,y)};
      d.precisa(30);d.ret(M,y-18,L,18,"0.93 0.95 0.97");cel(cab,true);linhas.forEach(l=>cel(l,false))},
    assinaturas(nomes){if(d.quando)d.par(d.quando,{antes:14,tam:9.5});d.precisa(90);y-=50;const w=(L-30*(nomes.length-1))/nomes.length;nomes.forEach((n,i)=>{const x=M+i*(w+30);d.linha(x,y,x+w,y,"0.3 0.36 0.4",0.8);d.txt(x,y-12,n,8.5,false,"0.29 0.36 0.42")});y-=20},
    espaco(h){y-=h},
    blob(cabecalho,rodape){const n=P.length;P.forEach((o,i)=>{o.unshift(...cabecalho(i,n));o.push(...rodape(i,n))});
      const objs=["<< /Type /Catalog /Pages 2 0 R >>",null,"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>","<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>"],kids=[];
      P.forEach(o=>{const s=o.join("\n");objs.push(`<< /Length ${s.length} >>\nstream\n${s}\nendstream`);objs.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ${objs.length} 0 R >>`);kids.push(objs.length+" 0 R")});
      objs[1]=`<< /Type /Pages /Kids [${kids.join(" ")}] /Count ${n} >>`;let pdf="%PDF-1.4\n",off=[];objs.forEach((o,i)=>{off.push(pdf.length);pdf+=`${i+1} 0 obj\n${o}\nendobj\n`});
      const xref=pdf.length;pdf+=`xref\n0 ${objs.length+1}\n0000000000 65535 f \n${off.map(o=>String(o).padStart(10,"0")+" 00000 n \n").join("")}trailer\n<< /Size ${objs.length+1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
      const u=new Uint8Array(pdf.length);for(let i=0;i<pdf.length;i++)u[i]=pdf.charCodeAt(i)&255;return new Blob([u],{type:"application/pdf"})}};
  return d}

/* ---- dados comuns ---- */
const eur=v=>Number(v||0).toLocaleString("pt-PT",{style:"currency",currency:"EUR"});
const num=v=>Number(String(v??"").replace(/\s/g,"").replace(",","."))||0;
const quem=p=>[p.nome,p.documento&&("doc. "+p.documento),p.nif&&("NIF "+p.nif)].filter(Boolean).join(", ")||"—";
const viaturaTxt=v=>[v.marca,v.modelo,v.ano&&("("+v.ano+")"),v.matricula&&("matrícula "+v.matricula)].filter(Boolean).join(" ")||"viatura";
function contas(d){const bens=(d.bens||[]).filter(b=>b&&(b.descricao||num(b.valor))),vb=bens.reduce((s,b)=>s+num(b.valor),0),vv=d.viatura?.inclui?num(d.viatura.valor):0;return{bens,vb,vv,total:vb+vv}}
const FIN={pessoal:"uso pessoal e familiar",mudanca:"mudança de residência",oferta:"oferta a familiares",comercial:"fins comerciais"};
const finalidade=d=>d.finalidade==="outra"?(d.finalidade_texto||"outra finalidade"):(FIN[d.finalidade]||FIN.pessoal);

const MODELOS=[
 {id:"viatura",n:1,nome:"Declaração de identificação da viatura",so:d=>!!d.viatura?.inclui,f(D,b,d){const v=d.viatura||{},p=d.proprietario||{},q=d.destinatario||{};
   D.seccao("Viatura");D.campos([["Matrícula",v.matricula],["Marca",v.marca],["Modelo",v.modelo],["VIN / n.º de chassis",v.vin],["Ano",v.ano],["Combustível",v.combustivel],["Cilindrada",v.cilindrada&&(v.cilindrada+" cm³")],["Cor",v.cor],["Valor estimado",v.valor?eur(v.valor):""]]);
   D.seccao("Proprietário");D.campos([["Nome",p.nome],["Documento / NIF",[p.documento,p.nif&&"NIF "+p.nif].filter(Boolean).join(" · ")],["Morada",p.morada],["Contacto",[p.telefone,p.email].filter(Boolean).join(" · ")]]);
   D.seccao("Destinatário");D.campos([["Nome",q.nome],["Documento",q.documento],["Morada",[q.morada,q.cidade].filter(Boolean).join(", ")],["Contacto",q.telefone]]);
   D.par(`Declaro que a viatura acima identificada é exportada de ${b.origem||"—"} para ${b.destino||"—"} no âmbito do processo ${b.codigo}.`,{antes:12});D.assinaturas(["O proprietário"])}},
 {id:"bens",n:2,nome:"Declaração de bens no interior da viatura",titulo:d=>d.viatura?.inclui?null:"Declaração de bens transportados",f(D,b,d){const c=contas(d);
   D.par(d.viatura?.inclui?`Bens transportados no interior da viatura ${viaturaTxt(d.viatura)}.`:"Bens incluídos na carga deste processo.",{antes:2});D.espaco(6);
   D.tabela(["#","Descrição","Qtd.","Estado","Valor"],[28,247,50,85,85],c.bens.map((x,i)=>[i+1,x.descricao,x.quantidade||1,x.estado||"Usado",eur(x.valor)]).concat([["","Total","","",eur(c.vb)]]),["","","d","","d"]);
   D.par(`Declaro que os bens acima são todos os que seguem ${d.viatura?.inclui?"no interior da viatura":"na carga"} e que os valores indicados são estimativas razoáveis.`,{antes:12});D.assinaturas(["O proprietário"])}},
 {id:"valor",n:3,nome:"Declaração de conteúdo e valor",f(D,b,d){const c=contas(d);
   D.tabela(["Conteúdo","Detalhe","Valor"],[150,230,115],[...(d.viatura?.inclui?[["Viatura",viaturaTxt(d.viatura),eur(c.vv)]]:[]),["Bens",c.bens.length+" linha(s) — ver declaração de bens",eur(c.vb)],["Valor total declarado","",eur(c.total)]],["","","d"]);
   D.seccao("Finalidade do envio");D.par(`O envio destina-se a ${finalidade(d)}.`);D.par(`Declaro que o conteúdo deste processo (${b.codigo}) é o descrito acima e que o valor total declarado é de ${eur(c.total)}.`,{antes:10});D.assinaturas(["O proprietário"])}},
 {id:"propriedade",n:4,nome:"Declaração de propriedade e finalidade",f(D,b,d){const p=d.proprietario||{},q=d.destinatario||{},v=d.viatura||{};
   D.par(`Eu, ${p.nome||"________________"}${p.documento?", portador(a) do documento "+p.documento:""}${p.nif?", NIF "+p.nif:""}${p.morada?", residente em "+p.morada:""}, declaro ser o(a) legítimo(a) proprietário(a) ${v.inclui?"da viatura "+viaturaTxt(v)+" e ":""}dos bens descritos no processo ${b.codigo}.`,{antes:8});
   D.par(`Declaro que se destinam a ${finalidade(d)} e não a revenda${d.finalidade==="comercial"?" (exceto o indicado como fins comerciais)":""}.`,{antes:8});
   D.seccao("Destinatário");D.campos([["Nome",q.nome],["Documento",q.documento],["Morada",[q.morada,q.cidade].filter(Boolean).join(", ")],["Destino",b.destino],["Contacto",q.telefone]]);D.assinaturas(["O proprietário"])}},
 {id:"responsabilidade",n:5,nome:"Declaração de responsabilidade",f(D,b,d){const p=d.proprietario||{},c=contas(d);
   D.par(`Eu, ${quem(p)}, declaro sob compromisso de honra que todas as informações prestadas no processo ${b.codigo} — identificação do proprietário e do destinatário${d.viatura?.inclui?", dados da viatura":""}, lista de bens (${c.bens.length} linha(s)) e valores (total declarado ${eur(c.total)}) — são verdadeiras e completas.`,{antes:8});
   D.par("Declaro que a carga não contém bens proibidos, perigosos ou sujeitos a licença sem a respetiva autorização, e assumo a responsabilidade por qualquer informação incorreta ou omissa, bem como pelos encargos que daí resultem.",{antes:8});
   D.par(`Destinatário: ${quem(d.destinatario||{})}.`,{antes:8});D.assinaturas(["O declarante"])}},
 {id:"processo",n:6,nome:"Folha de processo de exportação e transporte",f(D,b,d){const e=d.embarque||{},c=contas(d);
   D.seccao("Processo");D.campos([["Referência",b.codigo],["Cliente",quem({nome:b.cliente?.nome,nif:b.cliente?.nif})],["Prestador",quem({nome:b.empresa?.nome,nif:b.empresa?.nif})],["Proprietário",quem(d.proprietario||{})],["Destinatário",quem(d.destinatario||{})]]);
   D.seccao("Transporte");D.campos([["Porto de saída",e.porto_saida||b.origem],["Porto de destino",e.porto_destino||b.destino],["Transportadora",e.transportadora],["Navio / viagem",e.navio],["Contentor",e.contentor],["Conhecimento de embarque (BL)",e.bl],["Data de embarque",e.data_embarque&&e.data_embarque.split("-").reverse().join("/")]]);
   D.seccao("Carga");D.campos([["Viatura",d.viatura?.inclui?viaturaTxt(d.viatura):"Sem viatura"],["Bens",c.bens.length+" linha(s)"],["Valor total declarado",eur(c.total)],["Documentos anexos",e.anexos]]);D.assinaturas(["Pelo prestador","O cliente"])}}];

function gerar(base,dados,ids){const D=Doc(),lista=MODELOS.filter(m=>(!ids||ids.includes(m.id))&&(!m.so||m.so(dados)));if(!lista.length)throw new Error("Escolha pelo menos um modelo.");
  const local=dados.local||"",data=(dados.data||new Date().toISOString().slice(0,10)).split("-").reverse().join("/");
  D.quando=`${local?local+", ":""}${data}`;lista.forEach(m=>{D.pagina();D.titulo((m.titulo&&m.titulo(dados))||m.nome,`Modelo ${m.n} · Processo ${base.codigo} · ${base.origem||"—"} – ${base.destino||"—"}`);m.f(D,base,dados)});
  return D.blob(()=>["0.055 0.141 0.2 rg 0 812 595 30 re f",`BT 1 1 1 rg /F2 12 Tf 50 822 Td (ELOLOG) Tj ET`,`BT 0.75 0.84 0.9 rg /F1 8 Tf 112 822.5 Td (${pdfTxt("Intermediação e Gestão Logística")}) Tj ET`,`BT 0.75 0.84 0.9 rg /F1 8 Tf ${(545-largura(base.codigo,8)).toFixed(1)} 822.5 Td (${pdfTxt(base.codigo)}) Tj ET`],
    (i,n)=>["0.82 0.86 0.89 RG 0.6 w 50 48 m 545 48 l S",`BT 0.42 0.49 0.54 rg /F1 7.5 Tf 50 36 Td (${pdfTxt("Documento interno de apoio ao processo — não substitui documentos aduaneiros oficiais. · www.elolog.pt")}) Tj ET`,`BT 0.42 0.49 0.54 rg /F1 7.5 Tf 505 36 Td (${pdfTxt(`Pág. ${i+1}/${n}`)}) Tj ET`])}
window.elologDeclaracoesPdf={MODELOS,gerar,contas,largura};
})();
