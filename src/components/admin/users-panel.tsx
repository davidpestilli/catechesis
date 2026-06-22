import { useMemo, useState } from 'react'
import { Loader2, Mail, Shield, Trash2, UserPlus, UsersRound } from 'lucide-react'
import { toast } from 'sonner'
import { useCreateManagedUser, useDeleteManagedUser, useManagedUsers, useUpdateManagedUser } from '@/hooks/use-user-management'
import { useAuth } from '@/providers/auth-provider'
import { userManagementService } from '@/services/user-management-service'
import type { UserRole } from '@/types/content'
import { formatDate } from '@/lib/utils'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

const roleOptions: Array<{ value: UserRole; label: string }> = [
  { value: 'catequista', label: 'Catequista' },
  { value: 'admin', label: 'Admin' },
]

const selectClassName =
  'h-11 w-full rounded-2xl border border-input bg-white/90 px-4 text-sm text-stone-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20'

export function UsersPanel() {
  const { user } = useAuth()
  const usersQuery = useManagedUsers(user?.role === 'admin')
  const createUser = useCreateManagedUser()
  const updateUser = useUpdateManagedUser()
  const deleteUser = useDeleteManagedUser()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [name, setName] = useState('')
  const [role, setRole] = useState<UserRole>('catequista')
  const [pendingRoles, setPendingRoles] = useState<Record<string, UserRole>>({})

  const users = usersQuery.data ?? []
  const isAvailable = userManagementService.isAvailable()

  const sortedUsers = useMemo(
    () => [...users].sort((first, second) => first.email.localeCompare(second.email)),
    [users],
  )

  async function handleCreateUser() {
    const trimmedEmail = email.trim().toLowerCase()
    const trimmedPassword = password.trim()
    const trimmedName = name.trim()

    if (!trimmedEmail) {
      toast.error('Informe o email do novo usuário.')
      return
    }

    if (!trimmedPassword) {
      toast.error('Informe a senha inicial do novo usuário.')
      return
    }

    if (trimmedPassword.length < 6) {
      toast.error('A senha inicial precisa ter pelo menos 6 caracteres.')
      return
    }

    try {
      const result = await createUser.mutateAsync({
        email: trimmedEmail,
        password: trimmedPassword,
        role,
        name: trimmedName || undefined,
      })

      setEmail('')
      setPassword('')
      setName('')
      setRole('catequista')

      if (result.reusedExistingAccount) {
        toast.success('Acesso concedido à conta compartilhada.')
        if (result.notice) {
          toast.warning(result.notice)
        }
      } else if (result.credentialsEmailQueued) {
        toast.success('Usuário criado e email enviado.')
      } else {
        toast.warning(result.notice ?? 'Usuário criado, mas o email não foi enviado.')
      }
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Não foi possível criar o usuário.')
    }
  }

  async function handleSaveRole(userId: string) {
    const nextRole = pendingRoles[userId]

    if (!nextRole) {
      return
    }

    try {
      await updateUser.mutateAsync({ userId, role: nextRole })
      setPendingRoles((current) => {
        const next = { ...current }
        delete next[userId]
        return next
      })
      toast.success('Perfil atualizado.')
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Não foi possível atualizar o perfil.')
    }
  }

  async function handleDeleteUser(userId: string, userEmail: string) {
    if (!window.confirm(`Remover o acesso do usuário ${userEmail} ao Catequético?`)) {
      return
    }

    try {
      await deleteUser.mutateAsync(userId)
      toast.success('Acesso removido.')
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Não foi possível excluir o usuário.')
    }
  }

  if (user?.role !== 'admin') {
    return null
  }

  return (
    <div className="grid gap-6 lg:grid-cols-[0.88fr_1.12fr]">
      <Card>
        <div className="flex items-start justify-between gap-4">
          <div>
            <CardTitle>Cadastro de usuários</CardTitle>
            <CardDescription className="mt-2">
              Somente administradores podem criar acessos e definir se o novo perfil será Admin ou Catequista.
            </CardDescription>
          </div>
          <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
            <UserPlus className="h-5 w-5" />
          </div>
        </div>

        <div className="mt-6 space-y-4">
          <div className="space-y-2">
            <Label>Email</Label>
            <Input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="novo.usuario@exemplo.com"
            />
          </div>

          <div className="space-y-2">
            <Label>Senha inicial</Label>
            <Input
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="Defina a senha inicial"
            />
            <p className="text-xs text-stone-500">Use pelo menos 6 caracteres.</p>
          </div>

          <div className="space-y-2">
            <Label>Nome exibido no perfil</Label>
            <Input
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="Opcional. Se vazio, o sistema usa o email."
            />
          </div>

          <div className="space-y-2">
            <Label>Perfil</Label>
            <select value={role} onChange={(event) => setRole(event.target.value as UserRole)} className={selectClassName}>
              {roleOptions.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </div>

          <Button
            className="w-full"
            onClick={() => void handleCreateUser()}
            disabled={!isAvailable || createUser.isPending}
          >
            {createUser.isPending ? 'Criando...' : 'Criar usuário'}
          </Button>

          {!isAvailable ? (
            <div className="rounded-[22px] border border-dashed border-stone-300 bg-stone-50/90 px-4 py-3 text-sm text-stone-600">
              A gestão de usuários depende do Worker e do Supabase configurados.
            </div>
          ) : null}
        </div>
      </Card>

      <Card>
        <div className="flex items-start justify-between gap-4">
          <div>
            <CardTitle>Usuários cadastrados</CardTitle>
            <CardDescription className="mt-2">
              Altere o perfil de um usuário do Catequético ou remova acessos que não devem mais entrar neste painel.
            </CardDescription>
          </div>
          <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
            <UsersRound className="h-5 w-5" />
          </div>
        </div>

        <div className="mt-6 space-y-4">
          {usersQuery.isLoading ? (
            <div className="flex items-center gap-3 rounded-[22px] border border-stone-200 bg-stone-50 px-4 py-4 text-sm text-stone-600">
              <Loader2 className="h-4 w-4 animate-spin" />
              Carregando usuários...
            </div>
          ) : usersQuery.error ? (
            <div className="rounded-[22px] border border-rose-200 bg-rose-50 px-4 py-4 text-sm text-rose-700">
              Não foi possível carregar os usuários.
            </div>
          ) : sortedUsers.length === 0 ? (
            <div className="rounded-[22px] border border-stone-200 bg-stone-50 px-4 py-4 text-sm text-stone-600">
              Nenhum usuário encontrado.
            </div>
          ) : (
            sortedUsers.map((managedUser) => {
              const currentRole = pendingRoles[managedUser.id] ?? managedUser.role
              const isCurrentUser = managedUser.id === user?.id

              return (
                <div key={managedUser.id} className="rounded-[24px] border border-stone-200 bg-stone-50/80 p-4">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="font-semibold text-stone-900">
                        {managedUser.name.trim() || managedUser.email}
                      </p>
                      <div className="mt-2 flex flex-wrap items-center gap-2 text-sm text-stone-600">
                        <Mail className="h-4 w-4" />
                        <span className="break-all">{managedUser.email}</span>
                      </div>
                      <p className="mt-2 text-xs uppercase tracking-[0.16em] text-stone-500">
                        Criado em {formatDate(managedUser.createdAt)}
                      </p>
                    </div>

                    <Badge className="bg-primary text-primary-foreground">
                      <Shield className="mr-1 h-3.5 w-3.5" />
                      {managedUser.role === 'admin' ? 'Admin' : 'Catequista'}
                    </Badge>
                  </div>

                  <div className="mt-4 grid gap-3 md:grid-cols-[1fr_auto_auto] md:items-end">
                    <div className="space-y-2">
                      <Label>Perfil</Label>
                      <select
                        value={currentRole}
                        onChange={(event) =>
                          setPendingRoles((current) => ({
                            ...current,
                            [managedUser.id]: event.target.value as UserRole,
                          }))
                        }
                        className={selectClassName}
                        disabled={isCurrentUser}
                      >
                        {roleOptions.map((option) => (
                          <option key={option.value} value={option.value}>
                            {option.label}
                          </option>
                        ))}
                      </select>
                    </div>

                    <Button
                      type="button"
                      variant="outline"
                      onClick={() => void handleSaveRole(managedUser.id)}
                      disabled={isCurrentUser || currentRole === managedUser.role || updateUser.isPending}
                    >
                      Salvar perfil
                    </Button>

                    <Button
                      type="button"
                      variant="ghost"
                      onClick={() => void handleDeleteUser(managedUser.id, managedUser.email)}
                      disabled={isCurrentUser || deleteUser.isPending}
                    >
                      <Trash2 className="mr-2 h-4 w-4" />
                      Remover acesso
                    </Button>
                  </div>

                  {isCurrentUser ? (
                    <p className="mt-3 text-xs text-stone-500">
                      O próprio usuário logado não pode ser alterado ou excluído por esta tela.
                    </p>
                  ) : null}
                </div>
              )
            })
          )}
        </div>
      </Card>
    </div>
  )
}
