package net.dailyok.android.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime
import net.dailyok.android.BuildConfig
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun provideSupabaseClient(): SupabaseClient {
        return createSupabaseClient(
            supabaseUrl = BuildConfig.SUPABASE_URL,
            supabaseKey = BuildConfig.SUPABASE_ANON_KEY
        ) {
            install(Auth)
            install(Postgrest)
            install(Realtime)
            // Edge functions run as one Deno server at functions.dailyok.net
            // (CLAUDE.md), not as Supabase-hosted functions. Without a custom
            // URL the plugin called <SUPABASE_URL>/functions/v1/<name>, so every
            // check-in, join, invite and heartbeat from Android missed the
            // server. iOS has always used EDGE_FUNCTIONS_URL (EdgeFunctionsClient).
            install(Functions) {
                customUrl = BuildConfig.EDGE_FUNCTIONS_URL.trimEnd('/').ifBlank { null }
            }
        }
    }
}
