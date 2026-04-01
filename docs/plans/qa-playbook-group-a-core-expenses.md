# QA Playbook - Group A: Authentication + Expense CRUD + Expense List + Filters & Search

**Application:** Expense Tracker (Rails 8.1.2)
**Base URL:** `http://localhost:3000`
**UI Language:** Spanish
**Login Credentials:** `admin@expense-tracker.com` / `AdminPassword123!`
**Last Updated:** 2026-03-26

---

## General Instructions for QA Agent

1. Before starting, ensure the Rails server is running at `http://localhost:3000`.
2. Use a modern browser (Chrome or Firefox) with DevTools available.
3. For mobile scenarios, use DevTools responsive mode set to 375x812 (iPhone-sized).
4. For desktop scenarios, use a viewport of at least 1280x800.
5. Every "Expected" result must be verified literally. If the actual result differs in any way, mark the scenario as FAILED.
6. Screenshots should be taken on failure using the browser's built-in screenshot tool.
7. All flash messages in this application are in Spanish unless otherwise noted.
8. The admin login page messages are in English ("Invalid email or password.", "You have been signed out successfully.", etc.).

---

# Section 1: Authentication

---

## Scenario A-001: Login with valid credentials
**Priority:** Critical
**Feature:** Authentication
**Preconditions:** No active session (clear cookies or use incognito window)

### Steps
1. Navigate to `http://localhost:3000/admin/login`
   - **Expected:** Login page loads with an email field, password field, "Recordarme" checkbox, and "Iniciar Sesion" button. The page uses the `admin_login` layout (minimal, centered form). A security notice appears at the bottom.
2. Type `admin@expense-tracker.com` into the Email field
   - **Expected:** Email field accepts the input and displays it
3. Type `AdminPassword123!` into the Password field
   - **Expected:** Password field accepts the input and masks it with dots
4. Click the "Iniciar Sesion" button
   - **Expected:** Browser redirects to `http://localhost:3000/admin/patterns` (the admin root). A flash notice reading "You are already signed in." does NOT appear (that is for re-visiting login while authenticated). The admin patterns page loads successfully.

### Pass Criteria
- [ ] Page redirected to `/admin/patterns` after login
- [ ] No error messages displayed
- [ ] The admin patterns page content is visible
- [ ] Session cookie is set in the browser (check DevTools > Application > Cookies)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-002: Login with invalid email (non-existent user)
**Priority:** Critical
**Feature:** Authentication
**Preconditions:** No active session

### Steps
1. Navigate to `http://localhost:3000/admin/login`
   - **Expected:** Login form is displayed
2. Type `nonexistent@example.com` into the Email field
   - **Expected:** Email field accepts the input
3. Type `SomePassword123!` into the Password field
   - **Expected:** Password field accepts and masks the input
4. Click the "Iniciar Sesion" button
   - **Expected:** Page re-renders the login form (does NOT redirect). A flash alert message appears reading "Invalid email or password." The HTTP status code is 422 (Unprocessable Content). The URL remains `/admin/login`.

### Pass Criteria
- [ ] Flash alert displays "Invalid email or password."
- [ ] Page remains on the login form
- [ ] Email field is pre-filled with `nonexistent@example.com` (email preserved on failure)
- [ ] Password field is empty (not preserved)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-003: Login with valid email but wrong password
**Priority:** Critical
**Feature:** Authentication
**Preconditions:** No active session

### Steps
1. Navigate to `http://localhost:3000/admin/login`
   - **Expected:** Login form is displayed
2. Type `admin@expense-tracker.com` into the Email field
   - **Expected:** Email field accepts the input
3. Type `WrongPassword999!` into the Password field
   - **Expected:** Password field accepts and masks the input
4. Click the "Iniciar Sesion" button
   - **Expected:** Page re-renders the login form. Flash alert displays "Invalid email or password." The email field retains `admin@expense-tracker.com`.

### Pass Criteria
- [ ] Flash alert displays "Invalid email or password."
- [ ] Email field is pre-filled with the entered email
- [ ] Password field is empty
- [ ] No redirect occurred

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-004: Login with empty email and empty password
**Priority:** High
**Feature:** Authentication
**Preconditions:** No active session

### Steps
1. Navigate to `http://localhost:3000/admin/login`
   - **Expected:** Login form is displayed
2. Leave both the Email and Password fields empty
   - **Expected:** Fields are empty
3. Click the "Iniciar Sesion" button
   - **Expected:** Browser-level HTML5 validation prevents form submission (the email field has `required: true`). A browser tooltip appears on the email field indicating it is required.

### Pass Criteria
- [ ] Form submission is blocked by HTML5 required attribute validation
- [ ] Browser shows native "Please fill out this field" tooltip on the email field
- [ ] No network request is sent to the server

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-005: Login with valid email but empty password
**Priority:** High
**Feature:** Authentication
**Preconditions:** No active session

### Steps
1. Navigate to `http://localhost:3000/admin/login`
   - **Expected:** Login form is displayed
2. Type `admin@expense-tracker.com` into the Email field
   - **Expected:** Email field accepts the input
3. Leave the Password field empty
   - **Expected:** Password field is empty
4. Click the "Iniciar Sesion" button
   - **Expected:** Browser-level HTML5 validation prevents submission (password field has `required: true`). A browser tooltip appears on the password field.

### Pass Criteria
- [ ] Form submission is blocked by HTML5 required validation on the password field
- [ ] No network request is sent

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-006: Logout redirects to login page
**Priority:** Critical
**Feature:** Authentication
**Preconditions:** User is logged in (complete Scenario A-001 first)

### Steps
1. Confirm you are on an authenticated page (e.g., `/admin/patterns`)
   - **Expected:** Admin patterns page is loaded and accessible
2. Trigger the logout action by navigating to `http://localhost:3000/admin/logout`
   - **Expected:** Browser redirects to `http://localhost:3000/admin/login`. A flash notice displays "You have been signed out successfully."
3. Verify the session is destroyed by navigating to `http://localhost:3000/expenses`
   - **Expected:** Browser redirects to `http://localhost:3000/admin/login` with an alert "Please sign in to continue." (because the session was destroyed)

### Pass Criteria
- [ ] Redirected to `/admin/login` after logout
- [ ] Flash notice displays "You have been signed out successfully."
- [ ] Attempting to access a protected page after logout redirects back to login
- [ ] Session cookie is cleared or invalidated

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-007: Access protected page without authentication
**Priority:** Critical
**Feature:** Authentication
**Preconditions:** No active session (clear cookies or use incognito window)

### Steps
1. Navigate directly to `http://localhost:3000/expenses`
   - **Expected:** Browser redirects to `http://localhost:3000/admin/login`. A flash alert displays "Please sign in to continue."
2. Navigate directly to `http://localhost:3000/expenses/new`
   - **Expected:** Same redirect to login with the same alert message
3. Navigate directly to `http://localhost:3000/budgets`
   - **Expected:** Same redirect to login with the same alert message
4. Navigate directly to `http://localhost:3000/admin`
   - **Expected:** Redirects to `/admin/login` (admin root requires authentication)

### Pass Criteria
- [ ] All four protected URLs redirect to `/admin/login`
- [ ] Flash alert "Please sign in to continue." is displayed for each attempt
- [ ] No protected content is visible before authentication

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-008: Redirect back to original URL after login
**Priority:** High
**Feature:** Authentication
**Preconditions:** No active session

### Steps
1. Navigate directly to `http://localhost:3000/expenses`
   - **Expected:** Redirects to `/admin/login` with alert "Please sign in to continue." The original URL `/expenses` is stored in the session.
2. Type `admin@expense-tracker.com` into the Email field
   - **Expected:** Email field accepts input
3. Type `AdminPassword123!` into the Password field
   - **Expected:** Password field accepts input
4. Click the "Iniciar Sesion" button
   - **Expected:** Browser redirects to `http://localhost:3000/expenses` (the originally requested URL), NOT to `/admin/patterns`.

### Pass Criteria
- [ ] After login, redirected to `/expenses` (the original protected page)
- [ ] The expenses list page loads correctly
- [ ] No error messages displayed

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-009: Already logged in user visits login page
**Priority:** Medium
**Feature:** Authentication
**Preconditions:** User is logged in (complete Scenario A-001 first)

### Steps
1. While logged in, navigate to `http://localhost:3000/admin/login`
   - **Expected:** Browser redirects to `http://localhost:3000/admin/patterns`. A flash notice displays "You are already signed in."

