import { useState } from 'react'
import { LogOut, SquareArrowOutUpRight } from 'lucide-react'
import { Link, Outlet, useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/providers/auth-provider'

export function AdminShell() {
  const navigate = useNavigate()
  const { signOut } = useAuth()
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
        <div className="mx-auto flex max-w-7xl items-center justify-between gap-3 px-4 py-3">
          <Link to="/" className="shrink-0 py-2">
            <span className="font-display text-[1.6rem] tracking-[0.14em] text-stone-900 sm:text-[1.8rem]">
              Catequético
            </span>
          </Link>

          <div className="flex shrink-0 items-center gap-1 sm:gap-2">
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
