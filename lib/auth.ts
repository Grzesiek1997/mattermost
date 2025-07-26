import { supabase } from "./supabase"
import type { User } from "./supabase"

export class AuthService {
  // Debug function to check auth status
  static async debugAuth() {
    try {
      console.log("[AuthService] === DEBUG AUTH START ===")

      // Check Supabase connection
      const { data: connectionTest, error: connectionError } = await supabase
        .from("users")
        .select("count", { count: "exact", head: true })

      console.log("[AuthService] Connection test:", {
        success: !connectionError,
        error: connectionError?.message,
        count: connectionTest,
      })

      // Check current auth session
      const { data: session, error: sessionError } = await supabase.auth.getSession()
      console.log("[AuthService] Current session:", {
        hasSession: !!session.session,
        user: session.session?.user?.email,
        error: sessionError?.message,
      })

      // Check auth user
      const { data: authUser, error: authError } = await supabase.auth.getUser()
      console.log("[AuthService] Auth user:", {
        hasUser: !!authUser.user,
        email: authUser.user?.email,
        error: authError?.message,
      })

      // Test RLS policies
      try {
        const { data: testResult, error: testError } = await supabase.rpc("test_user_creation", {
          test_email: "test@example.com",
          test_username: "testuser",
        })
        console.log("[AuthService] RLS test:", { result: testResult, error: testError })
      } catch (testErr) {
        console.log("[AuthService] RLS test function not available")
      }

      console.log("[AuthService] === DEBUG AUTH END ===")

      return {
        connection: !connectionError,
        session: !!session.session,
        user: !!authUser.user,
      }
    } catch (error) {
      console.error("[AuthService] Debug failed:", error)
      return { error: error.message }
    }
  }

  static async signUp(email: string, password: string, userData: Partial<User>) {
    console.log("[AuthService] === SIGNUP START ===")
    console.log("[AuthService] Email:", email)
    console.log("[AuthService] Has password:", !!password)
    console.log("[AuthService] User data:", userData)

    try {
      // Normalize email
      const normalizedEmail = email.trim().toLowerCase()
      console.log("[AuthService] Normalized email:", normalizedEmail)

      // First, run debug to check system status
      await this.debugAuth()

      // Create auth user first
      console.log("[AuthService] Creating auth user...")
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email: normalizedEmail,
        password,
        options: {
          data: {
            username: userData.username,
            full_name: userData.full_name,
          },
        },
      })

      if (authError) {
        console.error("[AuthService] Auth signup error:", authError)
        throw new Error(`Authentication failed: ${authError.message}`)
      }

      if (!authData.user) {
        throw new Error("No user returned from authentication signup")
      }

      console.log("[AuthService] Auth user created:", {
        id: authData.user.id,
        email: authData.user.email,
        confirmed: authData.user.email_confirmed_at,
      })

      // Wait a moment for auth to settle
      await new Promise((resolve) => setTimeout(resolve, 1000))

      // Try using the secure function first
      console.log("[AuthService] Creating user profile with secure function...")
      try {
        const { data: profileFromFunction, error: functionError } = await supabase.rpc("create_user_profile", {
          user_id: authData.user.id,
          user_email: normalizedEmail,
          user_username: userData.username || normalizedEmail.split("@")[0],
          user_full_name: userData.full_name || "User",
        })

        if (!functionError && profileFromFunction) {
          console.log("[AuthService] Profile created via function:", profileFromFunction)
          console.log("[AuthService] === SIGNUP SUCCESS (FUNCTION) ===")
          return { user: authData.user, profile: profileFromFunction }
        } else {
          console.warn("[AuthService] Function failed, trying direct insert:", functionError)
        }
      } catch (funcError) {
        console.warn("[AuthService] Function not available, trying direct insert:", funcError)
      }

      // Fallback to direct insert
      console.log("[AuthService] Creating user profile with direct insert...")
      const profileData = {
        id: authData.user.id,
        email: normalizedEmail,
        username: userData.username || normalizedEmail.split("@")[0],
        full_name: userData.full_name || "User",
        bio: userData.bio || null,
        avatar_url: userData.avatar_url || null,
        phone: userData.phone || null,
        is_online: true,
        last_seen: new Date().toISOString(),
      }

      console.log("[AuthService] Profile data to insert:", profileData)

      const { data: profile, error: profileError } = await supabase.from("users").insert(profileData).select().single()

      if (profileError) {
        console.error("[AuthService] Profile creation error:", profileError)
        console.error("[AuthService] Profile error details:", {
          code: profileError.code,
          message: profileError.message,
          details: profileError.details,
          hint: profileError.hint,
        })

        // Try to clean up auth user
        try {
          console.log("[AuthService] Cleaning up auth user due to profile error...")
          await supabase.auth.signOut()
        } catch (cleanupError) {
          console.warn("[AuthService] Cleanup failed:", cleanupError)
        }

        // Provide specific error message
        if (profileError.message.includes("row-level security")) {
          throw new Error(
            "Profile creation blocked by security policies. Please contact support or try again in a few moments.",
          )
        } else if (profileError.code === "23505") {
          throw new Error("An account with this email or username already exists.")
        } else {
          throw new Error(`Profile creation failed: ${profileError.message}`)
        }
      }

      console.log("[AuthService] Profile created:", profile)
      console.log("[AuthService] === SIGNUP SUCCESS (DIRECT) ===")