### Pass Criteria
- [ ] Redirected away from the login page to `/admin/patterns`
- [ ] Flash notice "You are already signed in." is displayed
- [ ] Login form is NOT shown

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-010: Login form preserves email on failed attempt
**Priority:** Medium
**Feature:** Authentication
**Preconditions:** No active session

### Steps
1. Navigate to `http://localhost:3000/admin/login`
   - **Expected:** Login form is displayed with empty fields
2. Type `admin@expense-tracker.com` into the Email field
   - **Expected:** Email field shows the entered email
3. Type `WrongPassword!` into the Password field
   - **Expected:** Password field masks the input
4. Click the "Iniciar Sesion" button
   - **Expected:** Login form re-renders with the error "Invalid email or password."
5. Check the Email field value
   - **Expected:** The Email field still contains `admin@expense-tracker.com`
6. Check the Password field value
   - **Expected:** The Password field is empty (passwords are never preserved)

### Pass Criteria
- [ ] Email field retains the entered email after failed login
- [ ] Password field is cleared after failed login
- [ ] Error message is displayed

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-011: CSRF token present on login form
**Priority:** High
**Feature:** Authentication / Security
**Preconditions:** No active session

### Steps
1. Navigate to `http://localhost:3000/admin/login`
   - **Expected:** Login page loads
2. Open browser DevTools (F12), go to the Elements tab
   - **Expected:** DevTools opens
3. Inspect the login form HTML. Look for a hidden input field named `authenticity_token`
   - **Expected:** A hidden input `<input type="hidden" name="authenticity_token" value="...">` exists inside the `<form>` element. The value is a non-empty string.
4. Also check for a `<meta name="csrf-token">` tag in the `<head>`
   - **Expected:** The meta tag exists with a non-empty `content` attribute

### Pass Criteria
- [ ] Hidden `authenticity_token` field is present in the form
- [ ] The token value is a non-empty string
- [ ] `csrf-token` meta tag is present in the page head

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-012: Rate limiting blocks excessive login attempts
**Priority:** High
**Feature:** Authentication / Security
**Preconditions:** No active session. Clear any rate limit cache if possible.

### Steps
1. Navigate to `http://localhost:3000/admin/login`
   - **Expected:** Login form is displayed
2. Submit the login form with email `admin@expense-tracker.com` and password `Wrong1!` -- repeat this 10 times rapidly
   - **Expected:** Each of the first 9 attempts shows "Invalid email or password." and re-renders the form
3. On the 11th attempt, submit the form again
   - **Expected:** The page renders with the message "Too many login attempts. Please try again later." The HTTP response status is 429 (Too Many Requests).

### Pass Criteria
- [ ] After 10 failed attempts, login is blocked
- [ ] Message "Too many login attempts. Please try again later." is displayed
- [ ] HTTP status code is 429

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-013: GET logout also destroys session
**Priority:** Medium
**Feature:** Authentication
**Preconditions:** User is logged in

### Steps
1. While logged in, navigate to `http://localhost:3000/admin/logout` using the browser address bar (GET request)
   - **Expected:** Session is destroyed. Browser redirects to `/admin/login` with notice "You have been signed out successfully."
2. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Redirects to `/admin/login` confirming the session is gone

### Pass Criteria
- [ ] GET request to `/admin/logout` successfully destroys the session
- [ ] Redirected to login page with success message
- [ ] Protected pages are no longer accessible

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-014: Login form visual design matches Financial Confidence palette
**Priority:** Medium
**Feature:** Authentication / Design
**Preconditions:** No active session

### Steps
1. Navigate to `http://localhost:3000/admin/login`
   - **Expected:** Login page loads
2. Inspect the "Iniciar Sesion" button with DevTools
   - **Expected:** The button has CSS classes including `bg-teal-700` and `hover:bg-teal-800`. It does NOT use blue colors (`bg-blue-*`).
3. Inspect the email and password input focus states by clicking into each field
   - **Expected:** On focus, the input border turns teal (`focus:ring-teal-500`, `focus:border-teal-500`). No blue focus ring appears.
4. Inspect the "Recordarme" checkbox
   - **Expected:** The checkbox uses `text-teal-600` and `focus:ring-teal-500`
5. Check the security notice at the bottom
   - **Expected:** Text uses `text-slate-500` (muted/neutral color)

### Pass Criteria
- [ ] Primary button uses teal-700 background
- [ ] Input focus rings use teal-500
- [ ] No blue colors (`blue-*`) are used anywhere on the page
- [ ] Text colors follow slate palette

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-015: Session fixation prevention
**Priority:** High
**Feature:** Authentication / Security
**Preconditions:** No active session

### Steps
1. Navigate to `http://localhost:3000/admin/login`
   - **Expected:** Login page loads
2. Open DevTools > Application > Cookies. Note the current session cookie value (e.g., `_expense_tracker_session`)
   - **Expected:** A session cookie exists with some value
3. Log in with valid credentials (`admin@expense-tracker.com` / `AdminPassword123!`)
   - **Expected:** Redirected to `/admin/patterns`
4. Open DevTools > Application > Cookies. Check the session cookie value again
   - **Expected:** The session cookie value has CHANGED from the value noted in step 2 (this confirms `reset_session` was called, preventing session fixation)

### Pass Criteria
- [ ] Session cookie value changes after successful login
- [ ] Login completes successfully
- [ ] This confirms session fixation prevention is active

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

# Section 2: Expense CRUD

---

## Scenario A-016: View expense list (index page)
**Priority:** Critical
**Feature:** Expense CRUD
**Preconditions:** User is logged in. At least one expense exists in the database.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** The expense list page loads. The page title in the browser tab reads "Gastos - Expense Tracker". The heading "Gastos" is visible at the top.
2. Verify the summary statistics bar is visible
   - **Expected:** Three colored stat boxes are displayed: a teal box showing "Total" with a currency amount, an emerald box showing "Gastos" with a count, and an amber box showing "Categorias" with a count.
3. Verify the expenses table is visible (on desktop viewport >= 768px)
   - **Expected:** A table with columns "Fecha", "Comercio", "Categoria", "Monto" is visible. Additional columns "Banco", "Estado", "Acciones" may be visible in expanded mode.
4. Verify pagination info is present at the bottom of the table
   - **Expected:** A text string like "Mostrando X gastos" or "Mostrando X-Y de Z gastos" is visible below the table

### Pass Criteria
- [ ] Page loads without errors
- [ ] Summary statistics are displayed (Total amount, Expense count, Category count)
- [ ] Expense table is rendered with data rows
- [ ] Pagination information is present
- [ ] Page title is "Gastos - Expense Tracker"

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-017: View single expense (show page)
**Priority:** Critical
**Feature:** Expense CRUD
**Preconditions:** User is logged in. At least one expense exists.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads
2. On desktop, click on any expense row in the table (or find the show link in the actions column). Alternatively, note the ID of any expense and navigate to `http://localhost:3000/expenses/{id}`
   - **Expected:** The expense show page loads. The heading "Detalle del Gasto" is displayed.
3. Verify the amount display
   - **Expected:** A large formatted amount is shown (e.g., "₡95,000") centered on a slate-50 background
4. Verify the merchant name display
   - **Expected:** The merchant name appears below the amount. If no merchant exists, the text "Sin comercio (error de procesamiento)" appears in rose color.
5. Verify the status badge
   - **Expected:** A colored badge is displayed: green "Procesado" for processed, amber "Pendiente" for pending, or rose "Duplicado" for duplicate status
6. Verify the detail fields section "Informacion del Gasto"
   - **Expected:** Fields displayed: "Fecha de Transaccion", "Comercio", "Descripcion", "Categoria", "Banco", "Cuenta de Email"
7. Verify the metadata section "Metadatos"
   - **Expected:** Fields displayed: "Creado" with timestamp and relative time, "Ultima actualizacion" with timestamp and relative time, "ID" with a numeric value
8. Verify action buttons in the header
   - **Expected:** Three buttons are visible: "Editar" (teal), "Eliminar" (rose), and "Volver" (slate/gray). The "Editar" links to the edit page. The "Volver" links back to `/expenses`.

### Pass Criteria
- [ ] Show page loads without errors
- [ ] Amount is displayed formatted with currency symbol
- [ ] Merchant name or "Sin comercio" placeholder is shown
- [ ] Status badge is visible with correct color
- [ ] All detail fields are present and populated
- [ ] Metadata section shows created/updated timestamps and ID
- [ ] Edit, Delete, and Back buttons are visible

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-018: Create new expense with all valid fields
**Priority:** Critical
**Feature:** Expense CRUD
**Preconditions:** User is logged in. Categories exist in the database.

