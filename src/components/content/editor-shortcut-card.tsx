import { PencilLine } from 'lucide-react'
import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { useAuth } from '@/providers/auth-provider'

interface EditorShortcutCardProps {
  title: string
  description: string
}

export function EditorShortcutCard({ title, description }: EditorShortcutCardProps) {
  const { isAuthenticated } = useAuth()

  if (!isAuthenticated) {
    return null
  }

  return (
    <Card className="border-primary/20 bg-primary/5">
      <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.22em] text-primary/70">
            edicao liberada
          </p>
          <CardTitle className="mt-2">{title}</CardTitle>
          <CardDescription className="mt-2">{description}</CardDescription>
        </div>
        <Button asChild>
          <Link to="/admin">
            <PencilLine className="mr-2 h-4 w-4" />
            Abrir painel
          </Link>
        </Button>
      </div>
    </Card>
  )
}
