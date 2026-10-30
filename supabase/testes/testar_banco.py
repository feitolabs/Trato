"""Testa TODAS as migrations do Trato (F3.2 a F3.8) num Postgres LOCAL descartável. Nunca toca no Supabase.

Uso (venv fora do projeto, com pgserver e psycopg2-binary):
    python -I supabase/testes/testar_banco.py <raiz-do-projeto> <pasta-temporaria>

O que prova:
  (a) o usuário A não lê pedido, endereço, mensagem, pagamento, documento nem saldo do usuário B;
  (b) o profissional não vê o endereço antes do contrato e vê depois;
  (c) equipe de cadastro vê documentos; atendimento, financeiro e mediação não;
  (d) ledger não aceita UPDATE/DELETE; partidas desequilibradas são recusadas; estorno funciona;
  (e) mensagens e auditoria são imutáveis (auditoria com cadeia de hash);
  (f) configuração aprovada e contrato são imutáveis;
  (g) anon não lê nada; o app (authenticated) não escreve; funções SECURITY DEFINER são seguras;
  (h) o rollback de cada migration desfaz limpo (compara o estado do banco) e reaplicar funciona.
Sai com código 1 se qualquer verificação falhar.
"""
import sys
import uuid
import random
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from banco_local import Banco  # noqa: E402

RAIZ = pathlib.Path(sys.argv[1])
TEMP = sys.argv[2]
MODO = sys.argv[3] if len(sys.argv) > 3 else "real"
resultados = []


def verifica(nome, condicao, detalhe=""):
    resultados.append((nome, bool(condicao)))
    print(("OK    " if condicao else "ERRO  ") + nome + ("" if condicao or not detalhe else f"   [{detalhe}]"))


def falha_como(b, papel, sql):
    """Mensagem de erro ao rodar `sql` como dono ('owner') ou como outro papel; None se passou."""
    if papel == "owner":
        return b.falha(sql)
    r = b.tenta(None, sql, papel=papel)
    return r[1] if r[0] == "erro" else None


def tem_erro(texto, *trechos):
    return texto is not None and (not trechos or any(t.lower() in texto.lower() for t in trechos))


# ---------------------------------------------------------------------------------------------
# Estado do banco (para provar que o rollback desfaz tudo)
# ---------------------------------------------------------------------------------------------
CONSULTAS_ESTADO = [
    """select 'tabela '||n.nspname||'.'||c.relname||' tipo='||c.relkind::text||' rls='||c.relrowsecurity
         from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in ('public','privado') and c.relkind in ('r','v','S','m')""",
    """select 'acl '||c.relname||' '||(case when a.grantee=0 then 'public' else pg_get_userbyid(a.grantee)::text end)||' '||a.privilege_type
         from pg_class c join pg_namespace n on n.oid=c.relnamespace,
              lateral aclexplode(coalesce(c.relacl, acldefault((case when c.relkind='S' then 's' else 'r' end)::"char", c.relowner))) a
        where n.nspname='public' and c.relkind in ('r','v','S')""",
    """select 'acl_coluna '||c.relname||'.'||t.attname||' '||pg_get_userbyid(a.grantee)||' '||a.privilege_type
         from pg_attribute t join pg_class c on c.oid=t.attrelid join pg_namespace n on n.oid=c.relnamespace,
              lateral aclexplode(t.attacl) a
        where n.nspname='public' and t.attacl is not null""",
    """select 'funcao '||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||') secdef='||p.prosecdef
              ||' cfg='||coalesce(p.proconfig::text,'')
         from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','privado')""",
    """select 'acl_funcao '||p.proname||'('||pg_get_function_identity_arguments(p.oid)||') '
              ||(case when a.grantee=0 then 'public' else pg_get_userbyid(a.grantee)::text end)||' '||a.privilege_type
         from pg_proc p join pg_namespace n on n.oid=p.pronamespace,
              lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
        where n.nspname in ('public','privado')""",
    """select 'gatilho '||tgrelid::regclass||' '||tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid
        join pg_namespace n on n.oid=c.relnamespace where not tgisinternal and n.nspname='public'""",
    """select 'policy '||schemaname||'.'||tablename||' '||policyname||' '||cmd||' '||permissive from pg_policies""",
    """select 'indice '||indexname from pg_indexes where schemaname='public'""",
    """select 'restricao '||conrelid::regclass||' '||conname from pg_constraint c
        join pg_namespace n on n.oid=c.connamespace where n.nspname='public'""",
    """select 'schema '||nspname from pg_namespace where nspname='privado'""",
    """select 'default_acl '||coalesce(defaclnamespace::regnamespace::text,'')||' '||defaclobjtype::text||' '||defaclacl::text
         from pg_default_acl""",
    """select 'bucket '||id from storage.buckets""",
    """select 'evento '||evtname from pg_event_trigger""",
]


def estado(b):
    s = set()
    for q in CONSULTAS_ESTADO:
        s.update(r[0] for r in b.exec(q))
    return s


def diferenca(a, bb):
    return sorted(a - bb)[:6], sorted(bb - a)[:6]


