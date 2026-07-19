# Claude Code Instructions - Digibility SEO Intelligence Module

You are building the Digibility SEO Intelligence Module.

## Current SEO Module Folder

/Users/amitguptaamit/gitrepo/userguide/digibility-seo-module

## Existing Digibility App Reference Folder

/Users/amitguptaamit/gitrepo/userguide/digibility-UI-Kit-small

## Important Instruction

Do not modify the existing Digibility app unless explicitly instructed.

The existing app is only a reference for:

- Architecture
- Folder structure
- Tech stack
- UI components
- Design system
- Layout patterns
- Auth approach
- API patterns
- Styling conventions

## Main Context File

Before making any plan or writing any code, read:

PROJECT_CONTEXT.md

## Build Goal

Build SEO Intelligence as a separate independent module that can later plug into the existing Digibility platform.

SEO should support:

- SEO-only users
- Visibility Management-only users
- Users using both modules
- Team members
- Clients
- Agencies managing multiple websites or clients

## Non-Negotiable Rules

1. Do not create a separate authentication system.
2. Reuse Digibility’s existing auth approach later.
3. Do not create a totally new design style.
4. Follow the existing Digibility UI/UX style.
5. Keep SEO separate during development.
6. Every SEO record must be linked to a website URL.
7. Do not overbuild version 1.
8. Keep the architecture compatible with the existing Digibility system.
9. Ask before changing anything inside the existing Digibility app.
10. First inspect the existing project and then propose a plan.

## First Task

Start by inspecting:

1. PROJECT_CONTEXT.md
2. The existing Digibility app structure
3. package.json of the existing Digibility app
4. UI component structure of the existing Digibility app
5. Routing structure of the existing Digibility app
6. Auth/session approach if visible
7. Styling/design system

Then produce a short implementation plan before writing code.
