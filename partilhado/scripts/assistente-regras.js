/* Elolog — Regras de funcionamento do ELO (assistente virtual) e respostas em português, inglês e francês (v96).
   1 não inventa preços, transportadoras nem datas de navios · 2 só confirma encomendas consultando a plataforma ·
   3 não recebe pagamentos · 4 não aprova prestadores · 5 não mostra dados de terceiros · 6/7 pessoa da equipa e terminar a qualquer momento ·
   8 apresenta-se sempre como assistente virtual · 9 oculta dados pessoais antes de os guardar · 10 PT, EN e FR.
   Carrega ANTES de assistente.js; as regras entram à frente dos fluxos (window.eloFluxos). Usa a ligação Supabase existente (ELOLogServidor). */
(function(){"use strict";
const K="elo_lingua";let L="pt";try{L=sessionStorage.getItem(K)||(localStorage.getItem("elolog_lang")==="en"?"en":"pt")}catch(_){}
const guardar=l=>{L=l;try{sessionStorage.setItem(K,l)}catch(_){}};
const norm=v=>String(v||"").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"");
const sessao=()=>{try{return JSON.parse(sessionStorage.getItem("th_user")||"null")}catch(_){return null}};
const papel=()=>{const u=sessao();return!u?"visitante":u.role==="admin"?"admin":u.role==="prestador"?"prestador":"cliente"};
const servidor=()=>{try{return!!window.ELOLogServidor?.ativo?.()}catch(_){return false}};
const CODIGO=/\b(?:TR|EL|ENC|ORD)-\d{4,12}(?:-\d{4,8})?\b/i;

const T={
pt:{eu:"Sou o ELO, o assistente virtual da Elolog: um programa automático, não uma pessoa. Se preferir, escreva «falar com uma pessoa» e passo o assunto à equipa.",
 humano:"Preparei um resumo (sem dados pessoais) para a equipa Elolog. Toque em «Escrever à equipa», uma pessoa responde-lhe.",
 pagar:"Por segurança, não recebo pagamentos nem dados de pagamento. Pague apenas na página «Pagamentos» da sua conta, pelo valor calculado pela plataforma.",
 sensivel:"Por favor, não partilhe dados de cartão, IBAN ou palavras-passe no chat. Ocultei essa informação e não a guardei.",
 aprovarAdmin:"Não aprovo prestadores automaticamente. A aprovação é feita por um administrador, depois de verificar os documentos, em «Pedidos de inscrição». Vou abrir a página.",
 aprovar:"As inscrições de prestadores são analisadas por uma pessoa da equipa Elolog; não há aprovação automática. Recebe um email quando houver decisão.",
 preco:"Os preços só são calculados pela plataforma, na simulação, com as tarifas reais dos prestadores aprovados. Não dou estimativas no chat.",
 transportadoras:"Só indico os prestadores aprovados e disponíveis que a plataforma devolve para a sua rota, na simulação. Não sugiro transportadoras fora da Elolog.",
 navios:"Não indico datas de navios no chat: só são válidas quando o prestador as confirma na sua encomenda. Se precisar, passo o pedido a uma pessoa da equipa.",
 agendar:"Os agendamentos ficam na encomenda, na plataforma, e só estão confirmados quando o prestador os aceitar. Vou abrir as suas operações.",
 login:"Por privacidade, só mostro encomendas depois de iniciar sessão na conta a que pertencem. Não pesquiso por email ou NIF de terceiros.",
 codigo:"Indique o código da encomenda (por exemplo EL-000245) e consulto a plataforma.",
 consultar:c=>`A consultar a plataforma${c?` (${c})`:""}…`,
 naoEnc:c=>c?`A plataforma não tem a encomenda ${c} na sua conta. Confirme o código.`:"Ainda não tem encomendas na plataforma.",
 erro:"Não consegui consultar a plataforma agora, por isso não confirmo o estado. Tente de novo ou fale com uma pessoa da equipa.",
 enc:"Encomenda",dados:"Dados da plataforma às",
 privacidade:"Recolho o mínimo: a conversa fica só neste dispositivo durante 24 h, com emails, telefones, NIF e dados de pagamento ocultados. Escreva «apagar conversa» para a apagar já.",
 apagada:"Conversa apagada deste dispositivo.",
 simular:"Abro o simulador: o preço aparece apenas com tarifas reais de prestadores aprovados.",
 fim:"Conversa terminada e apagada deste dispositivo. Se precisar de uma pessoa da equipa: contacto@elolog.pt.",
 lingua:"Em que língua prefere? / Which language? / Quelle langue ?",ok:"Muito bem, continuamos em português.",
 ola:n=>`Olá${n}! Sou o ELO, o assistente virtual da Elolog. Em que posso ajudar?`,
 opcoes:"Claro. Escolha uma opção ou escreva o seu pedido."},
en:{eu:"I'm ELO, Elolog's virtual assistant: an automated program, not a person. If you prefer, type “talk to a person” and I'll pass it to the team.",
 humano:"Of course. I've prepared a summary (without personal data) for the Elolog team. Tap “Write to the team”, a person will reply.",
 pagar:"For security, I don't take payments or payment details. Pay only on the “Payments” page of your account, for the amount calculated by the platform.",
 sensivel:"Please don't share card details, IBAN or passwords in the chat. I've hidden that information and haven't stored it.",
 aprovarAdmin:"I don't approve providers automatically. An administrator approves them after checking the documents, in “Registration requests”. Opening the page.",
 aprovar:"Provider registrations are reviewed by a person on the Elolog team; there is no automatic approval. You'll get an email once there's a decision.",
 preco:"Prices are only calculated by the platform, in the simulation, from the real rates of approved providers. I don't give estimates in the chat.",
 transportadoras:"I only show the approved, available providers the platform returns for your route, in the simulation. I don't suggest carriers outside Elolog.",
 navios:"I don't give ship dates in the chat: they are only valid once the provider confirms them on your order. If needed, I can pass your request to a person on the team.",
 agendar:"Appointments are made on the order, in the platform, and are only confirmed once the provider accepts. Opening your operations.",
 login:"For privacy, I only show orders after you sign in to the account they belong to. I don't search by other people's email or tax ID.",
 codigo:"Give me the order code (for example EL-000245) and I'll check the platform.",
 consultar:c=>`Checking the platform${c?` (${c})`:""}…`,
 naoEnc:c=>c?`The platform has no order ${c} in your account. Please check the code.`:"You don't have any orders on the platform yet.",
 erro:"I couldn't reach the platform right now, so I can't confirm the status. Try again or talk to a person on the team.",
 enc:"Order",dados:"Platform data at",
 privacidade:"I collect the minimum: the chat stays only on this device for 24 h, with emails, phone numbers, tax IDs and payment details hidden. Type “delete chat” to erase it now.",
 apagada:"Chat deleted from this device.",
 simular:"Opening the simulator: prices appear only from real rates of approved providers.",
 fim:"Chat ended and deleted from this device. If you need a person on the team: contacto@elolog.pt.",
 lingua:"Which language? / Em que língua? / Quelle langue ?",ok:"Great, we'll continue in English.",
 ajuda:"I can: open a simulation, check an order status (signed in), take you to Payments, or pass you to a person. What do you need?",
 ola:n=>`Hello${n}! I'm ELO, Elolog's virtual assistant. How can I help?`,
 opcoes:"Sure. Choose an option or type your request."},
fr:{eu:"Je suis ELO, l'assistant virtuel d'Elolog : un programme automatique, pas une personne. Si vous préférez, écrivez « parler à une personne ».",
 humano:"Bien sûr. J'ai préparé un résumé (sans données personnelles) pour l'équipe Elolog. Touchez « Écrire à l'équipe », une personne vous répondra.",
 pagar:"Par sécurité, je ne reçois ni paiements ni données de paiement. Payez uniquement sur la page « Paiements » de votre compte, au montant calculé par la plateforme.",
 sensivel:"Merci de ne pas partager de carte bancaire, d'IBAN ou de mot de passe dans le chat. J'ai masqué ces informations et je ne les ai pas gardées.",
 aprovarAdmin:"Je n'approuve pas les prestataires automatiquement. Un administrateur les approuve après vérification des documents, dans « Demandes d'inscription ». J'ouvre la page.",
 aprovar:"Les inscriptions des prestataires sont examinées par une personne de l'équipe Elolog ; il n'y a pas d'approbation automatique. Vous recevrez un email à la décision.",
 preco:"Les prix sont calculés uniquement par la plateforme, dans la simulation, avec les tarifs réels des prestataires approuvés. Je ne donne pas d'estimation dans le chat.",
 transportadoras:"Je n'indique que les prestataires approuvés et disponibles que la plateforme propose pour votre trajet, dans la simulation. Pas de transporteurs hors Elolog.",
 navios:"Je ne donne pas de dates de navires dans le chat : elles ne sont valables qu'une fois confirmées par le prestataire sur votre commande. Si besoin, je transmets votre demande à une personne de l'équipe.",
 agendar:"Les rendez-vous se font sur la commande, dans la plateforme, et ne sont confirmés qu'après acceptation du prestataire. J'ouvre vos opérations.",
 login:"Par confidentialité, je n'affiche les commandes qu'après connexion au compte concerné. Je ne cherche pas par email ou NIF de tiers.",
 codigo:"Indiquez le code de la commande (par exemple EL-000245) et je consulte la plateforme.",
 consultar:c=>`Je consulte la plateforme${c?` (${c})`:""}…`,
 naoEnc:c=>c?`La plateforme n'a pas la commande ${c} dans votre compte. Vérifiez le code.`:"Vous n'avez pas encore de commande sur la plateforme.",
 erro:"Je n'ai pas pu consulter la plateforme, je ne confirme donc pas le statut. Réessayez ou parlez à une personne de l'équipe.",
 enc:"Commande",dados:"Données de la plateforme à",
 privacidade:"Je collecte le minimum : la conversation reste sur cet appareil 24 h, avec emails, téléphones, NIF et données de paiement masqués. Écrivez « effacer la conversation » pour l'effacer.",
 apagada:"Conversation effacée de cet appareil.",
 simular:"J'ouvre le simulateur : les prix viennent uniquement des tarifs réels des prestataires approuvés.",
 fim:"Conversation terminée et effacée de cet appareil. Pour parler à une personne de l'équipe : contacto@elolog.pt.",
 lingua:"Quelle langue ? / Em que língua? / Which language?",ok:"Très bien, nous continuons en français.",
 ajuda:"Je peux : ouvrir une simulation, consulter une commande (connecté), vous guider vers les Paiements ou vous passer à une personne. Que souhaitez-vous ?",
 ola:n=>`Bonjour${n} ! Je suis ELO, l'assistant virtuel d'Elolog. Comment puis-je vous aider ?`,
 opcoes:"Bien sûr. Choisissez une option ou écrivez votre demande."}};
const t=k=>T[L][k]??T.pt[k];
const ESTADOS={pt:{aprovacao:"a aguardar aprovação",agendamento:"agendamento",recolha:"recolha",armazenamento:"em armazém",expedicao:"expedição",em_transito:"em trânsito",destino:"no destino",entregue:"entregue",cancelada:"cancelada"},
 en:{aprovacao:"awaiting approval",agendamento:"scheduling",recolha:"pickup",armazenamento:"in warehouse",expedicao:"dispatch",em_transito:"in transit",destino:"at destination",entregue:"delivered",cancelada:"cancelled"},
 fr:{aprovacao:"en attente d'approbation",agendamento:"planification",recolha:"enlèvement",armazenamento:"en entrepôt",expedicao:"expédition",em_transito:"en transit",destino:"à destination",entregue:"livrée",cancelada:"annulée"}};
const CHIPS={pt:["Falar com uma pessoa","Terminar conversa","Idioma / Language / Langue"],
 en:["New simulation","Order status","Talk to a person","End chat","Idioma / Language / Langue"],
 fr:["Nouvelle simulation","Suivi de commande","Parler à une personne","Terminer la conversation","Idioma / Language / Langue"]};

/* 9 — dados pessoais ocultados antes de guardar ou enviar o resumo à equipa */
function ocultar(s){return String(s||"").replace(/\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]){11,30}\b/g,"[IBAN]").replace(/\b(?:\d[ -]?){13,19}\b/g,"[cartão]")
  .replace(/[\w.+-]+@[\w-]+\.[\w.-]+/g,"[email]").replace(/(?:\+|00)\d{1,3}[ \d]{8,14}\d|\b9\d{2}[ ]?\d{3}[ ]?\d{3}\b/g,"[telefone]").replace(/\b\d{9}\b/g,"[NIF]")
  .replace(/((?:palavra-passe|password|senha|mot de passe|pin)\s*(?:é|e|is|est|:|=)?\s*)\S+/gi,"$1[oculto]")}
