import { EncounterCard } from '@/components/content/encounter-card'
import { SectionTitle } from '@/components/home/section-title'
import { useCMSState } from '@/hooks/use-cms'

export function EncountersPage() {
  const { data } = useCMSState()

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 pb-24">
      <SectionTitle
        eyebrow=""
        title="Encontros"
        body=""
      />
      <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
        {data?.encounters.map((encounter) => (
          <EncounterCard key={encounter.id} encounter={encounter} />
        ))}
      </div>
    </section>
  )
}
