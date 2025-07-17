"use client"

import type React from "react"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ChatService } from "@/lib/chat-service"
import type { Chat } from "@/lib/supabase"
import { Plus, MessageCircle, Users, Hash } from "lucide-react"
import { toast } from "@/hooks/use-toast"

interface NewChatDialogProps {
  onChatCreated: (chat: Chat) => void
}

export function NewChatDialog({ onChatCreated }: NewChatDialogProps) {
  const [open, setOpen] = useState(false)
  const [loading, setLoading] = useState(false)
  const [chatData, setChatData] = useState({
    type: "group" as Chat["type"],
    title: "",
    description: "",
  })

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!chatData.title.trim()) {
      toast({
        title: "Error",
        description: "Please enter a chat title",
        variant: "destructive",
      })
      return
    }

    setLoading(true)

    try {
      const chat = await ChatService.createChat(
        chatData.type,
        chatData.title.trim(),
        chatData.description.trim() || undefined,
      )

      toast({
        title: "Success",
        description: `${chatData.type === "group" ? "Group" : "Channel"} created successfully!`,
      })

      onChatCreated(chat)
      setOpen(false)
      setChatData({ type: "group", title: "", description: "" })
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to create chat",
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  const getChatIcon = (type: Chat["type"]) => {
    switch (type) {
      case "group":
        return <Users className="h-4 w-4" />
      case "channel":
        return <Hash className="h-4 w-4" />
      default:
        return <MessageCircle className="h-4 w-4" />
    }
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button className="w-full" size="sm">
          <Plus className="h-4 w-4 mr-2" />
          New Chat
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <DialogTitle>Create New Chat</DialogTitle>
          <DialogDescription>Create a new group or channel to start chatting with others.</DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="chat-type">Chat Type</Label>
            <Select
              value={chatData.type}
              onValueChange={(value: Chat["type"]) => setChatData((prev) => ({ ...prev, type: value }))}
            >
              <SelectTrigger>
                <SelectValue placeholder="Select chat type" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="group">
                  <div className="flex items-center space-x-2">
                    <Users className="h-4 w-4" />
                    <span>Group Chat</span>
                  </div>
                </SelectItem>
                <SelectItem value="channel">
                  <div className="flex items-center space-x-2">
                    <Hash className="h-4 w-4" />
                    <span>Channel</span>
                  </div>
                </SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="chat-title">{chatData.type === "group" ? "Group" : "Channel"} Name</Label>
            <Input
              id="chat-title"
              placeholder={`Enter ${chatData.type} name`}
              value={chatData.title}
              onChange={(e) => setChatData((prev) => ({ ...prev, title: e.target.value }))}
              required
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="chat-description">Description (Optional)</Label>
            <Textarea
              id="chat-description"
              placeholder={`Describe what this ${chatData.type} is about`}
              value={chatData.description}
              onChange={(e) => setChatData((prev) => ({ ...prev, description: e.target.value }))}
              rows={3}
            />
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={loading}>
              Cancel
            </Button>
            <Button type="submit" disabled={loading}>
              {loading ? (
                <div className="flex items-center space-x-2">
                  <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white" />
                  <span>Creating...</span>
                </div>
              ) : (
                <div className="flex items-center space-x-2">
                  {getChatIcon(chatData.type)}
                  <span>Create {chatData.type === "group" ? "Group" : "Channel"}</span>
                </div>
              )}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
