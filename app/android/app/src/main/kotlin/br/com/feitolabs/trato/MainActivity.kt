package br.com.feitolabs.trato

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    companion object {
        const val CANAL_NOTIFICACOES = "trato_geral"
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
