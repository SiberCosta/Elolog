/* Menu (telemóvel) e submenu Serviços, como no simulador. */
(function(){function iniciarNavegacao(){const navToggle=document.getElementById("nav-toggle");const navMenu=document.getElementById("nav-menu");
const servicesToggle=document.querySelector(".nav-dropdown-toggle");const servicesDropdown=document.querySelector(".nav-dropdown");if(!navToggle||!navMenu)return;navToggle.addEventListener("click",()=>{const aberto=navMenu.classList.toggle("open");
navToggle.setAttribute("aria-expanded",String(aberto))});if(servicesToggle&&servicesDropdown){servicesToggle.addEventListener("click",event=>{if(window.innerWidth<=900){event.preventDefault();const aberto=servicesDropdown.classList.toggle("mobile-open");
servicesToggle.setAttribute("aria-expanded",String(aberto))}})}navMenu.querySelectorAll("a").forEach(link=>link.addEventListener("click",()=>{navMenu.classList.remove("open");navToggle.setAttribute("aria-expanded","false");
if(servicesDropdown)servicesDropdown.classList.remove("mobile-open");if(servicesToggle)servicesToggle.setAttribute("aria-expanded","false")}))}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",iniciarNavegacao);else iniciarNavegacao()})();
