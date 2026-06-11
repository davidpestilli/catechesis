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
  src: string
  alt: string
  motion: LandingImageMotion
}

export const landingImagePresets: LandingImagePreset[] = [
  {
    src: hero01,
    alt: 'Ilustracao luminosa de basilica para a abertura do Catechesis.',
    motion: 'drift-a',
  },
  {
    src: hero02,
    alt: 'Fachada de basilica iluminada ao entardecer.',
    motion: 'drift-b',
  },
  {
    src: hero03,
    alt: 'Colunata de Roma com profundidade cinematografica.',
    motion: 'drift-c',
  },
  {
    src: hero04,
    alt: 'Cupula sob nuvens suaves.',
    motion: 'drift-a',
  },
  {
    src: hero05,
    alt: 'Vista ampla da praca do Vaticano.',
    motion: 'drift-b',
  },
  {
    src: hero06,
    alt: 'Perspectiva da arquitetura do Vaticano.',
    motion: 'drift-c',
  },
  {
    src: hero07,
    alt: 'Paisagem do rio Tibre em tom contemplativo.',
    motion: 'drift-a',
  },
  {
    src: hero08,
    alt: 'Skyline do Vaticano com luz dramatica.',
    motion: 'drift-b',
  },
]

export function createDefaultLandingImages(): LandingSlide[] {
  return landingImagePresets.map((image) => ({
    id: createId(),
    ...image,
  }))
}
