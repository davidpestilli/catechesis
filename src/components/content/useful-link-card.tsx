import { ArrowUpRight, Link2 } from 'lucide-react'
import type { UsefulLink } from '@/types/content'
import { Badge } from '@/components/ui/badge'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'

export function UsefulLinkCard({ usefulLink }: { usefulLink: UsefulLink }) {
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

      {usefulLink.coverImageUrl ? (
        <img
          src={usefulLink.coverImageUrl}
          alt={usefulLink.title}
          className="mt-5 aspect-[16/9] w-full rounded-[20px] object-cover"
        />
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
