import { Link } from 'react-router-dom'
import { ArrowRight, LockKeyhole } from 'lucide-react'
import { ArticleCard } from '@/components/content/article-card'
import { GroupCard } from '@/components/content/group-card'
import { HeroBanner } from '@/components/home/hero-banner'
import { SectionTitle } from '@/components/home/section-title'
import { Button } from '@/components/ui/button'
import { landingImages } from '@/data/landing-images'
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
      <HeroBanner settings={data.settings} images={landingImages} />

      <section className="mx-auto max-w-6xl px-4 py-14">
        <SectionTitle
          eyebrow=""
          title="Turmas"
          body="A caminhada agora comeca pela turma. Entre primeiro no grupo e, dentro dele, escolha o encontro do dia."
        />
        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
          {data.groups.slice(0, 3).map((group) => (
            <GroupCard
              key={group.id}
              group={group}
              encounterCount={data.encounters.filter((encounter) => encounter.groupId === group.id).length}
              coverImageUrl={data.encounters.find((encounter) => encounter.groupId === group.id)?.coverImageUrl}
            />
          ))}
        </div>
        <Button asChild variant="ghost" className="mt-6">
          <Link to="/encontros">
            Ver todas as turmas
            <ArrowRight className="ml-2 h-4 w-4" />
          </Link>
        </Button>
      </section>

      <section className="border-y border-stone-200/80 bg-white/60">
        <div className="mx-auto max-w-6xl px-4 py-14">
          <SectionTitle
            eyebrow=""
            title="Artigos"
            body="Textos de apoio para preparar, aprofundar e revisar cada etapa da catequese."
          />
          <div className="grid gap-5 lg:grid-cols-2">
            {data.articles.slice(0, 2).map((article) => (
              <ArticleCard key={article.id} article={article} />
            ))}
          </div>
          <div className="mt-8 flex flex-col gap-4 rounded-[28px] border border-stone-200 bg-stone-50/80 p-5 md:flex-row md:items-center md:justify-between">
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