const sensivel=s=>/\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]){11,30}\b|\b(?:\d[ -]?){13,19}\b|(?:palavra-passe|password|senha|mot de passe)\s*(?:é|e|is|est|:|=)/i.test(String(s||""));

/* 10 — língua: escolha explícita ou deteção por palavras frequentes */
function detetar(n){if(/\b(portugues|em portugues)\b/.test(n)&&n.split(" ").length<=3)return"pt";if(/\b(english|in english|ingles)\b/.test(n)&&n.split(" ").length<=4)return"en";
  if(/\b(francais|french|frances|en francais)\b/.test(n)&&n.split(" ").length<=4)return"fr";
  const c=r=>(n.match(r)||[]).length;const en=c(/\b(hello|hi|the|my|where|is|how|much|please|thanks|order|ship|price|want|need|can|you|what|when|track)\b/g),
  fr=c(/\b(bonjour|salut|je|mon|ma|ou|est|prix|combien|merci|commande|navire|bateau|vous|quand|suivi|pour|une|le|la)\b/g),
  pt=c(/\b(ola|bom|boa|quero|preciso|minha|onde|esta|preco|quanto|obrigad[oa]|encomenda|navio|barco|quando|para|uma|o|a)\b/g);
  const m=Math.max(en,fr,pt);if(m<2)return"";return m===en&&en>pt&&en>fr?"en":m===fr&&fr>pt&&fr>en?"fr":m===pt&&pt>en&&pt>fr?"pt":""}

