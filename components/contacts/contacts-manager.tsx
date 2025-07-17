"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { SearchUsersDialog } from "./search-users-dialog"
import { ContactInvitations } from "./contact-invitations"
import { ContactsList } from "./contacts-list"
import type { User } from "@/lib/supabase"
import { Users, UserPlus, Search } from "lucide-react"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"

interface ContactsManagerProps {
  currentUser: User
  onStartChat?: (contactId: string) => void
}

export function ContactsManager({ currentUser, onStartChat }: ContactsManagerProps) {
  const [open, setOpen] = useState(false)
  const [refreshTrigger, setRefreshTrigger] = useState(0)

  const handleRefresh = () => {
    setRefreshTrigger((prev) => prev + 1)
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm">
          <Users className="h-4 w-4 mr-2" />
          Contacts
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[700px] max-h-[80vh]">
        <DialogHeader>
          <DialogTitle>Contact Manager</DialogTitle>
          <DialogDescription>Manage your contacts, invitations, and find new people to connect with</DialogDescription>
        </DialogHeader>

        <Tabs defaultValue="contacts" className="w-full">
          <TabsList className="grid w-full grid-cols-3">
            <TabsTrigger value="contacts">
              <Users className="h-4 w-4 mr-2" />
              Contacts
            </TabsTrigger>
            <TabsTrigger value="invitations">
              <UserPlus className="h-4 w-4 mr-2" />
              Invitations
            </TabsTrigger>
            <TabsTrigger value="search">
              <Search className="h-4 w-4 mr-2" />
              Find People
            </TabsTrigger>
          </TabsList>

          <TabsContent value="contacts" className="space-y-4">
            <ContactsList onStartChat={onStartChat} key={refreshTrigger} />
          </TabsContent>

          <TabsContent value="invitations" className="space-y-4">
            <ContactInvitations onInvitationHandled={handleRefresh} key={refreshTrigger} />
          </TabsContent>

          <TabsContent value="search" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center">
                  <Search className="h-5 w-5 mr-2" />
                  Find New People
                </CardTitle>
                <CardDescription>Search for users and send them contact invitations</CardDescription>
              </CardHeader>
              <CardContent>
                <SearchUsersDialog currentUser={currentUser} onContactAdded={handleRefresh} />
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </DialogContent>
    </Dialog>
  )
}
