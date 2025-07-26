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
    console.log("[AuthService] signUp called with:", { email, hasPassword: !!password })

    if (!SUPABASE_READY) {
      console.log("[AuthService] Using demo mode for signup")
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
      return { user: demoUser }
    }

    try {
      console.log("[AuthService] Attempting real Supabase signup...")
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

      if (error) {
        console.error("[AuthService] Supabase signup error:", error)
        throw error
      }

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

        if (profileError) {
          console.error("[AuthService] Profile creation error:", profileError)
          throw profileError
        }
      }

      console.log("[AuthService] Signup successful")
      return data
    } catch (error: any) {
      console.error("[AuthService] Signup failed:", error)

      // Enhanced fallback logic
      if (
        error.message?.includes("Failed to fetch") ||
        error.message?.includes("NetworkError") ||
        error.message?.includes("fetch")
      ) {
        console.log("[AuthService] Network error detected, using demo mode")
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
        return { user: demoUser }
      }
      throw error
    }
  }

  static async signIn(email: string, password: string) {
    console.log("[AuthService] signIn called with:", { email, hasPassword: !!password })

    if (!SUPABASE_READY) {
      console.log("[AuthService] Using demo mode for signin")
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
      return { user: demoUser }
    }

    try {
      console.log("[AuthService] Attempting real Supabase signin...")
      const { data, error } = await supabase.auth.signInWithPassword({ email, password })

      if (error) {
        console.error("[AuthService] Supabase signin error:", error)
        throw error
      }

      if (data.user) {
        // Update online status
        try {
          await supabase
            .from("users")
            .update({
              is_online: true,
              last_seen: new Date().toISOString(),
            })
            .eq("id", data.user.id)
        } catch (updateError) {
          console.warn("[AuthService] Failed to update online status:", updateError)
          // Don't fail the signin for this
        }
      }

      console.log("[AuthService] Signin successful")
      return data
    } catch (error: any) {
      console.error("[AuthService] Signin failed:", error)

      // Enhanced fallback logic for network errors
      if (
        error.message?.includes("Failed to fetch") ||
        error.message?.includes("NetworkError") ||
        error.message?.includes("fetch") ||
        error.name === "TypeError"
      ) {
        console.log("[AuthService] Network/fetch error detected, using demo mode")
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
        return { user: demoUser }
      }
      throw error
    }
  }

  static async signOut() {
    console.log("[AuthService] signOut called")

    if (!SUPABASE_READY) {
      console.log("[AuthService] Demo mode signout")
      setDemoUser(null)
      return
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (user) {
        try {
          await supabase
            .from("users")
            .update({
              is_online: false,
              last_seen: new Date().toISOString(),
            })
            .eq("id", user.id)
        } catch (updateError) {
          console.warn("[AuthService] Failed to update offline status:", updateError)
        }
      }

      const { error } = await supabase.auth.signOut()
      if (error) throw error

      console.log("[AuthService] Signout successful")
    } catch (error) {
      console.error("[AuthService] Signout error:", error)
      // Always clear demo user on signout attempt
      setDemoUser(null)
    }
  }

  static async getCurrentUser(): Promise<User | null> {
    console.log("[AuthService] getCurrentUser called")

    if (!SUPABASE_READY) {
      console.log("[AuthService] Demo mode - returning stored user")
      return getDemoUser()
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) {
        console.log("[AuthService] No authenticated user")
        return getDemoUser() // Fallback to demo user if available
      }

      const { data: profile, error } = await supabase.from("users").select("*").eq("id", user.id).single()

      if (error) {
        console.error("[AuthService] Error fetching user profile:", error)
        // Return basic user info if profile fetch fails
        const basicUser: User = {
          id: user.id,
          email: user.email!,
          username: user.user_metadata?.username || user.email!.split("@")[0],
          full_name: user.user_metadata?.full_name || "User",
          is_online: true,
          last_seen: new Date().toISOString(),
          created_at: user.created_at,
          updated_at: new Date().toISOString(),
        }
        return basicUser
      }

      console.log("[AuthService] User profile fetched successfully")
      return profile
    } catch (error) {
      console.error("[AuthService] getCurrentUser error:", error)
      // Final fallback to demo user
      return getDemoUser()
    }
  }

  static async updateProfile(userId: string, updates: Partial<User>) {
    console.log("[AuthService] updateProfile called for:", userId)

    if (!SUPABASE_READY) {
      console.log("[AuthService] Demo mode profile update")
      const stored = getDemoUser()
      if (stored && stored.id === userId) {
        const updated = { ...stored, ...updates, updated_at: new Date().toISOString() }
        setDemoUser(updated)
        return updated
      }
      throw new Error("User not found")
    }

    try {
      const { data, error } = await supabase
        .from("users")
        .update({
          ...updates,
          updated_at: new Date().toISOString(),
        })
        .eq("id", userId)
        .select()
        .single()

      if (error) {
        console.error("[AuthService] Profile update error:", error)
        throw error
      }

      console.log("[AuthService] Profile updated successfully")
      return data
    } catch (error: any) {
      console.error("[AuthService] updateProfile failed:", error)

      // Fallback for demo mode
      if (error.message?.includes("Failed to fetch")) {
        const stored = getDemoUser()
        if (stored && stored.id === userId) {
          const updated = { ...stored, ...updates, updated_at: new Date().toISOString() }
          setDemoUser(updated)
          return updated
        }
      }
      throw error
    }
  }
}
