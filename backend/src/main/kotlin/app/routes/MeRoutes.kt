package app.routes

import app.auth.SessionAuth
import app.auth.SessionAuth.authenticatedUser
import app.repo.LinkRepository
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable

@Serializable
data class LinkedAccountResponse(
    val id: Long,
    val userId: Long,
    val edition: String,
    val ign: String,
    val externalId: String?,
    val linkedAt: String
)

@Serializable
data class MeResponse(
    val user: UserResponse,
    val accounts: List<LinkedAccountResponse>
)

@Serializable
data class LinkRequest(
    val edition: String,
    val ign: String
)

fun Route.meRoutes() {
    route("/me") {
        intercept(ApplicationCallPipeline.Plugins) {
            SessionAuth.intercept(this)
        }

        get {
            val user = call.authenticatedUser
            val accounts = LinkRepository.listByUserId(user.id).map {
                LinkedAccountResponse(
                    id = it.id,
                    userId = it.userId,
                    edition = it.edition,
                    ign = it.ign,
                    externalId = it.externalId,
                    linkedAt = it.linkedAt.toString()
                )
            }

            call.respond(HttpStatusCode.OK, MeResponse(
                user = UserResponse(
                    id = user.id,
                    misskeyId = user.misskeyId,
                    misskeyHost = user.misskeyHost,
                    username = user.username
                ),
                accounts = accounts
            ))
        }

        post("/accounts") {
            val user = call.authenticatedUser
            val req = try {
                call.receive<LinkRequest>()
            } catch (e: Exception) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Invalid request body"))
                return@post
            }

            val edition = req.edition.lowercase()
            if (edition != "java" && edition != "bedrock") {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Edition must be either 'java' or 'bedrock'"))
                return@post
            }

            val ign = req.ign.trim()
            val javaRegex = Regex("^[A-Za-z0-9_]{1,16}$")
            val bedrockRegex = Regex("^[\\w ]{1,32}$")

            val isValid = if (edition == "java") {
                javaRegex.matches(ign)
            } else {
                bedrockRegex.matches(ign)
            }

            if (!isValid) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Invalid IGN format"))
                return@post
            }

            try {
                val account = LinkRepository.link(
                    userId = user.id,
                    edition = edition,
                    ign = ign,
                    actor = "self"
                )

                call.respond(HttpStatusCode.Created, LinkedAccountResponse(
                    id = account.id,
                    userId = account.userId,
                    edition = account.edition,
                    ign = account.ign,
                    externalId = account.externalId,
                    linkedAt = account.linkedAt.toString()
                ))
            } catch (e: Exception) {
                val msg = e.message ?: ""
                if (msg.contains("Duplicate entry") || msg.contains("ConstraintViolation") || e is java.sql.SQLIntegrityConstraintViolationException) {
                    call.respond(HttpStatusCode.Conflict, mapOf("error" to "Account already linked"))
                } else {
                    call.respond(HttpStatusCode.InternalServerError, mapOf("error" to "Database error: ${e.message}"))
                }
            }
        }

        delete("/accounts/{id}") {
            val user = call.authenticatedUser
            val id = call.parameters["id"]?.toLongOrNull()
            if (id == null) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Invalid account ID"))
                return@delete
            }

            val account = LinkRepository.findById(id)
            if (account == null) {
                call.respond(HttpStatusCode.NotFound, mapOf("error" to "Account not found"))
                return@delete
            }

            if (account.userId != user.id) {
                call.respond(HttpStatusCode.Forbidden, mapOf("error" to "You do not own this account"))
                return@delete
            }

            val deleted = LinkRepository.unlink(
                userId = user.id,
                id = id,
                actor = "self"
            )

            if (deleted) {
                call.respond(HttpStatusCode.NoContent)
            } else {
                call.respond(HttpStatusCode.InternalServerError, mapOf("error" to "Failed to unlink account"))
            }
        }
    }
}
