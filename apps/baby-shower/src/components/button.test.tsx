import { describe, expect, test } from "bun:test"
import { renderToString } from "preact-render-to-string"
import { Button } from "./button"

describe("Button", () => {
  test("renders primary intent by default", () => {
    const html = renderToString(<Button>Send RSVP</Button>)
    expect(html).toContain("bg-iris")
    expect(html).toContain("text-base")
  })

  test("renders ghost intent", () => {
    const html = renderToString(<Button intent="ghost">ES</Button>)
    expect(html).toContain("text-foam")
    expect(html).not.toContain("bg-iris")
  })

  test("merges a custom class", () => {
    const html = renderToString(<Button class="mt-4">Send RSVP</Button>)
    expect(html).toContain("mt-4")
  })
})
