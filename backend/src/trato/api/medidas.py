"""Medidas de conta (Termos 11.8 e 20): aplicar com aviso, terminar, reverter e contestar.

O aviso nunca é adiado (só o detalhe do motivo). A contestação vale por 30 dias do aviso e é
respondida por outro analista quando possível. Automática dura no máximo 72 h.
"""

from __future__ import annotations

from dataclasses import replace
from datetime import datetime, timedelta
from functools import partial

from pydantic import BaseModel, Field

from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto
from trato.api.indisponibilidade import APP, prazo_vigente
from trato.api.moedas import restaurar_tratinhos
from trato.api.pedidos_conta import TIPOS_QUE_CANCELAM, tratar_pedidos
from trato.disputas.prazos import adicionar_dias_uteis
from trato.financeiro import periodo
from trato.notificacoes.eventos import Evento
from trato.persistencia.medidas import (
    GRAVIDADE,
    JANELA_DE_FIM,
    STATUS_IMPOSTO,
    ContestacaoMedida,
    Medida,
)

# 13.10: guarda dos Tratinhos (o banco fixa os mesmos 90 dias para o retorno aprovado).
GUARDA_TRATINHOS_DIAS = 90
DIAS_PARA_CONTESTAR = 30
DIAS_UTEIS_PARA_RESPONDER = 10
HORAS_AUTOMATICA = 72
# 20.8: "pelo menos 30 dias"; a configuração só pode aumentar.
AVISO_ENCERRAMENTO_MINIMO_DIAS = 30
EFEITO_PADRAO = (
    "Pedidos e valores em andamento seguem a cláusula 20.6; o que é devido continua sendo pago."
)
COMO_CONTESTAR = (
    "Conteste em até 30 dias deste aviso, pelo aplicativo (Minhas medidas) ou pelo atendimento."
)
_NOMES = {
    "aviso": "aviso",
    "restricao": "restrição de funções",
    "suspensao": "suspensão da conta",
    "encerramento": "encerramento da conta",
    "bloqueio_preventivo": "bloqueio preventivo",
    "trava_saque": "trava de saques",
    "remocao_conteudo": "remoção de conteúdo",
}


class AnexoDaContestacaoOut(BaseModel):
    anexo_id: str
    content_type: str
    tamanho_bytes: int


class ContestacaoMedidaOut(BaseModel):
    protocolo: str | None
    status: str = Field(description="aberta | em_analise | mantida | alterada | revertida")
    versao: str
    canal: str
    aberta_em: datetime
    responder_ate: datetime
    resposta: str | None = None
    decidida_em: datetime | None = None
    anexos: list[AnexoDaContestacaoOut] = []


class MedidaOut(BaseModel):
    id: str
    protocolo: str | None
    tipo: str
    motivo: str
    clausulas: list[str]
    inicio_em: datetime
    fim_em: datetime | None = None
    efeito_pedidos_valores: str
    como_contestar: str
    detalhe_adiado: bool
    vigente: bool
    revertida_em: datetime | None = None
    avisado_em: datetime | None = None
    contestavel_ate: datetime | None = None
    contestacao: ContestacaoMedidaOut | None = None


def motivo_para_o_usuario(m: Medida) -> str:
    if not m.detalhe_adiado:
        return m.motivo
    return (
        "O detalhe do motivo foi adiado para não atrapalhar a apuração ou expor alguém. "
        f"Cláusulas envolvidas: {', '.join(m.clausulas)}."
    )


def contestavel_ate(contexto: Contexto, m: Medida) -> datetime | None:
    """22.3: falha do app prorroga o prazo para contestar."""
    return prazo_vigente(contexto, APP, m.avisado_em, m.contestavel_ate)


