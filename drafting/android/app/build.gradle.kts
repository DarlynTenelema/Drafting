import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val apiBaseUrl: String = (
    project.findProperty("API_BASE_URL") as String?
        ?: "https://drafting-production-0963.up.railway.app"
).trimEnd('/')

android {
    namespace = "com.drafting.app"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // Change applicationId before Play Store release (see PRODUCTION_GUIDE.md).
        applicationId = "com.drafting.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystorePropertiesFile = rootProject.file("key.properties")
            val keystoreProperties = Properties()
            if (keystorePropertiesFile.exists()) {
                keystoreProperties.load(FileInputStream(keystorePropertiesFile))
            }

            val storeFilePath = keystoreProperties.getProperty("storeFile") ?: project.findProperty("RELEASE_STORE_FILE")?.toString()
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
            }
            storePassword = keystoreProperties.getProperty("storePassword") ?: project.findProperty("RELEASE_STORE_PASSWORD")?.toString()
            keyAlias = keystoreProperties.getProperty("keyAlias") ?: project.findProperty("RELEASE_KEY_ALIAS")?.toString()
            keyPassword = keystoreProperties.getProperty("keyPassword") ?: project.findProperty("RELEASE_KEY_PASSWORD")?.toString()
        }
    }

    buildTypes {
        debug {
            buildConfigField("String", "BASE_URL", "\"$apiBaseUrl\"")
        }
        release {
            buildConfigField("String", "BASE_URL", "\"$apiBaseUrl\"")
            val releaseSigning = signingConfigs.getByName("release")
            signingConfig = if (releaseSigning.storeFile != null && releaseSigning.storeFile!!.exists()) {
                releaseSigning
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
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
