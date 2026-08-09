import { z } from "zod"

export const rsvpSchema = z.object({
  name: z.string().trim().min(1),
  attending: z.boolean(),
  plusOne: z.boolean(),
  plusOneName: z.string().trim().min(1).optional(),
  theory: z.enum(["girl", "boy"]).optional(),
})

export type Rsvp = z.infer<typeof rsvpSchema>
