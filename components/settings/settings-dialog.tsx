"use client"

import type React from "react"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { AuthService } from "@/lib/auth"
import { supabase } from "@/lib/supabase"
import type { User } from "@/lib/supabase"
import { Settings, UserIcon, Shield, Bell, Key, Eye, EyeOff } from "lucide-react"
import { toast } from "@/hooks/use-toast"

interface SettingsDialogProps {
  currentUser: User
  onUserUpdate: (user: User) => void
}

export function SettingsDialog({ currentUser, onUserUpdate }: SettingsDialogProps) {
  const [open, setOpen] = useState(false)
  const [loading, setLoading] = useState(false)
  const [passwordLoading, setPasswordLoading] = useState(false)
  const [showCurrentPassword, setShowCurrentPassword] = useState(false)
  const [showNewPassword, setShowNewPassword] = useState(false)

  const [profileData, setProfileData] = useState({
    username: currentUser.username || "",
    full_name: currentUser.full_name || "",
    bio: currentUser.bio || "",
    phone: currentUser.phone || "",
  })

  const [passwordData, setPasswordData] = useState({
    currentPassword: "",
    newPassword: "",
    confirmPassword: "",
  })

  const [privacySettings, setPrivacySettings] = useState({
    findByUsername: "everyone",
    whoCanMessage: "contacts",
    lastSeen: "contacts",
  })

  const [notificationSettings, setNotificationSettings] = useState({
    messageNotifications: true,
    contactInvitations: true,
    groupMentions: true,
    soundEnabled: true,
  })

  const handleProfileUpdate = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)

    try {
      const updatedUser = await AuthService.updateProfile(currentUser.id, {
        username: profileData.username.trim(),
        full_name: profileData.full_name.trim(),
        bio: profileData.bio.trim(),
        phone: profileData.phone.trim() || null,
      })

      onUserUpdate(updatedUser)
      toast({
        title: "Profile updated!",
        description: "Your profile has been updated successfully.",
      })
    } catch (error: any) {
      toast({
        title: "Update failed",
        description: error.message,
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  const handlePasswordChange = async (e: React.FormEvent) => {
    e.preventDefault()
    setPasswordLoading(true)

    try {
      if (passwordData.newPassword !== passwordData.confirmPassword) {
        throw new Error("New passwords do not match")
      }

      if (passwordData.newPassword.length < 6) {
        throw new Error("New password must be at least 6 characters long")
      }

      const { error } = await supabase.auth.updateUser({
        password: passwordData.newPassword,
      })

      if (error) throw error

      setPasswordData({
        currentPassword: "",
        newPassword: "",
        confirmPassword: "",
      })

      toast({
        title: "Password updated!",
        description: "Your password has been changed successfully.",
      })
    } catch (error: any) {
      toast({
        title: "Password change failed",
        description: error.message,
        variant: "destructive",
      })
    } finally {
      setPasswordLoading(false)
    }
  }

  const handlePrivacyUpdate = async () => {
    try {
      // In a real app, you would save these to a user_settings table
      toast({
        title: "Privacy settings updated!",
        description: "Your privacy preferences have been saved.",
      })
    } catch (error: any) {
      toast({
        title: "Update failed",
        description: error.message,
        variant: "destructive",
      })
    }
  }

  const handleNotificationUpdate = async () => {
    try {
      // In a real app, you would save these to a user_settings table
      toast({
        title: "Notification settings updated!",
        description: "Your notification preferences have been saved.",
      })
    } catch (error: any) {
      toast({
        title: "Update failed",
        description: error.message,
        variant: "destructive",
      })
    }
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="ghost">
          <Settings className="h-4 w-4" />
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[700px] max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Settings</DialogTitle>
          <DialogDescription>Manage your account settings and preferences</DialogDescription>
        </DialogHeader>

        <Tabs defaultValue="profile" className="w-full">
          <TabsList className="grid w-full grid-cols-4">
            <TabsTrigger value="profile">
              <UserIcon className="h-4 w-4 mr-2" />
              Profile
            </TabsTrigger>
            <TabsTrigger value="security">
              <Key className="h-4 w-4 mr-2" />
              Security
            </TabsTrigger>
            <TabsTrigger value="privacy">
              <Shield className="h-4 w-4 mr-2" />
              Privacy
            </TabsTrigger>
            <TabsTrigger value="notifications">
              <Bell className="h-4 w-4 mr-2" />
              Notifications
            </TabsTrigger>
          </TabsList>

          <TabsContent value="profile" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>Profile Information</CardTitle>
                <CardDescription>Update your profile information and how others can find you</CardDescription>
              </CardHeader>
              <CardContent>
                <form onSubmit={handleProfileUpdate} className="space-y-4">
                  <div className="flex items-center space-x-4">
                    <Avatar className="h-20 w-20">
                      <AvatarImage src={currentUser.avatar_url || "/placeholder.svg"} />
                      <AvatarFallback className="text-lg">
                        {currentUser.full_name?.charAt(0) || currentUser.username?.charAt(0) || "U"}
                      </AvatarFallback>
                    </Avatar>
                    <div>
                      <Button type="button" variant="outline" size="sm">
                        Change Photo
                      </Button>
                      <p className="text-sm text-gray-500 mt-1">JPG, PNG or GIF. Max size 2MB.</p>
                    </div>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div className="space-y-2">
                      <Label htmlFor="username">Username *</Label>
                      <Input
                        id="username"
                        placeholder="Enter username"
                        value={profileData.username}
                        onChange={(e) => setProfileData((prev) => ({ ...prev, username: e.target.value }))}
                        required
                      />
                      <p className="text-xs text-gray-500">Others can find you by this username</p>
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="full_name">Full Name</Label>
                      <Input
                        id="full_name"
                        placeholder="Enter full name"
                        value={profileData.full_name}
                        onChange={(e) => setProfileData((prev) => ({ ...prev, full_name: e.target.value }))}
                      />
                    </div>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="bio">Bio</Label>
                    <Textarea
                      id="bio"
                      placeholder="Tell others about yourself"
                      value={profileData.bio}
                      onChange={(e) => setProfileData((prev) => ({ ...prev, bio: e.target.value }))}
                      rows={3}
                      maxLength={150}
                    />
                    <p className="text-xs text-gray-500">{profileData.bio.length}/150 characters</p>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="phone">Phone Number</Label>
                    <Input
                      id="phone"
                      type="tel"
                      placeholder="Enter phone number"
                      value={profileData.phone}
                      onChange={(e) => setProfileData((prev) => ({ ...prev, phone: e.target.value }))}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label>Email</Label>
                    <Input value={currentUser.email} disabled />
                    <p className="text-xs text-gray-500">Contact support to change your email address</p>
                  </div>

                  <Button type="submit" disabled={loading} className="w-full">
                    {loading ? "Updating..." : "Update Profile"}
                  </Button>
                </form>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="security" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>Change Password</CardTitle>
                <CardDescription>Update your account password for better security</CardDescription>
              </CardHeader>
              <CardContent>
                <form onSubmit={handlePasswordChange} className="space-y-4">
                  <div className="space-y-2">
                    <Label htmlFor="newPassword">New Password</Label>
                    <div className="relative">
                      <Input
                        id="newPassword"
                        type={showNewPassword ? "text" : "password"}
                        placeholder="Enter new password"
                        value={passwordData.newPassword}
                        onChange={(e) => setPasswordData((prev) => ({ ...prev, newPassword: e.target.value }))}
                        required
                        minLength={6}
                      />
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        className="absolute right-0 top-0 h-full px-3 py-2 hover:bg-transparent"
                        onClick={() => setShowNewPassword(!showNewPassword)}
                      >
                        {showNewPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                      </Button>
                    </div>
                    <p className="text-xs text-gray-500">Password must be at least 6 characters long</p>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="confirmPassword">Confirm New Password</Label>
                    <Input
                      id="confirmPassword"
                      type="password"
                      placeholder="Confirm new password"
                      value={passwordData.confirmPassword}
                      onChange={(e) => setPasswordData((prev) => ({ ...prev, confirmPassword: e.target.value }))}
                      required
                      minLength={6}
                    />
                  </div>

                  <Button type="submit" disabled={passwordLoading} className="w-full">
                    {passwordLoading ? "Updating Password..." : "Change Password"}
                  </Button>
                </form>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="privacy" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>Privacy Settings</CardTitle>
                <CardDescription>Control who can find and contact you</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="space-y-2">
                  <Label>Who can find me by username</Label>
                  <Select
                    value={privacySettings.findByUsername}
                    onValueChange={(value) => setPrivacySettings((prev) => ({ ...prev, findByUsername: value }))}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="everyone">Everyone</SelectItem>
                      <SelectItem value="contacts">My Contacts</SelectItem>
                      <SelectItem value="nobody">Nobody</SelectItem>
                    </SelectContent>
                  </Select>
                  <p className="text-sm text-gray-500">Allow others to find you by your username</p>
                </div>

                <div className="space-y-2">
                  <Label>Who can send me messages</Label>
                  <Select
                    value={privacySettings.whoCanMessage}
                    onValueChange={(value) => setPrivacySettings((prev) => ({ ...prev, whoCanMessage: value }))}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="everyone">Everyone</SelectItem>
                      <SelectItem value="contacts">My Contacts</SelectItem>
                      <SelectItem value="nobody">Nobody</SelectItem>
                    </SelectContent>
                  </Select>
                  <p className="text-sm text-gray-500">Control who can start a conversation with you</p>
                </div>

                <div className="space-y-2">
                  <Label>Last seen visibility</Label>
                  <Select
                    value={privacySettings.lastSeen}
                    onValueChange={(value) => setPrivacySettings((prev) => ({ ...prev, lastSeen: value }))}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="everyone">Everyone</SelectItem>
                      <SelectItem value="contacts">My Contacts</SelectItem>
                      <SelectItem value="nobody">Nobody</SelectItem>
                    </SelectContent>
                  </Select>
                  <p className="text-sm text-gray-500">Show when you were last online</p>
                </div>

                <Button onClick={handlePrivacyUpdate} className="w-full">
                  Save Privacy Settings
                </Button>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="notifications" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle>Notification Settings</CardTitle>
                <CardDescription>Choose what notifications you want to receive</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="flex items-center justify-between">
                  <div className="space-y-0.5">
                    <Label>Message notifications</Label>
                    <p className="text-sm text-gray-500">Get notified when you receive new messages</p>
                  </div>
                  <Switch
                    checked={notificationSettings.messageNotifications}
                    onCheckedChange={(checked) =>
                      setNotificationSettings((prev) => ({ ...prev, messageNotifications: checked }))
                    }
                  />
                </div>

                <div className="flex items-center justify-between">
                  <div className="space-y-0.5">
                    <Label>Contact invitations</Label>
                    <p className="text-sm text-gray-500">Get notified when someone wants to connect</p>
                  </div>
                  <Switch
                    checked={notificationSettings.contactInvitations}
                    onCheckedChange={(checked) =>
                      setNotificationSettings((prev) => ({ ...prev, contactInvitations: checked }))
                    }
                  />
                </div>

                <div className="flex items-center justify-between">
                  <div className="space-y-0.5">
                    <Label>Group mentions</Label>
                    <p className="text-sm text-gray-500">Get notified when someone mentions you in a group</p>
                  </div>
                  <Switch
                    checked={notificationSettings.groupMentions}
                    onCheckedChange={(checked) =>
                      setNotificationSettings((prev) => ({ ...prev, groupMentions: checked }))
                    }
                  />
                </div>

                <div className="flex items-center justify-between">
                  <div className="space-y-0.5">
                    <Label>Sound notifications</Label>
                    <p className="text-sm text-gray-500">Play sound when receiving notifications</p>
                  </div>
                  <Switch
                    checked={notificationSettings.soundEnabled}
                    onCheckedChange={(checked) =>
                      setNotificationSettings((prev) => ({ ...prev, soundEnabled: checked }))
                    }
                  />
                </div>

                <Button onClick={handleNotificationUpdate} className="w-full">
                  Save Notification Settings
                </Button>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </DialogContent>
    </Dialog>
  )
}
