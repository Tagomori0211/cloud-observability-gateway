package app

import io.grpc.ServerBuilder
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.http.content.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import java.io.File

fun main() {
    val vmUrl = System.getenv("VICTORIA_METRICS_URL") ?: "http://localhost:8428"

    // ---- gRPC server :50051 ----
    val grpcServer = ServerBuilder
        .forPort(50051)
        .addService(SharedServiceImpl(vmUrl))
        .build()
        .start()
    println("gRPC server started on :50051")

    // ---- Ktor static file server :8080 ----
    // Flutter Web assets are bind-mounted to /app/web by docker-compose.
    // SPA fallback: unknown paths → index.html.
    embeddedServer(Netty, port = 8080) {
        routing {
            // index.html と flutter_bootstrap.js はデプロイ毎に変わるため no-store を付加し
            // Cloudflare エッジキャッシュ / ブラウザ HTTP キャッシュに古い JS が残るのを防ぐ。
            get("/") {
                call.response.headers.append(HttpHeaders.CacheControl, "no-store")
                call.respond(LocalFileContent(File("/app/web/index.html")))
            }
            get("/index.html") {
                call.response.headers.append(HttpHeaders.CacheControl, "no-store")
                call.respond(LocalFileContent(File("/app/web/index.html")))
            }
            get("/flutter_bootstrap.js") {
                call.response.headers.append(HttpHeaders.CacheControl, "no-store")
                call.respond(LocalFileContent(File("/app/web/flutter_bootstrap.js")))
            }
            singlePageApplication {
                useResources = false
                filesPath = "/app/web"
                defaultPage = "index.html"
            }
        }
    }.start(wait = false)
    println("Static file server started on :8080")

    grpcServer.awaitTermination()
}
