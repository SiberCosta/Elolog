/* Elolog — logótipo animado (v83). Na primeira página de cada visita, o logótipo da barra de navegação
   desenha-se: as duas metades, o selo com o visto e as letras. Respeita «reduzir movimento». Depois fica estático. */
(function(){"use strict";
const img=document.querySelector(".navbar .logo-image, .navbar img.logo-image");if(!img)return;
let visto=false;try{visto=sessionStorage.getItem("elolog_logo_animado")==="1";sessionStorage.setItem("elolog_logo_animado","1")}catch(_){}
const parado=visto||matchMedia("(prefers-reduced-motion: reduce)").matches;
const LETRAS=[
["c1","M573.27 214.56H651.56V195.22H595.83V168.86H647.39V150.03H595.83V124.77H651.56V105.43H573.27Z"],
["c1","M682.55 105.43H660.94V214.56H682.55Z"],
["c1","M730.67 216.32C754.18 216.32 770.00 200.20 770.00 175.96C770.00 151.72 754.18 135.46 730.67 135.46C707.23 135.46 691.41 151.72 691.41 175.96C691.41 200.20 707.23 216.32 730.67 216.32ZM730.67 198.81C720.20 198.81 713.17 190.32 713.17 175.96C713.17 161.53 720.27 152.96 730.67 152.96C741.14 152.96 748.25 161.53 748.25 175.96C748.25 190.32 741.22 198.81 730.67 198.81Z"],
["c2","M800.47 105.43H778.87V214.56H800.47Z"],
["c2","M848.60 216.32C872.11 216.32 887.93 200.20 887.93 175.96C887.93 151.72 872.11 135.46 848.60 135.46C825.16 135.46 809.34 151.72 809.34 175.96C809.34 200.20 825.16 216.32 848.60 216.32ZM848.60 198.81C838.12 198.81 831.09 190.32 831.09 175.96C831.09 161.53 838.20 152.96 848.60 152.96C859.07 152.96 866.17 161.53 866.17 175.96C866.17 190.32 859.14 198.81 848.60 198.81Z"],
["c2","M933.34 246.20C955.75 246.20 971.13 236.09 971.13 211.56V137.22H949.82V148.42H949.75C944.84 139.85 936.78 135.61 926.75 135.61C906.97 135.61 893.42 152.08 893.42 175.30C893.42 198.37 906.68 214.63 926.90 214.63C937.00 214.63 945.13 210.53 949.75 201.45H949.82V213.32C949.82 224.45 943.89 230.31 933.34 230.31C925.28 230.31 919.57 227.01 918.03 221.15H897.23C899.43 236.17 911.37 246.20 933.34 246.20ZM932.46 197.35C921.99 197.35 915.18 189.22 915.18 175.01C915.18 160.80 921.99 152.74 932.46 152.74C943.38 152.74 950.63 161.53 950.63 175.01C950.63 188.56 943.38 197.35 932.46 197.35Z"]];
const ns="http://www.w3.org/2000/svg",cls=parado?"elo-anim parado":"elo-anim";
const letras=LETRAS.map(([c,d],i)=>`<path class="ltr ${c}" style="--i:${i}" d="${d}"/>`).join("");
const svg=`<svg xmlns="${ns}" class="${img.className} ${cls}" viewBox="0 0 1038 320" preserveAspectRatio="xMinYMid meet" role="img" aria-label="${img.alt||"Elolog"}">
<defs><mask id="elo-anim-m" maskUnits="userSpaceOnUse" x="0" y="0" width="1000" height="500"><rect width="1000" height="500" fill="#fff"/><circle cx="500" cy="250" r="68" fill="#000"/></mask></defs>
<g transform="translate(-49.09 -2.34) scale(0.64935)"><g mask="url(#elo-anim-m)" fill="none" stroke-width="44" stroke-miterlimit="10">
<path class="trace" stroke="#1F5F8B" pathLength="1" d="M470 205 C415 125 320 88 190 118 L250 250 L190 382 C320 412 415 375 470 295"/>
<path class="trace" stroke="#1F7A5C" pathLength="1" d="M530 205 C580 135 635 102 700 102 C782 102 848 168 848 250 C848 332 782 398 700 398 C635 398 580 365 530 295"/></g>
<g class="badge"><circle cx="500" cy="250" r="56" fill="#1C6478"/><path class="check" pathLength="1" d="M475 251 L493 269 L527 233"/></g></g>${letras}</svg>`;
if(!document.getElementById("elo-anim-css")){const st=document.createElement("style");st.id="elo-anim-css";st.textContent=`
.elo-anim{overflow:visible}.elo-anim .c1{fill:#1F5F8B}.elo-anim .c2{fill:#1F7A5C}
.elo-anim .check{fill:none;stroke:#fff;stroke-width:11;stroke-linecap:round;stroke-linejoin:round}
.elo-anim .badge,.elo-anim .ltr{transform-box:fill-box;transform-origin:center}
.elo-anim:not(.parado) .trace{stroke-dasharray:1 1;stroke-dashoffset:1;animation:eloDraw 1.15s cubic-bezier(.65,0,.35,1) .15s forwards}
.elo-anim:not(.parado) .badge{transform:scale(0);animation:eloPop .55s cubic-bezier(.34,1.56,.64,1) .95s forwards}
.elo-anim:not(.parado) .check{stroke-dasharray:1 1;stroke-dashoffset:1;animation:eloDraw .4s ease-out 1.35s forwards}
.elo-anim:not(.parado) .ltr{opacity:0;transform:translateY(18px);animation:eloRise .6s cubic-bezier(.22,1,.36,1) calc(1.55s + var(--i)*.07s) forwards}
html:is(.dn-capa,.sim-capa) .navbar:not(.nav-solida) .elo-anim{filter:none!important}
html:is(.dn-capa,.sim-capa) .navbar:not(.nav-solida) .elo-anim .trace{stroke:#fff}
html:is(.dn-capa,.sim-capa) .navbar:not(.nav-solida) .elo-anim :is(.c1,.c2,.badge circle){fill:#fff}
html:is(.dn-capa,.sim-capa) .navbar:not(.nav-solida) .elo-anim .check{stroke:#13293D}
@keyframes eloDraw{to{stroke-dashoffset:0}}@keyframes eloPop{to{transform:scale(1)}}@keyframes eloRise{to{opacity:1;transform:none}}`;document.head.appendChild(st)}
const t=document.createElement("template");t.innerHTML=svg.trim();img.replaceWith(t.content.firstChild);
})();
