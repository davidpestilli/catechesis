export type AssetKind = 'summary' | 'support'
export type AssetView = 'image' | 'pdf' | 'html' | 'video' | 'link'
export type MaterialCategory = 'video' | 'image' | 'text' | 'website' | 'book'
export type LandingImageMotion = 'drift-a' | 'drift-b' | 'drift-c'

export interface EncounterAsset {
  id: string
  encounterId: string
  title: string
  description: string
  kind: AssetKind
  view: AssetView
  url: string
  materialCategory?: MaterialCategory
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

export interface ClassGroup {
  id: string
  slug: string
  name: string
  battleCry: string
  coverImageUrl?: string
  order: number
}

export interface Encounter {
  id: string
  groupId: string
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

export interface LandingSlide {
  id: string
  src: string
  alt: string
  motion: LandingImageMotion
}

export interface SiteSettings {
  heroVideoUrl: string
  heroPosterUrl: string
  homeLead: string
  landingImages: LandingSlide[]
}

export interface CMSState {
  groups: ClassGroup[]
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
