import { createId } from '@/lib/utils'
import type { LandingImageMotion, LandingSlide } from '@/types/content'
import hero01 from '@/assets/landing/01-ai-basilica.png'
import hero02 from '@/assets/landing/02-basilica-facade.jpg'
import hero03 from '@/assets/landing/03-rome-colonnade.jpg'
import hero04 from '@/assets/landing/04-clouds-dome.jpg'
import hero05 from '@/assets/landing/05-vatican-square.jpg'
import hero06 from '@/assets/landing/06-vatican-view.jpg'
import hero07 from '@/assets/landing/07-tiber-river.jpg'
import hero08 from '@/assets/landing/08-vatican-skyline.jpg'

export interface LandingImagePreset {
  canonicalSrc: string
  src: string
  alt: string
  motion: LandingImageMotion
}

export const landingImagePresets: LandingImagePreset[] = [
  {
    canonicalSrc: '/src/assets/landing/01-ai-basilica.png',
    src: hero01,
    alt: 'Ilustracao luminosa de basilica para a abertura do Catequético.',
    motion: 'drift-a',
  },
  {
    canonicalSrc: '/src/assets/landing/02-basilica-facade.jpg',
    src: hero02,
    alt: 'Fachada de basilica iluminada ao entardecer.',
    motion: 'drift-b',
  },
  {
    canonicalSrc: '/src/assets/landing/03-rome-colonnade.jpg',
    src: hero03,
    alt: 'Colunata de Roma com profundidade cinematografica.',
    motion: 'drift-c',
  },
  {
    canonicalSrc: '/src/assets/landing/04-clouds-dome.jpg',
    src: hero04,
    alt: 'Cupula sob nuvens suaves.',
    motion: 'drift-a',
  },
  {
    canonicalSrc: '/src/assets/landing/05-vatican-square.jpg',
    src: hero05,
    alt: 'Vista ampla da praca do Vaticano.',
    motion: 'drift-b',
  },
  {
    canonicalSrc: '/src/assets/landing/06-vatican-view.jpg',
    src: hero06,
    alt: 'Perspectiva da arquitetura do Vaticano.',
    motion: 'drift-c',
  },
  {
    canonicalSrc: '/src/assets/landing/07-tiber-river.jpg',
    src: hero07,
    alt: 'Paisagem do rio Tibre em tom contemplativo.',
    motion: 'drift-a',
  },
  {
    canonicalSrc: '/src/assets/landing/08-vatican-skyline.jpg',
    src: hero08,
    alt: 'Skyline do Vaticano com luz dramatica.',
    motion: 'drift-b',
  },
]

function normalizeImagePath(value: string) {
  const trimmed = value.trim()

  if (!trimmed) return ''

  try {
    return new URL(trimmed).pathname.replace(/\\/g, '/')
  } catch {
    return trimmed.replace(/\\/g, '/').split(/[?#]/, 1)[0]
  }
}

export function resolveLandingImageSrc(value: string) {
  const normalizedPath = normalizeImagePath(value)

  if (!normalizedPath) return value

  const preset = landingImagePresets.find(
    (image) => normalizedPath === image.canonicalSrc || normalizedPath === image.src,
  )

  return preset?.src ?? value
}

export function serializeLandingImageSrc(value: string) {
  const normalizedPath = normalizeImagePath(value)

  if (!normalizedPath) return value

  const preset = landingImagePresets.find(
    (image) => normalizedPath === image.canonicalSrc || normalizedPath === image.src,
  )

  return preset?.canonicalSrc ?? value
}

export function createDefaultLandingImages(): LandingSlide[] {
  return landingImagePresets.map((image) => ({
    id: createId(),
    src: image.src,
    alt: image.alt,
    motion: image.motion,
  }))
}
