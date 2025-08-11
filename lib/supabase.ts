import { createClientComponentClient } from "@supabase/auth-helpers-nextjs"

// Check if Supabase environment variables are available
export const isSupabaseConfigured =
  typeof process.env.NEXT_PUBLIC_SUPABASE_URL === "string" &&
  process.env.NEXT_PUBLIC_SUPABASE_URL.length > 0 &&
  typeof process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY === "string" &&
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY.length > 0

// Debug logging
console.log("[Supabase] Environment check:", {
  hasUrl: !!process.env.NEXT_PUBLIC_SUPABASE_URL,
  hasKey: !!process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  urlPreview: process.env.NEXT_PUBLIC_SUPABASE_URL
    ? process.env.NEXT_PUBLIC_SUPABASE_URL.substring(0, 30) + "..."
    : "missing",
  configured: isSupabaseConfigured,
})

if (!isSupabaseConfigured) {
  console.warn("[Supabase] Missing environment variables. Please configure Supabase integration in Project Settings.")
}

export const supabase = createClientComponentClient()

// Added back SUPABASE_READY export for compatibility
export const SUPABASE_READY = isSupabaseConfigured

async function testConnection() {
  if (!isSupabaseConfigured) {
    console.warn("[Supabase] Skipping connection test - Supabase not configured")
    return false
  }

  try {
    console.log("[Supabase] Testing connection...")

    // Test basic connection with a simple query
    const { data: healthCheck, error: healthError } = await supabase
      .from("users")
      .select("count", { count: "exact", head: true })

    if (healthError) {
      console.error("[Supabase] Health check failed:", healthError.message)
      return false
    }

    console.log("[Supabase] ✅ Connection successful!")

    // Test auth
    const { data: authData, error: authError } = await supabase.auth.getSession()
    if (authError) {
      console.warn("[Supabase] Auth check warning:", authError.message)
    } else {
      console.log("[Supabase] Auth status:", authData.session ? "Authenticated" : "Not authenticated")
    }

    return true
  } catch (err: any) {
    console.error("[Supabase] Connection test failed:", err.message)
    return false
  }
}

// Run connection test only if configured
if (isSupabaseConfigured) {
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
