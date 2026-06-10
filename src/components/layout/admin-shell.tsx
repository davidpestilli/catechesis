import { useState } from 'react'
import { LogOut, Shield, SquareArrowOutUpRight } from 'lucide-react'
import { Link, Outlet, useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import catechesisIlluminura from '@/assets/branding/catechesis-illuminura.png'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/providers/auth-provider'

export function AdminShell() {
  const navigate = useNavigate()
  const { user, signOut } = useAuth()
  const [isSigningOut, setIsSigningOut] = useState(false)

  async function handleSignOut() {
    try {
      setIsSigningOut(true)
      await signOut()
      navigate('/login', { replace: true })
      toast.success('Sessao encerrada.')
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Nao foi possivel encerrar a sessao.'
      toast.error(message)
    } finally {
      setIsSigningOut(false)
    }
  }

  return (
    <div className="min-h-screen bg-[radial-gradient(circle_at_top,rgba(214,191,132,0.24),transparent_30%),linear-gradient(180deg,#f8f4ea_0%,#efe6d2_100%)] text-foreground">
      <header className="sticky top-0 z-40 border-b border-stone-200/80 bg-[rgba(250,246,236,0.92)] backdrop-blur">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center gap-3 px-4 py-3">
          <Link to="/" className="relative h-[58px] w-[184px] shrink-0 overflow-hidden">
            <img
              src={catechesisIlluminura}
              alt="Catechesis"
              className="absolute left-0 top-1/2 h-[6.2rem] w-auto max-w-none -translate-y-1/2"
            />
          </Link>

          <div className="min-w-[220px] flex-1">
            <p className="text-[11px] font-semibold uppercase tracking-[0.24em] text-stone-500">
              painel administrativo
            </p>
            <div className="mt-1 flex flex-wrap items-center gap-2">
              <h1 className="font-display text-2xl text-stone-900">Edicao interna</h1>
              <span className="inline-flex items-center gap-1 rounded-full border border-stone-200 bg-white/80 px-3 py-1 text-xs text-stone-600">
                <Shield className="h-3.5 w-3.5" />
                {user?.name ?? user?.email ?? 'Editor'}
              </span>
            </div>
          </div>

          <div className="flex w-full flex-wrap items-center gap-2 sm:w-auto sm:justify-end">
            <Button variant="outline" size="sm" asChild>
              <Link to="/">
                <SquareArrowOutUpRight className="mr-2 h-4 w-4" />
                Ver site
              </Link>
            </Button>
            <Button variant="ghost" size="sm" onClick={() => void handleSignOut()} disabled={isSigningOut}>
              <LogOut className="mr-2 h-4 w-4" />
              {isSigningOut ? 'Saindo...' : 'Sair'}
            </Button>
          </div>
        </div>
      </header>

      <main className="pb-10">
        <Outlet />
      </main>
    </div>
  )
}
