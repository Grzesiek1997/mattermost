"use client"

import { useState, useEffect } from "react"
import { Bell } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { cn } from "@/lib/utils"

interface NotificationBadgeProps {
  count: number
  onClick: () => void
  hasNew?: boolean
}

export function NotificationBadge({ count, onClick, hasNew = false }: NotificationBadgeProps) {
  const [isGlowing, setIsGlowing] = useState(false)

  useEffect(() => {
    if (hasNew) {
      setIsGlowing(true)
      // Stop glowing after 3 seconds
      const timer = setTimeout(() => setIsGlowing(false), 3000)
      return () => clearTimeout(timer)
    }
  }, [hasNew])

  return (
    <div className="relative">
      <Button
        variant="ghost"
        size="sm"
        onClick={onClick}
        className={cn(
          "relative transition-all duration-300",
          isGlowing && "animate-pulse bg-green-100 hover:bg-green-200",
        )}
      >
        <Bell
          className={cn("h-5 w-5 transition-colors duration-300", isGlowing ? "text-green-600" : "text-gray-600")}
        />
        {count > 0 && (
          <Badge
            variant="destructive"
            className={cn(
              "absolute -top-1 -right-1 h-5 w-5 flex items-center justify-center text-xs transition-all duration-300",
              isGlowing && "bg-green-500 animate-bounce",
            )}
          >
            {count > 9 ? "9+" : count}
          </Badge>
        )}
      </Button>

      {isGlowing && (
        <div className="absolute inset-0 rounded-md bg-green-400 opacity-20 animate-ping pointer-events-none" />
      )}
    </div>
  )
}