### Steps
1. Navigate to `http://localhost:3000/expenses/new`
   - **Expected:** The new expense form loads. The heading "Crear Nuevo Gasto" is displayed with the subtitle "Agrega un gasto manualmente al sistema".
2. Verify all form fields are present
   - **Expected:** Fields visible: "Monto" (number field), "Moneda" (dropdown), "Fecha de Transaccion" (date field), "Comercio" (text field), "Descripcion" (text field), "Categoria" (dropdown with "Seleccionar categoria" blank option), "Cuenta de Email" (dropdown with "Entrada manual" blank option), "Notas" (textarea)
3. Enter `50000` in the "Monto" field
   - **Expected:** Number field accepts the value
4. Select `CRC` from the "Moneda" dropdown (if not already selected)
   - **Expected:** CRC is selected
5. Enter today's date in the "Fecha de Transaccion" field
   - **Expected:** Date is entered
6. Type `Supermercado Test` in the "Comercio" field
   - **Expected:** Text field accepts the input
7. Type `Compra de prueba QA` in the "Descripcion" field
   - **Expected:** Text field accepts the input
8. Select any category from the "Categoria" dropdown
   - **Expected:** A category is selected (note which one)
9. Leave "Cuenta de Email" as "Entrada manual"
   - **Expected:** The blank/default option remains
10. Type `Nota de prueba` in the "Notas" field
    - **Expected:** Textarea accepts the input
11. Click the submit button (labeled "Crear Gasto" or similar)
    - **Expected:** Browser redirects to the show page for the newly created expense. A flash notice displays "Gasto creado exitosamente." The show page displays all the values entered in the form.
12. Verify the expense details on the show page
    - **Expected:** Amount is ₡50,000. Merchant is "Supermercado Test". Status is "Procesado". Bank is "Manual Entry". Category matches the selection. Description matches.

### Pass Criteria
- [ ] Form submission succeeds without errors
- [ ] Redirected to the new expense's show page
- [ ] Flash notice "Gasto creado exitosamente." is displayed
- [ ] Amount, merchant, description, category, date all match the entered values
- [ ] Status is automatically set to "processed" (displayed as "Procesado")
- [ ] Bank name is automatically set to "Manual Entry"

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-019: Create expense with missing required fields (amount blank)
**Priority:** Critical
**Feature:** Expense CRUD / Validation
**Preconditions:** User is logged in

### Steps
1. Navigate to `http://localhost:3000/expenses/new`
   - **Expected:** New expense form loads
2. Leave the "Monto" field empty
   - **Expected:** Field is blank
3. Enter today's date in "Fecha de Transaccion"
   - **Expected:** Date is entered
4. Fill in "Comercio" with `Test Merchant`
   - **Expected:** Field accepts input
5. Click the submit button
   - **Expected:** The form re-renders on the same page with validation errors displayed. An error section at the top of the form shows a rose-colored box with the text "Se encontraron X error(es):" followed by a list including a message about amount being required. The page URL changes to `/expenses` (POST target). HTTP status is 422.

### Pass Criteria
- [ ] Form re-renders with validation error messages
- [ ] Error box has rose background (`bg-rose-50 border-rose-200 text-rose-700`)
- [ ] Amount validation error is listed (presence/numericality)
- [ ] No expense was created (verify by checking the expense list)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-020: Create expense with zero amount
**Priority:** High
**Feature:** Expense CRUD / Validation
**Preconditions:** User is logged in

### Steps
1. Navigate to `http://localhost:3000/expenses/new`
   - **Expected:** New expense form loads
2. Enter `0` in the "Monto" field
   - **Expected:** Field shows 0
3. Enter today's date in "Fecha de Transaccion"
   - **Expected:** Date is entered
4. Click the submit button
   - **Expected:** Form re-renders with validation errors. The amount error indicates it "must be greater than 0" (or the Spanish equivalent).

### Pass Criteria
- [ ] Validation error displayed for amount being zero
- [ ] No expense was created
- [ ] Form re-renders with error messages in the rose-colored error box

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-021: Create expense with negative amount
**Priority:** High
**Feature:** Expense CRUD / Validation
**Preconditions:** User is logged in

### Steps
1. Navigate to `http://localhost:3000/expenses/new`
   - **Expected:** New expense form loads
2. Enter `-5000` in the "Monto" field
   - **Expected:** Field shows -5000
3. Enter today's date in "Fecha de Transaccion"
   - **Expected:** Date is entered
4. Click the submit button
   - **Expected:** Form re-renders with validation errors. The amount error indicates it "must be greater than 0".

### Pass Criteria
- [ ] Validation error displayed for negative amount
- [ ] No expense was created

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-022: Create expense with missing transaction date
**Priority:** High
**Feature:** Expense CRUD / Validation
**Preconditions:** User is logged in

### Steps
1. Navigate to `http://localhost:3000/expenses/new`
   - **Expected:** New expense form loads
2. Enter `25000` in the "Monto" field
   - **Expected:** Field accepts the input
3. Leave "Fecha de Transaccion" empty
   - **Expected:** Date field is blank
4. Click the submit button
   - **Expected:** Form re-renders with validation errors. The transaction_date error indicates it is required.

### Pass Criteria
- [ ] Validation error displayed for missing transaction date
- [ ] No expense was created
- [ ] Other entered values are preserved in the form

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-023: Create expense defaults to CRC currency when none specified
**Priority:** Medium
**Feature:** Expense CRUD
**Preconditions:** User is logged in

### Steps
1. Navigate to `http://localhost:3000/expenses/new`
   - **Expected:** New expense form loads
2. Verify the "Moneda" dropdown default selection
   - **Expected:** The currency dropdown shows available options. The controller defaults to CRC if currency is blank.
3. Enter `10000` in "Monto", select today's date for "Fecha de Transaccion", and type `Test Currency Default` in "Comercio"
   - **Expected:** Fields accept input
4. Leave the "Moneda" dropdown on its default selection
   - **Expected:** Default is selected
5. Click the submit button
   - **Expected:** Expense is created successfully. On the show page, verify the currency is CRC.

### Pass Criteria
- [ ] Expense created successfully
- [ ] Currency defaults to CRC

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-024: Edit existing expense
**Priority:** Critical
**Feature:** Expense CRUD
**Preconditions:** User is logged in. At least one expense exists. Note an expense ID for this test.

### Steps
1. Navigate to `http://localhost:3000/expenses/{id}/edit` (replace `{id}` with a known expense ID)
   - **Expected:** Edit form loads with the heading "Editar Gasto" and subtitle "Modifica la informacion del gasto". All fields are pre-populated with the existing expense data.
2. Verify the form fields are pre-populated
   - **Expected:** Amount, currency, transaction date, merchant name, description, category, email account, and notes all show the current values of the expense
3. Change the "Monto" field to `99999`
   - **Expected:** Field updates to 99999
4. Change the "Comercio" field to `Comercio Editado QA`
   - **Expected:** Field updates
5. Click the submit button (labeled "Actualizar Gasto" or similar)
   - **Expected:** Browser redirects to the expense show page. Flash notice displays "Gasto actualizado exitosamente."
6. Verify the updated values on the show page
   - **Expected:** Amount shows ₡99,999. Merchant shows "Comercio Editado QA". All other fields retain their previous values.

### Pass Criteria
- [ ] Edit form loads with pre-populated values
- [ ] Updated fields are saved correctly
- [ ] Redirected to show page after save
- [ ] Flash notice "Gasto actualizado exitosamente." displayed
- [ ] Non-edited fields retain their original values

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-025: Edit expense with invalid data triggers validation
**Priority:** High
**Feature:** Expense CRUD / Validation
**Preconditions:** User is logged in. At least one expense exists.

### Steps
1. Navigate to `http://localhost:3000/expenses/{id}/edit`
   - **Expected:** Edit form loads with pre-populated values
2. Clear the "Monto" field (make it empty)
   - **Expected:** Field is now blank
3. Click the submit button
   - **Expected:** Form re-renders with validation errors in a rose-colored error box. The amount error is listed. The URL becomes `/expenses/{id}` (PATCH target). HTTP status is 422.

### Pass Criteria
- [ ] Validation errors are displayed in the rose error box
- [ ] Amount error is listed
- [ ] Expense was NOT updated (navigate to show page to verify original amount)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-026: Delete expense (soft delete with undo)
**Priority:** Critical
**Feature:** Expense CRUD
**Preconditions:** User is logged in. At least one expense exists. Note the expense ID and merchant name.

### Steps
1. Navigate to `http://localhost:3000/expenses/{id}`
   - **Expected:** Show page loads for the expense
