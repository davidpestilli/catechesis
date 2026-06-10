import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type PropsWithChildren,
} from 'react'
import { supabase } from '@/lib/supabase'
import type { EditorUser } from '@/types/content'

const DEMO_EMAIL = 'demo@catechesis.local'
const DEMO_PASSWORD = 'catechesis123'
const DEMO_STORAGE_KEY = 'catechesis-demo-session'

interface AuthContextValue {
  user: EditorUser | null
  loading: boolean
  isAuthenticated: boolean
  signIn: (email: string, password: string) => Promise<void>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: PropsWithChildren) {
  const [user, setUser] = useState<EditorUser | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!supabase) {
      const demoSession = sessionStorage.getItem(DEMO_STORAGE_KEY)
      if (demoSession === 'ok') {
        setUser({
          email: DEMO_EMAIL,
          name: 'Editor Demo',
          mode: 'demo',
        })
      }
      setLoading(false)
      return
    }

    supabase.auth.getSession().then(({ data }) => {
      const session = data.session
      const email = session?.user.email
      if (email) {
        setUser({
          email,
          name: session?.user.user_metadata?.name ?? 'Editor',
          mode: 'supabase',
        })
      }
      setLoading(false)
    })

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      const email = session?.user.email
      setUser(
        email
          ? {
              email,
              name: session.user.user_metadata?.name ?? 'Editor',
              mode: 'supabase',
            }
          : null,
      )
      setLoading(false)
    })

    return () => subscription.unsubscribe()
  }, [])

  const value = useMemo<AuthContextValue>(
    () => ({
      user,
      loading,
      isAuthenticated: Boolean(user),
      async signIn(email, password) {
        if (!supabase) {
          if (email === DEMO_EMAIL && password === DEMO_PASSWORD) {
            sessionStorage.setItem(DEMO_STORAGE_KEY, 'ok')
            setUser({
              email: DEMO_EMAIL,
              name: 'Editor Demo',
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
