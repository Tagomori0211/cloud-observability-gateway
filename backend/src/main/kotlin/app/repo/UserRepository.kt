package app.repo

import app.db.withConnection
import java.sql.ResultSet
import java.sql.Statement

data class DbUser(
    val id: Long,
    val misskeyId: String,
    val misskeyHost: String,
    val username: String,
    val passwordHash: String?
)

object UserRepository {
    fun upsert(misskeyId: String, misskeyHost: String, username: String): DbUser {
        return withConnection { conn ->
            val sql = """
                INSERT INTO users (misskey_id, misskey_host, username)
                VALUES (?, ?, ?)
                ON DUPLICATE KEY UPDATE username = VALUES(username)
            """.trimIndent()

            conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS).use { stmt ->
                stmt.setString(1, misskeyId)
                stmt.setString(2, misskeyHost)
                stmt.setString(3, username)
                stmt.executeUpdate()
            }

            findByMisskey(misskeyId, misskeyHost) ?: throw IllegalStateException("Failed to retrieve upserted user")
        }
    }

    fun setPassword(userId: Long, passwordHash: String) {
        withConnection { conn ->
            val sql = "UPDATE users SET password_hash = ? WHERE id = ?"
            conn.prepareStatement(sql).use { stmt ->
                stmt.setString(1, passwordHash)
                stmt.setLong(2, userId)
                stmt.executeUpdate()
            }
        }
    }

    fun findById(id: Long): DbUser? {
        return withConnection { conn ->
            val sql = "SELECT id, misskey_id, misskey_host, username, password_hash FROM users WHERE id = ?"
            conn.prepareStatement(sql).use { stmt ->
                stmt.setLong(1, id)
                stmt.executeQuery().use { rs ->
                    if (rs.next()) {
                        return@withConnection mapRow(rs)
                    }
                }
            }
            null
        }
    }

    fun findByMisskey(misskeyId: String, misskeyHost: String): DbUser? {
        return withConnection { conn ->
            val sql = "SELECT id, misskey_id, misskey_host, username, password_hash FROM users WHERE misskey_id = ? AND misskey_host = ?"
            conn.prepareStatement(sql).use { stmt ->
                stmt.setString(1, misskeyId)
                stmt.setString(2, misskeyHost)
                stmt.executeQuery().use { rs ->
                    if (rs.next()) {
                        return@withConnection mapRow(rs)
                    }
                }
            }
            null
        }
    }

    fun findByUsername(username: String): DbUser? {
        return withConnection { conn ->
            val sql = "SELECT id, misskey_id, misskey_host, username, password_hash FROM users WHERE username = ?"
            conn.prepareStatement(sql).use { stmt ->
                stmt.setString(1, username)
                stmt.executeQuery().use { rs ->
                    if (rs.next()) {
                        return@withConnection mapRow(rs)
                    }
                }
            }
            null
        }
    }

    private fun mapRow(rs: ResultSet): DbUser {
        return DbUser(
            id = rs.getLong("id"),
            misskeyId = rs.getString("misskey_id"),
            misskeyHost = rs.getString("misskey_host"),
            username = rs.getString("username"),
            passwordHash = rs.getString("password_hash")
        )
    }
}
