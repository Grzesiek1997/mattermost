"use client"

import { useEffect, useState } from "react"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { ChatService } from "@/lib/chat-service"
import type { Chat, User } from "@/lib/supabase"
import { formatDistanceToNow } from "date-fns"
import { MessageCircle, Users, Hash } from "lucide-react"

interface ChatListProps {
  currentUser: User
  selectedChatId?: string
  onChatSelect: (chatId: string) => void
}

interface ChatWithDetails extends Chat {
  created_by_user?: User
  member_count?: number
  last_message?: {
    content: string
    created_at: string
    user: User
  }
}

export function ChatList({ currentUser, selectedChatId, onChatSelect }: ChatListProps) {
  const [chats, setChats] = useState<ChatWithDetails[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadChats()
  }, [currentUser.id])

  const loadChats = async () => {
    try {
      const data = await ChatService.getUserChats(currentUser.id)
      const chatsWithDetails = data.map((member: any) => ({
        ...member.chats,
        created_by_user: member.chats.created_by_user,
      }))
      setChats(chatsWithDetails)
    } catch (error) {
      console.error("Error loading chats:", error)
    } finally {
      setLoading(false)
    }
  }

  const getChatTitle = (chat: ChatWithDetails) => {
    if (chat.title) return chat.title
    if (chat.type === "direct") {
      return chat.created_by_user?.full_name || chat.created_by_user?.username || "Direct Message"
    }
    return "Unnamed Chat"
  }

  const getChatIcon = (chat: ChatWithDetails) => {
    switch (chat.type) {
      case "direct":
        return <MessageCircle className="h-4 w-4" />
      case "group":
        return <Users className="h-4 w-4" />
      case "channel":
        return <Hash className="h-4 w-4" />
      default:
        return <MessageCircle className="h-4 w-4" />
    }
  }

  if (loading) {
    return (
      <div className="p-4">
        <div className="space-y-3">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="flex items-center space-x-3 animate-pulse">
              <div className="w-10 h-10 bg-gray-200 rounded-full" />
              <div className="flex-1 space-y-2">
                <div className="h-4 bg-gray-200 rounded w-3/4" />
                <div className="h-3 bg-gray-200 rounded w-1/2" />
              </div>
            </div>
          ))}
        </div>
      </div>
    )
  }

  return (
    <ScrollArea className="h-full">
      <div className="p-2 space-y-1">
        {chats.map((chat) => (
          <div
            key={chat.id}
            className={`flex items-center space-x-3 p-3 rounded-lg cursor-pointer transition-colors hover:bg-gray-100 ${
              selectedChatId === chat.id ? "bg-blue-50 border-l-4 border-blue-500" : ""
            }`}
            onClick={() => onChatSelect(chat.id)}
          >
            <div className="relative">
              <Avatar className="h-10 w-10">
                <AvatarImage src={chat.avatar_url || chat.created_by_user?.avatar_url} />
                <AvatarFallback>{getChatTitle(chat).charAt(0).toUpperCase()}</AvatarFallback>
              </Avatar>
              {chat.created_by_user?.is_online && chat.type === "direct" && (
                <div className="absolute -bottom-1 -right-1 w-3 h-3 bg-green-500 rounded-full border-2 border-white" />
              )}
            </div>

            <div className="flex-1 min-w-0">
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-2">
                  {getChatIcon(chat)}
                  <h3 className="font-medium text-sm truncate">{getChatTitle(chat)}</h3>
                </div>
                <span className="text-xs text-gray-500">
                  {formatDistanceToNow(new Date(chat.last_message_at), { addSuffix: true })}
                </span>
              </div>

              {chat.last_message && (
                <p className="text-sm text-gray-600 truncate">
                  {chat.last_message.user.username}: {chat.last_message.content}
                </p>
              )}

              {chat.type !== "direct" && (
                <div className="flex items-center space-x-2 mt-1">
                  <Badge variant="secondary" className="text-xs">
                    {chat.type}
                  </Badge>
                  {chat.member_count && <span className="text-xs text-gray-500">{chat.member_count} members</span>}
                </div>
              )}
            </div>
          </div>
        ))}

        {chats.length === 0 && (
          <div className="text-center py-8 text-gray-500">
            <MessageCircle className="h-12 w-12 mx-auto mb-4 opacity-50" />
            <p>No chats yet</p>
            <p className="text-sm">Start a conversation!</p>
          </div>
        )}
      </div>
    </ScrollArea>
  )
}
