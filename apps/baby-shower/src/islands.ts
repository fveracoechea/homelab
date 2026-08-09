import { registerIslands } from "./lib/preact-islands"

export const ISLANDS = {
  RsvpForm: () => import("./islands/RsvpForm"),
} as const

registerIslands()
