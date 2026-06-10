import { BookOpen, Home, LockKeyhole, ScrollText } from 'lucide-react'
import { Link, NavLink, Outlet, useLocation } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { useAuth } from '@/providers/auth-provider'

const navigation = [
  { to: '/', label: 'Inicio', icon: Home },
  { to: '/encontros', label: 'Encontros', icon: BookOpen },
  { to: '/artigos', label: 'Artigos', icon: ScrollText },
]

export function SiteShell() {
  const { isAuthenticated, signOut } = useAuth()
  const location = useLocation()

  return (
    <div className="min-h-screen bg-ink-glow text-foreground">
      <div className="fixed inset-x-0 top-0 z-50 border-b border-stone-200/70 bg-[rgba(251,247,235,0.86)] backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-4 py-3">
          <Link to="/" className="font-gothic text-2xl text-stone-900">
            Catechesis
          </Link>
          <div className="hidden items-center gap-2 md:flex">
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
          <div className="flex items-center gap-2">
            {isAuthenticated ? (
              <>
                <Button asChild variant="outline" size="sm">
                  <Link to="/admin">Painel</Link>
                </Button>
                <Button variant="ghost" size="sm" onClick={() => void signOut()}>
                  Sair
                </Button>
              </>
            ) : (
              <Button asChild size="sm">
                <Link to="/login" state={{ from: location }}>
                  <LockKeyhole className="mr-2 h-4 w-4" />
                  Entrar
                </Link>
              </Button>
            )}
          </div>
        </div>
      </div>

      <main className="pt-[78px]">
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
