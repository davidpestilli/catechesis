import type { Encounter, EncounterAsset, MaterialCategory } from '@/types/content'

export interface MaterialCategoryConfig {
  key: MaterialCategory
  label: string
  description: string
}

export const materialCategoryConfigs: MaterialCategoryConfig[] = [
  {
    key: 'video',
    label: 'Videos',
    description: 'Aulas, testemunhos, palestras e conteudos em video.',
  },
  {
    key: 'image',
    label: 'Imagens',
    description: 'Galerias, infograficos, ilustracoes e referencias visuais.',
  },
  {
    key: 'text',
    label: 'Textos',
    description: 'Artigos, documentos, roteiros e leituras de aprofundamento.',
  },
  {
    key: 'website',
    label: 'Websites',
    description: 'Paginas e portais para consulta complementar.',
  },
  {
    key: 'book',
    label: 'Livros',
    description: 'Livros, e-books e referencias bibliograficas.',
  },
]

function normalizeMaterialCategory(asset: EncounterAsset): MaterialCategory | null {
  if (asset.materialCategory) return asset.materialCategory
  if (asset.kind === 'support' && asset.view === 'link') return 'website'
  return null
}

export function getEncounterMaterialLinks(encounter: Encounter) {
  return encounter.assets
    .filter((asset) => asset.kind === 'support' && asset.view === 'link' && asset.url.trim())
    .map((asset) => {
      const category = normalizeMaterialCategory(asset)
      if (!category) return null

      return {
        ...asset,
        materialCategory: category,
      }
    })
    .filter((asset): asset is EncounterAsset & { materialCategory: MaterialCategory } => asset !== null)
}

export function getEncounterMaterialGroups(encounter: Encounter) {
  const links = getEncounterMaterialLinks(encounter)

  return materialCategoryConfigs
    .map((category) => ({
      ...category,
      items: links.filter((asset) => asset.materialCategory === category.key),
    }))
    .filter((group) => group.items.length > 0)
}
