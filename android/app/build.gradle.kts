import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Google Services plugin is applied conditionally at the bottom of this
    // file — only when google-services.json is present so builds don't fail
    // before Firebase credentials arrive.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.volcano.flamesurge"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 18.x requires desugaring for java.time.*
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.volcano.flamesurge"
        minSdk = 24
        targetSdk = 35
        versionCode = 4
        versionName = "1.0.1"
        multiDexEnabled = true
    }

    if (hasKeystore) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(
                    keystoreProperties["storeFile"] as String
                )
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        debug {
            isMinifyEnabled = false
        }
    }

    packaging {
        resources {
            excludes += listOf(
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/INDEX.LIST",
                "META-INF/DEPENDENCIES"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // Pinned explicitly (rather than relying on transitive resolution from
    // appsflyer_sdk) so `AdvertisingIdClient` is always on the classpath.
    // Without it, GAID retrieval throws `ClassNotFoundException` on some
    // OEM ROMs (Realme UI, MIUI, ColorOS) which collapses AppsFlyer's
    // fingerprint match and misclassifies non-organic installs as Organic.
    implementation("com.google.android.gms:play-services-ads-identifier:18.1.0")
    // Play Install Referrer AIDL client. AppsFlyer's Android SDK also brings
    // this in, but pinning here avoids version-skew surprises during
    // dependency resolution on newer AGP releases.
    implementation("com.android.installreferrer:installreferrer:2.2")
}

flutter {
    source = "../.."
}

// Apply google-services only when the credentials file is present so builds
// keep working before Firebase is provisioned.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