def saida(contexto: Contexto, m: Medida) -> MedidaOut:
    c = contexto.medidas.contestacao(m.id or "")
    return MedidaOut(
        id=m.id or "",
        protocolo=m.protocolo,
        tipo=m.tipo,
        motivo=motivo_para_o_usuario(m),
        clausulas=list(m.clausulas),
        inicio_em=m.inicio_em,
        fim_em=m.fim_em,
        efeito_pedidos_valores=m.efeito,
        como_contestar=m.como_contestar,
        detalhe_adiado=m.detalhe_adiado,
        vigente=m.vigente(contexto.agora()),
        revertida_em=m.revertida_em,
        avisado_em=m.avisado_em,
        contestavel_ate=contestavel_ate(contexto, m),
        contestacao=ContestacaoMedidaOut(
            **{n: getattr(c, n) for n in ContestacaoMedidaOut.model_fields if n != "anexos"},
            anexos=[
                AnexoDaContestacaoOut(**{n: a[n] for n in AnexoDaContestacaoOut.model_fields})
                for a in c.anexos
            ],
        )
        if c
        else None,
    )


def _data(momento: datetime) -> str:
    return f"{momento.astimezone(periodo.BRASILIA):%d/%m/%Y}"


def _avisar(contexto: Contexto, m: Medida, evento: Evento, chave: str, corpo: str) -> None:
    avisar_partes(
        contexto,
        evento,
        (m.usuario_id,),
        pedido_id=None,
        chave=f"medida:{m.id}:{chave}",
        corpo=f"Protocolo {m.protocolo}. {corpo}",
    )


def status_devido(contexto: Contexto, usuario_id: str, agora: datetime | None = None) -> str:
    """O que as medidas em vigor pedem para a conta."""
    vigentes, _ = contexto.medidas.listar(
        usuario_id=usuario_id, vigentes_em=agora or contexto.agora()
    )
    pedidos = [STATUS_IMPOSTO[m.tipo] for m in vigentes if m.tipo in STATUS_IMPOSTO]
    return max(pedidos, key=GRAVIDADE.__getitem__, default="ativo")


def desbloqueada_em(
    contexto: Contexto, usuario_id: str, desde: datetime, agora: datetime
) -> datetime | None:
    """Quando terminou o último bloqueio da conta que alcançou o período depois de `desde`
    (revertido ou vencido). `None`: nenhum bloqueio terminou nesse período. Sem a tabela de
    medidas, também `None`."""
    medidas, _ = contexto.medidas.listar(usuario_id=usuario_id, limite=500)
    fins = []
    for m in medidas:
        if STATUS_IMPOSTO.get(m.tipo) != "bloqueado":
            continue
        fim = min((d for d in (m.revertida_em, m.fim_em) if d is not None), default=None)
        if fim is not None and desde < fim <= agora and m.inicio_em < fim:
            fins.append(fim)
    return max(fins, default=None)


def _devolver_conta(contexto: Contexto, m: Medida, agora: datetime | None = None) -> bool:
    """Terminou uma medida: a conta volta ao que as outras pedem. Só mexe se o status atual é
    o que ESTA medida impunha."""
    imposto = STATUS_IMPOSTO.get(m.tipo)
    if imposto is None:
        return False
    devido = status_devido(contexto, m.usuario_id, agora)
    if GRAVIDADE[devido] >= GRAVIDADE[imposto]:
        return False
    return contexto.medidas.definir_status(m.usuario_id, (imposto,), devido)


def aviso_de_encerramento_dias(contexto: Contexto) -> int:
    publicado = contexto.config.parametro_inteiro("aviso_previo_encerramento_dias")
    return max(AVISO_ENCERRAMENTO_MINIMO_DIAS, publicado or 0)


def agendada(m: Medida) -> bool:
    """Avisada antes de começar (20.8): só o encerramento sem falta nasce assim."""
    return m.avisado_em is not None and m.inicio_em > m.avisado_em


