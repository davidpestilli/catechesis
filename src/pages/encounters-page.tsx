import { GroupCard } from '@/components/content/group-card'
import { SectionTitle } from '@/components/home/section-title'
import { useCMSState } from '@/hooks/use-cms'

export function EncountersPage() {
  const { data } = useCMSState()

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 pb-24">
      <SectionTitle
        eyebrow=""
        title="Turmas"
        body="Escolha a turma para acessar seus encontros, resumos, materiais e quizzes."
      />
      <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
        {data?.groups.map((group) => (
          <GroupCard
            key={group.id}
            group={group}
            encounterCount={data.encounters.filter((encounter) => encounter.groupId === group.id).length}
            coverImageUrl={data.encounters.find((encounter) => encounter.groupId === group.id)?.coverImageUrl}
          />
        ))}
      </div>
    </section>
  )
}
