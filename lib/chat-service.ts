import { supabase, SUPABASE_READY } from "./supabase"
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
      .from("chats")
      .insert({
        type,
        title,
        description,
        created_by: user.id,
      })
      .select()
      .single()

    if (error) throw error
    return data
  }

  // Get user's chats
  static async getUserChats(userId: string) {
    if (!SUPABASE_READY) {
      console.log("[ChatService] Demo mode - returning empty chat list")
      return []
    }

    try {
      const { data, error } = await supabase
        .from("chat_participants")
        .select(`
          *,
          chats:chat_id (
            *,
            created_by_user:created_by (
              id, username, full_name, avatar_url
            )
          )
        `)
        .eq("user_id", userId)
        .order("joined_at", { ascending: false })

      if (error) throw error
      return data || []
    } catch (error) {
      console.error("Get user chats error:", error)
      return []
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
          user:user_id (
            id, username, full_name, avatar_url, is_online
          ),
          reply_to:reply_to_id (
            id, content, user:user_id (username, full_name)
          ),
          reactions:message_reactions (
            id, emoji, user_id,
            user:user_id (username, full_name)
          )
        `)
        .eq("chat_id", chatId)
        .eq("is_deleted", false)
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
        chat_id: chatId,
        user_id: "demo-user",
        content,
        message_type: messageType,
        reply_to_id: replyToId,
        file_url: fileUrl,
        file_name: fileName,
        file_size: fileSize,
        is_edited: false,
        is_deleted: false,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }
    }

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) throw new Error("Not authenticated")

    const { data, error } = await supabase
      .from("messages")
      .insert({
        chat_id: chatId,
        user_id: user.id, // Changed from sender_id to user_id
        content,
        message_type: messageType,
        reply_to_id: replyToId,
        file_url: fileUrl,
        file_name: fileName,
        file_size: fileSize,
      })
      .select(`
        *,
        user:user_id (
          id, username, full_name, avatar_url, is_online
        ),
        reply_to:reply_to_id (
          id, content, user:user_id (username, full_name)
        )
      `)
      .single()

    if (error) throw error
    return data
  }

  // Add reaction to message
  static async addReaction(messageId: string, emoji: string) {
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
        emoji,
      })
      .select()
      .single()

    if (error) throw error
    return data
  }

  // Remove reaction from message
  static async removeReaction(messageId: string, emoji: string) {
    if (!SUPABASE_READY) {
      console.log("[ChatService] Demo mode - reaction removed (mock)")
      await new Promise((resolve) => setTimeout(resolve, 200))
      return { success: true }
    }

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) throw new Error("Not authenticated")

    const { error } = await supabase
      .from("message_reactions")
      .delete()
      .eq("message_id", messageId)
      .eq("user_id", user.id)
      .eq("emoji", emoji)

    if (error) throw error
  }

  // Update typing status
  static async updateTypingStatus(chatId: string, isTyping: boolean) {
    if (!SUPABASE_READY) {
      return
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) return

      const { error } = await supabase.from("typing_indicators").upsert({
        chat_id: chatId,
        user_id: user.id,
        is_typing: isTyping,
        updated_at: new Date().toISOString(),
      })

      if (error) console.error("Update typing status error:", error)
    } catch (error) {
      console.error("Update typing status error:", error)
    }
  }

  // Get typing indicators for a chat
  static async getTypingIndicators(chatId: string) {
    if (!SUPABASE_READY) {
      return []
    }

    try {
      const { data, error } = await supabase
        .from("typing_indicators")
        .select(`
          *,
          user:user_id (
            id, username, full_name
          )
        `)
        .eq("chat_id", chatId)
        .eq("is_typing", true)
        .gte("updated_at", new Date(Date.now() - 10000).toISOString()) // Last 10 seconds

      if (error) throw error
      return data || []
    } catch (error) {
      console.error("Get typing indicators error:", error)
      return []
    }
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

      const reads = messageIds.map((messageId) => ({
        message_id: messageId,
        user_id: user.id,
      }))

      const { error } = await supabase.from("message_reads").upsert(reads)

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
          user:user_id (
            id, username, full_name, avatar_url
          ),
          chats:chat_id (
            id, title, type
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
