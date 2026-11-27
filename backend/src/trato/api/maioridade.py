"""Termos 4.1: pedido, orçamento, pagamento e cadastro de profissional só para maiores de 18.

Ligado por `TRATO_SEG_EXIGIR_MAIORIDADE` (padrão desligado, para não travar o app antigo). A data
de nascimento é a gravada no cadastro (`/v1/me/dados-pessoais`); "hoje" é o dia em Brasília.
"""

from __future__ import annotations

from datetime import date

from fastapi import Depends, HTTPException, Request
from fastapi.responses import JSONResponse

from trato.api.auth import Usuario
from trato.api.contexto import Contexto, obter_contexto, usuario_atual
from trato.financeiro import periodo
from trato.seguranca.config import obter_config_seguranca

IDADE_MINIMA = 18  # Termos 4.1 (lei: capacidade para contratar)
SEM_DATA = "data_nascimento_obrigatoria"
MENOR = "menor_de_idade"
_MENSAGENS = {
    SEM_DATA: "Informe sua data de nascimento no cadastro para continuar.",
    MENOR: "O Trato é só para maiores de 18 anos.",
}


class ErroMaioridade(HTTPException):
    def __init__(self, codigo: str) -> None:
        super().__init__(422, _MENSAGENS[codigo])
        self.codigo = codigo


def idade(nascimento: date, hoje: date) -> int:
    antes_do_aniversario = (hoje.month, hoje.day) < (nascimento.month, nascimento.day)
    return hoje.year - nascimento.year - antes_do_aniversario


def exigir_maioridade(
    usuario: Usuario = Depends(usuario_atual), contexto: Contexto = Depends(obter_contexto)
) -> None:
    """Dependência de rota. Desligada, não consulta nada."""
    if not obter_config_seguranca().exigir_maioridade:
        return
    nascimento = contexto.usuarios.data_nascimento(usuario.id)
    if nascimento is None:
        raise ErroMaioridade(SEM_DATA)
    if idade(nascimento, contexto.agora().astimezone(periodo.BRASILIA).date()) < IDADE_MINIMA:
        raise ErroMaioridade(MENOR)


def tratar_maioridade(request: Request, erro: ErroMaioridade) -> JSONResponse:
    return JSONResponse({"detail": erro.detail, "codigo": erro.codigo}, status_code=422)
