import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type PropsWithChildren,
} from 'react'
import { supabase } from '@/lib/supabase'
import type { EditorUser, UserRole } from '@/types/content'

const DEMO_EMAIL = 'demo@catechesis.local'
const DEMO_PASSWORD = 'catechesis123'
const DEMO_STORAGE_KEY = 'catechesis-demo-session'

interface SharedUserProfileRow {
  id: string
  email: string
  nome: string
  ativo: boolean
}

interface UserAppAccessRow {
  user_id: string
  role: string
  ativo: boolean
}

function normalizeRole(role?: string | null): UserRole {
  return role === 'admin' ? 'admin' : 'catequista'
}

interface AuthContextValue {
  user: EditorUser | null
  loading: boolean
  isAuthenticated: boolean
  signIn: (email: string, password: string) => Promise<void>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | null>(null)

async function loadProfile(userId: string) {
  if (!supabase) return null

  const { data, error } = await supabase
    .from('users')
    .select('id,email,nome,ativo')
    .eq('id', userId)
    .maybeSingle()

  if (error) {
    throw new Error(error.message)
  }

  return (data as SharedUserProfileRow | null) ?? null
}

async function loadCatequeticoAccess(userId: string) {
  if (!supabase) return null

  const { data, error } = await supabase
    .from('user_app_access')
    .select('user_id,role,ativo')
    .eq('user_id', userId)
    .eq('app_code', 'catequetico')
    .maybeSingle()

  if (error) {
    throw new Error(error.message)
  }

  return (data as UserAppAccessRow | null) ?? null
}

function buildEditorUser(input: {
  id: string
  email: string
  profile?: SharedUserProfileRow | null
  access?: UserAppAccessRow | null
  fallbackName?: string
}): EditorUser {
  return {
    id: input.id,
    email: input.email,
    name: input.profile?.nome?.trim() || input.fallbackName || input.email.split('@')[0] || 'Editor',
    role: normalizeRole(input.access?.role),
    active: Boolean(input.profile?.ativo ?? true) && Boolean(input.access?.ativo ?? false),
    mode: 'supabase',
  }
}

async function loadCatequeticoUser(input: {
  id: string
  email: string
  fallbackName?: string
}) {
  const [profile, access] = await Promise.all([loadProfile(input.id), loadCatequeticoAccess(input.id)])

  if (!profile || !access || !profile.ativo || !access.ativo) {
    return null
  }

  return buildEditorUser({
    id: input.id,
    email: input.email,
    profile,
    access,
    fallbackName: input.fallbackName,
  })
}

export function AuthProvider({ children }: PropsWithChildren) {
  const [user, setUser] = useState<EditorUser | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let active = true

    async function syncSessionUser() {
      if (!supabase) {
        const demoSession = sessionStorage.getItem(DEMO_STORAGE_KEY)
        if (demoSession === 'ok') {
          setUser({
            id: 'demo-user',
            email: DEMO_EMAIL,
            name: 'Editor Demo',
            role: 'admin',
            active: true,
            mode: 'demo',
          })
        }
        setLoading(false)
        return
      }

      const { data } = await supabase.auth.getSession()
      const session = data.session
      const email = session?.user.email

      if (!active) return

      if (!session?.user.id || !email) {
        setUser(null)
        setLoading(false)
        return
      }

      try {
        const nextUser = await loadCatequeticoUser({
          id: session.user.id,
          email,
          fallbackName: session.user.user_metadata?.name,
        })

        if (!active) return

        if (!nextUser) {
          setUser(null)
          await supabase.auth.signOut()
          return
        }

        setUser(nextUser)
      } catch {
        if (!active) return
        setUser(null)
      } finally {
        if (active) {
          setLoading(false)
        }
      }
    }

    void syncSessionUser()

    if (!supabase) {
      return () => {
        active = false
      }
    }

    const client = supabase

    const {
      data: { subscription },
    } = client.auth.onAuthStateChange(async (_event, session) => {
      const email = session?.user.email

      if (!session?.user.id || !email) {
        if (!active) return
        setUser(null)
        setLoading(false)
        return
      }

      try {
        const nextUser = await loadCatequeticoUser({
          id: session.user.id,
          email,
          fallbackName: session.user.user_metadata?.name,
        })

        if (!active) return

        if (!nextUser) {
          setUser(null)
          await client.auth.signOut()
          return
        }

        setUser(nextUser)
      } catch {
        if (!active) return
        setUser(null)
      } finally {
        if (active) {
          setLoading(false)
        }
      }
    })

    return () => {
      active = false
      subscription.unsubscribe()
    }
  }, [])

  const value = useMemo<AuthContextValue>(
    () => ({
      user,
      loading,
      isAuthenticated: Boolean(user?.active),
      async signIn(email, password) {
        if (!supabase) {
          if (email === DEMO_EMAIL && password === DEMO_PASSWORD) {
            sessionStorage.setItem(DEMO_STORAGE_KEY, 'ok')
            setUser({
              id: 'demo-user',
              email: DEMO_EMAIL,
              name: 'Editor Demo',
              role: 'admin',
              active: true,
              mode: 'demo',
            })
            return
          }

          throw new Error(
            'Supabase ainda nao foi configurado. Para demonstracao local, use demo@catechesis.local / catechesis123.',
          )
        }

        const client = supabase
        const { data, error } = await client.auth.signInWithPassword({
          email,
          password,
        })

        if (error) throw new Error(error.message)

        const authUser = data.user
        const authEmail = authUser?.email

        if (!authUser?.id || !authEmail) {
          await client.auth.signOut()
          throw new Error('Nao foi possivel validar o acesso deste usuario no Catequetico.')
        }

        const nextUser = await loadCatequeticoUser({
          id: authUser.id,
          email: authEmail,
          fallbackName: authUser.user_metadata?.name,
        })

        if (!nextUser) {
          await client.auth.signOut()
          throw new Error('Este usuario nao possui acesso ao Catequetico.')
        }

        setUser(nextUser)
      },
      async signOut() {
        if (!supabase) {
          sessionStorage.removeItem(DEMO_STORAGE_KEY)
          setUser(null)
          return
        }

        const client = supabase
        const { error } = await client.auth.signOut()
        if (error) throw new Error(error.message)
      },
    }),
    [loading, user],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error('useAuth deve ser usado dentro de AuthProvider.')
  }

  return context
}
