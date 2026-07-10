// Root Gradle configuration.
//
// The `afterEvaluate` override forces every Android library subproject up to
// compileSdk 36. Some transitive plugin dependencies (e.g. flutter_plugin_
// android_lifecycle) already require 36 while a few older plugin releases
// still ship with 34, which trips CheckAarMetadata during merge. The override
// MUST be declared before the `evaluationDependsOn(":app")` block below,
// otherwise Gradle refuses to attach afterEvaluate callbacks
// (see gray_part_pitfalls.md §2 and §7).

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory
    .dir("../../build")
    .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.apply {
                if ((compileSdk ?: 0) < 36) {
                    compileSdk = 36
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
