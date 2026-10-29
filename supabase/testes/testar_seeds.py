"""Testa os SEEDS do Trato (supabase/seeds) num Postgres LOCAL descartável. Nunca toca no Supabase.

Uso (venv fora do projeto, com pgserver e psycopg2-binary):
    python -I supabase/testes/testar_seeds.py <raiz-do-projeto> <pasta-temporaria>

O que prova:
  (a) com parametros.sql como está (A DEFINIR), cada seed aborta com mensagem clara e não grava nada;
  (b) preenchidos os parâmetros de TESTE (valores fictícios, só aqui), os seeds entram e rodar DUAS vezes
      não muda nada (idempotência);
  (c) constraints: valor fora de min/max, tabela progressiva ligada, categoria de gás/estrutural,
      aprovar com a mesma pessoa, versão aprovada imutável e que não se apaga, conta do ledger imutável;
  (d) rollback de cada seed desfaz limpo e dá para aplicar de novo; rollback de versão aprovada aborta;
  (e) seed_equipe_admin não executa nada e não traz e-mail nem senha.
Sai com código 1 se qualquer verificação falhar.
"""
import pathlib
import re
import sys
import uuid

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from banco_local import Banco  # noqa: E402

RAIZ = pathlib.Path(sys.argv[1])
TEMP = sys.argv[2]
SEEDS = RAIZ / "supabase/seeds"
ROLLBACK = RAIZ / "supabase/rollback"
resultados = []


def verifica(titulo, ok, detalhe=""):
    resultados.append(bool(ok))
    print(("OK   " if ok else "ERRO ") + titulo + (f"  [{detalhe}]" if detalhe and not ok else ""))


def ler(caminho):
    return pathlib.Path(caminho).read_text(encoding="utf-8")


def tem(msg, *trechos):
    return msg is not None and all(t.lower() in msg.lower() for t in trechos)


PARAMETROS = ler(SEEDS / "parametros.sql")
SEED = {n: ler(SEEDS / f"{n}.sql") for n in ("seed_cidades_categorias", "seed_config_taxa", "seed_contas_ledger")}
RB = {n: ler(ROLLBACK / f"{n}_rollback.sql") for n in SEED}


def lit(v):
    return "null" if v is None else "'" + str(v).replace("'", "''") + "'"


def preenche(admin, **extra):
    """SQL que preenche os parâmetros de TESTE (valores fictícios) por cima do parametros.sql."""
    p = {
        "cidade_nome": "Cidade Teste", "cidade_uf": "TT",
        "cat1_garantia_dias": 30, "cat2_garantia_dias": 45, "cat3_garantia_dias": 60,
        "config_criada_por": admin, "ledger_p7_confirmado": "true",
    }
    p.update({k: v for k, v in extra.items() if not k.startswith("cfg_")})
    sql = "".join(f"update seed_param set valor = {lit(v)} where chave = {lit(k)};\n" for k, v in p.items())
    cfg = {"taxa_bps": (750, 0, 2000), "taxa_minima_centavos": (500, 0, 5000), "prazo_liberacao_dias": (7, 1, 30)}
    for k, v in extra.items():
        if k.startswith("cfg_"):
            cfg[k[4:]] = v
    for k, (valor, mn, mx) in cfg.items():
        sql += f"update seed_config set valor = {valor}, minimo = {mn}, maximo = {mx} where chave = {lit(k)};\n"
    return sql


def roda(b, texto, *, admin=None, preencher=True, **extra):
    """parametros + (preenchimento de teste) + script, tudo numa sessão e numa transação implícita."""
    pre = preenche(admin, **extra) if preencher else ""
    return b.falha(PARAMETROS + pre + texto)


def n(b, sql, *a):
    return b.um(sql, a or None)


def estado(b):
    return (
        n(b, "select count(*) from cidades"), n(b, "select count(*) from categorias"),
        n(b, "select count(*) from categoria_perguntas"), n(b, "select count(*) from config_definicoes"),
        n(b, "select count(*) from config_versoes"), n(b, "select count(*) from config_parametros"),
        n(b, "select count(*) from config_faixas_taxa"), n(b, "select count(*) from contas_ledger"),
    )


