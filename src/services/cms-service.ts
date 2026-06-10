import { defaultCMSState } from '@/data/mock-content'
import { hasSupabaseConfig } from '@/lib/env'
import { fileToDataUrl } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import {
  getLocalCMSState,
  upsertLocalGroup,
  saveLocalSettings,
  upsertLocalArticle,
  upsertLocalAsset,
  upsertLocalEncounter,
  upsertLocalQuiz,
} from '@/services/local-cms'
import type {
  Article,
  CMSState,
  ClassGroup,
  Encounter,
  EncounterAsset,
  EncounterQuiz,
  SiteSettings,
} from '@/types/content'

const STORAGE_BUCKET = 'catechesis-media'
const REMOVED_HOME_LEADS = new Set([
  'Um espaco mobile-first para encontros, artigos, resumos, materiais de apoio e quizzes de catequese.',
  'Um espaco mobile-first para encontros, artigos, resumos, materiais e quizzes de catequese.',
])

function sanitizeHomeLead(value: unknown) {
  const text = typeof value === 'string' ? value.trim() : ''
  return REMOVED_HOME_LEADS.has(text) ? '' : text
}

function cloneDefaultState() {
  return structuredClone(defaultCMSState)
}

function buildFallbackState(partial?: Partial<CMSState>): CMSState {
  const fallback = cloneDefaultState()

  return {
    settings: partial?.settings ?? fallback.settings,
    groups: partial?.groups?.length ? partial.groups : fallback.groups,
    encounters: partial?.encounters?.length ? partial.encounters : fallback.encounters,
    articles: partial?.articles?.length ? partial.articles : fallback.articles,
    updatedAt: partial?.updatedAt ?? new Date().toISOString(),
  }
}

async function mapSupabaseState(): Promise<CMSState> {
  if (!supabase) {
    return cloneDefaultState()
  }

  const [groupsRes, encountersRes, assetsRes, quizzesRes, questionsRes, optionsRes, articlesRes, settingsRes] =
    await Promise.all([
      supabase.from('class_groups').select('*').order('order_index'),
      supabase.from('encounters').select('*').order('order_index'),
      supabase.from('encounter_assets').select('*').order('order_index'),
      supabase.from('quizzes').select('*'),
      supabase.from('quiz_questions').select('*').order('order_index'),
      supabase.from('quiz_options').select('*').order('order_index'),
      supabase.from('articles').select('*').order('published_at', { ascending: false }),
      supabase.from('site_settings').select('*').eq('key', 'home').maybeSingle(),
    ])

  if (
    groupsRes.error ||
    encountersRes.error ||
    assetsRes.error ||
    quizzesRes.error ||
    questionsRes.error ||
    optionsRes.error ||
    articlesRes.error
  ) {
    throw new Error('Nao foi possivel carregar o conteudo salvo no Supabase.')
  }

  const groups =
    (groupsRes.data ?? []).map((group) => ({
      id: group.id,
      slug: group.slug,
      name: group.name,
      battleCry: group.battle_cry ?? '',
      order: group.order_index ?? 1,
    })) ?? []

  const questionsByQuiz = new Map<string, { id: string; prompt: string; explanation: string; options: EncounterQuiz['questions'][number]['options'] }[]>()

  for (const question of questionsRes.data ?? []) {
    const questionOptions =
      (optionsRes.data ?? [])
        .filter((option) => option.question_id === question.id)
        .map((option) => ({
          id: option.id,
          text: option.text,
          isCorrect: option.is_correct,
        })) ?? []

    const current = questionsByQuiz.get(question.quiz_id) ?? []
    current.push({
      id: question.id,
      prompt: question.prompt,
      explanation: question.explanation ?? '',
      options: questionOptions,
    })
    questionsByQuiz.set(question.quiz_id, current)
  }

  const quizzesByEncounter = new Map<string, EncounterQuiz>()

  for (const quiz of quizzesRes.data ?? []) {
    quizzesByEncounter.set(quiz.encounter_id, {
      id: quiz.id,
      encounterId: quiz.encounter_id,
      title: quiz.title,
      description: quiz.description ?? '',
      questions: questionsByQuiz.get(quiz.id) ?? [],
    })
  }

  const assetsByEncounter = new Map<string, EncounterAsset[]>()

  for (const asset of assetsRes.data ?? []) {
    const list = assetsByEncounter.get(asset.encounter_id) ?? []
    list.push({
      id: asset.id,
      encounterId: asset.encounter_id,
      title: asset.title,
      description: asset.description ?? '',
      kind: asset.kind,
      view: asset.view,
      url: asset.url,
      downloadable: asset.downloadable,
      order: asset.order_index ?? 1,
    })
    assetsByEncounter.set(asset.encounter_id, list)
  }

  return buildFallbackState({
    settings: {
      heroVideoUrl: settingsRes.data?.value?.heroVideoUrl ?? defaultCMSState.settings.heroVideoUrl,
      heroPosterUrl:
        settingsRes.data?.value?.heroPosterUrl ?? defaultCMSState.settings.heroPosterUrl,
      homeLead: sanitizeHomeLead(settingsRes.data?.value?.homeLead),
    },
    groups: groups as ClassGroup[],
    encounters:
      (encountersRes.data ?? []).map((encounter) => ({
        id: encounter.id,
        groupId: encounter.class_group_id ?? groups[0]?.id ?? '',
        slug: encounter.slug,
        title: encounter.title,
        illuminatedTitle: encounter.illuminated_title ?? 'Encontros',
        summary: encounter.summary ?? '',
        theme: encounter.theme ?? '',
        audience: encounter.audience ?? '',
        order: encounter.order_index ?? 1,
        coverImageUrl: encounter.cover_image_url ?? undefined,
        bodyHtml: encounter.body_html ?? undefined,
        assets: assetsByEncounter.get(encounter.id) ?? [],
        quiz: quizzesByEncounter.get(encounter.id),
      })) ?? [],
    articles:
      (articlesRes.data ?? []).map((article) => ({
        id: article.id,
        slug: article.slug,
        title: article.title,
        excerpt: article.excerpt ?? '',
        contentHtml: article.content_html,
        tags: article.tags ?? [],
        featured: article.featured ?? false,
        coverImageUrl: article.cover_image_url ?? undefined,
        publishedAt: article.published_at ?? new Date().toISOString(),
      })) ?? [],
    updatedAt: new Date().toISOString(),
  })
}

