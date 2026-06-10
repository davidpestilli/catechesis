import { Link } from 'react-router-dom'
import { ArrowRight, FileText, ScrollText } from 'lucide-react'
import { ArticleCard } from '@/components/content/article-card'
import { EncounterCard } from '@/components/content/encounter-card'
import { HeroBanner } from '@/components/home/hero-banner'
import { SectionTitle } from '@/components/home/section-title'
import { Button } from '@/components/ui/button'
import { landingImages } from '@/data/landing-images'
import { useCMSState } from '@/hooks/use-cms'

export function HomePage() {
  const { data } = useCMSState()

  if (!data) {
    return <div className="px-4 py-16 text-stone-700">Carregando conteudo...</div>
  }

    return (
    <div className="pb-24">
      <HeroBanner settings={data.settings} images={landingImages} />

      <section className="mx-auto max-w-6xl px-4 py-14">
        <SectionTitle
          eyebrow=""
          title="Encontros"
          body=""
        />
        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
          {data.encounters.slice(0, 3).map((encounter) => (
            <EncounterCard key={encounter.id} encounter={encounter} />
          ))}
        </div>
        <Button asChild variant="ghost" className="mt-6">
          <Link to="/encontros">
            Ver todos os encontros
            <ArrowRight className="ml-2 h-4 w-4" />
          </Link>
        </Button>
      </section>

      <section className="border-y border-stone-200/80 bg-white/60">
        <div className="mx-auto max-w-6xl px-4 py-14">
          <SectionTitle
            eyebrow=""
            title="Artigos"
            body=""
          />
          <div className="grid gap-5 lg:grid-cols-2">
            {data.articles.slice(0, 2).map((article) => (
              <ArticleCard key={article.id} article={article} />
            ))}
          </div>
          <div className="mt-8 grid gap-4 rounded-[28px] border border-stone-200 bg-stone-50/80 p-5 md:grid-cols-2">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-stone-500">
                fluxo previsto
              </p>
              <h3 className="mt-2 font-display text-2xl text-stone-900">
                Editor interno com publicacao imediata
              </h3>
            </div>
            <div className="space-y-3 text-sm leading-7 text-stone-700">
              <p className="inline-flex items-start gap-2">
                <ScrollText className="mt-1 h-4 w-4 text-primary" />
                O artigo e escrito em HTML no proprio sistema e vira uma rota publica de leitura.
              </p>
              <p className="inline-flex items-start gap-2">
                <FileText className="mt-1 h-4 w-4 text-primary" />
                O mesmo painel interno ajuda a anexar resumos, imagens e PDFs para cada encontro.
              </p>
            </div>
          </div>
        </div>
      </section>
    </div>
  )
}
