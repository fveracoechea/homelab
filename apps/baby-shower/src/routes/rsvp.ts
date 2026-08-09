import { zValidator } from "@hono/zod-validator"
import { Hono } from "hono"
import { rsvpSchema } from "../lib/schemas"

export const rsvpRoute = new Hono().post("/api/rsvp", zValidator("json", rsvpSchema), (c) => {
  const rsvp = c.req.valid("json")
  return c.json({ ok: true, rsvp })
})

export type RsvpRoute = typeof rsvpRoute
