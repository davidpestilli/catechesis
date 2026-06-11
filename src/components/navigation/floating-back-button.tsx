import { ArrowLeft } from 'lucide-react'
import { Link } from 'react-router-dom'
import { cn } from '@/lib/utils'

interface FloatingBackButtonProps {
  to: string
  label: string
  className?: string
}

export function FloatingBackButton({ to, label, className }: FloatingBackButtonProps) {
  return (
    <Link
      to={to}
      aria-label={label}
      title={label}
      className={cn(
        'fixed left-4 top-[108px] z-30 flex h-12 w-12 items-center justify-center rounded-full border border-stone-200/80 bg-[rgba(251,247,235,0.94)] text-stone-800 shadow-[0_18px_45px_rgba(74,61,35,0.18)] backdrop-blur transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30 sm:left-6 sm:top-[114px]',
        className,
      )}
    >
      <ArrowLeft className="h-5 w-5" />
      <span className="sr-only">{label}</span>
    </Link>
  )
}
