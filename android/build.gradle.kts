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
subprojects {
    project.evaluationDependsOn(":app")
    // Force all plugins to compile with Java 17 and suppress obsolete-options warnings
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
        options.compilerArgs.addAll(listOf("-Xlint:-options", "-Xlint:-deprecation"))
    }
    // AGP 8.1+ requires an explicit 'namespace' in every Android library module.
    // Many older Flutter plugins don't specify one; infer it from their AndroidManifest.xml
    // package attribute (the pre-AGP-8 way of declaring the namespace).
    if (!state.executed) {
        afterEvaluate {
            val androidLib = extensions.findByType<com.android.build.gradle.LibraryExtension>()
            if (androidLib != null) {
                // Force compileSdk to at least 35 for plugins compiled against older APIs
                if ((androidLib.compileSdk ?: 0) < 35) {
                    androidLib.compileSdk = 35
                }
                if (androidLib.namespace == null) {
                    val manifestFile = file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val pkg = groovy.xml.XmlParser().parse(manifestFile)
                            .attribute("package")?.toString()
                        if (pkg != null) {
                            androidLib.namespace = pkg
                        }
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
