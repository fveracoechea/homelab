import type { ComponentChildren } from "preact"
import { tv } from "tailwind-variants"

export const cardStyles = tv({
  base: "flex flex-col gap-4 border border-overlay bg-surface p-6",
})

export function Card({
  children,
  class: className,
}: {
  children: ComponentChildren
  class?: string
}) {
  return <section class={cardStyles({ class: className })}>{children}</section>
}
