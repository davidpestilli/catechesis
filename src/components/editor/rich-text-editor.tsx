import { useEffect, useMemo, useRef, useState } from 'react'
import {
  Bold,
  ImagePlus,
  Italic,
  Link2,
  List,
  ListOrdered,
  Sparkles,
  Type,
  Underline,
  Video,
} from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
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
    if (tag === 'image') {
      exec('insertImage', dataUrl)
      return
    }

    editorRef.current?.focus()
    document.execCommand(
      'insertHTML',
      false,
      `<video controls class="my-3 w-full rounded-3xl" src="${dataUrl}"></video>`,
    )
    emitChange()
  }

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
    <div className={cn('rounded-[28px] border border-stone-200 bg-slate-800/95 text-slate-100', className)}>
      <div className="flex flex-wrap items-center gap-2 border-b border-slate-700 px-3 py-3">
        <select
          className="rounded-xl border border-slate-600 bg-slate-700 px-3 py-2 text-sm"
          onChange={(event) => exec('fontName', event.target.value)}
          defaultValue={fonts[0]?.value}
        >
          {fonts.map((font) => (
            <option key={font.value} value={font.value}>
              {font.label}
            </option>
          ))}
        </select>

        <select
          className="rounded-xl border border-slate-600 bg-slate-700 px-3 py-2 text-sm"
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

        <div className="flex flex-wrap gap-1">
          {toolbarButtons.map(({ icon: Icon, label, action }) => (
            <button
              key={label}
              type="button"
              onClick={action}
              className="rounded-xl border border-slate-600 bg-slate-700 p-2 text-slate-100 transition hover:bg-slate-600"
              title={label}
            >
              <Icon className="h-4 w-4" />
            </button>
          ))}
        </div>

        <Button
          type="button"
          size="sm"
          variant="ghost"
          className="ml-auto border border-fuchsia-500/40 bg-fuchsia-500/10 text-fuchsia-200"
          onClick={() =>
            toast.info('A acao de IA fica pronta assim que o endpoint com DeepSeek for ligado ao worker.')
          }
        >
          <Sparkles className="mr-2 h-4 w-4" />
          IA
        </Button>
      </div>

      <div
        ref={editorRef}
        contentEditable
        suppressContentEditableWarning
        onInput={emitChange}
        className="min-h-[320px] w-full bg-slate-800 px-4 py-4 text-[15px] leading-7 text-slate-100 outline-none"
        data-placeholder={placeholder}
      />

      {!value ? (
        <div className="pointer-events-none -mt-[308px] px-4 py-4 text-sm text-slate-400">{placeholder}</div>
      ) : null}

      <div className="flex justify-end border-t border-slate-700 px-4 py-3 text-xs text-slate-400">
        <span className="inline-flex items-center gap-2">
          <Type className="h-3.5 w-3.5" />
          HTML publicado no proprio sistema
        </span>
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
