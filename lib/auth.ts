import { supabase, SUPABASE_READY } from "./supabase"
import type { User } from "./supabase"

const DEMO_USER_KEY = "__demo_user__"

/** Persist demo-mode user in localStorage so page reloads keep the session. */
function setDemoUser(user: any | null) {
  if (typeof window === "undefined") return
  if (user) {
    localStorage.setItem(DEMO_USER_KEY, JSON.stringify(user))
  } else {
    localStorage.removeItem(DEMO_USER_KEY)
  }
}

function getDemoUser() {
  if (typeof window === "undefined") return null
  const raw = localStorage.getItem(DEMO_USER_KEY)
  return raw ? JSON.parse(raw) : null
}

export class AuthService {
  static async signUp(email: string, password: string, userData: Partial<User>) {
    if (!SUPABASE_READY) {
      /* ---------- DEMO MODE FALLBACK ---------- */
      const demoUser: User = {
        id: "demo-" + Math.random().toString(36).slice(2),
        email,
        username: userData.username || email.split("@")[0],
        full_name: userData.full_name || "Demo User",
        avatar_url: userData.avatar_url,
        bio: userData.bio,
        phone: userData.phone,
        is_online: true,
        last_seen: new Date().toISOString(),
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }
      setDemoUser(demoUser)
      console.warn("[Auth] Demo mode - user created locally")
      return { user: demoUser }
    }

    try {
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            username: userData.username,
            full_name: userData.full_name,
          },
        },
      })

      if (error) throw error

      if (data.user) {
        // Insert user profile
        const { error: profileError } = await supabase.from("users").insert({
          id: data.user.id,
          email: data.user.email!,
          username: userData.username,
          full_name: userData.full_name,
          bio: userData.bio,
          avatar_url: userData.avatar_url,
          phone: userData.phone,
          is_online: true,
          last_seen: new Date().toISOString(),
        })

        if (profileError) throw profileError
      }

      return data
    } catch (error: any) {
      if (error.message?.includes("Failed to fetch")) {
        // Network error fallback
        const demoUser: User = {
          id: "demo-" + Math.random().toString(36).slice(2),
          email,
          username: userData.username || email.split("@")[0],
          full_name: userData.full_name || "Demo User",
          avatar_url: userData.avatar_url,
          bio: userData.bio,
          phone: userData.phone,
          is_online: true,
          last_seen: new Date().toISOString(),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }
        setDemoUser(demoUser)
        console.warn("[Auth] Network error - using demo mode")
        return { user: demoUser }
      }
      throw error
    }
  }

  static async signIn(email: string, password: string) {
    if (!SUPABASE_READY) {
      /* ---------- DEMO MODE FALLBACK ---------- */
      const stored = getDemoUser()
      const demoUser: User =
        stored && stored.email === email
          ? stored
          : {
              id: "demo-" + Math.random().toString(36).slice(2),
              email,
              username: email.split("@")[0],
              full_name: "Demo User",
              is_online: true,
              last_seen: new Date().toISOString(),
              created_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
            }
      setDemoUser(demoUser)
      console.warn("[Auth] Demo mode - user signed in locally")
      return { user: demoUser }
    }

    try {
      const { data, error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) throw error

      if (data.user) {
        // Update online status
        await supabase
          .from("users")
          .update({
            is_online: true,
            last_seen: new Date().toISOString(),
          })
          .eq("id", data.user.id)
      }

      return data
    } catch (error: any) {
      if (error.message?.includes("Failed to fetch")) {
        // Network error fallback
        const stored = getDemoUser()
        const demoUser: User =
          stored && stored.email === email
            ? stored
            : {
                id: "demo-" + Math.random().toString(36).slice(2),
                email,
                username: email.split("@")[0],
                full_name: "Demo User",
                is_online: true,
                last_seen: new Date().toISOString(),
                created_at: new Date().toISOString(),
                updated_at: new Date().toISOString(),
              }
        setDemoUser(demoUser)
        console.warn("[Auth] Network error - using demo mode")
        return { user: demoUser }
      }
      throw error
    }
  }

  static async signOut() {
    if (!SUPABASE_READY) {
      setDemoUser(null)
      return
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (user) {
        await supabase
          .from("users")
          .update({
            is_online: false,
            last_seen: new Date().toISOString(),
          })
          .eq("id", user.id)
      }

      const { error } = await supabase.auth.signOut()
      if (error) throw error
    } catch (error) {
      console.error("Sign out error:", error)
    }
  }

  static async getCurrentUser(): Promise<User | null> {
    if (!SUPABASE_READY) {
      return getDemoUser()
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) return null

      const { data: profile, error } = await supabase.from("users").select("*").eq("id", user.id).single()

      if (error) {
        console.error("Error fetching user profile:", error)
        return null
      }

      return profile
    } catch (error) {
      console.error("Get current user error:", error)
      return null
    }
  }

  static async updateProfile(userId: string, updates: Partial<User>) {
    if (!SUPABASE_READY) {
      const stored = getDemoUser()
      if (stored && stored.id === userId) {
        const updated = { ...stored, ...updates, updated_at: new Date().toISOString() }
        setDemoUser(updated)
        return updated
      }
      throw new Error("User not found")
    }

    const { data, error } = await supabase
      .from("users")
      .update({
        ...updates,
        updated_at: new Date().toISOString(),
      })
      .eq("id", userId)
      .select()
      .single()

    if (error) throw error
    return data
  }
}
