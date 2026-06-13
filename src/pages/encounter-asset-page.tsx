import DOMPurify from 'dompurify'
import { Navigate, useParams } from 'react-router-dom'
import { FloatingBackButton } from '@/components/navigation/floating-back-button'
import { Badge } from '@/components/ui/badge'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { useCMSState } from '@/hooks/use-cms'
import {
  getEncounterPrimarySummaryAsset,
  getEncounterSummaryContent,
} from '@/lib/encounter-summary'

export function EncounterAssetPage() {
  const { groupSlug, encounterSlug, assetId } = useParams()
  const { data } = useCMSState()
  const group = data?.groups.find((item) => item.slug === groupSlug)
  const encounter = data?.encounters.find(
    (item) => item.slug === encounterSlug && item.groupId === group?.id,
  )

  if (data && !encounter) {
    return <Navigate to="/encontros" replace />
  }

  if (!encounter) {
    return <div className="px-4 py-16 text-stone-700">Carregando conteudo...</div>
  }

  const summaryContent = getEncounterSummaryContent(encounter)
  const asset =
    assetId != null
      ? encounter.assets.find((item) => item.id === assetId)
      : summaryContent
        ? undefined
        : getEncounterPrimarySummaryAsset(encounter)

  if (!asset && !summaryContent) {
    return <Navigate to={`/encontros/${groupSlug}/${encounter.slug}`} replace />
  }

  const isSummaryPage = assetId == null
  const title = assetId == null ? summaryContent?.title ?? asset?.title ?? 'Resumo do encontro' : asset?.title
  const description = assetId == null ? summaryContent?.description ?? asset?.description ?? '' : asset?.description

  return (
    <section className="mx-auto max-w-5xl px-4 py-10 pb-24">
      <FloatingBackButton
        to={`/encontros/${groupSlug}/${encounter.slug}`}
        label="Voltar ao encontro"
      />

      <Card className={isSummaryPage ? 'overflow-hidden p-0' : 'space-y-6'}>
        {isSummaryPage && encounter.coverImageUrl ? (
          <img
            src={encounter.coverImageUrl}
            alt={encounter.title}
            className="h-60 w-full object-cover sm:h-72"
          />
        ) : null}

        <div className={isSummaryPage ? 'space-y-6 p-6 sm:p-8' : 'space-y-6'}>
          {isSummaryPage ? (
            <div className="flex flex-wrap gap-2">
              <Badge>{encounter.theme || 'Encontro'}</Badge>
              {group ? <Badge className="bg-stone-900 text-stone-50">{group.name}</Badge> : null}
            </div>
          ) : null}

          <div className="flex flex-wrap items-start justify-between gap-4">
            <div className={isSummaryPage ? 'max-w-3xl' : undefined}>
              {isSummaryPage ? (
                <h1 className="font-display text-4xl text-stone-900 sm:text-5xl">{title}</h1>
              ) : (
                <CardTitle>{title}</CardTitle>
              )}
              <CardDescription className={isSummaryPage ? 'mt-3 text-base leading-7 sm:text-lg' : 'mt-2'}>
                {description || 'Texto de apoio publicado no proprio sistema.'}
              </CardDescription>
            </div>
          </div>

          {asset?.view === 'image' ? (
            <img src={asset.url} alt={asset.title} className="max-h-[72svh] w-full rounded-[32px] object-contain" />
          ) : null}
          {asset?.view === 'pdf' ? (
            <iframe
              src={asset.url}
              title={asset.title}
              className="h-[72svh] w-full rounded-[32px] border border-stone-200"
            />
          ) : null}
          {asset?.view === 'video' ? (
            <video controls className="max-h-[72svh] w-full rounded-[32px] object-contain">
              <source src={asset.url} />
            </video>
          ) : null}
          {asset?.view === 'html' ? (
            <div
              className="prose-catechesis"
              dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(asset.url) }}
            />
          ) : null}
          {asset?.view === 'link' ? (
            <div className="rounded-[28px] bg-stone-100 p-6">
              <a className="text-primary underline" href={asset.url} target="_blank" rel="noreferrer">
                Abrir material em nova guia
              </a>
            </div>
          ) : null}

          {summaryContent ? (
            <div
              className="prose-catechesis"
              dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(summaryContent.html) }}
            />
          ) : null}
        </div>
      </Card>
    </section>
  )
}
