import { supabase } from "./supabase"
import type { User } from "./supabase"

export class AuthService {
  // Rate limiting tracking
  private static lastSignupAttempt = 0
  private static signupCooldown = 25000 // 25 seconds in milliseconds

  // Debug function to check auth status
  static async debugAuth() {
    try {
      console.log("[AuthService] === DEBUG AUTH START ===")

      // Check Supabase connection (this doesn't require auth)
      const { data: connectionTest, error: connectionError } = await supabase
        .from("profiles")
        .select("count", { count: "exact", head: true })

      console.log("[AuthService] Connection test:", {
        success: !connectionError,
        error: connectionError?.message,
        count: connectionTest,
      })

      // Check current auth session (safe - doesn't throw if no session)
      const { data: session, error: sessionError } = await supabase.auth.getSession()
      console.log("[AuthService] Current session:", {
        hasSession: !!session.session,
        user: session.session?.user?.email,
        confirmed: session.session?.user?.email_confirmed_at,
        error: sessionError?.message,
      })

      // Check auth user (safe - doesn't throw if no user)
      const { data: authUser, error: authError } = await supabase.auth.getUser()
      console.log("[AuthService] Auth user:", {
        hasUser: !!authUser.user,
        email: authUser.user?.email,
        confirmed: authUser.user?.email_confirmed_at,
        error: authError?.message,
      })

      // Test RLS policies (only if we have a user)
      let rlsTest = null
      if (authUser.user) {
        try {
          const { data: testResult, error: testError } = await supabase.rpc("test_user_creation", {
            test_email: "test@example.com",
            test_username: "testuser",
          })
          rlsTest = { result: testResult, error: testError }
        } catch (testErr) {
          rlsTest = { error: "Function not available" }
        }
      } else {
        rlsTest = { error: "No authenticated user for RLS test" }
      }

      console.log("[AuthService] RLS test:", rlsTest)

      // Check rate limiting status
      const now = Date.now()
      const timeSinceLastSignup = now - this.lastSignupAttempt
      const canSignup = timeSinceLastSignup >= this.signupCooldown

      console.log("[AuthService] Rate limiting:", {
        lastAttempt: new Date(this.lastSignupAttempt).toISOString(),
        timeSince: Math.round(timeSinceLastSignup / 1000),
        cooldownSeconds: this.signupCooldown / 1000,
        canSignup,
      })

      console.log("[AuthService] === DEBUG AUTH END ===")

      return {
        connection: !connectionError,
        session: !!session.session,
        user: !!authUser.user,
        userEmail: authUser.user?.email || null,
        emailConfirmed: !!authUser.user?.email_confirmed_at,
        rateLimiting: {
          canSignup,
          cooldownRemaining: canSignup ? 0 : Math.ceil((this.signupCooldown - timeSinceLastSignup) / 1000),
        },
        rlsTest,
        errors: {
          connection: connectionError?.message,
          session: sessionError?.message,
          auth: authError?.message,
        },
      }
    } catch (error) {
      console.error("[AuthService] Debug failed:", error)
      return {
        error: error.message,
        connection: false,
        session: false,
        user: false,
        emailConfirmed: false,
        rateLimiting: { canSignup: false, cooldownRemaining: 0 },
      }
    }
  }

  static async signUp(email: string, password: string, userData: Partial<User>) {
    console.log("[AuthService] === SIGNUP START ===")
    console.log("[AuthService] Email:", email)
    console.log("[AuthService] Has password:", !!password)
    console.log("[AuthService] User data:", userData)

    try {
      // Check rate limiting
      const now = Date.now()
      const timeSinceLastSignup = now - this.lastSignupAttempt
      const cooldownRemaining = this.signupCooldown - timeSinceLastSignup

      if (timeSinceLastSignup < this.signupCooldown) {
        const waitSeconds = Math.ceil(cooldownRemaining / 1000)
        console.log("[AuthService] Rate limited, need to wait:", waitSeconds, "seconds")
        throw new Error(
          `Please wait ${waitSeconds} seconds before creating another account. This is a security measure to prevent spam.`,
        )
      }

      // Update last attempt time
      this.lastSignupAttempt = now

      // Normalize email
      const normalizedEmail = email.trim().toLowerCase()
      console.log("[AuthService] Normalized email:", normalizedEmail)

      // First, run debug to check system status
      await this.debugAuth()

      // Create auth user first - disable email confirmation for development
      console.log("[AuthService] Creating auth user...")
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email: normalizedEmail,
        password,
        options: {
          data: {
            username: userData.username,
            full_name: userData.full_name,
          },
          // For development - skip email confirmation
          emailRedirectTo: undefined,
        },
      })