# ---------------------------------------------------------------------------------------------
# A suíte de acesso
# ---------------------------------------------------------------------------------------------
def suite(b, rodada):
    sufixo = f"{rodada}-{uuid.uuid4().hex[:6]}"
    U = {}

    def usuario(chave, status="ativo"):
        uid = uuid.uuid4()
        b.exec("insert into auth.users(id) values (%s)", (str(uid),))
        b.exec("insert into usuarios(id, nome, status) values (%s, %s, %s)", (str(uid), f"{chave} {sufixo}", status))
        cpf = "".join(random.choice("0123456789") for _ in range(11))
        b.exec("insert into usuarios_privados(usuario_id, cpf, telefone) values (%s, %s, %s)",
               (str(uid), cpf, "319" + cpf[:8]))
        U[chave] = uid
        return uid

    def cpf_de(chave):
        return b.um("select cpf from usuarios_privados where usuario_id=%s", (str(U[chave]),))

    def equipe(chave, papel, alcada=None):
        uid = usuario(chave)
        b.exec("insert into equipe(usuario_id, papel, alcada_centavos) values (%s, %s, %s)", (str(uid), papel, alcada))
        return uid

    def profissional(chave, status="aprovado", nivel="verificado"):
        uid = usuario(chave)
        b.exec("insert into perfis_profissional(usuario_id, status, nivel_verificacao, cnpj) values (%s,%s,%s,%s)",
               (str(uid), status, nivel, "12.345.678/0001-" + str(random.randint(10, 99))))
        return uid

    # --- cadastro-base: cidades, categorias, equipe, usuários -----------------------------------
    cid1 = str(uuid.uuid4()); cid2 = str(uuid.uuid4())
    b.exec("insert into cidades(id, nome, uf, ativa) values (%s,%s,'XX',true),(%s,%s,'YY',true)",
           (cid1, "Cidade1 " + sufixo, cid2, "Cidade2 " + sufixo))
    cat1 = str(uuid.uuid4()); cat2 = str(uuid.uuid4())
    b.exec("insert into categorias(id, nome, slug) values (%s,'Cat1',%s),(%s,'Cat2',%s)",
           (cat1, "cat1-" + sufixo, cat2, "cat2-" + sufixo))

    for chave, papel, alcada in [("cad", "cadastro", None), ("n1", "atendente_n1", None), ("n2", "atendente_n2", None),
                                 ("fin", "financeiro", None), ("med", "mediador", 100000),
                                 ("lider", "lider_suporte", None), ("seg", "seguranca", None),
                                 ("adm", "administrador", None), ("dpo", "dpo", None), ("mod", "moderador", None),
                                 ("jur", "juridico", None)]:
        equipe(chave, papel, alcada)
    for chave in ("A", "B", "outro"):
        usuario(chave)
    usuario("D", status="bloqueado")
    for chave, cat, cid in [("P1", cat1, cid1), ("P5", cat1, cid1), ("P4", cat1, cid1),
                            ("P2", cat2, cid1), ("P3", cat1, cid2)]:
        uid = profissional(chave)
        b.exec("insert into profissional_categorias(profissional_id, categoria_id) values (%s,%s)", (str(uid), cat))
        b.exec("insert into profissional_regioes(profissional_id, cidade_id) values (%s,%s)", (str(uid), cid))
    PX = profissional("PX", status="em_analise", nivel="basico")
    b.exec("insert into profissional_categorias(profissional_id, categoria_id) values (%s,%s)", (str(PX), cat1))
    b.exec("insert into profissional_regioes(profissional_id, cidade_id) values (%s,%s)", (str(PX), cid1))

    S = {k: str(v) for k, v in U.items()}  # ids como texto

    # configuração aprovada (duas pessoas diferentes)
    cfg = b.um("insert into config_versoes(criada_por, motivo) values (%s,'teste') returning id", (S["adm"],))
    b.exec("insert into config_definicoes(chave, descricao, unidade, minimo, maximo) values (%s,'t','bps',0,10000)",
           ("teste_" + sufixo,))
    b.exec("insert into config_parametros(versao_id, chave, valor) values (%s,%s,750)", (cfg, "teste_" + sufixo))
    b.exec("update config_versoes set status='aprovada', aprovada_por=%s where id=%s", (S["lider"], cfg))

    # --- verificação e documentos (c) -----------------------------------------------------------
    ver = b.um("insert into verificacoes(profissional_id, nivel_solicitado, consentimento_lgpd_em) values (%s,'verificado',now()) returning id",
               (str(PX),))
    b.exec("insert into verificacao_documentos(verificacao_id, tipo, storage_path) values (%s,'selfie',%s)",
           (ver, f"{PX}/{ver}/selfie.jpg"))
    b.exec("insert into storage.objects(bucket_id, name) values ('verificacao', %s)", (f"{PX}/{ver}/selfie.jpg",))

    print("\n== (c) Documentos de verificação ==")
    # A8 (fix de acesso): NINGUÉM lê documento direto, nem a equipe de cadastro. A leitura é só
    # por URL assinada do backend (service_role), com motivo e registro de quem viu.
    for chave, esperado in [("cad", 0), ("n1", 0), ("n2", 0), ("med", 0), ("fin", 0), ("seg", 0), ("adm", 0),
                            ("dpo", 0), ("P1", 0), ("A", 0)]:
        r = b.tenta(S[chave], "select id from verificacao_documentos")
        n = len(r[1]) if r[0] == "ok" else 0  # sem o grant de SELECT o banco recusa: também é "não vê"
        verifica(f"documentos: {chave} " + ("vê" if esperado else "não vê"), (n >= 1) if esperado else (n == 0), f"viu {n}")
    verifica("documentos: o backend (service_role) lê para assinar a URL curta",
             len(b.ve(None, "select id from verificacao_documentos", papel="service_role")) >= 1)
    verifica("documentos: a equipe de cadastro nem tem o grant de SELECT na tabela",
             tem_erro(b.tenta(S["cad"], "select storage_path from verificacao_documentos")[1], "permission denied"))
    verifica("documentos: o próprio profissional não lê de volta", b.tenta(str(PX), "select id from verificacao_documentos")[0] == "erro")
    verifica("documentos: anon recusado", b.tenta(None, "select * from verificacao_documentos", papel="anon")[0] == "erro")
    verifica("verificação: profissional vê a própria", len(b.ve(str(PX), "select id from verificacoes")) == 1)
    verifica("verificação: outro profissional não vê", len(b.ve(S["P1"], "select id from verificacoes")) == 0)
    verifica("verificação: analista_id/fornecedor_ref ocultos do app",
             tem_erro(b.tenta(str(PX), "select analista_id from verificacoes")[1], "permission denied"))
    for chave, esperado in [("cad", 0), ("n1", 0), ("med", 0), ("fin", 0), ("adm", 0), ("P1", 0), ("A", 0)]:
        n = len(b.ve(S[chave], "select name from storage.objects where bucket_id='verificacao'"))
        verifica(f"storage verificacao: {chave} " + ("lê" if esperado else "não lê"), n == esperado, f"viu {n}")

    # --- pedidos (a) e (b) ----------------------------------------------------------------------
    PA, PB, PC, PD = (str(uuid.uuid4()) for _ in range(4))
    b.exec("""insert into pedidos(id, cliente_id, categoria_id, cidade_id, bairro, titulo, descricao) values
              (%s,%s,%s,%s,'Savassi','Trocar chuveiro','Chuveiro queimado'),
              (%s,%s,%s,%s,'Savassi','Pintar sala','Sala 20m2'),
              (%s,%s,%s,%s,'Centro','Consertar cano','Vazamento'),
              (%s,%s,%s,%s,'Centro','Pedido do bloqueado','x')""",
           (PA, S["A"], cat1, cid1, PB, S["B"], cat1, cid1, PC, S["A"], cat2, cid1, PD, S["D"], cat1, cid1))
    for p, rua in [(PA, "Rua das Flores 10 apto 5"), (PB, "Rua Secreta 99")]:
        b.exec("insert into pedidos_endereco(pedido_id, logradouro, numero, lat, lng) values (%s,%s,'10',-19.93,-43.93)", (p, rua))

    print("\n== (a) Usuário A não lê dados do usuário B ==")
    ids_a = {r[0] for r in b.ve(S["A"], "select id from pedidos")}
    verifica("A vê os próprios pedidos e nenhum de B", ids_a == {PA, PC}, str(ids_a))
    ids_b = {r[0] for r in b.ve(S["B"], "select id from pedidos")}
    verifica("B vê só os próprios pedidos", ids_b == {PB}, str(ids_b))
    verifica("A não lê o endereço do pedido de B",
             len(b.ve(S["A"], "select pedido_id from pedidos_endereco where pedido_id=%s", (PB,))) == 0)
    verifica("A lê o próprio endereço", len(b.ve(S["A"], "select pedido_id from pedidos_endereco where pedido_id=%s", (PA,))) == 1)
    verifica("conta bloqueada não lê nem o próprio pedido", len(b.ve(S["D"], "select id from pedidos")) == 0)
    verifica("conta bloqueada não lê o próprio usuário", len(b.ve(S["D"], "select id from usuarios")) == 0)

    print("\n== (b) Profissional e endereço: antes do contrato ==")
    ids_p1 = {r[0] for r in b.ve(S["P1"], "select id from pedidos")}
    verifica("P1 (categoria e cidade certas) vê pedidos abertos PA e PB", ids_p1 == {PA, PB}, str(ids_p1))
    verifica("P1 não vê o pedido aberto de um cliente bloqueado", PD not in ids_p1)
    verifica("P2 (outra categoria) não vê PA", PA not in {r[0] for r in b.ve(S["P2"], "select id from pedidos")})
    verifica("P2 não vê nenhum pedido de cat1", len(b.ve(S["P2"], "select id from pedidos where categoria_id=%s", (cat1,))) == 0)
    verifica("P2 vê o pedido de cat2 (PC)", PC in {r[0] for r in b.ve(S["P2"], "select id from pedidos")})
    verifica("P3 (outra cidade) não vê PA nem PB", len(b.ve(S["P3"], "select id from pedidos")) == 0)
    verifica("PX (em análise) não vê pedidos", len(b.ve(str(PX), "select id from pedidos")) == 0)
    verifica("P1 NÃO vê o endereço de PA antes do contrato", len(b.ve(S["P1"], "select 1 from pedidos_endereco")) == 0)
    verifica("P1 vê o bairro (aproximado) em pedidos", b.ve(S["P1"], "select bairro from pedidos where id=%s", (PA,))[0][0] == "Savassi")
    verifica("n1 (atendimento) vê o pedido mas não o endereço",
             len(b.ve(S["n1"], "select id from pedidos")) >= 4 and len(b.ve(S["n1"], "select 1 from pedidos_endereco")) == 0)

    # --- orçamentos e contrato ------------------------------------------------------------------
    def orcamento(pedido, pro, total, versao=1, enviar=True):
        oid = str(uuid.uuid4())
        cmds = [("insert into orcamentos(id, pedido_id, profissional_id, versao, valor_total_centavos) values (%s,%s,%s,%s,%s)",
                 (oid, pedido, pro, versao, total)),
                ("insert into orcamento_itens(orcamento_id, tipo, descricao, quantidade, valor_unitario_centavos, total_centavos) "
                 "values (%s,'horas','mão de obra',1,%s,%s)", (oid, total, total))]
        if enviar:
            cmds.append(("update orcamentos set status='enviado', enviado_em=now() where id=%s", (oid,)))
        erro = b.transacao(cmds)
        assert erro is None, erro
        return oid

    TOTAL = 500000
    o1 = orcamento(PA, S["P1"], TOTAL)
    o5 = orcamento(PA, S["P5"], 450000)
    o1_rasc = orcamento(PA, S["P1"], 100, versao=2, enviar=False)
    o4 = orcamento(PB, S["P4"], TOTAL)

    print("\n== Orçamentos ==")
    ids_o = {r[0] for r in b.ve(S["A"], "select id from orcamentos")}
    verifica("A vê os 2 orçamentos enviados do próprio pedido, sem rascunho", ids_o == {o1, o5}, str(ids_o))
    verifica("B não vê orçamento de PA", len(b.ve(S["B"], "select id from orcamentos where pedido_id=%s", (PA,))) == 0)
    verifica("P5 não vê o orçamento do concorrente P1", {r[0] for r in b.ve(S["P5"], "select id from orcamentos")} == {o5})
    verifica("P1 vê os próprios (inclusive rascunho)", {r[0] for r in b.ve(S["P1"], "select id from orcamentos")} == {o1, o1_rasc})
    verifica("itens: P5 não vê itens do orçamento de P1",
             len(b.ve(S["P5"], "select id from orcamento_itens where orcamento_id=%s", (o1,))) == 0)
    verifica("itens: A não vê itens do rascunho",
             len(b.ve(S["A"], "select id from orcamento_itens where orcamento_id=%s", (o1_rasc,))) == 0)
    verifica("itens: A vê itens do orçamento enviado",
             len(b.ve(S["A"], "select id from orcamento_itens where orcamento_id=%s", (o1,))) == 1)
    verifica("trigger: profissional em análise não envia orçamento",
             tem_erro(b.transacao([("insert into orcamentos(pedido_id, profissional_id, status, valor_total_centavos, enviado_em) "
                                    "values (%s,%s,'enviado',0,now())", (PA, str(PX)))]), "verificado"))
    verifica("trigger: total do orçamento diferente da soma dos itens é recusado no commit",
             tem_erro(b.transacao([("insert into orcamentos(pedido_id, profissional_id, valor_total_centavos) values (%s,%s,999)",
                                    (PA, S["P3"]))]), "difere da soma"))
    verifica("trigger: item não entra em orçamento já enviado",
             tem_erro(b.falha("insert into orcamento_itens(orcamento_id,tipo,descricao,quantidade,valor_unitario_centavos,total_centavos) "
                              "values (%s,'outro','x',1,1,1)", (o1,)), "rascunho"))
    verifica("trigger: orçamento enviado não muda valor",
             tem_erro(b.falha("update orcamentos set valor_total_centavos=1 where id=%s", (o1,)), "enviado"))

    # contrato do cliente A com P1 (pedido PA) e de B com P4 (pedido PB)
    def contrato(pedido, orc, cliente, pro):
        b.exec("update orcamentos set status='aceito' where id=%s", (orc,))
        cid = str(uuid.uuid4())
        b.exec("""insert into contratos(id, pedido_id, orcamento_id, cliente_id, profissional_id, status, escopo_texto,
                    valor_total_centavos, taxa_bps_aplicada, taxa_trato_centavos, liquido_profissional_centavos,
                    adiantamento_centavos, custo_stripe_estimado_centavos, config_versao_id, regras_aplicadas,
                    hash_documento, aceito_em, aceite_ip)
                  values (%s,%s,%s,%s,%s,'ativo','escopo',%s,750,37500,462500,150000,2000,%s,'{"prazo":7}','abc',now(),'203.0.113.9')""",
               (cid, pedido, orc, cliente, pro, TOTAL, cfg))
        b.exec("update pedidos set status='orcamento_aceito' where id=%s", (pedido,))
        return cid

    C1 = contrato(PA, o1, S["A"], S["P1"])
    C2 = contrato(PB, o4, S["B"], S["P4"])
    b.exec("update orcamentos set status='recusado' where id=%s", (o5,))

    print("\n== (b) Endereço depois do contrato ==")
    verifica("P1 contratado, mas endereço ainda não liberado (liberado_em nulo): não vê",
             len(b.ve(S["P1"], "select 1 from pedidos_endereco where pedido_id=%s", (PA,))) == 0)
    b.exec("update pedidos_endereco set liberado_em = now() - interval '1 minute' where pedido_id in (%s,%s)", (PA, PB))
    verifica("P1 contratado e endereço liberado: vê o endereço de PA",
             b.ve(S["P1"], "select logradouro from pedidos_endereco where pedido_id=%s", (PA,))[0][0].startswith("Rua das Flores"))
    verifica("P5 (orçou e perdeu) não vê o endereço", len(b.ve(S["P5"], "select 1 from pedidos_endereco")) == 0)
    verifica("M7: P5 (orçou e perdeu) NÃO enxerga mais o pedido depois do contrato com P1",
             PA not in {r[0] for r in b.ve(S["P5"], "select id from pedidos")})
    verifica("M7: P1 (contratado) e A (dono) seguem vendo o pedido",
             all(PA in {r[0] for r in b.ve(S[c], "select id from pedidos")} for c in ("P1", "A")))
    verifica("M7: P5 não lê as respostas do pedido que perdeu",
             len(b.ve(S["P5"], "select 1 from pedido_respostas where pedido_id=%s", (PA,))) == 0)
    verifica("M7: a equipe de atendimento segue vendo o pedido",
             PA in {r[0] for r in b.ve(S["n1"], "select id from pedidos")})
    verifica("P4 (contratado por B) não vê o endereço de PA", len(b.ve(S["P4"], "select 1 from pedidos_endereco where pedido_id=%s", (PA,))) == 0)
    verifica("P4 vê o endereço do pedido que ele contratou (PB)", len(b.ve(S["P4"], "select 1 from pedidos_endereco where pedido_id=%s", (PB,))) == 1)
    verifica("P2 e P3 nunca veem endereço", len(b.ve(S["P2"], "select 1 from pedidos_endereco")) + len(b.ve(S["P3"], "select 1 from pedidos_endereco")) == 0)
    verifica("B não vê o endereço de PA", len(b.ve(S["B"], "select 1 from pedidos_endereco where pedido_id=%s", (PA,))) == 0)
    verifica("segurança vê o endereço durante o atendimento (contrato ativo)", len(b.ve(S["seg"], "select 1 from pedidos_endereco")) == 2)
    verifica("atendimento N1 e financeiro não veem endereço",
             len(b.ve(S["n1"], "select 1 from pedidos_endereco")) + len(b.ve(S["fin"], "select 1 from pedidos_endereco")) == 0)
    verifica("mediador sem disputa não vê endereço", len(b.ve(S["med"], "select 1 from pedidos_endereco")) == 0)
    b.exec("update contratos set status='cancelado' where id=%s", (C2,))
    verifica("contrato cancelado: P4 perde o endereço", len(b.ve(S["P4"], "select 1 from pedidos_endereco")) == 0)
    b.exec("update contratos set status='ativo' where id=%s", (C2,))

    print("\n== Contrato (f) ==")
    verifica("contrato: valor não muda", tem_erro(b.falha("update contratos set valor_total_centavos=1 where id=%s", (C1,)), "não pode ser alterada"))
    cfg2 = b.um("insert into config_versoes(criada_por, motivo) values (%s,'outra') returning id", (S["adm"],))
    verifica("contrato: config_versao_id não muda", tem_erro(b.falha("update contratos set config_versao_id=%s where id=%s", (cfg2, C1)), "não pode ser alterada"))
    verifica("contrato: regras_aplicadas não mudam", tem_erro(b.falha("update contratos set regras_aplicadas='{}' where id=%s", (C1,)), "não pode ser alterada"))
    verifica("contrato: não pode ser apagado", tem_erro(b.falha("delete from contratos where id=%s", (C1,)), "imutável"))
    verifica("contrato: status pode mudar", b.falha("update contratos set status='ativo' where id=%s", (C1,)) is None)
    verifica("contrato: valor diferente do orçamento aceito é recusado na criação",
             tem_erro(b.falha("""insert into contratos(pedido_id, orcamento_id, cliente_id, profissional_id, escopo_texto, valor_total_centavos,
                    taxa_bps_aplicada, taxa_trato_centavos, liquido_profissional_centavos, adiantamento_centavos, config_versao_id,
                    regras_aplicadas, hash_documento, aceito_em) values (%s,%s,%s,%s,'x',1,0,0,0,0,%s,'{}','h',now())""",
                              (PC, o5, S["A"], S["P5"], cfg)), "contrato", "orçamento"))
    verifica("A lê o contrato; B não", len(b.ve(S["A"], "select id from contratos")) == 1 and len(b.ve(S["B"], "select id from contratos where id=%s", (C1,))) == 0)
    verifica("P1 lê o contrato; P5 e P2 não", len(b.ve(S["P1"], "select id from contratos")) == 1
             and len(b.ve(S["P5"], "select id from contratos")) + len(b.ve(S["P2"], "select id from contratos")) == 0)
    verifica("contrato: IP do aceite e custo do Stripe ocultos do app",
             tem_erro(b.tenta(S["P1"], "select aceite_ip from contratos")[1], "permission denied")
             and tem_erro(b.tenta(S["A"], "select custo_stripe_estimado_centavos from contratos")[1], "permission denied"))
    verifica("contrato: pedido não ganha segundo contrato",
             tem_erro(b.falha("""insert into contratos(pedido_id, orcamento_id, cliente_id, profissional_id, escopo_texto, valor_total_centavos,
                    taxa_bps_aplicada, taxa_trato_centavos, liquido_profissional_centavos, adiantamento_centavos, config_versao_id,
                    regras_aplicadas, hash_documento, aceito_em) values (%s,%s,%s,%s,'x',%s,0,0,0,0,%s,'{}','h',now())""",
                              (PA, o5, S["A"], S["P5"], 450000, cfg)), "aceito", "duplicate"))

    print("\n== Configuração (f) ==")
    verifica("config aprovada: parâmetro não muda", tem_erro(b.falha("update config_parametros set valor=1 where versao_id=%s", (cfg,)), "aprovada"))
    verifica("config aprovada: versão não é apagada", tem_erro(b.falha("delete from config_versoes where id=%s", (cfg,)), "aprovad"))
    verifica("config aprovada: motivo não muda", tem_erro(b.falha("update config_versoes set motivo='x' where id=%s", (cfg,)), "aprovad"))
    for chave, esperado in [("fin", 1), ("adm", 1), ("A", 0), ("P1", 0), ("cad", 0), ("n1", 0)]:
        n = len(b.ve(S[chave], "select id from config_versoes"))
        verifica(f"config: {chave} vê {esperado}", (n >= 1) == (esperado == 1), f"viu {n}")

    # --- mídias, chat -----------------------------------------------------------------------------
    m_ped, m_chat, m_chat_b = (str(uuid.uuid4()) for _ in range(3))
    b.exec("""insert into midias(id, pedido_id, enviada_por, finalidade, bucket, storage_path, lat, lng) values
              (%s,%s,%s,'pedido','pedido-midias',%s,-19.9,-43.9)""", (m_ped, PA, S["A"], f"{PA}/foto1.jpg"))
    b.exec("insert into midias(id, pedido_id, enviada_por, finalidade, bucket, storage_path) values (%s,%s,%s,'chat','chat-anexos',%s)",
           (m_chat, PA, S["A"], f"{PA}/chat1.jpg"))
    b.exec("insert into midias(id, pedido_id, enviada_por, finalidade, bucket, storage_path) values (%s,%s,%s,'chat','chat-anexos',%s)",
           (m_chat_b, PB, S["B"], f"{PB}/chat1.jpg"))
    for bucket, nome in [("pedido-midias", f"{PA}/foto1.jpg"), ("chat-anexos", f"{PA}/chat1.jpg"), ("chat-anexos", f"{PB}/chat1.jpg")]:
        b.exec("insert into storage.objects(bucket_id, name) values (%s,%s)", (bucket, nome))

    cv_a_p1, cv_a_p5, cv_b_p4 = (str(uuid.uuid4()) for _ in range(3))
    b.exec("insert into conversas(id, pedido_id, cliente_id, profissional_id) values (%s,%s,%s,%s),(%s,%s,%s,%s),(%s,%s,%s,%s)",
           (cv_a_p1, PA, S["A"], S["P1"], cv_a_p5, PA, S["A"], S["P5"], cv_b_p4, PB, S["B"], S["P4"]))
    b.exec("insert into mensagens(conversa_id, autor_id, corpo, corpo_exibido, mascarada, midia_id) values (%s,%s,'meu fone 31999990000','[contato oculto]',true,%s)",
           (cv_a_p1, S["A"], m_chat))
    b.exec("insert into mensagens(conversa_id, autor_id, corpo, corpo_exibido) values (%s,%s,'oi P5','oi P5')", (cv_a_p5, S["A"]))
    b.exec("insert into mensagens(conversa_id, autor_id, corpo, corpo_exibido, midia_id) values (%s,%s,'segredo de B','segredo de B',%s)", (cv_b_p4, S["B"], m_chat_b))

    print("\n== (a) Chat ==")
    verifica("A lê as mensagens das suas duas conversas", len(b.ve(S["A"], "select id from mensagens")) == 2)
    verifica("A não lê a conversa de B", len(b.ve(S["A"], "select id from mensagens where conversa_id=%s", (cv_b_p4,))) == 0
             and len(b.ve(S["A"], "select id from conversas where id=%s", (cv_b_p4,))) == 0)
    verifica("P1 lê só a conversa dele", {r[0] for r in b.ve(S["P1"], "select conversa_id from mensagens")} == {cv_a_p1})
    verifica("P5 não lê a conversa de P1", len(b.ve(S["P5"], "select 1 from mensagens where conversa_id=%s", (cv_a_p1,))) == 0)
    verifica("texto original oculto do app (só corpo_exibido)",
             tem_erro(b.tenta(S["P1"], "select corpo from mensagens")[1], "permission denied")
             and b.ve(S["P1"], "select corpo_exibido from mensagens")[0][0] == "[contato oculto]")
    verifica("financeiro, N1 e cadastro não leem mensagens",
             sum(len(b.ve(S[c], "select id from mensagens")) for c in ("fin", "n1", "cad", "seg", "adm")) == 0)
    verifica("mediador sem disputa não lê chat", len(b.ve(S["med"], "select id from mensagens")) == 0)

    # --- agenda, presença -----------------------------------------------------------------------
    ag = str(uuid.uuid4())
    b.exec("""insert into agendamentos(id, contrato_id, data, janela_inicio, janela_fim, codigo_inicio_hash)
              values (%s,%s,current_date,now(),now() + interval '2 hours','hash-secreto')""", (ag, C1))
    print("\n== Agenda e presença ==")
    verifica("hash do código oculto do app (profissional e cliente)",
             tem_erro(b.tenta(S["P1"], "select codigo_inicio_hash from agendamentos")[1], "permission denied")
             and tem_erro(b.tenta(S["A"], "select codigo_conclusao_hash from agendamentos")[1], "permission denied"))
    verifica("partes leem o agendamento; B e P5 não",
             len(b.ve(S["A"], "select id from agendamentos")) == 1 and len(b.ve(S["P1"], "select id from agendamentos")) == 1
             and len(b.ve(S["B"], "select id from agendamentos")) + len(b.ve(S["P5"], "select id from agendamentos")) == 0)
    verifica("check-out sem check-in é recusado",
             tem_erro(b.falha("insert into presencas(agendamento_id, tipo, registrada_por) values (%s,'check_out',%s)", (ag, S["P1"])), "check-in"))
    verifica("só o profissional do contrato registra presença",
             tem_erro(b.falha("insert into presencas(agendamento_id, tipo, registrada_por) values (%s,'check_in',%s)", (ag, S["A"])), "profissional"))
    verifica("check-in e check-out entram", b.falha("insert into presencas(agendamento_id, tipo, registrada_por) values (%s,'check_in',%s)", (ag, S["P1"])) is None
             and b.falha("insert into presencas(agendamento_id, tipo, registrada_por) values (%s,'check_out',%s)", (ag, S["P1"])) is None)
    verifica("presença é imutável", tem_erro(b.falha("update presencas set codigo_validado=true"), "imutável"))
    verifica("partes leem presença; B não", len(b.ve(S["A"], "select id from presencas")) == 2 and len(b.ve(S["B"], "select id from presencas")) == 0)

    # --- pagamentos e ledger (d) ----------------------------------------------------------------
    pg1, pg2 = str(uuid.uuid4()), str(uuid.uuid4())
    b.exec("""insert into pagamentos(id, contrato_id, pagador_id, tipo, meio, valor_centavos, chave_idempotencia, status, confirmado_em,
                custo_stripe_estimado_centavos) values (%s,%s,%s,'adiantamento','pix',150000,%s,'confirmado',now(),500)""",
           (pg1, C1, S["A"], "idem-" + pg1))
    b.exec("insert into pagamentos(id, contrato_id, pagador_id, tipo, meio, valor_centavos, chave_idempotencia) values (%s,%s,%s,'adiantamento','pix',150000,%s)",
           (pg2, C2, S["B"], "idem-" + pg2))
    print("\n== (a) Pagamentos ==")
    verifica("A lê só o próprio pagamento", {r[0] for r in b.ve(S["A"], "select id from pagamentos")} == {pg1})
    verifica("B lê só o dele", {r[0] for r in b.ve(S["B"], "select id from pagamentos")} == {pg2})
    verifica("P1 lê o pagamento do contrato, sem pagador, meio nem custo",
             {r[0] for r in b.ve(S["P1"], "select id from pagamentos")} == {pg1}
             and all(tem_erro(b.tenta(S["P1"], f"select {c} from pagamentos")[1], "permission denied")
                     for c in ("pagador_id", "meio", "custo_stripe_estimado_centavos", "stripe_payment_intent_id")))
    verifica("P5 e P2 não leem pagamento", len(b.ve(S["P5"], "select id from pagamentos")) + len(b.ve(S["P2"], "select id from pagamentos")) == 0)
    verifica("pagamento só pelo cliente do contrato",
             tem_erro(b.falha("insert into pagamentos(contrato_id, pagador_id, tipo, meio, valor_centavos, chave_idempotencia) values (%s,%s,'saldo','pix',1,'x1')", (C1, S["B"])), "cliente"))
    verifica("chave de idempotência repetida é recusada",
             tem_erro(b.falha("insert into pagamentos(contrato_id, pagador_id, tipo, meio, valor_centavos, chave_idempotencia) values (%s,%s,'saldo','pix',1,%s)", (C1, S["A"], "idem-" + pg1)), "duplicate", "unique"))
    verifica("pagamento: valor não muda", tem_erro(b.falha("update pagamentos set valor_centavos=1 where id=%s", (pg1,)), "não pode ser alterada"))

    # contas e lançamentos
    caixa, retido, receita = (str(uuid.uuid4()) for _ in range(3))
    ap_p1, ap_p4 = str(uuid.uuid4()), str(uuid.uuid4())
    b.exec("""insert into contas_ledger(id, codigo, natureza, usuario_id) values
              (%s,'caixa_parceiro','ativo',null),(%s,'retido_servico','passivo',null),(%s,'receita_trato','receita',null),
              (%s,'a_pagar_profissional','passivo',%s),(%s,'a_pagar_profissional','passivo',%s)""",
           (caixa, retido, receita, ap_p1, S["P1"], ap_p4, S["P4"]))

    def lancar(contrato, tipo, partidas, chave=None, extra=None, papel=None):
        lid = str(uuid.uuid4())
        cmds = [("insert into lancamentos(id, contrato_id, tipo, chave_idempotencia, estorna_id) values (%s,%s,%s,%s,%s)",
                 (lid, contrato, tipo, chave or "l-" + lid, extra))]
        for conta, sentido, valor in partidas:
            cmds.append(("insert into partidas(lancamento_id, conta_id, sentido, valor_centavos) values (%s,%s,%s,%s)",
                         (lid, conta, sentido, valor)))
        return lid, b.transacao(cmds, papel=papel)

    L1, e1 = lancar(C1, "cobranca", [(caixa, "debito", 150000), (retido, "credito", 150000)], papel="service_role")
    print("\n== (d) Ledger ==")
    verifica("lançamento equilibrado confirma (como service_role)", e1 is None, str(e1))
    L2, e2 = lancar(C1, "repasse", [(retido, "debito", 100000), (receita, "credito", 7500), (ap_p1, "credito", 92500)])
    verifica("repasse com 3 partidas equilibradas confirma", e2 is None, str(e2))
    L3, e3 = lancar(C2, "cobranca", [(caixa, "debito", 150000), (retido, "credito", 150000)])
    L4, e4 = lancar(C2, "repasse", [(retido, "debito", 50000), (ap_p4, "credito", 50000)])
    verifica("lançamentos do outro contrato confirmam", e3 is None and e4 is None, f"{e3} {e4}")
    _, e = lancar(C1, "taxa", [(retido, "debito", 100), (receita, "credito", 99)])
    verifica("partidas DESEQUILIBRADAS são recusadas no commit", tem_erro(e, "desequilibrado"), str(e))
    _, e = lancar(C1, "taxa", [(retido, "debito", 100)])
    verifica("lançamento com uma partida só é recusado", tem_erro(e, "duas partidas"), str(e))
    _, e = lancar(C1, "taxa", [])
    verifica("lançamento sem partidas é recusado", tem_erro(e, "duas partidas"), str(e))
    verifica("partida com valor zero é recusada", tem_erro(b.transacao([
        ("insert into lancamentos(id, contrato_id, tipo, chave_idempotencia) values (%s,%s,'taxa','z1')", (str(uuid.uuid4()), C1))]
        + [("insert into partidas(lancamento_id, conta_id, sentido, valor_centavos) select id, %s, 'debito', 0 from lancamentos where chave_idempotencia='z1'", (retido,))]),
        "valor_centavos", "check"))
    verifica("nova partida em lançamento já fechado é recusada",
             tem_erro(b.falha("insert into partidas(lancamento_id, conta_id, sentido, valor_centavos) values (%s,%s,'debito',1)", (L1, caixa)), "fechado"))
    verifica("chave de idempotência repetida no lançamento é recusada",
             tem_erro(lancar(C1, "cobranca", [(caixa, "debito", 1), (retido, "credito", 1)], chave="l-" + L1)[1], "duplicate", "unique"))
    for papel in ("owner", "service_role"):
        roda = lambda sql: falha_como(b, papel, sql)
        verifica(f"ledger [{papel}]: UPDATE em partidas falha", roda("update partidas set valor_centavos=1") is not None)
        verifica(f"ledger [{papel}]: DELETE em partidas falha", roda("delete from partidas") is not None)
        verifica(f"ledger [{papel}]: UPDATE em lancamentos falha", roda("update lancamentos set descricao='x'") is not None)
        verifica(f"ledger [{papel}]: DELETE em lancamentos falha", roda("delete from lancamentos") is not None)
        verifica(f"ledger [{papel}]: TRUNCATE em partidas falha", roda("truncate partidas") is not None)
        verifica(f"ledger [{papel}]: TRUNCATE em lancamentos falha", roda("truncate lancamentos cascade") is not None)
    verifica("a mensagem de erro do owner vem do trigger de imutabilidade", tem_erro(b.falha("update partidas set valor_centavos=1"), "imutável"))

    # estorno
    _, e = lancar(C1, "estorno", [(caixa, "credito", 150000), (retido, "debito", 149999)], chave="est-ruim", extra=L1)
    verifica("estorno que NÃO inverte exatamente o original é recusado", tem_erro(e, "desequilibrado", "inverter"), str(e))
    _, e = lancar(C1, "estorno", [(caixa, "debito", 150000), (retido, "credito", 150000)], chave="est-igual", extra=L1)
    verifica("estorno com as mesmas partidas (não invertidas) é recusado", tem_erro(e, "inverter"), str(e))
    _, e = lancar(C2, "estorno", [(caixa, "credito", 150000), (retido, "debito", 150000)], chave="est-outro", extra=L1)
    verifica("estorno em contrato diferente do original é recusado", tem_erro(e, "mesmo contrato"), str(e))
    def saldo_passivo(conta):  # o ledger não tem saldo pronto (D15): a conta soma as partidas
        return b.um("select coalesce(sum(case sentido when 'credito' then valor_centavos else -valor_centavos end),0) from partidas where conta_id=%s", (conta,))
    saldo_antes = saldo_passivo(retido)
    LE, e = lancar(C1, "estorno", [(caixa, "credito", 150000), (retido, "debito", 150000)], chave="est-ok", extra=L1)
    verifica("estorno correto (partidas invertidas) confirma", e is None, str(e))
    saldo_depois = saldo_passivo(retido)
    verifica("o estorno devolve o valor (retido_servico cai 150000)", saldo_antes - saldo_depois == 150000, f"{saldo_antes}->{saldo_depois}")
    _, e = lancar(C1, "estorno", [(caixa, "credito", 150000), (retido, "debito", 150000)], chave="est-2x", extra=L1)
    verifica("um lançamento só é estornado uma vez", tem_erro(e, "duplicate", "unique"), str(e))
    verifica("tipo estorno exige estorna_id", tem_erro(b.falha("insert into lancamentos(contrato_id,tipo,chave_idempotencia) values (%s,'estorno','e-sem')", (C1,)), "check"))

    print("\n== (a) Extrato de cada usuário (sem saldo pronto, D15) ==")
    verifica("P1 vê só a própria conta", {r[0] for r in b.ve(S["P1"], "select id from contas_ledger")} == {ap_p1})
    verifica("as partidas de P1 somam 92500 (extrato)", b.ve(S["P1"], "select sum(valor_centavos) from partidas")[0][0] == 92500)
    verifica("P4 vê só a dele", {r[0] for r in b.ve(S["P4"], "select id from contas_ledger")} == {ap_p4})
    verifica("não existe view de saldo, tabela de saques nem de chaves Pix (D15)",
             b.um("select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname='public' and c.relname in ('saldos_contas','saques','chaves_pix')") == 0)
    verifica("P1 não lê as contas nem as partidas de P4",
             len(b.ve(S["P1"], "select 1 from contas_ledger where id=%s", (ap_p4,))) == 0
             and len(b.ve(S["P1"], "select 1 from partidas where conta_id=%s", (ap_p4,))) == 0)
    verifica("P1 vê no extrato só lançamentos que tocam a conta dele", {r[0] for r in b.ve(S["P1"], "select id from lancamentos")} == {L2})
    verifica("P1 não vê as contas de sistema (retido, caixa, receita)",
             len(b.ve(S["P1"], "select 1 from contas_ledger where usuario_id is null")) == 0)
    verifica("cliente A não lê nada do ledger",
             len(b.ve(S["A"], "select 1 from contas_ledger")) + len(b.ve(S["A"], "select 1 from partidas")) + len(b.ve(S["A"], "select 1 from lancamentos")) == 0)
    verifica("financeiro lê o ledger inteiro", len(b.ve(S["fin"], "select 1 from partidas")) >= 10 and len(b.ve(S["fin"], "select 1 from contas_ledger")) == 5)
    verifica("mediador, N1 e cadastro não leem o ledger",
             sum(len(b.ve(S[c], "select 1 from partidas")) for c in ("med", "n1", "cad", "seg")) == 0)

    # repasses (ordem de liberação ao parceiro)
    rep = str(uuid.uuid4())
    b.exec("""insert into repasses(id, contrato_id, profissional_id, valor_bruto_centavos, taxa_centavos, valor_liquido_centavos,
                gatilho, chave_idempotencia) values (%s,%s,%s,100000,7500,92500,'confirmacao_cliente',%s)""", (rep, C1, S["P1"], "rep-" + rep))
    print("\n== Repasses (ordem de liberação ao parceiro) ==")
    verifica("repasse: bruto = taxa + líquido", tem_erro(b.falha("""insert into repasses(contrato_id, profissional_id, valor_bruto_centavos, taxa_centavos,
        valor_liquido_centavos, gatilho, chave_idempotencia) values (%s,%s,100,1,1,'prazo','r-ruim')""", (C1, S["P1"])), "check"))
    verifica("repasse só vai para o profissional do contrato", tem_erro(b.falha("""insert into repasses(contrato_id, profissional_id, valor_bruto_centavos, taxa_centavos,
        valor_liquido_centavos, gatilho, chave_idempotencia) values (%s,%s,100,0,100,'prazo','r-outro')""", (C1, S["P5"])), "profissional do contrato"))
    verifica("P1 lê o próprio repasse; P4, P5 e A não", len(b.ve(S["P1"], "select 1 from repasses")) == 1
             and len(b.ve(S["P4"], "select 1 from repasses")) + len(b.ve(S["A"], "select 1 from repasses")) + len(b.ve(S["P5"], "select 1 from repasses")) == 0)
    verifica("financeiro lê repasses; mediador também (leitura)", len(b.ve(S["fin"], "select 1 from repasses")) == 1)
    verifica("repasse: id da transferência no parceiro é único",
             b.falha("update repasses set provedor_transferencia_id='tr_1' where id=%s", (rep,)) is None
             and tem_erro(b.falha("""insert into repasses(contrato_id, profissional_id, valor_bruto_centavos, taxa_centavos,
                valor_liquido_centavos, gatilho, chave_idempotencia, provedor_transferencia_id) values (%s,%s,100,0,100,'prazo','r-dup','tr_1')""", (C1, S["P1"])), "duplicate", "unique"))
    verifica("lançamento sem contrato é recusado (não há mais saque)",
             tem_erro(b.falha("insert into lancamentos(tipo, chave_idempotencia) values ('taxa','sem-ctr')"), "null", "contrato_id"))
    verifica("lançamento do tipo 'saque' é recusado",
             tem_erro(b.falha("insert into lancamentos(contrato_id, tipo, chave_idempotencia) values (%s,'saque','l-saque')", (C1,)), "check"))
    verifica("webhook: só o financeiro lê", len(b.ve(S["P1"], "select 1 from eventos_webhook")) == 0
             and b.exec("select 1")[0][0] == 1)
    b.exec("insert into eventos_webhook(provedor, evento_id, tipo, assinatura_valida, payload) values ('stripe','evt_1','payment_intent.succeeded',true,'{}')")
    ev = b.um("select id from eventos_webhook where evento_id='evt_1'")
    lid = str(uuid.uuid4())
    e = b.transacao([("insert into lancamentos(id, contrato_id, tipo, chave_idempotencia, evento_webhook_id) values (%s,%s,'cobranca','l-ev',%s)", (lid, C1, ev)),
                     ("insert into partidas(lancamento_id, conta_id, sentido, valor_centavos) values (%s,%s,'debito',10)", (lid, caixa)),
                     ("insert into partidas(lancamento_id, conta_id, sentido, valor_centavos) values (%s,%s,'credito',10)", (lid, retido))], papel="service_role")
    verifica("lançamento espelha um evento do parceiro (evento_webhook_id)", e is None, str(e))
    verifica("lançamento com evento inexistente é recusado",
             tem_erro(b.falha("insert into lancamentos(contrato_id, tipo, chave_idempotencia, evento_webhook_id) values (%s,'taxa','l-ev2',%s)", (C1, str(uuid.uuid4()))), "foreign key", "violates"))
    verifica("webhook repetido (mesmo evento) é recusado", tem_erro(b.falha("insert into eventos_webhook(provedor, evento_id, tipo, assinatura_valida, payload) values ('stripe','evt_1','x',true,'{}')"), "duplicate", "unique"))
    verifica("webhook com assinatura inválida não pode ser marcado como processado",
             tem_erro(b.falha("insert into eventos_webhook(provedor, evento_id, tipo, assinatura_valida, payload, processado_em) values ('stripe','evt_2','x',false,'{}',now())"), "check"))
    verifica("financeiro lê webhooks; mediador não", len(b.ve(S["fin"], "select 1 from eventos_webhook")) == 1 and len(b.ve(S["med"], "select 1 from eventos_webhook")) == 0)

    # --- disputa, garantia, avaliação -------------------------------------------------------------
    disp = str(uuid.uuid4())
    b.exec("insert into disputas(id, contrato_id, pedido_id, aberta_por, motivo, descricao, valor_congelado_centavos) values (%s,%s,%s,%s,'mal_feito','pintura riscada',400000)",
           (disp, C1, PA, S["A"]))
    b.exec("insert into disputa_evidencias(disputa_id, autor_id, tipo, texto) values (%s,%s,'relato','ficou torto')", (disp, S["A"]))
    b.exec("insert into disputa_evidencias(disputa_id, autor_id, tipo, texto, visivel_as_partes) values (%s,%s,'nota_interna','cliente parece honesto',false)", (disp, S["med"]))
    print("\n== Disputa ==")
    verifica("segunda disputa ativa no mesmo contrato é recusada",
             tem_erro(b.falha("insert into disputas(contrato_id, pedido_id, aberta_por, motivo, descricao) values (%s,%s,%s,'dano','x')", (C1, PA, S["A"])), "duplicate", "unique"))
    verifica("disputa só aberta pelas partes", tem_erro(b.falha("insert into disputas(contrato_id, pedido_id, aberta_por, motivo, descricao) values (%s,%s,%s,'dano','x')", (C2, PB, S["A"])), "partes"))
    verifica("partes e mediador leem a disputa; B e P5 não",
             all(len(b.ve(S[c], "select 1 from disputas")) == 1 for c in ("A", "P1", "med", "fin"))
             and sum(len(b.ve(S[c], "select 1 from disputas")) for c in ("B", "P5", "P4", "cad", "seg")) == 0)
    verifica("disputa: relato_ma_fe/procedente/decidida_por ocultos do app",
             all(tem_erro(b.tenta(S["A"], f"select {c} from disputas")[1], "permission denied") for c in ("relato_ma_fe", "procedente", "decidida_por")))
    verifica("evidências: partes veem só as visíveis (sem nota interna)", len(b.ve(S["A"], "select 1 from disputa_evidencias")) == 1
             and len(b.ve(S["P1"], "select 1 from disputa_evidencias")) == 1)
    verifica("evidências: mediador vê todas (inclui nota interna)", len(b.ve(S["med"], "select 1 from disputa_evidencias")) == 2)
    verifica("evidências: financeiro não vê nota interna", len(b.ve(S["fin"], "select 1 from disputa_evidencias")) == 1)
    verifica("nota interna só da equipe", tem_erro(b.falha("insert into disputa_evidencias(disputa_id, autor_id, tipo, texto, visivel_as_partes) values (%s,%s,'nota_interna','x',false)", (disp, S["A"])), "equipe"))
    verifica("evidência é imutável", tem_erro(b.falha("update disputa_evidencias set texto='x'"), "imutável"))
    verifica("agora o mediador lê o endereço do pedido em disputa", len(b.ve(S["med"], "select 1 from pedidos_endereco where pedido_id=%s", (PA,))) == 1
             and len(b.ve(S["med"], "select 1 from pedidos_endereco where pedido_id=%s", (PB,))) == 0)
    verifica("mediador lê o chat só do pedido em disputa", {r[0] for r in b.ve(S["med"], "select conversa_id from mensagens")} == {cv_a_p1, cv_a_p5})
    verifica("mediador não lê o texto original da mensagem", tem_erro(b.tenta(S["med"], "select corpo from mensagens")[1], "permission denied"))
    verifica("financeiro continua sem ler chat", len(b.ve(S["fin"], "select 1 from mensagens")) == 0)
    # alçada
    sql_dec = ("update disputas set status='decidida', decisao='reembolso_total', decidida_por=%s, aprovada_por=%s, "
               "decidida_em=now(), justificativa='provas ok' where id=%s")
    verifica("decisão acima da alçada sem 2ª pessoa é recusada", tem_erro(b.falha(sql_dec, (S["med"], None, disp)), "alçada"))
    verifica("decisão de reembolso aprovada pela mesma pessoa é recusada", tem_erro(b.falha(sql_dec, (S["med"], S["med"], disp)), "alçada", "check"))
    verifica("financeiro não decide mérito", tem_erro(b.falha(sql_dec, (S["fin"], S["lider"], disp)), "mediador"))
    verifica("aprovador precisa ser líder ou administrador", tem_erro(b.falha(sql_dec, (S["med"], S["cad"], disp)), "alçada"))
    verifica("decisão acima da alçada com líder de suporte aprova", b.falha(sql_dec, (S["med"], S["lider"], disp)) is None)
    verifica("disputa decidida não muda mais", tem_erro(b.falha("update disputas set justificativa='outra' where id=%s", (disp,)), "não pode mais mudar"))

    gar = str(uuid.uuid4())
    b.exec("insert into garantias(id, contrato_id, inicio_em, fim_em, dias) values (%s,%s,now(),now() + interval '30 days',30)", (gar, C1))
    verifica("garantia/retrabalho: partes leem; B não", len(b.ve(S["A"], "select 1 from garantias")) == 1 and len(b.ve(S["B"], "select 1 from garantias")) == 0)
    verifica("retrabalho só pelo cliente do contrato", tem_erro(b.falha("insert into retrabalhos(garantia_id, aberto_por, descricao) values (%s,%s,'x')", (gar, S["P1"])), "cliente"))
    verifica("retrabalho dentro da garantia entra", b.falha("insert into retrabalhos(garantia_id, aberto_por, descricao) values (%s,%s,'refazer')", (gar, S["A"])) is None)
    verifica("retrabalho: P1 e A leem; B não", len(b.ve(S["P1"], "select 1 from retrabalhos")) == 1 and len(b.ve(S["B"], "select 1 from retrabalhos")) == 0)

    print("\n== Avaliações ==")
    av1, av2 = str(uuid.uuid4()), str(uuid.uuid4())
    b.exec("insert into avaliacoes(id, contrato_id, direcao, avaliador_id, avaliado_id, nota_geral) values (%s,%s,'cliente_para_profissional',%s,%s,5)", (av1, C1, S["A"], S["P1"]))
    b.exec("insert into avaliacoes(id, contrato_id, direcao, avaliador_id, avaliado_id, nota_geral) values (%s,%s,'profissional_para_cliente',%s,%s,2)", (av2, C1, S["P1"], S["A"]))
    b.exec("insert into avaliacao_criterios(avaliacao_id, criterio, nota) values (%s,'pontualidade',5)", (av1,))
    verifica("avaliação: avaliador trocado é recusado", tem_erro(b.falha("insert into avaliacoes(contrato_id, direcao, avaliador_id, avaliado_id, nota_geral) values (%s,'cliente_para_profissional',%s,%s,3)", (C2, S["A"], S["P4"])), "não batem"))
    verifica("avaliação: critério de outra direção é recusado", tem_erro(b.falha("insert into avaliacao_criterios(avaliacao_id, criterio, nota) values (%s,'limpeza',4)", (av2,)), "direção"))
    verifica("avaliação: nota do cliente para o profissional é pública (B e P2 leem)",
             av1 in {r[0] for r in b.ve(S["B"], "select id from avaliacoes")} and av1 in {r[0] for r in b.ve(S["P2"], "select id from avaliacoes")})
    verifica("avaliação: nota do profissional para o cliente NÃO é pública (B e P2 não leem)",
             av2 not in {r[0] for r in b.ve(S["B"], "select id from avaliacoes")} and av2 not in {r[0] for r in b.ve(S["P2"], "select id from avaliacoes")})
    verifica("avaliação: o cliente, o avaliador e o profissional que orçou leem a nota do cliente",
             all(av2 in {r[0] for r in b.ve(S[c], "select id from avaliacoes")} for c in ("A", "P1", "P5")))
    verifica("avaliação: critérios seguem a visibilidade", len(b.ve(S["B"], "select 1 from avaliacao_criterios")) == 1)
    verifica("avaliação: nota não pode ser editada", tem_erro(b.falha("update avaliacoes set nota_geral=1 where id=%s", (av1,)), "não pode ser alterada"))
    b.exec("update avaliacoes set status='em_revisao' where id=%s", (av1,))
    verifica("avaliação em revisão some para terceiros e continua para o moderador",
             av1 not in {r[0] for r in b.ve(S["B"], "select id from avaliacoes")} and av1 in {r[0] for r in b.ve(S["mod"], "select id from avaliacoes")}
             and av1 in {r[0] for r in b.ve(S["A"], "select id from avaliacoes")})

    # --- mensagens imutáveis (e) --------------------------------------------------------------
    print("\n== (e) Mensagens e auditoria imutáveis ==")
    msg_id = b.um("select id from mensagens where conversa_id=%s limit 1", (cv_a_p5,))
    for papel in ("owner", "service_role"):
        roda2 = lambda sql: falha_como(b, papel, sql)
        verifica(f"mensagem [{papel}]: editar o texto falha", roda2(f"update mensagens set corpo='alterado' where id={msg_id}") is not None)
        verifica(f"mensagem [{papel}]: apagar falha", roda2(f"delete from mensagens where id={msg_id}") is not None)
        verifica(f"mensagem [{papel}]: TRUNCATE falha", roda2("truncate mensagens cascade") is not None)
    verifica("mensagem: lida_em pode ser preenchido uma vez", b.falha("update mensagens set lida_em=now() where id=%s", (msg_id,)) is None)
    verifica("mensagem: lida_em não muda de novo", tem_erro(b.falha("update mensagens set lida_em=now() + interval '1 day' where id=%s", (msg_id,)), "não é editável"))
    verifica("mensagem: só as partes escrevem na conversa", tem_erro(b.falha("insert into mensagens(conversa_id, autor_id, corpo, corpo_exibido) values (%s,%s,'invasor','invasor')", (cv_a_p1, S["B"])), "partes"))
    verifica("mensagem: anexo de outro pedido é recusado", tem_erro(b.falha("insert into mensagens(conversa_id, autor_id, corpo, corpo_exibido, midia_id) values (%s,%s,'x','x',%s)", (cv_a_p1, S["A"], m_chat_b)), "anexo"))
    verifica("conversa: pedido de outro cliente é recusado", tem_erro(b.falha("insert into conversas(pedido_id, cliente_id, profissional_id) values (%s,%s,%s)", (PB, S["A"], S["P5"])), "cliente"))
    verifica("mídia é imutável", tem_erro(b.falha("update midias set storage_path='x'"), "imutável"))
    verifica("histórico do pedido é imutável",
             b.falha("insert into pedido_historico(pedido_id, de_status, para_status) values (%s,'aberto','orcamento_aceito')", (PA,)) is None
             and tem_erro(b.falha("delete from pedido_historico"), "imutável"))

    aud_ids = []
    for acao, motivo in [("contrato.aceito", None), ("checkin.registrado", None), ("repasse.liberado", "confirmação do cliente")]:
        r = b.tenta(None, "select public.registrar_auditoria(%s,'sistema',%s,'contrato',%s,null,'{\"ok\":true}'::jsonb,%s)",
                    (None, acao, C1, motivo), papel="service_role")
        verifica(f"auditoria: service_role registra {acao}", r[0] == "ok", str(r))
        if r[0] == "ok":
            aud_ids.append(r[1][0][0])
    # as chamadas acima rodam em transação desfeita: refaz de verdade pelo dono para ter linhas
    b.exec("select public.registrar_auditoria(null,'sistema','contrato.aceito','contrato',%s)", (C1,))
    b.exec("select public.registrar_auditoria(%s,'equipe','dado_pessoal.revelado','usuario',%s,null,null,'chamado 123')", (S["seg"], S["A"]))
    b.exec("select public.registrar_auditoria(null,'sistema','repasse.liberado','repasse',%s,null,null,'prazo vencido')", (rep,))
    verifica("auditoria: ação financeira sem motivo é recusada", tem_erro(b.falha("select public.registrar_auditoria(null,'sistema','repasse.liberado','repasse',%s)", (rep,)), "check"))
    verifica("auditoria: revelar dado pessoal sem motivo é recusado", tem_erro(b.falha("select public.registrar_auditoria(null,'equipe','dado_pessoal.revelado')"), "check"))
    verifica("auditoria: cadeia de hash íntegra", b.um("select public.verificar_cadeia_auditoria()") is None)
    verifica("auditoria: hash_anterior encadeado", b.um("select count(*) from auditoria a join auditoria b on b.id = (select max(id) from auditoria where id < a.id) where a.hash_anterior = b.hash") == b.um("select count(*) from auditoria") - 1)
    for papel in ("owner", "service_role"):
        roda3 = lambda sql: falha_como(b, papel, sql)
        verifica(f"auditoria [{papel}]: UPDATE falha", roda3("update auditoria set motivo='x'") is not None)
        verifica(f"auditoria [{papel}]: DELETE falha", roda3("delete from auditoria") is not None)
        verifica(f"auditoria [{papel}]: TRUNCATE falha", roda3("truncate auditoria") is not None)
    verifica("auditoria: INSERT direto do service_role falha (só por registrar_auditoria)",
             b.tenta(None, "insert into auditoria(ocorrida_em, ator_tipo, acao, hash) values (now(),'sistema','x.y','h')", papel="service_role")[0] == "erro")
    # adulteração detectada: como superusuário, desliga o trigger DENTRO de uma transação que é desfeita
    cur = b.tx.cursor()
    cur.execute("alter table auditoria disable trigger auditoria_imutavel")
    cur.execute("update auditoria set depois='{\"ok\":false}' where id=(select min(id) from auditoria)")
    cur.execute("select public.verificar_cadeia_auditoria()")
    achou = cur.fetchone()[0]
    b.tx.rollback()
    verifica("auditoria: adulteração direta é detectada pela cadeia", achou is not None and achou == b.um("select min(id) from auditoria"))
    cur = b.tx.cursor()
    cur.execute("alter table auditoria disable trigger auditoria_imutavel")
    cur.execute("delete from auditoria where id=(select id from auditoria order by id offset 1 limit 1)")
    cur.execute("select public.verificar_cadeia_auditoria()")
    achou2 = cur.fetchone()[0]
    b.tx.rollback()
    verifica("auditoria: remoção de uma linha é detectada pela cadeia", achou2 is not None)
    print("\n== Auditoria: quem lê ==")
    for chave, esperado in [("adm", True), ("dpo", True), ("seg", True), ("n1", False), ("fin", False), ("A", False), ("P1", False), ("mod", False)]:
        n = len(b.ve(S[chave], "select id from auditoria"))
        verifica(f"auditoria: {chave} {'lê' if esperado else 'não lê'}", (n > 0) == esperado, f"viu {n}")
    verifica("auditoria e config: o jurídico lê", len(b.ve(S["jur"], "select 1 from auditoria")) > 0 and len(b.ve(S["jur"], "select 1 from config_versoes")) > 0)

    # --- notificações, usuários, perfis ---------------------------------------------------------------
    b.exec("insert into notificacoes(usuario_id, tipo, canal, titulo) values (%s,'x','app','para A'),(%s,'x','app','para B')", (S["A"], S["B"]))
    b.exec("insert into notificacao_preferencias(usuario_id) values (%s),(%s)", (S["A"], S["B"]))
    print("\n== Notificações, usuários e perfis ==")
    verifica("notificações: cada um lê só as suas", [r[0] for r in b.ve(S["A"], "select titulo from notificacoes")] == ["para A"]
             and [r[0] for r in b.ve(S["B"], "select titulo from notificacoes")] == ["para B"])
    verifica("preferências: cada um lê só as suas", len(b.ve(S["A"], "select 1 from notificacao_preferencias")) == 1)
    verifica("equipe não lê notificação de usuário", len(b.ve(S["adm"], "select 1 from notificacoes")) == 0)
    verifica("CPF/telefone: A lê só o próprio", [r[0] for r in b.ve(S["A"], "select usuario_id::text from usuarios_privados")] == [S["A"]])
    verifica("CPF/telefone: P1 não lê os de A (outra parte do contrato)",
             len(b.ve(S["P1"], "select 1 from usuarios_privados where usuario_id=%s", (S["A"],))) == 0)
    verifica("CPF/telefone: nem a equipe lê o de outras pessoas direto (só pelo backend)",
             sum(len(b.ve(S[c], "select 1 from usuarios_privados where usuario_id <> %s", (S[c],))) for c in ("cad", "adm", "dpo", "seg", "n1")) == 0)
    verifica("usuarios: A vê o nome de P1 (aprovado) e o próprio, não o de B",
             {r[0] for r in b.ve(S["A"], "select id::text from usuarios")} >= {S["A"], S["P1"]}
             and S["B"] not in {r[0] for r in b.ve(S["A"], "select id::text from usuarios")})
    verifica("usuarios: P1 vê o nome do cliente A (contrato) e não o de B",
             S["A"] in {r[0] for r in b.ve(S["P1"], "select id::text from usuarios")}
             and S["B"] not in {r[0] for r in b.ve(S["P1"], "select id::text from usuarios")})
    verifica("usuarios: P2 (sem relação) não vê o nome de A", S["A"] not in {r[0] for r in b.ve(S["P2"], "select id::text from usuarios")})
    verifica("usuarios: status/aceite de termos ocultos", tem_erro(b.tenta(S["A"], "select status from usuarios")[1], "permission denied"))
    verifica("perfis: A vê perfis aprovados e não o do PX em análise",
             str(PX) not in {r[0] for r in b.ve(S["A"], "select usuario_id::text from perfis_profissional")}
             and S["P1"] in {r[0] for r in b.ve(S["A"], "select usuario_id::text from perfis_profissional")})
    verifica("perfis: CNPJ oculto de quem não é o app dono (nem o dono lê direto)", tem_erro(b.tenta(S["A"], "select cnpj from perfis_profissional")[1], "permission denied"))
    verifica("perfis: o PX em análise vê o próprio perfil", str(PX) in {r[0] for r in b.ve(str(PX), "select usuario_id::text from perfis_profissional")})
    verifica("equipe: tabela só para o administrador e a própria linha", len(b.ve(S["adm"], "select 1 from equipe")) == b.um("select count(*) from equipe")
             and len(b.ve(S["fin"], "select 1 from equipe")) == 1 and len(b.ve(S["A"], "select 1 from equipe")) == 0)
    verifica("catálogo: cliente lê cidades e categorias ativas", len(b.ve(S["A"], "select 1 from cidades")) >= 2 and len(b.ve(S["A"], "select 1 from categorias")) >= 2)
    b.exec("update categorias set ativa=false where id=%s", (cat2,))
    verifica("catálogo: categoria inativa some para o cliente e aparece para a equipe",
             len(b.ve(S["A"], "select 1 from categorias where id=%s", (cat2,))) == 0 and len(b.ve(S["cad"], "select 1 from categorias where id=%s", (cat2,))) == 1)
    verifica("regiões/categorias do profissional: A vê as de P1 aprovado; não as do PX",
             len(b.ve(S["A"], "select 1 from profissional_regioes where profissional_id=%s", (S["P1"],))) == 1
             and len(b.ve(S["A"], "select 1 from profissional_regioes where profissional_id=%s", (str(PX),))) == 0)

    # --- N1/N2 atendimento ------------------------------------------------------------------------
    print("\n== Equipe de atendimento: o que pode ==")
    verifica("N1 consulta pedido, contrato e pagamento", all(len(b.ve(S["n1"], f"select 1 from {t}")) > 0 for t in ("pedidos", "contratos", "pagamentos")))
    verifica("N1 não vê documentos, ledger, webhooks, chat nem endereço",
             sum(len(b.ve(S["n1"], f"select 1 from {t}")) for t in ("partidas", "eventos_webhook", "mensagens", "pedidos_endereco")) == 0)
    verifica("moderador não vê dados financeiros",
             sum(len(b.ve(S["mod"], f"select 1 from {t}")) for t in ("pagamentos", "partidas", "eventos_webhook", "repasses", "contratos")) == 0)
    verifica("cadastro não vê pedido, pagamento nem repasse",
             sum(len(b.ve(S["cad"], f"select 1 from {t}")) for t in ("pedidos", "pagamentos", "repasses", "contratos")) == 0)
    verifica("seguranca vê contrato (localização), mas não ledger", len(b.ve(S["seg"], "select 1 from contratos")) == 2 and len(b.ve(S["seg"], "select 1 from partidas")) == 0)

    # --- storage -------------------------------------------------------------------------------
    print("\n== Storage (buckets privados) ==")
    pm = "select name from storage.objects where bucket_id='pedido-midias'"
    cx = "select name from storage.objects where bucket_id='chat-anexos'"
    verifica("buckets existem e são todos privados",
             b.um("select count(*) from storage.buckets where id in ('verificacao','pedido-midias','chat-anexos','avatar') and public = false") == 4)
    verifica("foto do pedido: A e P1 leem; P5 (orçou e perdeu) não lê mais (M7)",
             all(len(b.ve(S[c], pm)) == 1 for c in ("A", "P1")) and len(b.ve(S["P5"], pm)) == 0)
    verifica("foto do pedido: B, P2, P3 e PX não leem", sum(len(b.ve(S[c], pm)) for c in ("B", "P2", "P3")) + len(b.ve(str(PX), pm)) == 0)
    verifica("foto do pedido: anon não lê", b.tenta(None, pm, papel="anon")[0] == "erro" or len(b.ve(None, pm, papel="anon")) == 0)
    verifica("chat: A e P1 leem o anexo da conversa deles; P5 não", len(b.ve(S["A"], cx)) == 1 and len(b.ve(S["P1"], cx)) == 1 and len(b.ve(S["P5"], cx)) == 0)
    verifica("chat: B lê só o anexo do chat dele", [r[0] for r in b.ve(S["B"], cx)] == [f"{PB}/chat1.jpg"] and len(b.ve(S["P4"], cx)) == 1)
    verifica("chat: mediador lê o anexo do pedido em disputa e não o do outro", [r[0] for r in b.ve(S["med"], cx)] == [f"{PA}/chat1.jpg"])
    verifica("chat: financeiro e N1 não leem anexos", len(b.ve(S["fin"], cx)) + len(b.ve(S["n1"], cx)) == 0)
    verifica("app não grava no Storage (sem policy de INSERT)",
             b.tenta(S["A"], "insert into storage.objects(bucket_id, name) values ('pedido-midias', %s)", (f"{PA}/hack.jpg",))[0] == "erro")
    verifica("app não apaga nem altera arquivos do Storage",
             len(b.ve(S["A"], "update storage.objects set name = name || 'x' where bucket_id='pedido-midias' returning 1")) == 0
             and len(b.ve(S["A"], "delete from storage.objects where bucket_id='pedido-midias' returning 1")) == 0)

    print("\n== Fix de acesso: M6 (Storage e tabelas futuras) e M7 (histórico do pedido) ==")
    # M6: com uma policy permissiva de teste, só a restritiva `conta_ativa_obrigatoria` separa A de D.
    b.exec("insert into storage.objects(bucket_id, name) values ('avatar', %s)", (f"{S['D']}/m6.jpg",))
    b.exec("create policy teste_m6_aberta on storage.objects for select to authenticated using (bucket_id = 'avatar')")
    verifica("M6: conta ativa lê o Storage quando a policy permite",
             len(b.ve(S["A"], "select name from storage.objects where bucket_id='avatar'")) >= 1)
    verifica("M6: conta bloqueada NÃO lê o Storage nem quando a policy permite",
             len(b.ve(S["D"], "select name from storage.objects where bucket_id='avatar'")) == 0)
    b.exec("drop policy teste_m6_aberta on storage.objects")
    b.exec("create table public.tabela_futura_teste (id int)")
    verifica("M6: tabela criada DEPOIS nasce com RLS e a policy restritiva (gatilho de evento)",
             b.um("select relrowsecurity from pg_class where oid = 'public.tabela_futura_teste'::regclass") is True
             and b.um("select count(*) from pg_policies where tablename='tabela_futura_teste' "
                      "and policyname='conta_ativa_obrigatoria' and permissive='RESTRICTIVE'") == 1)
    b.exec("drop table public.tabela_futura_teste")
    verifica("M6: toda tabela de public tem a policy restritiva",
             b.um("select count(*) from pg_tables t where schemaname='public' and not exists "
                  "(select 1 from pg_policies p where p.schemaname='public' and p.tablename=t.tablename "
                  "and p.policyname='conta_ativa_obrigatoria')") == 0)
    # M7: histórico (prova em JSON) só das partes e da equipe
    b.exec("insert into pedido_historico(pedido_id, de_status, para_status) values (%s,'orcamento_aceito','agendado')", (PA,))
    verifica("M7: histórico do pedido: A, P1 (contratado) e a equipe de atendimento leem",
             all(len(b.ve(S[c], "select 1 from pedido_historico where pedido_id=%s", (PA,))) >= 1 for c in ("A", "P1", "n1", "fin", "med")))
    verifica("M7: histórico do pedido: P5 (perdeu), B, P2 e cadastro NÃO leem",
             sum(len(b.ve(S[c], "select 1 from pedido_historico where pedido_id=%s", (PA,))) for c in ("P5", "B", "P2", "cad")) == 0)
    b.exec("update usuarios set foto_path=%s where id=%s", (f"{S['P1']}/avatar.png", S["P1"]))
    b.exec("insert into storage.objects(bucket_id, name) values ('avatar', %s)", (f"{S['P1']}/avatar.png",))
    verifica("avatar: A vê a foto de P1 (profissional aprovado)",
             len(b.ve(S["A"], "select 1 from storage.objects where bucket_id='avatar'")) == 1)

    return S