2. Click the "Eliminar" button (rose-colored)
   - **Expected:** A browser confirmation dialog appears asking to confirm deletion (text from `t("expenses.actions.delete_confirm")`)
3. Click "OK" / "Accept" on the confirmation dialog
   - **Expected:** Browser redirects to `http://localhost:3000/expenses`. A flash notice displays "Gasto eliminado. Puedes deshacer esta accion."
4. Verify the expense is no longer visible in the list
   - **Expected:** The deleted expense does not appear in the table (it was soft-deleted)
5. Check for the undo notification
   - **Expected:** A flash message with undo capability is shown. The message mentions the ability to undo the deletion.

### Pass Criteria
- [ ] Confirmation dialog appeared before deletion
- [ ] Redirected to expense list after deletion
- [ ] Flash notice "Gasto eliminado. Puedes deshacer esta accion." displayed
- [ ] Expense is no longer visible in the list
- [ ] Undo notification is present

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-027: Delete expense - cancel confirmation dialog
**Priority:** Medium
**Feature:** Expense CRUD
**Preconditions:** User is logged in. At least one expense exists.

### Steps
1. Navigate to `http://localhost:3000/expenses/{id}`
   - **Expected:** Show page loads
2. Click the "Eliminar" button
   - **Expected:** Confirmation dialog appears
3. Click "Cancel" on the confirmation dialog
   - **Expected:** Dialog closes. The expense show page remains displayed. No deletion occurs.

### Pass Criteria
- [ ] Cancelling the dialog prevents deletion
- [ ] Expense show page remains visible
- [ ] No flash messages appear

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-028: Duplicate expense
**Priority:** High
**Feature:** Expense CRUD
**Preconditions:** User is logged in. At least one expense exists. Note its ID, amount, and merchant name.

### Steps
1. Navigate to `http://localhost:3000/expenses/{id}`
   - **Expected:** Show page loads showing the expense details. Note the amount, merchant, category, and date.
2. Trigger the duplicate action (POST to `/expenses/{id}/duplicate`). This may be available as a button or link on the show page or the expense list row. If not visible in UI, use DevTools console:
   ```javascript
   fetch('/expenses/{id}/duplicate', { method: 'POST', headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content, 'Accept': 'text/html' } }).then(r => r.redirected ? window.location = r.url : null)
   ```
   - **Expected:** A new expense is created and the browser redirects to the new expense's show page. Flash notice "Gasto duplicado exitosamente" is displayed.
3. Verify the duplicated expense on its show page
   - **Expected:** The amount and merchant match the original. The transaction date is today's date (not the original date). The status is "Pendiente" (pending), NOT the original status. The category matches the original (if one was set).

### Pass Criteria
- [ ] New expense created successfully
- [ ] Flash notice "Gasto duplicado exitosamente" displayed
- [ ] Amount and merchant match the original expense
- [ ] Transaction date is today's date
- [ ] Status is "Pendiente" (pending)
- [ ] ML fields are cleared (no confidence badge shown)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-029: Access non-existent expense
**Priority:** High
**Feature:** Expense CRUD
**Preconditions:** User is logged in

### Steps
1. Navigate to `http://localhost:3000/expenses/999999999`
   - **Expected:** Browser redirects to `http://localhost:3000/expenses`. A flash alert displays "Gasto no encontrado o no tienes permiso para verlo."

### Pass Criteria
- [ ] Redirected to the expense list
- [ ] Flash alert "Gasto no encontrado o no tienes permiso para verlo." displayed
- [ ] No error page (500) shown

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-030: New expense form has correct field types
**Priority:** Medium
**Feature:** Expense CRUD / Form
**Preconditions:** User is logged in

### Steps
1. Navigate to `http://localhost:3000/expenses/new`
   - **Expected:** Form loads
2. Inspect the "Monto" field with DevTools
   - **Expected:** Input type is `number` with `step="0.01"` and `placeholder="95000.00"`
3. Inspect the "Fecha de Transaccion" field
   - **Expected:** Input type is `date`
4. Inspect the "Moneda" dropdown
   - **Expected:** It is a `<select>` element with currency options (CRC, USD, EUR, etc.)
5. Inspect the "Categoria" dropdown
   - **Expected:** It is a `<select>` element with a blank option "Seleccionar categoria" followed by category names sorted alphabetically
6. Inspect the "Cuenta de Email" dropdown
   - **Expected:** It is a `<select>` element with a blank option "Entrada manual" followed by email addresses sorted alphabetically
7. Inspect the "Notas" field
   - **Expected:** It is a `<textarea>` element with `rows="3"`
8. Verify the Cancel and Submit buttons
   - **Expected:** Cancel button (slate colors) links to `/expenses`. Submit button (teal colors) has the text "Crear Gasto".

### Pass Criteria
- [ ] Amount field is type="number" with step="0.01"
- [ ] Date field is type="date"
- [ ] Currency is a select dropdown
- [ ] Category is a select with blank "Seleccionar categoria" option
- [ ] Email Account is a select with blank "Entrada manual" option
- [ ] Notes is a textarea
- [ ] Cancel links to `/expenses`
- [ ] Submit button text is "Crear Gasto"

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-031: Edit form submit button text differs from new form
**Priority:** Low
**Feature:** Expense CRUD / Form
**Preconditions:** User is logged in. At least one expense exists.

### Steps
1. Navigate to `http://localhost:3000/expenses/new`
   - **Expected:** Submit button text is "Crear Gasto"
2. Navigate to `http://localhost:3000/expenses/{id}/edit`
   - **Expected:** Submit button text is "Actualizar Gasto" (different from the new form)
3. Verify the Cancel button on the edit form
   - **Expected:** Cancel button links to the expense's show page (`/expenses/{id}`), NOT to the list

### Pass Criteria
- [ ] New form submit button says "Crear Gasto"
- [ ] Edit form submit button says "Actualizar Gasto"
- [ ] Edit form Cancel links to the expense show page

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-032: Show page action buttons link correctly
**Priority:** Medium
**Feature:** Expense CRUD
**Preconditions:** User is logged in. At least one expense exists.

### Steps
1. Navigate to `http://localhost:3000/expenses/{id}`
   - **Expected:** Show page loads
2. Inspect the "Editar" button's href
   - **Expected:** Links to `/expenses/{id}/edit`
3. Click the "Editar" button
   - **Expected:** Edit form loads for this expense
4. Click browser Back button to return to show page
   - **Expected:** Show page loads again
5. Inspect the "Volver" button's href
   - **Expected:** Links to `/expenses`
6. Click the "Volver" button
   - **Expected:** Navigates to the expense list

### Pass Criteria
- [ ] "Editar" button navigates to the edit form for the correct expense
- [ ] "Volver" button navigates to the expense list
- [ ] "Eliminar" button is present with rose styling

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-033: Show page displays ML confidence badge
**Priority:** Medium
**Feature:** Expense CRUD / ML Categorization
**Preconditions:** User is logged in. An expense with ML categorization exists (has ml_confidence set).

### Steps
1. Find or identify an expense that has been auto-categorized by ML (has a non-null `ml_confidence` value). Navigate to its show page `http://localhost:3000/expenses/{id}`
   - **Expected:** Show page loads
2. Look at the "Categoria" section
   - **Expected:** A category name is displayed. If ML categorized, a confidence indicator is shown. Confidence levels: high (>= 85%, green), medium (>= 70%, amber), low (>= 50%, orange), very low (< 50%, rose).
3. If no ML-categorized expense exists, verify that manually categorized expenses show the category name without a confidence badge
   - **Expected:** Category name displayed without confidence percentage

### Pass Criteria
- [ ] Category is displayed on the show page
- [ ] If ML-categorized, confidence badge/indicator is visible with correct color
- [ ] If manually categorized, no confidence badge appears

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-034: Show page metadata section displays timestamps
**Priority:** Medium
**Feature:** Expense CRUD
**Preconditions:** User is logged in. At least one expense exists.

### Steps
1. Navigate to `http://localhost:3000/expenses/{id}`
   - **Expected:** Show page loads
2. Scroll to the "Metadatos" section
   - **Expected:** Section heading "Metadatos" is visible
3. Verify "Creado" field
   - **Expected:** Shows a date/time in format "DD/MM/YYYY a las HH:MM" followed by a relative time in parentheses (e.g., "(3 days ago)")
4. Verify "Ultima actualizacion" field
   - **Expected:** Shows a date/time in the same format with relative time
5. Verify "ID" field
   - **Expected:** Shows the expense ID as a number prefixed with "#" in monospace font

