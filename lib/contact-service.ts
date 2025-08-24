import { supabase } from "./supabase"
import type { User } from "./supabase"

export interface ContactInvitation {
  id: string
  user_id: string
  contact_user_id: string
  status: "pending" | "accepted" | "blocked"
  invited_at: string
  accepted_at?: string
  blocked_at?: string
  inviter_username?: string
  inviter_full_name?: string
  inviter_avatar_url?: string
  invitee_username?: string
  invitee_full_name?: string
  invitee_avatar_url?: string
}

export interface SearchableUser extends User {
  contact_status?: "none" | "pending" | "accepted" | "blocked"
}

export class ContactService {
  // Test database connection
  static async testConnection(): Promise<boolean> {
    try {
      console.log("[ContactService] Testing database connection...")

      const { data, error } = await supabase.from("profiles").select("id, username, full_name").limit(1)

      if (error) {
        console.error("[ContactService] Connection test failed:", error)

        // Try a simpler query to diagnose the issue
        try {
          const { count, error: simpleError } = await supabase
            .from("profiles")
            .select("*", { count: "exact", head: true })
          if (simpleError) {
            console.error("[ContactService] Simple query also failed:", simpleError)
          } else {
            console.log("[ContactService] Simple query succeeded, RLS policy issue detected")
          }
        } catch (simpleErr) {
          console.error("[ContactService] Simple query error:", simpleErr)
        }

        return false
      }

      console.log("[ContactService] ✅ Connection successful! Sample data:", data)
      return true
    } catch (err: any) {
      console.error("[ContactService] Connection test error:", err)

      // Additional diagnostic information
      if (err.message?.includes("permission denied")) {
        console.error("[ContactService] Permission denied - RLS policies may be too restrictive")
      } else if (err.message?.includes("relation") && err.message?.includes("does not exist")) {
        console.error("[ContactService] Table does not exist - database setup required")
      }

      return false
    }
  }

  // Search for users by username, name, or email
  static async searchUsers(query: string, limit = 20): Promise<SearchableUser[]> {
    console.log(`[ContactService] searchUsers called with query: "${query}", limit: ${limit}`)

    try {
      // Get current user first
      const {
        data: { user: currentUser },
        error: authError,
      } = await supabase.auth.getUser()

      if (authError) {
        console.error("[ContactService] Auth error:", authError)
        throw new Error("Not authenticated")
      }

      if (!currentUser) {
        console.log("[ContactService] No authenticated user")
        throw new Error("Not authenticated")
      }

      console.log(`[ContactService] Current user: ${currentUser.id}`)

      try {
        const { data: functionData, error: functionError } = await supabase.rpc("search_users", {
          search_term: query,
        })

        if (!functionError && functionData) {
          console.log(`[ContactService] Function search found ${functionData.length} users`)

          const userIds = functionData.map((u: any) => u.id) || []
          const contactStatuses: Record<string, string> = {}

          if (userIds.length > 0) {
            const { data: friendshipData, error: friendshipError } = await supabase
              .from("friendships")
              .select("user_id, friend_id")
              .or(`user_id.eq.${currentUser.id},friend_id.eq.${currentUser.id}`)
              .in("user_id", [...userIds, currentUser.id])
              .in("friend_id", [...userIds, currentUser.id])

            const { data: requestData, error: requestError } = await supabase
              .from("friend_requests")
              .select("sender_id, receiver_id, status")
              .or(`sender_id.eq.${currentUser.id},receiver_id.eq.${currentUser.id}`)
              .in("sender_id", [...userIds, currentUser.id])
              .in("receiver_id", [...userIds, currentUser.id])

            if (!friendshipError && friendshipData) {
              friendshipData.forEach((friendship: any) => {
                const otherUserId = friendship.user_id === currentUser.id ? friendship.friend_id : friendship.user_id
                contactStatuses[otherUserId] = "accepted"
              })
            }

            if (!requestError && requestData) {
              requestData.forEach((request: any) => {
                const otherUserId = request.sender_id === currentUser.id ? request.receiver_id : request.sender_id
                if (!contactStatuses[otherUserId]) {
                  contactStatuses[otherUserId] = request.status
                }
              })
            }
          }

          // Combine user data with contact statuses
          const results = functionData.map((user: any) => ({
            ...user,
            contact_status: contactStatuses[user.id] || ("none" as const),
          }))

          return results
        } else {
          console.warn("[ContactService] Function search failed:", functionError)
        }
      } catch (funcErr) {
        console.warn("[ContactService] Function not available, using direct query")
      }

      const { data: directData, error: directError } = await supabase
        .from("profiles")
        .select(`
          id, username, full_name, avatar_url, bio, phone, 
          status, last_seen, created_at, updated_at
        `)
        .or(`username.ilike.%${query}%,full_name.ilike.%${query}%`)
        .neq("id", currentUser.id)
        .limit(limit)

      if (directError) {
        console.error("[ContactService] Direct query failed:", directError)
        throw directError
      }

      console.log(`[ContactService] Direct search found ${directData?.length || 0} users`)

      const userIds = directData?.map((u) => u.id) || []
      const contactStatuses: Record<string, string> = {}

      if (userIds.length > 0) {
        const { data: friendshipData, error: friendshipError } = await supabase
          .from("friendships")
          .select("user_id, friend_id")
          .or(`user_id.eq.${currentUser.id},friend_id.eq.${currentUser.id}`)
          .in("user_id", [...userIds, currentUser.id])
          .in("friend_id", [...userIds, currentUser.id])

        const { data: requestData, error: requestError } = await supabase
          .from("friend_requests")
          .select("sender_id, receiver_id, status")
          .or(`sender_id.eq.${currentUser.id},receiver_id.eq.${currentUser.id}`)
          .in("sender_id", [...userIds, currentUser.id])
          .in("receiver_id", [...userIds, currentUser.id])

        if (!friendshipError && friendshipData) {
          friendshipData.forEach((friendship: any) => {
            const otherUserId = friendship.user_id === currentUser.id ? friendship.friend_id : friendship.user_id
            contactStatuses[otherUserId] = "accepted"
          })
        }

        if (!requestError && requestData) {
          requestData.forEach((request: any) => {
            const otherUserId = request.sender_id === currentUser.id ? request.receiver_id : request.sender_id
            if (!contactStatuses[otherUserId]) {
              contactStatuses[otherUserId] = request.status
            }
          })
        }
      }

      // Combine user data with contact statuses
      const results = (directData || []).map((user) => ({
        ...user,
        is_online: user.status === "online",
        email: "", // Add missing email field for compatibility
        contact_status: contactStatuses[user.id] || ("none" as const),
      }))

      console.log(`[ContactService] Returning ${results.length} users with contact statuses`)
      return results
    } catch (error: any) {
      console.error("[ContactService] Search error:", error)
      throw error
    }
  }

