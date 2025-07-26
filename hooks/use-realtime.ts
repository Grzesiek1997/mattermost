"use client"

import { useEffect, useState } from "react"
import { supabase, SUPABASE_READY } from "@/lib/supabase"
import type { Message, TypingIndicator } from "@/lib/supabase"

export function useRealtimeMessages(chatId: string) {
  const [messages, setMessages] = useState<Message[]>([])
  const [typingUsers, setTypingUsers] = useState<TypingIndicator[]>([])

  useEffect(() => {
    if (!chatId || !SUPABASE_READY) return

    console.log(`[useRealtimeMessages] Setting up realtime for chat: ${chatId}`)

    // Subscribe to new messages
    const messagesChannel = supabase
      .channel(`messages:${chatId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "messages",
          filter: `chat_id=eq.${chatId}`,
        },
        async (payload) => {
          // Fetch the complete message with relations
          const { data } = await supabase
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
            .eq("id", payload.new.id)
            .single()

          if (data) {
            setMessages((prev) => [...prev, data])
          }
        },
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "messages",
          filter: `chat_id=eq.${chatId}`,
        },
        async (payload) => {
          // Fetch updated message
          const { data } = await supabase
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
            .eq("id", payload.new.id)
            .single()

          if (data) {
            setMessages((prev) => prev.map((msg) => (msg.id === data.id ? data : msg)))
          }
        },
      )
      .subscribe()

    // Subscribe to message reactions
    const reactionsChannel = supabase
      .channel(`reactions:${chatId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "message_reactions",
        },
        async () => {
          // Refresh messages to get updated reactions
          const { data } = await supabase
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
            .order("created_at", { ascending: true })

          if (data) {
            setMessages(data)
          }
        },
      )
      .subscribe()

    // Subscribe to typing indicators
    const typingChannel = supabase
      .channel(`typing:${chatId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "typing_indicators",
          filter: `chat_id=eq.${chatId}`,
        },
        async () => {
          const { data } = await supabase
            .from("typing_indicators")
            .select(`
              *,
              user:user_id (
                id, username, full_name
              )
            `)
            .eq("chat_id", chatId)
            .eq("is_typing", true)
            .gte("updated_at", new Date(Date.now() - 10000).toISOString())

          setTypingUsers(data || [])
        },
      )
      .subscribe()

    return () => {
      console.log(`[useRealtimeMessages] Cleaning up realtime for chat: ${chatId}`)
      supabase.removeChannel(messagesChannel)
      supabase.removeChannel(reactionsChannel)
      supabase.removeChannel(typingChannel)
    }
  }, [chatId])

  return { messages, setMessages, typingUsers }
}

export function useRealtimePresence() {
  const [onlineUsers, setOnlineUsers] = useState<string[]>([])

  useEffect(() => {
    if (!SUPABASE_READY) {
      // Return mock online users for demo
      setOnlineUsers(["demo-user-1", "demo-user-5", "demo-user-7", "demo-user-9"])
      return
    }

    console.log("[useRealtimePresence] Setting up presence tracking")

    const channel = supabase
      .channel("online-users")
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "users",
        },
        (payload) => {
          if (payload.new.is_online) {
            setOnlineUsers((prev) => [...new Set([...prev, payload.new.id])])
          } else {
            setOnlineUsers((prev) => prev.filter((id) => id !== payload.new.id))
          }
        },
      )
      .subscribe()

    return () => {
      console.log("[useRealtimePresence] Cleaning up presence tracking")
      supabase.removeChannel(channel)
    }
  }, [])

  return onlineUsers
}
