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
      <div className="fixed inset-x-0 top-0 z-50 overflow-hidden border-b border-stone-200/70 bg-[linear-gradient(180deg,rgba(251,247,235,0.96),rgba(245,238,222,0.84))] backdrop-blur-xl">
        <div className="absolute inset-x-0 top-0 h-px bg-[linear-gradient(90deg,transparent,rgba(180,138,58,0.72),transparent)]" />
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(216,185,120,0.16),transparent_42%)]" />
        <div className="absolute left-1/2 top-full h-16 w-56 -translate-x-1/2 -translate-y-8 rounded-full bg-amber-200/30 blur-3xl" />

        <div className="relative mx-auto flex min-h-[122px] max-w-6xl flex-col gap-4 px-4 py-3 sm:px-6 md:min-h-[112px] md:flex-row md:items-center md:justify-between">
          <Link to="/" className="self-center md:self-auto">
            <div className="flex flex-col items-center rounded-[28px] border border-stone-200/80 bg-[rgba(255,252,246,0.72)] px-5 py-3 shadow-[0_14px_36px_rgba(68,49,20,0.08)] backdrop-blur md:items-start">
              <span className="text-[0.62rem] font-semibold uppercase tracking-[0.34em] text-stone-500">
                Plataforma de catequese
              </span>
              <span className="mt-1 font-gothic text-[1.95rem] tracking-[0.08em] text-stone-900 sm:text-[2.15rem]">
                Catequético
              </span>
              <span className="mt-2 h-px w-20 bg-[linear-gradient(90deg,transparent,rgba(176,132,48,0.8),transparent)] md:w-24 md:bg-[linear-gradient(90deg,rgba(176,132,48,0.8),transparent)]" />
            </div>
          </Link>

          <div className="hidden items-center gap-2 rounded-full border border-stone-200/80 bg-white/55 p-2 shadow-[0_12px_30px_rgba(68,49,20,0.06)] backdrop-blur md:flex">
            {navigation.map(({ to, label, ornate }) => (
              <NavLink
                key={to}
                to={to}
                className={({ isActive }) =>
                  cn(
                    'rounded-full px-4 py-2 text-sm font-medium text-stone-600 transition hover:bg-stone-100/90',
                    isActive && 'bg-stone-900 text-stone-50 shadow-sm hover:bg-stone-900',
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

      <main className="pt-[122px] md:pt-[112px]">
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
