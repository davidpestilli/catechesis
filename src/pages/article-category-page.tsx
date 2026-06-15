import { useState } from 'react'
import { Navigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { ArticleCard } from '@/components/content/article-card'
import { SectionTitle } from '@/components/home/section-title'
import { FloatingBackButton } from '@/components/navigation/floating-back-button'
import { SubscriptionEmailNotice } from '@/components/subscriptions/subscription-email-notice'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useCreateArticleCategorySubscription } from '@/hooks/use-article-subscriptions'
import { useCMSState } from '@/hooks/use-cms'
import {
  articleCategoryOptions,
  getArticleCategoryFromFolderSlug,
  getArticleCategoryMeta,
} from '@/lib/diversos'

const validFolders = new Set(articleCategoryOptions.map((option) => option.folderSlug))

export function ArticleCategoryPage() {
  const { folderSlug } = useParams()
  const { data } = useCMSState()
  const createSubscription = useCreateArticleCategorySubscription()
  const [subscriberEmail, setSubscriberEmail] = useState('')
  const [subscriptionNoticeVisible, setSubscriptionNoticeVisible] = useState(false)

  if (!folderSlug || !validFolders.has(folderSlug)) {
    return <Navigate to="/artigos" replace />
  }

  if (!data) {
    return <div className="px-4 py-16 text-stone-700">Carregando pasta...</div>
  }

  const category = getArticleCategoryFromFolderSlug(folderSlug)
  if (!category) {
    return <Navigate to="/artigos" replace />
  }
  const activeCategory = category

  const meta = getArticleCategoryMeta(activeCategory)
  const filteredArticles = data.articles.filter((article) => article.category === activeCategory)

  async function handleSubscribe() {
    const trimmedEmail = subscriberEmail.trim().toLowerCase()

    if (!trimmedEmail) {
      toast.error('Informe seu email para receber notificacoes.')
      return
    }

    try {
      const result = await createSubscription.mutateAsync({
        category: activeCategory,
        email: trimmedEmail,
      })

      if (result.alreadySubscribed) {
        setSubscriptionNoticeVisible(false)
        toast.warning('Este email ja esta inscrito nesta pasta.')
        return
      }

      setSubscriberEmail('')
      setSubscriptionNoticeVisible(true)
      toast.success('Inscricao registrada. Voce recebera um email de confirmacao.')
    } catch (error) {
      setSubscriptionNoticeVisible(false)
      const message = error instanceof Error ? error.message : 'Nao foi possivel registrar sua inscricao.'
      toast.error(message)
    }
  }

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 pb-24">
      <FloatingBackButton to="/artigos" label="Voltar para as pastas de artigos" />

      <SectionTitle
        eyebrow="pasta"
        title={meta.label}
        body={meta.description}
      />

      <Card className="mb-6">
        <CardTitle>Receber novos artigos por email</CardTitle>
        <CardDescription className="mt-2">
          Inscreva-se para ser avisado sempre que um novo artigo for publicado em {meta.label}.
        </CardDescription>
        {subscriptionNoticeVisible ? (
          <div className="mt-4">
            <SubscriptionEmailNotice>
              <p>
                Enviamos um email confirmando esta inscricao. Ele pode levar alguns minutos para chegar. Se cair na
                caixa de spam ou na lixeira, mova-o para a caixa principal para ajudar no recebimento dos proximos
                emails do sistema.
              </p>
            </SubscriptionEmailNotice>
          </div>
        ) : null}
        <div className="mt-5 flex flex-col gap-3 md:flex-row md:items-end">
          <div className="flex-1 space-y-2">
            <Label htmlFor="article-category-subscription-email">Email</Label>
            <Input
              id="article-category-subscription-email"
              type="email"
              value={subscriberEmail}
              onChange={(event) => setSubscriberEmail(event.target.value)}
              placeholder="voce@exemplo.com"
            />
          </div>
          <Button onClick={() => void handleSubscribe()} disabled={createSubscription.isPending}>
            {createSubscription.isPending ? 'Inscrevendo...' : 'Quero ser notificado'}
          </Button>
        </div>
      </Card>

      <div className="grid gap-5 lg:grid-cols-2">
        {filteredArticles.map((article) => (
          <ArticleCard key={article.id} article={article} />
        ))}
      </div>

      {filteredArticles.length === 0 ? (
        <div className="rounded-[26px] border border-dashed border-stone-300 bg-white/70 p-6 text-sm leading-6 text-stone-600">
          Nenhum artigo foi publicado nesta pasta ainda.
        </div>
      ) : null}
    </section>
  )
}
