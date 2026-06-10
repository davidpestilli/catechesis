export type AssetKind = 'summary' | 'support'
export type AssetView = 'image' | 'pdf' | 'html' | 'video' | 'link'

export interface EncounterAsset {
  id: string
  encounterId: string
  title: string
  description: string
  kind: AssetKind
  view: AssetView
  url: string
  downloadable: boolean
  order: number
}

export interface QuizOption {
  id: string
  text: string
  isCorrect: boolean
}

export interface QuizQuestion {
  id: string
  prompt: string
  explanation: string
  options: QuizOption[]
}

export interface EncounterQuiz {
  id: string
  encounterId: string
  title: string
  description: string
  questions: QuizQuestion[]
}

export interface Encounter {
  id: string
  slug: string
  title: string
  illuminatedTitle: string
  summary: string
  theme: string
  audience: string
  order: number
  coverImageUrl?: string
  bodyHtml?: string
  assets: EncounterAsset[]
  quiz?: EncounterQuiz
}

export interface Article {
  id: string
  slug: string
  title: string
  excerpt: string
  contentHtml: string
  tags: string[]
  coverImageUrl?: string
  featured?: boolean
  publishedAt: string
}

export interface SiteSettings {
  heroVideoUrl: string
  heroPosterUrl: string
  homeLead: string
}

export interface CMSState {
  encounters: Encounter[]
  articles: Article[]
  settings: SiteSettings
  updatedAt: string
}

export interface EditorUser {
  email: string
  name: string
  mode: 'demo' | 'supabase'
}
