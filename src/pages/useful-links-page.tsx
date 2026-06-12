import { EditorShortcutCard } from '@/components/content/editor-shortcut-card'
import { UsefulLinkCard } from '@/components/content/useful-link-card'
import { SectionTitle } from '@/components/home/section-title'
import { FloatingBackButton } from '@/components/navigation/floating-back-button'
import { useCMSState } from '@/hooks/use-cms'

export function UsefulLinksPage() {
  const { data } = useCMSState()

  if (!data) {
    return <div className="px-4 py-16 text-stone-700">Carregando links...</div>
  }

  const usefulLinks = [...data.usefulLinks].sort((first, second) => first.order - second.order)

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 pb-24">
      <FloatingBackButton to="/diversos" label="Voltar para Diversos" />

      <SectionTitle
        eyebrow="atalhos"
        title="Links Uteis"
        body="Uma selecao de referencias externas para estudo, consulta e preparacao dos encontros."
      />

      <div className="grid gap-5 lg:grid-cols-2">
        {usefulLinks.map((usefulLink) => (
          <UsefulLinkCard key={usefulLink.id} usefulLink={usefulLink} />
        ))}
      </div>

      {usefulLinks.length === 0 ? (
        <div className="rounded-[26px] border border-dashed border-stone-300 bg-white/70 p-6 text-sm leading-6 text-stone-600">
          Nenhum link util foi publicado ainda.
        </div>
      ) : null}

      <div className="mt-6">
        <EditorShortcutCard
          title="Editar Links Uteis"
          description="Como voce esta logado, pode abrir o painel para cadastrar, revisar ou reorganizar os links desta area."
        />
      </div>
    </section>
  )
}
