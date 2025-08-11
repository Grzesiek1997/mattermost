"use client"

import { useState, useEffect } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { supabase } from "@/lib/supabase"
import { AuthService } from "@/lib/auth"
import type { User } from "@/lib/supabase"
import { Users, Search, Eye, Edit, Ban, Trash2, UserPlus, Activity, Calendar, Mail, Phone } from "lucide-react"
import { toast } from "@/hooks/use-toast"
import { formatDistanceToNow } from "date-fns"

interface UserDetails extends User {
  admin_role?: string
  total_messages?: number
  total_chats?: number
  last_login?: string
  is_banned?: boolean
}

interface UserActivity {
  id: string
  action_type: string
  details: any
  created_at: string
}

interface UserManagementProps {
  currentUser: User
  adminRole: string
}

export function UserManagement({ currentUser, adminRole }: UserManagementProps) {
  const [users, setUsers] = useState<UserDetails[]>([])
  const [selectedUser, setSelectedUser] = useState<UserDetails | null>(null)
  const [userActivity, setUserActivity] = useState<UserActivity[]>([])
  const [searchQuery, setSearchQuery] = useState("")
  const [filterRole, setFilterRole] = useState("all")
  const [filterStatus, setFilterStatus] = useState("all")
  const [loading, setLoading] = useState(true)
  const [detailsLoading, setDetailsLoading] = useState(false)
  const [editingUser, setEditingUser] = useState<UserDetails | null>(null)
  const [promoteEmail, setPromoteEmail] = useState("")

  useEffect(() => {
    loadUsers()
  }, [])

  const loadUsers = async () => {
    try {
      setLoading(true)

      // Load users with admin roles
      const { data: usersData, error } = await supabase
        .from("users")
        .select(`
          *,
          admin_roles (role)
        `)
        .order("created_at", { ascending: false })

      if (error) throw error

      // Enhance user data with additional info
      const enhancedUsers = await Promise.all(
        (usersData || []).map(async (user) => {
          // Get message count
          const { count: messageCount } = await supabase
            .from("messages")
            .select("count", { count: "exact", head: true })
            .eq("user_id", user.id)

          // Get chat count
          const { count: chatCount } = await supabase
            .from("chat_members")
            .select("count", { count: "exact", head: true })
            .eq("user_id", user.id)

          return {
            ...user,
            admin_role: user.admin_roles?.[0]?.role || "user",
            total_messages: messageCount || 0,
            total_chats: chatCount || 0,
          }
        }),
      )

      setUsers(enhancedUsers)
    } catch (error) {
      console.error("Failed to load users:", error)
      toast({
        title: "Error",
        description: "Failed to load users",
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  const loadUserDetails = async (user: UserDetails) => {
    try {
      setDetailsLoading(true)
      setSelectedUser(user)

      // Load user activity (admin actions related to this user)
      const { data: activityData } = await supabase
        .from("admin_actions")
        .select("*")
        .eq("target_id", user.id)
        .order("created_at", { ascending: false })
        .limit(50)

      setUserActivity(activityData || [])
    } catch (error) {
      console.error("Failed to load user details:", error)
    } finally {
      setDetailsLoading(false)
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
      const result = await AuthService.promoteUserToAdmin(promoteEmail.trim())

      if (result.startsWith("SUCCESS:")) {
        toast({
          title: "Success!",
          description: result.replace("SUCCESS: ", ""),
        })
        setPromoteEmail("")
        loadUsers()
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
    }
  }

  const handleBanUser = async (user: UserDetails) => {
    try {
      const { error } = await supabase.rpc("admin_manage_user", {
        target_user_id: user.id,
        action_type: "ban",
        reason: "Banned by admin",
      })

      if (error) throw error

      toast({
        title: "User banned",
        description: `${user.username} has been banned`,
      })

      loadUsers()
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to ban user",
        variant: "destructive",
      })
    }
  }

  const handleDeleteUser = async (user: UserDetails) => {
    if (!confirm(`Are you sure you want to delete ${user.username}? This cannot be undone.`)) {
      return
    }

    try {
      const { error } = await supabase.rpc("admin_manage_user", {
        target_user_id: user.id,
        action_type: "delete",
        reason: "Deleted by admin",
      })

      if (error) throw error

      toast({
        title: "User deleted",
        description: `${user.username} has been deleted`,
      })

      loadUsers()
      setSelectedUser(null)
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to delete user",
        variant: "destructive",
      })
    }
  }

  const handleUpdateUser = async (updatedUser: UserDetails) => {
    try {
      const { error } = await supabase
        .from("users")
        .update({
          username: updatedUser.username,
          full_name: updatedUser.full_name,
          bio: updatedUser.bio,
          phone: updatedUser.phone,
        })
        .eq("id", updatedUser.id)

      if (error) throw error

      toast({
        title: "User updated",
        description: "User profile has been updated",
      })

      setEditingUser(null)
      loadUsers()
      if (selectedUser?.id === updatedUser.id) {
        setSelectedUser(updatedUser)
      }
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to update user",
        variant: "destructive",
      })
    }
  }

  const filteredUsers = users.filter((user) => {
    const matchesSearch =
      user.username?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      user.full_name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      user.email.toLowerCase().includes(searchQuery.toLowerCase())

    const matchesRole = filterRole === "all" || user.admin_role === filterRole
    const matchesStatus =
      filterStatus === "all" ||
      (filterStatus === "online" && user.is_online) ||
      (filterStatus === "offline" && !user.is_online)

    return matchesSearch && matchesRole && matchesStatus
  })

  return (
    <div className="space-y-6">
      {/* Header with Actions */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold flex items-center gap-2">
            <Users className="h-6 w-6" />
            User Management
          </h2>
          <p className="text-gray-600">Manage users, roles, and permissions</p>
        </div>

        {adminRole === "super_admin" && (
          <Dialog>
            <DialogTrigger asChild>
              <Button>
                <UserPlus className="h-4 w-4 mr-2" />
                Promote User
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Promote User to Admin</DialogTitle>
                <DialogDescription>Enter the email of the user you want to promote to admin role</DialogDescription>
              </DialogHeader>
              <div className="space-y-4">
                <div>
                  <Label>User Email</Label>
                  <Input
                    type="email"
                    placeholder="user@example.com"
                    value={promoteEmail}
                    onChange={(e) => setPromoteEmail(e.target.value)}
                  />
                </div>
                <Button onClick={handlePromoteUser} className="w-full">
                  Promote to Admin
                </Button>
              </div>
            </DialogContent>
          </Dialog>
        )}
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-4">
        <div className="flex items-center space-x-2">
          <Search className="h-4 w-4 text-gray-400" />
          <Input
            placeholder="Search users..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-64"
          />
        </div>

        <Select value={filterRole} onValueChange={setFilterRole}>
          <SelectTrigger className="w-40">
            <SelectValue placeholder="Filter by role" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Roles</SelectItem>
            <SelectItem value="user">Users</SelectItem>
            <SelectItem value="admin">Admins</SelectItem>
            <SelectItem value="super_admin">Super Admins</SelectItem>
          </SelectContent>
        </Select>

        <Select value={filterStatus} onValueChange={setFilterStatus}>
          <SelectTrigger className="w-40">
            <SelectValue placeholder="Filter by status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            <SelectItem value="online">Online</SelectItem>
            <SelectItem value="offline">Offline</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Users List */}
        <div className="lg:col-span-2">
          <Card>
            <CardHeader>
              <CardTitle>Users ({filteredUsers.length})</CardTitle>
            </CardHeader>
            <CardContent>
              <ScrollArea className="h-[600px]">
                <div className="space-y-2">
                  {loading ? (
                    <div className="flex justify-center py-8">
                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500" />
                    </div>
                  ) : (
                    filteredUsers.map((user) => (
                      <div
                        key={user.id}
                        className={`flex items-center justify-between p-4 border rounded-lg hover:bg-gray-50 cursor-pointer ${
                          selectedUser?.id === user.id ? "bg-blue-50 border-blue-200" : ""
                        }`}
                        onClick={() => loadUserDetails(user)}
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
                              {user.admin_role !== "user" && (
                                <Badge className="text-xs bg-red-500 hover:bg-red-500">{user.admin_role}</Badge>
                              )}
                            </div>
                            <p className="text-sm text-gray-600">{user.email}</p>
                            <div className="flex items-center space-x-4 text-xs text-gray-500">
                              <span>{user.total_messages} messages</span>
                              <span>{user.total_chats} chats</span>
                              <span>Joined {formatDistanceToNow(new Date(user.created_at), { addSuffix: true })}</span>
                            </div>
                          </div>
                        </div>

                        <div className="flex items-center space-x-1">
                          {user.is_online ? (
                            <Badge className="text-xs bg-green-500 hover:bg-green-500">Online</Badge>
                          ) : (
                            <Badge variant="secondary" className="text-xs">
                              Offline
                            </Badge>
                          )}
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </ScrollArea>
            </CardContent>
          </Card>
        </div>

        {/* User Details */}
        <div>
          {selectedUser ? (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center justify-between">
                  User Details
                  <div className="flex space-x-1">
                    <Button size="sm" variant="outline" onClick={() => setEditingUser(selectedUser)}>
                      <Edit className="h-4 w-4" />
                    </Button>
                    <Button size="sm" variant="outline" onClick={() => handleBanUser(selectedUser)}>
                      <Ban className="h-4 w-4" />
                    </Button>
                    {adminRole === "super_admin" && (
                      <Button size="sm" variant="destructive" onClick={() => handleDeleteUser(selectedUser)}>
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                </CardTitle>
              </CardHeader>
              <CardContent>
                {detailsLoading ? (
                  <div className="flex justify-center py-8">
                    <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-500" />
                  </div>
                ) : (
                  <Tabs defaultValue="profile" className="space-y-4">
                    <TabsList className="grid w-full grid-cols-2">
                      <TabsTrigger value="profile">Profile</TabsTrigger>
                      <TabsTrigger value="activity">Activity</TabsTrigger>
                    </TabsList>

                    <TabsContent value="profile" className="space-y-4">
                      <div className="text-center">
                        <Avatar className="h-20 w-20 mx-auto mb-4">
                          <AvatarImage src={selectedUser.avatar_url || "/placeholder.svg"} />
                          <AvatarFallback className="text-lg">
                            {selectedUser.full_name?.charAt(0) || selectedUser.username?.charAt(0) || "U"}
                          </AvatarFallback>
                        </Avatar>
                        <h3 className="font-semibold text-lg">{selectedUser.full_name || selectedUser.username}</h3>
                        <p className="text-gray-600">@{selectedUser.username}</p>
                        {selectedUser.admin_role !== "user" && (
                          <Badge className="mt-2 bg-red-500 hover:bg-red-500">{selectedUser.admin_role}</Badge>
                        )}
                      </div>

                      <div className="space-y-3">
                        <div className="flex items-center space-x-2">
                          <Mail className="h-4 w-4 text-gray-400" />
                          <span className="text-sm">{selectedUser.email}</span>
                        </div>
                        {selectedUser.phone && (
                          <div className="flex items-center space-x-2">
                            <Phone className="h-4 w-4 text-gray-400" />
                            <span className="text-sm">{selectedUser.phone}</span>
                          </div>
                        )}
                        <div className="flex items-center space-x-2">
                          <Calendar className="h-4 w-4 text-gray-400" />
                          <span className="text-sm">
                            Joined {formatDistanceToNow(new Date(selectedUser.created_at), { addSuffix: true })}
                          </span>
                        </div>
                        <div className="flex items-center space-x-2">
                          <Activity className="h-4 w-4 text-gray-400" />
                          <span className="text-sm">
                            {selectedUser.is_online
                              ? "Online now"
                              : `Last seen ${formatDistanceToNow(new Date(selectedUser.last_seen), { addSuffix: true })}`}
                          </span>
                        </div>
                      </div>

                      {selectedUser.bio && (
                        <div>
                          <Label className="text-sm font-medium">Bio</Label>
                          <p className="text-sm text-gray-600 mt-1">{selectedUser.bio}</p>
                        </div>
                      )}

                      <div className="grid grid-cols-2 gap-4 pt-4 border-t">
                        <div className="text-center">
                          <div className="text-2xl font-bold text-blue-600">{selectedUser.total_messages}</div>
                          <div className="text-sm text-gray-600">Messages</div>
                        </div>
                        <div className="text-center">
                          <div className="text-2xl font-bold text-green-600">{selectedUser.total_chats}</div>
                          <div className="text-sm text-gray-600">Chats</div>
                        </div>
                      </div>
                    </TabsContent>

                    <TabsContent value="activity" className="space-y-4">
                      <ScrollArea className="h-64">
                        <div className="space-y-2">
                          {userActivity.length > 0 ? (
                            userActivity.map((activity) => (
                              <div key={activity.id} className="p-3 border rounded-lg">
                                <div className="flex items-center justify-between">
                                  <Badge variant="outline">{activity.action_type}</Badge>
                                  <span className="text-xs text-gray-500">
                                    {formatDistanceToNow(new Date(activity.created_at), { addSuffix: true })}
                                  </span>
                                </div>
                                {activity.details && (
                                  <p className="text-sm text-gray-600 mt-1">{JSON.stringify(activity.details)}</p>
                                )}
                              </div>
                            ))
                          ) : (
                            <p className="text-center text-gray-500 py-4">No activity recorded</p>
                          )}
                        </div>
                      </ScrollArea>
                    </TabsContent>
                  </Tabs>
                )}
              </CardContent>
            </Card>
          ) : (
            <Card>
              <CardContent className="flex items-center justify-center h-64">
                <div className="text-center text-gray-500">
                  <Eye className="h-12 w-12 mx-auto mb-4 opacity-50" />
                  <p>Select a user to view details</p>
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      </div>

      {/* Edit User Dialog */}
      {editingUser && (
        <Dialog open={!!editingUser} onOpenChange={() => setEditingUser(null)}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Edit User</DialogTitle>
              <DialogDescription>Update user profile information</DialogDescription>
            </DialogHeader>
            <div className="space-y-4">
              <div>
                <Label>Username</Label>
                <Input
                  value={editingUser.username || ""}
                  onChange={(e) => setEditingUser({ ...editingUser, username: e.target.value })}
                />
              </div>
              <div>
                <Label>Full Name</Label>
                <Input
                  value={editingUser.full_name || ""}
                  onChange={(e) => setEditingUser({ ...editingUser, full_name: e.target.value })}
                />
              </div>
              <div>
                <Label>Phone</Label>
                <Input
                  value={editingUser.phone || ""}
                  onChange={(e) => setEditingUser({ ...editingUser, phone: e.target.value })}
                />
              </div>
              <div>
                <Label>Bio</Label>
                <Textarea
                  value={editingUser.bio || ""}
                  onChange={(e) => setEditingUser({ ...editingUser, bio: e.target.value })}
                />
              </div>
              <div className="flex space-x-2">
                <Button onClick={() => handleUpdateUser(editingUser)} className="flex-1">
                  Save Changes
                </Button>
                <Button variant="outline" onClick={() => setEditingUser(null)} className="flex-1">
                  Cancel
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      )}
    </div>
  )
}
