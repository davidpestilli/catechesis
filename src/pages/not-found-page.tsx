import { FloatingBackButton } from '@/components/navigation/floating-back-button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'

export function NotFoundPage() {
  return (
    <section className="mx-auto max-w-3xl px-4 py-16 pb-24">
      <FloatingBackButton to="/" label="Voltar para a home" />
      <Card>
        <CardTitle>Pagina nao encontrada</CardTitle>
        <CardDescription className="mt-2">
          O conteudo procurado nao existe ou ainda nao foi publicado no Catechesis.
        </CardDescription>
      </Card>
    </section>
  )
}
