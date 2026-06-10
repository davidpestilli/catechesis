import { defaultCMSState } from '@/data/mock-content'
import { createId, slugify } from '@/lib/utils'
import type {
  Article,
  CMSState,
  ClassGroup,
  Encounter,
  EncounterAsset,
  EncounterQuiz,
  SiteSettings,
} from '@/types/content'

const STORAGE_KEY = 'catechesis-local-cms'
const REMOVED_HOME_LEADS = new Set([
  'Um espaco mobile-first para encontros, artigos, resumos, materiais de apoio e quizzes de catequese.',
  'Um espaco mobile-first para encontros, artigos, resumos, materiais e quizzes de catequese.',
])

function sanitizeHomeLead(value: unknown) {
  const text = typeof value === 'string' ? value.trim() : ''
  return REMOVED_HOME_LEADS.has(text) ? '' : text
}

function buildLegacyGroups(encounters: Encounter[]) {
  const groupsByLabel = new Map<string, ClassGroup>()

  for (const encounter of encounters) {
    const label = encounter.audience?.trim() || 'Turma geral'
    if (!groupsByLabel.has(label)) {
      groupsByLabel.set(label, {
        id: createId(),
        slug: slugify(label),
        name: label,
        battleCry: '',
        order: groupsByLabel.size + 1,
      })
    }
  }

  if (groupsByLabel.size === 0) {
    const defaultGroup: ClassGroup = {
      id: createId(),
      slug: 'turma-geral',
      name: 'Turma geral',
      battleCry: '',
      order: 1,
    }
    groupsByLabel.set(defaultGroup.name, defaultGroup)
  }

  return groupsByLabel
}

function normalizeCMSState(state: CMSState): CMSState {
  const existingGroups = Array.isArray(state.groups) ? state.groups : []
  const groups = existingGroups.length > 0 ? existingGroups : Array.from(buildLegacyGroups(state.encounters).values())
  const fallbackGroupId = groups[0]?.id ?? createId()

  return {
    ...state,
    groups,
    encounters: state.encounters.map((encounter) => {
      if (encounter.groupId) {
        return encounter
      }

      const matchingGroup =
        groups.find((group) => group.name === encounter.audience?.trim()) ?? groups[0] ?? null

      return {
        ...encounter,
        groupId: matchingGroup?.id ?? fallbackGroupId,
      }
    }),
  }
}

function sanitizeCMSState(state: CMSState): CMSState {
  const normalizedState = normalizeCMSState(state)
  return {
    ...normalizedState,
    settings: {
      ...normalizedState.settings,
      homeLead: sanitizeHomeLead(normalizedState.settings?.homeLead),
    },
  }
}

function canUseStorage() {
  return typeof window !== 'undefined' && 'localStorage' in window
}

export function getLocalCMSState(): CMSState {
  if (!canUseStorage()) {
    return sanitizeCMSState(structuredClone(defaultCMSState))
  }

  const raw = window.localStorage.getItem(STORAGE_KEY)

  if (!raw) {
    const sanitizedDefault = sanitizeCMSState(structuredClone(defaultCMSState))
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(sanitizedDefault))
    return sanitizedDefault
  }

  try {
    const parsed = sanitizeCMSState(JSON.parse(raw) as CMSState)
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(parsed))
    return parsed
  } catch {
    const sanitizedDefault = sanitizeCMSState(structuredClone(defaultCMSState))
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(sanitizedDefault))
    return sanitizedDefault
  }
}

export function saveLocalCMSState(nextState: CMSState) {
  if (!canUseStorage()) return

  const sanitizedState = sanitizeCMSState(nextState)

  window.localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify({ ...sanitizedState, updatedAt: new Date().toISOString() }),
  )
}

export function upsertLocalEncounter(input: Partial<Encounter> & Pick<Encounter, 'title'>) {
  const state = getLocalCMSState()
  const id = input.id ?? createId()
  const encounter: Encounter = {
    id,
    groupId: input.groupId ?? state.groups[0]?.id ?? createId(),
    slug: input.slug ?? slugify(input.title),
    title: input.title,
    illuminatedTitle: input.illuminatedTitle ?? 'Encontros',
    summary: input.summary ?? '',
    theme: input.theme ?? '',
    audience: input.audience ?? '',
    order: input.order ?? state.encounters.length + 1,
    coverImageUrl: input.coverImageUrl,
    bodyHtml: input.bodyHtml,
    assets: input.assets ?? state.encounters.find((item) => item.id === id)?.assets ?? [],
    quiz: input.quiz ?? state.encounters.find((item) => item.id === id)?.quiz,
  }

  const existingIndex = state.encounters.findIndex((item) => item.id === id)

  if (existingIndex >= 0) {
    state.encounters[existingIndex] = encounter
  } else {
    state.encounters.push(encounter)
  }

  saveLocalCMSState(state)
  return encounter
}

export function upsertLocalGroup(input: Partial<ClassGroup> & Pick<ClassGroup, 'name'>) {
  const state = getLocalCMSState()
  const id = input.id ?? createId()
  const group: ClassGroup = {
    id,
    slug: input.slug ?? slugify(input.name),
    name: input.name,
    battleCry: input.battleCry ?? '',
    order: input.order ?? state.groups.length + 1,
  }

  const existingIndex = state.groups.findIndex((item) => item.id === id)

  if (existingIndex >= 0) {
    state.groups[existingIndex] = group
  } else {
    state.groups.push(group)
  }

  saveLocalCMSState(state)
  return group
}

export function upsertLocalArticle(input: Partial<Article> & Pick<Article, 'title' | 'contentHtml'>) {
  const state = getLocalCMSState()
  const id = input.id ?? createId()
  const article: Article = {
    id,
    slug: input.slug ?? slugify(input.title),
    title: input.title,
    excerpt: input.excerpt ?? '',
    contentHtml: input.contentHtml,
    tags: input.tags ?? [],
    featured: input.featured ?? false,
    coverImageUrl: input.coverImageUrl,
    publishedAt: input.publishedAt ?? new Date().toISOString(),
  }

  const existingIndex = state.articles.findIndex((item) => item.id === id)

  if (existingIndex >= 0) {
    state.articles[existingIndex] = article
  } else {
    state.articles.push(article)
  }

  saveLocalCMSState(state)
  return article
}

export function upsertLocalAsset(asset: EncounterAsset) {
  const state = getLocalCMSState()
  const encounter = state.encounters.find((item) => item.id === asset.encounterId)

  if (!encounter) {
    throw new Error('Encontro nao encontrado para anexar o material.')
  }

  const assetIndex = encounter.assets.findIndex((item) => item.id === asset.id)

  if (assetIndex >= 0) {
    encounter.assets[assetIndex] = asset
  } else {
    encounter.assets.push(asset)
  }

  saveLocalCMSState(state)
  return asset
}

export function upsertLocalQuiz(quiz: EncounterQuiz) {
  const state = getLocalCMSState()
  const encounter = state.encounters.find((item) => item.id === quiz.encounterId)

  if (!encounter) {
    throw new Error('Encontro nao encontrado para salvar o quiz.')
  }

  encounter.quiz = quiz
  saveLocalCMSState(state)
  return quiz
}

export function saveLocalSettings(settings: SiteSettings) {
  const state = getLocalCMSState()
  state.settings = {
    ...settings,
    homeLead: sanitizeHomeLead(settings.homeLead),
  }
  saveLocalCMSState(state)
  return state.settings
}