### Pass Criteria
- [ ] "Creado" timestamp is present and formatted correctly
- [ ] "Ultima actualizacion" timestamp is present and formatted correctly
- [ ] ID is displayed with "#" prefix in monospace font
- [ ] Relative times are displayed in parentheses

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-035: Create expense with all fields blank
**Priority:** Medium
**Feature:** Expense CRUD / Validation
**Preconditions:** User is logged in

### Steps
1. Navigate to `http://localhost:3000/expenses/new`
   - **Expected:** New expense form loads
2. Do not fill in any fields. Remove any default values if present in date or currency fields.
   - **Expected:** Fields are empty or at default
3. Click the submit button
   - **Expected:** Form re-renders with multiple validation errors. At minimum: amount (presence and numericality), transaction_date (presence), status (presence), currency (presence). The error count is shown in the error summary header.

### Pass Criteria
- [ ] Multiple validation errors are displayed
- [ ] Amount, transaction_date errors are present at minimum
- [ ] Error box is rose-colored and lists all errors
- [ ] No expense was created

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

# Section 3: Expense List and Pagination

---

## Scenario A-036: Default list shows up to 50 expenses per page
**Priority:** Critical
**Feature:** Expense List / Pagination
**Preconditions:** User is logged in. More than 50 expenses exist in the database.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads
2. Count the number of expense rows in the table (desktop view)
   - **Expected:** Exactly 50 rows are visible (or fewer if total expenses < 50)
3. Verify the pagination text at the bottom
   - **Expected:** Text reads "Mostrando 1-50 de {total} gastos" where {total} is the total expense count

### Pass Criteria
- [ ] No more than 50 expense rows displayed on the first page
- [ ] Pagination text shows "Mostrando 1-50 de X gastos"
- [ ] Total count in the summary matches the pagination count

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-037: Pagination controls navigate between pages
**Priority:** Critical
**Feature:** Expense List / Pagination
**Preconditions:** User is logged in. More than 50 expenses exist.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** First page of expenses loads with pagination controls visible
2. Verify pagination controls exist below the table
   - **Expected:** Page number links and/or Next/Previous buttons are visible
3. Click the "Next" page button or page number "2"
   - **Expected:** Page reloads showing the second set of expenses. URL updates to include `?page=2`. Pagination text updates to "Mostrando 51-100 de X gastos" (or appropriate range).
4. Click the "Previous" page button or page number "1"
   - **Expected:** Page returns to the first set of expenses. Pagination text reverts to "Mostrando 1-50 of X gastos".

### Pass Criteria
- [ ] Pagination controls are visible and clickable
- [ ] Clicking Next/page 2 shows a different set of expenses
- [ ] URL updates with `?page=2` parameter
- [ ] Clicking Previous/page 1 returns to the first page
- [ ] Pagination text updates accurately on each page

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-038: View toggle between compact and expanded mode (desktop)
**Priority:** High
**Feature:** Expense List / View Toggle
**Preconditions:** User is logged in. At least one expense exists. Desktop viewport (>= 768px).

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads in default view mode. The view toggle button is visible in the table header area with text "Vista Compacta" and a list icon.
2. Note which columns are visible
   - **Expected:** In compact mode, columns shown are: Fecha, Comercio, Categoria, Monto. The columns "Banco", "Estado", "Acciones" may be hidden (they have `data-view-toggle-target="expandedColumns"`).
3. Click the view toggle button ("Vista Compacta" / icon)
   - **Expected:** The view switches to expanded mode. The button text changes (icon swaps). Additional columns "Banco", "Estado", "Acciones" become visible. Alternatively, if already in expanded mode, clicking toggles to compact (hiding those columns).
4. Click the view toggle button again
   - **Expected:** View switches back to the previous mode

### Pass Criteria
- [ ] View toggle button is visible in the table header
- [ ] Clicking the toggle changes the visible columns
- [ ] Expanded mode shows Banco, Estado, Acciones columns
- [ ] Compact mode hides those columns
- [ ] Toggle button text/icon updates to reflect current mode

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-039: View toggle persists across page loads (sessionStorage)
**Priority:** Medium
**Feature:** Expense List / View Toggle
**Preconditions:** User is logged in. Desktop viewport.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads
2. Click the view toggle button to switch to expanded mode (or compact if already expanded)
   - **Expected:** View changes
3. Note the current view mode
   - **Expected:** View mode is noted (compact or expanded)
4. Reload the page (F5 or Ctrl+R)
   - **Expected:** After reload, the view mode should be the same as what was set in step 2 (persisted via sessionStorage)
5. Open browser DevTools > Application > Session Storage
   - **Expected:** A key related to view toggle exists with the saved view mode value

### Pass Criteria
- [ ] View mode persists after page reload
- [ ] SessionStorage contains the view mode preference
- [ ] The correct mode is applied on page load

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-040: Mobile card view visible at < 768px
**Priority:** Critical
**Feature:** Expense List / Responsive
**Preconditions:** User is logged in. At least one expense exists.

### Steps
1. Open DevTools and set the viewport to 375x812 (mobile size)
   - **Expected:** Responsive mode activated
2. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Page loads. The desktop table (`#expense_list`) is hidden (`hidden md:block`). The mobile card view (`#expense_cards`) is visible.
3. Verify the mobile card section header
   - **Expected:** "Lista de Gastos" heading is visible with a count (e.g., "X gastos")
4. Verify at least one expense card is displayed
   - **Expected:** Cards are rendered as `<article>` elements with white backgrounds, rounded corners, and border. Each card shows: a category color dot, merchant name, amount on the right, date below, and category name.
5. Check that the desktop table is NOT visible
   - **Expected:** The `<div id="expense_list">` element has `hidden md:block` class, so at < 768px it is hidden

### Pass Criteria
- [ ] Mobile card view is visible at 375px width
- [ ] Desktop table is hidden at 375px width
- [ ] Cards display merchant name, amount, date, and category
- [ ] Card styling matches Financial Confidence palette (white bg, rounded-xl, slate border)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-041: Desktop table visible at >= 768px
**Priority:** High
**Feature:** Expense List / Responsive
**Preconditions:** User is logged in. At least one expense exists.

### Steps
1. Open DevTools and set the viewport to 1280x800 (desktop size)
   - **Expected:** Desktop responsive mode activated
2. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Page loads. The desktop table (`#expense_list`) is visible (`hidden md:block` - visible at md and above). The mobile card section (`#expense_cards`) is hidden (`md:hidden`).
3. Verify the table headers
   - **Expected:** Table headers include "Fecha", "Comercio", "Categoria", "Monto" at minimum
4. Verify the mobile cards are NOT visible
   - **Expected:** The `<div id="expense_cards">` element has `md:hidden` class, so at >= 768px it is hidden

### Pass Criteria
- [ ] Desktop table is visible at 1280px width
- [ ] Mobile cards are hidden at 1280px width
- [ ] Table has proper column headers

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-042: Collapsible filters on mobile
**Priority:** High
**Feature:** Expense List / Mobile UX
**Preconditions:** User is logged in. Mobile viewport (375px wide).

### Steps
1. Set viewport to 375x812
   - **Expected:** Mobile viewport active
2. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Page loads. The filter form is hidden by default on mobile (wrapped in `data-collapsible-filter-target="content"` with class `hidden md:block`).
3. Locate the "Filtrar" button
   - **Expected:** A button labeled "Filtrar" with a filter icon is visible. It has an `aria-expanded="false"` attribute.
4. Click the "Filtrar" button
   - **Expected:** The filter section expands/becomes visible below the button. The `aria-expanded` attribute changes to `"true"`. Filter fields (category dropdown, bank dropdown, date fields, filter/clear buttons) are now visible.
5. Click the "Filtrar" button again
   - **Expected:** The filter section collapses and becomes hidden again. `aria-expanded` returns to `"false"`.

### Pass Criteria
- [ ] Filters are hidden by default on mobile
- [ ] "Filtrar" button is visible on mobile
- [ ] Clicking the button toggles the filter section visibility
- [ ] `aria-expanded` attribute updates correctly
- [ ] Filter fields are accessible when expanded

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-043: Active filter count badge on mobile
**Priority:** Medium
**Feature:** Expense List / Mobile UX
**Preconditions:** User is logged in. Mobile viewport (375px wide).

### Steps
1. Set viewport to 375x812
   - **Expected:** Mobile viewport active
2. Navigate to `http://localhost:3000/expenses?category=Supermercado&bank=BAC`
   - **Expected:** Page loads with filters applied
