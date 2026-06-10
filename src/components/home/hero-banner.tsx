import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowDownRight, BookMarked } from 'lucide-react'
import { Button } from '@/components/ui/button'
import catechesisIlluminura from '@/assets/branding/catechesis-illuminura.png'
import type { LandingImage } from '@/data/landing-images'
import type { SiteSettings } from '@/types/content'

interface HeroBannerProps {
  settings: SiteSettings
  images: LandingImage[]
}

export function HeroBanner({ settings, images }: HeroBannerProps) {
  const [currentIndex, setCurrentIndex] = useState(0)

  const hasImages = images.length > 0
  const visibleImages = useMemo(() => (hasImages ? images : []), [hasImages, images])

  useEffect(() => {
    if (visibleImages.length <= 1) return

    const intervalId = window.setInterval(() => {
      setCurrentIndex((value) => (value + 1) % visibleImages.length)
    }, 5600)

    return () => window.clearInterval(intervalId)
  }, [visibleImages.length])

  return (
    <section className="relative isolate overflow-hidden">
      <div className="relative min-h-[90svh]">
        {hasImages ? (
          <div className="absolute inset-0 overflow-hidden">
            {visibleImages.map((image, index) => {
              const isActive = index === currentIndex
              return (
                <div
                  key={image.src}
                  className={`hero-slide ${isActive ? 'hero-slide-active' : 'hero-slide-idle'}`}
                >
                  <img
                    src={image.src}
                    alt={image.alt}
                    className={`hero-slide-image hero-slide-${image.motion}`}
                  />
                </div>
              )
            })}
          </div>
        ) : (
          <video
            autoPlay
            muted
            loop
            playsInline
            poster={settings.heroPosterUrl}
            className="absolute inset-0 h-full w-full object-cover"
          >
            <source src={settings.heroVideoUrl} type="video/mp4" />
          </video>
        )}
        <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(17,21,12,0.24),rgba(17,21,12,0.72))]" />
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_22%_18%,rgba(235,213,151,0.22),transparent_26%),radial-gradient(circle_at_82%_72%,rgba(255,244,214,0.14),transparent_24%)]" />
        <div className="relative z-10 mx-auto flex min-h-[90svh] max-w-6xl flex-col justify-end px-4 pb-12 pt-28 text-stone-50 sm:pb-16">
          <div className="max-w-xl">
            <img
              src={catechesisIlluminura}
              alt="Catechesis"
              className="-ml-20 -mb-[8rem] h-auto w-[clamp(22rem,70vw,72rem)] max-w-full sm:-mb-[13rem]"
            />
            <p className="mt-4 max-w-lg text-lg leading-7 text-stone-100/90">{settings.homeLead}</p>
            <div className="mt-4 flex flex-wrap gap-3">
              <Button asChild size="lg">
                <Link to="/encontros">
                  Explorar encontros
                  <ArrowDownRight className="ml-2 h-4 w-4" />
                </Link>
              </Button>
              <Button asChild variant="outline" size="lg">
                <Link to="/artigos">
                  <BookMarked className="mr-2 h-4 w-4" />
                  Ler artigos
                </Link>
              </Button>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
