import br.com.feitolabs.trato.DecisaoDeIntent;

/**
 * Verificação sem JUnit (o projeto não tem JUnit configurado) da regra que decide se o intent VIEW
 * de uma atividade recriada é descartado. Como rodar (depois de `gradlew :app:compileDebugKotlin`):
 *
 *   javac -cp "<classes-kotlin>:<kotlin-stdlib.jar>" -d out verificar_intent/VerificarDecisaoDeIntent.java
 *   java  -cp "out:<classes-kotlin>:<kotlin-stdlib.jar>" VerificarDecisaoDeIntent
 *
 * `<classes-kotlin>` = app/build/app/tmp/kotlin-classes/debug. Sai com código 1 se algo falhar.
 */
public class VerificarDecisaoDeIntent {
    static int falhas = 0;
    static int total = 0;

    static void esperar(boolean esperado, String esquema, String host, boolean salvo, boolean recentes) {
        total++;
        boolean r = DecisaoDeIntent.INSTANCE.deveDescartar(esquema, host, salvo, recentes);
        if (r != esperado) {
            falhas++;
            System.out.println("FALHOU: " + esquema + "://" + host + " salvo=" + salvo
                    + " recentes=" + recentes + " -> " + r + " (esperado " + esperado + ")");
        }
    }

    public static void main(String[] args) {
        final String app = "br.com.feitolabs.trato";
        final boolean[] bools = {false, true};
        // login-callback: NUNCA descarta, em todas as combinações (também com maiúsculas).
        for (boolean salvo : bools) {
            for (boolean recentes : bools) {
                esperar(false, app, "login-callback", salvo, recentes);
                esperar(false, app, "LOGIN-CALLBACK", salvo, recentes);
                esperar(false, "BR.COM.FEITOLABS.TRATO", "login-callback", salvo, recentes);
                // Outro host, outro esquema, sem host: nunca descarta.
                esperar(false, app, "perfil", salvo, recentes);
                esperar(false, app, null, salvo, recentes);
                esperar(false, "https", "pedido", salvo, recentes);
                esperar(false, null, "pedido", salvo, recentes);
            }
        }
        // Os 6 hosts de navegação: descarta só com estado salvo ou vindo dos recentes.
        for (String host : new String[] {"pedido", "orcamentos", "chat", "recorrencia", "disputa", "avaliacao"}) {
            esperar(false, app, host, false, false); // link NOVO: abre normalmente
            esperar(true, app, host, true, false);
            esperar(true, app, host, false, true);
            esperar(true, app, host, true, true);
            esperar(true, "BR.com.feitolabs.TRATO", host.toUpperCase(), true, false);
        }
        System.out.println(total + " verificações, " + falhas + " falhas");
        System.exit(falhas == 0 ? 0 : 1);
    }
}
