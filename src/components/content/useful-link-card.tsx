import { useEffect, useState } from 'react'
import { ArrowUpRight, ImageOff, Link2 } from 'lucide-react'
import type { UsefulLink } from '@/types/content'
import { Badge } from '@/components/ui/badge'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'

export function UsefulLinkCard({ usefulLink }: { usefulLink: UsefulLink }) {
  const [imageVisible, setImageVisible] = useState(Boolean(usefulLink.coverImageUrl))

  useEffect(() => {
    setImageVisible(Boolean(usefulLink.coverImageUrl))
  }, [usefulLink.coverImageUrl])

  return (
    <Card className="group h-full">
      <div className="flex flex-wrap gap-2">
        {usefulLink.tags.slice(0, 3).map((tag) => (
          <Badge key={tag} className="bg-stone-200 text-stone-700">
            {tag}
          </Badge>
        ))}
      </div>

      <CardTitle className="mt-5">{usefulLink.title}</CardTitle>
      <CardDescription className="mt-3">{usefulLink.description}</CardDescription>

      {usefulLink.coverImageUrl && imageVisible ? (
        <img
          src={usefulLink.coverImageUrl}
          alt={usefulLink.title}
          loading="lazy"
          referrerPolicy="no-referrer"
          onError={() => setImageVisible(false)}
          className="mt-5 aspect-[16/9] w-full rounded-[20px] object-cover"
        />
      ) : usefulLink.coverImageUrl ? (
        <div className="mt-5 flex aspect-[16/9] items-center justify-center gap-2 rounded-[20px] border border-dashed border-stone-300 bg-stone-100/80 px-4 text-center text-sm text-stone-500">
          <ImageOff className="h-4 w-4 shrink-0" />
          Nao foi possivel carregar a imagem desta referencia.
        </div>
      ) : null}

      <a
        href={usefulLink.url}
        target="_blank"
        rel="noreferrer"
        className="mt-5 inline-flex items-center gap-2 font-semibold text-stone-900"
      >
        <Link2 className="h-4 w-4" />
        Abrir link
        <ArrowUpRight className="h-4 w-4" />
      </a>
    </Card>
  )
}
