import { describe, expect, test } from "bun:test"
import { renderToString } from "preact-render-to-string"
import { Card } from "./card"

describe("Card", () => {
  test("renders children with panel styles", () => {
    const html = renderToString(
      <Card>
        <p>Clue</p>
      </Card>,
    )
    expect(html).toContain("bg-surface")
    expect(html).toContain("<p>Clue</p>")
  })

  test("merges a custom class", () => {
    const html = renderToString(<Card class="gap-8">Clue</Card>)
    expect(html).toContain("gap-8")
  })
})
