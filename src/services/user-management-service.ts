import { env } from '@/lib/env'
import { supabase } from '@/lib/supabase'
import type { ManagedUser, UserRole } from '@/types/content'

interface ManagedUserRow {
  id: string
  email: string
  nome: string
  role: string
  ativo: boolean
  created_at: string
  updated_at: string
}

interface CreateUserPayload {
  email: string
  password: string
  role: UserRole
  name?: string
}

interface UpdateUserPayload {
  role: UserRole
  name?: string
}

async function getAuthToken() {
  if (!supabase) return null

  const { data } = await supabase.auth.getSession()
  return data.session?.access_token ?? null
}

function mapManagedUser(row: ManagedUserRow): ManagedUser {
  return {
    id: row.id,
    email: row.email,
    name: row.nome,
    role: row.role === 'admin' ? 'admin' : 'catequista',
    active: row.ativo,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

async function request<T>(path: string, init: RequestInit = {}) {
  if (!env.workerUrl) {
    throw new Error('A URL do Worker nao foi configurada.')
  }

  const token = await getAuthToken()
  const response = await fetch(`${env.workerUrl}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(init.headers ?? {}),
    },
  })

  const payload = (await response.json().catch(() => null)) as T | { error?: string } | null

  if (!response.ok) {
    throw new Error(
      payload && typeof payload === 'object' && 'error' in payload && payload.error
        ? payload.error
        : 'Nao foi possivel concluir a operacao.',
    )
  }

  return payload as T
}

export const userManagementService = {
  isAvailable() {
    return Boolean(env.workerUrl && supabase)
  },

  async listUsers() {
    const payload = await request<{ users: ManagedUserRow[] }>('/admin/users', { method: 'GET' })
    return (payload.users ?? []).map(mapManagedUser)
  },

  async createUser(input: CreateUserPayload) {
    const payload = await request<{
      user: ManagedUserRow
      credentialsEmailQueued: boolean
      credentialsEmailError?: string | null
    }>('/admin/users', {
      method: 'POST',
      body: JSON.stringify(input),
    })

    return {
      user: mapManagedUser(payload.user),
      credentialsEmailQueued: payload.credentialsEmailQueued,
      credentialsEmailError: payload.credentialsEmailError ?? null,
    }
  },

  async updateUser(userId: string, input: UpdateUserPayload) {
    const payload = await request<{ user: ManagedUserRow }>(`/admin/users/${userId}`, {
      method: 'PATCH',
      body: JSON.stringify(input),
    })

    return mapManagedUser(payload.user)
  },

  async deleteUser(userId: string) {
    await request<{ ok: true }>(`/admin/users/${userId}`, {
      method: 'DELETE',
    })
  },
}
