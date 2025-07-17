"use client"

import { useEffect, useState } from "react"
import { supabase, SUPABASE_READY } from "@/lib/supabase"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { CheckCircle, XCircle, Loader2, UserIcon } from "lucide-react"

export function SupabaseConnectionTester() {
  const [connectionStatus, setConnectionStatus] = useState<"checking" | "connected" | "failed">("checking")
  const [userStatus, setUserStatus] = useState<"checking" | "authenticated" | "unauthenticated" | "error">("checking")
  const [currentUserEmail, setCurrentUserEmail] = useState<string | null>(null)
  const [connectionError, setConnectionError] = useState<string | null>(null)

  useEffect(() => {
    const testConnection = async () => {
      try {
        // Test database connection
        const { count, error: dbError } = await supabase.from("users").select("count", { count: "exact", head: true })

        if (dbError) {
          setConnectionStatus("failed")
          setConnectionError(dbError.message)
          console.error("[SupabaseConnectionTester] Database connection test failed:", dbError)
        } else {
          setConnectionStatus("connected")
          console.log("[SupabaseConnectionTester] Database connection test successful. User count:", count)
        }

        // Test user authentication status
        const {
          data: { user },
          error: authError,
        } = await supabase.auth.getUser()

        if (authError) {
          setUserStatus("error")
          console.error("[SupabaseConnectionTester] Auth status check failed:", authError)
        } else if (user) {
          setUserStatus("authenticated")
          setCurrentUserEmail(user.email)
          console.log("[SupabaseConnectionTester] User authenticated:", user.email)
        } else {
          setUserStatus("unauthenticated")
          console.log("[SupabaseConnectionTester] User unauthenticated.")
        }
      } catch (err: any) {
        setConnectionStatus("failed")
        setConnectionError(err.message || "Unknown error during connection test.")
        setUserStatus("error")
        console.error("[SupabaseConnectionTester] General error during connection test:", err)
      }
    }

    testConnection()
  }, [])

  return (
    <Card className="w-full max-w-md mx-auto mt-4">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Loader2 className={`h-5 w-5 ${connectionStatus === "checking" ? "animate-spin" : ""}`} />
          Supabase Connection Status
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex items-center justify-between">
          <span className="font-medium">API Keys Status:</span>
          {SUPABASE_READY ? (
            <Badge className="bg-green-500 hover:bg-green-500">
              <CheckCircle className="h-4 w-4 mr-1" /> Real Keys
            </Badge>
          ) : (
            <Badge variant="destructive">
              <XCircle className="h-4 w-4 mr-1" /> Demo Keys (No Env Vars)
            </Badge>
          )}
        </div>

        <div className="flex items-center justify-between">
          <span className="font-medium">Database Connection:</span>
          {connectionStatus === "checking" && (
            <Badge variant="secondary">
              <Loader2 className="h-4 w-4 mr-1 animate-spin" /> Checking...
            </Badge>
          )}
          {connectionStatus === "connected" && (
            <Badge className="bg-green-500 hover:bg-green-500">
              <CheckCircle className="h-4 w-4 mr-1" /> Connected
            </Badge>
          )}
          {connectionStatus === "failed" && (
            <Badge variant="destructive">
              <XCircle className="h-4 w-4 mr-1" /> Failed
            </Badge>
          )}
        </div>

        {connectionError && connectionStatus === "failed" && (
          <p className="text-sm text-red-500 mt-1">Error: {connectionError}</p>
        )}

        <div className="flex items-center justify-between">
          <span className="font-medium">User Authentication:</span>
          {userStatus === "checking" && (
            <Badge variant="secondary">
              <Loader2 className="h-4 w-4 mr-1 animate-spin" /> Checking...
            </Badge>
          )}
          {userStatus === "authenticated" && (
            <Badge className="bg-blue-500 hover:bg-blue-500">
              <UserIcon className="h-4 w-4 mr-1" /> Authenticated
            </Badge>
          )}
          {userStatus === "unauthenticated" && (
            <Badge variant="outline">
              <XCircle className="h-4 w-4 mr-1" /> Unauthenticated
            </Badge>
          )}
          {userStatus === "error" && (
            <Badge variant="destructive">
              <XCircle className="h-4 w-4 mr-1" /> Error
            </Badge>
          )}
        </div>

        {currentUserEmail && userStatus === "authenticated" && (
          <p className="text-sm text-gray-600">Logged in as: {currentUserEmail}</p>
        )}

        <p className="text-xs text-gray-500 mt-4">
          Sprawdź konsolę przeglądarki (F12) dla szczegółowych logów z `lib/supabase.ts` i `lib/contact-service.ts`.
        </p>
      </CardContent>
    </Card>
  )
}
