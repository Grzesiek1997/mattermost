import { supabase } from "./supabase"
import type { RealtimeChannel } from "@supabase/supabase-js"

export interface Message {
  id: string
  conversation_id: string
  sender_id: string
  content: string
  message_type: "text" | "image" | "file" | "audio" | "video"
  reply_to_id?: string
  is_edited: boolean
  is_deleted: boolean
  created_at: string
  updated_at: string
  sender?: {
    id: string
    username: string
    full_name: string
    avatar_url: string
  }
}

export interface TypingUser {
  user_id: string
  username: string
  full_name: string
}

export interface UserPresence {
  user_id: string
  username: string
  full_name: string
  avatar_url: string
  status: "online" | "offline" | "away" | "busy"
  last_seen: string
}

class RealtimeService {
  private channels: Map<string, RealtimeChannel> = new Map()
  private messageCallbacks: Map<string, (message: Message) => void> = new Map()
  private typingCallbacks: Map<string, (users: TypingUser[]) => void> = new Map()
  private presenceCallbacks: Map<string, (users: UserPresence[]) => void> = new Map()

  // Subscribe to conversation messages
  subscribeToConversation(
    conversationId: string,
    onMessage: (message: Message) => void,
    onTyping?: (users: TypingUser[]) => void,
    onPresence?: (users: UserPresence[]) => void,
  ) {
    const channelName = `conversation:${conversationId}`

    // Remove existing channel if it exists
    this.unsubscribeFromConversation(conversationId)

    const channel = supabase
      .channel(channelName, {
        config: {
          private: true,
        },
      })
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "messages",
          filter: `conversation_id=eq.${conversationId}`,
        },
        (payload) => {
          console.log("[v0] New message received:", payload)
          onMessage(payload.new as Message)
        },
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "messages",
          filter: `conversation_id=eq.${conversationId}`,
        },
        (payload) => {
          console.log("[v0] Message updated:", payload)
          onMessage(payload.new as Message)
        },
      )

    // Add broadcast for typing indicators
    if (onTyping) {
      channel.on("broadcast", { event: "typing" }, (payload) => {
        console.log("[v0] Typing event:", payload)
        onTyping(payload.payload.users || [])
      })
      this.typingCallbacks.set(conversationId, onTyping)
    }

    // Add presence for online users
    if (onPresence) {
      channel.on("presence", { event: "sync" }, () => {
        const state = channel.presenceState()
        const users: UserPresence[] = []

        Object.keys(state).forEach((userId) => {
          const presences = state[userId] as UserPresence[]
          if (presences.length > 0) {
            users.push(presences[0])
          }
        })

        console.log("[v0] Presence sync:", users)
        onPresence(users)
      })

      channel.on("presence", { event: "join" }, ({ key, newPresences }) => {
        console.log("[v0] User joined:", key, newPresences)
      })

      channel.on("presence", { event: "leave" }, ({ key, leftPresences }) => {
        console.log("[v0] User left:", key, leftPresences)
      })

      this.presenceCallbacks.set(conversationId, onPresence)
    }

    channel.subscribe(async (status) => {
      console.log("[v0] Realtime subscription status:", status)

      if (status === "SUBSCRIBED" && onPresence) {
        // Track user presence when successfully subscribed
        const user = await this.getCurrentUser()
        if (user) {
          await channel.track({
            user_id: user.id,
            username: user.username,
            full_name: user.full_name,
            avatar_url: user.avatar_url,
            status: user.status,
            last_seen: new Date().toISOString(),
          })
        }
      }
    })

    this.channels.set(conversationId, channel)
    this.messageCallbacks.set(conversationId, onMessage)

    return channel
  }

  // Unsubscribe from conversation
  unsubscribeFromConversation(conversationId: string) {
    const channel = this.channels.get(conversationId)
    if (channel) {
      supabase.removeChannel(channel)
      this.channels.delete(conversationId)
      this.messageCallbacks.delete(conversationId)
      this.typingCallbacks.delete(conversationId)
      this.presenceCallbacks.delete(conversationId)
    }
  }

  // Send typing indicator
  async sendTypingIndicator(conversationId: string, isTyping: boolean) {
    const channel = this.channels.get(conversationId)
    const user = await this.getCurrentUser()

    if (channel && user) {
      await channel.send({
        type: "broadcast",
        event: "typing",
        payload: {
          user_id: user.id,
          username: user.username,
          full_name: user.full_name,
          is_typing: isTyping,
        },
      })
    }
  }

  // Update user presence
  async updatePresence(conversationId: string, status: "online" | "offline" | "away" | "busy") {
    const channel = this.channels.get(conversationId)
    const user = await this.getCurrentUser()

    if (channel && user) {
      await channel.track({
        user_id: user.id,
        username: user.username,
        full_name: user.full_name,
        avatar_url: user.avatar_url,
        status: status,
        last_seen: new Date().toISOString(),
      })
    }
  }

  // Get current user
  private async getCurrentUser() {
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) return null

    const { data: profile } = await supabase.from("profiles").select("*").eq("id", user.id).single()

    return profile
  }

  // Clean up all subscriptions
  cleanup() {
    this.channels.forEach((channel) => {
      supabase.removeChannel(channel)
    })
    this.channels.clear()
    this.messageCallbacks.clear()
    this.typingCallbacks.clear()
    this.presenceCallbacks.clear()
  }
}

export const realtimeService = new RealtimeService()
