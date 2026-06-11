import { BookOpen, Home, ScrollText } from 'lucide-react'
import { Link, NavLink, Outlet } from 'react-router-dom'
import { cn } from '@/lib/utils'

const navigation = [
  { to: '/', label: 'Inicio', icon: Home },
  { to: '/encontros', label: 'Encontros', icon: BookOpen },
  { to: '/artigos', label: 'Artigos', icon: ScrollText },
]

export function SiteShell() {
  return (
    <div className="min-h-screen bg-ink-glow text-foreground">
      <div className="fixed inset-x-0 top-0 z-50 border-b border-stone-200/60 bg-[rgba(251,247,235,0.78)] backdrop-blur-xl">
        <div className="mx-auto flex h-[96px] max-w-6xl items-center justify-between gap-6 px-4 sm:px-6">
          <Link to="/" className="shrink-0 py-3">
            <span className="font-display text-[1.65rem] tracking-[0.18em] text-stone-900 sm:text-[1.9rem]">
              Catechesis
            </span>
          </Link>
          <div className="hidden items-center gap-2 md:ml-auto md:flex">
            {navigation.map(({ to, label }) => (
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
                {label}
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
          {navigation.map(({ to, label, icon: Icon }) => (
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
              {label}
            </NavLink>
          ))}
        </div>
      </nav>
    </div>
  )
}
