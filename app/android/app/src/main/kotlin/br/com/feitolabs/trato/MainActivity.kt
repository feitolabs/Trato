package br.com.feitolabs.trato

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    companion object {
        const val CANAL_NOTIFICACOES = "trato_geral"
    }

    /**
     * BUG-P11. Depois que o processo morre (`am kill`, o sistema fechando o app), reabrir pelo
     * ícone ou pelos recentes faz o Android recriar a atividade com o intent VIEW que a abriu da
     * primeira vez (o link velho) e com o estado salvo. O FragmentManager então RECRIA o
     * FlutterFragment com os argumentos antigos, e a rota inicial do Flutter volta a ser o link:
     * o app abre de novo "serviço recorrente não existe". Trocar só o `getInitialRoute()` não
     * adianta, porque o fragmento restaurado nem o consulta.
     *
     * Por isso, quando a atividade é recriada (estado salvo) ou vem dos recentes e o intent é um
     * link de NAVEGAÇÃO (nunca o login-callback), trocamos o intent por um de abertura comum e descartamos o estado salvo: o app começa
     * pela tela inicial. Um link novo (sem estado salvo) segue funcionando; o toque num push chega
     * por `onNewIntent` e pelo Firebase.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        val recebido = intent
        val dados = recebido?.data
        val deHistorico =
            ((recebido?.flags ?: 0) and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        // Só os links de navegação (pedido, chat...) são descartados. O login-callback do e-mail
        // (supabase_flutter) e qualquer outro intent seguem intactos: ver DecisaoDeIntent.
        val linkVelho =
            recebido?.action == Intent.ACTION_VIEW &&
                DecisaoDeIntent.deveDescartar(
                    esquema = dados?.scheme,
                    host = dados?.host,
                    temEstadoSalvo = savedInstanceState != null,
                    vemDosRecentes = deHistorico,
                )
        if (linkVelho) {
            intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        }
        super.onCreate(if (linkVelho) null else savedInstanceState)
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
