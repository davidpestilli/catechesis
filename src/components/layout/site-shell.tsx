import { useEffect, useRef, useState } from 'react'
import { BookOpen, Home, LogIn, Menu, ScrollText, X } from 'lucide-react'
import { Link, NavLink, Outlet, useLocation } from 'react-router-dom'
import { cn } from '@/lib/utils'
import { useAuth } from '@/providers/auth-provider'

const navigation = [
  { to: '/', label: 'Inicio', icon: Home },
  { to: '/encontros', label: 'Turmas', icon: BookOpen },
  { to: '/diversos', label: 'Diversos', icon: ScrollText },
]

export function SiteShell() {
  const [menuOpen, setMenuOpen] = useState(false)
  const menuRef = useRef<HTMLDivElement | null>(null)
  const location = useLocation()
  const { isAuthenticated } = useAuth()

  useEffect(() => {
    setMenuOpen(false)
  }, [location.pathname])

  useEffect(() => {
    if (!menuOpen) return

    function handlePointerDown(event: MouseEvent) {
      if (!menuRef.current?.contains(event.target as Node)) {
        setMenuOpen(false)
      }
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        setMenuOpen(false)
      }
    }

    window.addEventListener('mousedown', handlePointerDown)
    window.addEventListener('keydown', handleKeyDown)

    return () => {
      window.removeEventListener('mousedown', handlePointerDown)
      window.removeEventListener('keydown', handleKeyDown)
    }
  }, [menuOpen])

  const utilityItem = {
    to: isAuthenticated ? '/admin' : '/login',
    label: isAuthenticated ? 'Painel' : 'Login',
    icon: LogIn,
  }

  return (
    <div className="min-h-screen bg-ink-glow text-foreground" style={{ ['--site-header-height' as string]: '76px' }}>
      <div className="fixed inset-x-0 top-0 z-50 overflow-visible border-b border-stone-200/70 bg-[linear-gradient(180deg,rgba(251,247,235,0.96),rgba(245,238,222,0.84))] backdrop-blur-xl">
        <div className="absolute inset-x-0 top-0 h-px bg-[linear-gradient(90deg,transparent,rgba(180,138,58,0.72),transparent)]" />
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(216,185,120,0.16),transparent_42%)]" />
        <div className="absolute right-8 top-full h-14 w-40 -translate-y-7 rounded-full bg-amber-200/25 blur-3xl" />

        <div className="relative mx-auto flex h-[76px] max-w-6xl items-center justify-between px-4 sm:px-6">
          <Link to="/" className="min-w-0">
            <div className="flex items-center gap-3">
              <span className="h-8 w-px bg-[linear-gradient(180deg,rgba(176,132,48,0.18),rgba(176,132,48,0.78),rgba(176,132,48,0.18))]" />
              <span className="truncate font-gothic text-[1.85rem] tracking-[0.08em] text-stone-900 sm:text-[2rem]">
                Catequético
              </span>
            </div>
          </Link>

          <div className="relative" ref={menuRef}>
            <button
              type="button"
              aria-expanded={menuOpen}
              aria-controls="site-header-menu"
              aria-label={menuOpen ? 'Fechar menu' : 'Abrir menu'}
              onClick={() => setMenuOpen((value) => !value)}
              className={cn(
                'flex h-11 w-11 items-center justify-center rounded-full border border-stone-200/80 bg-white/65 text-stone-700 shadow-[0_12px_30px_rgba(68,49,20,0.07)] backdrop-blur transition',
                menuOpen && 'border-stone-900 bg-stone-900 text-stone-50',
              )}
            >
              {menuOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
            </button>

            <div
              id="site-header-menu"
              className={cn(
                'absolute right-0 top-[calc(100%+0.75rem)] w-64 origin-top-right rounded-[24px] border border-stone-200/80 bg-[rgba(255,252,246,0.94)] p-3 shadow-[0_24px_60px_rgba(68,49,20,0.14)] backdrop-blur-xl transition duration-200',
                menuOpen
                  ? 'pointer-events-auto translate-y-0 scale-100 opacity-100'
                  : 'pointer-events-none -translate-y-2 scale-95 opacity-0',
              )}
            >
              <div className="mb-2 px-3 pt-1 text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-stone-500">
                Navegacao
              </div>
              <div className="space-y-1">
                {[...navigation, utilityItem].map(({ to, label, icon: Icon }) => (
                  <NavLink
                    key={to}
                    to={to}
                    className={({ isActive }) =>
                      cn(
                        'flex items-center gap-3 rounded-[18px] px-3 py-3 text-sm text-stone-700 transition hover:bg-stone-100/90',
                        isActive && 'bg-stone-900 text-stone-50 shadow-sm hover:bg-stone-900',
                      )
                    }
                  >
                    <Icon className="h-4 w-4 shrink-0" />
                    <span className="font-medium">{label}</span>
                  </NavLink>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>

      <main style={{ paddingTop: 'var(--site-header-height)' }}>
        <Outlet />
      </main>
    </div>
  )
}
