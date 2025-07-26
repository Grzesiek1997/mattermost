"use client"

import { useEffect, useState } from "react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { AuthService } from "@/lib/auth"
import { supabase } from "@/lib/supabase"
import type { User } from "@/lib/supabase"
import { Users, MessageSquare, Shield, AlertTriangle, Activity, Database, Ban, Eye, Trash2, Search } from "lucide-react"
import { toast } from "@/hooks/use-toast"
import { formatDistanceToNow } from "date-fns"

interface AdminStats {
  totalUsers: number
  onlineUsers: number
  totalChats: number
  totalMessages: number
  pendingReports: number
}

interface UserReport {
  id: string
  reporter_id: string
  reported_user_id: string
  report_type: string
  description: string
  status: string
  created_at: string
  reporter: User
  reported_user: User
}

interface AdminPanelProps {
  currentUser: User
  onClose: () => void
}

export function AdminPanel({ currentUser, onClose }: AdminPanelProps) {
  const [adminRole, setAdminRole] = useState<string>("user")
  const [stats, setStats] = useState<AdminStats>({
    totalUsers: 0,
    onlineUsers: 0,
    totalChats: 0,
    totalMessages: 0,
    pendingReports: 0,
  })
  const [users, setUsers] = useState<User[]>([])
  const [reports, setReports] = useState<UserReport[]>([])
  const [loading, setLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState("")

  useEffect(() => {
    checkAdminAccess()
  }, [])

  const checkAdminAccess = async () => {
    try {
      const role = await AuthService.getAdminRole(currentUser.id)
      setAdminRole(role)

      if (role === "user") {
        toast({
          title: "Access Denied",
          description: "You don't have admin privileges",
          variant: "destructive",
        })
        onClose()
        return
      }

      await loadAdminData()
    } catch (error) {
      console.error("Admin access check failed:", error)
      onClose()
    } finally {
      setLoading(false)
    }
  }

  const loadAdminData = async () => {
    try {
      // Load stats
      const [usersCount, onlineCount, chatsCount, messagesCount, reportsCount] = await Promise.all([
        supabase.from("users").select("count", { count: "exact", head: true }),
        supabase.from("users").select("count", { count: "exact", head: true }).eq("is_online", true),
        supabase.from("chats").select("count", { count: "exact", head: true }),
        supabase.from("messages").select("count", { count: "exact", head: true }),
        supabase.from("user_reports").select("count", { count: "exact", head: true }).eq("status", "pending"),
      ])

      setStats({
        totalUsers: usersCount.count || 0,
        onlineUsers: onlineCount.count || 0,
        totalChats: chatsCount.count || 0,
        totalMessages: messagesCount.count || 0,
        pendingReports: reportsCount.count || 0,
      })

      // Load users
      const { data: usersData } = await supabase
        .from("users")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(100)

      setUsers(usersData || [])

      // Load reports
      const { data: reportsData } = await supabase
        .from("user_reports")
        .select(`
          *,
          reporter:reporter_id (id, username, full_name, avatar_url),
          reported_user:reported_user_id (id, username, full_name, avatar_url)
        `)
        .eq("status", "pending")
        .order("created_at", { ascending: false })

      setReports(reportsData || [])
    } catch (error) {
      console.error("Failed to load admin data:", error)
    }
  }

  const handleBanUser = async (userId: string) => {
    try {
      // In a real app, you'd have a banned_users table or status field
      await supabase.from("users").update({ is_online: false }).eq("id", userId)

      // Log admin action
      await supabase.rpc("log_admin_action", {
        action_type_param: "ban_user",
        target_type_param: "user",
        target_id_param: userId,
      })

      toast({
        title: "User banned",
        description: "User has been banned successfully",
      })

      loadAdminData()
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message,
        variant: "destructive",
      })
    }
  }

  const handleResolveReport = async (reportId: string, action: "resolved" | "dismissed") => {
    try {
      await supabase
        .from("user_reports")
        .update({
          status: action,
          reviewed_by: currentUser.id,
          reviewed_at: new Date().toISOString(),
        })
        .eq("id", reportId)

      // Log admin action
      await supabase.rpc("log_admin_action", {
        action_type_param: `report_${action}`,
        target_type_param: "report",
        target_id_param: reportId,
      })

      toast({
        title: "Report updated",
        description: `Report has been ${action}`,
      })

      loadAdminData()
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message,
        variant: "destructive",
      })
    }
  }

  const filteredUsers = users.filter(
    (user) =>
      user.username?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      user.full_name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      user.email.toLowerCase().includes(searchQuery.toLowerCase()),
  )

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500" />
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50 p-6">
      <div className="max-w-7xl mx-auto space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold flex items-center gap-2">
              <Shield className="h-8 w-8 text-blue-600" />
              Admin Panel
            </h1>
            <p className="text-gray-600">
              Welcome, {currentUser.full_name} ({adminRole})
            </p>
          </div>
          <Button onClick={onClose} variant="outline">
            Back to App
          </Button>
        </div>

        {/* Stats Cards */}
        <div className="grid grid-cols-1 md:grid-cols-5 gap-4">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium flex items-center gap-2">
                <Users className="h-4 w-4" />
                Total Users
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{stats.totalUsers}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium flex items-center gap-2">
                <Activity className="h-4 w-4 text-green-600" />
                Online Users
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold text-green-600">{stats.onlineUsers}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium flex items-center gap-2">
                <MessageSquare className="h-4 w-4" />
                Total Chats
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{stats.totalChats}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium flex items-center gap-2">
                <Database className="h-4 w-4" />
                Messages
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{stats.totalMessages}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium flex items-center gap-2">
                <AlertTriangle className="h-4 w-4 text-red-600" />
                Reports
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold text-red-600">{stats.pendingReports}</div>
            </CardContent>
          </Card>
        </div>

        {/* Main Content */}
        <Tabs defaultValue="users" className="space-y-4">
          <TabsList>
            <TabsTrigger value="users">Users Management</TabsTrigger>
            <TabsTrigger value="reports">Reports</TabsTrigger>
            <TabsTrigger value="settings">System Settings</TabsTrigger>
          </TabsList>

          <TabsContent value="users" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>Users Management</CardTitle>
                <CardDescription>Manage all users in the system</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  <div className="flex items-center space-x-2">
                    <Search className="h-4 w-4 text-gray-400" />
                    <Input
                      placeholder="Search users..."
                      value={searchQuery}
                      onChange={(e) => setSearchQuery(e.target.value)}
                      className="max-w-sm"
                    />
                  </div>

                  <ScrollArea className="h-[600px]">
                    <div className="space-y-2">
                      {filteredUsers.map((user) => (
                        <div
                          key={user.id}
                          className="flex items-center justify-between p-4 border rounded-lg hover:bg-gray-50"
                        >
                          <div className="flex items-center space-x-3">
                            <div className="relative">
                              <Avatar className="h-10 w-10">
                                <AvatarImage src={user.avatar_url || "/placeholder.svg"} />
                                <AvatarFallback>
                                  {user.full_name?.charAt(0) || user.username?.charAt(0) || "U"}
                                </AvatarFallback>
                              </Avatar>
                              {user.is_online && (
                                <div className="absolute -bottom-1 -right-1 w-3 h-3 bg-green-500 rounded-full border-2 border-white" />
                              )}
                            </div>
                            <div>
                              <div className="flex items-center space-x-2">
                                <span className="font-medium">{user.full_name || user.username}</span>
                                <Badge variant="outline" className="text-xs">
                                  @{user.username}
                                </Badge>
                                {user.is_online ? (
                                  <Badge className="text-xs bg-green-500 hover:bg-green-500">Online</Badge>
                                ) : (
                                  <Badge variant="secondary" className="text-xs">
                                    Offline
                                  </Badge>
                                )}
                              </div>
                              <p className="text-sm text-gray-600">{user.email}</p>
                              <p className="text-xs text-gray-500">
                                Joined {formatDistanceToNow(new Date(user.created_at), { addSuffix: true })}
                              </p>
                            </div>
                          </div>

                          <div className="flex items-center space-x-2">
                            <Button size="sm" variant="outline">
                              <Eye className="h-4 w-4" />
                            </Button>
                            <Button size="sm" variant="outline" onClick={() => handleBanUser(user.id)}>
                              <Ban className="h-4 w-4" />
                            </Button>
                            {adminRole === "super_admin" && (
                              <Button size="sm" variant="destructive">
                                <Trash2 className="h-4 w-4" />
                              </Button>
                            )}
                          </div>
                        </div>
                      ))}
                    </div>
                  </ScrollArea>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="reports" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>User Reports</CardTitle>
                <CardDescription>Review and manage user reports</CardDescription>
              </CardHeader>
              <CardContent>
                <ScrollArea className="h-[600px]">
                  <div className="space-y-4">
                    {reports.map((report) => (
                      <div key={report.id} className="border rounded-lg p-4 space-y-3">
                        <div className="flex items-center justify-between">
                          <div className="flex items-center space-x-2">
                            <Badge variant="destructive">{report.report_type}</Badge>
                            <span className="text-sm text-gray-500">
                              {formatDistanceToNow(new Date(report.created_at), { addSuffix: true })}
                            </span>
                          </div>
                          <div className="flex space-x-2">
                            <Button
                              size="sm"
                              variant="outline"
                              onClick={() => handleResolveReport(report.id, "resolved")}
                            >
                              Resolve
                            </Button>
                            <Button
                              size="sm"
                              variant="ghost"
                              onClick={() => handleResolveReport(report.id, "dismissed")}
                            >
                              Dismiss
                            </Button>
                          </div>
                        </div>

                        <div className="grid grid-cols-2 gap-4">
                          <div>
                            <Label className="text-xs text-gray-500">Reporter</Label>
                            <div className="flex items-center space-x-2 mt-1">
                              <Avatar className="h-6 w-6">
                                <AvatarImage src={report.reporter?.avatar_url || "/placeholder.svg"} />
                                <AvatarFallback className="text-xs">
                                  {report.reporter?.full_name?.charAt(0) || "U"}
                                </AvatarFallback>
                              </Avatar>
                              <span className="text-sm">{report.reporter?.full_name || report.reporter?.username}</span>
                            </div>
                          </div>

                          <div>
                            <Label className="text-xs text-gray-500">Reported User</Label>
                            <div className="flex items-center space-x-2 mt-1">
                              <Avatar className="h-6 w-6">
                                <AvatarImage src={report.reported_user?.avatar_url || "/placeholder.svg"} />
                                <AvatarFallback className="text-xs">
                                  {report.reported_user?.full_name?.charAt(0) || "U"}
                                </AvatarFallback>
                              </Avatar>
                              <span className="text-sm">
                                {report.reported_user?.full_name || report.reported_user?.username}
                              </span>
                            </div>
                          </div>
                        </div>

                        <div>
                          <Label className="text-xs text-gray-500">Description</Label>
                          <p className="text-sm mt-1">{report.description}</p>
                        </div>
                      </div>
                    ))}

                    {reports.length === 0 && (
                      <div className="text-center py-8 text-gray-500">
                        <AlertTriangle className="h-12 w-12 mx-auto mb-4 opacity-50" />
                        <p>No pending reports</p>
                      </div>
                    )}
                  </div>
                </ScrollArea>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="settings" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>System Settings</CardTitle>
                <CardDescription>Configure application settings</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <Label>Application Name</Label>
                      <Input defaultValue="Telegram Clone" />
                    </div>
                    <div>
                      <Label>Max File Size (MB)</Label>
                      <Input type="number" defaultValue="50" />
                    </div>
                  </div>

                  <div>
                    <Label>Registration Enabled</Label>
                    <Select defaultValue="true">
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="true">Enabled</SelectItem>
                        <SelectItem value="false">Disabled</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>

                  <div>
                    <Label>System Announcement</Label>
                    <Textarea placeholder="Enter system-wide announcement..." />
                  </div>

                  <Button>Save Settings</Button>
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </div>
  )
}
