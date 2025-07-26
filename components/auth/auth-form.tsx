"use client"

import type React from "react"
import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Label } from "@/components/ui/label"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { AuthService } from "@/lib/auth"
import { SUPABASE_READY } from "@/lib/supabase"
import { toast } from "@/hooks/use-toast"
import { Info, AlertTriangle, TestTube, CheckCircle, XCircle } from "lucide-react"

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
  const [debugMode, setDebugMode] = useState(false)
  const [debugInfo, setDebugInfo] = useState<any>(null)

  const runDebug = async () => {
    try {
      setDebugMode(true)
      setIsLoading(true)
      console.log("Running comprehensive debug...")

      const info = await AuthService.debugAuth()
      setDebugInfo(info)

      toast({
        title: "Debug Complete",
        description: "Check console and debug info below for details",
      })
    } catch (error) {
      console.error("Debug failed:", error)
      toast({
        title: "Debug Failed",
        description: error.message,
        variant: "destructive",
      })
    } finally {
      setIsLoading(false)
    }
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

      // Provide helpful error messages
      if (errorMessage.includes("Invalid login credentials")) {
        errorMessage = "Invalid email or password. Please check your credentials and try again."
      } else if (errorMessage.includes("Email not confirmed")) {
        errorMessage = "Please check your email and click the confirmation link before signing in."
      }

      toast({
        title: "Sign in failed",
        description: errorMessage,
        variant: "destructive",
      })
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

    setIsLoading(true)

    try {
      console.log("[AuthForm] Attempting signup...")
      await AuthService.signUp(signUpData.email, signUpData.password, {
        username: signUpData.username,
        full_name: signUpData.fullName || signUpData.username,
      })

      toast({
        title: "Account created!",
        description: `Welcome ${signUpData.fullName || signUpData.username}! You are now signed in.`,
      })
      onAuthSuccess()
    } catch (error: any) {
      console.error("[AuthForm] Signup error:", error)

      let errorMessage = error.message || "An unexpected error occurred"

      // Provide helpful error messages
      if (errorMessage.includes("User already registered")) {
        errorMessage = "An account with this email already exists. Please sign in instead."
      } else if (errorMessage.includes("Password should be at least 6 characters")) {
        errorMessage = "Password must be at least 6 characters long."
      } else if (errorMessage.includes("row-level security")) {
        errorMessage = "Account creation temporarily blocked. Please try again in a moment or contact support."
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

  const handleTestAccount = async () => {
    setIsLoading(true)

    try {
      // Try to sign up with a test account
      const timestamp = Date.now()
      const testEmail = `test${timestamp}@example.com`
      const testPassword = "test123456"
      const testUsername = `testuser${timestamp}`

      console.log("[AuthForm] Creating test account:", { testEmail, testUsername })

      await AuthService.signUp(testEmail, testPassword, {
        username: testUsername,
        full_name: "Test User",
      })

      toast({
        title: "Test account created!",
        description: `Created and signed in as ${testEmail}`,
      })
      onAuthSuccess()
    } catch (error: any) {
      console.error("[AuthForm] Test account error:", error)
      toast({
        title: "Test account failed",
        description: error.message,
        variant: "destructive",
      })
    } finally {
      setIsLoading(false)
    }
  }

  const getDebugStatusIcon = (status: boolean | undefined) => {
    if (status === true) return <CheckCircle className="h-4 w-4 text-green-500" />
    if (status === false) return <XCircle className="h-4 w-4 text-red-500" />
    return <AlertTriangle className="h-4 w-4 text-yellow-500" />
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
                <Button type="submit" className="w-full" disabled={isLoading}>
                  {isLoading ? "Creating account..." : "Sign Up"}
                </Button>
              </form>
            </TabsContent>
          </Tabs>

          <div className="space-y-2">
            <div className="relative">
              <div className="absolute inset-0 flex items-center">
                <span className="w-full border-t" />
              </div>
              <div className="relative flex justify-center text-xs uppercase">
                <span className="bg-white px-2 text-muted-foreground">Quick Actions</span>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-2">
              <Button type="button" variant="outline" size="sm" onClick={handleTestAccount} disabled={isLoading}>
                Create Test Account
              </Button>
              <Button type="button" variant="outline" size="sm" onClick={runDebug} disabled={isLoading}>
                <TestTube className="h-4 w-4 mr-1" />
                Debug System
              </Button>
            </div>
          </div>

          {debugMode && debugInfo && (
            <Alert>
              <Info className="h-4 w-4" />
              <AlertDescription>
                <div className="space-y-2">
                  <strong>System Status:</strong>
                  <div className="grid grid-cols-2 gap-2 text-xs">
                    <div className="flex items-center gap-1">
                      {getDebugStatusIcon(debugInfo.connection)}
                      <span>Database</span>
                    </div>
                    <div className="flex items-center gap-1">
                      {getDebugStatusIcon(debugInfo.session)}
                      <span>Session</span>
                    </div>
                    <div className="flex items-center gap-1">
                      {getDebugStatusIcon(debugInfo.user)}
                      <span>Auth User</span>
                    </div>
                    <div className="flex items-center gap-1">
                      {getDebugStatusIcon(SUPABASE_READY)}
                      <span>Supabase</span>
                    </div>
                  </div>
                  <details className="mt-2">
                    <summary className="text-xs cursor-pointer">Show detailed debug info</summary>
                    <pre className="text-xs mt-2 bg-gray-100 p-2 rounded overflow-auto max-h-32">
                      {JSON.stringify(debugInfo, null, 2)}
                    </pre>
                  </details>
                </div>
              </AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
