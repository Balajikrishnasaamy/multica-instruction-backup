
## 1. Struts Action Registration

File: `product_package/webapps/ROOT/WEB-INF/classes/struts-qntrl.xml`

This file is checked into the repo but **starts empty** — it is populated by the build from other struts XML configs. The actual pattern for existing endpoints is defined per product package. When adding a new endpoint, find the nearest existing endpoint of the same shape in the security XML (see below) to understand what Struts configuration is expected, or check any `struts-*.xml` in the build output.

**How Struts2 routes requests in this codebase:**

- The `CustomActionMapper` (in the `qntrl` module) maps URL segments to action parameters:
  - `PRIMARY_ENTITY` → resource name (e.g. `circuits`)
  - `PRIMARY_ENTITY_ID` → resource ID (e.g. `abc123`)
  - `SECONDARY_ENTITY` → sub-resource name
  - `SECONDARY_ENTITY_ID` → sub-resource ID
  - `THIRD_ENTITY` / `THIRD_ENTITY_ID` → tertiary nesting

- HTTP method determines which controller method runs:
  - `GET` (no ID) → `index()`
  - `POST` (no ID) → `create()`
  - `GET` (with ID) → `show()` — call `getEntityId()` for the ID
  - `POST` (with ID) → `update()` — call `getEntityId()` for the ID
  - `DELETE` (with ID) → `destroy()` — call `getEntityId()` for the ID

- URL paths follow: `/qntrl/_web/v2/${portal_name}/${workspace_id}/<resource>` (workspace-scoped) or `/qntrl/_web/v2/${portal_name}/<resource>` (portal-scoped).
