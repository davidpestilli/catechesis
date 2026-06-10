interface SectionTitleProps {
  eyebrow: string
  title: string
  body: string
}

export function SectionTitle({ eyebrow, title, body }: SectionTitleProps) {
  return (
    <div className="mb-6 max-w-2xl">
      <p className="mb-2 text-xs font-semibold uppercase tracking-[0.22em] text-stone-500">
        {eyebrow}
      </p>
      <h2 className="font-gothic text-4xl text-stone-900 sm:text-5xl">{title}</h2>
      <p className="mt-3 text-lg leading-7 text-stone-700">{body}</p>
    </div>
  )
}
