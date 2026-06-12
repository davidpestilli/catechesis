import { ExternalLink, ScrollText } from 'lucide-react'
import { Link } from 'react-router-dom'
import { EditorShortcutCard } from '@/components/content/editor-shortcut-card'
import { SectionTitle } from '@/components/home/section-title'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'

const sections = [
  {
    to: '/artigos',
    title: 'Artigos',
    description: 'Abra a biblioteca de artigos e navegue pelas pastas Gerais e Vida dos Santos.',
    icon: ScrollText,
  },
  {
    to: '/links-uteis',
    title: 'Links Uteis',
    description: 'Acesse uma selecao de links externos com materiais de consulta e aprofundamento.',
    icon: ExternalLink,
  },
]

export function MiscPage() {
  return (
    <section className="mx-auto max-w-6xl px-4 py-12 pb-24">
      <SectionTitle
        eyebrow="conteudos"
        title="Diversos"
        body="Reunimos aqui outros caminhos de apoio para a catequese, com acesso rapido a artigos e links de referencia."
      />

      <div className="grid gap-5 lg:grid-cols-2">
        {sections.map(({ to, title, description, icon: Icon }) => (
          <Link key={to} to={to} className="block transition hover:-translate-y-1">
            <Card className="h-full">
              <div className="rounded-2xl bg-stone-100 p-3 text-stone-700 w-fit">
                <Icon className="h-6 w-6" />
              </div>
              <CardTitle className="mt-5">{title}</CardTitle>
              <CardDescription className="mt-3">{description}</CardDescription>
            </Card>
          </Link>
        ))}
      </div>

      <div className="mt-6">
        <EditorShortcutCard
          title="Editar a area Diversos"
          description="O painel administrativo concentra a manutencao dos artigos e dos links uteis exibidos nesta pagina."
        />
      </div>
    </section>
  )
}
