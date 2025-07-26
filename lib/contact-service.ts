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

// Enhanced demo users database
const DEMO_USERS: SearchableUser[] = [
  {
    id: "demo-user-1",
    email: "john.doe@example.com",
    username: "johndoe",
    full_name: "John Doe",
    avatar_url: "/placeholder.svg?height=40&width=40&text=JD",
    bio: "Software Developer at Tech Corp. Love coding and coffee ☕",
    phone: "+1-555-0101",
    is_online: true,
    last_seen: new Date().toISOString(),
    created_at: new Date(Date.now() - 86400000 * 30).toISOString(),
    updated_at: new Date().toISOString(),
    contact_status: "none",
  },
  {
    id: "demo-user-2",
    email: "jane.smith@example.com",
    username: "janesmith",
    full_name: "Jane Smith",
    avatar_url: "/placeholder.svg?height=40&width=40&text=JS",
    bio: "UI/UX Designer | Creative Professional | Dog lover 🐕",
    phone: "+1-555-0102",
    is_online: false,
    last_seen: new Date(Date.now() - 3600000).toISOString(),
    created_at: new Date(Date.now() - 86400000 * 25).toISOString(),
    updated_at: new Date().toISOString(),
    contact_status: "none",
  },
  {
    id: "demo-user-3",
    email: "mike.wilson@example.com",
    username: "mikewilson",
    full_name: "Mike Wilson",
    avatar_url: "/placeholder.svg?height=40&width=40&text=MW",
    bio: "Product Manager | Tech Enthusiast | Startup advisor",
    phone: "+1-555-0103",
    is_online: true,
    last_seen: new Date().toISOString(),
    created_at: new Date(Date.now() - 86400000 * 20).toISOString(),
    updated_at: new Date().toISOString(),
    contact_status: "pending",
  },
  {
    id: "demo-user-4",
    email: "sarah.johnson@example.com",
    username: "sarahj",
    full_name: "Sarah Johnson",
    avatar_url: "/placeholder.svg?height=40&width=40&text=SJ",
    bio: "Marketing Specialist | Content Creator | Travel enthusiast ✈️",
    phone: "+1-555-0104",
    is_online: false,
    last_seen: new Date(Date.now() - 7200000).toISOString(),
    created_at: new Date(Date.now() - 86400000 * 15).toISOString(),
    updated_at: new Date().toISOString(),
    contact_status: "accepted",
  },
  {
    id: "demo-user-5",
    email: "alex.brown@example.com",
    username: "alexbrown",
    full_name: "Alex Brown",
    avatar_url: "/placeholder.svg?height=40&width=40&text=AB",
    bio: "Data Scientist | AI/ML Engineer | Python enthusiast 🐍",
    phone: "+1-555-0105",
    is_online: true,
    last_seen: new Date().toISOString(),
    created_at: new Date(Date.now() - 86400000 * 10).toISOString(),
    updated_at: new Date().toISOString(),
    contact_status: "none",
  },
  {
    id: "demo-user-6",
    email: "emma.davis@example.com",
    username: "emmadavis",
    full_name: "Emma Davis",
    avatar_url: "/placeholder.svg?height=40&width=40&text=ED",
    bio: "Frontend Developer | React specialist | Open source contributor",
    phone: "+1-555-0106",
    is_online: false,
    last_seen: new Date(Date.now() - 1800000).toISOString(),
    created_at: new Date(Date.now() - 86400000 * 8).toISOString(),
    updated_at: new Date().toISOString(),
    contact_status: "none",
  },
  {
    id: "demo-user-7",
    email: "tom.miller@example.com",
    username: "tommiller",
    full_name: "Tom Miller",
    avatar_url: "/placeholder.svg?height=40&width=40&text=TM",
    bio: "Backend Engineer | Node.js expert | DevOps enthusiast",
    phone: "+1-555-0107",
    is_online: true,
    last_seen: new Date().toISOString(),
    created_at: new Date(Date.now() - 86400000 * 5).toISOString(),
    updated_at: new Date().toISOString(),
    contact_status: "none",
  },
  {
    id: "demo-user-8",
    email: "lisa.garcia@example.com",
    username: "lisagarcia",
    full_name: "Lisa Garcia",
    avatar_url: "/placeholder.svg?height=40&width=40&text=LG",
    bio: "Graphic Designer | Brand strategist | Coffee addict ☕",
    phone: "+1-555-0108",
    is_online: false,
    last_seen: new Date(Date.now() - 5400000).toISOString(),
    created_at: new Date(Date.now() - 86400000 * 12).toISOString(),
    updated_at: new Date().toISOString(),
    contact_status: "none",
  },
  {
    id: "demo-user-9",
    email: "david.lee@example.com",
    username: "davidlee",
    full_name: "David Lee",
    avatar_url: "/placeholder.svg?height=40&width=40&text=DL",
    bio: "Mobile Developer | iOS & Android | Tech blogger",
    phone: "+1-555-0109",
    is_online: true,
    last_seen: new Date().toISOString(),
    created_at: new Date(Date.now() - 86400000 * 18).toISOString(),
    updated_at: new Date().toISOString(),
    contact_status: "none",
  },
  {
    id: "demo-user-10",
    email: "anna.white@example.com",
    username: "annawhite",
    full_name: "Anna White",
    avatar_url: "/placeholder.svg?height=40&width=40&text=AW",
    bio: "Project Manager | Agile coach | Team builder 👥",
    phone: "+1-555-0110",
    is_online: false,
    last_seen: new Date(Date.now() - 9000000).toISOString(),
    created_at: new Date(Date.now() - 86400000 * 22).toISOString(),
    updated_at: new Date().toISOString(),
    contact_status: "none",
  },
]

