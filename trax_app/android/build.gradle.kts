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
        }
        project.afterEvaluate {
            extensions.findByName("android")?.let { ext ->
                try {
                    val current = ext.javaClass.getMethod("getCompileSdkVersion").invoke(ext) as? String
                    val n = current?.removePrefix("android-")?.toIntOrNull() ?: 0
                    if (n < 34) {
                        ext.javaClass.getMethod("setCompileSdkVersion", String::class.java)
                            .invoke(ext, "android-34")
                    }
                } catch (_: Throwable) { }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
