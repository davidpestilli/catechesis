import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { commentService } from '@/services/comment-service'
import type { CommentContentType, CommentDraft } from '@/types/content'

export function useComments(contentType: CommentContentType, contentId: string, page: number) {
  return useQuery({
    queryKey: ['comments', contentType, contentId, page],
    queryFn: () => commentService.listComments(contentType, contentId, page),
    enabled: Boolean(contentId),
  })
}

export function useCreateComment(contentType: CommentContentType, contentId: string) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (input: CommentDraft) => commentService.createComment(input),
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ['comments', contentType, contentId],
      })
    },
  })
}
