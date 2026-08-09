import type { FunctionalComponent, HTMLAttributes } from "preact"
import hydrate from "preact-iso/hydrate"
import { ISLANDS } from "../islands"

type ObjectAny = Record<PropertyKey, unknown>

type IslandProps = {
  visible?: boolean
  media?: string
}

type IslandComponent<P extends ObjectAny = ObjectAny> = FunctionalComponent<P & IslandProps>

function isIslandComponent(src: string | null): src is keyof typeof ISLANDS {
  if (!src) return false
  return Array.from(Object.keys(ISLANDS)).includes(src)
}

export function isBrowser(): boolean {
  return typeof window !== "undefined" && typeof customElements !== "undefined"
}

export function island<P extends ObjectAny>(
  Component: FunctionalComponent<P>,
  islandName: keyof typeof ISLANDS,
): IslandComponent<P> {
  if (!islandName) {
    throw new Error("island() requires a named component. Anonymous functions are not allowed.")
  }

  const Wrapper: IslandComponent<P> = (props: P & IslandProps) => {
    const { visible, media, ...runtimeProps } = props

    if (isBrowser()) {
      return <Component {...(runtimeProps as P)} />
    }

    return (
      <preact-island src={islandName} visible={visible} media={media}>
        <Component {...(runtimeProps as P)} />
      </preact-island>
    )
  }

  Wrapper.displayName = `island_${islandName}`

  return Wrapper
}

function createPreactIslandClass(): typeof HTMLElement {
  return class PreactIsland extends HTMLElement {
    async connectedCallback() {
      const src = this.getAttribute("src")

      if (!isIslandComponent(src)) {
        throw new Error(`${src} is not a registered island`)
      }

      if (this.hasAttribute("media")) {
        await waitForMedia(this.getAttribute("media")!)
      }

      if (this.hasAttribute("visible")) {
        await waitForVisible(this)
      }

      const load = ISLANDS[src]
      if (!load) throw new Error(`${src} loader is undefined`)

      const mod = await load()
      const Component = mod.default

      hydrate(<Component />, this)
    }
  }
}

export function registerIslands(): void {
  if (!isBrowser()) return
  if (customElements.get("preact-island")) return
  customElements.define("preact-island", createPreactIslandClass())
}

export function waitForVisible(element: Element): Promise<void> {
  return new Promise((resolve) => {
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          observer.disconnect()
          resolve()
        }
      }
    })
    observer.observe(element)
  })
}

export function waitForMedia(query: string): Promise<void> {
  const mediaQuery = globalThis.matchMedia(query)

  return new Promise((resolve) => {
    function mediaListener(e: MediaQueryListEvent) {
      if (!e.matches) return
      resolve()
      mediaQuery.removeEventListener("change", mediaListener)
    }

    if (mediaQuery.matches) resolve()
    else mediaQuery.addEventListener("change", mediaListener)
  })
}

declare module "preact/jsx-runtime" {
  namespace JSX {
    interface IntrinsicElements {
      "preact-island": HTMLAttributes<HTMLElement> & {
        visible?: boolean | string
        media?: string
        src: keyof typeof ISLANDS
      }
    }
  }
}
