"use client"

import type React from "react"
import { useState, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Label } from "@/components/ui/label"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { AuthService } from "@/lib/auth"
import { SUPABASE_READY } from "@/lib/supabase"
import { toast } from "@/hooks/use-toast"
import { AlertTriangle, Mail, RefreshCw, Clock, RotateCcw } from "lucide-react"

interface AuthFormProps {
  onAuthSuccess: () => void
}

export function AuthForm({ onAuthSuccess }: AuthFormProps) {
  const [isLoading, setIsLoading] = useState(false)
  const [signInData, setSignInData] = useState({ email: "", password: "" })
  const [signUpData, setSignUpData] = useState({
    email: "",
    password: "",
    username: "",
    fullName: "",
  })
  const [emailConfirmationNeeded, setEmailConfirmationNeeded] = useState<string | null>(null)
  const [rateLimitInfo, setRateLimitInfo] = useState({ canSignup: true, cooldownRemaining: 0 })

  // Update rate limit info every second
  useEffect(() => {
    const updateRateLimit = () => {
      const info = AuthService.getRateLimitInfo()
      setRateLimitInfo(info)
    }

    updateRateLimit()
    const interval = setInterval(updateRateLimit, 1000)

    return () => clearInterval(interval)
  }, [])

  const handleResendConfirmation = async (email: string) => {
    setIsLoading(true)
    try {
      await AuthService.resendConfirmation(email)
      toast({
        title: "Confirmation email sent!",
        description: `Please check your email (${email}) for the confirmation link.`,
      })
    } catch (error: any) {
      toast({
        title: "Failed to resend email",
        description: error.message,
        variant: "destructive",
      })
    } finally {
      setIsLoading(false)
    }
  }

  const handleResetRateLimit = () => {
    AuthService.resetRateLimit()
    setRateLimitInfo({ canSignup: true, cooldownRemaining: 0 })
    toast({
      title: "Rate limit reset",
      description: "You can now create accounts immediately (for testing)",
    })
  }

  const handleSignIn = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!signInData.email.trim() || !signInData.password.trim()) {
      toast({
        title: "Validation Error",
        description: "Please enter both email and password",
        variant: "destructive",
      })
      return
    }

    setIsLoading(true)
    setEmailConfirmationNeeded(null)

    try {
      console.log("[AuthForm] Attempting signin...")
      await AuthService.signIn(signInData.email, signInData.password)

      toast({
        title: "Welcome back!",
        description: `Signed in as ${signInData.email}`,
      })
      onAuthSuccess()
    } catch (error: any) {
      console.error("[AuthForm] Signin error:", error)

      let errorMessage = error.message || "An unexpected error occurred"

      // Handle email confirmation needed
      if (errorMessage.includes("confirmation link")) {
        setEmailConfirmationNeeded(signInData.email)
        toast({
          title: "Email confirmation required",
          description: errorMessage,
          variant: "destructive",
        })
      } else {
        // Provide helpful error messages for other cases
        if (errorMessage.includes("Invalid login credentials")) {
          errorMessage = "Invalid email or password. Please check your credentials and try again."
        } else if (errorMessage.includes("Too many requests")) {
          errorMessage = "Too many login attempts. Please wait a moment and try again."
        }

        toast({
          title: "Sign in failed",
          description: errorMessage,
          variant: "destructive",
        })
      }
    } finally {
      setIsLoading(false)
    }
  }

  const handleSignUp = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!signUpData.email.trim() || !signUpData.password.trim() || !signUpData.username.trim()) {
      toast({
        title: "Validation Error",
        description: "Please fill in all required fields (email, username, password)",
        variant: "destructive",
      })
      return
    }

    if (signUpData.password.length < 6) {
      toast({
        title: "Validation Error",
        description: "Password must be at least 6 characters long",
        variant: "destructive",
      })
      return
    }

    // Basic username validation
    if (!/^[a-zA-Z0-9_]+$/.test(signUpData.username)) {
      toast({
        title: "Validation Error",
        description: "Username can only contain letters, numbers, and underscores",
        variant: "destructive",
      })
      return
    }

    // Check rate limiting
    if (!rateLimitInfo.canSignup) {
      toast({
        title: "Please wait",
        description: `You can create another account in ${rateLimitInfo.cooldownRemaining} seconds. This prevents spam.`,
        variant: "destructive",
      })
      return
    }

    setIsLoading(true)
    setEmailConfirmationNeeded(null)

    try {
      console.log("[AuthForm] Attempting signup...")
      const result = await AuthService.signUp(signUpData.email, signUpData.password, {
        username: signUpData.username,
        full_name: signUpData.fullName || signUpData.username,
      })

      if (result.needsEmailConfirmation) {
        setEmailConfirmationNeeded(signUpData.email)
        toast({
          title: "Check your email!",
          description: result.message,
        })
      } else {
        toast({
          title: "Account created!",
          description: `Welcome ${signUpData.fullName || signUpData.username}! You are now signed in.`,
        })
        onAuthSuccess()
      }
    } catch (error: any) {
      console.error("[AuthForm] Signup error:", error)

      let errorMessage = error.message || "An unexpected error occurred"

      // Handle rate limiting specifically
      if (errorMessage.includes("wait") && errorMessage.includes("seconds")) {
        // Error already has good message about waiting
      } else if (errorMessage.includes("User already registered")) {
        errorMessage = "An account with this email already exists. Please sign in instead."
      } else if (errorMessage.includes("Password should be at least 6 characters")) {
        errorMessage = "Password must be at least 6 characters long."
      } else if (errorMessage.includes("row-level security")) {
        errorMessage = "Account creation temporarily blocked. Please try again in a moment or contact support."
      } else if (errorMessage.includes("Invalid email")) {
        errorMessage = "Please enter a valid email address."
      } else if (errorMessage.includes("Signup is disabled")) {
        errorMessage = "Account creation is currently disabled. Please contact support."
      }

      toast({
        title: "Sign up failed",
        description: errorMessage,
        variant: "destructive",
      })
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className="flex items-center justify-center min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl font-bold">Telegram Clone</CardTitle>
          <CardDescription>Connect with friends and family instantly</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {!SUPABASE_READY && (
            <Alert>
              <AlertTriangle className="h-4 w-4" />
              <AlertDescription>
                <strong>Warning:</strong> Supabase connection not configured. Some features may not work.
              </AlertDescription>
            </Alert>
          )}

          {!rateLimitInfo.canSignup && (
            <Alert>
              <Clock className="h-4 w-4" />
              <AlertDescription>
                <div className="space-y-2">
                  <p>
                    <strong>Rate limit active</strong>
                  </p>
                  <p className="text-sm">
                    Please wait {rateLimitInfo.cooldownRemaining} seconds before creating another account. This prevents
                    spam and protects our service.
                  </p>
                  <Button variant="outline" size="sm" onClick={handleResetRateLimit} className="w-full bg-transparent">
                    <RotateCcw className="h-4 w-4 mr-2" />
                    Reset rate limit (for testing)
                  </Button>
                </div>
              </AlertDescription>
            </Alert>
          )}

          {emailConfirmationNeeded && (
            <Alert>
              <Mail className="h-4 w-4" />
              <AlertDescription>
                <div className="space-y-2">
                  <p>
                    <strong>Email confirmation required</strong>
                  </p>
                  <p className="text-sm">
                    Please check your email ({emailConfirmationNeeded}) and click the confirmation link.
                  </p>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handleResendConfirmation(emailConfirmationNeeded)}
                    disabled={isLoading}
                    className="w-full"
                  >
                    <RefreshCw className="h-4 w-4 mr-2" />
                    Resend confirmation email
                  </Button>
                </div>
              </AlertDescription>
            </Alert>
          )}

          <Tabs defaultValue="signin" className="w-full">
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="signin">Sign In</TabsTrigger>
              <TabsTrigger value="signup">Sign Up</TabsTrigger>
            </TabsList>

            <TabsContent value="signin">
              <form onSubmit={handleSignIn} className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="signin-email">Email</Label>
                  <Input
                    id="signin-email"
                    type="email"
                    placeholder="Enter your email"
                    value={signInData.email}
                    onChange={(e) => setSignInData((prev) => ({ ...prev, email: e.target.value }))}
                    required
                    disabled={isLoading}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="signin-password">Password</Label>
                  <Input
                    id="signin-password"
                    type="password"
                    placeholder="Enter your password"
                    value={signInData.password}
                    onChange={(e) => setSignInData((prev) => ({ ...prev, password: e.target.value }))}
                    required
                    disabled={isLoading}
                  />
                </div>
                <Button type="submit" className="w-full" disabled={isLoading}>
                  {isLoading ? "Signing in..." : "Sign In"}
                </Button>
              </form>
            </TabsContent>

            <TabsContent value="signup">
              <form onSubmit={handleSignUp} className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="signup-email">Email *</Label>
                  <Input
                    id="signup-email"
                    type="email"
                    placeholder="Enter your email"
                    value={signUpData.email}
                    onChange={(e) => setSignUpData((prev) => ({ ...prev, email: e.target.value }))}
                    required
                    disabled={isLoading}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="signup-username">Username *</Label>
                  <Input
                    id="signup-username"
                    type="text"
                    placeholder="Choose a username (letters, numbers, _)"
                    value={signUpData.username}
                    onChange={(e) => setSignUpData((prev) => ({ ...prev, username: e.target.value }))}
                    required
                    disabled={isLoading}
                    pattern="[a-zA-Z0-9_]+"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="signup-fullname">Full Name</Label>
                  <Input
                    id="signup-fullname"
                    type="text"
                    placeholder="Enter your full name (optional)"
                    value={signUpData.fullName}
                    onChange={(e) => setSignUpData((prev) => ({ ...prev, fullName: e.target.value }))}
                    disabled={isLoading}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="signup-password">Password *</Label>
                  <Input
                    id="signup-password"
                    type="password"
                    placeholder="Create a password (min 6 characters)"
                    value={signUpData.password}
                    onChange={(e) => setSignUpData((prev) => ({ ...prev, password: e.target.value }))}
                    required
                    disabled={isLoading}
                    minLength={6}
                  />
                </div>
                <Button
                  type="submit"
                  className="w-full"
                  disabled={isLoading || !rateLimitInfo.canSignup}
                  title={
                    !rateLimitInfo.canSignup
                      ? `Please wait ${rateLimitInfo.cooldownRemaining} seconds`
                      : "Create your account"
                  }
                >
                  {isLoading
                    ? "Creating account..."
                    : !rateLimitInfo.canSignup
                      ? `Wait ${rateLimitInfo.cooldownRemaining}s`
                      : "Sign Up"}
                </Button>
              </form>
            </TabsContent>
          </Tabs>
        </CardContent>
      </Card>
    </div>
  )
}
