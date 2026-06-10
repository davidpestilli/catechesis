import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { cmsService } from '@/services/cms-service'
import type {
  Article,
  Encounter,
  EncounterAsset,
  EncounterQuiz,
  SiteSettings,
} from '@/types/content'

export function useCMSState() {
  return useQuery({
    queryKey: ['cms-state'],
    queryFn: () => cmsService.getState(),
  })
}

export function useSaveEncounter() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (encounter: Partial<Encounter> & Pick<Encounter, 'title'>) =>
      cmsService.saveEncounter(encounter),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['cms-state'] }),
  })
}

export function useSaveArticle() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (article: Partial<Article> & Pick<Article, 'title' | 'contentHtml'>) =>
      cmsService.saveArticle(article),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['cms-state'] }),
  })
}

export function useSaveAsset() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ asset, file }: { asset: EncounterAsset; file?: File | null }) =>
      cmsService.saveAsset(asset, file),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['cms-state'] }),
  })
}

export function useSaveQuiz() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (quiz: EncounterQuiz) => cmsService.saveQuiz(quiz),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['cms-state'] }),
  })
}

export function useSaveSettings() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (settings: SiteSettings) => cmsService.saveSettings(settings),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['cms-state'] }),
  })
}
