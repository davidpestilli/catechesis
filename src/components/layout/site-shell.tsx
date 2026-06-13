import { BookOpen, Home, ScrollText } from 'lucide-react'
import { Link, NavLink, Outlet } from 'react-router-dom'
import { cn } from '@/lib/utils'

const navigation = [
  { to: '/', label: 'Início', icon: Home, ornate: true },
  { to: '/encontros', label: 'Turmas', icon: BookOpen, ornate: true },
  { to: '/diversos', label: 'Diversos', icon: ScrollText, ornate: true },
]

export function SiteShell() {
  return (
    <div className="min-h-screen bg-ink-glow text-foreground">
      <div className="fixed inset-x-0 top-0 z-50 border-b border-stone-200/60 bg-[rgba(251,247,235,0.78)] backdrop-blur-xl">
        <div className="mx-auto grid h-[96px] max-w-6xl grid-cols-1 items-center px-4 sm:px-6 md:grid-cols-[1fr_auto]">
          <Link to="/" className="justify-self-center py-3 md:justify-self-start">
            <span className="font-gothic text-[2rem] tracking-[0.08em] text-stone-900 sm:text-[2.2rem]">
              Catequético
            </span>
          </Link>
          <div className="hidden items-center gap-2 md:justify-self-end md:flex">
            {navigation.map(({ to, label, ornate }) => (
              <NavLink
                key={to}
                to={to}
                className={({ isActive }) =>
                  cn(
                    'rounded-full px-4 py-2 text-sm font-medium text-stone-600 transition hover:bg-stone-100',
                    isActive && 'bg-stone-900 text-stone-50 hover:bg-stone-900',
                  )
                }
              >
                <span
                  className={cn(
                    ornate
                      ? 'font-gothic text-lg leading-none tracking-normal'
                      : 'text-sm font-medium',
                  )}
                >
                  {label}
                </span>
              </NavLink>
            ))}
          </div>
        </div>
      </div>

      <main className="pt-[96px]">
        <Outlet />
      </main>

      <nav className="fixed inset-x-0 bottom-0 z-40 border-t border-stone-200 bg-[rgba(251,247,235,0.96)] px-3 py-2 backdrop-blur md:hidden">
        <div className="mx-auto grid max-w-md grid-cols-3 gap-2">
          {navigation.map(({ to, label, icon: Icon, ornate }) => (
            <NavLink
              key={to}
              to={to}
              className={({ isActive }) =>
                cn(
                  'flex flex-col items-center rounded-2xl px-3 py-2 text-[11px] font-semibold text-stone-500',
                  isActive && 'bg-stone-900 text-stone-50',
                )
              }
            >
              <Icon className="mb-1 h-4 w-4" />
              <span
                className={cn(
                  ornate ? 'font-gothic text-[1.15rem] leading-none tracking-normal' : 'leading-none',
                )}
              >
                {label}
              </span>
            </NavLink>
          ))}
        </div>
      </nav>
    </div>
  )
}
