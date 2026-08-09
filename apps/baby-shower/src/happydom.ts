import { GlobalRegistrator } from "@happy-dom/global-registrator"

// Imported for side effects before @testing-library/preact in DOM test files:
// testing-library binds its queries to document at module-eval time, so the
// globals must exist first. Not a bunfig preload — bun test shares one global
// across files, and a global window would flip isBrowser() during SSR tests.
GlobalRegistrator.register()
