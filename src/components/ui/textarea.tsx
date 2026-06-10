import * as React from 'react'
import { cn } from '@/lib/utils'

export const Textarea = React.forwardRef<
  HTMLTextAreaElement,
  React.TextareaHTMLAttributes<HTMLTextAreaElement>
>(({ className, ...props }, ref) => {
  return (
    <textarea
      ref={ref}
      className={cn(
        'flex min-h-[120px] w-full rounded-3xl border border-input bg-white/90 px-4 py-3 text-sm text-stone-900 outline-none transition placeholder:text-stone-400 focus:border-primary focus:ring-2 focus:ring-primary/20',
        className,
      )}
      {...props}
    />
  )
})

Textarea.displayName = 'Textarea'
