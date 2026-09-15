import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase Android (FCM). Nécessite android/app/google-services.json (non
    // versionné). Absent -> le build échoue explicitement : c'est voulu pour une
    // release, l'app ne doit pas partir sans push. En local, poser le fichier
    // fourni hors dépôt (cf. docs/store/android/GOOGLE_PLAY_SUBMISSION.md).
    id("com.google.gms.google-services")
}

// F5-B.1 — signature RELEASE : la clé d'upload Auryel est décrite dans
// android/key.properties (NON suivi par Git ; sauvegardé hors repo).
// Absent en build DEBUG : sans effet (debug garde sa propre signature).
// Absent en build RELEASE : le build échoue explicitement (voir bloc
// gradle.taskGraph.whenReady plus bas) — jamais de repli silencieux.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

// Meta App Events — App ID + Client Token. Fichier NON versionné
// (android/meta.properties, gitignore). Absent -> valeurs vides : le SDK Meta
// reste inactif (la façade Dart NoopMetaEvents ne l'initialise pas). Ces
// valeurs peuvent aussi être passées par -PmetaAppId=... au build CI.
val metaPropertiesFile = rootProject.file("meta.properties")
val metaProperties = Properties()
if (metaPropertiesFile.exists()) {
    FileInputStream(metaPropertiesFile).use { metaProperties.load(it) }
}
val resolvedMetaAppId: String =
    (project.findProperty("metaAppId") as String?)
        ?: metaProperties.getProperty("metaAppId")
        ?: ""
val resolvedMetaClientToken: String =
    (project.findProperty("metaClientToken") as String?)
        ?: metaProperties.getProperty("metaClientToken")
        ?: ""

android {
    namespace = "com.auryel.auryel"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Requis par flutter_local_notifications (API date/time rétro-portée).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.auryel.auryel"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Substitué dans AndroidManifest (com.facebook.sdk.*). Vide si
        // meta.properties absent -> SDK Meta non initialisé côté Dart.
        manifestPlaceholders["metaAppId"] = resolvedMetaAppId
        manifestPlaceholders["metaClientToken"] = resolvedMetaClientToken
        manifestPlaceholders["adMobAppId"] =
            "ca-app-pub-3940256099942544~3347511713"
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        debug {
            manifestPlaceholders["adMobAppId"] =
                "ca-app-pub-3940256099942544~3347511713"
        }
        release {
            // Clé d'upload Auryel uniquement — plus AUCUN repli sur la clé debug.
            signingConfig = signingConfigs.getByName("release")
            // V1 — R8 / shrink DÉSACTIVÉS volontairement (décision explicite, pas
            // un défaut hérité) : priorité à la stabilité de la 1re release.
            // Firebase (FCM), Google Play Billing, Meta SDK et
            // flutter_local_notifications utilisent de la réflexion et
            // exigeraient des règles keep éprouvées ; les activer sans QA release
            // complète risque un strip silencieux -> crash uniquement en prod.
            // À réévaluer en v1.1 avec un proguard-rules.pro dédié + QA release.
            isMinifyEnabled = false
            isShrinkResources = false
            // release n'est jamais debuggable (défaut AGP) — rendu explicite.
            isDebuggable = false
            manifestPlaceholders["adMobAppId"] =
                "ca-app-pub-6355299363807052~4131926439"
        }
    }
}

// ---------------------------------------------------------------------------
// Garde-fou release AUR-C02 — décode les valeurs `--dart-define` passées par la
// CLI Flutter (`-Pdart-defines`, liste de "KEY=VALUE" en base64) et REFUSE un
// `assembleRelease` / `bundleRelease` si `AURYEL_API_BASE_URL` est absente,
// non-HTTPS, locale (`localhost` / `127.0.0.1` / `10.0.2.2` …), une IP privée
// ou un hôte non qualifié. Un AAB/APK release avec une mauvaise URL API ne peut
// donc PAS être produit (le contrôle Dart de ApiConfig est la 2e barrière, au
// démarrage). DEBUG n'est jamais concerné.
// ---------------------------------------------------------------------------
fun auryelReleaseApiUrlProblem(url: String): String? {
    val u = url.trim()
    if (u.isEmpty()) return "absente"
    val lower = u.lowercase()
    if (!lower.startsWith("https://")) return "non HTTPS (\"$u\")"
    // authority = ce qui suit "https://" jusqu'au premier / ? #
    val authority = u.substring("https://".length)
        .substringBefore('/').substringBefore('?').substringBefore('#')
    // retire un éventuel userinfo ("user:pass@") puis le port (":8443")
    val hostPort = authority.substringAfterLast('@')
    val host = (if (hostPort.startsWith("[")) {
        hostPort.substringAfter('[').substringBefore(']') // IPv6 littéral
    } else {
        hostPort.substringBefore(':')
    }).lowercase()
    if (host.isEmpty()) return "hôte manquant (\"$u\")"
    val localHosts = setOf(
        "localhost", "127.0.0.1", "::1", "0.0.0.0",
        "10.0.2.2", "10.0.3.2", "host.docker.internal",
    )
    if (host in localHosts) return "hôte local/émulateur \"$host\""
    if (host.endsWith(".local")) return "hôte de développement \"$host\""
    val octets = host.split(".")
    if (octets.size == 4 && octets.all { it.toIntOrNull() in 0..255 }) {
        val a = octets[0].toInt(); val b = octets[1].toInt()
        if (a == 10 || a == 127 || a == 0 ||
            (a == 192 && b == 168) ||
            (a == 172 && b in 16..31) ||
            (a == 169 && b == 254)
        ) return "adresse IP privée/loopback \"$host\""
    }
    if (!host.contains(".")) return "nom d'hôte non qualifié \"$host\""
    return null
}

gradle.taskGraph.whenReady {
    val isReleaseBuild = allTasks.any { it.name.contains("Release") }
    if (!isReleaseBuild) return@whenReady

    // 1) signature : jamais d'artefact signé avec une clé involontaire.
    if (!keystorePropertiesFile.exists()) {
        throw GradleException(
            "Build release impossible : android/key.properties introuvable. " +
                "Restaurer la clé d'upload Auryel (voir la sauvegarde hors repo, F5-B.1)."
        )
    }

    // 2) URL API de production (AUR-C02).
    val rawDefines = (project.findProperty("dart-defines") as String?).orEmpty()
    var apiBaseUrl: String? = null
    for (token in rawDefines.split(",")) {
        if (token.isBlank()) continue
        val decoded = try {
            String(Base64.getDecoder().decode(token.trim()), Charsets.UTF_8)
        } catch (_: Exception) {
            continue
        }
        if (decoded.startsWith("AURYEL_API_BASE_URL=")) {
            apiBaseUrl = decoded.substringAfter("=")
        }
    }
    val problem = auryelReleaseApiUrlProblem(apiBaseUrl ?: "")
    if (problem != null) {
        throw GradleException(
            "Build release refusé (AUR-C02) : AURYEL_API_BASE_URL $problem. " +
                "Fournir --dart-define=AURYEL_API_BASE_URL=https://<backend de " +
                "production Auryel> (URL HTTPS publique, jamais localhost / " +
                "10.0.2.2 / IP privée)."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring — dépendance de flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // NotificationCompat (notification plein écran du Réveil Auryel, cf.
    // WakeAlarmReceiver). Déjà présent transitivement via
    // flutter_local_notifications ; déclaré ici explicitement pour ne pas en
    // dépendre implicitement.
    implementation("androidx.core:core-ktx:1.15.0")
}
