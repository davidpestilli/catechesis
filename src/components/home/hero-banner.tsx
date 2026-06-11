import { useEffect, useMemo, useState } from 'react'
import { createDefaultLandingImages } from '@/data/landing-images'
import type { SiteSettings } from '@/types/content'

interface HeroBannerProps {
  settings: SiteSettings
}

export function HeroBanner({ settings }: HeroBannerProps) {
  const [currentIndex, setCurrentIndex] = useState(0)

  const visibleImages = useMemo(
    () => (settings.landingImages.length > 0 ? settings.landingImages : createDefaultLandingImages()),
    [settings.landingImages],
  )
  const hasImages = visibleImages.length > 0

  useEffect(() => {
    if (visibleImages.length <= 1) return

    const intervalId = window.setInterval(() => {
      setCurrentIndex((value) => (value + 1) % visibleImages.length)
    }, 5600)

    return () => window.clearInterval(intervalId)
  }, [visibleImages.length])

  return (
    <section className="relative isolate overflow-hidden">
      <div className="relative min-h-[78svh]">
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
        <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(17,21,12,0.18),rgba(17,21,12,0.56))]" />
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_20%_18%,rgba(235,213,151,0.16),transparent_28%),radial-gradient(circle_at_82%_72%,rgba(255,244,214,0.10),transparent_24%)]" />
        <div className="relative z-10 mx-auto flex min-h-[78svh] max-w-6xl flex-col justify-center px-4 py-20 text-stone-50 sm:px-6 sm:py-24">
          <div className="max-w-4xl">
            <p className="text-xs font-semibold uppercase tracking-[0.3em] text-stone-100/90">
              Plataforma de catequese
            </p>
            <h1 className="mt-5 max-w-4xl font-display text-5xl leading-[1.02] text-stone-50 sm:text-6xl lg:text-7xl">
              Turmas, encontros e materiais em um so lugar
            </h1>
          </div>
        </div>
      </div>
    </section>
  )
}
