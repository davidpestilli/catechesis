import type { CMSState } from '@/types/content'
import { createDefaultLandingImages } from '@/data/landing-images'
import { createId } from '@/lib/utils'

const groupOneId = createId()
const groupTwoId = createId()
const encounterOneId = createId()
const encounterTwoId = createId()
const encounterThreeId = createId()
const encounterFourId = createId()
const encounterFiveId = createId()
const quizOneId = createId()
const quizThreeId = createId()

export const defaultCMSState: CMSState = {
  settings: {
    heroVideoUrl:
      'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
    heroPosterUrl:
      'https://images.unsplash.com/photo-1519494026892-80bbd2d6fd0d?auto=format&fit=crop&w=1200&q=80',
    homeLead: '',
    landingImages: createDefaultLandingImages(),
  },
  groups: [
    {
      id: groupOneId,
      slug: 'turma-sao-pedro',
      name: 'Turma Sao Pedro',
      battleCry: 'Firmes na fe, alegres na missao.',
      coverImageUrl:
        'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?auto=format&fit=crop&w=1200&q=80',
      order: 1,
    },
    {
      id: groupTwoId,
      slug: 'turma-sao-paulo',
      name: 'Turma Sao Paulo',
      battleCry: 'Anunciar, servir e caminhar juntos.',
      coverImageUrl:
        'https://images.unsplash.com/photo-1507692049790-de58290a4334?auto=format&fit=crop&w=1200&q=80',
      order: 2,
    },
  ],
  encounters: [
    {
      id: encounterOneId,
      groupId: groupOneId,
      slug: 'o-chamado-da-fe',
      title: 'O Chamado da Fe',
      illuminatedTitle: 'Encontros',
      summary:
        'Apresenta o primeiro encontro com foco no sentido da catequese, acolhida e caminhada em comunidade.',
      theme: 'Introducao a catequese',
      audience: 'Catequizandos iniciantes',
      order: 1,
      coverImageUrl:
        'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?auto=format&fit=crop&w=1200&q=80',
      bodyHtml:
        '<h2>Boas-vindas</h2><p>Este encontro convida o grupo a reconhecer a fe como resposta viva ao amor de Deus, unindo escuta, oracao e convivio.</p><p>Use esta pagina como texto de apoio publicado no proprio sistema.</p>',
      assets: [
        {
          id: createId(),
          encounterId: encounterOneId,
          title: 'Resumo do Encontro',
          description: 'PDF com a estrutura principal do encontro.',
          kind: 'summary',
          view: 'pdf',
          url: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
          downloadable: true,
          order: 1,
        },
        {
          id: createId(),
          encounterId: encounterOneId,
          title: 'Video de acolhida',
          description: 'Breve introducao em video para abrir a conversa do encontro.',
          kind: 'support',
          view: 'link',
          url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          materialCategory: 'video',
          downloadable: false,
          order: 2,
        },
        {
          id: createId(),
          encounterId: encounterOneId,
          title: 'Texto sobre catequese e comunidade',
          description: 'Leitura curta para aprofundar a ideia de caminhada comunitaria.',
          kind: 'support',
          view: 'link',
          url: 'https://www.vatican.va',
          materialCategory: 'text',
          downloadable: false,
          order: 3,
        },
        {
          id: createId(),
          encounterId: encounterOneId,
          title: 'Imagem simbolica da Palavra',
          description: 'Referencia visual para projetar ou compartilhar com a turma.',
          kind: 'support',
          view: 'link',
          url: 'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?auto=format&fit=crop&w=1200&q=80',
          materialCategory: 'image',
          downloadable: false,
          order: 4,
        },
      ],
      quiz: {
        id: quizOneId,
        encounterId: encounterOneId,
        title: 'Quiz do Encontro 1',
        description: 'Revise as ideias centrais trabalhadas no encontro.',
        questions: [
          {
            id: createId(),
            prompt: 'Qual e a proposta principal deste primeiro encontro?',
            explanation:
              'O encontro apresenta a catequese como caminho de fe vivido em comunidade e resposta ao amor de Deus.',
            options: [
              { id: createId(), text: 'Memorizar datas historicas isoladas.', isCorrect: false },
              { id: createId(), text: 'Reconhecer a catequese como caminhada de fe em comunidade.', isCorrect: true },
              { id: createId(), text: 'Substituir a vida comunitaria por estudo individual.', isCorrect: false },
              { id: createId(), text: 'Tratar somente de regras disciplinares.', isCorrect: false },
              { id: createId(), text: 'Encerrar a preparacao liturgica do grupo.', isCorrect: false },
            ],
          },
        ],
      },
    },
    {
      id: encounterThreeId,
      groupId: groupOneId,
      slug: 'jesus-nos-chama-pelo-nome',
      title: 'Jesus nos Chama pelo Nome',
      illuminatedTitle: 'Encontros',
      summary:
        'Aprofunda o chamado pessoal de cada catequizando, com escuta do Evangelho e partilha da propria historia.',
      theme: 'Identidade e vocacao',
      audience: 'Catequizandos iniciantes',
      order: 2,
      coverImageUrl:
        'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80',
      bodyHtml:
        '<h2>Chamado pessoal</h2><p>Jesus conhece cada pessoa pelo nome e chama para uma resposta livre, concreta e comunitaria.</p><p>Este encontro favorece testemunhos, escuta e um pequeno gesto de envio.</p>',
      assets: [
        {
          id: createId(),
          encounterId: encounterThreeId,
          title: 'Roteiro do catequista',
          description: 'Sequencia sugerida para acolhida, Palavra e dinamica.',
          kind: 'summary',
          view: 'pdf',
          url: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
          downloadable: true,
          order: 1,
        },
      ],
      quiz: {
        id: quizThreeId,
        encounterId: encounterThreeId,
        title: 'Quiz do chamado',
        description: 'Revise os pontos principais sobre vocacao e resposta.',
        questions: [
          {
            id: createId(),
            prompt: 'O que significa dizer que Jesus chama cada pessoa pelo nome?',
            explanation:
              'Significa que a fe nao e generica: ela toca a historia pessoal de cada catequizando e pede resposta concreta.',
            options: [
              { id: createId(), text: 'Que a fe dispensa a comunidade.', isCorrect: false },
              { id: createId(), text: 'Que o chamado de Deus alcanca a historia pessoal de cada um.', isCorrect: true },
              { id: createId(), text: 'Que somente os catequistas sao chamados.', isCorrect: false },
              { id: createId(), text: 'Que basta decorar conteudos.', isCorrect: false },
              { id: createId(), text: 'Que nao ha necessidade de resposta.', isCorrect: false },
            ],
          },
        ],
      },
    },
    {
      id: encounterTwoId,
      groupId: groupTwoId,
      slug: 'a-palavra-que-ilumina',
      title: 'A Palavra que Ilumina',
      illuminatedTitle: 'Encontros',
      summary:
        'Explora a importancia da Sagrada Escritura na vida catequetica, com escuta, meditacao e resposta.',
      theme: 'Biblia e vida',
      audience: 'Turmas intermediarias',
      order: 2,
      coverImageUrl:
        'https://images.unsplash.com/photo-1507692049790-de58290a4334?auto=format&fit=crop&w=1200&q=80',
      bodyHtml:
        '<h2>Escuta e resposta</h2><p>A Palavra ilumina a historia pessoal e comunitaria. Cada leitura precisa abrir espaco para silencio, partilha e compromisso.</p>',
      assets: [
        {
          id: createId(),
          encounterId: encounterTwoId,
          title: 'Roteiro visual',
          description: 'Imagem para projetar durante a dinamica.',
          kind: 'summary',
          view: 'image',
          url: 'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?auto=format&fit=crop&w=1200&q=80',
          downloadable: true,
          order: 1,
        },
      ],
    },
    {
      id: encounterFourId,
      groupId: groupTwoId,
      slug: 'celebrar-e-fazer-memoria',
      title: 'Celebrar e Fazer Memoria',
      illuminatedTitle: 'Encontros',
      summary:
        'Convida a turma a compreender a celebracao como memoria viva da fe e experiencia comunitaria.',
      theme: 'Liturgia e comunidade',
      audience: 'Turmas intermediarias',
      order: 2,
      coverImageUrl:
        'https://images.unsplash.com/photo-1464638681273-0962e9b53566?auto=format&fit=crop&w=1200&q=80',
      bodyHtml:
        '<h2>Memoria viva</h2><p>A celebracao ajuda a comunidade a recordar a acao de Deus e responder com louvor, escuta e compromisso.</p>',
      assets: [
        {
          id: createId(),
          encounterId: encounterFourId,
          title: 'Esquema celebrativo',
          description: 'Sugestao simples para conduzir um momento orante com a turma.',
          kind: 'summary',
          view: 'html',
          url: '<h2>Momento celebrativo</h2><p>Inicie com um refrao, proclame a Palavra, abra uma breve partilha e conclua com uma prece comum.</p>',
          downloadable: false,
          order: 1,
        },
      ],
    },
    {
      id: encounterFiveId,
      groupId: groupTwoId,
      slug: 'servico-e-envio',
      title: 'Servico e Envio',
      illuminatedTitle: 'Encontros',
      summary:
        'Organiza a passagem do encontro para a vida concreta, com foco em caridade, servico e testemunho.',
      theme: 'Missao crista',
      audience: 'Turmas intermediarias',
      order: 3,
      coverImageUrl:
        'https://images.unsplash.com/photo-1469571486292-b53601020f35?auto=format&fit=crop&w=1200&q=80',
      bodyHtml:
        '<h2>Fe que se torna gesto</h2><p>O encontro termina com um compromisso simples para a semana e com a recordacao de que a catequese continua fora da sala.</p>',
      assets: [
        {
          id: createId(),
          encounterId: encounterFiveId,
          title: 'Proposta de gesto concreto',
          description: 'Sugestoes de servico para viver durante a semana.',
          kind: 'support',
          view: 'link',
          url: 'https://www.vatican.va',
          materialCategory: 'website',
          downloadable: false,
          order: 1,
        },
        {
          id: createId(),
          encounterId: encounterFiveId,
          title: 'Livro para aprofundamento',
          description: 'Referencia bibliografica para continuar o estudo sobre missao e servico.',
          kind: 'support',
          view: 'link',
          url: 'https://books.google.com',
          materialCategory: 'book',
          downloadable: false,
          order: 2,
        },
      ],
    },
  ],
  articles: [
    {
      id: createId(),
      slug: 'como-organizar-um-encontro-catequetico',
      title: 'Como organizar um encontro catequetico',
      excerpt:
        'Um guia breve para preparar acolhida, proclamacao da Palavra, dinamica e envio com intencionalidade pastoral.',
      publishedAt: new Date().toISOString(),
      category: 'general',
      featured: true,
      tags: ['metodologia', 'planejamento', 'catequese'],
      coverImageUrl:
        'https://images.unsplash.com/photo-1517486808906-6ca8b3f04846?auto=format&fit=crop&w=1200&q=80',
      contentHtml:
        '<h2>Antes do encontro</h2><p>Planeje o objetivo, a passagem biblica central e o gesto concreto que ajudara a turma a guardar a experiencia.</p><h2>Durante o encontro</h2><p>Varie os ritmos entre escuta, conversa, silencio e celebracao.</p><blockquote>A catequese floresce quando o conteudo encontra a vida.</blockquote>',
    },
    {
      id: createId(),
      slug: 'sao-francisco-de-assis-e-a-alegria-do-evangelho',
      title: 'Sao Francisco de Assis e a alegria do Evangelho',
      excerpt:
        'Uma leitura breve sobre simplicidade, louvor e testemunho a partir da vida de Sao Francisco.',
      publishedAt: new Date().toISOString(),
      category: 'saints-life',
      featured: false,
      tags: ['santos', 'testemunho', 'espiritualidade'],
      coverImageUrl:
        'https://images.unsplash.com/photo-1520637836862-4d197d17c11a?auto=format&fit=crop&w=1200&q=80',
      contentHtml:
        '<h2>Um coracao livre</h2><p>Sao Francisco descobriu no Evangelho um caminho de liberdade, pobreza e fraternidade.</p><h2>Para a catequese</h2><p>Sua vida ajuda a aproximar os catequizandos da alegria simples de seguir Jesus com inteireza.</p>',
    },
  ],
  usefulLinks: [
    {
      id: createId(),
      title: 'Portal do Vaticano',
      description: 'Documentos, noticias e textos oficiais para consulta e aprofundamento.',
      url: 'https://www.vatican.va',
      tags: ['igreja', 'documentos', 'vaticano'],
      coverImageUrl:
        'https://images.unsplash.com/photo-1531572753322-ad063cecc140?auto=format&fit=crop&w=1200&q=80',
      order: 1,
    },
    {
      id: createId(),
      title: 'Biblia Online - CNBB',
      description: 'Leitura e pesquisa das Sagradas Escrituras em ambiente digital.',
      url: 'https://www.bibliacatolica.com.br',
      tags: ['biblia', 'leitura', 'estudo'],
      coverImageUrl:
        'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?auto=format&fit=crop&w=1200&q=80',
      order: 2,
    },
  ],
  updatedAt: new Date().toISOString(),
}
