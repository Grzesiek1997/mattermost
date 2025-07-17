import { supabase, SUPABASE_READY } from "./supabase"
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
  // Search for users by username, name, or email
  static async searchUsers(query: string, limit = 20): Promise<SearchableUser[]> {
    console.log(`[ContactService] searchUsers called with query: "${query}", limit: ${limit}`)
    console.log(`[ContactService] SUPABASE_READY: ${SUPABASE_READY}`)

    if (!SUPABASE_READY) {
      console.log("[ContactService] Using demo mode for search")

      // Enhanced demo mode with more realistic users
      const mockUsers: SearchableUser[] = [
        {
          id: "demo-user-1",
          email: "john.doe@example.com",
          username: "johndoe",
          full_name: "John Doe",
          avatar_url: "/placeholder.svg",
          bio: "Software Developer at Tech Corp",
          phone: null,
          is_online: true,
          last_seen: new Date().toISOString(),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          contact_status: "none",
        },
        {
          id: "demo-user-2",
          email: "jane.smith@example.com",
          username: "janesmith",
          full_name: "Jane Smith",
          avatar_url: "/placeholder.svg",
          bio: "UI/UX Designer | Creative Professional",
          phone: null,
          is_online: false,
          last_seen: new Date(Date.now() - 3600000).toISOString(),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          contact_status: "none",
        },
        {
          id: "demo-user-3",
          email: "mike.wilson@example.com",
          username: "mikewilson",
          full_name: "Mike Wilson",
          avatar_url: "/placeholder.svg",
          bio: "Product Manager | Tech Enthusiast",
          phone: null,
          is_online: true,
          last_seen: new Date().toISOString(),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          contact_status: "pending",
        },
        {
          id: "demo-user-4",
          email: "sarah.johnson@example.com",
          username: "sarahj",
          full_name: "Sarah Johnson",
          avatar_url: "/placeholder.svg",
          bio: "Marketing Specialist",
          phone: null,
          is_online: false,
          last_seen: new Date(Date.now() - 7200000).toISOString(),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          contact_status: "accepted",
        },
        {
          id: "demo-user-5",
          email: "alex.brown@example.com",
          username: "alexbrown",
          full_name: "Alex Brown",
          avatar_url: "/placeholder.svg",
          bio: "Data Scientist",
          phone: null,
          is_online: true,
          last_seen: new Date().toISOString(),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          contact_status: "none",
        },
        {
          id: "demo-user-6",
          email: "emma.davis@example.com",
          username: "emmadavis",
          full_name: "Emma Davis",
          avatar_url: "/placeholder.svg",
          bio: "Frontend Developer",
          phone: null,
          is_online: false,
          last_seen: new Date(Date.now() - 1800000).toISOString(),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          contact_status: "none",
        },
        {
          id: "demo-user-7",
          email: "tom.miller@example.com",
          username: "tommiller",
          full_name: "Tom Miller",
          avatar_url: "/placeholder.svg",
          bio: "Backend Engineer",
          phone: null,
          is_online: true,
          last_seen: new Date().toISOString(),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          contact_status: "none",
        },
      ]

      // More flexible search - case insensitive and partial matching
      const searchTerm = query.toLowerCase().trim()
      const filtered = mockUsers.filter(
        (user) =>
          user.username?.toLowerCase().includes(searchTerm) ||
          user.full_name?.toLowerCase().includes(searchTerm) ||
          user.email.toLowerCase().includes(searchTerm) ||
          user.bio?.toLowerCase().includes(searchTerm),
      )

      console.log(
        `[ContactService] Demo mode - searched "${query}", found ${filtered.length} users:`,
        filtered.map((u) => ({ username: u.username, email: u.email })),
      )
      return filtered
    }

    try {
      // Test basic connection first
      console.log("[ContactService] Testing Supabase connection...")
      const { data: testData, error: testError } = await supabase
        .from("users")
        .select("count", { count: "exact", head: true })

      if (testError) {
        console.error("[ContactService] Supabase connection test failed:", testError)
        throw new Error(`Database connection failed: ${testError.message}`)
      }

      console.log(`[ContactService] Connection successful, total users in DB: ${testData}`)

      // Get current user
      const {
        data: { user },
      } = await supabase.auth.getUser()

      console.log(
        "[ContactService] Current auth user:",
        user ? { id: user.id, email: user.email } : "not authenticated",
      )

      if (!user) {
        console.error("[ContactService] User not authenticated")
        // In demo mode, still return results
        console.log("[ContactService] Falling back to demo mode due to no auth")
        return this.searchUsers(query, limit) // This will trigger demo mode
      }

      console.log(`[ContactService] Authenticated user: ${user.id}`)

      // Try direct query first (simpler approach)
      console.log("[ContactService] Trying direct query...")
      const { data: directData, error: directError } = await supabase
        .from("users")
        .select("id, email, username, full_name, avatar_url, bio, is_online, last_seen, created_at, updated_at")
        .or(`username.ilike.%${query}%,full_name.ilike.%${query}%,email.ilike.%${query}%`)
        .neq("id", user.id)
        .limit(limit)

      if (directError) {
        console.error("[ContactService] Direct query failed:", directError)

        // Try even simpler query
        console.log("[ContactService] Trying simple select all...")
        const { data: allData, error: allError } = await supabase
          .from("users")
          .select("id, email, username, full_name")
          .limit(10)

        if (allError) {
          console.error("[ContactService] Simple query also failed:", allError)
          throw new Error(`All database queries failed: ${allError.message}`)
        }

        console.log("[ContactService] Simple query results:", allData)

        // Filter manually
        const filtered = (allData || [])
          .filter((u) => u.id !== user.id)
          .filter(
            (u) =>
              u.username?.toLowerCase().includes(query.toLowerCase()) ||
              u.full_name?.toLowerCase().includes(query.toLowerCase()) ||
              u.email?.toLowerCase().includes(query.toLowerCase()),
          )
          .map((u) => ({ ...u, contact_status: "none" as const }))

        console.log(`[ContactService] Manual filter results: ${filtered.length}`)
        return filtered
      }

      console.log(`[ContactService] Direct query success - found ${directData?.length || 0} users`)
      console.log(
        "[ContactService] Direct query results:",
        directData?.map((u) => ({ username: u.username, email: u.email })),
      )

      return (directData || []).map((u) => ({ ...u, contact_status: "none" as const }))
    } catch (error: any) {
      console.error("[ContactService] Search users error:", error)

      // Final fallback to demo mode
      console.log("[ContactService] All real queries failed, using demo mode")
      const mockUsers: SearchableUser[] = [
        {
          id: "fallback-user-1",
          email: "test1@example.com",
          username: "testuser1",
          full_name: "Test User 1",
          avatar_url: "/placeholder.svg",
          bio: "Fallback test user",
          phone: null,
          is_online: true,
          last_seen: new Date().toISOString(),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          contact_status: "none",
        },
        {
          id: "fallback-user-2",
          email: "test2@example.com",
          username: "testuser2",
          full_name: "Test User 2",
          avatar_url: "/placeholder.svg",
          bio: "Another fallback user",
          phone: null,
          is_online: false,
          last_seen: new Date().toISOString(),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          contact_status: "none",
        },
      ]

      const searchTerm = query.toLowerCase().trim()
      const filtered = mockUsers.filter(
        (user) =>
          user.username?.toLowerCase().includes(searchTerm) ||
          user.full_name?.toLowerCase().includes(searchTerm) ||
          user.email.toLowerCase().includes(searchTerm),
      )

      console.log(`[ContactService] Fallback mode - found ${filtered.length} users`)
      return filtered
    }
  }

  // Send contact invitation
  static async sendContactInvitation(receiverId: string) {
    if (!SUPABASE_READY) {
      console.warn("[ContactService] Demo mode - invitation sent (mock)")
      return { success: true }
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) throw new Error("Not authenticated")

      // Check if any relationship already exists
      const { data: existing, error: checkError } = await supabase
        .from("contacts")
        .select("id, status, user_id, contact_user_id")
        .or(
          `and(user_id.eq.${user.id},contact_user_id.eq.${receiverId}),and(user_id.eq.${receiverId},contact_user_id.eq.${user.id})`,
        )
        .maybeSingle()

      if (checkError) {
        console.error("Check existing contact error:", checkError)
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
      const { error: insertError } = await supabase.from("contacts").insert({
        user_id: user.id,
        contact_user_id: receiverId,
        status: "pending",
        invited_at: new Date().toISOString(),
      })

      if (insertError) {
        console.error("Send invitation error:", insertError)
        throw insertError
      }

      console.log(`[ContactService] Invitation sent to user: ${receiverId}`)
      return { success: true }
    } catch (error: any) {
      console.error("Send contact invitation error:", error)
      throw error
    }
  }

  // Accept contact invitation
  static async acceptContactInvitation(invitationId: string) {
    if (!SUPABASE_READY) {
      console.warn("[ContactService] Demo mode - invitation accepted (mock)")
      return { success: true }
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) throw new Error("Not authenticated")

      // Get the invitation details
      const { data: invitation, error: fetchError } = await supabase
        .from("contacts")
        .select("id, user_id, contact_user_id, status")
        .eq("id", invitationId)
        .eq("contact_user_id", user.id)
        .eq("status", "pending")
        .single()

      if (fetchError) {
        console.error("Fetch invitation error:", fetchError)
        throw fetchError
      }
      if (!invitation) throw new Error("Invitation not found or already processed")

      // Update the invitation to accepted
      const { error: updateError } = await supabase
        .from("contacts")
        .update({
          status: "accepted",
          accepted_at: new Date().toISOString(),
        })
        .eq("id", invitationId)

      if (updateError) {
        console.error("Update invitation error:", updateError)
        throw updateError
      }

      // Create reverse relationship (mutual contact)
      const { error: reverseError } = await supabase.from("contacts").upsert(
        {
          user_id: invitation.contact_user_id, // The person who accepted (current user)
          contact_user_id: invitation.user_id, // The person who sent the invitation
          status: "accepted",
          accepted_at: new Date().toISOString(),
        },
        {
          onConflict: "user_id,contact_user_id",
        },
      )

      if (reverseError) {
        console.error("Create reverse relationship error:", reverseError)
        throw reverseError
      }

      console.log(`[ContactService] Invitation accepted: ${invitationId}`)
      return { success: true }
    } catch (error: any) {
      console.error("Accept contact invitation error:", error)
      throw error
    }
  }

  // Reject contact invitation
  static async rejectContactInvitation(invitationId: string) {
    if (!SUPABASE_READY) {
      console.warn("[ContactService] Demo mode - invitation rejected (mock)")
      return { success: true }
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) throw new Error("Not authenticated")

      const { error } = await supabase
        .from("contacts")
        .delete()
        .eq("id", invitationId)
        .eq("contact_user_id", user.id)
        .eq("status", "pending")

      if (error) {
        console.error("Reject invitation error:", error)
        throw error
      }

      console.log(`[ContactService] Invitation rejected: ${invitationId}`)
      return { success: true }
    } catch (error: any) {
      console.error("Reject contact invitation error:", error)
      throw error
    }
  }

  // Get pending invitations received by current user
  static async getPendingInvitations(): Promise<ContactInvitation[]> {
    if (!SUPABASE_READY) {
      const mockInvitations: ContactInvitation[] = [
        {
          id: "demo-inv-1",
          user_id: "demo-user-1",
          contact_user_id: "demo-current-user",
          status: "pending",
          invited_at: new Date(Date.now() - 3600000).toISOString(),
          inviter_username: "johndoe",
          inviter_full_name: "John Doe",
          inviter_avatar_url: "/placeholder.svg",
        },
        {
          id: "demo-inv-2",
          user_id: "demo-user-3",
          contact_user_id: "demo-current-user",
          status: "pending",
          invited_at: new Date(Date.now() - 7200000).toISOString(),
          inviter_username: "mikewilson",
          inviter_full_name: "Mike Wilson",
          inviter_avatar_url: "/placeholder.svg",
        },
      ]
      return mockInvitations
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) return []

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
        console.error("Get pending invitations error:", error)
        throw error
      }

      const invitations = (data || []).map((item: any) => ({
        ...item,
        inviter_username: item.inviter?.username,
        inviter_full_name: item.inviter?.full_name,
        inviter_avatar_url: item.inviter?.avatar_url,
      }))

      console.log(`[ContactService] Found ${invitations.length} pending invitations`)
      return invitations
    } catch (error) {
      console.error("Get pending invitations error:", error)
      return []
    }
  }

  // Get accepted contacts
  static async getContacts(): Promise<User[]> {
    if (!SUPABASE_READY) {
      // Return some mock accepted contacts
      return [
        {
          id: "demo-user-4",
          email: "sarah.johnson@example.com",
          username: "sarahj",
          full_name: "Sarah Johnson",
          avatar_url: "/placeholder.svg",
          bio: "Marketing Specialist",
          phone: null,
          is_online: false,
          last_seen: new Date(Date.now() - 7200000).toISOString(),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        },
      ]
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) return []

      const { data, error } = await supabase
        .from("contacts")
        .select(`
          contact_user_id,
          accepted_at,
          contact:contact_user_id (
            id, email, username, full_name, avatar_url, bio, is_online, last_seen
          )
        `)
        .eq("user_id", user.id)
        .eq("status", "accepted")
        .order("accepted_at", { ascending: false })

      if (error) {
        console.error("Get contacts error:", error)
        throw error
      }

      const contacts = (data || []).map((item: any) => item.contact).filter(Boolean)
      console.log(`[ContactService] Found ${contacts.length} contacts`)
      return contacts
    } catch (error) {
      console.error("Get contacts error:", error)
      return []
    }
  }

  // Block contact
  static async blockContact(contactId: string) {
    if (!SUPABASE_READY) {
      console.warn("[ContactService] Demo mode - contact blocked (mock)")
      return { success: true }
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) throw new Error("Not authenticated")

      const { error } = await supabase
        .from("contacts")
        .update({
          status: "blocked",
          blocked_at: new Date().toISOString(),
        })
        .eq("user_id", user.id)
        .eq("contact_user_id", contactId)

      if (error) {
        console.error("Block contact error:", error)
        throw error
      }

      console.log(`[ContactService] Contact blocked: ${contactId}`)
      return { success: true }
    } catch (error: any) {
      console.error("Block contact error:", error)
      throw error
    }
  }

  // Remove contact
  static async removeContact(contactId: string) {
    if (!SUPABASE_READY) {
      console.warn("[ContactService] Demo mode - contact removed (mock)")
      return { success: true }
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) throw new Error("Not authenticated")

      // Remove both directions of the contact relationship
      const { error } = await supabase
        .from("contacts")
        .delete()
        .or(
          `and(user_id.eq.${user.id},contact_user_id.eq.${contactId}),and(user_id.eq.${contactId},contact_user_id.eq.${user.id})`,
        )

      if (error) {
        console.error("Remove contact error:", error)
        throw error
      }

      console.log(`[ContactService] Contact removed: ${contactId}`)
      return { success: true }
    } catch (error: any) {
      console.error("Remove contact error:", error)
      throw error
    }
  }

  // Start direct chat with contact
  static async startDirectChat(contactId: string) {
    if (!SUPABASE_READY) {
      console.warn("[ContactService] Demo mode - direct chat started (mock)")
      return { id: "demo-chat-" + contactId }
    }

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) throw new Error("Not authenticated")

      // Check if direct chat already exists between these users
      const { data: existingMembers, error: searchError } = await supabase
        .from("chat_members")
        .select(`
          chat_id,
          chats:chat_id (
            id, type, created_by
          )
        `)
        .in("user_id", [user.id, contactId])

      if (searchError) {
        console.error("Search existing chat error:", searchError)
        throw searchError
      }

      // Find a direct chat that contains both users
      const chatCounts: Record<string, number> = {}
      existingMembers?.forEach((member: any) => {
        if (member.chats?.type === "direct") {
          chatCounts[member.chat_id] = (chatCounts[member.chat_id] || 0) + 1
        }
      })

      const existingChatId = Object.keys(chatCounts).find((chatId) => chatCounts[chatId] === 2)

      if (existingChatId) {
        console.log(`[ContactService] Found existing direct chat: ${existingChatId}`)
        return { id: existingChatId }
      }

      // Create new direct chat
      const { data: newChat, error: createError } = await supabase
        .from("chats")
        .insert({
          type: "direct",
          created_by: user.id,
        })
        .select()
        .single()

      if (createError) {
        console.error("Create chat error:", createError)
        throw createError
      }

      // Add both users as members
      const { error: membersError } = await supabase.from("chat_members").insert([
        { chat_id: newChat.id, user_id: user.id, role: "member" },
        { chat_id: newChat.id, user_id: contactId, role: "member" },
      ])

      if (membersError) {
        console.error("Add chat members error:", membersError)
        throw membersError
      }

      console.log(`[ContactService] Created new direct chat: ${newChat.id}`)
      return newChat
    } catch (error: any) {
      console.error("Start direct chat error:", error)
      throw error
    }
  }
}
