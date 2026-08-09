import { hc } from "hono/client"
import type { RsvpRoute } from "../routes/rsvp"

export const client = hc<RsvpRoute>("/")