export class ContactService {
  // Search for users by username, name, or email
  static async searchUsers(query: string, limit = 20): Promise<SearchableUser[]> {
    console.log(`[ContactService] searchUsers called with query: "${query}", limit: ${limit}`)

    if (!SUPABASE_READY) {
      console.log("[ContactService] Using enhanced demo mode for search")

      // Enhanced search with better matching
      const searchTerm = query.toLowerCase().trim()

      if (searchTerm.length < 1) {
        return []
      }

      const filtered = DEMO_USERS.filter((user) => {
        const matchUsername = user.username?.toLowerCase().includes(searchTerm)
        const matchFullName = user.full_name?.toLowerCase().includes(searchTerm)
        const matchEmail = user.email.toLowerCase().includes(searchTerm)
        const matchBio = user.bio?.toLowerCase().includes(searchTerm)

        return matchUsername || matchFullName || matchEmail || matchBio
      }).slice(0, limit)

      console.log(`[ContactService] Demo search found ${filtered.length} users for "${query}"`)
      return filtered
    }

    try {
      // Get current user
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user) {
        console.log("[ContactService] No authenticated user, falling back to demo")
        return this.searchUsers(query, limit) // Fallback to demo
      }

      console.log(`[ContactService] Authenticated user: ${user.id}`)

      // Try direct query
      const { data: directData, error: directError } = await supabase
        .from("users")
        .select("id, email, username, full_name, avatar_url, bio, phone, is_online, last_seen, created_at, updated_at")
        .or(`username.ilike.%${query}%,full_name.ilike.%${query}%,email.ilike.%${query}%`)
        .neq("id", user.id)
        .limit(limit)

      if (directError) {
        console.error("[ContactService] Database query failed:", directError)
        console.log("[ContactService] Falling back to demo mode")
        return this.searchUsers(query, limit) // Fallback to demo
      }

      console.log(`[ContactService] Database search found ${directData?.length || 0} users`)
      return (directData || []).map((u) => ({ ...u, contact_status: "none" as const }))
    } catch (error: any) {
      console.error("[ContactService] Search error:", error)
      console.log("[ContactService] Using demo fallback")

      // Return demo results
      const searchTerm = query.toLowerCase().trim()
      const filtered = DEMO_USERS.filter((user) => {
        const matchUsername = user.username?.toLowerCase().includes(searchTerm)
        const matchFullName = user.full_name?.toLowerCase().includes(searchTerm)
        const matchEmail = user.email.toLowerCase().includes(searchTerm)

        return matchUsername || matchFullName || matchEmail
      }).slice(0, limit)

      return filtered
    }
  }

  // Send contact invitation
  static async sendContactInvitation(receiverId: string) {
    if (!SUPABASE_READY) {
      console.log("[ContactService] Demo mode - invitation sent (mock)")
      // Simulate delay
      await new Promise((resolve) => setTimeout(resolve, 500))
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
      console.log("[ContactService] Demo mode - invitation accepted (mock)")
      await new Promise((resolve) => setTimeout(resolve, 500))
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
      console.log("[ContactService] Demo mode - invitation rejected (mock)")
      await new Promise((resolve) => setTimeout(resolve, 500))
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
          inviter_avatar_url: "/placeholder.svg?height=40&width=40&text=JD",
        },
        {
          id: "demo-inv-2",
          user_id: "demo-user-3",
          contact_user_id: "demo-current-user",
          status: "pending",
          invited_at: new Date(Date.now() - 7200000).toISOString(),
          inviter_username: "mikewilson",
          inviter_full_name: "Mike Wilson",
          inviter_avatar_url: "/placeholder.svg?height=40&width=40&text=MW",
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
          avatar_url: "/placeholder.svg?height=40&width=40&text=SJ",
          bio: "Marketing Specialist",
          phone: "+1-555-0104",
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
            id, email, username, full_name, avatar_url, bio, phone, is_online, last_seen, created_at, updated_at
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
      console.log("[ContactService] Demo mode - contact blocked (mock)")
      await new Promise((resolve) => setTimeout(resolve, 500))
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
      console.log("[ContactService] Demo mode - contact removed (mock)")
      await new Promise((resolve) => setTimeout(resolve, 500))
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
      console.log("[ContactService] Demo mode - direct chat started (mock)")
      await new Promise((resolve) => setTimeout(resolve, 500))
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
