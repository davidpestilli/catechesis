import * as TabsPrimitive from '@radix-ui/react-tabs'
import { cn } from '@/lib/utils'

export const Tabs = TabsPrimitive.Root

export function TabsList({
  className,
  ...props
}: React.ComponentPropsWithoutRef<typeof TabsPrimitive.List>) {
  return (
    <TabsPrimitive.List
      className={cn(
        'inline-flex h-auto flex-wrap gap-2 rounded-full bg-stone-100 p-1',
        className,
      )}
      {...props}
    />
  )
}

export function TabsTrigger({
  className,
  ...props
}: React.ComponentPropsWithoutRef<typeof TabsPrimitive.Trigger>) {
  return (
    <TabsPrimitive.Trigger
      className={cn(
        'rounded-full px-4 py-2 text-sm font-medium text-stone-600 transition data-[state=active]:bg-white data-[state=active]:text-stone-900 data-[state=active]:shadow',
        className,
      )}
      {...props}
    />
  )
}

export const TabsContent = TabsPrimitive.Content
