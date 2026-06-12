import com.google.protobuf.gradle.id
import com.google.protobuf.gradle.GenerateProtoTask

plugins {
    kotlin("jvm") version "2.0.21"
    id("com.google.protobuf") version "0.9.4"
    id("com.github.johnrengelman.shadow") version "8.1.1"
    application
}

group = "app"
version = "1.0.0"

repositories { mavenCentral() }

// grpc-kotlin-stub と grpc-netty-shaded の両方が google/api/*.proto を
// バンドルするため protoc が重複定義エラーを出す。shared.proto では
// google API アノテーションを使わないので除外する。
configurations.all {
    exclude(group = "com.google.api.grpc", module = "proto-google-common-protos")
}

val ktorVersion        = "2.3.12"
val grpcVersion        = "1.66.0"
val grpcKotlinVersion  = "1.4.1"
val protobufVersion    = "4.27.3"

dependencies {
    // Ktor — static file serving
    implementation("io.ktor:ktor-server-core:$ktorVersion")
    implementation("io.ktor:ktor-server-netty:$ktorVersion")

    // gRPC — grpc-netty-shaded は内部に google/protobuf/*.proto をバンドルし
    // protoc の WKT と二重定義エラーになるため非シェード版を使用
    implementation("io.grpc:grpc-netty:$grpcVersion")
    implementation("io.grpc:grpc-protobuf:$grpcVersion")
    implementation("io.grpc:grpc-kotlin-stub:$grpcKotlinVersion")
    implementation("com.google.protobuf:protobuf-kotlin:$protobufVersion")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")

    // HTTP client for VictoriaMetrics queries
    implementation("io.ktor:ktor-client-core:$ktorVersion")
    implementation("io.ktor:ktor-client-cio:$ktorVersion")
    implementation("io.ktor:ktor-client-content-negotiation:$ktorVersion")
    implementation("io.ktor:ktor-serialization-kotlinx-json:$ktorVersion")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // Logging
    implementation("ch.qos.logback:logback-classic:1.5.8")
}

application {
    mainClass.set("app.MainKt")
}

java {
    toolchain { languageVersion.set(JavaLanguageVersion.of(21)) }
}

// ---- SSOT: shared.proto を build/ 内にコピーして srcDir に使用 ----
// srcDir("../") でリポジトリルートを直接指定すると Gradle が全ファイルをスキャンし
// processResources / extractIncludeProto との implicit dependency 違反になる。
val copySharedProto by tasks.registering(Copy::class) {
    from(file("../shared.proto"))
    into(layout.buildDirectory.dir("proto-ssot"))
}

sourceSets {
    main {
        proto {
            srcDir(layout.buildDirectory.dir("proto-ssot"))
        }
    }
}

protobuf {
    protoc { artifact = "com.google.protobuf:protoc:$protobufVersion" }
    plugins {
        id("grpc")   { artifact = "io.grpc:protoc-gen-grpc-java:$grpcVersion" }
        id("grpckt") { artifact = "io.grpc:protoc-gen-grpc-kotlin:$grpcKotlinVersion:jdk8@jar" }
    }
    generateProtoTasks {
        all().forEach {
            it.plugins {
                id("grpc")
                id("grpckt")
            }
            it.builtins {
                id("kotlin")
            }
        }
    }
}

tasks.shadowJar {
    archiveClassifier.set("")
    mergeServiceFiles()
}

// protobuf-java/grpc の JAR に同梱された google/protobuf WKT が
// extracted-include-protos に展開され、protoc 組み込み WKT と衝突する。
// shared.proto は google/** を一切インポートしないため、実行前に削除して回避。
afterEvaluate {
    // processResources が proto-ssot / extractIncludeProto の出力を読む際の
    // Gradle 8.3+ implicit dependency 違反を解消する。
    tasks.named("processResources") {
        dependsOn(copySharedProto)
        dependsOn(tasks.named("extractIncludeProto"))
    }
    tasks.withType<GenerateProtoTask>().configureEach {
        dependsOn(copySharedProto)
        doFirst {
            // shared.proto は google/** を一切インポートしないため、
            // 依存 JAR から展開された全プロトを削除して protoc 組み込み WKT のみ使用する。
            val extractedDir = layout.buildDirectory.dir("extracted-include-protos/main").get().asFile
            if (extractedDir.exists()) {
                extractedDir.deleteRecursively()
            }
        }
    }
}
