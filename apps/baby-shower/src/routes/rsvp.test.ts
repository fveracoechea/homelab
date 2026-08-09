import { describe, expect, test } from "bun:test"
import { testClient } from "hono/testing"
import { rsvpRoute } from "./rsvp"

const client = testClient(rsvpRoute)

describe("POST /api/rsvp", () => {
  test("accepts a valid rsvp and echoes the parsed payload", async () => {
    const res = await client.api.rsvp.$post({
      json: { name: "  Ana  ", attending: true, plusOne: true, plusOneName: "Luis", theory: "girl" },
    })
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({
      ok: true,
      rsvp: { name: "Ana", attending: true, plusOne: true, plusOneName: "Luis", theory: "girl" },
    })
  })

  test("rejects an invalid rsvp", async () => {
    const res = await client.api.rsvp.$post({
      json: { name: "", attending: true, plusOne: false },
    })
    expect(res.status).toBe(400)
  })
})
