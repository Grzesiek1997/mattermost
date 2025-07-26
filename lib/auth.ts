import { supabase } from "./supabase"
import type { User } from "./supabase"

export class AuthService {
  static async signUp(email: string, password: string, userData: Partial<User>) {
    console.log("[AuthService] signUp called with:", { email, hasPassword: !!password })

    try {
      console.log("[AuthService] Attempting Supabase signup...")

      // Create auth user
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            username: userData.username,
            full_name: userData.full_name,
          },
        },
      })

      if (authError) {
        console.error("[AuthService] Supabase signup error:", authError)
        throw authError
      }

      if (!authData.user) {
        throw new Error("No user returned from signup")
      }

      console.log("[AuthService] Auth user created:", authData.user.id)

      // Create user profile
      const { error: profileError } = await supabase.from("users").insert({
        id: authData.user.id,
        email: authData.user.email!,
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
        // Try to clean up auth user if profile creation fails
        await supabase.auth.signOut()
        throw profileError
      }

      console.log("[AuthService] ✅ Signup successful for:", email)
      return authData
    } catch (error: any) {
      console.error("[AuthService] Signup failed:", error)
      throw error
    }
  }

  static async signIn(email: string, password: string) {
    console.log("[AuthService] signIn called with:", { email, hasPassword: !!password })

    try {
      console.log("[AuthService] Attempting Supabase signin...")

      const { data, error } = await supabase.auth.signInWithPassword({
        email: email.trim().toLowerCase(),
        password,
      })

      if (error) {
        console.error("[AuthService] Supabase signin error:", error)
        throw error
      }

      if (!data.user) {
        throw new Error("No user returned from signin")
      }

      console.log("[AuthService] Auth successful for:", data.user.email)

      // Update online status
      try {
        const { error: updateError } = await supabase
          .from("users")
          .update({
            is_online: true,
            last_seen: new Date().toISOString(),
          })
          .eq("id", data.user.id)

        if (updateError) {
          console.warn("[AuthService] Failed to update online status:", updateError)
        }
      } catch (updateError) {
        console.warn("[AuthService] Online status update failed:", updateError)
      }

      console.log("[AuthService] ✅ Signin successful")
      return data
    } catch (error: any) {
      console.error("[AuthService] Signin failed:", error)
      throw error
    }
  }

  static async signOut() {
    console.log("[AuthService] signOut called")

    try {
      // Get current user before signing out
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (user) {
        try {
          // Update offline status
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

      // Sign out from Supabase
      const { error } = await supabase.auth.signOut()
      if (error) {
        console.error("[AuthService] Signout error:", error)
        throw error
      }

      console.log("[AuthService] ✅ Signout successful")
    } catch (error) {
      console.error("[AuthService] Signout error:", error)
      throw error
    }
  }

  static async getCurrentUser(): Promise<User | null> {
    console.log("[AuthService] getCurrentUser called")

    try {
      // Get authenticated user
      const {
        data: { user: authUser },
        error: authError,
      } = await supabase.auth.getUser()

      if (authError) {
        console.error("[AuthService] Auth error:", authError)
        return null
      }

      if (!authUser) {
        console.log("[AuthService] No authenticated user")
        return null
      }

      console.log("[AuthService] Auth user found:", authUser.email)

      // Get user profile
      const { data: profile, error: profileError } = await supabase
        .from("users")
        .select("*")
        .eq("id", authUser.id)
        .single()

      if (profileError) {
        console.error("[AuthService] Error fetching user profile:", profileError)

        // If profile doesn't exist, create it
        if (profileError.code === "PGRST116") {
          console.log("[AuthService] Creating missing profile for:", authUser.email)

          const { data: newProfile, error: createError } = await supabase
            .from("users")
            .insert({
              id: authUser.id,
              email: authUser.email!,
              username: authUser.user_metadata?.username || authUser.email!.split("@")[0],
              full_name: authUser.user_metadata?.full_name || "User",
              is_online: true,
              last_seen: new Date().toISOString(),
            })
            .select()
            .single()

          if (createError) {
            console.error("[AuthService] Failed to create profile:", createError)
            return null
          }

          return newProfile
        }

        return null
      }

      console.log("[AuthService] ✅ User profile fetched successfully")
      return profile
    } catch (error) {
      console.error("[AuthService] getCurrentUser error:", error)
      return null
    }
  }

  static async updateProfile(userId: string, updates: Partial<User>) {
    console.log("[AuthService] updateProfile called for:", userId)

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

      console.log("[AuthService] ✅ Profile updated successfully")
      return data
    } catch (error: any) {
      console.error("[AuthService] updateProfile failed:", error)
      throw error
    }
  }

  // Check if user is admin
  static async isAdmin(userId?: string): Promise<boolean> {
    try {
      const { data, error } = await supabase.rpc("is_admin", {
        user_uuid: userId || undefined,
      })

      if (error) {
        console.error("[AuthService] Admin check error:", error)
        return false
      }

      return data || false
    } catch (error) {
      console.error("[AuthService] Admin check failed:", error)
      return false
    }
  }

  // Get admin role
  static async getAdminRole(userId?: string): Promise<string> {
    try {
      const { data, error } = await supabase.rpc("get_admin_role", {
        user_uuid: userId || undefined,
      })

      if (error) {
        console.error("[AuthService] Admin role check error:", error)
        return "user"
      }

      return data || "user"
    } catch (error) {
      console.error("[AuthService] Admin role check failed:", error)
      return "user"
    }
  }
}
