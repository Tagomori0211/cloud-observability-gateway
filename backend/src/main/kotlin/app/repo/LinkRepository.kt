package app.repo

import app.db.withConnection
import app.db.runInTransaction
import java.sql.ResultSet
import java.sql.Statement
import java.time.Instant

data class DbLinkedMcAccount(
    val id: Long,
    val userId: Long,
    val edition: String, // 'java' | 'bedrock'
    val ign: String,
    val externalId: String?,
    val linkedAt: Instant
)

object LinkRepository {
    fun listByUserId(userId: Long): List<DbLinkedMcAccount> {
        return withConnection { conn ->
            val sql = "SELECT id, user_id, edition, ign, external_id, linked_at FROM linked_mc_accounts WHERE user_id = ?"
            conn.prepareStatement(sql).use { stmt ->
                stmt.setLong(1, userId)
                stmt.executeQuery().use { rs ->
                    val list = mutableListOf<DbLinkedMcAccount>()
                    while (rs.next()) {
                        list.add(mapRow(rs))
                    }
                    list
                }
            }
        }
    }

    fun findById(id: Long): DbLinkedMcAccount? {
        return withConnection { conn ->
            val sql = "SELECT id, user_id, edition, ign, external_id, linked_at FROM linked_mc_accounts WHERE id = ?"
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

    fun link(userId: Long, edition: String, ign: String, actor: String): DbLinkedMcAccount {
        return runInTransaction { conn ->
            val insertLinkSql = """
                INSERT INTO linked_mc_accounts (user_id, edition, ign) 
                VALUES (?, ?, ?)
            """.trimIndent()
            
            var generatedId: Long = -1
            conn.prepareStatement(insertLinkSql, Statement.RETURN_GENERATED_KEYS).use { stmt ->
                stmt.setLong(1, userId)
                stmt.setString(2, edition)
                stmt.setString(3, ign)
                stmt.executeUpdate()
                
                stmt.generatedKeys.use { rs ->
                    if (rs.next()) {
                        generatedId = rs.getLong(1)
                    }
                }
            }
            
            if (generatedId == -1L) {
                throw IllegalStateException("Failed to insert linked account")
            }

            val insertAuditSql = """
                INSERT INTO link_audit (user_id, action, edition, ign, actor) 
                VALUES (?, 'link', ?, ?, ?)
            """.trimIndent()
            conn.prepareStatement(insertAuditSql).use { stmt ->
                stmt.setLong(1, userId)
                stmt.setString(2, edition)
                stmt.setString(3, ign)
                stmt.setString(4, actor)
                stmt.executeUpdate()
            }

            DbLinkedMcAccount(
                id = generatedId,
                userId = userId,
                edition = edition,
                ign = ign,
                externalId = null,
                linkedAt = Instant.now()
            )
        }
    }

    fun unlink(userId: Long, id: Long, actor: String): Boolean {
        val account = findById(id) ?: return false
        if (account.userId != userId) {
            return false
        }

        return runInTransaction { conn ->
            val deleteSql = "DELETE FROM linked_mc_accounts WHERE id = ? AND user_id = ?"
            var rowsDeleted = 0
            conn.prepareStatement(deleteSql).use { stmt ->
                stmt.setLong(1, id)
                stmt.setLong(2, userId)
                rowsDeleted = stmt.executeUpdate()
            }

            if (rowsDeleted > 0) {
                val insertAuditSql = """
                    INSERT INTO link_audit (user_id, action, edition, ign, actor) 
                    VALUES (?, 'unlink', ?, ?, ?)
                """.trimIndent()
                conn.prepareStatement(insertAuditSql).use { stmt ->
                    stmt.setLong(1, userId)
                    stmt.setString(2, account.edition)
                    stmt.setString(3, account.ign)
                    stmt.setString(4, actor)
                    stmt.executeUpdate()
                }
                true
            } else {
                false
            }
        }
    }

    private fun mapRow(rs: ResultSet): DbLinkedMcAccount {
        return DbLinkedMcAccount(
            id = rs.getLong("id"),
            userId = rs.getLong("user_id"),
            edition = rs.getString("edition"),
            ign = rs.getString("ign"),
            externalId = rs.getString("external_id"),
            linkedAt = rs.getTimestamp("linked_at").toInstant()
        )
    }
}