def aplicar(contexto: Contexto, medida: Medida) -> tuple[Medida, bool]:
    """Grava a medida, ajusta a conta e avisa por app e e-mail (depois do commit).

    Encerramento sem falta (20.8): `inicio_em` recebido é o momento do aviso; a medida só começa
    depois do prazo, e até lá a conta segue como estava."""
    with contexto.transacao():
        agora = medida.inicio_em
        if medida.tipo == "encerramento" and medida.sem_falta is True:
            dias = aviso_de_encerramento_dias(contexto)
            medida = replace(medida, inicio_em=agora + timedelta(days=dias))
        nova, criada = contexto.medidas.criar(
            replace(
                medida,
                avisado_em=agora,
                contestavel_ate=agora + timedelta(days=DIAS_PARA_CONTESTAR),
            )
        )
        if not criada:
            return nova, False
        imposto = STATUS_IMPOSTO.get(nova.tipo)
        futura = nova.inicio_em > agora
        if imposto is not None and not futura:
            menores = [s for s, g in GRAVIDADE.items() if g < GRAVIDADE[imposto]]
            contexto.medidas.definir_status(nova.usuario_id, menores, imposto)
        ate = f" até {_data(nova.fim_em)}" if nova.fim_em else ", sem data final definida"
        _avisar(
            contexto,
            nova,
            Evento.MEDIDA_APLICADA,
            "aplicada",
            f"Medida: {_NOMES[nova.tipo]}, {'a partir de' if futura else 'desde'} "
            f"{_data(nova.inicio_em)}{ate}. "
            + ("Até essa data a conta continua funcionando. " if futura else "")
            + f"Motivo: {motivo_para_o_usuario(nova)} Cláusulas: {', '.join(nova.clausulas)}. "
            f"{nova.efeito} {nova.como_contestar}",
        )
        if nova.tipo in TIPOS_QUE_CANCELAM and not futura:  # 20.6: com a medida já gravada
            contexto.depois_do_commit(partial(tratar_pedidos, contexto, nova.usuario_id))
    return nova, True


def aplicar_automatica(
    contexto: Contexto,
    usuario_id: str,
    tipo: str,
    motivo: str,
    clausulas: tuple[str, ...],
    horas: int = HORAS_AUTOMATICA,
) -> tuple[Medida, bool]:
    """Alerta automático restringe por no máximo 72 h (20.2); o resto é decisão de analista."""
    if tipo not in ("aviso", "restricao", "bloqueio_preventivo", "trava_saque"):
        raise ValueError("Esta medida só pode ser decidida por um analista.")
    agora = contexto.agora()
    return aplicar(
        contexto,
        Medida(
            usuario_id=usuario_id,
            tipo=tipo,
            motivo=motivo,
            clausulas=clausulas,
            inicio_em=agora,
            fim_em=agora + timedelta(hours=max(1, min(horas, HORAS_AUTOMATICA))),
            efeito=EFEITO_PADRAO,
            como_contestar=COMO_CONTESTAR,
            origem="automatica",
        ),
    )


def reverter(contexto: Contexto, medida: Medida, analista_id: str) -> bool:
    with contexto.transacao():
        if not contexto.medidas.mudar(
            medida.id or "", {"revertida_em": contexto.agora(), "revertida_por": analista_id}
        ):
            return False
        if medida.inicio_em <= contexto.agora():  # ainda não começou: nada a desfazer
            _devolver_conta(contexto, medida)
            if medida.tipo == "encerramento":  # desfeito: devolve em qualquer data (13.10)
                _restaurar_tratinhos(contexto, medida)
        _avisar(
            contexto,
            medida,
            Evento.MEDIDA_ENCERRADA,
            "revertida",
            f"A medida ({_NOMES[medida.tipo]}) foi revertida.",
        )
    return True