/* ações na página */
const abrir=(id,btn)=>()=>{try{const r=papel(),b=document.querySelector(`[onclick*="'${id}'"]`);if(r==="admin")showAdminPage(id,b);else if(r==="prestador")showProviderPage(id,b);else showPage(id,btn?document.getElementById(btn):b)}catch(_){}};
const PAG={pagamentos:{cliente:"payments",prestador:"providerPagamentos",admin:"adminBilling"},operacoes:{cliente:"operations",prestador:"providerOrder",admin:"adminOperations"}};
const irPara=k=>{const id=PAG[k][papel()];return id?abrir(id):null};
const simulador=()=>{if(document.getElementById("clientSimulation"))return abrir("clientSimulation","menuSimulation")();const o=document.getElementById("origem");
  if(o)return o.scrollIntoView({behavior:"smooth",block:"center"});location.href=(location.pathname.includes("/app/")?"../site/":"")+"simulador.html"};
const destacarEquipa=()=>{const a=document.querySelector(".elo-assistant-whatsapp");if(a){a.classList.add("destacado");a.focus?.()}};
function dizer(txt){const m=document.querySelector(".elo-assistant-messages");if(!m)return;const d=document.createElement("div");d.className="elo-message";
  d.innerHTML="<strong>ELO</strong>";d.appendChild(document.createTextNode(txt));m.appendChild(d);m.scrollTop=m.scrollHeight}

