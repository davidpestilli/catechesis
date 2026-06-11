import type { Encounter, EncounterAsset } from '@/types/content'

export function getEncounterSummaryContent(encounter: Encounter) {
  const encounterHtml = encounter.bodyHtml?.trim()
  if (encounterHtml) {
    return {
      title: 'Resumo do encontro',
      description: encounter.summary,
      html: encounterHtml,
    }
  }

  const htmlAsset = encounter.assets.find((asset) => asset.kind === 'summary' && asset.view === 'html')
  if (!htmlAsset?.url.trim()) {
    return null
  }

  return {
    title: htmlAsset.title || 'Resumo do encontro',
    description: htmlAsset.description || encounter.summary,
    html: htmlAsset.url.trim(),
  }
}

export function getEncounterSummaryDownloadAsset(encounter: Encounter): EncounterAsset | undefined {
  return encounter.assets.find(
    (asset) => asset.kind === 'summary' && asset.downloadable && asset.view !== 'html',
  )
}

export function getEncounterPrimarySummaryAsset(encounter: Encounter): EncounterAsset | undefined {
  return encounter.assets.find((asset) => asset.kind === 'summary')
}
