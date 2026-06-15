interface SubscriptionEmailNoticeProps {
  children: React.ReactNode
}

export function SubscriptionEmailNotice({ children }: SubscriptionEmailNoticeProps) {
  return (
    <div className="rounded-[28px] border border-amber-300 bg-[linear-gradient(180deg,rgba(255,251,235,0.98),rgba(255,247,237,0.98))] px-5 py-4 text-sm leading-7 text-amber-950 shadow-[0_18px_45px_rgba(146,64,14,0.08)]">
      <p className="font-semibold uppercase tracking-[0.18em] text-amber-800">Verifique seu email</p>
      <div className="mt-2">{children}</div>
    </div>
  )
}
