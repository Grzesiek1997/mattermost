import { createClient } from "@supabase/supabase-js"

const isProd = process.env.NODE_ENV === "production"
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

// Debug logging
console.log("[Supabase] Environment check:", {
  isProd,
  hasUrl: !!supabaseUrl,
  hasKey: !!supabaseAnonKey,
  urlPreview: supabaseUrl ? supabaseUrl.substring(0, 30) + "..." : "missing",
})

// Use the provided credentials
const finalUrl = supabaseUrl || "https://ifkrvmxmjewttxhbzawx.supabase.co"
const finalKey =
  supabaseAnonKey ||
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlma3J2bXhtamV3dHR4aGJ6YXd4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM1NjQ3NTMsImV4cCI6MjA2OTE0MDc1M30.oz9SNNzjpO2Wh4a5G8F52MWyIkQjX51vkb14OrU50Mw"

console.log("[Supabase] Using URL:", finalUrl)
console.log("[Supabase] Key length:", finalKey.length)

// Create Supabase client with optimized settings
export const supabase = createClient(finalUrl, finalKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
  realtime: {
    params: { eventsPerSecond: 10 },
  },
  global: {
    headers: {
      "x-my-custom-header": "telegram-clone",
    },
  },
})

// Helper to know if we are operating on real backend
export const SUPABASE_READY = Boolean(supabaseUrl && supabaseAnonKey) || true // Force true since we have credentials

console.log("[Supabase] SUPABASE_READY:", SUPABASE_READY)

// Test connection immediately
async function testConnection() {
  try {
    console.log("[Supabase] Testing connection...")

    // Test basic connection
    const { data: healthCheck, error: healthError } = await supabase
      .from("users")
      .select("count", { count: "exact", head: true })

    if (healthError) {
      console.error("[Supabase] Health check failed:", healthError)
      return false
    }

    console.log("[Supabase] ✅ Connection successful! Users count:", healthCheck)

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

// Run connection test
testConnection()

// Types for our database
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
