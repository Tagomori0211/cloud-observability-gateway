package app

import io.grpc.ServerBuilder
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.http.content.*
import io.ktor.server.routing.*

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
