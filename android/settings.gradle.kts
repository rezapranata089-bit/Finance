pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

gradle.beforeProject {
    val bFile = buildFile
    if (bFile.exists() && bFile.name == "build.gradle") {
        var text = bFile.readText()
        var changed = false
        if (text.contains("jcenter()")) {
            text = text.replace("jcenter()", "mavenCentral()")
            changed = true
        }
        if (text.contains("classpath 'com.android.tools.build:gradle:") || text.contains("classpath \"com.android.tools.build:gradle:")) {
            text = text.replace(Regex("classpath\\s+['\"]com\\.android\\.tools\\.build:gradle:[^'\"]+['\"]"), "")
            changed = true
        }
        if (name == "flutter_tesseract_ocr") {
            if (!text.contains("namespace")) {
                text = text.replace("android {", "android {\n    namespace 'io.paratoner.flutter_tesseract_ocr'")
                changed = true
            }
            if (text.contains("compileSdkVersion 31")) {
                text = text.replace("compileSdkVersion 31", "compileSdkVersion 34")
                changed = true
            }
        }
        if (changed) {
            bFile.writeText(text)
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
