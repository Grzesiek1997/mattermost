import { supabase, SUPABASE_READY } from "./supabase"
import { realtimeService } from "./realtime-service"
import type { Chat, Message } from "./supabase"

export class ChatService {
  // Create a new chat
  static async createChat(type: Chat["type"], title?: string, description?: string) {
    if (!SUPABASE_READY) {
      console.log("[ChatService] Demo mode - chat created (mock)")
      await new Promise((resolve) => setTimeout(resolve, 500))
      return {
        id: "demo-chat-" + Math.random().toString(36).slice(2),
        type,
        title,
        description,
        created_by: "demo-user",
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        last_message_at: new Date().toISOString(),
      }
    }

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) throw new Error("Not authenticated")

    const { data, error } = await supabase
      .from("rooms")
      .insert({
        name: title,
        description,
        type: type === "group" ? "group" : "private",
        creator_id: user.id,
      })
      .select()
      .single()

    if (error) throw error

    await supabase.from("room_participants").insert({
      room_id: data.id,
      user_id: user.id,
      role: "admin",
    })

    return data
  }

  // Get a user's chats
  static async getUserChats(userId: string) {
    if (!SUPABASE_READY) {
      console.log("[ChatService] Demo mode - returning empty chat list")
      return []
    }

    try {
      const { data, error } = await supabase.rpc("get_user_rooms", {
        p_user_id: userId,
      })

      if (error) throw error
      return data || []
    } catch (error) {
      console.error("Get user chats error:", error)
      try {
        const { data: roomsData, error: roomsError } = await supabase
          .from("rooms")
          .select(`
            id,
            name,
            description,
            type,
            avatar_url,
            creator_id,
            rooms.created_at,
            rooms.updated_at,
            room_participants!inner(
              user_id,
              role,
              joined_at
            )
          `)
          .eq("room_participants.user_id", userId)
          .order("rooms.updated_at", { ascending: false })

        if (roomsError) throw roomsError
        return roomsData || []
      } catch (fallbackError) {
        console.error("Fallback query also failed:", fallbackError)
        return []
      }
    }
  }

  // Get chat messages with pagination
  static async getChatMessages(chatId: string, limit = 50, offset = 0) {
    if (!SUPABASE_READY) {
      console.log("[ChatService] Demo mode - returning empty messages")
      return []
    }

    try {
      const { data, error } = await supabase
        .from("messages")
        .select(`
          *,
          sender:profiles!messages_sender_id_fkey (
            id, username, full_name, avatar_url, status
          ),
          reply_to:messages!messages_reply_to_id_fkey (
            id, content, 
            sender:profiles!messages_sender_id_fkey (username, full_name)
          )
        `)
        .eq("room_id", chatId)
        .order("created_at", { ascending: false })
        .range(offset, offset + limit - 1)

      if (error) throw error
      return (data || []).reverse() // Reverse to show oldest first
    } catch (error) {
      console.error("Get chat messages error:", error)
      return []
    }
  }

  // Send a message
  static async sendMessage(
    chatId: string,
    content: string,
    messageType: Message["message_type"] = "text",
    replyToId?: string,
    fileUrl?: string,
    fileName?: string,
    fileSize?: number,
  ) {
    if (!SUPABASE_READY) {
      console.log("[ChatService] Demo mode - message sent (mock)")
      await new Promise((resolve) => setTimeout(resolve, 300))
      return {
        id: "demo-msg-" + Math.random().toString(36).slice(2),
        room_id: chatId,
        sender_id: "demo-user",
        content,
        message_type: messageType,
        reply_to_id: replyToId,
        created_at: new Date().toISOString(),
      }
    }

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) throw new Error("Not authenticated")

    const { data, error } = await supabase
      .from("messages")
      .insert({
        room_id: chatId,
        sender_id: user.id,
        content,
        message_type: messageType,
        reply_to_id: replyToId,
      })
      .select(`
        *,
        sender:profiles!messages_sender_id_fkey (
          id, username, full_name, avatar_url, status
        ),
        reply_to:messages!messages_reply_to_id_fkey (
          id, content, 
          sender:profiles!messages_sender_id_fkey (username, full_name)
        )
      `)
      .single()

    if (error) throw error

    return data
  }

  // Add reaction to message
  static async addReaction(messageId: string, reaction: string) {
    if (!SUPABASE_READY) {
      console.log("[ChatService] Demo mode - reaction added (mock)")
      await new Promise((resolve) => setTimeout(resolve, 200))
      return { success: true }
    }

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) throw new Error("Not authenticated")

    const { data, error } = await supabase
      .from("message_reactions")
      .upsert({
        message_id: messageId,
        user_id: user.id,
        reaction,
      })
      .select()
      .single()

    if (error) throw error
    return data
  }

  // Remove reaction from message
  static async removeReaction(messageId: string, reaction: string) {
    if (!SUPABASE_READY) {
      return
    }

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) return

    const { error } = await supabase
      .from("message_reactions")
      .delete()
      .eq("message_id", messageId)
      .eq("user_id", user.id)
      .eq("reaction", reaction)

    if (error) throw error
  }

  // Update typing status
  static async updateTypingStatus(roomId: string, isTyping: boolean) {
    if (!SUPABASE_READY) {
      return
    }

    try {
      await realtimeService.sendTypingIndicator(roomId, isTyping)
    } catch (error) {
      console.error("Update typing status error:", error)
    }
  }

  static subscribeToConversation(
    roomId: string,
    onMessage: (message: any) => void,
    onTyping?: (users: any[]) => void,
    onPresence?: (users: any[]) => void,
  ) {
    return realtimeService.subscribeToConversation(roomId, onMessage, onTyping, onPresence)
  }

  static unsubscribeFromConversation(roomId: string) {
    realtimeService.unsubscribeFromConversation(roomId)
  }

  static async updatePresence(roomId: string, status: "online" | "offline" | "away" | "busy") {
    await realtimeService.updatePresence(roomId, status)
  }

  // Mark messages as read
  static async markMessagesAsRead(messageIds: string[]) {
    if (!SUPABASE_READY) {
      return
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) return

      const receipts = messageIds.map((messageId) => ({
        message_id: messageId,
        user_id: user.id,
        status: "read" as const,
      }))

      const { error } = await supabase.from("message_receipts").upsert(receipts)

      if (error) console.error("Mark messages as read error:", error)
    } catch (error) {
      console.error("Mark messages as read error:", error)
    }
  }

  // Search messages
  static async searchMessages(query: string, limit = 50): Promise<Message[]> {
    if (!SUPABASE_READY) {
      console.log("[ChatService] Demo mode - message search returns empty list")
      return []
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) return []

      const { data, error } = await supabase
        .from("messages")
        .select(`
          *,
          sender:profiles!messages_sender_id_fkey (
            id, username, full_name, avatar_url
          ),
          conversation:conversations!messages_conversation_id_fkey (
            id, name, is_group
          )
        `)
        .ilike("content", `%${query}%`)
        .eq("is_deleted", false)
        .order("created_at", { ascending: false })
        .limit(limit)

      if (error) throw error
      return data || []
    } catch (error) {
      console.error("Search messages error:", error)
      return []
    }
  }
}
