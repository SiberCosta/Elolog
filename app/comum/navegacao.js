/* Elolog — módulo 12/15: Navegação, menu lateral e modo móvel
   Script clássico: partilha o âmbito global com os restantes módulos. Carregar pela ordem numérica. */
function showPage(page,button){const ALIASES={simulation:"clientSimulation",orders:"tracking",admin:"dashboard",support:"clientSupport"};if(!document.getElementById(page)&&ALIASES[page])page=ALIASES[page];const target=document.getElementById(page);if(!target){
console.warn("Elolog: página inexistente:",page);return}document.querySelectorAll(".page").forEach(p=>p.classList.remove("active"));target.classList.add("active");
document.querySelectorAll("#sidebar .menu > button").forEach(b=>b.classList.remove("client-menu-active","active"));if(button&&button.closest("#sidebar .menu")){button.classList.add("client-menu-active")}
if(currentUser?.role==="prestador")setProviderDesktopNavState(button,page);const titles={dashboard:"Dashboard",operations:"Operações",proposals:"Propostas",tracking:"Encomendas",clientSimulation:"Simulação",documents:"Documentos",payments:"Pagamentos",
admin:"Administração"};document.getElementById("pageTitle").textContent=titles[page];document.getElementById("sidebar").classList.remove("open")}function toggleSidebar(){const sidebar=document.getElementById("sidebar");if(!sidebar)return;
const open=sidebar.classList.toggle("open");document.body.classList.toggle("sidebar-mobile-open",open&&window.innerWidth<=900)}function closeSidebar(){document.getElementById("sidebar")?.classList.remove("open");
document.body.classList.remove("sidebar-mobile-open")}document.getElementById("sidebar")?.addEventListener("click",e=>{const b=e.target.closest(".menu button");if(!b||window.innerWidth>900)return;if(b.classList.contains("provider-menu-main")||/toggle\w*Group/.test(b.getAttribute("onclick")||"")||b.hasAttribute("aria-expanded"))return;setTimeout(closeSidebar,80)});window.addEventListener("resize",()=>{
if(window.innerWidth>900)closeSidebar()});
