import java.util.Properties
import java.util.Base64
import java.io.FileInputStream

val debugAbi = providers.gradleProperty("komet.debugAbi").get()

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// #***! KOMET_INSTANCE в натив (BuildConfig.KOMET_INSTANCE) — то же имя копии,
// что уходит в Dart через --dart-define. Flutter-тул пробрасывает dart-define'ы
// в Gradle свойством -Pdart-defines=<entry>,<entry>…, где каждая запись — это
// base64 от percent-закодированной строки KEY=VALUE (у свежих версий тула перед
// base64 ещё префикс «d:»). Здесь вытаскиваем из неё имя копии: натив сразу
// открывает нужную базу komet[_имя].db, без канала из Dart и без состояния.
// Декодер читает процентные последовательности как байты и собирает из них
// utf-8 строку — так же, как Uri.decode в Dart.
fun kometPercentDecode(s: String): String {
    if ('%' !in s) return s
    val bytes = ArrayList<Byte>(s.length)
    var i = 0
    while (i < s.length) {
        val c = s[i]
        if (c == '%' && i + 2 < s.length) {
            val hi = Character.digit(s[i + 1], 16)
            val lo = Character.digit(s[i + 2], 16)
            if (hi >= 0 && lo >= 0) {
                bytes.add(((hi shl 4) or lo).toByte())
                i += 3
                continue
            }
        }
        for (b in c.toString().toByteArray(Charsets.UTF_8)) bytes.add(b)
        i += 1
    }
    return String(bytes.toByteArray(), Charsets.UTF_8)
}

// «+» не превращаем в пробел (как это сделал бы java.net.URLDecoder):
// base64-алфавит его допускает, а flutter-тул плюс не экранирует.
fun kometDecodeDartDefine(entry: String): String? {
    val unescaped = kometPercentDecode(entry)
    val payload = if (unescaped.startsWith("d:")) unescaped.substring(2) else unescaped
    return try {
        kometPercentDecode(String(Base64.getDecoder().decode(payload), Charsets.UTF_8))
    } catch (e: IllegalArgumentException) {
        unescaped // совсем старый формат тула — запись без кодирования
    }
}

val kometInstance = providers.gradleProperty("dart-defines").orNull
    ?.split(',')
    ?.firstNotNullOfOrNull { entry ->
        kometDecodeDartDefine(entry.trim())?.let { decoded ->
            val i = decoded.indexOf('=')
            if (i > 0 && decoded.substring(0, i) == "KOMET_INSTANCE") decoded.substring(i + 1) else null
        }
    }
    ?: ""

// Экзотическое имя копии натив не осилит: проверку «прочитано» в пуше придётся
// выключить, поэтому предупреждаем об этом ещё на сборке.
if (!kometInstance.matches(Regex("[A-Za-z0-9_-]*"))) {
    logger.warn("komet: unusual KOMET_INSTANCE '$kometInstance'; native read-mark check will be disabled")
}

android {
    namespace = "ru.komet.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "ru.komet.app"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // #***! имя копии (см. kometInstance выше); его читает MessageReadState
        buildConfigField(
            "String",
            "KOMET_INSTANCE",
            kometInstance
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .let { "\"$it\"" },
        )
    }

    buildFeatures {
        // нужен BuildConfig.KOMET_INSTANCE
        buildConfig = true
    }

    flavorDimensions += "distribution"

    productFlavors {
        create("komet") {
            dimension = "distribution"
            isDefault = true
            applicationId = "ru.komet.app"
        }
        create("oneme") {
            dimension = "distribution"
            applicationId = "ru.oneme.app"
        }
        create("store") {
            dimension = "distribution"
            applicationId = "pw.komet.app"
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    // format proeban? da i huy s nim))
    buildTypes {
    debug {
        if (!project.hasProperty("split-per-abi")) {
            ndk {
                abiFilters += debugAbi
            }
        }
    }
    release {
        signingConfig = if (hasReleaseSigning) {
            signingConfigs.getByName("release")
        } else {
            signingConfigs.getByName("debug")
        }
    }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.media3:media3-transformer:1.9.3")
    implementation("androidx.media3:media3-effect:1.9.3")
    implementation("androidx.media3:media3-common:1.9.3")
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.1")
}
