import { env } from '@/lib/env'
import type {
  ArticleCategorySubscriptionDraft,
  CreateArticleCategorySubscriptionResult,
} from '@/types/content'

export const articleSubscriptionService = {
  isAvailable() {
    return Boolean(env.workerUrl)
  },

  async createSubscription(
    input: ArticleCategorySubscriptionDraft,
  ): Promise<CreateArticleCategorySubscriptionResult> {
    if (!env.workerUrl) {
      throw new Error('A URL do Worker não foi configurada.')
    }

    const response = await fetch(`${env.workerUrl}/article-subscriptions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(input),
    })

    const payload = (await response.json().catch(() => null)) as
      | { alreadySubscribed?: boolean; error?: string }
      | null

    if (!response.ok) {
      throw new Error(payload?.error ?? 'Não foi possível registrar sua inscrição.')
    }

    return {
      alreadySubscribed: Boolean(payload?.alreadySubscribed),
    }
  },
}
