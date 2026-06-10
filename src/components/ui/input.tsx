import * as React from 'react'
import { cn } from '@/lib/utils'

export const Input = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(
  ({ className, ...props }, ref) => {
    return (
      <input
        ref={ref}
        className={cn(
          'flex h-11 w-full rounded-2xl border border-input bg-white/90 px-4 py-2 text-sm text-stone-900 outline-none transition placeholder:text-stone-400 focus:border-primary focus:ring-2 focus:ring-primary/20',
          className,
        )}
        {...props}
      />
    )
  },
)

Input.displayName = 'Input'
