"use client"

import type React from "react"

import { useState, useRef, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { ChatService } from "@/lib/chat-service"
import type { Message } from "@/lib/supabase"
import { Send, Paperclip, Smile, X } from "lucide-react"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"

interface MessageInputProps {
  chatId: string
  replyTo?: Message
  onClearReply: () => void
}

const EMOJI_LIST = ["😀", "😂", "😍", "🤔", "😢", "😡", "👍", "👎", "❤️", "🔥", "💯", "🎉"]

export function MessageInput({ chatId, replyTo, onClearReply }: MessageInputProps) {
  const [message, setMessage] = useState("")
  const [isTyping, setIsTyping] = useState(false)
  const [isSending, setIsSending] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const typingTimeoutRef = useRef<NodeJS.Timeout>()

  useEffect(() => {
    if (replyTo && inputRef.current) {
      inputRef.current.focus()
    }
  }, [replyTo])

  const handleTyping = async (value: string) => {
    setMessage(value)

    if (!isTyping && value.length > 0) {
      setIsTyping(true)
      await ChatService.updateTypingStatus(chatId, true)
    }

    // Clear existing timeout
    if (typingTimeoutRef.current) {
      clearTimeout(typingTimeoutRef.current)
    }

    // Set new timeout to stop typing indicator
    typingTimeoutRef.current = setTimeout(async () => {
      setIsTyping(false)
      await ChatService.updateTypingStatus(chatId, false)
    }, 2000)
  }

  const handleSend = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!message.trim() || isSending) return

    setIsSending(true)

    try {
      // Stop typing indicator
      if (isTyping) {
        setIsTyping(false)
        await ChatService.updateTypingStatus(chatId, false)
      }

      await ChatService.sendMessage(chatId, message.trim(), "text", replyTo?.id)

      setMessage("")
      onClearReply()

      if (inputRef.current) {
        inputRef.current.focus()
      }
    } catch (error) {
      console.error("Error sending message:", error)
    } finally {
      setIsSending(false)
    }
  }

  const handleFileUpload = async (file: File) => {
    if (!file) return

    setIsSending(true)

    try {
      // In a real app, you'd upload to Supabase Storage or another service
      // For now, we'll simulate file upload
      const fileUrl = URL.createObjectURL(file)
      const messageType = file.type.startsWith("image/") ? "image" : "file"

      await ChatService.sendMessage(
        chatId,
        `Shared ${file.type.startsWith("image/") ? "an image" : "a file"}: ${file.name}`,
        messageType,
        replyTo?.id,
        fileUrl,
        file.name,
        file.size,
      )

      onClearReply()
    } catch (error) {
      console.error("Error uploading file:", error)
    } finally {
      setIsSending(false)
    }
  }

  const insertEmoji = (emoji: string) => {
    const newMessage = message + emoji
    setMessage(newMessage)
    handleTyping(newMessage)

    if (inputRef.current) {
      inputRef.current.focus()
    }
  }

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      handleSend(e)
    }
  }

  return (
    <div className="border-t bg-white p-4">
      {/* Reply indicator */}
      {replyTo && (
        <div className="mb-3 p-3 bg-gray-50 rounded-lg border-l-4 border-blue-500">
          <div className="flex items-center justify-between">
            <div className="flex-1">
              <div className="text-sm font-medium text-blue-600">
                Replying to {replyTo.user?.full_name || replyTo.user?.username}
              </div>
              <div className="text-sm text-gray-600 truncate">{replyTo.content}</div>
            </div>
            <Button size="sm" variant="ghost" onClick={onClearReply} className="h-6 w-6 p-0">
              <X className="h-4 w-4" />
            </Button>
          </div>
        </div>
      )}

      {/* Message input */}
      <form onSubmit={handleSend} className="flex items-end space-x-2">
        <div className="flex space-x-1">
          {/* File upload */}
          <input
            ref={fileInputRef}
            type="file"
            className="hidden"
            onChange={(e) => {
              const file = e.target.files?.[0]
              if (file) {
                handleFileUpload(file)
              }
            }}
            accept="image/*,video/*,audio/*,.pdf,.doc,.docx,.txt"
          />
          <Button
            type="button"
            size="sm"
            variant="ghost"
            onClick={() => fileInputRef.current?.click()}
            disabled={isSending}
          >
            <Paperclip className="h-4 w-4" />
          </Button>

          {/* Emoji picker */}
          <Popover>
            <PopoverTrigger asChild>
              <Button type="button" size="sm" variant="ghost" disabled={isSending}>
                <Smile className="h-4 w-4" />
              </Button>
            </PopoverTrigger>
            <PopoverContent className="w-auto p-2">
              <div className="grid grid-cols-6 gap-1">
                {EMOJI_LIST.map((emoji) => (
                  <Button
                    key={emoji}
                    type="button"
                    size="sm"
                    variant="ghost"
                    className="h-8 w-8 p-0 text-lg hover:bg-gray-100"
                    onClick={() => insertEmoji(emoji)}
                  >
                    {emoji}
                  </Button>
                ))}
              </div>
            </PopoverContent>
          </Popover>
        </div>

        {/* Message input field */}
        <div className="flex-1">
          <Input
            ref={inputRef}
            value={message}
            onChange={(e) => handleTyping(e.target.value)}
            onKeyPress={handleKeyPress}
            placeholder="Type a message..."
            disabled={isSending}
            className="resize-none"
          />
        </div>

        {/* Send button */}
        <Button type="submit" size="sm" disabled={!message.trim() || isSending} className="px-4">
          {isSending ? (
            <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white" />
          ) : (
            <Send className="h-4 w-4" />
          )}
        </Button>
      </form>

      {/* Typing indicator */}
      {isTyping && (
        <div className="mt-2">
          <Badge variant="secondary" className="text-xs">
            Typing...
          </Badge>
        </div>
      )}
    </div>
  )
}