def _restaurar_tratinhos(contexto: Contexto, medida: Medida) -> int:
    """Só com a conta de fato de volta: outro encerramento em vigor adia."""
    outros, _ = contexto.medidas.listar(
        usuario_id=medida.usuario_id, tipo="encerramento", limite=100
    )
    aprovados = set()
    if contexto.retorno_conta.disponivel():
        aprovados = {
            _sem_hifens(r.medida_id)
            for r in contexto.retorno_conta.listar_retornos_do_usuario(medida.usuario_id)
            if r.status == "aprovado"
        }
    atual = _sem_hifens(medida.id)
    agora = contexto.agora()
    if any(
        o.revertida_em is None
        and o.inicio_em <= agora  # o que só está avisado ainda não encerrou nada
        and _sem_hifens(o.id) not in {atual, *aprovados}
        for o in outros
    ):
        return 0
    return restaurar_tratinhos(
        contexto.moedas, medida.id or "", medida.usuario_id, medida.inicio_em, contexto.agora()
    )


def _sem_hifens(valor: str | None) -> str:
    return str(valor or "").replace("-", "")


def restabelecer_por_retorno(contexto: Contexto, medida_id: str, pedido_em: datetime) -> int:
    """Retorno aprovado (20.9) de encerramento sem falta, pedido dentro dos 90 dias da guarda:
    devolve os Tratinhos vencidos no período. Não muda o prazo do retorno."""
    if not contexto.medidas.disponivel():
        return 0
    with contexto.transacao():
        medida = contexto.medidas.obter(medida_id)
        if (
            medida is None
            or medida.tipo != "encerramento"
            or medida.revertida_em is not None  # a reversão já devolveu
            or medida.sem_falta is False
            or medida.infracao_grave
            or pedido_em > medida.inicio_em + timedelta(days=GUARDA_TRATINHOS_DIAS)
            or contexto.moedas is None
            or not contexto.moedas.restauracao_disponivel()
        ):
            return 0
        if medida.sem_falta is None:  # linha sem resposta: vale a favor do usuário
            contexto.medidas.mudar(medida.id or "", {"sem_falta": True})
        return _restaurar_tratinhos(contexto, medida)


def encerrar_vencidas(contexto: Contexto, agora: datetime) -> int:
    """Agendador: medida com prazo vencido devolve a conta. Repetir não faz nada."""
    devolvidas = 0
    for medida in contexto.medidas.terminadas(agora):
        with contexto.transacao():
            if _devolver_conta(contexto, medida, agora):
                devolvidas += 1
                _avisar(
                    contexto,
                    medida,
                    Evento.MEDIDA_ENCERRADA,
                    "fim",
                    f"O prazo da medida ({_NOMES[medida.tipo]}) terminou.",
                )
    return devolvidas


def iniciar_agendadas(contexto: Contexto, agora: datetime) -> int:
    """Agendador (20.8): chegou o dia do encerramento avisado, a conta é bloqueada. Só olha o
    que começou há pouco, para não bloquear de novo quem voltou depois. Repetir não faz nada.

    20.6: também trata os pedidos futuros das suspensões e encerramentos em vigor há pouco
    (os que começam agora e os que falharam na hora de aplicar)."""
    bloqueadas = 0
    for tipo in TIPOS_QUE_CANCELAM:
        deslocamento = 0
        while True:
            medidas, total = contexto.medidas.listar(
                tipo=tipo, vigentes_em=agora, limite=500, deslocamento=deslocamento
            )
            for medida in medidas:
                if agora - medida.inicio_em > JANELA_DE_FIM:
                    continue
                with contexto.transacao():
                    atual = contexto.medidas.obter(medida.id or "")  # pode ter sido revertida
                    if atual is None or not atual.vigente(agora):
                        continue
                    if tipo == "encerramento" and agendada(atual):
                        bloqueadas += contexto.medidas.definir_status(
                            atual.usuario_id, ("ativo", "restrito"), "bloqueado"
                        )
                    if contexto.medidas.conta_bloqueada_travada(atual.usuario_id):
                        contexto.depois_do_commit(
                            partial(tratar_pedidos, contexto, atual.usuario_id)
                        )
            deslocamento += len(medidas)
            if not medidas or deslocamento >= total:
                break
    return bloqueadas


