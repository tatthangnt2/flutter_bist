# Commands

Script JSON `schema: 4`. Builders have the same names in TypeScript (`import … from 'flutter_bist'`, options in an object:
`tap({ text: 'Send' })`) and Dart (`package:flutter_bist/model.dart`, named parameters: `tap(text: 'Send')`).

## Script tree

| Node | Meaning |
|---|---|
| `TestGroup` | Children are independent: a failing child doesn't stop the others. `pre` / `after` run before / after **each** child. A script file is one root group whose `id` equals the file name. |
| `TestSequence` | Children run in order (they share `{{now}}` and variables); after a failure the rest is skipped. Running one child alone runs the children before it first. `pre` / `after` run once. |
| `TestUnit` | One test: `steps`, plus its own `pre` / `after`. |

Every node: `name`, `id` (unique, `[A-Za-z0-9._-]`, for `runTest` and `BIST_RUN`), `minVersion` / `maxVersion`
(`1.0.0+10`, outside the range → "Not for this version"), `manual` (reason it can't be automated → "Needs a tester",
not a failure), `writes` (creates / changes data → refused on production servers).

## Finding widgets

Every finding command accepts these properties; the widget must match **all** of them:

| Property | |
|---|---|
| `text` | Visible text, input label / hint, tooltip, Semantics label (plus what `BistProvider.textsOf` returns) |
| `match` | How `text` / `value` compare: `exact` (default), `contains`, `regex` |
| `id` | `ValueKey` of the widget (or an ancestor close to the text) |
| `type` | `button`, `input`, `text`, `image` |
| `icon` | Material icon name for icon-only buttons: `add`, `close`, `delete`, `edit`, `logout`, `menu`, `more_vert`, `search`, `send`, `settings`, … |
| `route` | Only inside the screen with this route |
| `inside` | Only inside a block (card, list row, dialog) that contains this exact text |

The runner waits up to `timeout` (default 5000 ms), scrolls the largest list when the widget isn't on screen, and
closes the keyboard when it covers the widget.

Options of every step: `timeout` (ms), `note` (shown in reports), `shot` (screenshot even when it passes), `onError`
(actions to run when the step fails – if they pass, the step counts as passed; one level only).

## Tap, input

| Command | |
|---|---|
| `tap(find)` / `tapLong(find)` / `tapDouble(find)` | Tap / long press (700 ms) / double tap |
| `input(value, find)` | Replace the text of an input (`''` clears it). `text` = label / hint, or the text right above / before the input. No finding property → the focused input. Dropdowns: picks the item `value`. |
| `inputDate(value, find)` / `inputDateRange(start, end, find)` | Date fields (`dd/MM/yyyy`, or `{{date:+1}}`) – app-specific widgets need `BistProvider.inputDate`; a plain text field gets the text typed |
| `pickFile(url, {name})` | The next file / image picker returns this file (needs provider support) |

## Checks

| Command | |
|---|---|
| `expect(find, state)` | Waits until shown. Only `route` → waits until that screen is open. |
| `notExpect(find, state)` | Waits until gone. With state conditions → the widget is there but doesn't meet them. |

State conditions: `enabled: true`, input `value` (uses `match`), `focused`, `obscured`, `maxLength`, `count` (number of
matching widgets on screen), `checked` (checkbox / switch / radio), `selected` (tab / chip / list item).

## Navigation, waiting

| Command | |
|---|---|
| `back()` | Close the top dialog / screen |
| `swipe(direction, find?)` | `up` = see what's below, `down` = pull down; inside the scrollable of the found widget, else the largest |
| `wait(ms)` | Only when there is nothing to expect |
| `runTest(id)` | Run another node (e.g. login) inline, up to 3 levels deep |
| `nav(path)` | Open a route directly |
| `server(name)` | Switch server (provider) |

## Loops, data, variables

| Command | |
|---|---|
| `loop(from, to, steps)` | `{{i}}` = from..to (max 200 iterations) |
| `loopWhile(condition, steps, {max})` | While `expect(...)` / `notExpect(...)` holds (default max 20) |
| `randInt(name, min, max, {format})` / `randText(name, minLength, maxLength, {chars, format})` | Random value into `{{name}}`; `format: 'Order {value}'` |
| `getText(name, find)` | Text of a widget / input into `{{name}}` |
| `getLog(name, tag, {path, level})` | Value from the newest app log into `{{name}}` |
| `getEnv(name, key)` | Environment value into `{{name}}` |

Placeholders in every string: `{{now}}` (run start `HHmmss`, unique text to find data the run created), `{{date}}`,
`{{date:+1}}`, `{{i}}`, `{{env:key}}`, `{{tc:group.field}}` (test data), `{{name}}` (variables). Secret-looking keys and
paths (token, password, cookie, authorization…) are refused.

## Print, ask the tester, developer tools

| Command | |
|---|---|
| `log(message)` | Into the report and the `BIST|` console line |
| `toast(message)` | Short message on screen |
| `confirm(message, {yes, no})` | Tester answers; "no" fails the step |
| `ask(name, message, {initial, hint})` | Tester types a value (e.g. an OTP) into `{{name}}` |
| `expectLog(tag, {level})` | Waits for a new app log |
| `mockApi(api, {status, body, delay, times, method})` | Fake response for requests whose URL contains `api` |
| `offline({on})` | Every request fails like no network |
| `resetApi()` | Remove mocks; everything is removed anyway when the run ends |