3. Locate the "Filtrar" button
   - **Expected:** The button shows a circular badge with the number `2` (because two filters are active: category and bank). The badge has classes including `bg-teal-600 rounded-full text-white`.
4. Navigate to `http://localhost:3000/expenses?category=Supermercado`
   - **Expected:** Badge shows `1`
5. Navigate to `http://localhost:3000/expenses` (no filters)
   - **Expected:** No badge is shown next to the "Filtrar" button

### Pass Criteria
- [ ] Badge shows correct count of active filters
- [ ] Badge is teal-colored circle with white text
- [ ] Badge disappears when no filters are active
- [ ] Count includes category, bank, start_date, end_date params

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-044: Collapsible category summary on mobile
**Priority:** Medium
**Feature:** Expense List / Mobile UX
**Preconditions:** User is logged in. Multiple categories with expenses exist. Mobile viewport. No category filter applied.

### Steps
1. Set viewport to 375x812
   - **Expected:** Mobile viewport active
2. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Page loads. The "Resumen por Categoria" section is present (only when no category filter is active).
3. Verify the category summary section is collapsed on mobile
   - **Expected:** The heading "Resumen por Categoria" is visible. A "Ver resumen" button is visible (md:hidden). The category grid content is hidden on mobile (`hidden md:block` class on the content div).
4. Click the "Ver resumen" button
   - **Expected:** The category summary grid expands, showing category names with their total amounts in slate-50 rounded boxes
5. Click the "Ver resumen" button again
   - **Expected:** The summary collapses back to hidden

### Pass Criteria
- [ ] Category summary heading is visible
- [ ] Content is collapsed by default on mobile
- [ ] "Ver resumen" toggle button works
- [ ] Category amounts are displayed when expanded

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-045: Mobile card displays correct expense data
**Priority:** High
**Feature:** Expense List / Mobile
**Preconditions:** User is logged in. Expenses with various statuses exist. Mobile viewport (375px wide).

### Steps
1. Set viewport to 375x812
   - **Expected:** Mobile viewport active
2. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Mobile cards are displayed
3. Examine the first expense card
   - **Expected:** The card contains:
     - A small colored circle (category color dot) on the left
     - Merchant name (truncated if long) next to the dot
     - Amount formatted as "₡X,XXX" right-aligned
     - Below the merchant: date in DD/MM/YYYY format, a dot separator, and category name
4. Find a card for an expense with status "pending"
   - **Expected:** The card shows an additional amber-colored badge "Pendiente" after the category name
5. Find a card for an expense with status "processed"
   - **Expected:** No status badge is shown (status badge is hidden for "processed" expenses)
6. Find a card for an uncategorized expense (if any)
   - **Expected:** A slate-gray dot is shown instead of a colored category dot. The merchant name area may show "Sin comercio" in rose italic if merchant is also missing.

### Pass Criteria
- [ ] Category color dot is present on each card
- [ ] Merchant name and amount are displayed on the same row
- [ ] Date and category name are on a second row
- [ ] "Pendiente" badge appears for pending expenses
- [ ] No status badge for "processed" expenses
- [ ] Uncategorized expenses show a gray dot

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-046: Mobile card expand actions on tap
**Priority:** High
**Feature:** Expense List / Mobile Interactions
**Preconditions:** User is logged in. Expenses exist. Mobile viewport (375px wide).

### Steps
1. Set viewport to 375x812
   - **Expected:** Mobile viewport active
2. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Mobile cards are displayed. Action sections are hidden by default.
3. Tap (click) on any expense card
   - **Expected:** An action bar slides open below the card content. The action bar shows four buttons: "Categoria" (teal), "Estado" (emerald), "Editar" (slate), "Eliminar" (rose). The bar has a top border and slate-50 background.
4. Tap the same card again (or press Escape)
   - **Expected:** The action bar collapses and hides

### Pass Criteria
- [ ] Tapping a card reveals the action buttons
- [ ] Four action buttons are visible: Categoria, Estado, Editar, Eliminar
- [ ] Action buttons use correct Financial Confidence colors
- [ ] Tapping again or pressing Escape hides the actions

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-047: Mobile pagination
**Priority:** High
**Feature:** Expense List / Pagination / Mobile
**Preconditions:** User is logged in. More than 50 expenses exist. Mobile viewport (375px wide).

### Steps
1. Set viewport to 375x812
   - **Expected:** Mobile viewport active
2. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Mobile cards are displayed. Scroll to the bottom of the card list.
3. Verify mobile pagination section
   - **Expected:** If more than one page exists, pagination controls are visible below the cards. Text "Mostrando X-Y de Z gastos" is displayed.
4. Click a pagination link to go to page 2
   - **Expected:** Page reloads with the next set of cards. Pagination text updates.

### Pass Criteria
- [ ] Pagination controls appear below mobile cards
- [ ] Pagination text shows correct range
- [ ] Clicking page links loads different cards

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-048: Summary statistics update with filters
**Priority:** High
**Feature:** Expense List / Summary
**Preconditions:** User is logged in. Multiple expenses with different categories exist.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Page loads with summary stats: Total amount, expense count, category count
2. Note the Total amount and expense count values
   - **Expected:** Values are noted
3. Apply a category filter by selecting a specific category and clicking "Filtrar"
   - **Expected:** Page reloads with filtered results. The Total amount and expense count in the summary stats update to reflect ONLY the filtered expenses. The category count may change.
4. Compare the new stats with the unfiltered stats
   - **Expected:** The filtered Total amount is less than or equal to the unfiltered Total. The filtered count is less than or equal to the unfiltered count.

### Pass Criteria
- [ ] Summary stats update when filters are applied
- [ ] Total amount reflects only filtered expenses
- [ ] Expense count reflects only filtered expenses
- [ ] Category count updates appropriately

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-049: Category summary section hides when category filter is active
**Priority:** Medium
**Feature:** Expense List
**Preconditions:** User is logged in. Multiple categories with expenses exist.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** "Resumen por Categoria" section is visible (when no category filter is applied)
2. Apply a category filter by selecting a category and clicking "Filtrar"
   - **Expected:** Page reloads with filtered results. The "Resumen por Categoria" section is NO LONGER visible (the view conditionally hides it when `params[:category]` is present).

### Pass Criteria
- [ ] Category summary is visible when no category filter is active
- [ ] Category summary is hidden when a category filter is active

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-050: Batch selection mode toggle (desktop)
**Priority:** Medium
**Feature:** Expense List / Batch Selection
**Preconditions:** User is logged in. Expenses exist. Desktop viewport.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense table is displayed. The "Seleccion Multiple" button is visible in the table header.
2. Verify the checkbox column is hidden by default
   - **Expected:** The checkbox column header (with `checkbox-header` class) has `hidden` class. Row checkboxes are not visible.
3. Click the "Seleccion Multiple" button
   - **Expected:** Checkbox column becomes visible. Each expense row now shows a checkbox. A master checkbox appears in the header. The selection counter "0 gastos seleccionados" may appear.
4. Click a row checkbox to select one expense
   - **Expected:** Checkbox is checked. The selection counter updates to "1 gastos seleccionados". The batch selection toolbar may appear at the bottom.
5. Click the "Seleccion Multiple" button again to exit selection mode
   - **Expected:** Checkboxes are hidden. Selection is cleared. Toolbar disappears.

### Pass Criteria
- [ ] "Seleccion Multiple" button is visible in table header
- [ ] Clicking it reveals checkboxes on each row
- [ ] Selecting a checkbox updates the counter
- [ ] Exiting selection mode hides checkboxes and clears selection

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

# Section 4: Filters and Search

---

## Scenario A-051: Filter by category dropdown
**Priority:** Critical
**Feature:** Filters
**Preconditions:** User is logged in. Expenses with different categories exist.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads with all expenses. Filter form is visible (on desktop).
2. Click the category dropdown (labeled "Todas las categorias")
   - **Expected:** Dropdown opens showing all category names sorted alphabetically, plus the blank option "Todas las categorias"
3. Select a specific category (e.g., "Supermercado" or any available category)
   - **Expected:** Category is selected in the dropdown
4. Click the "Filtrar" button (teal button)
   - **Expected:** Page reloads. URL now includes `?category={selected_category}`. Only expenses belonging to the selected category are displayed. The summary stats reflect only the filtered expenses.
5. Verify the expense rows
   - **Expected:** Every visible expense row shows the selected category name in the "Categoria" column

