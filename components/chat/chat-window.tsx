"use client"

import { useEffect, useState, useRef } from "react"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { MessageItem } from "./message-item"
import { MessageInput } from "./message-input"
import { ChatService } from "@/lib/chat-service"
import { useRealtimeMessages } from "@/hooks/use-realtime"
import type { Chat, Message, User } from "@/lib/supabase"
import { Phone, Video, MoreVertical, Search, Users } from "lucide-react"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"

interface ChatWindowProps {
  chat: Chat
  currentUser: User
}

export function ChatWindow({ chat, currentUser }: ChatWindowProps) {
  const [replyTo, setReplyTo] = useState<Message | undefined>()
  const [loading, setLoading] = useState(true)
  const scrollAreaRef = useRef<HTMLDivElement>(null)
  const { messages, setMessages, typingUsers } = useRealtimeMessages(chat.id)

  useEffect(() => {
    loadMessages()
  }, [chat.id])

  useEffect(() => {
    // Auto-scroll to bottom when new messages arrive
    if (scrollAreaRef.current) {
      const scrollElement = scrollAreaRef.current.querySelector("[data-radix-scroll-area-viewport]")
      if (scrollElement) {
        scrollElement.scrollTop = scrollElement.scrollHeight
      }
    }
  }, [messages])

  const loadMessages = async () => {
    try {
      setLoading(true)
      const data = await ChatService.getChatMessages(chat.id)
      setMessages(data)
    } catch (error) {
      console.error("Error loading messages:", error)
    } finally {
      setLoading(false)
    }
  }

  const getChatTitle = () => {
    if (chat.title) return chat.title
    if (chat.type === "direct") {
      return "Direct Message"
    }
    return "Chat"
  }

  const getTypingText = () => {
    const otherTypingUsers = typingUsers.filter((t) => t.user_id !== currentUser.id)
    if (otherTypingUsers.length === 0) return null

    if (otherTypingUsers.length === 1) {
      return `${otherTypingUsers[0].user?.full_name || otherTypingUsers[0].user?.username} is typing...`
    }

    return `${otherTypingUsers.length} people are typing...`
  }

  return (
    <div className="flex flex-col h-full bg-white">
      {/* Chat header */}
      <div className="flex items-center justify-between p-4 border-b bg-gray-50">
        <div className="flex items-center space-x-3">
          <Avatar className="h-10 w-10">
            <AvatarImage src={chat.avatar_url || "/placeholder.svg"} />
            <AvatarFallback>{getChatTitle().charAt(0).toUpperCase()}</AvatarFallback>
          </Avatar>
          <div>
            <h2 className="font-semibold text-lg">{getChatTitle()}</h2>
            <div className="flex items-center space-x-2">
              <Badge variant="secondary" className="text-xs">
                {chat.type}
              </Badge>
              {getTypingText() && <span className="text-sm text-green-600 animate-pulse">{getTypingText()}</span>}
            </div>
          </div>
        </div>

        <div className="flex items-center space-x-2">
          <Button size="sm" variant="ghost">
            <Search className="h-4 w-4" />
          </Button>
          <Button size="sm" variant="ghost">
            <Phone className="h-4 w-4" />
          </Button>
          <Button size="sm" variant="ghost">
            <Video className="h-4 w-4" />
          </Button>
          {chat.type !== "direct" && (
            <Button size="sm" variant="ghost">
              <Users className="h-4 w-4" />
            </Button>
          )}

          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button size="sm" variant="ghost">
                <MoreVertical className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent>
              <DropdownMenuItem>Chat Info</DropdownMenuItem>
              <DropdownMenuItem>Search Messages</DropdownMenuItem>
              <DropdownMenuItem>Export Chat</DropdownMenuItem>
              {chat.type !== "direct" && (
                <>
                  <DropdownMenuItem>Manage Members</DropdownMenuItem>
                  <DropdownMenuItem>Chat Settings</DropdownMenuItem>
                </>
              )}
              <DropdownMenuItem className="text-red-600">Leave Chat</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>

      {/* Messages area */}
      <ScrollArea className="flex-1 p-4" ref={scrollAreaRef}>
        {loading ? (
          <div className="space-y-4">
            {[...Array(5)].map((_, i) => (
              <div key={i} className="flex items-start space-x-3 animate-pulse">
                <div className="w-8 h-8 bg-gray-200 rounded-full" />
                <div className="flex-1 space-y-2">
                  <div className="h-4 bg-gray-200 rounded w-3/4" />
                  <div className="h-3 bg-gray-200 rounded w-1/2" />
                </div>
              </div>
            ))}
          </div>
        ) : messages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-gray-500">
            <div className="text-6xl mb-4">💬</div>
            <h3 className="text-lg font-medium mb-2">No messages yet</h3>
            <p className="text-sm text-center">Start the conversation by sending a message below</p>
          </div>
        ) : (
          <div className="space-y-1">
            {messages.map((message) => (
              <MessageItem
                key={message.id}
                message={message}
                currentUser={currentUser}
                onReply={setReplyTo}
                isOwn={message.user_id === currentUser.id}
              />
            ))}
          </div>
        )}
      </ScrollArea>

      {/* Message input */}
      <MessageInput chatId={chat.id} replyTo={replyTo} onClearReply={() => setReplyTo(undefined)} />
    </div>
  )
}
