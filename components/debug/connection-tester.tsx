"use client"

import { useEffect, useState } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ContactService } from "@/lib/contact-service"
import { AuthService } from "@/lib/auth"
import { supabase, SUPABASE_READY } from "@/lib/supabase"
import { CheckCircle, XCircle, Loader2, RefreshCw, Database, Users, Search, UserPlus } from "lucide-react"

interface TestResult {
  name: string
  status: "pending" | "success" | "error"
  message: string
  details?: any
}

export function ConnectionTester() {
  const [tests, setTests] = useState<TestResult[]>([])
  const [isRunning, setIsRunning] = useState(false)
  const [currentUser, setCurrentUser] = useState<any>(null)

  const updateTest = (name: string, status: TestResult["status"], message: string, details?: any) => {
    setTests((prev) => {
      const existing = prev.find((t) => t.name === name)
      if (existing) {
        existing.status = status
        existing.message = message
        existing.details = details
        return [...prev]
      } else {
        return [...prev, { name, status, message, details }]
      }
    })
  }

  const runTests = async () => {
    setIsRunning(true)
    setTests([])

    // Test 1: Database Connection
    updateTest("Database Connection", "pending", "Testing connection...")
    try {
      const { data, error } = await supabase.from("users").select("count", { count: "exact", head: true })
      if (error) throw error
      updateTest("Database Connection", "success", `Connected! Users count: ${data}`)
    } catch (err: any) {
      updateTest("Database Connection", "error", `Failed: ${err.message}`)
    }

    // Test 2: Authentication
    updateTest("Authentication", "pending", "Checking auth status...")
    try {
      const user = await AuthService.getCurrentUser()
      if (user) {
        setCurrentUser(user)
        updateTest("Authentication", "success", `Authenticated as: ${user.email}`, user)
      } else {
        updateTest("Authentication", "error", "Not authenticated")
      }
    } catch (err: any) {
      updateTest("Authentication", "error", `Auth error: ${err.message}`)
    }

    // Test 3: Contact Service Connection
    updateTest("Contact Service", "pending", "Testing contact service...")
    try {
      const connectionOk = await ContactService.testConnection()
      if (connectionOk) {
        updateTest("Contact Service", "success", "Contact service working")
      } else {
        updateTest("Contact Service", "error", "Contact service failed")
      }
    } catch (err: any) {
      updateTest("Contact Service", "error", `Contact service error: ${err.message}`)
    }

    // Test 4: User Search (only if authenticated)
    const authTest = tests.find((t) => t.name === "Authentication")
    if (authTest?.status === "success") {
      updateTest("User Search", "pending", "Testing user search...")
      try {
        const searchResults = await ContactService.searchUsers("test", 5)
        updateTest("User Search", "success", `Found ${searchResults.length} users`, searchResults)
      } catch (err: any) {
        updateTest("User Search", "error", `Search failed: ${err.message}`)
      }

      // Test 5: Get Contacts
      updateTest("Get Contacts", "pending", "Getting contacts...")
      try {
        const contacts = await ContactService.getContacts()
        updateTest("Get Contacts", "success", `Found ${contacts.length} contacts`, contacts)
      } catch (err: any) {
        updateTest("Get Contacts", "error", `Failed: ${err.message}`)
      }

      // Test 6: Get Invitations
      updateTest("Get Invitations", "pending", "Getting invitations...")
      try {
        const invitations = await ContactService.getPendingInvitations()
        updateTest("Get Invitations", "success", `Found ${invitations.length} invitations`, invitations)
      } catch (err: any) {
        updateTest("Get Invitations", "error", `Failed: ${err.message}`)
      }
    }

    setIsRunning(false)
  }

  useEffect(() => {
    runTests()
  }, [])

  const getStatusIcon = (status: TestResult["status"]) => {
    switch (status) {
      case "pending":
        return <Loader2 className="h-4 w-4 animate-spin text-blue-500" />
      case "success":
        return <CheckCircle className="h-4 w-4 text-green-500" />
      case "error":
        return <XCircle className="h-4 w-4 text-red-500" />
    }
  }

  const getStatusBadge = (status: TestResult["status"]) => {
    switch (status) {
      case "pending":
        return <Badge variant="secondary">Testing...</Badge>
      case "success":
        return <Badge className="bg-green-500 hover:bg-green-500">Success</Badge>
      case "error":
        return <Badge variant="destructive">Error</Badge>
    }
  }

  return (
    <div className="max-w-4xl mx-auto p-6 space-y-6">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <CardTitle className="flex items-center gap-2">
              <Database className="h-5 w-5" />
              Telegram Clone - System Test
            </CardTitle>
            <Button onClick={runTests} disabled={isRunning} size="sm">
              <RefreshCw className={`h-4 w-4 mr-2 ${isRunning ? "animate-spin" : ""}`} />
              {isRunning ? "Testing..." : "Run Tests"}
            </Button>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          <Alert>
            <Database className="h-4 w-4" />
            <AlertDescription>
              <strong>Supabase Status:</strong> {SUPABASE_READY ? "✅ Connected" : "❌ Not configured"}
            </AlertDescription>
          </Alert>

          {currentUser && (
            <Alert className="border-blue-200 bg-blue-50">
              <Users className="h-4 w-4 text-blue-600" />
              <AlertDescription className="text-blue-800">
                <strong>Current User:</strong> {currentUser.full_name || currentUser.username} ({currentUser.email})
              </AlertDescription>
            </Alert>
          )}

          <div className="grid gap-4">
            {tests.map((test) => (
              <div key={test.name} className="flex items-center justify-between p-4 border rounded-lg">
                <div className="flex items-center gap-3">
                  {getStatusIcon(test.status)}
                  <div>
                    <h3 className="font-medium">{test.name}</h3>
                    <p className="text-sm text-gray-600">{test.message}</p>
                    {test.details && test.status === "success" && (
                      <details className="mt-2">
                        <summary className="text-xs text-blue-600 cursor-pointer">Show details</summary>
                        <pre className="text-xs bg-gray-100 p-2 rounded mt-1 overflow-auto max-h-32">
                          {JSON.stringify(test.details, null, 2)}
                        </pre>
                      </details>
                    )}
                  </div>
                </div>
                {getStatusBadge(test.status)}
              </div>
            ))}
          </div>

          {tests.length > 0 && (
            <div className="mt-6 p-4 bg-gray-50 rounded-lg">
              <h3 className="font-medium mb-2">Test Summary</h3>
              <div className="flex gap-4 text-sm">
                <span className="text-green-600">✅ Passed: {tests.filter((t) => t.status === "success").length}</span>
                <span className="text-red-600">❌ Failed: {tests.filter((t) => t.status === "error").length}</span>
                <span className="text-blue-600">⏳ Running: {tests.filter((t) => t.status === "pending").length}</span>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Quick Actions */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <UserPlus className="h-5 w-5" />
            Quick Test Actions
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <Button
            onClick={async () => {
              try {
                const results = await ContactService.searchUsers("john", 3)
                alert(`Search results: ${JSON.stringify(results, null, 2)}`)
              } catch (err: any) {
                alert(`Search error: ${err.message}`)
              }
            }}
            variant="outline"
            size="sm"
          >
            <Search className="h-4 w-4 mr-2" />
            Test Search "john"
          </Button>

          <Button
            onClick={async () => {
              try {
                const contacts = await ContactService.getContacts()
                alert(`Contacts: ${JSON.stringify(contacts, null, 2)}`)
              } catch (err: any) {
                alert(`Contacts error: ${err.message}`)
              }
            }}
            variant="outline"
            size="sm"
          >
            <Users className="h-4 w-4 mr-2" />
            Get My Contacts
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
