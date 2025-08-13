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

      const { data, error } = await supabase.from("users").select("id, username, full_name").limit(1)

      if (error) {
        console.error("[ContactService] Connection test failed:", error)
        return false
      }

      console.log("[ContactService] ✅ Connection successful! Sample data:", data)
      return true
    } catch (err: any) {
      console.error("[ContactService] Connection test error:", err)
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

      // Try using the custom function first
      try {
        const { data: functionData, error: functionError } = await supabase.rpc("get_searchable_users", {
          search_query: query,
          current_user_id: currentUser.id,
          result_limit: limit,
        })

        if (!functionError && functionData) {
          console.log(`[ContactService] Function search found ${functionData.length} users`)
          return functionData
        } else {
          console.warn("[ContactService] Function search failed:", functionError)
        }
      } catch (funcErr) {
        console.warn("[ContactService] Function not available, using direct query")
      }

      // Fallback to direct query
      const { data: directData, error: directError } = await supabase
        .from("users")
        .select(`
          id, email, username, full_name, avatar_url, bio, phone, 
          is_online, last_seen, created_at, updated_at
        `)
        .or(`username.ilike.%${query}%,full_name.ilike.%${query}%,email.ilike.%${query}%`)
        .neq("id", currentUser.id)
        .limit(limit)

      if (directError) {
        console.error("[ContactService] Direct query failed:", directError)
        throw directError
      }

      console.log(`[ContactService] Direct search found ${directData?.length || 0} users`)

      // Get contact statuses for found users
      const userIds = directData?.map((u) => u.id) || []
      const contactStatuses: Record<string, string> = {}

      if (userIds.length > 0) {
        const { data: contactData, error: contactError } = await supabase
          .from("contacts")
          .select("contact_user_id, user_id, status")
          .or(
            `and(user_id.eq.${currentUser.id},contact_user_id.in.(${userIds.join(",")})),and(contact_user_id.eq.${currentUser.id},user_id.in.(${userIds.join(",")}))`,
          )

        if (!contactError && contactData) {
          contactData.forEach((contact: any) => {
            const otherUserId = contact.user_id === currentUser.id ? contact.contact_user_id : contact.user_id
            contactStatuses[otherUserId] = contact.status
          })
        }
      }

      // Combine user data with contact statuses
      const results = (directData || []).map((user) => ({
        ...user,
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

      // Check if any relationship already exists
      const { data: existing, error: checkError } = await supabase
        .from("contacts")
        .select("id, status, user_id, contact_user_id")
        .or(
          `and(user_id.eq.${user.id},contact_user_id.eq.${receiverId}),and(user_id.eq.${receiverId},contact_user_id.eq.${user.id})`,
        )
        .maybeSingle()

      if (checkError) {
        console.error("[ContactService] Check existing contact error:", checkError)
        throw checkError
      }

      if (existing) {
        if (existing.status === "pending") {
          throw new Error("Invitation already sent or received")
        }
        if (existing.status === "accepted") {
          throw new Error("Already connected")
        }
        if (existing.status === "blocked") {
          throw new Error("Cannot send invitation")
        }
      }

      // Send invitation
      const { data: newInvitation, error: insertError } = await supabase
        .from("contacts")
        .insert({
          user_id: user.id,
          contact_user_id: receiverId,
          status: "pending",
          invited_at: new Date().toISOString(),
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

      // Get the invitation details
      const { data: invitation, error: fetchError } = await supabase
        .from("contacts")
        .select("id, user_id, contact_user_id, status")
        .eq("id", invitationId)
        .eq("contact_user_id", user.id)
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
        .from("contacts")
        .update({
          status: "accepted",
          accepted_at: new Date().toISOString(),
        })
        .eq("id", invitationId)

      if (updateError) {
        console.error("[ContactService] Update invitation error:", updateError)
        throw updateError
      }

      // Create reverse relationship (mutual contact)
      const { error: reverseError } = await supabase.from("contacts").upsert(
        {
          user_id: invitation.contact_user_id,
          contact_user_id: invitation.user_id,
          status: "accepted",
          accepted_at: new Date().toISOString(),
        },
        {
          onConflict: "user_id,contact_user_id",
        },
      )

      if (reverseError) {
        console.error("[ContactService] Create reverse relationship error:", reverseError)
        throw reverseError
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

      const { error } = await supabase
        .from("contacts")
        .delete()
        .eq("id", invitationId)
        .eq("contact_user_id", user.id)
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
        .from("contacts")
        .select(`
          *,
          inviter:user_id (
            id, username, full_name, avatar_url
          )
        `)
        .eq("contact_user_id", user.id)
        .eq("status", "pending")
        .order("invited_at", { ascending: false })

      if (error) {
        console.error("[ContactService] Get pending invitations error:", error)
        throw error
      }

      const invitations = (data || []).map((item: any) => ({
        ...item,
        inviter_username: item.inviter?.username,
        inviter_full_name: item.inviter?.full_name,
        inviter_avatar_url: item.inviter?.avatar_url,
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
        .from("contacts")
        .select(`
          contact_user_id,
          accepted_at,
          contact:contact_user_id (
            id, email, username, full_name, avatar_url, bio, phone, 
            is_online, last_seen, created_at, updated_at
          )
        `)
        .eq("user_id", user.id)
        .eq("status", "accepted")
        .order("accepted_at", { ascending: false })

      if (error) {
        console.error("[ContactService] Get contacts error:", error)
        throw error
      }

      const contacts = (data || []).map((item: any) => item.contact).filter(Boolean)
      console.log(`[ContactService] ✅ Found ${contacts.length} contacts`)
      return contacts
    } catch (error) {
      console.error("[ContactService] Get contacts error:", error)
      return []
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

      try {
        const { data: chatId, error: rpcError } = await supabase.rpc("create_direct_chat_with_members", {
          user1: user.id,
          user2: contactId,
        })

        if (!rpcError && chatId) {
          console.log(`[ContactService] ✅ Direct chat ready via RPC: ${chatId}`)
          return { id: chatId }
        } else {
          console.warn("[ContactService] RPC failed, trying manual creation:", rpcError)
        }
      } catch (rpcErr) {
        console.warn("[ContactService] RPC function not available, using manual creation")
      }

      console.log("[ContactService] Creating chat manually...")

      // First check if direct chat already exists
      const { data: existingChats, error: searchError } = await supabase
        .from("chats")
        .select(`
          id,
          chat_participants!inner(user_id)
        `)
        .eq("type", "direct")

      if (searchError) {
        console.error("[ContactService] Search existing chats error:", searchError)
        throw searchError
      }

      // Check if any existing chat has both users
      for (const chat of existingChats || []) {
        const participantIds = chat.chat_participants.map((p: any) => p.user_id)
        if (participantIds.includes(user.id) && participantIds.includes(contactId) && participantIds.length === 2) {
          console.log(`[ContactService] ✅ Found existing direct chat: ${chat.id}`)
          return { id: chat.id }
        }
      }

      // Create new chat
      const { data: newChat, error: chatError } = await supabase
        .from("chats")
        .insert({
          name: null,
          type: "direct",
          created_by: user.id,
        })
        .select("id")
        .single()

      if (chatError) {
        console.error("[ContactService] Chat creation error:", chatError)
        throw chatError
      }

      const { error: membersError } = await supabase.from("chat_participants").insert([
        { chat_id: newChat.id, user_id: user.id, role: "member" },
        { chat_id: newChat.id, user_id: contactId, role: "member" },
      ])

      if (membersError) {
        console.error("[ContactService] Members addition error:", membersError)
        throw membersError
      }

      console.log(`[ContactService] ✅ Direct chat created manually: ${newChat.id}`)
      return { id: newChat.id }
    } catch (error: any) {
      console.error("[ContactService] Start direct chat error:", error)
      throw error
    }
  }
}
