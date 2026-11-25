package br.com.feitolabs.trato

/**
 * Decide, sem depender do Android (para poder testar), se o intent VIEW com que a atividade foi
 * recriada deve ser DESCARTADO (BUG-P11: o link velho não pode reabrir "pedido que não existe").
 *
 * Só os hosts de navegação entram na regra. O link de confirmação/login por e-mail
 * (`br.com.feitolabs.trato://login-callback`) e qualquer outro host NUNCA são descartados: o
 * supabase_flutter precisa ler esse link mesmo com a atividade restaurada.
 */
object DecisaoDeIntent {
    const val ESQUEMA = "br.com.feitolabs.trato"

    /** Os 6 links que abrem telas do app. */
    val HOSTS_DE_NAVEGACAO =
        setOf("pedido", "orcamentos", "chat", "recorrencia", "disputa", "avaliacao")

    fun deveDescartar(
        esquema: String?,
        host: String?,
        temEstadoSalvo: Boolean,
        vemDosRecentes: Boolean,
    ): Boolean {
        if (esquema?.lowercase() != ESQUEMA) return false
        if (host?.lowercase() !in HOSTS_DE_NAVEGACAO) return false // login-callback e outros: nunca
        return temEstadoSalvo || vemDosRecentes
    }
}