def contestar(
    contexto: Contexto,
    medida: Medida,
    versao: str,
    canal: str,
    anexos: tuple[dict, ...] = (),
) -> tuple[ContestacaoMedida, bool]:
    agora = contexto.agora()
    return contexto.medidas.abrir_contestacao(
        ContestacaoMedida(
            medida_id=medida.id or "",
            usuario_id=medida.usuario_id,
            versao=versao,
            canal=canal,
            anexos=anexos,
            aberta_em=agora,
            responder_ate=adicionar_dias_uteis(
                agora.astimezone(periodo.BRASILIA),
                DIAS_UTEIS_PARA_RESPONDER,
                contexto.config.carregar().disputas.feriados,
            ),
        )
    )


def avisar_resposta(contexto: Contexto, medida: Medida, resultado: str, resposta: str) -> None:
    _avisar(
        contexto,
        medida,
        Evento.MEDIDA_ENCERRADA,
        "contestacao",
        f"A sua contestação foi respondida: medida {resultado}. {resposta}",
    )


# --- rotas antigas de status e risco -------------------------------------------------------------


def prazo_da_trava(
    contexto: Contexto, tipo: str, motivo_fraude: bool, limite: int | None, dias: int | None
) -> tuple[int | None, str | None]:
    """(dias da medida, erro). Trava por fraude exige limite e sempre tem fim: sem `dias`, vale
    o prazo máximo configurado."""
    if not motivo_fraude:
        erro = "O limite de retenção só vale com motivo_fraude." if limite is not None else None
        return dias, erro
    if tipo != "trava_saque":
        return dias, "motivo_fraude só vale na trava de saques."
    if limite is None:
        return dias, "Informe o limite da retenção (o prejuízo apurado), em centavos."
    maximo = contexto.medidas.prazo_maximo_trava_fraude_dias()
    if dias is not None and dias > maximo:
        return dias, f"A trava por fraude vale no máximo {maximo} dias; renovar é medida nova."
    return dias or maximo, None


def espelhar_status(
    contexto: Contexto,
    usuario_id: str,
    analista_id: str,
    *,
    para: str,
    tipo: str,
    termina: tuple[str, ...],
    motivo: str,
    motivo_usuario: str | None = None,
    clausulas: tuple[str, ...] = (),
    dias: int | None = None,
    motivo_fraude: bool = False,
    limite_retencao_centavos: int | None = None,
) -> str | None:
    """Depois de a rota antiga mudar o status: cria a medida (ou reverte as que acabaram).
    Sem a tabela, nada acontece. Devolve o protocolo da medida criada."""
    if not contexto.medidas.disponivel():
        return None
    agora = contexto.agora()
    if termina:
        vigentes, _ = contexto.medidas.listar(usuario_id=usuario_id, vigentes_em=agora)
        for m in vigentes:
            if m.tipo in termina:
                reverter(contexto, m, analista_id)
        # Outra medida ainda em vigor continua valendo.
        devido = status_devido(contexto, usuario_id)
        if GRAVIDADE[devido] > GRAVIDADE[para]:
            contexto.medidas.definir_status(usuario_id, (para,), devido)
    if para == "ativo":
        return None
    texto = (motivo_usuario or "").strip()
    nova, _ = aplicar(
        contexto,
        Medida(
            usuario_id=usuario_id,
            tipo=tipo,
            # Sem texto escrito para o usuário, o motivo interno NÃO é mostrado (20.4).
            motivo=texto or "Veja as cláusulas e peça os detalhes pelo atendimento.",
            clausulas=clausulas or ("20.1",),
            inicio_em=agora,
            fim_em=agora + timedelta(days=dias) if dias else None,
            motivo_fraude=motivo_fraude,
            limite_retencao_centavos=limite_retencao_centavos,
            efeito=EFEITO_PADRAO,
            como_contestar=COMO_CONTESTAR,
            aplicada_por=analista_id,
            nota_interna=motivo,
            detalhe_adiado=not texto,
            justificativa_adiamento=None
            if texto
            else "Rota antiga do painel: sem texto para o usuário.",
        ),
    )
    return nova.protocolo
