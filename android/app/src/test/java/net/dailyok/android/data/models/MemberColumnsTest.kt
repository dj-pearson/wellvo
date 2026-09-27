package net.dailyok.android.data.models

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Member rows no longer carry other people's email / phone (00067). */
class MemberColumnsTest {

    private fun columns(list: String): Set<String> = list.split(",").map { it.trim() }.toSet()

    @Test
    fun `member columns leave out private fields`() {
        val member = columns(AppUser.MEMBER_COLUMNS)
        listOf("email", "phone", "is_system_admin", "*").forEach { assertFalse(it, it in member) }
        listOf("id", "display_name", "role", "timezone", "created_at", "updated_at").forEach { assertTrue(it, it in member) }
        assertTrue(columns(AppUser.SELF_COLUMNS).containsAll(listOf("email", "phone")))
        assertTrue(FamilyMember.COLUMNS_WITH_USER.endsWith("users(${AppUser.MEMBER_COLUMNS})"))
        assertFalse(FamilyMember.COLUMNS_WITH_USER.contains("*"))
    }

    @Test
    fun `family columns leave out the billing receipt`() {
        val family = columns(Family.COLUMNS)
        listOf("*", "billing_original_transaction_id", "billing_platform", "billing_verified_at")
            .forEach { assertFalse(it, it in family) }
    }
}
