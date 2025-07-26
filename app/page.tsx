"use client"

import { useEffect, useState } from "react"
import { AuthForm } from "@/components/auth/auth-form"
import { ChatList } from "@/components/chat/chat-list"
import { ChatWindow } from "@/components/chat/chat-window"
import { NewChatDialog } from "@/components/chat/new-chat-dialog"
import { SettingsDialog } from "@/components/settings/settings-dialog"
import { SupabaseSetupGuide } from "@/components/setup/supabase-setup-guide"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { AuthService } from "@/lib/auth"
import { useRealtimePresence } from "@/hooks/use-realtime"
import { SUPABASE_READY } from "@/lib/supabase"
import type { User, Chat } from "@/lib/supabase"
import { LogOut, Moon, Sun, Bell } from "lucide-react"
import { toast } from "@/hooks/use-toast"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { ContactsManager } from "@/components/contacts/contacts-manager"

export default function Home() {
  const [currentUser, setCurrentUser] = useState<User | null>(null)
  const [selectedChat, setSelectedChat] = useState<Chat | null>(null)
  const [loading, setLoading] = useState(true)
  const [darkMode, setDarkMode] = useState(false)
  const onlineUsers = useRealtimePresence()

  useEffect(() => {
    checkAuth()
  }, [])

  const checkAuth = async () => {
    try {
      const user = await AuthService.getCurrentUser()
      setCurrentUser(user)
    } catch (error) {
      console.error("Auth check failed:", error)
    } finally {
      setLoading(false)
    }
  }

  const handleSignOut = async () => {
    try {
      await AuthService.signOut()
      setCurrentUser(null)
      setSelectedChat(null)
      toast({
        title: "Signed out",
        description: "You have been signed out successfully.",
      })
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message,
        variant: "destructive",
      })
    }
  }

  const handleChatSelect = async (chatId: string) => {
    try {
      // In a real app, you'd fetch the chat details
      // For now, we'll create a minimal chat object
      const chat: Chat = {
        id: chatId,
        type: "group",
        title: "Loading...",
        created_by: currentUser!.id,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        last_message_at: new Date().toISOString(),
      }
      setSelectedChat(chat)
    } catch (error) {
      console.error("Error selecting chat:", error)
    }
  }

  const handleUserUpdate = (updatedUser: User) => {
    setCurrentUser(updatedUser)
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500" />
      </div>
    )
  }

  // Show setup guide if Supabase is not configured
  if (!SUPABASE_READY) {
    return <SupabaseSetupGuide />
  }

  if (!currentUser) {
    return <AuthForm onAuthSuccess={checkAuth} />
  }

  return (
    <div className={`flex h-screen bg-gray-100 ${darkMode ? "dark" : ""}`}>
      {/* Sidebar */}
      <div className="w-80 bg-white border-r flex flex-col">
        {/* User header */}
        <div className="p-4 border-b bg-gray-50">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-3">
              <div className="relative">
                <Avatar className="h-10 w-10">
                  <AvatarImage src={currentUser.avatar_url || "/placeholder.svg"} />
                  <AvatarFallback>
                    {currentUser.full_name?.charAt(0) || currentUser.username?.charAt(0) || "U"}
                  </AvatarFallback>
                </Avatar>
                <div className="absolute -bottom-1 -right-1 w-3 h-3 bg-green-500 rounded-full border-2 border-white" />
              </div>
              <div className="flex-1 min-w-0">
                <h2 className="font-semibold text-lg truncate">{currentUser.full_name || currentUser.username}</h2>
                <div className="flex items-center space-x-2">
                  <Badge variant="secondary" className="text-xs">
                    @{currentUser.username}
                  </Badge>
                  <span className="text-xs text-gray-500">{onlineUsers.length} online</span>
                </div>
              </div>
            </div>

            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <SettingsDialog currentUser={currentUser} onUserUpdate={handleUserUpdate} />
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem onClick={() => setDarkMode(!darkMode)}>
                  {darkMode ? <Sun className="h-4 w-4 mr-2" /> : <Moon className="h-4 w-4 mr-2" />}
                  {darkMode ? "Light Mode" : "Dark Mode"}
                </DropdownMenuItem>
                <DropdownMenuItem>
                  <Bell className="h-4 w-4 mr-2" />
                  Notifications
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={handleSignOut} className="text-red-600">
                  <LogOut className="h-4 w-4 mr-2" />
                  Sign Out
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>

        {/* Search and New Chat */}
        <div className="p-4 space-y-3">
          <ContactsManager currentUser={currentUser} onStartChat={handleChatSelect} />
          <NewChatDialog onChatCreated={(chat) => setSelectedChat(chat)} />
        </div>

        <Separator />

        {/* Chat list */}
        <div className="flex-1 overflow-hidden">
          <ChatList currentUser={currentUser} selectedChatId={selectedChat?.id} onChatSelect={handleChatSelect} />
        </div>
      </div>

      {/* Main chat area */}
      <div className="flex-1 flex flex-col">
        {selectedChat ? (
          <ChatWindow chat={selectedChat} currentUser={currentUser} />
        ) : (
          <div className="flex-1 flex items-center justify-center bg-gray-50">
            <div className="text-center">
              <div className="text-6xl mb-4">💬</div>
              <h2 className="text-2xl font-semibold text-gray-700 mb-2">Welcome to Telegram Clone</h2>
              <p className="text-gray-500 mb-6">Select a chat to start messaging or create a new one</p>
              <NewChatDialog onChatCreated={(chat) => setSelectedChat(chat)} />
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
