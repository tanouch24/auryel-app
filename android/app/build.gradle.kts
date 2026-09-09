import java.io.FileInputStream
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
        release {
            // Clé d'upload Auryel uniquement — plus AUCUN repli sur la clé debug.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Garde-fou : un build RELEASE sans android/key.properties DOIT échouer, jamais
// produire un artefact signé avec une clé involontaire.
gradle.taskGraph.whenReady {
    val isReleaseBuild = allTasks.any { it.name.contains("Release") }
    if (isReleaseBuild && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "Build release impossible : android/key.properties introuvable. " +
                "Restaurer la clé d'upload Auryel (voir la sauvegarde hors repo, F5-B.1)."
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
}
