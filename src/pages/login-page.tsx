import { useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { BookLock } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useAuth } from '@/providers/auth-provider'

export function LoginPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const { signIn } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError(null)
    setSubmitting(true)

    try {
      await signIn(email, password)
      const destination = (location.state as { from?: { pathname?: string } } | null)?.from?.pathname
      navigate(destination ?? '/admin')
    } catch (submitError) {
      setError(submitError instanceof Error ? submitError.message : 'Falha ao entrar.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <section className="mx-auto flex min-h-[calc(100svh-78px)] max-w-4xl items-center px-4 py-12 pb-24">
      <div className="grid gap-5 md:grid-cols-[1.05fr_0.95fr]">
        <Card className="bg-stone-900 text-stone-50">
          <BookLock className="h-9 w-9 text-amber-300" />
          <CardTitle className="mt-6 text-stone-50">Modo de edicao</CardTitle>
          <CardDescription className="mt-3 text-stone-200">
            O login libera o painel interno para criar encontros, subir materiais, editar artigos e
            comentar como catequista.
          </CardDescription>
          <div className="mt-6 rounded-[24px] bg-stone-800/70 p-4 text-sm leading-7 text-stone-200">
            Os perfis sao gerenciados no Supabase Auth. Apenas usuarios com perfil <strong>Admin</strong>{' '}
            podem cadastrar ou excluir outros acessos.
          </div>
        </Card>

        <Card>
          <CardTitle>Entrar</CardTitle>
          <CardDescription className="mt-2">
            Use o email e a senha recebidos no cadastro.
          </CardDescription>
          <form className="mt-6 space-y-4" onSubmit={handleSubmit}>
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input id="email" type="email" value={email} onChange={(event) => setEmail(event.target.value)} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Senha</Label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
            </div>

            {error ? (
              <div className="rounded-[22px] border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">
                {error}
              </div>
            ) : null}

            <Button type="submit" className="w-full" disabled={submitting}>
              {submitting ? 'Entrando...' : 'Acessar painel'}
            </Button>
          </form>
        </Card>
      </div>
    </section>
  )
}
