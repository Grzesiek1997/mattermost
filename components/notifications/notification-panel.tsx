"use client"

import { useState, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Bell, Check, X, UserPlus, MessageCircle } from "lucide-react"
import { formatDistanceToNow } from "date-fns"
import { toast } from "@/hooks/use-toast"
import { supabase } from "@/lib/supabase"
import { ContactService } from "@/lib/contact-service"

interface Notification {
  id: string
  type: "contact_invitation" | "contact_accepted" | "message" | "system"
  title: string
  message?: string
  data?: any
  is_read: boolean
  created_at: string
}

interface NotificationPanelProps {
  onNotificationHandled?: () => void
}

export function NotificationPanel({ onNotificationHandled }: NotificationPanelProps) {
  const [notifications, setNotifications] = useState<Notification[]>([])
  const [loading, setLoading] = useState(true)
  const [processing, setProcessing] = useState<Set<string>>(new Set())

  useEffect(() => {
    loadNotifications()

    // Subscribe to real-time notifications
    const setupSubscription = async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user) return

      const channel = supabase
        .channel("notifications")
        .on(
          "postgres_changes",
          {
            event: "INSERT",
            schema: "public",
            table: "notifications",
            filter: `user_id=eq.${user.id}`,
          },
          (payload) => {
            console.log("[NotificationPanel] New notification:", payload)
            setNotifications((prev) => [payload.new as Notification, ...prev])
          },
        )
        .subscribe()

      return () => {
        supabase.removeChannel(channel)
      }
    }

    const cleanup = setupSubscription()
    return () => {
      cleanup.then((fn) => fn && fn())
    }
  }, [])

  const loadNotifications = async () => {
    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) return

      const { data, error } = await supabase
        .from("notifications")
        .select("*")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(50)

      if (error) throw error

      setNotifications(data || [])
    } catch (error) {
      console.error("Error loading notifications:", error)
      toast({
        title: "Failed to load notifications",
        description: "Unable to load notifications. Please try again.",
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  const markAsRead = async (notificationId: string) => {
    try {
      const { error } = await supabase.from("notifications").update({ is_read: true }).eq("id", notificationId)

      if (error) throw error

      setNotifications((prev) => prev.map((n) => (n.id === notificationId ? { ...n, is_read: true } : n)))
    } catch (error) {
      console.error("Error marking notification as read:", error)
    }
  }

  const handleContactInvitation = async (notificationId: string, action: "accept" | "reject") => {
    setProcessing((prev) => new Set(prev).add(notificationId))

    try {
      const notification = notifications.find((n) => n.id === notificationId)
      if (!notification?.data?.invitation_id) return

      if (action === "accept") {
        await ContactService.acceptContactInvitation(notification.data.invitation_id)
        toast({
          title: "Invitation accepted!",
          description: "You are now connected with this contact.",
        })
      } else {
        await ContactService.rejectContactInvitation(notification.data.invitation_id)
        toast({
          title: "Invitation rejected",
          description: "The contact invitation has been declined.",
        })
      }

      // Mark notification as read and remove from list
      await markAsRead(notificationId)
      setNotifications((prev) => prev.filter((n) => n.id !== notificationId))
      onNotificationHandled?.()
    } catch (error: any) {
      toast({
        title: `Failed to ${action} invitation`,
        description: error.message || `Unable to ${action} invitation. Please try again.`,
        variant: "destructive",
      })
    } finally {
      setProcessing((prev) => {
        const newSet = new Set(prev)
        newSet.delete(notificationId)
        return newSet
      })
    }
  }

  const getNotificationIcon = (type: string) => {
    switch (type) {
      case "contact_invitation":
        return <UserPlus className="h-4 w-4" />
      case "contact_accepted":
        return <Check className="h-4 w-4" />
      case "message":
        return <MessageCircle className="h-4 w-4" />
      default:
        return <Bell className="h-4 w-4" />
    }
  }

  const unreadCount = notifications.filter((n) => !n.is_read).length

  if (loading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center">
            <Bell className="h-5 w-5 mr-2" />
            Notifications
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
    <Dialog open={true}>
      <DialogContent className="sm:max-w-[600px] max-h-[80vh]">
        <DialogHeader>
          <DialogTitle className="flex items-center">
            <Bell className="h-5 w-5 mr-2" />
            Notifications
            {unreadCount > 0 && (
              <Badge variant="destructive" className="ml-2">
                {unreadCount}
              </Badge>
            )}
          </DialogTitle>
          <DialogDescription>Your recent notifications and invitations</DialogDescription>
        </DialogHeader>

        {notifications.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <Bell className="h-12 w-12 mx-auto mb-4 opacity-50" />
            <p>No notifications</p>
            <p className="text-sm mt-1">When you receive invitations or messages, they will appear here</p>
          </div>
        ) : (
          <ScrollArea className="h-[400px]">
            <div className="space-y-3">
              {notifications.map((notification) => (
                <div
                  key={notification.id}
                  className={`flex items-start space-x-3 p-3 rounded-lg transition-colors ${
                    notification.is_read ? "bg-gray-50" : "bg-blue-50 border border-blue-200"
                  }`}
                  onClick={() => !notification.is_read && markAsRead(notification.id)}
                >
                  <div className="flex-shrink-0 mt-1">{getNotificationIcon(notification.type)}</div>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center space-x-2 mb-1">
                      <span className={`font-medium text-sm ${!notification.is_read ? "font-semibold" : ""}`}>
                        {notification.title}
                      </span>
                      {!notification.is_read && <div className="w-2 h-2 bg-blue-500 rounded-full" />}
                    </div>
                    {notification.message && <p className="text-sm text-gray-600 mb-2">{notification.message}</p>}
                    <p className="text-xs text-gray-500">
                      {formatDistanceToNow(new Date(notification.created_at), { addSuffix: true })}
                    </p>

                    {/* Contact invitation actions */}
                    {notification.type === "contact_invitation" && !notification.is_read && (
                      <div className="flex space-x-2 mt-3">
                        <Button
                          size="sm"
                          onClick={(e) => {
                            e.stopPropagation()
                            handleContactInvitation(notification.id, "accept")
                          }}
                          disabled={processing.has(notification.id)}
                          className="text-green-600 hover:text-green-700 hover:bg-green-50"
                        >
                          <Check className="h-3 w-3 mr-1" />
                          Accept
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={(e) => {
                            e.stopPropagation()
                            handleContactInvitation(notification.id, "reject")
                          }}
                          disabled={processing.has(notification.id)}
                          className="text-red-600 hover:text-red-700 hover:bg-red-50"
                        >
                          <X className="h-3 w-3 mr-1" />
                          Reject
                        </Button>
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </ScrollArea>
        )}
      </DialogContent>
    </Dialog>
  )
}
