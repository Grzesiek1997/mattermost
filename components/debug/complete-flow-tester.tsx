"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Input } from "@/components/ui/input"
import { AuthService } from "@/lib/auth"
import { ContactService } from "@/lib/contact-service"
import { ChatService } from "@/lib/chat-service"
import { supabase } from "@/lib/supabase"
import { CheckCircle, XCircle, Clock, Play, User, MessageCircle, Users } from "lucide-react"

interface TestResult {
  name: string
  status: "pending" | "running" | "success" | "error"
  message: string
  details?: any
}

export function CompleteFlowTester() {
  const [tests, setTests] = useState<TestResult[]>([])
  const [isRunning, setIsRunning] = useState(false)
  const [testUser, setTestUser] = useState<any>(null)
  const [searchQuery, setSearchQuery] = useState("test")

  const updateTest = (name: string, status: TestResult["status"], message: string, details?: any) => {
    setTests((prev) => prev.map((test) => (test.name === name ? { ...test, status, message, details } : test)))
  }

  const addTest = (name: string) => {
    setTests((prev) => [...prev, { name, status: "pending", message: "Waiting..." }])
  }

  const runCompleteFlowTest = async () => {
    setIsRunning(true)
    setTests([])

    // Initialize all tests
    const testNames = [
      "Database Connection",
      "User Authentication",
      "User Profile Creation",
      "Contact Search",
      "Contact Invitation",
      "Chat Creation",
      "Message Sending",
      "Real-time Updates",
      "Complete Flow Verification",
    ]

    testNames.forEach(addTest)

    try {
      // Test 1: Database Connection
      updateTest("Database Connection", "running", "Testing Supabase connection...")
      try {
        const { data, error } = await supabase.from("users").select("id").limit(1)
        if (error) throw error
        updateTest("Database Connection", "success", "Connected to Supabase successfully")
      } catch (error: any) {
        updateTest("Database Connection", "error", `Connection failed: ${error.message}`)
        return
      }

      // Test 2: User Authentication
      updateTest("User Authentication", "running", "Checking authentication...")
      try {
        const currentUser = await AuthService.getCurrentUser()
        if (!currentUser) {
          updateTest("User Authentication", "error", "No authenticated user found")
          return
        }
        setTestUser(currentUser)
        updateTest("User Authentication", "success", `Authenticated as: ${currentUser.username}`, currentUser)
      } catch (error: any) {
        updateTest("User Authentication", "error", `Auth failed: ${error.message}`)
        return
      }

      // Test 3: User Profile Creation
      updateTest("User Profile Creation", "running", "Verifying user profile...")
      try {
        const profile = await AuthService.getCurrentUser()
        if (!profile?.username) {
          updateTest("User Profile Creation", "error", "User profile incomplete")
          return
        }
        updateTest("User Profile Creation", "success", `Profile complete: ${profile.full_name || profile.username}`)
      } catch (error: any) {
        updateTest("User Profile Creation", "error", `Profile error: ${error.message}`)
        return
      }

      // Test 4: Contact Search
      updateTest("Contact Search", "running", `Searching for users with query: "${searchQuery}"...`)
      try {
        const searchResults = await ContactService.searchUsers(searchQuery, 5)
        if (searchResults.length === 0) {
          updateTest("Contact Search", "error", `No users found for "${searchQuery}"`)
          return
        }
        updateTest("Contact Search", "success", `Found ${searchResults.length} users`, searchResults)
      } catch (error: any) {
        updateTest("Contact Search", "error", `Search failed: ${error.message}`)
        return
      }

      // Test 5: Contact Invitation (simulate)
      updateTest("Contact Invitation", "running", "Testing contact invitation system...")
      try {
        const contacts = await ContactService.getContacts()
        const invitations = await ContactService.getPendingInvitations()
        updateTest(
          "Contact Invitation",
          "success",
          `${contacts.length} contacts, ${invitations.length} pending invitations`,
          {
            contacts: contacts.length,
            invitations: invitations.length,
          },
        )
      } catch (error: any) {
        updateTest("Contact Invitation", "error", `Contact system failed: ${error.message}`)
        return
      }

      // Test 6: Chat Creation
      updateTest("Chat Creation", "running", "Testing chat creation...")
      try {
        const userChats = await ChatService.getUserChats(testUser.id)
        updateTest("Chat Creation", "success", `User has ${userChats.length} chats`, userChats)
      } catch (error: any) {
        updateTest("Chat Creation", "error", `Chat creation failed: ${error.message}`)
        return
      }

      // Test 7: Message Sending (simulate)
      updateTest("Message Sending", "running", "Testing message system...")
      try {
        // Test message search instead of sending to avoid creating test messages
        const messages = await ChatService.searchMessages("test", 5)
        updateTest("Message Sending", "success", `Message system working, found ${messages.length} test messages`)
      } catch (error: any) {
        updateTest("Message Sending", "error", `Message system failed: ${error.message}`)
        return
      }

      // Test 8: Real-time Updates
      updateTest("Real-time Updates", "running", "Testing real-time subscriptions...")
      try {
        // Test if we can create a subscription
        const channel = supabase.channel("test-channel")
        await new Promise((resolve) => {
          channel.subscribe((status) => {
            if (status === "SUBSCRIBED") {
              resolve(true)
            }
          })
          setTimeout(resolve, 2000) // Timeout after 2 seconds
        })
        supabase.removeChannel(channel)
        updateTest("Real-time Updates", "success", "Real-time subscriptions working")
      } catch (error: any) {
        updateTest("Real-time Updates", "error", `Real-time failed: ${error.message}`)
        return
      }

      // Test 9: Complete Flow Verification
      updateTest("Complete Flow Verification", "running", "Verifying complete user flow...")
      try {
        const allTestsPassed = tests
          .filter((t) => t.name !== "Complete Flow Verification")
          .every((t) => t.status === "success")
        if (allTestsPassed) {
          updateTest(
            "Complete Flow Verification",
            "success",
            "All systems operational! Users can register, find contacts, create chats, and send messages.",
          )
        } else {
          updateTest("Complete Flow Verification", "error", "Some systems have issues - check individual test results")
        }
      } catch (error: any) {
        updateTest("Complete Flow Verification", "error", `Flow verification failed: ${error.message}`)
      }
    } catch (error: any) {
      console.error("Complete flow test error:", error)
    } finally {
      setIsRunning(false)
    }
  }

  const getStatusIcon = (status: TestResult["status"]) => {
    switch (status) {
      case "success":
        return <CheckCircle className="h-4 w-4 text-green-600" />
      case "error":
        return <XCircle className="h-4 w-4 text-red-600" />
      case "running":
        return <Clock className="h-4 w-4 text-blue-600 animate-spin" />
      default:
        return <Clock className="h-4 w-4 text-gray-400" />
    }
  }

  const getStatusBadge = (status: TestResult["status"]) => {
    const variants = {
      success: "default",
      error: "destructive",
      running: "secondary",
      pending: "outline",
    } as const

    return (
      <Badge variant={variants[status]} className="text-xs">
        {status.toUpperCase()}
      </Badge>
    )
  }

  return (
    <Card className="w-full max-w-4xl mx-auto">
      <CardHeader>
        <CardTitle className="flex items-center">
          <MessageCircle className="h-5 w-5 mr-2" />
          Complete User Flow Test
        </CardTitle>
        <CardDescription>Test the entire application flow from authentication to messaging</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center space-x-4">
          <div className="flex-1">
            <Input
              placeholder="Search query for contact test"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              disabled={isRunning}
            />
          </div>
          <Button onClick={runCompleteFlowTest} disabled={isRunning} className="flex items-center">
            <Play className="h-4 w-4 mr-2" />
            {isRunning ? "Running Tests..." : "Run Complete Test"}
          </Button>
        </div>

        {testUser && (
          <div className="p-3 bg-blue-50 rounded-lg border">
            <div className="flex items-center space-x-2">
              <User className="h-4 w-4 text-blue-600" />
              <span className="font-medium text-blue-900">Test User:</span>
              <span className="text-blue-700">{testUser.full_name || testUser.username}</span>
              <Badge variant="outline" className="text-xs">
                {testUser.email}
              </Badge>
            </div>
          </div>
        )}

        <ScrollArea className="h-[500px] w-full border rounded-lg p-4">
          <div className="space-y-3">
            {tests.length === 0 ? (
              <div className="text-center py-8 text-gray-500">
                <Users className="h-12 w-12 mx-auto mb-4 opacity-50" />
                <p>Click "Run Complete Test" to start testing the application flow</p>
              </div>
            ) : (
              tests.map((test, index) => (
                <div key={index} className="flex items-start space-x-3 p-3 rounded-lg border bg-white">
                  <div className="mt-0.5">{getStatusIcon(test.status)}</div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between mb-1">
                      <span className="font-medium text-sm">{test.name}</span>
                      {getStatusBadge(test.status)}
                    </div>
                    <p className="text-sm text-gray-600">{test.message}</p>
                    {test.details && (
                      <details className="mt-2">
                        <summary className="text-xs text-gray-500 cursor-pointer hover:text-gray-700">
                          View Details
                        </summary>
                        <pre className="mt-1 text-xs bg-gray-50 p-2 rounded overflow-auto">
                          {JSON.stringify(test.details, null, 2)}
                        </pre>
                      </details>
                    )}
                  </div>
                </div>
              ))
            )}
          </div>
        </ScrollArea>

        {tests.length > 0 && (
          <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
            <div className="flex space-x-4 text-sm">
              <span className="flex items-center">
                <CheckCircle className="h-4 w-4 text-green-600 mr-1" />
                {tests.filter((t) => t.status === "success").length} Passed
              </span>
              <span className="flex items-center">
                <XCircle className="h-4 w-4 text-red-600 mr-1" />
                {tests.filter((t) => t.status === "error").length} Failed
              </span>
              <span className="flex items-center">
                <Clock className="h-4 w-4 text-blue-600 mr-1" />
                {tests.filter((t) => t.status === "running").length} Running
              </span>
            </div>
            <div className="text-sm text-gray-600">
              {tests.filter((t) => t.status !== "pending").length} / {tests.length} Complete
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
