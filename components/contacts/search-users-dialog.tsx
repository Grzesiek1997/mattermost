"use client"

import { useState, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { ContactService, type SearchableUser } from "@/lib/contact-service"
import type { User } from "@/lib/supabase"
import { Search, UserPlus, Clock, MessageCircle, Check } from "lucide-react"
import { toast } from "@/hooks/use-toast"

interface SearchUsersDialogProps {
  currentUser: User
  onContactAdded?: () => void
}

export function SearchUsersDialog({ currentUser, onContactAdded }: SearchUsersDialogProps) {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState("")
  const [results, setResults] = useState<SearchableUser[]>([])
  const [loading, setLoading] = useState(false)
  const [sendingInvitations, setSendingInvitations] = useState<Set<string>>(new Set())

  useEffect(() => {
    if (query.trim().length < 2) {
      setResults([])
      return
    }

    const searchTimeout = setTimeout(async () => {
      setLoading(true)
      console.log(`[SearchUsers] Starting search for: "${query.trim()}"`)
      console.log(`[SearchUsers] Current user:`, { id: currentUser.id, username: currentUser.username })

      try {
        const searchResults = await ContactService.searchUsers(query.trim())
        console.log(`[SearchUsers] Raw results:`, searchResults)

        // Filter results to ensure we don't show current user
        const filteredResults = searchResults.filter((user) => user.id !== currentUser.id)
        console.log(
          `[SearchUsers] Filtered results (${filteredResults.length}):`,
          filteredResults.map((u) => ({ id: u.id, username: u.username, email: u.email })),
        )

        setResults(filteredResults)

        // Show toast with results for debugging
        if (filteredResults.length > 0) {
          console.log(`[SearchUsers] SUCCESS: Found ${filteredResults.length} users`)
        } else {
          console.log(`[SearchUsers] No results found for "${query.trim()}"`)
          // Try to understand why - check if it's a connection issue
          if (
            query.toLowerCase().includes("test") ||
            query.toLowerCase().includes("john") ||
            query.toLowerCase().includes("jane")
          ) {
            console.log(
              `[SearchUsers] Expected to find results for common terms like "${query}" - possible connection issue`,
            )
          }
        }
      } catch (error) {
        console.error("[SearchUsers] Search error:", error)
        toast({
          title: "Search failed",
          description: `Unable to search users: ${error.message || "Unknown error"}. Check console for details.`,
          variant: "destructive",
        })
        setResults([])
      } finally {
        setLoading(false)
      }
    }, 300)

    return () => clearTimeout(searchTimeout)
  }, [query, currentUser.id])

  const handleSendInvitation = async (userId: string) => {
    setSendingInvitations((prev) => new Set(prev).add(userId))

    try {
      await ContactService.sendContactInvitation(userId)
      toast({
        title: "Invitation sent!",
        description: "Your contact invitation has been sent successfully.",
      })

      // Update the user's status in results
      setResults((prev) => prev.map((user) => (user.id === userId ? { ...user, contact_status: "pending" } : user)))

      onContactAdded?.()
    } catch (error: any) {
      toast({
        title: "Failed to send invitation",
        description: error.message || "Unable to send invitation. Please try again.",
        variant: "destructive",
      })
    } finally {
      setSendingInvitations((prev) => {
        const newSet = new Set(prev)
        newSet.delete(userId)
        return newSet
      })
    }
  }

  const handleStartChat = async (userId: string) => {
    try {
      const chat = await ContactService.startDirectChat(userId)
      toast({
        title: "Chat started!",
        description: "You can now start messaging this contact.",
      })
      setOpen(false)
      // Here you would typically navigate to the chat
    } catch (error: any) {
      toast({
        title: "Failed to start chat",
        description: error.message || "Unable to start chat. Please try again.",
        variant: "destructive",
      })
    }
  }

  const getActionButton = (user: SearchableUser) => {
    const isProcessing = sendingInvitations.has(user.id)

    switch (user.contact_status) {
      case "accepted":
        return (
          <Button size="sm" onClick={() => handleStartChat(user.id)}>
            <MessageCircle className="h-3 w-3 mr-1" />
            Chat
          </Button>
        )
      case "pending":
        return (
          <Button size="sm" variant="outline" disabled>
            <Clock className="h-3 w-3 mr-1" />
            Pending
          </Button>
        )
      case "blocked":
        return (
          <Button size="sm" variant="outline" disabled>
            Blocked
          </Button>
        )
      default:
        return (
          <Button size="sm" variant="outline" onClick={() => handleSendInvitation(user.id)} disabled={isProcessing}>
            {isProcessing ? (
              <>
                <Clock className="h-3 w-3 mr-1 animate-spin" />
                Sending...
              </>
            ) : (
              <>
                <UserPlus className="h-3 w-3 mr-1" />
                Invite
              </>
            )}
          </Button>
        )
    }
  }

  const getStatusBadge = (user: SearchableUser) => {
    if (user.contact_status === "accepted") {
      return (
        <Badge variant="outline" className="text-xs text-green-600">
          <Check className="h-3 w-3 mr-1" />
          Connected
        </Badge>
      )
    }
    if (user.contact_status === "pending") {
      return (
        <Badge variant="outline" className="text-xs text-yellow-600">
          <Clock className="h-3 w-3 mr-1" />
          Pending
        </Badge>
      )
    }
    if (user.is_online) {
      return (
        <Badge variant="outline" className="text-xs text-green-600">
          Online
        </Badge>
      )
    }
    return (
      <Badge variant="outline" className="text-xs text-gray-500">
        Offline
      </Badge>
    )
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm" className="w-full bg-transparent">
          <Search className="h-4 w-4 mr-2" />
          Find People
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[500px] max-h-[80vh]">
        <DialogHeader>
          <DialogTitle>Find People</DialogTitle>
          <DialogDescription>Search for users by username, name, or email to connect with them</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-gray-400" />
            <Input
              placeholder={`Search users... ${results.length > 0 ? `(${results.length} found)` : query.length >= 2 && !loading ? "(no results)" : ""}`}
              value={query}
              onChange={(e) => {
                console.log(`[SearchUsers] Query changed to: "${e.target.value}"`)
                setQuery(e.target.value)
              }}
              className="pl-10"
              autoFocus
            />
          </div>

          {query.trim().length >= 2 && (
            <div className="text-xs text-gray-400 bg-gray-50 p-2 rounded">
              <div>
                Query: "{query}" | Results: {results.length} | Loading: {loading ? "Yes" : "No"}
              </div>
              <div>
                Current User: {currentUser.username} ({currentUser.id})
              </div>
            </div>
          )}

          <ScrollArea className="h-[400px]">
            {loading ? (
              <div className="space-y-3">
                {[...Array(5)].map((_, i) => (
                  <div key={i} className="flex items-center space-x-3 p-3 animate-pulse">
                    <div className="w-10 h-10 bg-gray-200 rounded-full" />
                    <div className="flex-1 space-y-2">
                      <div className="h-4 bg-gray-200 rounded w-3/4" />
                      <div className="h-3 bg-gray-200 rounded w-1/2" />
                    </div>
                  </div>
                ))}
              </div>
            ) : results.length === 0 ? (
              <div className="text-center py-8 text-gray-500">
                <UserPlus className="h-12 w-12 mx-auto mb-4 opacity-50" />
                <p>No users found for "{query}"</p>
                <div className="text-sm mt-4 space-y-2 text-left bg-gray-50 p-4 rounded">
                  <p>
                    <strong>Debug Info:</strong>
                  </p>
                  <p>• Query: "{query}"</p>
                  <p>• Query length: {query.length}</p>
                  <p>
                    • Current user: {currentUser.username} ({currentUser.id})
                  </p>
                  <p>• Loading: {loading ? "Yes" : "No"}</p>
                  <p>• Results count: {results.length}</p>
                  <div className="mt-2">
                    <p>
                      <strong>Try searching for:</strong>
                    </p>
                    <ul className="text-xs space-y-1 mt-1">
                      <li>• "test" (should find test users)</li>
                      <li>• "john" (should find John Doe)</li>
                      <li>• "jane" (should find Jane Smith)</li>
                      <li>• "@example.com" (should find all demo users)</li>
                    </ul>
                  </div>
                </div>
              </div>
            ) : (
              <div className="space-y-2">
                {results.map((user) => (
                  <div
                    key={user.id}
                    className="flex items-center space-x-3 p-3 rounded-lg hover:bg-gray-50 transition-colors"
                  >
                    <div className="relative">
                      <Avatar className="h-10 w-10">
                        <AvatarImage src={user.avatar_url || "/placeholder.svg"} />
                        <AvatarFallback>{user.full_name?.charAt(0) || user.username?.charAt(0) || "U"}</AvatarFallback>
                      </Avatar>
                      {user.is_online && user.contact_status !== "pending" && user.contact_status !== "blocked" && (
                        <div className="absolute -bottom-1 -right-1 w-3 h-3 bg-green-500 rounded-full border-2 border-white" />
                      )}
                    </div>

                    <div className="flex-1 min-w-0">
                      <div className="flex items-center space-x-2 mb-1">
                        <span className="font-medium text-sm truncate">{user.full_name || user.username}</span>
                        {getStatusBadge(user)}
                      </div>
                      <p className="text-xs text-gray-600 truncate">@{user.username}</p>
                      <p className="text-xs text-gray-500 truncate">{user.email}</p>
                      {user.bio && <p className="text-xs text-gray-500 truncate mt-1">{user.bio}</p>}
                    </div>

                    <div className="flex space-x-2">{getActionButton(user)}</div>
                  </div>
                ))}
              </div>
            )}
          </ScrollArea>

          {query.trim().length >= 2 && !loading && (
            <div className="text-xs text-gray-500 text-center">
              Found {results.length} user{results.length !== 1 ? "s" : ""} for "{query}"
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  )
}
