import { useState } from 'react'
import { Navigate, useParams } from 'react-router-dom'
import { CheckCircle2 } from 'lucide-react'
import { FloatingBackButton } from '@/components/navigation/floating-back-button'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { useCMSState } from '@/hooks/use-cms'

export function EncounterQuizPage() {
  const { groupSlug, encounterSlug } = useParams()
  const { data } = useCMSState()
  const group = data?.groups.find((item) => item.slug === groupSlug)
  const encounter = data?.encounters.find(
    (item) => item.slug === encounterSlug && item.groupId === group?.id,
  )
  const [answers, setAnswers] = useState<Record<string, string>>({})
  const [submitted, setSubmitted] = useState(false)

  if (data && !encounter) {
    return <Navigate to="/encontros" replace />
  }

  if (!encounter) {
    return <div className="px-4 py-16 text-stone-700">Carregando quiz...</div>
  }

  const quiz = encounter.quiz

  if (!quiz) {
    return (
      <section className="mx-auto max-w-3xl px-4 py-12">
        <FloatingBackButton to={`/encontros/${groupSlug}/${encounter.slug}`} label="Voltar ao encontro" />
        <Card className="mt-6">
          <CardTitle>Quiz ainda nao cadastrado</CardTitle>
          <CardDescription className="mt-2">
            Use o painel interno para criar perguntas, alternativas e explicacoes deste encontro.
          </CardDescription>
        </Card>
      </section>
    )
  }

  const result = {
    total: quiz.questions.length,
    correct: quiz.questions.filter((question) => {
      const selected = answers[question.id]
      return question.options.find((option) => option.id === selected)?.isCorrect
    }).length,
  }

  return (
    <section className="mx-auto max-w-4xl px-4 py-10 pb-24">
      <FloatingBackButton to={`/encontros/${groupSlug}/${encounter.slug}`} label="Voltar ao encontro" />

      <div className="space-y-5">
        <Card>
          <CardTitle>{quiz.title}</CardTitle>
          <CardDescription className="mt-2">{quiz.description}</CardDescription>
        </Card>

        {quiz.questions.map((question, questionIndex) => {
          const selectedOption = answers[question.id]
          const selectedIsCorrect = question.options.find((option) => option.id === selectedOption)?.isCorrect
          return (
            <Card key={question.id}>
              <CardTitle className="text-2xl">{questionIndex + 1}. {question.prompt}</CardTitle>
              <div className="mt-5 grid gap-3">
                {question.options.map((option) => (
                  <label
                    key={option.id}
                    className="flex cursor-pointer items-start gap-3 rounded-[22px] border border-stone-200 bg-stone-50/70 p-4"
                  >
                    <input
                      type="radio"
                      name={question.id}
                      checked={answers[question.id] === option.id}
                      onChange={() => setAnswers((current) => ({ ...current, [question.id]: option.id }))}
                      className="mt-1"
                    />
                    <span className="text-sm leading-7 text-stone-800">{option.text}</span>
                  </label>
                ))}
              </div>

              {submitted ? (
                <div className="mt-5 rounded-[24px] bg-stone-100 p-4 text-sm leading-7 text-stone-700">
                  <p className="font-semibold text-stone-900">
                    {selectedIsCorrect ? 'Resposta correta.' : 'Resposta incorreta.'}
                  </p>
                  <p className="mt-2">{question.explanation}</p>
                </div>
              ) : null}
            </Card>
          )
        })}

        <Card>
          <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <div>
              <CardTitle>Enviar respostas</CardTitle>
            </div>
            <Button onClick={() => setSubmitted(true)}>Corrigir quiz</Button>
          </div>

          {submitted ? (
            <div className="mt-5 rounded-[26px] bg-primary/10 p-5 text-stone-900">
              <p className="inline-flex items-center gap-2 text-lg font-semibold">
                <CheckCircle2 className="h-5 w-5 text-primary" />
                Voce acertou {result.correct} de {result.total}.
              </p>
            </div>
          ) : null}
        </Card>
      </div>
    </section>
  )
}
