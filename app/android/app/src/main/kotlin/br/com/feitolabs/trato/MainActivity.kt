package br.com.feitolabs.trato

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        const val CANAL_PUSH = "br.com.feitolabs.trato/push"
        const val CANAL_NOTIFICACOES = "trato_geral"
        private const val CODIGO_PERMISSAO_NOTIFICACAO = 4107

        @Volatile
        private var canalAtivo: MethodChannel? = null

        fun emitirTokenAtualizado(token: String) {
            canalAtivo?.let { canal ->
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    canal.invokeMethod(
                        "tokenAtualizado",
                        mapOf("token" to token, "plataforma" to "android"),
                    )
                }
            }
        }
    }

    private var resultadoPendente: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        garantirCanalNotificacoes()

        val canal = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_PUSH)
        canalAtivo = canal
        canal.setMethodCallHandler { call, result ->
            if (call.method == "obterTokenPush") {
                iniciarObtencaoToken(result)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        canalAtivo = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun iniciarObtencaoToken(result: MethodChannel.Result) {
        if (!firebaseConfigurado()) {
            result.success(null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val status = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            )
            if (status != PackageManager.PERMISSION_GRANTED) {
                resultadoPendente?.success(null)
                resultadoPendente = result
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    CODIGO_PERMISSAO_NOTIFICACAO,
                )
                return
            }
        }
        buscarTokenFcm(result)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == CODIGO_PERMISSAO_NOTIFICACAO) {
            val pendente = resultadoPendente
            resultadoPendente = null
            if (pendente != null) {
                val permitido = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                if (permitido) {
                    buscarTokenFcm(pendente)
                } else {
                    pendente.success(null)
                }
            }
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun firebaseConfigurado(): Boolean {
        return try {
            if (FirebaseApp.getApps(this).isNotEmpty()) {
                true
            } else {
                FirebaseApp.initializeApp(this) != null
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun buscarTokenFcm(result: MethodChannel.Result) {
        try {
            FirebaseMessaging.getInstance().token
                .addOnSuccessListener { token ->
                    val limpo = token?.trim().orEmpty()
                    if (limpo.isEmpty()) {
                        result.success(null)
                    } else {
                        result.success(mapOf("token" to limpo, "plataforma" to "android"))
                    }
                }
                .addOnFailureListener {
                    result.success(null)
                }
        } catch (_: Throwable) {
            result.success(null)
        }
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
