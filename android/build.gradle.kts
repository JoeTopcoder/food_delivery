allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // Several Flutter plugins (share_plus, flutter_tts, stripe_android, etc.) still
    // apply their own Kotlin Gradle Plugin via a legacy buildscript classpath block,
    // which conflicts with the project-level KGP 2.3.0 and causes K2 compiler errors
    // such as "Unresolved reference" for classes in the same package.
    // Forcing every KGP + stdlib coordinate to 2.3.0 — in both buildscript classpath
    // and runtime configurations — ensures a single consistent Kotlin toolchain is used
    // throughout the build, eliminating the inter-version K2 incompatibilities.
    val kotlinVersion = "2.3.0"
    buildscript {
        configurations.all {
            resolutionStrategy {
                force("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
                force("org.jetbrains.kotlin:kotlin-stdlib:$kotlinVersion")
                force("org.jetbrains.kotlin:kotlin-stdlib-jdk7:$kotlinVersion")
                force("org.jetbrains.kotlin:kotlin-stdlib-jdk8:$kotlinVersion")
                force("org.jetbrains.kotlin:kotlin-reflect:$kotlinVersion")
            }
        }
    }
    configurations.all {
        resolutionStrategy {
            force("org.jetbrains.kotlin:kotlin-stdlib:$kotlinVersion")
            force("org.jetbrains.kotlin:kotlin-stdlib-jdk7:$kotlinVersion")
            force("org.jetbrains.kotlin:kotlin-stdlib-jdk8:$kotlinVersion")
            force("org.jetbrains.kotlin:kotlin-reflect:$kotlinVersion")
        }
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