/* 2 e 5 — encomendas: só a plataforma confirma, e só da conta com sessão iniciada (RLS do Supabase) */
async function consultar(codigo){const lg=L;try{const sb=await window.ELOLogServidor.cliente();let q=sb.from("encomendas").select("codigo,estado,origem,destino,created_at");
  q=codigo?q.eq("codigo",codigo.toUpperCase()).limit(1):q.order("created_at",{ascending:false}).limit(1);const{data,error}=await q;if(error)throw error;const o=data?.[0];
  if(!o)return dizer(T[lg].naoEnc(codigo));const h=new Date().toLocaleTimeString(lg==="en"?"en-GB":lg==="fr"?"fr-FR":"pt-PT",{hour:"2-digit",minute:"2-digit"});
  dizer(`${T[lg].enc} ${o.codigo}: ${ESTADOS[lg][o.estado]||o.estado}. ${o.origem||"—"} → ${o.destino||"—"}. (${T[lg].dados} ${h})`)}catch(_){dizer(T[lg].erro)}}
const R=(texto,go,chips)=>({texto,go,chips:chips||lista()});
const lista=()=>{const r=papel(),base=window.__eloChipsBase?.[r];return L==="pt"?[...(base||["Nova simulação","Estado da encomenda"]),...CHIPS.pt]:CHIPS[L]};
const fora=()=>L!=="pt";
const regra=(teste,fazer)=>({re:{test:teste},fazer});

