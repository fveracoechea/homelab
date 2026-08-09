import { describe, expect, test } from "bun:test"
import { rsvpSchema } from "./rsvp"

describe("rsvpSchema", () => {
  test("parses a minimal rsvp", () => {
    const rsvp = rsvpSchema.parse({ name: "Ana", attending: true, plusOne: false })
    expect(rsvp).toEqual({ name: "Ana", attending: true, plusOne: false })
  })

  test("trims the guest name", () => {
    const rsvp = rsvpSchema.parse({ name: "  Ana  ", attending: true, plusOne: false })
    expect(rsvp.name).toBe("Ana")
  })

  test("rejects an empty name", () => {
    const result = rsvpSchema.safeParse({ name: "   ", attending: true, plusOne: false })
    expect(result.success).toBe(false)
  })

  test("accepts an optional plus-one name and theory", () => {
    const rsvp = rsvpSchema.parse({
      name: "Ana",
      attending: true,
      plusOne: true,
      plusOneName: "Luis",
      theory: "girl",
    })
    expect(rsvp.plusOneName).toBe("Luis")
    expect(rsvp.theory).toBe("girl")
  })

  test("rejects an invalid theory", () => {
    const result = rsvpSchema.safeParse({
      name: "Ana",
      attending: true,
      plusOne: false,
      theory: "alien",
    })
    expect(result.success).toBe(false)
  })
})
