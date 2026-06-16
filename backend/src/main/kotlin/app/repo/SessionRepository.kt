package app.repo

import app.db.withConnection
import java.sql.ResultSet
import java.sql.Timestamp
import java.time.Instant

data class DbSession(
    val id: Long,
    val tokenHash: String,
    val userId: Long,
    val expiresAt: Instant,
    val createdAt: Instant
)

object SessionRepository {
    fun create(tokenHash: String, userId: Long, expiresAt: Instant): DbSession {
        return withConnection { conn ->
            val sql = "INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)"
            conn.prepareStatement(sql, java.sql.Statement.RETURN_GENERATED_KEYS).use { stmt ->
                stmt.setString(1, tokenHash)
                stmt.setLong(2, userId)
                stmt.setTimestamp(3, Timestamp.from(expiresAt))
                stmt.executeUpdate()

                stmt.generatedKeys.use { rs ->
                    if (rs.next()) {
                        val id = rs.getLong(1)
                        return@withConnection DbSession(
                            id = id,
                            tokenHash = tokenHash,
                            userId = userId,
                            expiresAt = expiresAt,
                            createdAt = Instant.now()
                        )
                    }
                }
            }
            throw IllegalStateException("Failed to create session")
        }
    }

    fun findByTokenHash(tokenHash: String): DbSession? {
        return withConnection { conn ->
            val sql = "SELECT id, token_hash, user_id, expires_at, created_at FROM sessions WHERE token_hash = ?"
            conn.prepareStatement(sql).use { stmt ->
                stmt.setString(1, tokenHash)
                stmt.executeQuery().use { rs ->
                    if (rs.next()) {
                        return@withConnection mapRow(rs)
                    }
                }
            }
            null
        }
    }

    fun deleteByTokenHash(tokenHash: String) {
        withConnection { conn ->
            val sql = "DELETE FROM sessions WHERE token_hash = ?"
            conn.prepareStatement(sql).use { stmt ->
                stmt.setString(1, tokenHash)
                stmt.executeUpdate()
            }
        }
    }

    fun deleteExpiredBefore(now: Instant) {
        withConnection { conn ->
            val sql = "DELETE FROM sessions WHERE expires_at < ?"
            conn.prepareStatement(sql).use { stmt ->
                stmt.setTimestamp(1, Timestamp.from(now))
                stmt.executeUpdate()
            }
        }
    }

    private fun mapRow(rs: ResultSet): DbSession {
        return DbSession(
            id = rs.getLong("id"),
            tokenHash = rs.getString("token_hash"),
            userId = rs.getLong("user_id"),
            expiresAt = rs.getTimestamp("expires_at").toInstant(),
            createdAt = rs.getTimestamp("created_at").toInstant()
        )
    }
}