  // Send contact invitation
  static async sendContactInvitation(receiverId: string) {
    console.log(`[ContactService] Sending invitation to: ${receiverId}`)

    try {
      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser()

      if (authError || !user) {
        throw new Error("Not authenticated")
      }

      try {
        const { data: result, error: rpcError } = await supabase.rpc("send_friend_request", {
          receiver_id: receiverId,
        })

        if (!rpcError && result) {
          console.log(`[ContactService] ✅ Invitation sent via RPC:`, result)
          return { success: result.success, message: result.message }
        } else {
          console.warn("[ContactService] RPC failed, trying manual creation:", rpcError)
        }
      } catch (rpcErr) {
        console.warn("[ContactService] RPC function not available, using manual creation")
      }

      // Manual fallback
      const { data: existing, error: checkError } = await supabase
        .from("friend_requests")
        .select("id, status")
        .or(
          `and(sender_id.eq.${user.id},receiver_id.eq.${receiverId}),and(sender_id.eq.${receiverId},receiver_id.eq.${user.id})`,
        )
        .maybeSingle()

      if (checkError) {
        console.error("[ContactService] Check existing request error:", checkError)
        throw checkError
      }

      if (existing) {
        if (existing.status === "pending") {
          throw new Error("Invitation already sent or received")
        }
        if (existing.status === "accepted") {
          throw new Error("Already connected")
        }
      }

      // Send invitation
      const { data: newInvitation, error: insertError } = await supabase
        .from("friend_requests")
        .insert({
          sender_id: user.id,
          receiver_id: receiverId,
          status: "pending",
        })
        .select()
        .single()

      if (insertError) {
        console.error("[ContactService] Send invitation error:", insertError)
        throw insertError
      }

      console.log(`[ContactService] ✅ Invitation sent successfully:`, newInvitation)
      return { success: true, invitation: newInvitation }
    } catch (error: any) {
      console.error("[ContactService] Send contact invitation error:", error)
      throw error
    }
  }

