"use client"

import { useState, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { ContactService, type ContactInvitation } from "@/lib/contact-service"
import { Check, X, Clock, UserPlus } from "lucide-react"
import { formatDistanceToNow } from "date-fns"
import { toast } from "@/hooks/use-toast"

interface ContactInvitationsProps {
  onInvitationHandled?: () => void
}

export function ContactInvitations({ onInvitationHandled }: ContactInvitationsProps) {
  const [invitations, setInvitations] = useState<ContactInvitation[]>([])
  const [loading, setLoading] = useState(true)
  const [processing, setProcessing] = useState<Set<string>>(new Set())

  useEffect(() => {
    loadInvitations()
  }, [])

  const loadInvitations = async () => {
    try {
      console.log("[ContactInvitations] Loading invitations...")
      const data = await ContactService.getPendingInvitations()
      console.log(`[ContactInvitations] Loaded ${data.length} invitations`)
      setInvitations(data)
    } catch (error) {
      console.error("Error loading invitations:", error)
      toast({
        title: "Failed to load invitations",
        description: "Unable to load contact invitations. Please try again.",
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  const handleAccept = async (invitationId: string) => {
    setProcessing((prev) => new Set(prev).add(invitationId))

    try {
      await ContactService.acceptContactInvitation(invitationId)
      toast({
        title: "Invitation accepted!",
        description: "You are now connected with this contact.",
      })
      setInvitations((prev) => prev.filter((inv) => inv.id !== invitationId))
      onInvitationHandled?.()
    } catch (error: any) {
      toast({
        title: "Failed to accept invitation",
        description: error.message || "Unable to accept invitation. Please try again.",
        variant: "destructive",
      })
    } finally {
      setProcessing((prev) => {
        const newSet = new Set(prev)
        newSet.delete(invitationId)
        return newSet
      })
    }
  }

  const handleReject = async (invitationId: string) => {
    setProcessing((prev) => new Set(prev).add(invitationId))

    try {
      await ContactService.rejectContactInvitation(invitationId)
      toast({
        title: "Invitation rejected",
        description: "The contact invitation has been declined.",
      })
      setInvitations((prev) => prev.filter((inv) => inv.id !== invitationId))
      onInvitationHandled?.()
    } catch (error: any) {
      toast({
        title: "Failed to reject invitation",
        description: error.message || "Unable to reject invitation. Please try again.",
        variant: "destructive",
      })
    } finally {
      setProcessing((prev) => {
        const newSet = new Set(prev)
        newSet.delete(invitationId)
        return newSet
      })
    }
  }

  if (loading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center">
            <UserPlus className="h-5 w-5 mr-2" />
            Contact Invitations
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-3">
            {[...Array(3)].map((_, i) => (
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
          <UserPlus className="h-5 w-5 mr-2" />
          Contact Invitations
          {invitations.length > 0 && (
            <Badge variant="secondary" className="ml-2">
              {invitations.length}
            </Badge>
          )}
        </CardTitle>
        <CardDescription>People who want to connect with you</CardDescription>
      </CardHeader>
      <CardContent>
        {invitations.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <UserPlus className="h-12 w-12 mx-auto mb-4 opacity-50" />
            <p>No pending invitations</p>
            <p className="text-sm mt-1">When someone sends you a contact request, it will appear here</p>
          </div>
        ) : (
          <ScrollArea className="h-[300px]">
            <div className="space-y-3">
              {invitations.map((invitation) => (
                <div
                  key={invitation.id}
                  className="flex items-center space-x-3 p-3 rounded-lg bg-gray-50 hover:bg-gray-100 transition-colors"
                >
                  <Avatar className="h-10 w-10">
                    <AvatarImage src={invitation.inviter_avatar_url || "/placeholder.svg"} />
                    <AvatarFallback>
                      {invitation.inviter_full_name?.charAt(0) || invitation.inviter_username?.charAt(0) || "U"}
                    </AvatarFallback>
                  </Avatar>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center space-x-2 mb-1">
                      <span className="font-medium text-sm truncate">
                        {invitation.inviter_full_name || invitation.inviter_username}
                      </span>
                      <Badge variant="outline" className="text-xs">
                        @{invitation.inviter_username}
                      </Badge>
                    </div>
                    <p className="text-xs text-gray-600">
                      Sent {formatDistanceToNow(new Date(invitation.invited_at), { addSuffix: true })}
                    </p>
                  </div>

                  <div className="flex space-x-2">
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => handleAccept(invitation.id)}
                      disabled={processing.has(invitation.id)}
                      className="text-green-600 hover:text-green-700 hover:bg-green-50"
                    >
                      {processing.has(invitation.id) ? (
                        <Clock className="h-3 w-3 animate-spin" />
                      ) : (
                        <Check className="h-3 w-3" />
                      )}
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => handleReject(invitation.id)}
                      disabled={processing.has(invitation.id)}
                      className="text-red-600 hover:text-red-700 hover:bg-red-50"
                    >
                      {processing.has(invitation.id) ? (
                        <Clock className="h-3 w-3 animate-spin" />
                      ) : (
                        <X className="h-3 w-3" />
                      )}
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          </ScrollArea>
        )}
      </CardContent>
    </Card>
  )
}
