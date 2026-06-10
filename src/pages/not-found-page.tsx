import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'

export function NotFoundPage() {
  return (
    <section className="mx-auto max-w-3xl px-4 py-16 pb-24">
      <Card>
        <CardTitle>Pagina nao encontrada</CardTitle>
        <CardDescription className="mt-2">
          O conteudo procurado nao existe ou ainda nao foi publicado no Catechesis.
        </CardDescription>
        <Button asChild className="mt-5">
          <Link to="/">Voltar para a home</Link>
        </Button>
      </Card>
    </section>
  )
}
