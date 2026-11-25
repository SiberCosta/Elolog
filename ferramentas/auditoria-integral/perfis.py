"""Sessões de demonstração da Elolog (dados de partilhado/scripts/dados-demo.js), injetadas no separador."""
import json

EMPRESA = {"id": "DEMO-PRV-001", "type": "prestador", "name": "Transatlântico Demo, Lda.", "tradeName": "Transatlântico Demo",
           "nif": "509999990", "status": "Ativo", "validationStatus": "approved", "plan": "Profissional"}

PERFIS = {
    "cliente": {"email": "cliente@demo.elolog.pt", "role": "cliente", "name": "Comercial Atlântico Demo",
                "profile": {"nif": "599999991", "phone": "+351 910 000 001", "address": "Rua do Mercado, 25, Lisboa"},
                "providerFunction": None, "providerCompany": None, "authenticatedBy": "local-demo"},
    "prestador": {"email": "admin@transatlantico.demo", "role": "prestador", "name": "Marta Ferreira",
                  "providerFunction": "admin", "providerCompany": EMPRESA, "authenticatedBy": "local-demo"},
    "terreno": {"email": "terreno@transatlantico.demo", "role": "prestador", "name": "Rui Costa",
                "providerFunction": "field_operator", "providerCompany": EMPRESA, "authenticatedBy": "local-demo"},
    "admin": {"email": "admin@demo.elolog.pt", "role": "admin", "name": "Administrador Elolog Demo",
              "profile": {"id": "LOCAL-ADMIN"}, "providerFunction": None, "providerCompany": None, "authenticatedBy": "local-demo"},
}

BASE = "http://127.0.0.1:8772/app/area-cliente.html"


async def entrar(pg, perfil):
    """Abre a app em demonstração e injeta a sessão do perfil."""
    await pg.goto(BASE + "?demo=1", wait_until="load")
    await pg.wait_for_timeout(800)
    u = json.dumps(PERFIS[perfil])
    acesso = {"admin": "?acesso=administracao", "prestador": "?acesso=prestador", "terreno": "?acesso=prestador"}.get(perfil, "")
    await pg.evaluate(f"""()=>{{sessionStorage.setItem('elolog_demo','1');sessionStorage.setItem('th_user',JSON.stringify({u}));
      localStorage.setItem('elolog_cookie_consent','1')}}""")
    await pg.goto(BASE + acesso, wait_until="load")
    await pg.wait_for_timeout(2500)