      if (authError) {
        console.error("[AuthService] Auth signup error:", authError)

        // Handle specific signup errors
        if (authError.message.includes("For security purposes, you can only request this after")) {
          // Extract wait time from error message if possible
          const match = authError.message.match(/after (\d+) seconds/)
          const waitTime = match ? Number.parseInt(match[1]) : 25
          throw new Error(
            `Please wait ${waitTime} seconds before creating another account. This prevents spam and protects our service.`,
          )
        } else if (authError.message.includes("User already registered")) {
          throw new Error(`An account with ${normalizedEmail} already exists. Please sign in instead.`)
        } else if (authError.message.includes("Password should be at least")) {
          throw new Error("Password must be at least 6 characters long.")
        } else if (authError.message.includes("Invalid email")) {
          throw new Error("Please enter a valid email address.")
        } else if (authError.message.includes("Signup is disabled")) {
          throw new Error("Account creation is currently disabled. Please contact support.")
        }

        throw new Error(`Account creation failed: ${authError.message}`)
      }

      if (!authData.user) {
        throw new Error("No user returned from authentication signup")
      }

      console.log("[AuthService] Auth user created:", {
        id: authData.user.id,
        email: authData.user.email,
        confirmed: authData.user.email_confirmed_at,
        needsConfirmation: !authData.user.email_confirmed_at && !authData.session,
      })

      // Check if email confirmation is required
      if (!authData.user.email_confirmed_at && !authData.session) {
        console.log("[AuthService] Email confirmation required")
        return {
          user: authData.user,
          profile: null,
          needsEmailConfirmation: true,
          message: `Please check your email (${normalizedEmail}) and click the confirmation link to complete your account setup.`,
        }
      }

      // If we have a session, the user is automatically confirmed (development mode)
      if (authData.session) {
        console.log("[AuthService] User automatically confirmed (development mode)")
      }

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
          return { user: authData.user, profile: profileFromFunction, needsEmailConfirmation: false }
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

      const { data: profile, error: profileError } = await supabase
        .from("profiles")
        .insert(profileData)
        .select()
        .single()

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

      return { user: authData.user, profile, needsEmailConfirmation: false }
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

        // Handle specific signin errors
        if (error.message.includes("Email not confirmed")) {
          // Try to resend confirmation email
          console.log("[AuthService] Attempting to resend confirmation email...")
          try {
            await supabase.auth.resend({
              type: "signup",
              email: normalizedEmail,
            })
            throw new Error(
              `Please check your email (${normalizedEmail}) and click the confirmation link. We've sent you a new confirmation email.`,
            )
          } catch (resendError) {
            throw new Error(
              `Please check your email (${normalizedEmail}) and click the confirmation link to activate your account.`,
            )
          }
        } else if (error.message.includes("Invalid login credentials")) {
          // Check if user exists in our profiles table (this doesn't require auth)
          const { data: existingUser } = await supabase
            .from("profiles")
            .select("email")
            .eq("email", normalizedEmail)
            .single()

          if (!existingUser) {
            throw new Error(`No account found for ${normalizedEmail}. Please sign up first.`)
          } else {
            throw new Error(`Invalid password for ${normalizedEmail}. Please check your password and try again.`)
          }
        } else if (error.message.includes("Too many requests")) {
          throw new Error("Too many login attempts. Please wait a moment and try again.")
        }

