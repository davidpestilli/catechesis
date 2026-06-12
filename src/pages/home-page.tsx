import { Link } from 'react-router-dom'
import { LockKeyhole } from 'lucide-react'
import { HeroBanner } from '@/components/home/hero-banner'
import { Button } from '@/components/ui/button'
import { useCMSState } from '@/hooks/use-cms'
import { useAuth } from '@/providers/auth-provider'

export function HomePage() {
  const { data } = useCMSState()
  const { isAuthenticated } = useAuth()

  if (!data) {
    return <div className="px-4 py-16 text-stone-700">Carregando conteudo...</div>
  }

  return (
    <div className="pb-24">
      <HeroBanner settings={data.settings} />

      <section className="border-t border-stone-200/80 bg-white/60">
        <div className="mx-auto max-w-6xl px-4 py-14">
          <div className="flex flex-col gap-4 rounded-[28px] border border-stone-200 bg-stone-50/80 p-5 md:flex-row md:items-center md:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-stone-500">
                acesso interno
              </p>
              <h3 className="mt-2 font-display text-2xl text-stone-900">
                Area do editor
              </h3>
              <p className="mt-2 max-w-2xl text-sm leading-7 text-stone-700">
                O login fica reservado a poucos usuarios responsaveis pela edicao de turmas, encontros, materiais e artigos.
              </p>
            </div>
            <Button asChild size="lg">
              <Link to={isAuthenticated ? '/admin' : '/login'}>
                <LockKeyhole className="mr-2 h-4 w-4" />
                {isAuthenticated ? 'Abrir painel' : 'Entrar'}
              </Link>
            </Button>
          </div>
        </div>
      </section>
    </div>
  )
}
