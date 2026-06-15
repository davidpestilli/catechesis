import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { userManagementService } from '@/services/user-management-service'
import type { UserRole } from '@/types/content'

export function useManagedUsers(enabled = true) {
  return useQuery({
    queryKey: ['managed-users'],
    queryFn: () => userManagementService.listUsers(),
    enabled: enabled && userManagementService.isAvailable(),
  })
}

export function useCreateManagedUser() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (input: { email: string; password: string; role: UserRole; name?: string }) =>
      userManagementService.createUser(input),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['managed-users'] }),
  })
}

export function useUpdateManagedUser() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (input: { userId: string; role: UserRole; name?: string }) =>
      userManagementService.updateUser(input.userId, { role: input.role, name: input.name }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['managed-users'] }),
  })
}

export function useDeleteManagedUser() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (userId: string) => userManagementService.deleteUser(userId),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['managed-users'] }),
  })
}