        throw new Error(`Sign in failed: ${error.message}`)
      }

      if (!data.user) {
        throw new Error("No user returned from signin")
      }

      console.log("[AuthService] Auth signin successful:", {
        id: data.user.id,
        email: data.user.email,
        confirmed: data.user.email_confirmed_at,
      })

      // Get or create user profile
      console.log("[AuthService] Getting user profile...")
      let { data: profile, error: profileError } = await supabase
        .from("profiles")
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
            .from("profiles")
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
          .from("profiles")
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
      // Get current user before signing out (safe - doesn't throw)
      const {
        data: { user },
        error: getUserError,
      } = await supabase.auth.getUser()

      if (getUserError) {
        console.warn("[AuthService] Error getting user for signout:", getUserError)
      }

      if (user) {
        console.log("[AuthService] Updating offline status for:", user.email)
        try {
          await supabase
            .from("profiles")
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
      // Get authenticated user (safe - doesn't throw)
      const {
        data: { user: authUser },
        error: authError,
      } = await supabase.auth.getUser()

      if (authError) {
        console.error("[AuthService] Auth error:", authError)
        // Don't throw here - just return null for unauthenticated state
        return null
      }

      if (!authUser) {
        console.log("[AuthService] No authenticated user")
        return null
      }

      console.log("[AuthService] Auth user found:", authUser.email)

      // Get user profile
      const { data: profile, error: profileError } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", authUser.id)
        .single()

      if (profileError) {
        console.error("[AuthService] Profile fetch error:", profileError)
        // If profile doesn't exist, return null instead of throwing
        return null
      }

      console.log("[AuthService] === GET CURRENT USER SUCCESS ===")
      return profile
    } catch (error) {
      console.error("[AuthService] === GET CURRENT USER FAILED ===")
      console.error("[AuthService] Error:", error)
      // Return null instead of throwing to handle gracefully
      return null
    }
  }

  static async updateProfile(userId: string, updates: Partial<User>) {
    console.log("[AuthService] Updating profile for:", userId)

    try {
      const { data, error } = await supabase
        .from("profiles")
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

  // Admin functions - these handle missing auth gracefully
  static async isAdmin(userId?: string): Promise<boolean> {
    try {
      // If no userId provided, get current user
      if (!userId) {
        const {
          data: { user },
          error: authError,
        } = await supabase.auth.getUser()

        if (authError || !user) {
          console.log("[AuthService] No authenticated user for admin check")
          return false
        }
        userId = user.id
      }

      const { data, error } = await supabase.rpc("is_admin", {
        user_uuid: userId,
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
      // If no userId provided, get current user
      if (!userId) {
        const {
          data: { user },
          error: authError,
        } = await supabase.auth.getUser()

        if (authError || !user) {
          console.log("[AuthService] No authenticated user for admin role check")
          return "user"
        }
        userId = user.id
      }

      const { data, error } = await supabase.rpc("get_admin_role", {
        user_uuid: userId,
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

  // Check if user is authenticated (safe method)
  static async isAuthenticated(): Promise<boolean> {
    try {
      const {
        data: { user },
        error,
      } = await supabase.auth.getUser()

      return !error && !!user
    } catch (error) {
      console.error("[AuthService] Authentication check failed:", error)
      return false
    }
  }

  // Get auth session safely
  static async getSession() {
    try {
      const { data, error } = await supabase.auth.getSession()
      return { session: data.session, error }
    } catch (error) {
      console.error("[AuthService] Get session failed:", error)
      return { session: null, error }
    }
  }

  // Resend confirmation email
  static async resendConfirmation(email: string): Promise<void> {
    try {
      console.log("[AuthService] Resending confirmation email to:", email)

      const { error } = await supabase.auth.resend({
        type: "signup",
        email: email.trim().toLowerCase(),
      })

      if (error) {
        console.error("[AuthService] Resend confirmation error:", error)
        throw new Error(`Failed to resend confirmation email: ${error.message}`)
      }

      console.log("[AuthService] Confirmation email sent successfully")
    } catch (error: any) {
      console.error("[AuthService] Resend confirmation failed:", error)
      throw error
    }
  }

  // Get rate limiting info
  static getRateLimitInfo() {
    const now = Date.now()
    const timeSinceLastSignup = now - this.lastSignupAttempt
    const canSignup = timeSinceLastSignup >= this.signupCooldown
    const cooldownRemaining = canSignup ? 0 : Math.ceil((this.signupCooldown - timeSinceLastSignup) / 1000)

    return {
      canSignup,
      cooldownRemaining,
      lastAttempt: this.lastSignupAttempt,
    }
  }

  // Reset rate limiting (for testing)
  static resetRateLimit() {
    this.lastSignupAttempt = 0
    console.log("[AuthService] Rate limit reset")
  }
}
