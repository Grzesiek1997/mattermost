import { createClient } from "@supabase/supabase-js"

export const isSupabaseConfigured =
  (typeof process.env.NEXT_PUBLIC_SUPABASE_URL === "string" && process.env.NEXT_PUBLIC_SUPABASE_URL.length > 0) ||
  (typeof process.env.SUPABASE_URL === "string" && process.env.SUPABASE_URL.length > 0)

export const SUPABASE_READY = isSupabaseConfigured

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL || ""
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY || ""

// Debug logging
console.log("[Supabase] Environment check:", {
  hasUrl: !!supabaseUrl,
  hasKey: !!supabaseAnonKey,
  urlPreview: supabaseUrl ? supabaseUrl.substring(0, 30) + "..." : "missing",
  configured: isSupabaseConfigured,
})

if (!isSupabaseConfigured) {
  console.warn("[Supabase] Missing environment variables. Please configure Supabase integration in Project Settings.")
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true,
  },
})

async function testConnection() {
  if (!isSupabaseConfigured) {
    console.warn("[Supabase] Skipping connection test - Supabase not configured")
    return false
  }

  try {
    console.log("[Supabase] Testing connection...")

    // Simple auth session check instead of table access
    const { data: authData, error: authError } = await supabase.auth.getSession()

    if (authError) {
      console.error("[Supabase] Connection test failed:", authError.message)
      return false
    }

    console.log("[Supabase] ✅ Connection successful!")
    console.log("[Supabase] Auth status:", authData.session ? "Authenticated" : "Not authenticated")

    return true
  } catch (err: any) {
    console.error("[Supabase] Connection test failed:", err.message)
    return false
  }
}

// Run connection test only if configured
if (isSupabaseConfigured && typeof window !== "undefined") {
  testConnection()
}

// Restored all TypeScript interfaces that other components depend on
export interface User {
  id: string
  email: string
  username?: string
  full_name?: string
  bio?: string
  avatar_url?: string
  phone?: string
  is_online: boolean
  last_seen: string
  created_at: string
  updated_at: string
}

export interface Chat {
  id: string
  type: "direct" | "group" | "channel"
  title?: string
  description?: string
  avatar_url?: string
  created_by: string
  created_at: string
  updated_at: string
  last_message_at: string
}

export interface Message {
  id: string
  chat_id: string
  user_id: string
  content?: string
  message_type: "text" | "image" | "file" | "voice" | "video"
  file_url?: string
  file_name?: string
  file_size?: number
  reply_to_id?: string
  thread_id?: string
  is_edited: boolean
  is_deleted: boolean
  created_at: string
  updated_at: string
  user?: User
  reactions?: MessageReaction[]
  reply_to?: Message
}

export interface MessageReaction {
  id: string
  message_id: string
  user_id: string
  emoji: string
  created_at: string
  user?: User
}

export interface ChatMember {
  id: string
  chat_id: string
  user_id: string
  role: "owner" | "admin" | "member"
  joined_at: string
  can_send_messages: boolean
  can_add_members: boolean
  can_delete_messages: boolean
  user?: User
}

export interface TypingIndicator {
  id: string
  chat_id: string
  user_id: string
  is_typing: boolean
  updated_at: string
  user?: User
}
