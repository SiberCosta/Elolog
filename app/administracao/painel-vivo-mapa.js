/* Elolog — Painel ao vivo (v101): mapa do corredor atlântico em SVG próprio (sem serviços externos).
   Projeção simples lon/lat → 1200×600. Navios: posição AIS quando existe; senão posição estimada pelas datas de partida e chegada
   ao longo da rota (indicada como «estimada»). */
(function(){"use strict";
const X=lon=>(lon+32)/50*1200,Y=lat=>(46-lat)/58*600;
const norm=v=>String(v||"").normalize("NFD").replace(/[̀-ͯ]/g,"").toLowerCase().trim();
const PORTOS={lisboa:[-9.1,38.7],alverca:[-9.04,38.9],setubal:[-8.9,38.52],sines:[-8.87,37.95],leixoes:[-8.7,41.2],porto:[-8.6,41.15],matosinhos:[-8.69,41.18],
  "sao tome":[6.6,0.3],neves:[6.55,0.36],principe:[7.4,1.6],praia:[-23.5,14.9],mindelo:[-24.99,16.89],"sao vicente":[-24.99,16.89],luanda:[13.2,-8.8],lobito:[13.54,-12.35],
  bissau:[-15.6,11.86],dakar:[-17.44,14.69],"las palmas":[-15.42,28.13],funchal:[-16.91,32.65]};
function coord(cidade){const n=norm(cidade);for(const k in PORTOS)if(n===k||n.startsWith(k+",")||n.startsWith(k+" ")||n.includes(k))return PORTOS[k];return null}
const MAIN=[[550,76,540,80,516,88,492,103],[492,103,468,118,440,141,408,166],[408,166,376,190,322,221,300,248],[300,248,278,276,266,303,276,331],[276,331,286,359,310,392,360,414],
  [360,414,410,435,500,451,576,460],[576,460,652,469,758,466,816,468],[816,468,874,470,908,472,926,473]];
const PRAIA=[[550,76,534,84,496,101,456,124],[456,124,416,148,354,184,312,217],[312,217,270,250,222,304,204,322]];
const LUANDA=MAIN.concat([[926,473,936,478,964,495,984,507],[984,507,1004,519,1027,533,1044,543],[1044,543,1061,553,1078,563,1085,567]]);
function rota(destino){const d=norm(destino);return/praia|mindelo|vicente|cabo verde/.test(d)?PRAIA:/luanda|lobito|angola/.test(d)?LUANDA:MAIN}
const caminho=r=>"M"+r[0][0]+","+r[0][1]+r.map(g=>` C${g[2]},${g[3]} ${g[4]},${g[5]} ${g[6]},${g[7]}`).join("");
function ponto(r,t){t=Math.max(0,Math.min(.999,t));const n=r.length,i=Math.floor(t*n),u=t*n-i,g=r[i],m=1-u;
  return[m*m*m*g[0]+3*m*m*u*g[2]+3*m*u*u*g[4]+u*u*u*g[6],m*m*m*g[1]+3*m*m*u*g[3]+3*m*u*u*g[5]+u*u*u*g[7]]}
function progresso(v){const a=Date.parse(v.partida||""),b=Date.parse(v.chegada||"");if(isNaN(a)||isNaN(b)||b<=a)return v.em_transito?.5:.02;
  return Math.max(.02,Math.min(.99,(Date.now()-a)/(b-a)))}
/** Posição de uma viagem: [x, y, origem da posição] */
function posicao(v){if(v.ais&&v.ais.lat!=null)return[X(+v.ais.lon),Y(+v.ais.lat),"AIS"];if(!v.em_transito){const c=coord(v.origem)||PORTOS.lisboa;return[X(c[0]),Y(c[1]),"no porto"]}
  const p=ponto(rota(v.destino),progresso(v));return[p[0],p[1],"estimada"]}
const COR={normal:"#1F5F8B",chega:"#1F7A5C",atraso:"#C27A12"};
function corViagem(v){if(v.atrasada)return COR.atraso;const b=Date.parse(v.chegada||"");return!isNaN(b)&&b-Date.now()<1.5*864e5?COR.chega:COR.normal}
const esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c]);

