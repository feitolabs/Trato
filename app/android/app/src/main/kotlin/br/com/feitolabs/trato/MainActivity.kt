package br.com.feitolabs.trato

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    companion object {
        const val CANAL_NOTIFICACOES = "trato_geral"
    }

    /**
     * Reaberto pelos "recentes" (FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY), o Android entrega de novo o
     * intent VIEW que abriu o app da primeira vez (um deep link velho). Nesse caso o app começa
     * pela tela inicial: o link já foi tratado e não pode abrir "pedido que não existe" de novo.
     */
    override fun getInitialRoute(): String? {
        val deHistorico =
            (intent?.flags ?: 0) and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        return if (deHistorico) "/" else super.getInitialRoute()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        garantirCanalNotificacoes()
    }

    private fun garantirCanalNotificacoes() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CANAL_NOTIFICACOES) != null) return
        val canal = NotificationChannel(
            CANAL_NOTIFICACOES,
            "Atualizações de pedidos e mensagens",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Avisos de orçamentos, pagamentos, agenda e mensagens do Trato."
        }
        manager.createNotificationChannel(canal)
    }
}