async function uploadFile(file: File, folder: string) {
  if (!supabase) {
    return fileToDataUrl(file)
  }

  const filePath = `${folder}/${Date.now()}-${file.name.replace(/\s+/g, '-')}`
  const { error } = await supabase.storage.from(STORAGE_BUCKET).upload(filePath, file, {
    upsert: true,
  })

  if (error) {
    throw new Error(error.message)
  }

  const { data } = supabase.storage.from(STORAGE_BUCKET).getPublicUrl(filePath)
  return data.publicUrl
}

export const cmsService = {
  async getState() {
    if (!hasSupabaseConfig || !supabase) {
      return getLocalCMSState()
    }

    try {
      return await mapSupabaseState()
    } catch {
      return getLocalCMSState()
    }
  },

  async saveEncounter(encounter: Partial<Encounter> & Pick<Encounter, 'title'>) {
    if (!supabase) {
      return upsertLocalEncounter(encounter)
    }

    const payload = {
      id: encounter.id,
      class_group_id: encounter.groupId,
      slug: encounter.slug,
      title: encounter.title,
      illuminated_title: encounter.illuminatedTitle,
      summary: encounter.summary,
      theme: encounter.theme,
      audience: encounter.audience,
      order_index: encounter.order,
      cover_image_url: encounter.coverImageUrl,
      body_html: encounter.bodyHtml,
    }

    const { data, error } = await supabase.from('encounters').upsert(payload).select('*').single()

    if (error) throw new Error(error.message)

    return {
      id: data.id,
      groupId: data.class_group_id,
      slug: data.slug,
      title: data.title,
      illuminatedTitle: data.illuminated_title ?? 'Encontros',
      summary: data.summary ?? '',
      theme: data.theme ?? '',
      audience: data.audience ?? '',
      order: data.order_index ?? 1,
      coverImageUrl: data.cover_image_url ?? undefined,
      bodyHtml: data.body_html ?? undefined,
      assets: encounter.assets ?? [],
      quiz: encounter.quiz,
    } satisfies Encounter
  },

  async saveGroup(group: Partial<ClassGroup> & Pick<ClassGroup, 'name'>) {
    if (!supabase) {
      return upsertLocalGroup(group)
    }

    const payload = {
      id: group.id,
      slug: group.slug,
      name: group.name,
      battle_cry: group.battleCry,
      order_index: group.order,
    }

    const { data, error } = await supabase.from('class_groups').upsert(payload).select('*').single()

    if (error) throw new Error(error.message)

    return {
      id: data.id,
      slug: data.slug,
      name: data.name,
      battleCry: data.battle_cry ?? '',
      order: data.order_index ?? 1,
    } satisfies ClassGroup
  },

  async saveArticle(article: Partial<Article> & Pick<Article, 'title' | 'contentHtml'>) {
    if (!supabase) {
      return upsertLocalArticle(article)
    }

    const payload = {
      id: article.id,
      slug: article.slug,
      title: article.title,
      excerpt: article.excerpt,
      content_html: article.contentHtml,
      tags: article.tags,
      featured: article.featured,
      cover_image_url: article.coverImageUrl,
      published_at: article.publishedAt,
    }

    const { data, error } = await supabase.from('articles').upsert(payload).select('*').single()

    if (error) throw new Error(error.message)

    return {
      id: data.id,
      slug: data.slug,
      title: data.title,
      excerpt: data.excerpt ?? '',
      contentHtml: data.content_html,
      tags: data.tags ?? [],
      featured: data.featured ?? false,
      coverImageUrl: data.cover_image_url ?? undefined,
      publishedAt: data.published_at ?? new Date().toISOString(),
    } satisfies Article
  },

  async saveAsset(asset: EncounterAsset, file?: File | null) {
    const finalUrl = file ? await uploadFile(file, asset.kind) : asset.url

    if (!supabase) {
      return upsertLocalAsset({ ...asset, url: finalUrl })
    }

    const payload = {
      id: asset.id,
      encounter_id: asset.encounterId,
      title: asset.title,
      description: asset.description,
      kind: asset.kind,
      view: asset.view,
      url: finalUrl,
      downloadable: asset.downloadable,
      order_index: asset.order,
    }

    const { data, error } = await supabase
      .from('encounter_assets')
      .upsert(payload)
      .select('*')
      .single()

    if (error) throw new Error(error.message)

    return {
      id: data.id,
      encounterId: data.encounter_id,
      title: data.title,
      description: data.description ?? '',
      kind: data.kind,
      view: data.view,
      url: data.url,
      downloadable: data.downloadable,
      order: data.order_index ?? 1,
    } satisfies EncounterAsset
  },

  async saveQuiz(quiz: EncounterQuiz) {
    if (!supabase) {
      return upsertLocalQuiz(quiz)
    }

    const { data: quizRow, error: quizError } = await supabase
      .from('quizzes')
      .upsert({
        id: quiz.id,
        encounter_id: quiz.encounterId,
        title: quiz.title,
        description: quiz.description,
      })
      .select('*')
      .single()

    if (quizError) throw new Error(quizError.message)

    const existingQuestions = quiz.questions.map((question) => question.id)

    await supabase.from('quiz_questions').delete().eq('quiz_id', quizRow.id)
    await supabase
      .from('quiz_options')
      .delete()
      .in('question_id', existingQuestions.length ? existingQuestions : ['__none__'])

    for (const [questionIndex, question] of quiz.questions.entries()) {
      const { data: questionRow, error: questionError } = await supabase
        .from('quiz_questions')
        .insert({
          id: question.id,
          quiz_id: quizRow.id,
          prompt: question.prompt,
          explanation: question.explanation,
          order_index: questionIndex + 1,
        })
        .select('*')
        .single()

      if (questionError) throw new Error(questionError.message)

      const optionsPayload = question.options.map((option, optionIndex) => ({
        id: option.id,
        question_id: questionRow.id,
        text: option.text,
        is_correct: option.isCorrect,
        order_index: optionIndex + 1,
      }))

      const { error: optionsError } = await supabase.from('quiz_options').insert(optionsPayload)
      if (optionsError) throw new Error(optionsError.message)
    }

    return quiz
  },

  async saveSettings(settings: SiteSettings) {
    if (!supabase) {
      return saveLocalSettings({
        ...settings,
        homeLead: sanitizeHomeLead(settings.homeLead),
      })
    }

    const { error } = await supabase.from('site_settings').upsert({
      key: 'home',
      value: {
        ...settings,
        homeLead: sanitizeHomeLead(settings.homeLead),
      },
    })

    if (error) throw new Error(error.message)
    return {
      ...settings,
      homeLead: sanitizeHomeLead(settings.homeLead),
    }
  },
}
