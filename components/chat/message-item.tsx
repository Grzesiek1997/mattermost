"use client"

import { useState } from "react"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import type { Message, User } from "@/lib/supabase"
import { ChatService } from "@/lib/chat-service"
import { formatDistanceToNow } from "date-fns"
import { Reply, Smile, MoreHorizontal, File, ImageIcon, Mic, Video } from "lucide-react"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"

interface MessageItemProps {
  message: Message
  currentUser: User
  onReply: (message: Message) => void
  isOwn: boolean
}

const EMOJI_LIST = ["👍", "❤️", "😂", "😮", "😢", "😡", "👎"]

export function MessageItem({ message, currentUser, onReply, isOwn }: MessageItemProps) {
  const [showReactions, setShowReactions] = useState(false)

  const handleReaction = async (emoji: string) => {
    try {
      const existingReaction = message.reactions?.find((r) => r.user_id === currentUser.id && r.emoji === emoji)

      if (existingReaction) {
        await ChatService.removeReaction(message.id, emoji)
      } else {
        await ChatService.addReaction(message.id, emoji)
      }
    } catch (error) {
      console.error("Error handling reaction:", error)
    }
    setShowReactions(false)
  }

  const getMessageIcon = () => {
    switch (message.message_type) {
      case "image":
        return <ImageIcon className="h-4 w-4" />
      case "file":
        return <File className="h-4 w-4" />
      case "voice":
        return <Mic className="h-4 w-4" />
      case "video":
        return <Video className="h-4 w-4" />
      default:
        return null
    }
  }

  const renderMessageContent = () => {
    switch (message.message_type) {
      case "image":
        return (
          <div className="space-y-2">
            {message.file_url && (
              <img
                src={message.file_url || "/placeholder.svg"}
                alt={message.file_name || "Image"}
                className="max-w-xs rounded-lg cursor-pointer hover:opacity-90 transition-opacity"
                onClick={() => window.open(message.file_url, "_blank")}
              />
            )}
            {message.content && <p className="text-sm">{message.content}</p>}
          </div>
        )
      case "file":
        return (
          <div className="flex items-center space-x-2 p-3 bg-gray-50 rounded-lg max-w-xs">
            <File className="h-8 w-8 text-blue-500" />
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium truncate">{message.file_name || "File"}</p>
              {message.file_size && (
                <p className="text-xs text-gray-500">{(message.file_size / 1024 / 1024).toFixed(2)} MB</p>
              )}
            </div>
            {message.file_url && (
              <Button size="sm" variant="ghost" onClick={() => window.open(message.file_url, "_blank")}>
                Download
              </Button>
            )}
          </div>
        )
      case "voice":
        return (
          <div className="flex items-center space-x-2 p-3 bg-blue-50 rounded-lg max-w-xs">
            <Mic className="h-6 w-6 text-blue-500" />
            <div className="flex-1">
              <div className="h-8 bg-blue-200 rounded-full flex items-center px-2">
                <div className="text-xs text-blue-700">Voice Message</div>
              </div>
            </div>
            {message.file_url && (
              <audio controls className="max-w-xs">
                <source src={message.file_url} type="audio/mpeg" />
                Your browser does not support the audio element.
              </audio>
            )}
          </div>
        )
      default:
        return <p className="text-sm whitespace-pre-wrap">{message.content}</p>
    }
  }

  const groupedReactions = message.reactions?.reduce(
    (acc, reaction) => {
      if (!acc[reaction.emoji]) {
        acc[reaction.emoji] = []
      }
      acc[reaction.emoji].push(reaction)
      return acc
    },
    {} as Record<string, typeof message.reactions>,
  )

  return (
    <div className={`flex ${isOwn ? "justify-end" : "justify-start"} mb-4 group`}>
      <div className={`flex ${isOwn ? "flex-row-reverse" : "flex-row"} items-start space-x-2 max-w-[70%]`}>
        {!isOwn && (
          <Avatar className="h-8 w-8 mt-1">
            <AvatarImage src={message.user?.avatar_url || "/placeholder.svg"} />
            <AvatarFallback>
              {message.user?.full_name?.charAt(0) || message.user?.username?.charAt(0) || "U"}
            </AvatarFallback>
          </Avatar>
        )}

        <div className={`flex flex-col ${isOwn ? "items-end" : "items-start"}`}>
          {/* Reply indicator */}
          {message.reply_to && (
            <div className="mb-1 p-2 bg-gray-100 rounded-lg text-xs border-l-2 border-blue-500">
              <div className="font-medium text-blue-600">
                {message.reply_to.user?.full_name || message.reply_to.user?.username}
              </div>
              <div className="text-gray-600 truncate max-w-xs">{message.reply_to.content}</div>
            </div>
          )}

          {/* Message bubble */}
          <div
            className={`relative px-4 py-2 rounded-2xl ${
              isOwn ? "bg-blue-500 text-white rounded-br-md" : "bg-gray-100 text-gray-900 rounded-bl-md"
            }`}
          >
            {/* Message type indicator */}
            {getMessageIcon() && (
              <div className="flex items-center space-x-1 mb-1">
                {getMessageIcon()}
                <span className="text-xs opacity-75">{message.message_type}</span>
              </div>
            )}

            {/* Message content */}
            {renderMessageContent()}

            {/* Message info */}
            <div
              className={`flex items-center justify-between mt-1 text-xs ${isOwn ? "text-blue-100" : "text-gray-500"}`}
            >
              <span>{formatDistanceToNow(new Date(message.created_at), { addSuffix: true })}</span>
              {message.is_edited && (
                <Badge variant="secondary" className="text-xs ml-2">
                  edited
                </Badge>
              )}
            </div>

            {/* Action buttons (visible on hover) */}
            <div
              className={`absolute top-0 ${isOwn ? "left-0 -translate-x-full" : "right-0 translate-x-full"} 
              opacity-0 group-hover:opacity-100 transition-opacity flex items-center space-x-1 bg-white 
              rounded-lg shadow-lg p-1 border`}
            >
              <Popover open={showReactions} onOpenChange={setShowReactions}>
                <PopoverTrigger asChild>
                  <Button size="sm" variant="ghost" className="h-8 w-8 p-0">
                    <Smile className="h-4 w-4" />
                  </Button>
                </PopoverTrigger>
                <PopoverContent className="w-auto p-2">
                  <div className="flex space-x-1">
                    {EMOJI_LIST.map((emoji) => (
                      <Button
                        key={emoji}
                        size="sm"
                        variant="ghost"
                        className="h-8 w-8 p-0 text-lg hover:bg-gray-100"
                        onClick={() => handleReaction(emoji)}
                      >
                        {emoji}
                      </Button>
                    ))}
                  </div>
                </PopoverContent>
              </Popover>

              <Button size="sm" variant="ghost" className="h-8 w-8 p-0" onClick={() => onReply(message)}>
                <Reply className="h-4 w-4" />
              </Button>

              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button size="sm" variant="ghost" className="h-8 w-8 p-0">
                    <MoreHorizontal className="h-4 w-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent>
                  <DropdownMenuItem onClick={() => onReply(message)}>Reply</DropdownMenuItem>
                  <DropdownMenuItem onClick={() => navigator.clipboard.writeText(message.content || "")}>
                    Copy
                  </DropdownMenuItem>
                  {isOwn && (
                    <>
                      <DropdownMenuItem>Edit</DropdownMenuItem>
                      <DropdownMenuItem className="text-red-600">Delete</DropdownMenuItem>
                    </>
                  )}
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          </div>

          {/* Reactions */}
          {groupedReactions && Object.keys(groupedReactions).length > 0 && (
            <div className="flex flex-wrap gap-1 mt-1">
              {Object.entries(groupedReactions).map(([emoji, reactions]) => (
                <Button
                  key={emoji}
                  size="sm"
                  variant="outline"
                  className="h-6 px-2 text-xs rounded-full bg-transparent"
                  onClick={() => handleReaction(emoji)}
                >
                  {emoji} {reactions.length}
                </Button>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
