"use client"

import { useState, useEffect } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { supabase } from "@/lib/supabase"
import type { User } from "@/lib/supabase"
import { MessageSquare, Search, Eye, Trash2, Ban, Users, Calendar, Hash } from "lucide-react"
import { toast } from "@/hooks/use-toast"
import { formatDistanceToNow } from "date-fns"

interface ChatDetails {
  id: string
  type: string
  title: string
  description?: string
  avatar_url?: string
  created_by: string
  created_at: string
  updated_at: string
  last_message_at: string
  member_count: number
  message_count: number
  creator: User
  is_active: boolean
}

interface ChatMember {
  id: string
  user_id: string
  role: string
  joined_at: string
  can_send_messages: boolean
  can_add_members: boolean
  can_delete_messages: boolean
  user: User
}

interface ChatMessage {
  id: string
  content: string
  message_type: string
  created_at: string
  is_deleted: boolean
  user: User
}

interface ChatManagementProps {
  currentUser: User
  adminRole: string
}

export function ChatManagement({ currentUser, adminRole }: ChatManagementProps) {
  const [chats, setChats] = useState<ChatDetails[]>([])
  const [selectedChat, setSelectedChat] = useState<ChatDetails | null>(null)
  const [chatMembers, setChatMembers] = useState<ChatMember[]>([])
  const [chatMessages, setChatMessages] = useState<ChatMessage[]>([])
  const [searchQuery, setSearchQuery] = useState("")
  const [filterType, setFilterType] = useState("all")
  const [loading, setLoading] = useState(true)
  const [detailsLoading, setDetailsLoading] = useState(false)

  useEffect(() => {
    loadChats()
  }, [])

  const loadChats = async () => {
    try {
      setLoading(true)

      // Load chats with creator info and stats
      const { data: chatsData, error } = await supabase
        .from("chats")
        .select(`
          *,
          creator:users!chats_created_by_fkey (id, username, full_name, avatar_url)
        `)
        .order("created_at", { ascending: false })

      if (error) throw error

      // Enhance chat data with member and message counts
      const enhancedChats = await Promise.all(
        (chatsData || []).map(async (chat) => {
          // Get member count
          const { count: memberCount } = await supabase
            .from("chat_members")
            .select("count", { count: "exact", head: true })
            .eq("chat_id", chat.id)

          // Get message count
          const { count: messageCount } = await supabase
            .from("messages")
            .select("count", { count: "exact", head: true })
            .eq("chat_id", chat.id)

          return {
            ...chat,
            member_count: memberCount || 0,
            message_count: messageCount || 0,
            is_active:
              chat.last_message_at && new Date(chat.last_message_at) > new Date(Date.now() - 7 * 24 * 60 * 60 * 1000), // Active if message in last 7 days
          }
        }),
      )

      setChats(enhancedChats)
    } catch (error) {
      console.error("Failed to load chats:", error)
      toast({
        title: "Error",
        description: "Failed to load chats",
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  const loadChatDetails = async (chat: ChatDetails) => {
    try {
      setDetailsLoading(true)
      setSelectedChat(chat)

      // Load chat members
      const { data: membersData, error: membersError } = await supabase
        .from("chat_members")
        .select(`
          *,
          user:users (id, username, full_name, avatar_url, is_online)
        `)
        .eq("chat_id", chat.id)
        .order("joined_at", { ascending: false })

      if (membersError) throw membersError
      setChatMembers(membersData || [])

      // Load recent messages
      const { data: messagesData, error: messagesError } = await supabase
        .from("messages")
        .select(`
          *,
          user:users (id, username, full_name, avatar_url)
        `)
        .eq("chat_id", chat.id)
        .order("created_at", { ascending: false })
        .limit(50)

      if (messagesError) throw messagesError
      setChatMessages(messagesData || [])
    } catch (error) {
      console.error("Failed to load chat details:", error)
      toast({
        title: "Error",
        description: "Failed to load chat details",
        variant: "destructive",
      })
    } finally {
      setDetailsLoading(false)
    }
  }

  const handleDeleteChat = async (chat: ChatDetails) => {
    if (!confirm(`Are you sure you want to delete the chat "${chat.title || "Untitled"}"? This cannot be undone.`)) {
      return
    }

    try {
      const { error } = await supabase.from("chats").delete().eq("id", chat.id)

      if (error) throw error

      // Log admin action
      await supabase.rpc("log_admin_action", {
        action_type_param: "delete_chat",
        target_type_param: "chat",
        target_id_param: chat.id,
        details_param: { chat_title: chat.title, member_count: chat.member_count },
      })

      toast({
        title: "Chat deleted",
        description: `Chat "${chat.title || "Untitled"}" has been deleted`,
      })

      loadChats()
      if (selectedChat?.id === chat.id) {
        setSelectedChat(null)
      }
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to delete chat",
        variant: "destructive",
      })
    }
  }

  const handleRemoveMember = async (chatId: string, memberId: string, username: string) => {
    if (!confirm(`Remove ${username} from this chat?`)) {
      return
    }

    try {
      const { error } = await supabase.from("chat_members").delete().eq("id", memberId)

      if (error) throw error

      toast({
        title: "Member removed",
        description: `${username} has been removed from the chat`,
      })

      // Reload chat details
      if (selectedChat) {
        loadChatDetails(selectedChat)
      }
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to remove member",
        variant: "destructive",
      })
    }
  }

  const handleDeleteMessage = async (messageId: string) => {
    if (!confirm("Delete this message? This cannot be undone.")) {
      return
    }

    try {
      const { error } = await supabase
        .from("messages")
        .update({ is_deleted: true, content: "[Message deleted by admin]" })
        .eq("id", messageId)

      if (error) throw error

      toast({
        title: "Message deleted",
        description: "Message has been deleted",
      })

      // Reload messages
      if (selectedChat) {
        loadChatDetails(selectedChat)
      }
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to delete message",
        variant: "destructive",
      })
    }
  }

  const filteredChats = chats.filter((chat) => {
    const matchesSearch =
      chat.title?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      chat.creator?.username?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      chat.creator?.full_name?.toLowerCase().includes(searchQuery.toLowerCase())

    const matchesType = filterType === "all" || chat.type === filterType

    return matchesSearch && matchesType
  })

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h2 className="text-2xl font-bold flex items-center gap-2">
          <MessageSquare className="h-6 w-6" />
          Chat Management
        </h2>
        <p className="text-gray-600">Monitor and moderate chats and messages</p>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-4">
        <div className="flex items-center space-x-2">
          <Search className="h-4 w-4 text-gray-400" />
          <Input
            placeholder="Search chats..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-64"
          />
        </div>

        <Select value={filterType} onValueChange={setFilterType}>
          <SelectTrigger className="w-40">
            <SelectValue placeholder="Filter by type" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Types</SelectItem>
            <SelectItem value="direct">Direct</SelectItem>
            <SelectItem value="group">Group</SelectItem>
            <SelectItem value="channel">Channel</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Chats List */}
        <div className="lg:col-span-2">
          <Card>
            <CardHeader>
              <CardTitle>Chats ({filteredChats.length})</CardTitle>
            </CardHeader>
            <CardContent>
              <ScrollArea className="h-[600px]">
                <div className="space-y-2">
                  {loading ? (
                    <div className="flex justify-center py-8">
                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500" />
                    </div>
                  ) : (
                    filteredChats.map((chat) => (
                      <div
                        key={chat.id}
                        className={`flex items-center justify-between p-4 border rounded-lg hover:bg-gray-50 cursor-pointer ${
                          selectedChat?.id === chat.id ? "bg-blue-50 border-blue-200" : ""
                        }`}
                        onClick={() => loadChatDetails(chat)}
                      >
                        <div className="flex items-center space-x-3">
                          <Avatar className="h-10 w-10">
                            <AvatarImage src={chat.avatar_url || "/placeholder.svg"} />
                            <AvatarFallback>
                              {chat.type === "group" ? (
                                <Users className="h-5 w-5" />
                              ) : (
                                <MessageSquare className="h-5 w-5" />
                              )}
                            </AvatarFallback>
                          </Avatar>
                          <div>
                            <div className="flex items-center space-x-2">
                              <span className="font-medium">{chat.title || `${chat.type} chat`}</span>
                              <Badge variant="outline" className="text-xs">
                                {chat.type}
                              </Badge>
                              {chat.is_active && (
                                <Badge className="text-xs bg-green-500 hover:bg-green-500">Active</Badge>
                              )}
                            </div>
                            <p className="text-sm text-gray-600">
                              Created by {chat.creator?.full_name || chat.creator?.username}
                            </p>
                            <div className="flex items-center space-x-4 text-xs text-gray-500">
                              <span>{chat.member_count} members</span>
                              <span>{chat.message_count} messages</span>
                              <span>Created {formatDistanceToNow(new Date(chat.created_at), { addSuffix: true })}</span>
                            </div>
                          </div>
                        </div>

                        <div className="flex items-center space-x-1">
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={(e) => {
                              e.stopPropagation()
                              loadChatDetails(chat)
                            }}
                          >
                            <Eye className="h-4 w-4" />
                          </Button>
                          <Button
                            size="sm"
                            variant="destructive"
                            onClick={(e) => {
                              e.stopPropagation()
                              handleDeleteChat(chat)
                            }}
                          >
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </ScrollArea>
            </CardContent>
          </Card>
        </div>

        {/* Chat Details */}
        <div>
          {selectedChat ? (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center justify-between">
                  Chat Details
                  <Button size="sm" variant="destructive" onClick={() => handleDeleteChat(selectedChat)}>
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </CardTitle>
              </CardHeader>
              <CardContent>
                {detailsLoading ? (
                  <div className="flex justify-center py-8">
                    <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-500" />
                  </div>
                ) : (
                  <Tabs defaultValue="info" className="space-y-4">
                    <TabsList className="grid w-full grid-cols-3">
                      <TabsTrigger value="info">Info</TabsTrigger>
                      <TabsTrigger value="members">Members</TabsTrigger>
                      <TabsTrigger value="messages">Messages</TabsTrigger>
                    </TabsList>

                    <TabsContent value="info" className="space-y-4">
                      <div className="text-center">
                        <Avatar className="h-16 w-16 mx-auto mb-4">
                          <AvatarImage src={selectedChat.avatar_url || "/placeholder.svg"} />
                          <AvatarFallback className="text-lg">
                            {selectedChat.type === "group" ? (
                              <Users className="h-8 w-8" />
                            ) : (
                              <MessageSquare className="h-8 w-8" />
                            )}
                          </AvatarFallback>
                        </Avatar>
                        <h3 className="font-semibold text-lg">{selectedChat.title || `${selectedChat.type} chat`}</h3>
                        <Badge variant="outline" className="mt-2">
                          {selectedChat.type}
                        </Badge>
                      </div>

                      <div className="space-y-3">
                        <div className="flex items-center space-x-2">
                          <Hash className="h-4 w-4 text-gray-400" />
                          <span className="text-sm">ID: {selectedChat.id.slice(0, 8)}...</span>
                        </div>
                        <div className="flex items-center space-x-2">
                          <Users className="h-4 w-4 text-gray-400" />
                          <span className="text-sm">
                            Created by {selectedChat.creator?.full_name || selectedChat.creator?.username}
                          </span>
                        </div>
                        <div className="flex items-center space-x-2">
                          <Calendar className="h-4 w-4 text-gray-400" />
                          <span className="text-sm">
                            Created {formatDistanceToNow(new Date(selectedChat.created_at), { addSuffix: true })}
                          </span>
                        </div>
                      </div>

                      {selectedChat.description && (
                        <div>
                          <Label className="text-sm font-medium">Description</Label>
                          <p className="text-sm text-gray-600 mt-1">{selectedChat.description}</p>
                        </div>
                      )}

                      <div className="grid grid-cols-2 gap-4 pt-4 border-t">
                        <div className="text-center">
                          <div className="text-2xl font-bold text-blue-600">{selectedChat.member_count}</div>
                          <div className="text-sm text-gray-600">Members</div>
                        </div>
                        <div className="text-center">
                          <div className="text-2xl font-bold text-green-600">{selectedChat.message_count}</div>
                          <div className="text-sm text-gray-600">Messages</div>
                        </div>
                      </div>
                    </TabsContent>

                    <TabsContent value="members" className="space-y-4">
                      <ScrollArea className="h-64">
                        <div className="space-y-2">
                          {chatMembers.map((member) => (
                            <div key={member.id} className="flex items-center justify-between p-2 border rounded">
                              <div className="flex items-center space-x-2">
                                <div className="relative">
                                  <Avatar className="h-8 w-8">
                                    <AvatarImage src={member.user?.avatar_url || "/placeholder.svg"} />
                                    <AvatarFallback className="text-xs">
                                      {member.user?.full_name?.charAt(0) || member.user?.username?.charAt(0) || "U"}
                                    </AvatarFallback>
                                  </Avatar>
                                  {member.user?.is_online && (
                                    <div className="absolute -bottom-1 -right-1 w-2 h-2 bg-green-500 rounded-full border border-white" />
                                  )}
                                </div>
                                <div>
                                  <div className="text-sm font-medium">
                                    {member.user?.full_name || member.user?.username}
                                  </div>
                                  <div className="flex items-center space-x-1">
                                    <Badge variant="outline" className="text-xs">
                                      {member.role}
                                    </Badge>
                                    <span className="text-xs text-gray-500">
                                      Joined {formatDistanceToNow(new Date(member.joined_at), { addSuffix: true })}
                                    </span>
                                  </div>
                                </div>
                              </div>
                              {member.role !== "owner" && (
                                <Button
                                  size="sm"
                                  variant="outline"
                                  onClick={() =>
                                    handleRemoveMember(selectedChat.id, member.id, member.user?.username || "User")
                                  }
                                >
                                  <Ban className="h-3 w-3" />
                                </Button>
                              )}
                            </div>
                          ))}
                        </div>
                      </ScrollArea>
                    </TabsContent>

                    <TabsContent value="messages" className="space-y-4">
                      <ScrollArea className="h-64">
                        <div className="space-y-2">
                          {chatMessages.map((message) => (
                            <div key={message.id} className="p-2 border rounded">
                              <div className="flex items-center justify-between mb-1">
                                <div className="flex items-center space-x-2">
                                  <Avatar className="h-6 w-6">
                                    <AvatarImage src={message.user?.avatar_url || "/placeholder.svg"} />
                                    <AvatarFallback className="text-xs">
                                      {message.user?.full_name?.charAt(0) || message.user?.username?.charAt(0) || "U"}
                                    </AvatarFallback>
                                  </Avatar>
                                  <span className="text-sm font-medium">
                                    {message.user?.full_name || message.user?.username}
                                  </span>
                                  <span className="text-xs text-gray-500">
                                    {formatDistanceToNow(new Date(message.created_at), { addSuffix: true })}
                                  </span>
                                </div>
                                {!message.is_deleted && (
                                  <Button size="sm" variant="ghost" onClick={() => handleDeleteMessage(message.id)}>
                                    <Trash2 className="h-3 w-3" />
                                  </Button>
                                )}
                              </div>
                              <p className={`text-sm ${message.is_deleted ? "text-gray-500 italic" : ""}`}>
                                {message.content}
                              </p>
                              {message.message_type !== "text" && (
                                <Badge variant="outline" className="text-xs mt-1">
                                  {message.message_type}
                                </Badge>
                              )}
                            </div>
                          ))}
                          {chatMessages.length === 0 && (
                            <p className="text-center text-gray-500 py-4">No messages in this chat</p>
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
                  <MessageSquare className="h-12 w-12 mx-auto mb-4 opacity-50" />
                  <p>Select a chat to view details</p>
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      </div>
    </div>
  )
}
