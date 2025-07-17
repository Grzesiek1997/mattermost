"use client"

import { useState, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { ContactService } from "@/lib/contact-service"
import type { User } from "@/lib/supabase"
import { Users, MessageCircle, Search, MoreHorizontal } from "lucide-react"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { toast } from "@/hooks/use-toast"

interface ContactsListProps {
  onStartChat?: (contactId: string) => void
}

export function ContactsList({ onStartChat }: ContactsListProps) {
  const [contacts, setContacts] = useState<User[]>([])
  const [loading, setLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState("")

  useEffect(() => {
    loadContacts()
  }, [])

  const loadContacts = async () => {
    try {
      const data = await ContactService.getContacts()
      setContacts(data)
    } catch (error) {
      console.error("Error loading contacts:", error)
    } finally {
      setLoading(false)
    }
  }

  const handleStartChat = async (contactId: string) => {
    try {
      const chat = await ContactService.startDirectChat(contactId)
      toast({
        title: "Chat started!",
        description: "You can now start messaging this contact.",
      })
      onStartChat?.(contactId)
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to start chat",
        variant: "destructive",
      })
    }
  }

  const handleRemoveContact = async (contactId: string) => {
    try {
      await ContactService.removeContact(contactId)
      toast({
        title: "Contact removed",
        description: "The contact has been removed from your list.",
      })
      setContacts((prev) => prev.filter((contact) => contact.id !== contactId))
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to remove contact",
        variant: "destructive",
      })
    }
  }

  const handleBlockContact = async (contactId: string) => {
    try {
      await ContactService.blockContact(contactId)
      toast({
        title: "Contact blocked",
        description: "The contact has been blocked.",
      })
      setContacts((prev) => prev.filter((contact) => contact.id !== contactId))
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to block contact",
        variant: "destructive",
      })
    }
  }

  const filteredContacts = contacts.filter(
    (contact) =>
      contact.full_name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      contact.username?.toLowerCase().includes(searchQuery.toLowerCase()),
  )

  if (loading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center">
            <Users className="h-5 w-5 mr-2" />
            My Contacts
          </CardTitle>
        </CardHeader>
        <CardContent>
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
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center">
          <Users className="h-5 w-5 mr-2" />
          My Contacts
          {contacts.length > 0 && (
            <Badge variant="secondary" className="ml-2">
              {contacts.length}
            </Badge>
          )}
        </CardTitle>
        <CardDescription>Your connected contacts</CardDescription>
      </CardHeader>
      <CardContent>
        {contacts.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <Users className="h-12 w-12 mx-auto mb-4 opacity-50" />
            <p>No contacts yet</p>
            <p className="text-sm">Start by finding and inviting people!</p>
          </div>
        ) : (
          <div className="space-y-4">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-gray-400" />
              <Input
                placeholder="Search contacts..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-10"
              />
            </div>

            <ScrollArea className="h-[400px]">
              <div className="space-y-2">
                {filteredContacts.map((contact) => (
                  <div
                    key={contact.id}
                    className="flex items-center space-x-3 p-3 rounded-lg hover:bg-gray-50 transition-colors"
                  >
                    <div className="relative">
                      <Avatar className="h-10 w-10">
                        <AvatarImage src={contact.avatar_url || "/placeholder.svg"} />
                        <AvatarFallback>
                          {contact.full_name?.charAt(0) || contact.username?.charAt(0) || "U"}
                        </AvatarFallback>
                      </Avatar>
                      {contact.is_online && (
                        <div className="absolute -bottom-1 -right-1 w-3 h-3 bg-green-500 rounded-full border-2 border-white" />
                      )}
                    </div>

                    <div className="flex-1 min-w-0">
                      <div className="flex items-center space-x-2">
                        <span className="font-medium text-sm truncate">{contact.full_name || contact.username}</span>
                        {contact.is_online ? (
                          <Badge variant="outline" className="text-xs text-green-600">
                            Online
                          </Badge>
                        ) : (
                          <Badge variant="outline" className="text-xs text-gray-500">
                            Offline
                          </Badge>
                        )}
                      </div>
                      <p className="text-xs text-gray-600 truncate">@{contact.username}</p>
                      {contact.bio && <p className="text-xs text-gray-500 truncate mt-1">{contact.bio}</p>}
                    </div>

                    <div className="flex items-center space-x-2">
                      <Button size="sm" onClick={() => handleStartChat(contact.id)}>
                        <MessageCircle className="h-3 w-3 mr-1" />
                        Chat
                      </Button>

                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button size="sm" variant="ghost">
                            <MoreHorizontal className="h-4 w-4" />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent>
                          <DropdownMenuItem onClick={() => handleStartChat(contact.id)}>Start Chat</DropdownMenuItem>
                          <DropdownMenuItem onClick={() => handleRemoveContact(contact.id)}>
                            Remove Contact
                          </DropdownMenuItem>
                          <DropdownMenuItem onClick={() => handleBlockContact(contact.id)} className="text-red-600">
                            Block Contact
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </div>
                  </div>
                ))}
              </div>
            </ScrollArea>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
