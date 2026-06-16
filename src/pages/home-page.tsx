import { HeroBanner } from '@/components/home/hero-banner'
import { useCMSState } from '@/hooks/use-cms'

export function HomePage() {
  const { data } = useCMSState()

  if (!data) {
    return <div className="px-4 py-16 text-stone-700">Carregando conteudo...</div>
  }

  return (
    <div className="pb-16">
      <HeroBanner settings={data.settings} />
    </div>
  )
}