### Pass Criteria
- [ ] Category dropdown lists all categories alphabetically
- [ ] After filtering, URL includes category parameter
- [ ] Only expenses with the selected category are shown
- [ ] Summary stats update to reflect filtered data
- [ ] All visible expenses belong to the selected category

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-052: Filter by bank dropdown
**Priority:** Critical
**Feature:** Filters
**Preconditions:** User is logged in. Expenses from different banks exist.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads. Bank dropdown is visible.
2. Click the bank dropdown (labeled "Todos los bancos")
   - **Expected:** Dropdown opens showing all active bank names sorted alphabetically, plus "Todos los bancos" as the blank option
3. Select a specific bank name
   - **Expected:** Bank is selected
4. Click the "Filtrar" button
   - **Expected:** Page reloads. URL includes `?bank={selected_bank}`. Only expenses from that bank are shown.
5. Switch to expanded view mode if needed and verify the "Banco" column
   - **Expected:** Every visible expense shows the selected bank name

### Pass Criteria
- [ ] Bank dropdown lists available banks alphabetically
- [ ] After filtering, only expenses from selected bank are shown
- [ ] URL includes bank parameter
- [ ] Summary stats reflect filtered results

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-053: Filter by date range (start and end dates)
**Priority:** Critical
**Feature:** Filters
**Preconditions:** User is logged in. Expenses from different dates exist.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads. Date fields are visible in the filter form.
2. Enter a start date in the "Fecha inicio" date field (e.g., first day of current month)
   - **Expected:** Date picker accepts the date
3. Enter an end date in the "Fecha fin" date field (e.g., last day of current month)
   - **Expected:** Date picker accepts the date
4. Click the "Filtrar" button
   - **Expected:** Page reloads. URL includes `?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD`. Only expenses with transaction dates within the specified range (inclusive) are displayed.
5. Verify expense dates
   - **Expected:** Every visible expense has a transaction date within the start-end range

### Pass Criteria
- [ ] Date range fields accept dates
- [ ] After filtering, URL includes start_date and end_date parameters
- [ ] Only expenses within the date range are shown
- [ ] All visible expense dates fall within the specified range

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-054: Combined filters (category + bank + date range)
**Priority:** Critical
**Feature:** Filters
**Preconditions:** User is logged in. Expenses from multiple categories, banks, and dates exist.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads
2. Select a category from the category dropdown
   - **Expected:** Category is selected
3. Select a bank from the bank dropdown
   - **Expected:** Bank is selected
4. Enter a start date and end date
   - **Expected:** Dates are entered
5. Click the "Filtrar" button
   - **Expected:** Page reloads. URL includes all four parameters: `?category=X&bank=Y&start_date=Z&end_date=W`. Only expenses matching ALL criteria are displayed. If no expenses match all criteria, an empty list is shown (not an error).
6. Verify the results
   - **Expected:** Every visible expense matches the selected category AND bank AND falls within the date range

### Pass Criteria
- [ ] All four filter parameters appear in the URL
- [ ] Results match ALL filter criteria simultaneously
- [ ] Summary stats reflect the combined filter results
- [ ] If no matches, empty state is shown gracefully

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-055: Clear filters button resets all
**Priority:** Critical
**Feature:** Filters
**Preconditions:** User is logged in. Filters are currently applied.

### Steps
1. Navigate to `http://localhost:3000/expenses?category=Supermercado&bank=BAC&start_date=2026-01-01&end_date=2026-03-31`
   - **Expected:** Filtered expense list loads
2. Verify filters are active
   - **Expected:** Category dropdown shows "Supermercado", bank dropdown shows "BAC", dates are filled in
3. Click the "Limpiar" button (slate-colored, next to the "Filtrar" button)
   - **Expected:** Browser navigates to `http://localhost:3000/expenses` (no query parameters). All filters are cleared. The full unfiltered expense list is displayed.
4. Verify all filter fields are reset
   - **Expected:** Category dropdown shows "Todas las categorias". Bank dropdown shows "Todos los bancos". Date fields are empty.

### Pass Criteria
- [ ] "Limpiar" button navigates to `/expenses` without parameters
- [ ] All filter dropdowns reset to their default/blank values
- [ ] Date fields are cleared
- [ ] Full unfiltered list is displayed

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-056: Filter persistence across page loads (session storage)
**Priority:** High
**Feature:** Filters / Persistence
**Preconditions:** User is logged in. Desktop viewport.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads. The filter form has `data-filter-persistence-target="filterForm"` and the container has `data-filter-persistence-auto-save-value="true"` and `data-filter-persistence-auto-restore-value="true"`.
2. Select a category from the dropdown
   - **Expected:** Category selected
3. Click "Filtrar"
   - **Expected:** Filtered results load. The filter-persistence Stimulus controller saves the filter state to session storage.
4. Navigate away to another page (e.g., `http://localhost:3000/expenses/dashboard`)
   - **Expected:** Dashboard loads
5. Navigate back to `http://localhost:3000/expenses`
   - **Expected:** The filter-persistence controller restores the saved filters. The category dropdown should show the previously selected category. Results should be filtered accordingly.
6. Open DevTools > Application > Session Storage
   - **Expected:** A session storage key exists containing the saved filter state

### Pass Criteria
- [ ] Filter state is saved to session storage after applying filters
- [ ] Navigating away and returning restores the filter state
- [ ] The category dropdown shows the previously selected value
- [ ] Results match the restored filters

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-057: Empty state when no expenses match filters
**Priority:** High
**Feature:** Filters / Empty State
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads
2. Apply filters that will produce zero results. For example, set a date range far in the future (e.g., start_date=2030-01-01, end_date=2030-12-31)
   - **Expected:** Filters are applied
3. Click "Filtrar"
   - **Expected:** Page reloads. The table body is empty (no expense rows). The summary shows Total: ₡0, Gastos: 0, Categorias: 0. The pagination text shows "Mostrando 0 gastos". No error page or crash occurs.

### Pass Criteria
- [ ] Page loads without errors when no results match
- [ ] Table is empty (no rows)
- [ ] Summary stats show zero values
- [ ] Pagination shows "Mostrando 0 gastos"
- [ ] No 500 error or exception

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-058: Filter description displayed when filters are active
**Priority:** Medium
**Feature:** Filters / UX
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses?period=month&filter_type=dashboard_metric`
   - **Expected:** The expense list loads. A teal-colored navigation bar appears at the top (because `filter_type=dashboard_metric`). It contains a "Volver al Dashboard" link and a filter description like "Gastos de este mes".
2. Navigate to `http://localhost:3000/expenses?category=Supermercado&bank=BAC`
   - **Expected:** The filter description reflects the active filters (e.g., "Categoria: Supermercado"). Note: the filter_description is built from period/date/category/bank params.

### Pass Criteria
- [ ] Dashboard navigation bar appears when `filter_type=dashboard_metric` is present
- [ ] Filter description text accurately describes the active filters
- [ ] "Volver al Dashboard" link navigates to the dashboard

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-059: Filter form select elements have correct options
**Priority:** Medium
**Feature:** Filters / Form
**Preconditions:** User is logged in. Categories and bank names exist.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads with filter form visible
2. Open the category dropdown and inspect its options
   - **Expected:** First option is "Todas las categorias" (blank value). Remaining options are all category names from the database, sorted alphabetically by name.
3. Open the bank dropdown and inspect its options
   - **Expected:** First option is "Todos los bancos" (blank value). Remaining options are distinct active bank names, sorted alphabetically.
4. Inspect the date fields
   - **Expected:** Two date input fields with type="date". They accept date values in YYYY-MM-DD format.

### Pass Criteria
- [ ] Category dropdown has "Todas las categorias" as first option
- [ ] Category options are sorted alphabetically
- [ ] Bank dropdown has "Todos los bancos" as first option
- [ ] Bank options are sorted alphabetically
- [ ] Date fields are type="date"

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-060: Filter with only start date (no end date)
**Priority:** Medium
**Feature:** Filters / Edge Cases
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads
2. Enter a start date but leave the end date empty
   - **Expected:** Only start_date is filled
3. Click "Filtrar"
   - **Expected:** Page reloads. URL includes `?start_date=YYYY-MM-DD`. The behavior depends on the filter service -- it may show all expenses from the start date onward, or it may ignore incomplete date ranges. The page should NOT crash or show an error.

### Pass Criteria
- [ ] Page does not crash with only start_date
- [ ] No 500 error
- [ ] Results are displayed (may be filtered or unfiltered depending on implementation)

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-061: Filter with only end date (no start date)
**Priority:** Medium
**Feature:** Filters / Edge Cases
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads
2. Leave start date empty and enter an end date only
   - **Expected:** Only end_date is filled
3. Click "Filtrar"
   - **Expected:** Page reloads. URL includes `?end_date=YYYY-MM-DD`. Page does NOT crash.