# ---------------------------------------------------------------------------------------------
# Verificações globais de segurança (g)
# ---------------------------------------------------------------------------------------------
def seguranca_global(b):
    print("\n== (g) anon não lê nada; o app não escreve; funções seguras ==")
    tabelas = [r[0] for r in b.exec("select tablename from pg_tables where schemaname='public' order by 1")]
    visoes = [r[0] for r in b.exec("select viewname from pg_views where schemaname='public'")]
    verifica(f"RLS ligado em TODAS as {len(tabelas)} tabelas do schema public",
             b.um("select count(*) from pg_tables where schemaname='public' and not rowsecurity") == 0)
    nao_lidas = [t for t in tabelas + visoes if b.tenta(None, f"select * from public.{t} limit 1", papel="anon")[0] != "erro"]
    verifica(f"anon não consegue ler nenhuma das {len(tabelas) + len(visoes)} tabelas/views", not nao_lidas, str(nao_lidas))
    escreve = [t for t in tabelas
               if any(b.um("select has_table_privilege('authenticated', %s, %s)", (f"public.{t}", p)) for p in ("insert", "update", "delete", "truncate"))]
    verifica("authenticated (o app) não tem INSERT/UPDATE/DELETE/TRUNCATE em nenhuma tabela", not escreve, str(escreve))
    anon_priv = [t for t in tabelas + visoes
                 if any(b.um("select has_table_privilege('anon', %s, %s)", (f"public.{t}", p)) for p in ("select", "insert", "update", "delete", "truncate", "references", "trigger"))]
    verifica("anon não tem nenhum privilégio em nenhuma tabela", not anon_priv, str(anon_priv))
    verifica("nenhuma policy usa using (true)", b.um("select count(*) from pg_policies where qual = 'true' or with_check = 'true'") == 0)
    verifica("toda policy é só para authenticated", b.um("select count(*) from pg_policies where roles <> '{authenticated}'") == 0)
    verifica("só policies de SELECT (o app não escreve)", b.um("select count(*) from pg_policies where cmd <> 'SELECT'") == 0)
    sem_pol = [t for t in tabelas if b.um("select count(*) from pg_policies where schemaname='public' and tablename=%s and permissive='PERMISSIVE'", (t,)) == 0]
    print(f"      (tabelas sem policy permissiva = ninguém do app lê: {sem_pol})")
    verifica("somente tabelas de uso exclusivo do backend ficam sem policy de leitura", set(sem_pol) == {"agendador_execucoes", "dispositivos_push", "verificacao_documentos"}, str(sem_pol))
    # (as 2 primeiras são do agendador/push, só do backend; verificacao_documentos virou só-backend no fix de acesso, A8)
    sd = b.exec("""select n.nspname||'.'||p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                    where n.nspname in ('public','privado') and p.prosecdef
                      and not (coalesce(p.proconfig, '{}') @> array['search_path=""'])""")
    verifica("TODA função SECURITY DEFINER tem search_path vazio", not sd, str(sd))
    exec_anon = b.exec("""select n.nspname||'.'||p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                           where n.nspname in ('public','privado') and p.prokind='f'
                             and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'))""")
    verifica("NENHUMA função (public/privado) é executável por anon ou PUBLIC", not exec_anon, str(exec_anon))
    sd_auth = b.exec("""select n.nspname||'.'||p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                         where n.nspname='public' and p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute')""")
    verifica("nenhuma função SECURITY DEFINER do schema public é chamável pelo app (RPC)", not sd_auth, str(sd_auth))
    verifica("rls_auto_enable não é executável por anon (lição do advisor)", not b.um("select has_function_privilege('anon','public.rls_auto_enable()','execute')"))
    # O backend precisa funcionar: service_role lê tudo, escreve onde deve e nunca faz TRUNCATE.
    nao_le = [t for t in tabelas if b.tenta(None, f"select count(*) from public.{t}", papel="service_role")[0] != "ok"]
    verifica(f"service_role lê todas as {len(tabelas)} tabelas (o backend funciona)", not nao_le, str(nao_le))
    truncou = [t for t in tabelas if b.um("select has_table_privilege('service_role', %s, 'truncate')", (f"public.{t}",))]
    verifica("service_role não tem TRUNCATE em nenhuma tabela", not truncou, str(truncou))
    ref = [t for t in tabelas if any(b.um("select has_table_privilege(%s, %s, 'truncate')", (r, f"public.{t}")) for r in ("anon", "authenticated"))]
    verifica("anon e authenticated não têm TRUNCATE em nenhuma tabela", not ref, str(ref))
    verifica("service_role consegue gravar pedido e ler de volta (grants do backend)",
             b.tenta(None, """with c as (select id from usuarios limit 1), g as (select id from categorias limit 1), d as (select id from cidades limit 1)
                insert into pedidos(cliente_id, categoria_id, cidade_id, titulo, descricao)
                select c.id, g.id, d.id, 't', 'd' from c, g, d returning id""", papel="service_role")[0] == "ok")
    verifica("anon não tem acesso ao schema privado", not b.um("select has_schema_privilege('anon','privado','usage')"))
    verifica("registrar_auditoria só é executável pelo service_role",
             b.um("select has_function_privilege('service_role','public.registrar_auditoria(uuid,text,text,text,uuid,jsonb,jsonb,text,text,text,text)','execute')")
             and not b.um("select has_function_privilege('authenticated','public.registrar_auditoria(uuid,text,text,text,uuid,jsonb,jsonb,text,text,text,text)','execute')"))
    verifica("service_role não tem UPDATE/DELETE/TRUNCATE em partidas, lançamentos e auditoria",
             not any(b.um("select has_table_privilege('service_role', %s, %s)", (f"public.{t}", p))
                     for t in ("partidas", "lancamentos", "auditoria") for p in ("update", "delete", "truncate")))
    verifica("service_role não tem UPDATE/DELETE/TRUNCATE em mensagens", not any(b.um("select has_table_privilege('service_role','public.mensagens',%s)", (p,)) for p in ("delete", "truncate")))
    verifica("tabelas novas nascem fechadas (privilégio padrão sem anon/authenticated)",
             b.um("select count(*) from pg_default_acl d, aclexplode(d.defaclacl) a where d.defaclobjtype='r' and a.grantee in (select oid from pg_roles where rolname in ('anon','authenticated'))") == 0)
    verifica("anon não consegue chamar função do schema privado",
             b.tenta(None, "select privado.eh_equipe('cadastro')", papel="anon")[0] == "erro")
    verifica("authenticated chama as funções privadas só sobre si mesmo (um usuário comum recebe falso)",
             b.ve(str(uuid.uuid4()), "select privado.eh_equipe('administrador')")[0][0] is False)


