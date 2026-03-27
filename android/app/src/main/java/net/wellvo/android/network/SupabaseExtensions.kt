package net.wellvo.android.network

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.PostgrestQueryBuilder
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.realtime.realtime

val SupabaseClient.authClient: Auth
    get() = auth

val SupabaseClient.db: Postgrest
    get() = postgrest

val SupabaseClient.realtimeClient: Realtime
    get() = realtime

val SupabaseClient.functionsClient: Functions
    get() = functions

fun SupabaseClient.from(table: String): PostgrestQueryBuilder {
    return postgrest.from(table)
}

suspend inline fun <reified T : Any> SupabaseClient.selectAll(table: String): List<T> {
    return postgrest.from(table).select().decodeList()
}

suspend inline fun <reified T : Any> SupabaseClient.selectById(table: String, id: String): T {
    return postgrest.from(table).select {
        filter { eq("id", id) }
    }.decodeSingle()
}

suspend inline fun <reified T : Any> SupabaseClient.selectWhere(
    table: String,
    column: String,
    value: String
): List<T> {
    return postgrest.from(table).select {
        filter { eq(column, value) }
    }.decodeList()
}

suspend inline fun <reified T : Any> SupabaseClient.insertRow(table: String, row: T) {
    postgrest.from(table).insert(row)
}

suspend inline fun <reified T : Any> SupabaseClient.upsertRow(table: String, row: T) {
    postgrest.from(table).upsert(row)
}

suspend fun SupabaseClient.deleteById(table: String, id: String) {
    postgrest.from(table).delete {
        filter { eq("id", id) }
    }
}
