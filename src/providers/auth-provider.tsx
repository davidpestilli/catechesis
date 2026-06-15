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

interface UserProfileRow {
  id: string
  email: string
  nome: string
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
    .select('id,email,nome,role,ativo')
    .eq('id', userId)
    .maybeSingle()

  if (error) {
    throw new Error(error.message)
  }

  return (data as UserProfileRow | null) ?? null
}

function buildEditorUser(input: {
  id: string
  email: string
  profile?: UserProfileRow | null
  fallbackName?: string
}): EditorUser {
  return {
    id: input.id,
    email: input.email,
    name: input.profile?.nome?.trim() || input.fallbackName || input.email.split('@')[0] || 'Editor',
    role: normalizeRole(input.profile?.role),
    active: input.profile?.ativo ?? true,
    mode: 'supabase',
  }
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
        const profile = await loadProfile(session.user.id)

        if (!active) return

        setUser(
          buildEditorUser({
            id: session.user.id,
            email,
            profile,
            fallbackName: session.user.user_metadata?.name,
          }),
        )
      } catch {
        if (!active) return

        setUser(
          buildEditorUser({
            id: session.user.id,
            email,
            fallbackName: session.user.user_metadata?.name,
          }),
        )
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

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange(async (_event, session) => {
      const email = session?.user.email

      if (!session?.user.id || !email) {
        if (!active) return
        setUser(null)
        setLoading(false)
        return
      }

      try {
        const profile = await loadProfile(session.user.id)

        if (!active) return

        setUser(
          buildEditorUser({
            id: session.user.id,
            email,
            profile,
            fallbackName: session.user.user_metadata?.name,
          }),
        )
      } catch {
        if (!active) return

        setUser(
          buildEditorUser({
            id: session.user.id,
            email,
            fallbackName: session.user.user_metadata?.name,
          }),
        )
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

        const { error } = await supabase.auth.signInWithPassword({
          email,
          password,
        })

        if (error) throw new Error(error.message)
      },
      async signOut() {
        if (!supabase) {
          sessionStorage.removeItem(DEMO_STORAGE_KEY)
          setUser(null)
          return
        }

        const { error } = await supabase.auth.signOut()
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