def main():
    b = Banco(RAIZ, TEMP, nome=f"pgdata_{MODO}", modo=MODO)
    print(f"Padrão de privilégios da plataforma simulado: {MODO}")
    try:
        print(b.um("select version()")[:45])
        passos = [m for m in b.migrations if not any(k in m.name for k in ("f32_", "revogar_execute"))]
        rollback_de = {"f33": "F3.3", "f34": "F3.4", "f35": "F3.5", "f36": "F3.6", "f37": "F3.7",
                       "f38a": "F3.8a", "f38b": "F3.8b", "f38c": "F3.8c",
                       "notificacoes": "notificacoes_dispositivos", "fix_acesso": "fix_acesso"}

        def sigla(m):
            return [v for k, v in rollback_de.items() if f"_{k}_" in m.name][0]

        print("\n== Aplicando as migrations em ordem ==")
        estados = []
        for m in b.migrations:
            b.aplicar(m)
            estados.append(estado(b))
            print(f"aplicada {m.name}")
        pos_f3 = {m.name: i for i, m in enumerate(b.migrations)}

        suite(b, 1)
        seguranca_global(b)
        b.exec("delete from storage.objects")  # buckets precisam estar vazios no rollback da F3.8c

        if MODO != "real":
            print("\n(rollback não testado neste modo: ele restaura o padrão observado no projeto real)")
            return finalizar(b)
        print("\n== (h) Rollback de cada migration, na ordem inversa ==")
        for m in reversed(passos):
            nome = sigla(m)
            b.rollback(f"{nome}_rollback.sql")
            novo = estado(b)
            esperado = estados[pos_f3[m.name] - 1]
            falta, sobra = diferenca(novo, esperado)
            verifica(f"rollback {nome} deixa o banco exatamente como antes da migration", novo == esperado,
                     f"sobrou: {falta} | faltou: {sobra}")
        print("\n== (h) Reaplicando tudo depois do rollback ==")
        for m in passos:
            b.aplicar(m)
            novo = estado(b)
            falta, sobra = diferenca(novo, estados[pos_f3[m.name]])
            verifica(f"reaplicar {sigla(m)} reproduz o mesmo estado", novo == estados[pos_f3[m.name]], f"{falta} | {sobra}")
        print("\n== Segunda rodada completa da suíte, no banco reconstruído ==")
        suite(b, 2)
        seguranca_global(b)
    finally:
        pass
    finalizar(b)


def finalizar(b):
    b.fechar()
    falhas = [n for n, ok in resultados if not ok]
    print(f"\nRESUMO: {len(resultados) - len(falhas)} verificações OK, {len(falhas)} com erro")
    for n in falhas:
        print("  ERRO:", n)
    sys.exit(1 if falhas else 0)


if __name__ == "__main__":
    main()
