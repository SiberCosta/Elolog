/* Elolog — ELO: o que o assistente sabe explicar (v174).
   Perguntas frequentes respondidas no chat, sem abrir páginas: como funciona a Elolog, medidas e volume (m³), embalagem,
   o que não se envia, recolha, pagamentos, rastreio, avaliações, grupagem, fecho de carga, conta e prestadores.
   Só explica como a plataforma funciona e dá conselhos gerais; preços, datas e prazos continuam a vir só da plataforma.
   Também faz contas simples: «60x40x40» → volume em m³. Cada tema tem palavras-chave; ganha o que tiver mais acertos.
   Carregar depois de assistente-saidas.js e antes de assistente.js. */
(function(){"use strict";
const norm=v=>String(v||"").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"").replace(/[^a-z0-9x,. ]+/g," ").replace(/\s+/g," ").trim();
const num=v=>Number(String(v).replace(",","."));
const m3=v=>(Math.round(v*1000)/1000).toLocaleString("pt-PT",{maximumFractionDigits:3});
/* [palavras-chave (todas têm de estar numa das alternativas), resposta, opções] */
const TEMAS=[
 [["como funciona","o que e a elolog","o que e elolog","o que fazem","para que serve","como trabalham"],
  "A Elolog junta clientes e transportadoras verificadas:\n1. Faz uma simulação (origem, destino, peso e medidas).\n2. Vê os preços reais dos prestadores aprovados e escolhe um.\n3. O prestador aprova o pedido e trata da recolha, armazém e envio.\n4. Acompanha tudo na sua área, com o código ELO da encomenda.\nPaga só na página Pagamentos, pelo valor que a plataforma calcula.",["Nova simulação","Como medir as caixas?","Falar com uma pessoa"]],
 [["como medir","medidas","medir as caixas","medir a carga","o que e m3","metro cubico","metros cubicos","calcular volume","calcular o volume","volume"],
  "Meça cada caixa em centímetros: comprimento × largura × altura. Para passar a m³, multiplique as três e divida por 1 000 000.\nEx.: 60 × 40 × 40 cm = 96 000 ÷ 1 000 000 = 0,096 m³. Com 3 caixas iguais: 0,288 m³.\nPode escrever-me as medidas (ex.: «3 caixas 60x40x40») e eu faço a conta.",["Nova simulação","Como embalar?"]],
 [["embalar","embalagem","embalo","proteger a carga","caixas boas","como preparar a carga","preparar a carga"],
  "Algumas regras simples para a carga chegar bem:\n• caixas firmes, cheias (sem espaços vazios) e bem fechadas com fita;\n• objetos frágeis envolvidos um a um e marcados «Frágil»;\n• líquidos bem fechados e dentro de saco;\n• nome e contacto do destinatário em cada volume;\n• uma lista do que vai em cada caixa (ajuda também na alfândega).\nO prestador pode ter regras próprias: confirme na proposta.",["Que documentos preciso?","Nova simulação"]],
 [["nao posso enviar","proibid","o que nao se pode","nao se pode enviar","posso enviar","pode ir","produtos perigosos","inflamave","baterias","liquidos","medicamentos","armas"],
  "Em regra, as transportadoras não aceitam mercadorias perigosas (inflamáveis, explosivos, gases, produtos corrosivos), armas, drogas nem bens ilegais. Baterias, líquidos, alimentos e medicamentos podem ter regras especiais.\nCada prestador indica o que aceita: na dúvida, descreva a carga no pedido ou pergunte a uma pessoa da equipa antes de enviar.",["Falar com uma pessoa","Como embalar?"]],
 [["recolha","recolher","vao buscar","vem buscar","buscar a carga","levantar em casa"],
  "Se quiser que vão buscar a carga, indique a morada na simulação. O custo da recolha conta a partir do armazém do prestador mais próximo dessa morada. Se o prestador não tiver armazém registado, a recolha fica por juntar ao preço e ele indica-a.\nTambém pode levar a carga ao armazém do prestador.",["Nova simulação"]],
 [["grupagem","carga consolidada","carga partilhada","partilhar contentor","contentor partilhado"],
  "Grupagem (ou carga consolidada) é juntar cargas de vários clientes no mesmo contentor. Paga só o espaço que a sua carga ocupa, por isso costuma compensar em envios pequenos e médios.",["Nova simulação","Próximas saídas"]],
 [["fecho de carga","fecho da carga","ultimo dia para entregar","data limite"],
  "O fecho de carga é o último dia para a carga chegar ao armazém do prestador e seguir num barco. Depois dessa data, passa para a saída seguinte. Vê o fecho de cada saída nas «Próximas saídas».",["Próximas saídas"]],
 [["codigo elo","codigo da encomenda","numero da encomenda","referencia da encomenda","onde vejo o codigo"],
  "Cada encomenda tem um código ELO, por exemplo ELO_TRAN-000123. Está na sua área, em Encomendas, e nos emails da encomenda. Com ele pode rastrear no site sem entrar na conta.",["Estado da encomenda"]],
 [["rastrear","seguir a encomenda","acompanhar a encomenda","tracking"],
  "Para rastrear, escreva aqui o código ELO (ex.: ELO_TRAN-000123) ou use «Rastrear carga» no site. Com sessão iniciada vê todas as suas encomendas e o histórico.",["Estado da encomenda"]],
 [["pagar","pagamento","pagamentos","transferencia","multibanco","mbway","fatura","recibo"],
  "Os pagamentos fazem-se só na página Pagamentos da sua conta, pelo valor que a plataforma calcula. Não envie dados de cartão ou IBAN no chat. As faturas e comprovativos ficam em Documentos.",["Falar com uma pessoa"]],
 [["avaliar","avaliacao","avaliacoes","estrelas","classificacao","classificacoes","nivel ouro","recomendado elolog"],
  "Depois de cada encomenda entregue, pode avaliar o prestador no Início da sua área (1 a 5 estrelas, e se quiser pontualidade, comunicação e cuidado com a carga). As avaliações aparecem no site, sem o seu nome. Os níveis (Recomendado Elolog, Ouro, Prata, Bronze) são atribuídos pela equipa Elolog.",["Estado da encomenda"]],
 [["criar conta","registar","registo","inscrever","conta gratis","e gratis","custa criar"],
  "Criar conta de cliente é grátis: em «Área de Cliente», escolha criar conta e use o seu email. Depois vê os preços reais e acompanha as encomendas.",["Nova simulação"]],
 [["ser prestador","tornar-me prestador","tornar me prestador","sou transitario","sou transportadora","trabalhar com a elolog","parceiro","parceria"],
  "Se tem uma transportadora ou transitário, pode juntar-se à rede: no site, em Contacto, escolha «Tornar-se prestador». Uma pessoa da equipa Elolog verifica os documentos da empresa antes de a aprovar.",["Falar com uma pessoa"]],
 [["seguro","segurar a carga","valor declarado","se partir","se perder","danificad","estragad"],
  "Indique o valor da carga no pedido (valor declarado). Se algo chegar danificado ou faltar, registe logo uma ocorrência na encomenda, com fotografias, e fale com a equipa. As condições de seguro são as de cada prestador: confirme na proposta.",["Falar com uma pessoa"]],
 [["aviao","aereo","maritimo","barco ou aviao","qual o mais rapido","mais barato"],
  "Em geral, o transporte aéreo é mais rápido e mais caro e serve para cargas urgentes e pequenas. O marítimo é mais lento e mais económico para volumes maiores ou mudanças. A simulação mostra as opções e prazos de cada prestador para a sua rota.",["Nova simulação","Próximas saídas"]]
];
/* conta de volume: «60x40x40», «3 caixas 60x40x40», «1,2 x 0,8 x 1 m» */
function conta(n){const d=n.match(/(\d+(?:[.,]\d+)?)\s*x\s*(\d+(?:[.,]\d+)?)\s*x\s*(\d+(?:[.,]\d+)?)\s*(cm|m)?\b/);if(!d)return null;
  const f=d[4]==="m"?1:1e-2,v=num(d[1])*f*num(d[2])*f*num(d[3])*f,q=+(n.match(/(\d+)\s*(caixas?|volumes?|paletes?|malas?|embalagens?|sacos?)/)?.[1]||1);
  return`${d[1]} × ${d[2]} × ${d[3]} ${d[4]||"cm"} = ${m3(v)} m³${q>1?` por volume; ${q} volumes = ${m3(v*q)} m³`:""}.`}
function procurar(n){let melhor=null,pts=0;for(const t of TEMAS){const p=t[0].filter(k=>n.includes(k)).reduce((s,k)=>s+k.split(" ").length,0);if(p>pts){pts=p;melhor=t}}return melhor}
const pergunta=n=>/\?|^(o que|como|porque|por que|qual|quais|quanto|onde|quando|posso|pode|e possivel|da para|existe|tem)\b/.test(n);
const fluxos=window.eloFluxos||(window.eloFluxos=[]);
/* contas de volume e perguntas claras entram cedo; o resto fica para o fim (só se nenhuma outra regra responder) */
fluxos.unshift({re:{test:n=>/^(quanto (da|e)|calcula\w*|qual (e )?o volume)/.test(norm(n))&&!!conta(norm(n))},fazer:x=>({texto:conta(norm(x))+"\nQuer simular com estas medidas? Escreva origem e destino, por ex.: «de Lisboa para São Tomé».",chips:["Nova simulação"]})});
const navegar=n=>/\b(abr[ei]r?|abra|ir para|vai para|leva-?me|mostra(r)?|aceder)\b/.test(n);
fluxos.push({re:{test:n=>{const m=norm(n);return!navegar(m)&&!!procurar(m)}},fazer:x=>{const t=procurar(norm(x)),seg=window.eloSimular?.pendente?.();return{texto:t[1]+(seg?`\n\nContinuamos a simulação: ${seg}`:""),chips:seg?["Cancelar"]:t[2]}}});
window.eloSaber={procurar:x=>procurar(norm(x))?.[1]||null,conta:x=>conta(norm(x)),pergunta:x=>pergunta(norm(x))};
})();