  // Accept contact invitation
  static async acceptContactInvitation(invitationId: string) {
    console.log(`[ContactService] Accepting invitation: ${invitationId}`)

    try {
      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser()

      if (authError || !user) {
        throw new Error("Not authenticated")
      }

      try {
        const { data: result, error: rpcError } = await supabase.rpc("accept_friend_request", {
          request_id: invitationId,
        })

        if (!rpcError && result) {
          console.log(`[ContactService] ✅ Invitation accepted via RPC:`, result)
          return { success: result.success, message: result.message }
        } else {
          console.warn("[ContactService] RPC failed, trying manual acceptance:", rpcError)
        }
      } catch (rpcErr) {
        console.warn("[ContactService] RPC function not available, using manual acceptance")
      }

      // Manual fallback
      const { data: invitation, error: fetchError } = await supabase
        .from("friend_requests")
        .select("id, sender_id, receiver_id, status")
        .eq("id", invitationId)
        .eq("receiver_id", user.id)
        .eq("status", "pending")
        .single()

      if (fetchError) {
        console.error("[ContactService] Fetch invitation error:", fetchError)
        throw fetchError
      }

      if (!invitation) {
        throw new Error("Invitation not found or already processed")
      }

      // Update the invitation to accepted
      const { error: updateError } = await supabase
        .from("friend_requests")
        .update({
          status: "accepted",
          updated_at: new Date().toISOString(),
        })
        .eq("id", invitationId)

      if (updateError) {
        console.error("[ContactService] Update invitation error:", updateError)
        throw updateError
      }

      // Create friendship (both directions)
      const { error: friendshipError } = await supabase.from("friendships").insert([
        { user_id: invitation.sender_id, friend_id: invitation.receiver_id },
        { user_id: invitation.receiver_id, friend_id: invitation.sender_id },
      ])

      if (friendshipError) {
        console.error("[ContactService] Create friendship error:", friendshipError)
        throw friendshipError
      }

      console.log(`[ContactService] ✅ Invitation accepted successfully: ${invitationId}`)
      return { success: true }
    } catch (error: any) {
      console.error("[ContactService] Accept contact invitation error:", error)
      throw error
    }
  }

  // Reject contact invitation
  static async rejectContactInvitation(invitationId: string) {
    console.log(`[ContactService] Rejecting invitation: ${invitationId}`)

    try {
      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser()

      if (authError || !user) {
        throw new Error("Not authenticated")
      }

      try {
        const { data: result, error: rpcError } = await supabase.rpc("reject_friend_request", {
          request_id: invitationId,
        })

        if (!rpcError && result) {
          console.log(`[ContactService] ✅ Invitation rejected via RPC:`, result)
          return { success: result.success, message: result.message }
        }
      } catch (rpcErr) {
        console.warn("[ContactService] RPC function not available, using manual rejection")
      }

      // Manual fallback
      const { error } = await supabase
        .from("friend_requests")
        .update({ status: "rejected", updated_at: new Date().toISOString() })
        .eq("id", invitationId)
        .eq("receiver_id", user.id)
        .eq("status", "pending")

      if (error) {
        console.error("[ContactService] Reject invitation error:", error)
        throw error
      }

      console.log(`[ContactService] ✅ Invitation rejected successfully: ${invitationId}`)
      return { success: true }
    } catch (error: any) {
      console.error("[ContactService] Reject contact invitation error:", error)
      throw error
    }
  }

  // Get pending invitations received by current user
  static async getPendingInvitations(): Promise<ContactInvitation[]> {
    console.log("[ContactService] Getting pending invitations...")

    try {
      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser()

      if (authError || !user) {
        console.log("[ContactService] Not authenticated")
        return []
      }

      const { data, error } = await supabase
        .from("friend_requests")
        .select(`
          *,
          sender:profiles!friend_requests_sender_id_fkey (
            id, username, full_name, avatar_url
          )
        `)
        .eq("receiver_id", user.id)
        .eq("status", "pending")
        .order("created_at", { ascending: false })

      if (error) {
        console.error("[ContactService] Get pending invitations error:", error)
        throw error
      }

      const invitations = (data || []).map((item: any) => ({
        ...item,
        user_id: item.sender_id,
        contact_user_id: item.receiver_id,
        invited_at: item.created_at,
        inviter_username: item.sender?.username,
        inviter_full_name: item.sender?.full_name,
        inviter_avatar_url: item.sender?.avatar_url,
      }))

      console.log(`[ContactService] ✅ Found ${invitations.length} pending invitations`)
      return invitations
    } catch (error) {
      console.error("[ContactService] Get pending invitations error:", error)
      return []
    }
  }

