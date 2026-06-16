import { HeroBanner } from '@/components/home/hero-banner'
import { useCMSState } from '@/hooks/use-cms'

export function HomePage() {
  const { data } = useCMSState()

  if (!data) {
    return <div className="px-4 py-16 text-stone-700">Carregando conteúdo...</div>
  }

  return (
    <div className="pb-16">
      <HeroBanner settings={data.settings} />
      <section className="border-t border-stone-200/80 bg-[linear-gradient(180deg,rgba(255,252,246,0.96),rgba(248,241,227,0.9))]">
        <div className="mx-auto max-w-4xl px-4 py-12 text-center sm:px-6 sm:py-14">
          <h2 className="font-display text-3xl leading-tight text-stone-900 sm:text-4xl">
            Turmas, encontros e materiais em um só lugar.
          </h2>
          <p className="mx-auto mt-4 max-w-3xl text-base leading-8 text-stone-700 sm:text-lg">
            O Catequético reúne conteúdos, avisos, materiais e caminhos de formação para auxiliar
            catequistas, alunos e comunidades em sua caminhada de fé.
          </p>
        </div>
      </section>
    </div>
  )
}
