import { useMutation } from '@tanstack/react-query'
import { articleSubscriptionService } from '@/services/article-subscription-service'
import type { ArticleCategorySubscriptionDraft } from '@/types/content'

export function useCreateArticleCategorySubscription() {
  return useMutation({
    mutationFn: (input: ArticleCategorySubscriptionDraft) =>
      articleSubscriptionService.createSubscription(input),
  })
}