function svg(d,sel,zoom){const vs=d.viagens||[],P=(d.portos||[]).map(p=>({...p,c:coord(p.cidade)})).filter(p=>p.c);
  const pos=vs.map(posicao);let vb="0 0 1200 600";
  if(zoom>1&&pos[sel]){const w=1200/zoom,h=600/zoom,x=Math.max(0,Math.min(1200-w,pos[sel][0]-w*.38)),y=Math.max(0,Math.min(600-h,pos[sel][1]-h/2));vb=`${x.toFixed(0)} ${y.toFixed(0)} ${w.toFixed(0)} ${h.toFixed(0)}`}
  const portos=[];const usados=new Set();P.forEach(p=>{const k=p.c.join();if(usados.has(k))return;usados.add(k);const x=X(p.c[0]),y=Y(p.c[1]),nm=esc(p.cidade.split(",")[0]),lw=nm.length*7.4+30,cima=y<120||y>540,ly=cima?y-44:y+18;
    portos.push(`<g><circle cx="${x}" cy="${y}" r="7" fill="#13293D" stroke="#fff" stroke-width="3"/><rect x="${x-lw/2}" y="${ly}" width="${lw}" height="24" rx="7" fill="#fff" stroke="#C9D6E0"/>
      <text x="${x-lw/2+9}" y="${ly+16.5}" font-size="12.5" font-weight="600" fill="#13293D">${nm}</text><text x="${x-lw/2+15+nm.length*7.4}" y="${ly+16.5}" font-size="12.5" fill="#1F5F8B">${p.n}</text></g>`)});
  const rotas=[...new Set(vs.map(v=>rota(v.destino)))];if(!rotas.length)rotas.push(MAIN);
  const navios=vs.map((v,i)=>{const[x,y]=pos[i],c=corViagem(v),s=i===sel;return`<g class="pv-navio"><circle cx="${x}" cy="${y}" r="15" fill="${c}" class="pv-onda"/>
    <circle cx="${x}" cy="${y}" r="${s?10:7}" fill="#fff" stroke="${c}" stroke-width="${s?4:3}"/><circle cx="${x}" cy="${y}" r="3.5" fill="${c}"/>${s?`<text x="${x+16}" y="${y-12}" font-size="14" font-weight="700" fill="#13293D" paint-order="stroke" stroke="#fff" stroke-width="5">${esc(v.navio)}</text>`:""}</g>`}).join("");
  return`<svg class="pv-svg" viewBox="${vb}" preserveAspectRatio="xMidYMid slice" role="img" aria-label="Mapa do Atlântico com ${vs.length} navio(s) com carga Elolog">
  <defs><pattern id="pvPontos" width="7" height="7" patternUnits="userSpaceOnUse"><circle cx="3.5" cy="3.5" r="1.35" fill="#9DB7CB"/></pattern></defs>
  <g stroke="#DCE6EE" stroke-width="1">${[62,166,269,372].map(y=>`<line x1="0" y1="${y}" x2="1200" y2="${y}"/>`).join("")}${[288,528,768,1008].map(x=>`<line x1="${x}" y1="0" x2="${x}" y2="600"/>`).join("")}</g>
  <line x1="0" y1="476" x2="1200" y2="476" stroke="#1F7A5C" stroke-opacity=".5" stroke-width="1.2" stroke-dasharray="2 6"/><text x="1110" y="470" font-size="12" fill="#1F7A5C">Equador</text>
  <polygon points="725,27 734,0 1200,0 1200,10 1092,3 1066,19 1128,62 1152,83 1142,80 1104,52 1020,32 977,17 924,30 845,28 845,38" fill="url(#pvPontos)" stroke="#B4C8D7" stroke-opacity=".8" stroke-dasharray="1 3"/>
  <polygon points="552,26 725,27 845,38 845,47 773,67 751,87 715,96 634,103 614,95 554,93 557,76 542,68 559,50 547,31" fill="url(#pvPontos)" stroke="#B4C8D7" stroke-opacity=".8" stroke-dasharray="1 3"/>
  <polygon points="1200,90 1008,91 744,112 626,106 533,160 451,190 360,259 372,274 348,324 367,348 408,362 449,383 492,404 588,430 672,422 792,415 876,411 924,430 972,429 998,440 996,466 991,486 1051,526 1061,538 1085,567 1092,600 1200,600" fill="url(#pvPontos)" stroke="#B4C8D7" stroke-opacity=".8" stroke-dasharray="1 3"/>
  ${rotas.map(r=>`<path d="${caminho(r)}" fill="none" stroke="#1F5F8B" stroke-opacity=".75" stroke-width="2"/><path class="pv-fluxo" d="${caminho(r)}" fill="none" stroke="#EAF1F6" stroke-width="2"/>`).join("")}
  ${portos.join("")}${navios}</svg>`}
window.elologPVMapa={svg,posicao,progresso,corViagem,coord};
})();
