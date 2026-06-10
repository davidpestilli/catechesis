import { BookOpen, Home, ScrollText } from 'lucide-react'
import { Link, NavLink, Outlet } from 'react-router-dom'
import catechesisIlluminura from '@/assets/branding/catechesis-illuminura.png'
import { cn } from '@/lib/utils'

const navigation = [
  { to: '/', label: 'Inicio', icon: Home },
  { to: '/encontros', label: 'Encontros', icon: BookOpen },
  { to: '/artigos', label: 'Artigos', icon: ScrollText },
]

export function SiteShell() {
  return (
    <div className="min-h-screen bg-ink-glow text-foreground">
      <div className="fixed inset-x-0 top-0 z-50 border-b border-stone-200/70 bg-[rgba(251,247,235,0.86)] backdrop-blur">
        <div className="mx-auto flex h-[88px] max-w-6xl items-center justify-between gap-3 px-4">
          <Link to="/" className="relative h-[68px] w-[230px] shrink-0 overflow-hidden">
            <img
              src={catechesisIlluminura}
              alt="Catechesis"
              className="absolute left-0 top-1/2 h-[7.50rem] w-auto max-w-none -translate-y-1/2 sm:h-[5rem]"
            />
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

      <main className="pt-[88px]">
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