const REGRAS=[
 regra(n=>/^idioma . language . langue$|^(mudar (de )?)?(idioma|lingua)$|^(language|langue)$/.test(n),()=>R(t("lingua"),null,["Português","English","Français"])),
 regra(n=>/^(em |in |en )?(portugues|english|ingles|anglais|francais|french|frances)$/.test(n),(x,n)=>{guardar(/portugues/.test(n)?"pt":/english|ingles|anglais/.test(n)?"en":"fr");return R(t("ok"))}),
 regra((n,raw)=>sensivel(raw),()=>R(t("sensivel"))),
 regra(n=>/\b(es|e|sera|sou) (um |uma )?(humano|pessoa|robo|bot|maquina)|quem (es|e) tu|com quem (falo|estou)|are you (a )?(human|bot|robot|real|person)|who are you|etes-vous|es-tu (un )?(humain|robot)|qui (etes|es)/.test(n),()=>R(t("eu"))),
 regra(n=>/\b(apagar|eliminar|limpar) (a )?conversa|delete (the |my )?chat|clear (the )?chat|effacer (la )?conversation/.test(n),()=>{try{localStorage.removeItem("elolog_assistant_history");sessionStorage.removeItem("elolog_assistant_state")}catch(_){}return R(t("apagada"))}),
 regra(n=>/privacidade|dados pessoais|rgpd|\bgdpr\b|privacy|personal data|donnees personnelles|confidentialite/.test(n),()=>R(t("privacidade"))),
 regra(n=>/\b(aprov\w*|validar|autorizar|approve|approval|approuver|valider)\b.*\b(prestador\w*|empresa|inscric\w*|registo|provider|registration|prestataire|inscription)|\b(prestador\w*|inscric\w*|provider|prestataire)\b.*\b(aprov\w*|approv\w*)/.test(n),
   ()=>papel()==="admin"?R(t("aprovarAdmin"),abrir("adminProviderRequests")):R(t("aprovar"))),
 regra(n=>fora()&&/\b(human|person|agent|someone|representative|operator|humain|personne|conseiller|quelqu)\b/.test(n),()=>R(t("humano"),destacarEquipa,CHIPS[L])),
 regra(n=>fora()&&/\b(pay|payment|card|paid|payer|paiement|carte|regler)\b/.test(n),()=>R(t("pagar"),papel()==="visitante"?null:irPara("pagamentos"))),
 regra(n=>fora()&&/\b(price|prices|cost|how much|quote|rate|rates|prix|combien|tarifs?|devis|cout)\b/.test(n),()=>R(t("preco"),simulador)),
 regra(n=>fora()&&/\b(simulat\w*|send|ship from|from .+ to |envoyer|expedier|de .+ (a|vers) )/.test(n),()=>R(t("simular"),simulador)),
 regra((n,raw)=>CODIGO.test(raw)&&(servidor()||papel()==="visitante")&&!/simul/.test(n),x=>{const c=x.match(CODIGO)[0].toUpperCase();
   if(papel()==="visitante")return R(t("login"));setTimeout(()=>consultar(c),250);return R(t("consultar")(c))}),
 regra(n=>(servidor()||papel()==="visitante")&&!/inscric|cotac|\b(price|prix|cost|combien|how much|quote|devis|preco|quanto custa)\b/.test(n)&&/\b(encomendas?|estado|rastre\w*|onde (esta|anda)|order|track\w*|parcel|shipment|commande|suivi|colis)\b/.test(n),(x,n)=>{
   if(papel()==="visitante")return R(t("login"));if(papel()==="cliente"&&/(minha|ultima|my|last|latest|ma |derniere)/.test(n)){setTimeout(()=>consultar(""),250);return R(t("consultar")(""))}return R(t("codigo"))}),
 regra(n=>servidor()&&/\b(agendar|agendamento|marcar|schedule|appointment|book|rendez-vous|planifier)\b/.test(n),()=>R(t("agendar"),irPara("operacoes"))),
 regra(n=>!/tempo real|\bais\b|mapa|calendario/.test(n)&&/\b(proximo (barco|navio)|proxima (saida|partida)|navios?|barcos?|datas? de (saida|partida|chegada)|next (ship|vessel|sailing|boat)|ships|vessels?|sailings?|departures?|navires?|bateaux?|prochain (navire|bateau|depart))\b/.test(n),
   ()=>R(t("navios"))),
 regra(n=>/\b(transportadoras?|quais (os )?prestadores|que empresas|carriers?|shipping compan\w*|transporteurs?)\b/.test(n),()=>R(t("transportadoras"))),
 regra(n=>/^(ola|oi|bom dia|boa tarde|boa noite|ajuda|opcoes|menu|hello|hi|hey|help|options|good (morning|afternoon|evening)|bonjour|salut|bonsoir|aide)\b/.test(n)&&n.split(" ").length<=4,()=>R(t("opcoes"))),
 regra(()=>fora(),()=>R(t("ajuda")))];

/* liga ao assistente: regras antes dos fluxos; atalhos na língua escolhida */
const fluxos=window.eloFluxos||[];window.eloFluxos=fluxos;
fluxos.unshift(...REGRAS.map(r=>({re:{test:n=>r.re.test(n,window.__eloUltimo||n)},fazer:(x,n)=>r.fazer(x,n)})));
window.__eloChipsBase=window.eloChips||{};
window.eloChips=new Proxy(window.__eloChipsBase,{get:(o,k)=>typeof k==="string"&&["cliente","prestador","admin","visitante"].includes(k)?lista():o[k]});
window.eloRegras={ocultar,
  antes(texto){window.__eloUltimo=texto;const l=detetar(norm(texto));if(l&&l!==L&&norm(texto).split(" ").length>=2)guardar(l)},
  terminar:s=>/\b(end (the )?(chat|conversation)|close (the )?chat|goodbye|bye|terminer (la )?conversation|fin de (la )?conversation|au revoir|terminar( a)? conversa|adeus)\b/.test(norm(s)),
  fim:()=>t("fim"),
  saudacao:nome=>T[L].ola(nome),
  lingua:()=>L};
})();
