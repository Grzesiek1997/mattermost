"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { AdminPanel } from "@/components/admin/admin-panel"
import { AuthService } from "@/lib/auth"
import type { User } from "@/lib/supabase"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Shield, Lock, UserPlus, ArrowLeft } from "lucide-react"
import { toast } from "@/hooks/use-toast"

export default function AdminPage() {
  const router = useRouter()
  const [currentUser, setCurrentUser] = useState<User | null>(null)
  const [isAdmin, setIsAdmin] = useState(false)
  const [loading, setLoading] = useState(true)
  const [adminSetup, setAdminSetup] = useState(false)
  const [promoteEmail, setPromoteEmail] = useState("")
  const [promoteLoading, setPromoteLoading] = useState(false)

  useEffect(() => {
    checkAdminAccess()
  }, [])

  const checkAdminAccess = async () => {
    try {
      const user = await AuthService.getCurrentUser()

      if (!user) {
        // Redirect to login if not authenticated
        router.push("/?redirect=admin")
        return
      }

      setCurrentUser(user)

      // Check if user is admin
      const adminStatus = await AuthService.isAdmin(user.id)
      setIsAdmin(adminStatus)

      if (!adminStatus) {
        // Check if this could be the first admin setup
        setAdminSetup(true)
      }
    } catch (error) {
      console.error("Admin access check failed:", error)
      router.push("/")
    } finally {
      setLoading(false)
    }
  }

  const handleCreateFirstAdmin = async () => {
    try {
      setPromoteLoading(true)
      const result = await AuthService.createFirstSuperAdmin()

      toast({
        title: "Success!",
        description: result,
      })

      // Refresh admin status
      await checkAdminAccess()
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message,
        variant: "destructive",
      })
    } finally {
      setPromoteLoading(false)
    }
  }

  const handlePromoteUser = async () => {
    if (!promoteEmail.trim()) {
      toast({
        title: "Error",
        description: "Please enter an email address",
        variant: "destructive",
      })
      return
    }

    try {
      setPromoteLoading(true)
      const result = await AuthService.promoteUserToAdmin(promoteEmail.trim())

      if (result.startsWith("SUCCESS:")) {
        toast({
          title: "Success!",
          description: result.replace("SUCCESS: ", ""),
        })
        setPromoteEmail("")
      } else {
        toast({
          title: "Error",
          description: result.replace("ERROR: ", ""),
          variant: "destructive",
        })
      }
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message,
        variant: "destructive",
      })
    } finally {
      setPromoteLoading(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500" />
      </div>
    )
  }

  if (!currentUser) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gray-50">
        <Card className="w-full max-w-md">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Lock className="h-5 w-5" />
              Authentication Required
            </CardTitle>
            <CardDescription>You need to be logged in to access the admin panel</CardDescription>
          </CardHeader>
          <CardContent>
            <Button onClick={() => router.push("/")} className="w-full">
              Go to Login
            </Button>
          </CardContent>
        </Card>
      </div>
    )
  }

  if (!isAdmin && adminSetup) {
    return (
      <div className="min-h-screen bg-gray-50 p-6">
        <div className="max-w-2xl mx-auto space-y-6">
          <div className="flex items-center gap-2">
            <Button variant="ghost" size="sm" onClick={() => router.push("/")}>
              <ArrowLeft className="h-4 w-4 mr-2" />
              Back to App
            </Button>
          </div>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Shield className="h-5 w-5 text-blue-600" />
                Admin Setup Required
              </CardTitle>
              <CardDescription>
                No admin users found. Set up the first super admin to access the admin panel.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
              <Alert>
                <Shield className="h-4 w-4" />
                <AlertDescription>
                  <strong>Current User:</strong> {currentUser.full_name || currentUser.username} ({currentUser.email})
                </AlertDescription>
              </Alert>

              <div className="space-y-4">
                <div>
                  <h3 className="font-semibold mb-2">Option 1: Make yourself the first Super Admin</h3>
                  <p className="text-sm text-gray-600 mb-4">
                    This will automatically promote the oldest user account (likely yours) to Super Admin.
                  </p>
                  <Button onClick={handleCreateFirstAdmin} disabled={promoteLoading} className="w-full">
                    {promoteLoading ? "Creating..." : "Create First Super Admin"}
                  </Button>
                </div>

                <div className="relative">
                  <div className="absolute inset-0 flex items-center">
                    <span className="w-full border-t" />
                  </div>
                  <div className="relative flex justify-center text-xs uppercase">
                    <span className="bg-white px-2 text-muted-foreground">Or</span>
                  </div>
                </div>

                <div>
                  <h3 className="font-semibold mb-2">Option 2: Promote specific user</h3>
                  <p className="text-sm text-gray-600 mb-4">
                    Enter the email of a user you want to promote to admin (only works if you're already a super admin).
                  </p>
                  <div className="space-y-2">
                    <Label htmlFor="promote-email">User Email</Label>
                    <Input
                      id="promote-email"
                      type="email"
                      placeholder="user@example.com"
                      value={promoteEmail}
                      onChange={(e) => setPromoteEmail(e.target.value)}
                    />
                    <Button
                      onClick={handlePromoteUser}
                      disabled={promoteLoading || !promoteEmail.trim()}
                      variant="outline"
                      className="w-full bg-transparent"
                    >
                      <UserPlus className="h-4 w-4 mr-2" />
                      {promoteLoading ? "Promoting..." : "Promote to Admin"}
                    </Button>
                  </div>
                </div>
              </div>

              <Alert>
                <Shield className="h-4 w-4" />
                <AlertDescription>
                  <strong>Security Note:</strong> Only the first option will work if no admins exist yet. After creating
                  the first super admin, they can promote other users.
                </AlertDescription>
              </Alert>
            </CardContent>
          </Card>
        </div>
      </div>
    )
  }

  if (!isAdmin) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gray-50">
        <Card className="w-full max-w-md">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Lock className="h-5 w-5 text-red-500" />
              Access Denied
            </CardTitle>
            <CardDescription>You don't have admin privileges to access this panel</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <Alert>
              <Shield className="h-4 w-4" />
              <AlertDescription>
                <strong>Current User:</strong> {currentUser.full_name || currentUser.username} ({currentUser.email})
                <br />
                <strong>Role:</strong> Regular User
              </AlertDescription>
            </Alert>
            <Button onClick={() => router.push("/")} className="w-full">
              Back to App
            </Button>
          </CardContent>
        </Card>
      </div>
    )
  }

  return <AdminPanel currentUser={currentUser} onClose={() => router.push("/")} />
}
