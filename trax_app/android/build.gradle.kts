allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Patch legacy Flutter plugins that pre-date AGP 8's required `namespace`
// attribute (e.g. amap_flutter_map, amap_flutter_location which haven't
// been updated since 2021). Also force a modern compileSdk for plugins
// that pin compileSdk 30 (which causes `attr/lStar not found`).
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            if (namespace == null) {
                val manifestFile = file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val pkg = Regex("package=\"([^\"]+)\"")
                        .find(manifestFile.readText())?.groupValues?.get(1)
                    if (pkg != null) namespace = pkg
                }
            }
            if ((compileSdk ?: 0) < 34) {
                compileSdk = 34
            }
            // Align Java with Kotlin (JVM 17). The Flutter / Kotlin Gradle
            // plugins push Kotlin to 17 in this project; without matching
            // Java, AGP fails ':install_plugin' etc. with "Inconsistent
            // JVM-target compatibility".
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Force UTF-8 source encoding for all Java compilation. Some legacy plugins
// (e.g. amap_flutter_map) ship UTF-8 source files with Chinese comments;
// without this, javac falls back to the system default (GBK on zh-CN
// Windows) and fails with "illegal character" errors.
allprojects {
    tasks.withType<JavaCompile>().configureEach {
        options.encoding = "UTF-8"
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