  // Get accepted contacts
  static async getContacts(): Promise<User[]> {
    console.log("[ContactService] Getting contacts...")

    try {
      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser()

      if (authError || !user) {
        console.log("[ContactService] Not authenticated")
        return []
      }

      const { data, error } = await supabase
        .from("friendships")
        .select(`
          friend_id,
          created_at,
          friend:profiles!friendships_friend_id_fkey (
            id, username, full_name, avatar_url, bio, phone, 
            status, last_seen, created_at, updated_at
          )
        `)
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })

      if (error) {
        console.error("[ContactService] Get contacts error:", error)
        throw error
      }

      const contacts = (data || [])
        .map((item: any) => ({
          ...item.friend,
          email: "", // Add missing email field for compatibility
          is_online: item.friend?.status === "online",
        }))
        .filter(Boolean)

      console.log(`[ContactService] ✅ Found ${contacts.length} contacts`)
      return contacts
    } catch (error) {
      console.error("[ContactService] Get contacts error:", error)
      return []
    }
  }

  // Start direct chat with contact
  static async startDirectChat(contactId: string) {
    console.log(`[ContactService] Starting direct chat with: ${contactId}`)

    try {
      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser()

      if (authError || !user) {
        throw new Error("Not authenticated")
      }

      // Check for existing direct conversation
      const { data: existingConversations, error: searchError } = await supabase
        .from("conversation_participants")
        .select(`
          conversation_id,
          conversations!inner(
            id, is_group, created_by
          )
        `)
        .eq("user_id", user.id)
        .eq("conversations.is_group", false)

      if (searchError) {
        console.error("[ContactService] Search existing conversations error:", searchError)
        throw searchError
      }

      // Check if any existing conversation has both users
      for (const conv of existingConversations || []) {
        const { data: participants, error: participantsError } = await supabase
          .from("conversation_participants")
          .select("user_id")
          .eq("conversation_id", conv.conversation_id)

        if (!participantsError && participants) {
          const participantIds = participants.map((p) => p.user_id)
          if (participantIds.includes(contactId) && participantIds.length === 2) {
            console.log(`[ContactService] ✅ Found existing direct conversation: ${conv.conversation_id}`)
            return { id: conv.conversation_id }
          }
        }
      }

      // Create new conversation
      const { data: newConversation, error: conversationError } = await supabase
        .from("conversations")
        .insert({
          is_group: false,
          created_by: user.id,
        })
        .select("id")
        .single()

      if (conversationError) {
        console.error("[ContactService] Conversation creation error:", conversationError)
        throw conversationError
      }

      const { error: participantsError } = await supabase.from("conversation_participants").insert([
        { conversation_id: newConversation.id, user_id: user.id, role: "member" },
        { conversation_id: newConversation.id, user_id: contactId, role: "member" },
      ])

      if (participantsError) {
        console.error("[ContactService] Participants addition error:", participantsError)
        throw participantsError
      }

      console.log(`[ContactService] ✅ Direct conversation created: ${newConversation.id}`)
      return { id: newConversation.id }
    } catch (error: any) {
      console.error("[ContactService] Start direct chat error:", error)
      throw error
    }
  }

  // Block contact
  static async blockContact(contactId: string) {
    console.log(`[ContactService] Blocking contact: ${contactId}`)

    try {
      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser()

      if (authError || !user) {
        throw new Error("Not authenticated")
      }

      const { error } = await supabase
        .from("contacts")
        .update({
          status: "blocked",
          blocked_at: new Date().toISOString(),
        })
        .eq("user_id", user.id)
        .eq("contact_user_id", contactId)

      if (error) {
        console.error("[ContactService] Block contact error:", error)
        throw error
      }

      console.log(`[ContactService] ✅ Contact blocked successfully: ${contactId}`)
      return { success: true }
    } catch (error: any) {
      console.error("[ContactService] Block contact error:", error)
      throw error
    }
  }

  // Remove contact
  static async removeContact(contactId: string) {
    console.log(`[ContactService] Removing contact: ${contactId}`)

    try {
      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser()

      if (authError || !user) {
        throw new Error("Not authenticated")
      }

      // Remove both directions of the contact relationship
      const { error } = await supabase
        .from("contacts")
        .delete()
        .or(
          `and(user_id.eq.${user.id},contact_user_id.eq.${contactId}),and(user_id.eq.${contactId},contact_user_id.eq.${user.id})`,
        )

      if (error) {
        console.error("[ContactService] Remove contact error:", error)
        throw error
      }

      console.log(`[ContactService] ✅ Contact removed successfully: ${contactId}`)
      return { success: true }
    } catch (error: any) {
      console.error("[ContactService] Remove contact error:", error)
      throw error
    }
  }
}
