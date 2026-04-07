# Localization — Language Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> to implement this plan task-by-task.

**Goal:** Allow users to switch between Spanish and English in the UI

**Architecture:** Session-based locale persistence with optional DB persistence for logged-in users. `before_action :set_locale` in ApplicationController reads locale from session/cookie. Language dropdown in navigation bar.

**Tech Stack:** Rails I18n, Stimulus controller for dropdown, existing en.yml/es.yml locale files

**Current State:**
- Default locale: `:es`, available: `[:es, :en]`
- 34/45 views use `t()` helpers already
- en.yml has 71 keys, es.yml has 298 keys (gap of ~227 keys)
- ~10-15 views have hardcoded Spanish strings mixed with `t()` calls
- No locale-switching mechanism exists

---

### Task 1: Locale Switching Infrastructure

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Create: `app/controllers/locale_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/views/layouts/application.html.erb`

**Context:** Add the core locale-switching mechanism — a controller action to change locale, session storage, and a before_action to apply it on every request.

- [ ] **Step 1: Add set_locale before_action to ApplicationController**

  ```ruby
  before_action :set_locale

  private

  def set_locale
    I18n.locale = session[:locale] || I18n.default_locale
  end
  ```

- [ ] **Step 2: Create LocaleController with update action**

  ```ruby
  class LocaleController < ApplicationController
    skip_before_action :verify_authenticity_token, only: :update

    def update
      locale = params[:locale].to_s.strip.to_sym
      if I18n.available_locales.include?(locale)
        session[:locale] = locale
      end
      redirect_back(fallback_location: root_path)
    end
  end
  ```

- [ ] **Step 3: Add route**

  ```ruby
  patch "locale", to: "locale#update", as: :locale
  ```

- [ ] **Step 4: Make HTML lang tag dynamic**

  Change `<html lang="es">` to `<html lang="<%= I18n.locale %>">`

- [ ] **Step 5: Write tests**

  - Test set_locale reads from session
  - Test LocaleController#update sets session and redirects
  - Test invalid locale is ignored
  - Test HTML lang tag reflects current locale

- [ ] **Step 6: Commit**

  ```bash
  git add app/controllers/application_controller.rb app/controllers/locale_controller.rb config/routes.rb app/views/layouts/application.html.erb spec/
  git commit -m "feat(i18n): add locale switching infrastructure"
  ```

---

### Task 2: Language Selector UI Component

**Files:**
- Modify: `app/views/layouts/_nav_links.html.erb`
- Create: `app/javascript/controllers/locale_selector_controller.js`

**Context:** Add a language dropdown to the navigation bar that lets users switch between ES and EN. Should work on both desktop and mobile nav.

- [ ] **Step 1: Create Stimulus controller for dropdown toggle**

  Simple dropdown controller that toggles visibility on click and closes on outside click.

- [ ] **Step 2: Add language selector to _nav_links.html.erb**

  Add a dropdown with flag/label for each language. Use `patch` requests to LocaleController.
  Desktop: inline dropdown in nav. Mobile: items in mobile menu.
  Use Financial Confidence palette (teal for active, slate for inactive).

- [ ] **Step 3: Write tests**

  - Test nav renders language selector
  - Test current locale is highlighted

- [ ] **Step 4: Commit**

  ```bash
  git commit -m "feat(i18n): add language selector dropdown in navigation"
  ```

---

### Task 3: Complete English Locale File

**Files:**
- Modify: `config/locales/en.yml`

**Context:** The English locale file has only 71 keys while Spanish has 298. Need to add all missing translations to achieve parity.

- [ ] **Step 1: Read es.yml to get all keys**
- [ ] **Step 2: Read en.yml to identify gaps**
- [ ] **Step 3: Add all missing English translations**
- [ ] **Step 4: Verify no missing keys with rake task or i18n-tasks gem**
- [ ] **Step 5: Commit**

  ```bash
  git commit -m "feat(i18n): complete English locale translations"
  ```

---

### Task 4: Extract Hardcoded Spanish Strings from Views

**Files:**
- Modify: Multiple view files (~10-15 files)
- Modify: `config/locales/en.yml` and `config/locales/es.yml`

**Context:** Some views have hardcoded Spanish strings instead of using t() helpers. Extract these to locale files with both ES and EN translations.

Key areas with hardcoded strings:
- Dashboard: "Sincronización de Correos", "Progreso general", etc.
- Expenses index: "Filtrar", "Limpiar", budget statuses
- Forms: Placeholders ("Todas las categorías", "Fecha inicio")
- Buttons and labels throughout
- Sync widget: status messages, labels
- Navigation: ARIA labels, skip links

- [ ] **Step 1: Grep for common hardcoded Spanish patterns**
- [ ] **Step 2: Extract strings from dashboard views**
- [ ] **Step 3: Extract strings from expense views**
- [ ] **Step 4: Extract strings from sync session views**
- [ ] **Step 5: Extract strings from navigation/layout**
- [ ] **Step 6: Add corresponding EN translations**
- [ ] **Step 7: Verify app renders correctly in both locales**
- [ ] **Step 8: Commit**

  ```bash
  git commit -m "feat(i18n): extract hardcoded Spanish strings to locale files"
  ```

---

### Task 5: JavaScript/Stimulus i18n Support

**Files:**
- Modify: `app/javascript/controllers/sync_widget_controller.js`
- Modify: `app/javascript/mixins/sync_channel_mixin.js`
- Modify: `app/views/layouts/application.html.erb`

**Context:** JavaScript controllers have hardcoded Spanish strings (notifications, error messages, status labels). Need to make these translatable.

- [ ] **Step 1: Add locale meta tag to layout for JS access**

  ```erb
  <%= tag.meta name: "locale", content: I18n.locale %>
  ```

- [ ] **Step 2: Create JS i18n helper that reads translations from meta tag or data attributes**
- [ ] **Step 3: Update sync_channel_mixin notifications**
- [ ] **Step 4: Update sync_widget_controller status labels**
- [ ] **Step 5: Commit**

  ```bash
  git commit -m "feat(i18n): add JavaScript translation support for Stimulus controllers"
  ```

---

## Ticket Summary (for Linear when available)

| # | Title | Priority | Complexity |
|---|-------|----------|------------|
| 1 | Locale switching infrastructure (controller, session, routes) | High | Easy |
| 2 | Language selector UI component in navigation | High | Easy |
| 3 | Complete English locale file (227 missing keys) | High | Medium |
| 4 | Extract hardcoded Spanish strings from views | Medium | Medium |
| 5 | JavaScript/Stimulus i18n support | Medium | Medium |
