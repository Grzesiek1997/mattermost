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

// ---------------------------------------------------------------------------
// 1.  Production  ➜  hard-fail if credentials are missing
// 2.  Preview / dev ➜  fall back to public demo project so the UI renders
// ---------------------------------------------------------------------------
if (isProd && (!supabaseUrl || !supabaseAnonKey)) {
  throw new Error(
    "Missing Supabase env vars. Add NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY on Vercel.",
  )
}

// Public playground (read-only) – lets preview build start without crashing
const FALLBACK_URL = "https://obkftjvrfpcumryromnh.supabase.co"
const FALLBACK_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9ia2Z0anZyZnBjdW1yeXJvbW5oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDk4MjU2MDAsImV4cCI6MjAyNTQwMTYwMH0.demo-key-for-preview"

const finalUrl = supabaseUrl ?? FALLBACK_URL
const finalKey = supabaseAnonKey ?? FALLBACK_KEY

console.log("[Supabase] Using:", {
  url: finalUrl.substring(0, 30) + "...",
  isReal: !!supabaseUrl,
})

export const supabase = createClient(finalUrl, finalKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
  realtime: { params: { eventsPerSecond: 10 } },
})

// Helper to know if we are operating on real backend
export const SUPABASE_READY = Boolean(supabaseUrl && supabaseAnonKey)

console.log("[Supabase] SUPABASE_READY:", SUPABASE_READY)

// Test connection
supabase
  .from("users")
  .select("count", { count: "exact", head: true })
  .then(({ count, error }) => {
    if (error) {
      console.log("[Supabase] Connection test failed:", error.message)
    } else {
      console.log("[Supabase] Connection test successful, users count:", count)
    }
  })
  .catch((err) => {
    console.log("[Supabase] Connection test error:", err.message)
  })

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
