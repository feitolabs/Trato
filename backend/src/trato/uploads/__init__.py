"""Upload seguro: URL de envio assinada, revalidação do arquivo no servidor e registro."""

from trato.uploads.armazenamento import ArmazenamentoArquivos, ArmazenamentoFake

__all__ = ["ArmazenamentoArquivos", "ArmazenamentoFake"]
