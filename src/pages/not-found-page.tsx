import { FloatingBackButton } from '@/components/navigation/floating-back-button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'

export function NotFoundPage() {
  return (
    <section className="mx-auto max-w-3xl px-4 py-16 pb-24">
      <FloatingBackButton to="/" label="Voltar para a home" />
      <Card>
        <CardTitle>Página não encontrada</CardTitle>
        <CardDescription className="mt-2">
          O conteúdo procurado não existe ou ainda não foi publicado no Catequético.
        </CardDescription>
      </Card>
    </section>
  )
}