### Pass Criteria
- [ ] Page does not crash with only end_date
- [ ] No 500 error
- [ ] Results are displayed

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-062: Filter by period parameter from dashboard
**Priority:** High
**Feature:** Filters / Dashboard Integration
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses?period=month&filter_type=dashboard_metric`
   - **Expected:** Page loads showing only expenses from the current month. A period label appears in the table header area: "Periodo: Este Mes".
2. Navigate to `http://localhost:3000/expenses?period=week&filter_type=dashboard_metric`
   - **Expected:** Page loads showing only expenses from the current week. Period label: "Periodo: Esta Semana".
3. Navigate to `http://localhost:3000/expenses?period=day&filter_type=dashboard_metric`
   - **Expected:** Page loads showing only expenses from today. Period label: "Periodo: Hoy".
4. Navigate to `http://localhost:3000/expenses?period=year&filter_type=dashboard_metric`
   - **Expected:** Page loads showing only expenses from the current year. Period label: "Periodo: Este Ano".

### Pass Criteria
- [ ] `period=month` shows current month expenses only
- [ ] `period=week` shows current week expenses only
- [ ] `period=day` shows today's expenses only
- [ ] `period=year` shows current year expenses only
- [ ] Period label displays correctly in each case

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-063: Filter form submit uses GET method
**Priority:** Medium
**Feature:** Filters / Technical
**Preconditions:** User is logged in. Desktop viewport.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads
2. Open DevTools > Network tab
   - **Expected:** DevTools is open and recording
3. Select a category and click "Filtrar"
   - **Expected:** A GET request is made to `/expenses?category=X`. Not a POST request. The filter parameters are visible in the URL, making the filtered view bookmarkable and shareable.

### Pass Criteria
- [ ] Filter form submits as GET (not POST)
- [ ] Filter parameters appear in the URL
- [ ] The filtered URL is bookmarkable

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-064: "Limpiar" button links to clean expenses URL
**Priority:** Medium
**Feature:** Filters
**Preconditions:** User is logged in.

### Steps
1. Navigate to `http://localhost:3000/expenses?category=Supermercado`
   - **Expected:** Filtered list loads
2. Inspect the "Limpiar" button/link with DevTools
   - **Expected:** The `href` attribute points to `/expenses` with no query parameters. It is a standard `<a>` link, not a form submission.
3. Click "Limpiar"
   - **Expected:** Navigates to `/expenses` (clean URL)

### Pass Criteria
- [ ] "Limpiar" is an `<a>` link with href="/expenses"
- [ ] Clicking it removes all filter parameters from the URL

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

## Scenario A-065: Filter styling matches Financial Confidence palette
**Priority:** Medium
**Feature:** Filters / Design
**Preconditions:** User is logged in. Desktop viewport.

### Steps
1. Navigate to `http://localhost:3000/expenses`
   - **Expected:** Expense list loads with filter form visible
2. Inspect the "Filtrar" submit button
   - **Expected:** Button has classes `bg-teal-700 hover:bg-teal-800 text-white rounded-lg shadow-sm`. No blue colors.
3. Inspect the "Limpiar" button
   - **Expected:** Button has classes `bg-slate-200 hover:bg-slate-300 text-slate-700 rounded-lg`. Secondary button style.
4. Click into a filter select dropdown to check focus state
   - **Expected:** Focus ring uses teal colors (`focus:border-teal-500 focus:ring-teal-500`). No blue focus ring.

### Pass Criteria
- [ ] "Filtrar" button uses teal-700 background
- [ ] "Limpiar" button uses slate-200 background
- [ ] Focus states use teal-500 ring
- [ ] No blue colors used in filter form

### If Failed
- Document the URL where failure occurred
- Screenshot the page state
- Note the exact step number that failed
- Record any error messages or unexpected behavior

---

# Appendix: Scenario Index

| ID | Title | Priority | Section |
|----|-------|----------|---------|
| A-001 | Login with valid credentials | Critical | Authentication |
| A-002 | Login with invalid email | Critical | Authentication |
| A-003 | Login with valid email but wrong password | Critical | Authentication |
| A-004 | Login with empty email and empty password | High | Authentication |
| A-005 | Login with valid email but empty password | High | Authentication |
| A-006 | Logout redirects to login page | Critical | Authentication |
| A-007 | Access protected page without authentication | Critical | Authentication |
| A-008 | Redirect back to original URL after login | High | Authentication |
| A-009 | Already logged in user visits login page | Medium | Authentication |
| A-010 | Login form preserves email on failed attempt | Medium | Authentication |
| A-011 | CSRF token present on login form | High | Authentication |
| A-012 | Rate limiting blocks excessive login attempts | High | Authentication |
| A-013 | GET logout also destroys session | Medium | Authentication |
| A-014 | Login form visual design matches Financial Confidence palette | Medium | Authentication |
| A-015 | Session fixation prevention | High | Authentication |
| A-016 | View expense list (index page) | Critical | Expense CRUD |
| A-017 | View single expense (show page) | Critical | Expense CRUD |
| A-018 | Create new expense with all valid fields | Critical | Expense CRUD |
| A-019 | Create expense with missing required fields (amount blank) | Critical | Expense CRUD |
| A-020 | Create expense with zero amount | High | Expense CRUD |
| A-021 | Create expense with negative amount | High | Expense CRUD |
| A-022 | Create expense with missing transaction date | High | Expense CRUD |
| A-023 | Create expense defaults to CRC currency | Medium | Expense CRUD |
| A-024 | Edit existing expense | Critical | Expense CRUD |
| A-025 | Edit expense with invalid data triggers validation | High | Expense CRUD |
| A-026 | Delete expense (soft delete with undo) | Critical | Expense CRUD |
| A-027 | Delete expense - cancel confirmation dialog | Medium | Expense CRUD |
| A-028 | Duplicate expense | High | Expense CRUD |
| A-029 | Access non-existent expense | High | Expense CRUD |
| A-030 | New expense form has correct field types | Medium | Expense CRUD |
| A-031 | Edit form submit button text differs from new form | Low | Expense CRUD |
| A-032 | Show page action buttons link correctly | Medium | Expense CRUD |
| A-033 | Show page displays ML confidence badge | Medium | Expense CRUD |
| A-034 | Show page metadata section displays timestamps | Medium | Expense CRUD |
| A-035 | Create expense with all fields blank | Medium | Expense CRUD |
| A-036 | Default list shows up to 50 expenses per page | Critical | Expense List |
| A-037 | Pagination controls navigate between pages | Critical | Expense List |
| A-038 | View toggle between compact and expanded mode | High | Expense List |
| A-039 | View toggle persists across page loads | Medium | Expense List |
| A-040 | Mobile card view visible at < 768px | Critical | Expense List |
| A-041 | Desktop table visible at >= 768px | High | Expense List |
| A-042 | Collapsible filters on mobile | High | Expense List |
| A-043 | Active filter count badge on mobile | Medium | Expense List |
| A-044 | Collapsible category summary on mobile | Medium | Expense List |
| A-045 | Mobile card displays correct expense data | High | Expense List |
| A-046 | Mobile card expand actions on tap | High | Expense List |
| A-047 | Mobile pagination | High | Expense List |
| A-048 | Summary statistics update with filters | High | Expense List |
| A-049 | Category summary hides when category filter active | Medium | Expense List |
| A-050 | Batch selection mode toggle (desktop) | Medium | Expense List |
| A-051 | Filter by category dropdown | Critical | Filters |
| A-052 | Filter by bank dropdown | Critical | Filters |
| A-053 | Filter by date range | Critical | Filters |
| A-054 | Combined filters (category + bank + date range) | Critical | Filters |
| A-055 | Clear filters button resets all | Critical | Filters |
| A-056 | Filter persistence across page loads | High | Filters |
| A-057 | Empty state when no expenses match filters | High | Filters |
| A-058 | Filter description displayed when filters active | Medium | Filters |
| A-059 | Filter form select elements have correct options | Medium | Filters |
| A-060 | Filter with only start date (no end date) | Medium | Filters |
| A-061 | Filter with only end date (no start date) | Medium | Filters |
| A-062 | Filter by period parameter from dashboard | High | Filters |
| A-063 | Filter form submit uses GET method | Medium | Filters |
| A-064 | "Limpiar" button links to clean expenses URL | Medium | Filters |
| A-065 | Filter styling matches Financial Confidence palette | Medium | Filters |

---

**Total Scenarios:** 65
**Critical:** 18 | **High:** 26 | **Medium:** 20 | **Low:** 1