      return { user: authData.user, profile }
    } catch (error: any) {
      console.error("[AuthService] === SIGNUP FAILED ===")
      console.error("[AuthService] Error:", error)
      throw error
    }
  }

  static async signIn(email: string, password: string) {
    console.log("[AuthService] === SIGNIN START ===")
    console.log("[AuthService] Email:", email)
    console.log("[AuthService] Has password:", !!password)

    try {
      // Normalize email
      const normalizedEmail = email.trim().toLowerCase()
      console.log("[AuthService] Normalized email:", normalizedEmail)

      // Run debug first
      await this.debugAuth()

      // Attempt signin
      console.log("[AuthService] Attempting signin...")
      const { data, error } = await supabase.auth.signInWithPassword({
        email: normalizedEmail,
        password,
      })

      if (error) {
        console.error("[AuthService] Signin error:", error)

        // If user doesn't exist, suggest signup
        if (error.message.includes("Invalid login credentials")) {
          // Check if user exists in our users table
          const { data: existingUser } = await supabase
            .from("users")
            .select("email")
            .eq("email", normalizedEmail)
            .single()

          if (!existingUser) {
            throw new Error(`No account found for ${normalizedEmail}. Please sign up first.`)
          } else {
            throw new Error(`Invalid password for ${normalizedEmail}. Please check your password.`)
          }
        }

        throw error
      }

      if (!data.user) {
        throw new Error("No user returned from signin")
      }

      console.log("[AuthService] Auth signin successful:", {
        id: data.user.id,
        email: data.user.email,
      })

      // Get or create user profile
      console.log("[AuthService] Getting user profile...")
      let { data: profile, error: profileError } = await supabase
        .from("users")
        .select("*")
        .eq("id", data.user.id)
        .single()

      if (profileError && profileError.code === "PGRST116") {
        // Profile doesn't exist, create it
        console.log("[AuthService] Creating missing profile...")

        // Try secure function first
        try {
          const { data: profileFromFunction, error: functionError } = await supabase.rpc("create_user_profile", {
            user_id: data.user.id,
            user_email: normalizedEmail,
            user_username: data.user.user_metadata?.username || normalizedEmail.split("@")[0],
            user_full_name: data.user.user_metadata?.full_name || "User",
          })

          if (!functionError && profileFromFunction) {
            profile = profileFromFunction
          } else {
            throw new Error("Function failed")
          }
        } catch (funcError) {
          // Fallback to direct insert
          const { data: newProfile, error: createError } = await supabase
            .from("users")
            .insert({
              id: data.user.id,
              email: normalizedEmail,
              username: data.user.user_metadata?.username || normalizedEmail.split("@")[0],
              full_name: data.user.user_metadata?.full_name || "User",
              is_online: true,
              last_seen: new Date().toISOString(),
            })
            .select()
            .single()

          if (createError) {
            console.error("[AuthService] Failed to create profile:", createError)
            throw new Error(`Failed to create profile: ${createError.message}`)
          }

          profile = newProfile
        }
      } else if (profileError) {
        console.error("[AuthService] Profile fetch error:", profileError)
        throw new Error(`Failed to get profile: ${profileError.message}`)
      }

      // Update online status
      console.log("[AuthService] Updating online status...")
      try {
        await supabase
          .from("users")
          .update({
            is_online: true,
            last_seen: new Date().toISOString(),
          })
          .eq("id", data.user.id)
      } catch (updateError) {
        console.warn("[AuthService] Online status update failed:", updateError)
      }

      console.log("[AuthService] === SIGNIN SUCCESS ===")
      return { user: data.user, profile }
    } catch (error: any) {
      console.error("[AuthService] === SIGNIN FAILED ===")
      console.error("[AuthService] Error:", error)
      throw error
    }
  }

  static async signOut() {
    console.log("[AuthService] === SIGNOUT START ===")

    try {
      // Get current user before signing out
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (user) {
        console.log("[AuthService] Updating offline status for:", user.email)
        try {
          await supabase
            .from("users")
            .update({
              is_online: false,
              last_seen: new Date().toISOString(),
            })
            .eq("id", user.id)
        } catch (updateError) {
          console.warn("[AuthService] Offline status update failed:", updateError)
        }
      }

      // Sign out
      const { error } = await supabase.auth.signOut()
      if (error) {
        console.error("[AuthService] Signout error:", error)
        throw error
      }

      console.log("[AuthService] === SIGNOUT SUCCESS ===")
    } catch (error) {
      console.error("[AuthService] === SIGNOUT FAILED ===")
      console.error("[AuthService] Error:", error)
      throw error
    }
  }

  static async getCurrentUser(): Promise<User | null> {
    console.log("[AuthService] === GET CURRENT USER START ===")

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
        console.error("[AuthService] Profile fetch error:", profileError)
        return null
      }

      console.log("[AuthService] === GET CURRENT USER SUCCESS ===")
      return profile
    } catch (error) {
      console.error("[AuthService] === GET CURRENT USER FAILED ===")
      console.error("[AuthService] Error:", error)
      return null
    }
  }

  static async updateProfile(userId: string, updates: Partial<User>) {
    console.log("[AuthService] Updating profile for:", userId)

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
      console.error("[AuthService] Profile update failed:", error)
      throw error
    }
  }

  // Admin functions
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

  // Create first super admin (only works if no admins exist)
  static async createFirstSuperAdmin(): Promise<string> {
    try {
      const { data, error } = await supabase.rpc("create_first_super_admin")

      if (error) {
        console.error("[AuthService] Create first super admin error:", error)
        throw error
      }

      return data
    } catch (error: any) {
      console.error("[AuthService] Create first super admin failed:", error)
      throw error
    }
  }

  // Promote user to admin (only super admins can do this)
  static async promoteUserToAdmin(email: string, role = "admin"): Promise<string> {
    try {
      const { data, error } = await supabase.rpc("promote_user_to_admin", {
        target_email: email,
        admin_role: role,
      })

      if (error) {
        console.error("[AuthService] Promote user error:", error)
        throw error
      }

      return data
    } catch (error: any) {
      console.error("[AuthService] Promote user failed:", error)
      throw error
    }
  }
}
