import { createHashRouter, RouterProvider } from 'react-router-dom'
import { AdminShell } from '@/components/layout/admin-shell'
import { ProtectedRoute } from '@/components/protected-route'
import { SiteShell } from '@/components/layout/site-shell'
import { AdminDashboardPage } from '@/pages/admin-dashboard-page'
import { ArticleCategoryPage } from '@/pages/article-category-page'
import { ArticleViewPage } from '@/pages/article-view-page'
import { ArticlesPage } from '@/pages/articles-page'
import { EncounterAssetPage } from '@/pages/encounter-asset-page'
import { EncounterDetailPage } from '@/pages/encounter-detail-page'
import { EncounterMaterialsPage } from '@/pages/encounter-materials-page'
import { EncounterQuizPage } from '@/pages/encounter-quiz-page'
import { EncountersPage } from '@/pages/encounters-page'
import { GroupDetailPage } from '@/pages/group-detail-page'
import { HomePage } from '@/pages/home-page'
import { LoginPage } from '@/pages/login-page'
import { MiscPage } from '@/pages/misc-page'
import { NotFoundPage } from '@/pages/not-found-page'
import { UsefulLinksPage } from '@/pages/useful-links-page'

const router = createHashRouter([
  {
    path: '/',
    element: <SiteShell />,
    children: [
      { index: true, element: <HomePage /> },
      { path: 'encontros', element: <EncountersPage /> },
      { path: 'encontros/:groupSlug', element: <GroupDetailPage /> },
      { path: 'encontros/:groupSlug/:encounterSlug', element: <EncounterDetailPage /> },
      { path: 'encontros/:groupSlug/:encounterSlug/resumo', element: <EncounterAssetPage /> },
      { path: 'encontros/:groupSlug/:encounterSlug/materiais', element: <EncounterMaterialsPage /> },
      { path: 'encontros/:groupSlug/:encounterSlug/quiz', element: <EncounterQuizPage /> },
      { path: 'diversos', element: <MiscPage /> },
      { path: 'artigos', element: <ArticlesPage /> },
      { path: 'artigos/pasta/:folderSlug', element: <ArticleCategoryPage /> },
      { path: 'artigos/:slug', element: <ArticleViewPage /> },
      { path: 'links-uteis', element: <UsefulLinksPage /> },
      { path: 'login', element: <LoginPage /> },
      { path: '*', element: <NotFoundPage /> },
    ],
  },
  {
    element: <ProtectedRoute />,
    children: [
      {
        path: '/admin',
        element: <AdminShell />,
        children: [{ index: true, element: <AdminDashboardPage /> }],
      },
    ],
  },
])

export default function App() {
  return <RouterProvider router={router} />
}
