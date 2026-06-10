import { useEffect, useMemo, useRef, useState } from 'react'
import {
  Bold,
  ImagePlus,
  Italic,
  Link2,
  List,
  ListOrdered,
  Type,
  Underline,
  Video,
} from 'lucide-react'
import { cn, fileToDataUrl } from '@/lib/utils'

interface RichTextEditorProps {
  value: string
  onChange: (value: string) => void
  placeholder?: string
  className?: string
}

const fonts = [
  { label: 'Cormorant', value: '"Cormorant Garamond", serif' },
  { label: 'Fraunces', value: '"Fraunces", serif' },
  { label: 'Georgia', value: 'Georgia, serif' },
  { label: 'Arial', value: 'Arial, sans-serif' },
]

const headings = [
  { label: 'Paragrafo', value: 'P' },
  { label: 'Titulo 1', value: 'H1' },
  { label: 'Titulo 2', value: 'H2' },
  { label: 'Titulo 3', value: 'H3' },
]

export function RichTextEditor({
  value,
  onChange,
  placeholder = 'Digite ou cole o conteudo aqui...',
  className,
}: RichTextEditorProps) {
  const editorRef = useRef<HTMLDivElement>(null)
  const imageInputRef = useRef<HTMLInputElement>(null)
  const videoInputRef = useRef<HTMLInputElement>(null)
  const [mounted, setMounted] = useState(false)
  const [currentFont, setCurrentFont] = useState(fonts[0]?.value ?? 'inherit')
  const [currentHeading, setCurrentHeading] = useState('P')

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!mounted || !editorRef.current) return
    if (editorRef.current.innerHTML !== value) {
      editorRef.current.innerHTML = value
    }
  }, [mounted, value])

  function emitChange() {
    onChange(editorRef.current?.innerHTML ?? '')
  }

  function exec(command: string, commandValue?: string) {
    editorRef.current?.focus()
    document.execCommand(command, false, commandValue)
    emitChange()
  }

  async function handleFileInsert(file: File, tag: 'image' | 'video') {
    const dataUrl = await fileToDataUrl(file)
    editorRef.current?.focus()
    const markup =
      tag === 'image'
        ? `<img alt="" class="my-4 h-auto max-w-full rounded-[24px]" src="${dataUrl}" />`
        : `<video controls class="my-4 w-full rounded-[24px]" src="${dataUrl}"></video>`
    document.execCommand('insertHTML', false, markup)
    emitChange()
  }

  const plainText = useMemo(
    () =>
      value
        .replace(/<[^>]+>/g, ' ')
        .replace(/\s+/g, ' ')
        .trim(),
    [value],
  )

  const toolbarButtons = useMemo(
    () => [
      { icon: Bold, label: 'Negrito', action: () => exec('bold') },
      { icon: Italic, label: 'Italico', action: () => exec('italic') },
      { icon: Underline, label: 'Sublinhado', action: () => exec('underline') },
      { icon: List, label: 'Lista', action: () => exec('insertUnorderedList') },
      { icon: ListOrdered, label: 'Lista numerada', action: () => exec('insertOrderedList') },
      {
        icon: Link2,
        label: 'Link',
        action: () => {
          const url = window.prompt('Informe a URL do link:')
          if (url) exec('createLink', url)
        },
      },
      { icon: ImagePlus, label: 'Imagem', action: () => imageInputRef.current?.click() },
      { icon: Video, label: 'Video', action: () => videoInputRef.current?.click() },
    ],
    [],
  )

  return (
    <div
      className={cn(
        'overflow-hidden rounded-[28px] border border-stone-200/80 bg-[linear-gradient(180deg,rgba(255,255,255,0.96),rgba(246,241,230,0.92))] text-stone-800 shadow-[0_18px_45px_rgba(74,61,35,0.09)] transition focus-within:border-primary/30 focus-within:ring-4 focus-within:ring-primary/10',
        className,
      )}
    >
      <div className="border-b border-stone-200/90 bg-stone-50/80 px-3 py-3 md:px-4">
        <div className="grid gap-3">
          <div className="grid gap-2 sm:grid-cols-2 xl:flex xl:flex-wrap xl:items-center">
            <select
              className="h-11 rounded-2xl border border-stone-200 bg-white px-4 text-sm text-stone-700 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
              onChange={(event) => {
                setCurrentFont(event.target.value)
                exec('fontName', event.target.value)
              }}
              value={currentFont}
            >
              {fonts.map((font) => (
                <option key={font.value} value={font.value}>
                  {font.label}
                </option>
              ))}
            </select>

            <select
              className="h-11 rounded-2xl border border-stone-200 bg-white px-4 text-sm text-stone-700 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
              value={currentHeading}
              onChange={(event) => {
                setCurrentHeading(event.target.value)
                exec('formatBlock', event.target.value)
              }}
            >
              {headings.map((heading) => (
                <option key={heading.value} value={heading.value}>
                  {heading.label}
                </option>
              ))}
            </select>
          </div>

          <div className="overflow-x-auto pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            <div className="flex min-w-max gap-2">
              {toolbarButtons.map(({ icon: Icon, label, action }) => (
                <button
                  key={label}
                  type="button"
                  onClick={action}
                  className="inline-flex h-11 w-11 items-center justify-center rounded-2xl border border-stone-200 bg-white text-stone-600 shadow-sm transition hover:border-stone-300 hover:bg-stone-50 hover:text-stone-900"
                  title={label}
                  aria-label={label}
                >
                  <Icon className="h-4 w-4" />
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>

      <div className="bg-white">
        <div
          ref={editorRef}
          contentEditable
          suppressContentEditableWarning
          onInput={emitChange}
          className="rich-text-editor-content min-h-[260px] w-full px-4 py-4 text-[15px] leading-7 text-stone-800 outline-none md:min-h-[340px] md:px-5"
          data-placeholder={placeholder}
        />
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 border-t border-stone-200 bg-stone-50/70 px-4 py-3 text-xs text-stone-500">
        <span className="inline-flex items-center gap-2 font-medium">
          <Type className="h-3.5 w-3.5" />
          HTML publicado no proprio sistema
        </span>
        <span>{plainText ? `${plainText.length} caracteres no conteudo` : 'Editor pronto para receber texto, imagens e video'}</span>
      </div>

      <input
        ref={imageInputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={async (event) => {
          const file = event.target.files?.[0]
          if (file) await handleFileInsert(file, 'image')
          event.target.value = ''
        }}
      />
      <input
        ref={videoInputRef}
        type="file"
        accept="video/*"
        className="hidden"
        onChange={async (event) => {
          const file = event.target.files?.[0]
          if (file) await handleFileInsert(file, 'video')
          event.target.value = ''
        }}
      />
    </div>
  )
}
