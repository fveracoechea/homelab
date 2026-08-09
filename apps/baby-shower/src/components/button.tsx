import type { ComponentChildren } from "preact"
import { tv, type VariantProps } from "tailwind-variants"

export const buttonStyles = tv({
  base: "px-4 py-2 font-semibold transition-colors disabled:opacity-60",
  variants: {
    intent: {
      primary: "bg-iris text-base hover:bg-iris/90",
      ghost: "bg-transparent text-foam hover:text-foam/80",
    },
  },
  defaultVariants: {
    intent: "primary",
  },
})

export type ButtonProps = VariantProps<typeof buttonStyles> & {
  children: ComponentChildren
  type?: "button" | "submit"
  disabled?: boolean
  class?: string
}

export function Button({ intent, class: className, children, ...props }: ButtonProps) {
  return (
    <button class={buttonStyles({ intent, class: className })} {...props}>
      {children}
    </button>
  )
}