def main():
    b = Banco(RAIZ, TEMP, nome="pgdata_seeds")
    try:
        b.aplicar_todas()
        verifica("migrations F3.2 a F3.8 aplicadas", n(b, "select count(*) from pg_tables where schemaname='public'") > 40)
        zero = estado(b)
        verifica("banco começa vazio", all(v == 0 for v in zero), str(zero))

        # equipe de teste (o primeiro administrador real é criado pelo João, nunca por seed)
        adm, fin = str(uuid.uuid4()), str(uuid.uuid4())
        for u, nome, papel in ((adm, "Admin Teste", "administrador"), (fin, "Financeiro Teste", "financeiro")):
            b.exec("insert into auth.users (id) values (%s)", (u,))
            b.exec("insert into usuarios (id, nome) values (%s,%s)", (u, nome))
            b.exec("insert into equipe (usuario_id, papel) values (%s,%s)", (u, papel))

        # (a) parametros.sql como está: nada roda sem o João
        for nome in SEED:
            msg = roda(b, SEED[nome], admin=adm, preencher=False)
            verifica(f"{nome}: sem parâmetros aborta com 'A DEFINIR'", tem(msg, "A DEFINIR"), msg)
        verifica("nada foi gravado pelos abortos", estado(b) == zero)
        msg = b.falha(SEED["seed_cidades_categorias"])
        verifica("seed sem parametros.sql na sessão avisa", tem(msg, "parametros.sql"), msg)

        # (b) preenchido: entra, e duas vezes dá no mesmo
        todos = "".join(SEED.values())
        msg = roda(b, todos, admin=adm, cat3_incluir="true")
        verifica("os 3 seeds aplicam (parâmetros de teste)", msg is None, msg)
        e1 = estado(b)
        verifica("cidade do piloto criada, inativa", b.exec("select nome, uf, ativa from cidades") == [("Cidade Teste", "TT", False)])
        verifica("3 categorias com garantia do parâmetro",
                 b.exec("select slug, garantia_retrabalho_dias from categorias order by ordem")
                 == [("limpeza-residencial", 30), ("montagem-de-moveis", 45), ("pintura-interna", 60)])
        verifica("cada categoria tem 5 perguntas (4 + triagem de risco)",
                 b.exec("select count(*) from categoria_perguntas group by categoria_id") == [(5,)] * 3)
        verifica("pergunta de triagem de obra estrutural/gás em todas",
                 n(b, "select count(*) from categoria_perguntas where texto like '%estrutural ou instalação de gás%' and obrigatoria") == 3)
        verifica("perguntas com opções são jsonb válido",
                 n(b, "select count(*) from categoria_perguntas where tipo in ('escolha_unica','multipla') and jsonb_typeof(opcoes)='array'") == 3)
        verifica("versão de configuração nasce em rascunho, criada pelo admin",
                 b.exec("select status, criada_por::text, aprovada_por from config_versoes") == [("rascunho", adm, None)])
        verifica("tabela progressiva DESLIGADA e sem faixas",
                 n(b, "select valor from config_parametros where chave='taxa_progressiva_ativa'") == 0
                 and n(b, "select count(*) from config_faixas_taxa") == 0)
        verifica("taxa única e mínimo vêm do parâmetro",
                 b.exec("select chave, valor from config_parametros where chave in ('taxa_bps','taxa_minima_centavos') order by chave")
                 == [("taxa_bps", 750), ("taxa_minima_centavos", 500)])
        verifica("prazos do escopo: resposta 48 h, decisão 5 dias úteis, retrabalho 7 dias",
                 b.exec("""select chave, valor from config_parametros where chave in
                    ('prazo_resposta_disputa_horas','prazo_decisao_disputa_dias_uteis','prazo_retrabalho_atendimento_dias')
                    order by chave""") == [("prazo_decisao_disputa_dias_uteis", 5), ("prazo_resposta_disputa_horas", 48),
                                           ("prazo_retrabalho_atendimento_dias", 7)])
        verifica("opcionais sem valor ficam de fora do rascunho",
                 n(b, "select count(*) from config_parametros where chave in ('prazo_confirmacao_cliente_horas','prazo_congelar_disputa_horas')") == 0)
        verifica("taxa e prazos exigem dupla aprovação no catálogo",
                 n(b, "select count(*) from config_definicoes where chave in ('taxa_bps','taxa_minima_centavos','prazo_liberacao_dias') and exige_dupla_aprovacao") == 3)
        verifica("4 contas de sistema, nenhuma por usuário e nenhuma com 'stripe' no nome",
                 b.exec("select count(*), count(usuario_id), count(*) filter (where codigo ilike '%stripe%') from contas_ledger") == [(4, 0, 0)])

        msg = roda(b, todos, admin=adm, cat3_incluir="true")
        verifica("2ª aplicação passa", msg is None, msg)
        verifica("idempotente: nada muda ao aplicar duas vezes", estado(b) == e1, f"{e1} -> {estado(b)}")

        # (c) constraints
        for chave, valor, trecho in (("taxa_bps", 3000, "acima do máximo"), ("prazo_liberacao_dias", 0, "abaixo do mínimo")):
            # em outro banco lógico não dá; força uma versão nova só neste teste, desfeita pela transação
            msg = b.falha(f"""begin; insert into config_versoes(status, criada_por, motivo) values ('rascunho','{adm}','t');
                insert into config_parametros(versao_id, chave, valor)
                  select id, '{chave}', {valor} from config_versoes where motivo = 't'; commit;""")
            b.falha("rollback")
            verifica(f"{chave}={valor} fora de min/max é recusado", tem(msg, trecho), msg)
        msg = b.falha("insert into config_parametros(versao_id, chave, valor, escopo_tipo, escopo_texto) "
                      "select id, 'taxa_bps', 5, 'nivel', 'ouro' from config_versoes limit 1")
        verifica("escopo não permitido na definição é recusado", tem(msg, "escopo"), msg)

        base = b.exec("select id from config_versoes")[0][0]
        verifica("definição não aceita minimo > maximo",
                 tem(b.falha("insert into config_definicoes(chave, descricao, unidade, minimo, maximo) values ('x','x','dias',5,1)"), "check"))

        # parâmetros inválidos: abortam sem gravar nada (usa banco já com seed; aplica sobre ele)
        for rotulo, extra, trecho in (
            ("progressiva ligada (D2 em espera)", dict(cfg_taxa_progressiva_ativa=(1, 0, 1)), "em espera"),
            ("categoria de gás", dict(cat1_nome="Instalação de gás", cat1_slug="instalacao-de-gas"), "fora do piloto"),
            ("categoria estrutural", dict(cat2_nome="Reforço estrutural", cat2_slug="reforco-estrutural"), "fora do piloto"),
            ("P7 não confirmado", dict(ledger_p7_confirmado="false"), "P7"),
            ("criada_por fora da equipe", dict(config_criada_por=str(uuid.uuid4())), "equipe"),
        ):
            msg = roda(b, todos, admin=adm, **extra)
            verifica(f"recusa: {rotulo}", tem(msg, trecho), msg)
        verifica("recusas não gravam nada", estado(b) == e1)

        # aprovação dupla e imutabilidade
        verifica("aprovar com a mesma pessoa que criou é recusado",
                 b.falha("update config_versoes set status='aprovada', aprovada_por=%s", (adm,)) is not None)
        verifica("aprovar sem aprovador é recusado",
                 b.falha("update config_versoes set status='aprovada'") is not None)

        # (d) rollback dos seeds sobre rascunho
        for nome in ("seed_contas_ledger", "seed_config_taxa", "seed_cidades_categorias"):
            msg = roda(b, RB[nome], admin=adm, cat3_incluir="true")
            verifica(f"rollback {nome} roda", msg is None, msg)
        verifica("rollback devolve o banco ao estado vazio", estado(b) == zero, str(estado(b)))

        # valor acima do máximo em versão nova: o trigger de parâmetros barra e nada é gravado
        msg = roda(b, SEED["seed_config_taxa"], admin=adm, cfg_prazo_liberacao_dias=(99, 1, 30))
        verifica("valor 99 > máximo 30 é recusado pelo trigger", tem(msg, "acima do máximo"), msg)
        verifica("...e a versão não fica pela metade", n(b, "select count(*) from config_versoes") == 0)

        msg = roda(b, todos, admin=adm, cat3_incluir="true")
        verifica("reaplicar depois do rollback funciona", msg is None, msg)
        verifica("versão nova recebe novo número (identity não volta)", n(b, "select numero from config_versoes") > 1)

        # faixas progressivas: entram, mas a tabela continua desligada
        b_faixa = ("update seed_faixa set de_centavos=0, ate_centavos=50000, taxa_bps=750 where ordem=1;"
                   "update seed_faixa set de_centavos=50000, ate_centavos=null, taxa_bps=500 where ordem=2;")
        roda(b, RB["seed_config_taxa"], admin=adm)
        msg = b.falha(PARAMETROS + preenche(adm) + b_faixa + SEED["seed_config_taxa"])
        verifica("faixas preenchidas entram no rascunho", msg is None and n(b, "select count(*) from config_faixas_taxa") == 2, msg)
        verifica("com faixas, a tabela segue desligada", n(b, "select valor from config_parametros where chave='taxa_progressiva_ativa'") == 0)

        # aprovação e imutabilidade
        v = b.exec("select id from config_versoes")[0][0]
        verifica("aprovar com OUTRA pessoa passa",
                 b.falha("update config_versoes set status='aprovada', aprovada_por=%s where id=%s", (fin, v)) is None)
        verifica("aprovada: parâmetro não muda", tem(b.falha("update config_parametros set valor=1 where versao_id=%s and chave='taxa_bps'", (v,)), "aprovada"))
        verifica("aprovada: faixa não muda", tem(b.falha("delete from config_faixas_taxa where versao_id=%s", (v,)), "aprovada"))
        verifica("aprovada: motivo não muda", tem(b.falha("update config_versoes set motivo='outro' where id=%s", (v,)), "aprovada"))
        verifica("aprovada: não se apaga", tem(b.falha("delete from config_versoes where id=%s", (v,)), "aprovada"))
        e2 = estado(b)
        msg = roda(b, SEED["seed_config_taxa"], admin=adm)
        verifica("seed reaplicado com versão aprovada não cria outra nem mexe", msg is None and estado(b) == e2, msg)
        msg = roda(b, RB["seed_config_taxa"], admin=adm)
        verifica("rollback de versão aprovada ABORTA", tem(msg, "aprovada"), msg)
        verifica("...e não apaga nada", estado(b) == e2)

        # ledger imutável
        verifica("conta de sistema não pode ser apagada à mão",
                 b.falha("delete from contas_ledger where codigo='receita_taxa'") is not None)
        verifica("conta de sistema não muda de natureza",
                 b.falha("update contas_ledger set natureza='ativo' where codigo='receita_taxa'") is not None)
        msg = roda(b, RB["seed_contas_ledger"], admin=adm)
        verifica("rollback das contas (sem lançamentos) apaga e religa o trigger",
                 msg is None and n(b, "select count(*) from contas_ledger") == 0
                 and n(b, "select tgenabled from pg_trigger where tgname='contas_ledger_sem_delete'") == "O")
        msg = roda(b, SEED["seed_contas_ledger"], admin=adm)
        verifica("contas recriadas depois do rollback", msg is None and n(b, "select count(*) from contas_ledger") == 4, msg)

        # (e) equipe: só modelo comentado
        for arq in ("supabase/seeds/seed_equipe_admin.sql", "supabase/rollback/seed_equipe_admin_rollback.sql"):
            linhas = [x for x in ler(RAIZ / arq).splitlines() if x.strip() and not x.strip().startswith("--")]
            verifica(f"{arq}: nada executável", not linhas, str(linhas))
            texto = ler(RAIZ / arq)
            verifica(f"{arq}: sem e-mail", not re.search(r"[\w.+-]+@[\w-]+\.[\w.]+", texto))

        # arquivos
        verifica("todo seed tem rollback", all((ROLLBACK / f"{s}_rollback.sql").exists()
                                               for s in (*SEED, "seed_equipe_admin")))
        verifica("parâmetros: taxa e P1 seguem NULL no repositório",
                 not re.search(r"\('taxa_bps',\s*[0-9]", PARAMETROS) and not re.search(r"\('prazo_liberacao_dias',\s*[0-9]", PARAMETROS))
    finally:
        b.fechar()
    falhas = resultados.count(False)
    print(f"\n{len(resultados) - falhas} OK, {falhas} erro(s)")
    sys.exit(1 if falhas else 0)


main()
