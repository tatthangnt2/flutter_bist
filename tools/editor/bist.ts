/**
 * BIST – write, check, bundle and export test scripts in TypeScript. A single file:
 * - **Script-writing library**: `import { TestGroup, TestUnit, tap, expect, … } from 'flutter_bist'` (resolves to this file / `bist.mjs`).
 * - **Tools**: `transpile`, `typecheck`, `bundleMjs` (shared by `editor.html` and the command line).
 * - **Editor page**: `npm run build` (in tools/editor) embeds this file into `bin/editor.html` – opens with a double click.
 * - **Export from the command line**: `node bin/bist.mjs <scripts dir> <JSON dir> [--mjs <dir>]`:
 *   `<id>.ts` → type check → standalone `<id>.mjs` (library embedded) → `node <id>.mjs` prints JSON → validate → `<id>.json` → app.
 *   The app only receives JSON (it never runs downloaded code). Needs the `typescript` package (installed here or globally).
 *
 * The JSON format (schema 4) is identical to the Dart model `package:flutter_bist/model.dart` – the in-app runner reads it with `TestGroup.fromJson`.
 * When changing commands / validation rules here, change the Dart model too. After editing this file run `npm run build` to regenerate `bin/bist.mjs`, `bin/bist.d.ts`.
 *
 * ```ts
 * import { TestGroup, TestUnit, WidgetType, input, tap, expect, printJson } from 'flutter_bist';
 *
 * const login = (user: string, pass: string) => [
 *   input(user, { text: 'Username' }),
 *   input(pass, { text: 'Password' }),
 *   tap({ text: 'SIGN IN', type: WidgetType.button }),
 * ];
 *
 * printJson(TestGroup({ id: 'login', name: 'Login', cases: [
 *   TestUnit({ name: 'Missing fields', steps: [...login('', ''), expect({ text: 'Please enter your username and password.' })] }),
 * ] }));
 * ```
 */

// Runs both in node and in the browser – no dependency on Node / DOM types
declare const console: { log(...args: unknown[]): void; error(...args: unknown[]): void };
declare const process: any;
declare const btoa: ((s: string) => string) | undefined;

/** JSON format version – same as `kTestScriptSchema` in the Dart model */
export const SCHEMA = 4;

// ==== Types ====

export const WidgetType = { button: 'button', input: 'input', text: 'text', image: 'image' } as const;
export type WidgetType = (typeof WidgetType)[keyof typeof WidgetType];

export const LogLevel = { debug: 'debug', info: 'info', warn: 'warn', error: 'error', damage: 'damage', success: 'success' } as const;
export type LogLevel = (typeof LogLevel)[keyof typeof LogLevel];

export const SwipeDirection = { up: 'up', down: 'down', left: 'left', right: 'right' } as const;

/** How `text` / `value` is compared: exact (default), contains, regular expression */
export const TextMatch = { exact: 'exact', contains: 'contains', regex: 'regex' } as const;
export type TextMatch = (typeof TextMatch)[keyof typeof TextMatch];

/** HTTP method for mockApi */
export type HttpMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
const HTTP_METHODS = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];
export type SwipeDirection = (typeof SwipeDirection)[keyof typeof SwipeDirection];

/** One action (step) – the JSON sent to the app */
export interface TestAction {
  readonly cmd: string;
  readonly [key: string]: unknown;
}

/** Widget finder: the widget must match **all** given properties */
export interface Find {
  /** Text on screen (including input labels / hints, tooltips, Semantics labels) – exact match */
  text?: string;
  /** The widget's `Key` (`ValueKey('login.submit')`) */
  id?: string;
  /** Widget kind */
  type?: WidgetType;
  /** Material icon name of an icon-only button (`add`, `logout`, …) */
  icon?: string;
  /** Only search on the screen with this route */
  route?: string;
  /** Only search inside a block (card, row, dialog) that contains this text */
  inside?: string;
  /** How `text` (and expect's `value`) is compared: `exact` (default), `contains`, `regex` regular expression */
  match?: TextMatch;
}

/** Common options */
export interface Opt {
  /** Timeout (ms), default 5000 */
  timeout?: number;
  /** Note shown in the report */
  note?: string;
  /** Take a screenshot at this step (failed steps always take one) */
  shot?: boolean;
  /** Actions to run when the step fails; if they all pass, the run continues (one level only) */
  onError?: TestAction[];
}

/** Extra conditions for expect / notExpect */
export interface FieldState {
  /** Button / field is enabled */
  enabled?: boolean;
  /** Current text in the input (after the app's filtering / trimming) */
  value?: string;
  /** Field has focus */
  focused?: boolean;
  /** Field hides its characters (password) */
  obscured?: boolean;
  /** Field's max length */
  maxLength?: number;
  /** Number of matching widgets on screen (e.g. a 20-row list); notExpect: any other number */
  count?: number;
  /** Checkbox / switch / radio next to the widget is on */
  checked?: boolean;
  /** Tab / chip / list item is selected */
  selected?: boolean;
}

/** Properties shared by every node in the tree */
export interface CaseProps {
  name: string;
  /** For calling it again (`runTest(id)`) and running it alone (`BIST_RUN=<id>`); unique across all files */
  id?: string;
  /** App version range `1.0.0+10` (inclusive) */
  minVersion?: string;
  maxVersion?: string;
  /** Case that can't be automated (the reason) – result is "Needs tester" */
  manual?: string;
  /** Creates / changes data – only runs on non-Production servers */
  writes?: boolean;
  /** Setup / cleanup (TestGroup: around each child; TestSequence: once) */
  pre?: TestAction[];
  after?: TestAction[];
}

export interface TestUnitNode extends CaseProps {
  readonly type: 'unit';
  steps: TestAction[];
}

export interface TestGroupNode extends CaseProps {
  readonly type: 'group' | 'sequence';
  cases: TestCaseNode[];
}

export type TestCaseNode = TestUnitNode | TestGroupNode;

// ==== Command table (same as `_fields` in the Dart model) ====

const OPT = ['timeout', 'note', 'shot', 'onError'];
const FIND_KEYS = ['text', 'id', 'type', 'icon', 'route', 'inside', 'match'];
const FIELD_STATE = ['enabled', 'value', 'focused', 'obscured', 'maxLength', 'count', 'checked', 'selected'];
const RESERVED_VARS = ['now', 'date', 'tc', 'i'];
const STRING_KEYS = [
  'text', 'id', 'icon', 'route', 'inside', 'note', 'value', 'script', 'path', 'name', 'tag', 'start', 'end',
  'chars', 'format', 'url', 'key', 'message', 'yes', 'no', 'initial', 'hint', 'api',
];

/** Secret-looking keys / paths – getEnv, getLog refuse them */
export const SECRET_PATTERN = /token|password|passwd|secret|crypto|apikey|api_key|private|cookie|authorization|header|credential|mat_?khau/i;

/** Placeholders replaced at run time: `{{tc:group.field}}`, `{{env:key}}`, `{{date:+1}}`, `{{now}}`, `{{i}}`, `{{variable}}` */
export const VALUE_PATTERN = /\{\{(tc:[^{}]+|env:[^{}]+|date(?::[+-]\d+)?|[A-Za-z_][A-Za-z0-9_]*)\}\}/g;

const FIELDS: Record<string, { main: string[]; extra: string[]; find: boolean }> = {
  // tap, input
  tap: { main: [], extra: [], find: true },
  tapLong: { main: [], extra: [], find: true },
  tapDouble: { main: [], extra: [], find: true },
  input: { main: ['value'], extra: [], find: true },
  inputDate: { main: ['value'], extra: [], find: true },
  inputDateRange: { main: ['start', 'end'], extra: [], find: true },
  pickFile: { main: ['url'], extra: ['name'], find: false },
  // check
  expect: { main: [], extra: FIELD_STATE, find: true },
  notExpect: { main: [], extra: FIELD_STATE, find: true },
  // navigate, scroll, wait
  back: { main: [], extra: [], find: false },
  swipe: { main: ['direction'], extra: [], find: true },
  wait: { main: ['ms'], extra: [], find: false },
  runTest: { main: ['script'], extra: [], find: false },
  // loops, generated data
  loop: { main: ['from', 'to', 'steps'], extra: [], find: false },
  loopWhile: { main: ['condition', 'steps'], extra: ['max'], find: false },
  randInt: { main: ['name', 'min', 'max'], extra: ['format'], find: false },
  randText: { main: ['name', 'minLength', 'maxLength'], extra: ['chars', 'format'], find: false },
  // read values
  getText: { main: ['name'], extra: [], find: true },
  getLog: { main: ['name', 'tag'], extra: ['path', 'level'], find: false },
  getEnv: { main: ['name', 'key'], extra: [], find: false },
  // print, notify, ask the tester
  log: { main: ['message'], extra: [], find: false },
  toast: { main: ['message'], extra: [], find: false },
  confirm: { main: ['message'], extra: ['yes', 'no'], find: false },
  ask: { main: ['name', 'message'], extra: ['initial', 'hint'], find: false },
  // for developers
  nav: { main: ['path'], extra: [], find: false },
  server: { main: ['name'], extra: [], find: false },
  expectLog: { main: ['tag'], extra: ['level'], find: false },
  // mock server (removed automatically when the run ends)
  mockApi: { main: ['api'], extra: ['status', 'body', 'delay', 'times', 'method'], find: false },
  offline: { main: [], extra: ['on'], find: false },
  resetApi: { main: [], extra: [], find: false },
};

export const COMMANDS = Object.keys(FIELDS);

// ==== Validation ====

type Json = Record<string, unknown>;

const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const isRatioOk = (v: unknown) => typeof v === 'string';

function validateStep(raw: unknown, p: string, nested: boolean, e: string[]): void {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw) || !((raw as Json).cmd as string in FIELDS)) {
    e.push(`${p}: unknown command – available: ${COMMANDS.join(', ')}`);
    return;
  }
  const st = raw as Json;
  const cmd = st.cmd as string;
  const f = FIELDS[cmd];
  const allowed = [...f.main, ...f.extra, ...(f.find ? FIND_KEYS : []), ...OPT];
  for (const k of Object.keys(st)) {
    if (k !== 'cmd' && !allowed.includes(k)) e.push(`${p}: ${cmd} has no parameter "${k}" (allowed: ${allowed.join(', ')})`);
  }
  for (const k of f.main) if (st[k] === undefined || st[k] === null) e.push(`${p}: ${cmd} is missing "${k}"`);
  for (const k of STRING_KEYS) {
    const v = st[k];
    if (v !== undefined && v !== null && typeof v !== 'string') e.push(`${p}: ${k} must be a string`);
    if (v === '' && k !== 'value') e.push(`${p}: ${k} must not be empty`);
  }
  const hasTarget = ['text', 'id', 'icon', 'type'].some((k) => st[k] != null);
  if (['tap', 'tapLong', 'tapDouble'].includes(cmd) && !hasTarget) e.push(`${p}: ${cmd} needs at least one of text, id, icon, type`);
  if ((cmd === 'expect' || cmd === 'notExpect') && !hasTarget && st.route == null) e.push(`${p}: ${cmd} needs at least one of ${FIND_KEYS.join(', ')}`);
  for (const k of FIELD_STATE) {
    if (cmd.endsWith('xpect') && st[k] != null && !hasTarget) e.push(`${p}: ${k} needs a widget to check (text, id, icon, type)`);
  }
  for (const k of ['focused', 'obscured', 'enabled', 'shot', 'checked', 'selected', 'on']) if (st[k] != null && typeof st[k] !== 'boolean') e.push(`${p}: ${k} must be true | false`);
  if (st.match != null) {
    if (!Object.values(TextMatch).includes(st.match as TextMatch)) e.push(`${p}: match must be ${Object.values(TextMatch).join(' | ')}`);
    if (st.text == null && st.value == null) e.push(`${p}: match needs text or value`);
    if (st.match === 'regex') {
      for (const k of ['text', 'value']) {
        const v = st[k];
        if (typeof v === 'string' && !v.includes('{{')) { try { new RegExp(v); } catch { e.push(`${p}: ${k} is not a valid regex`); } }
      }
    }
  }
  if (st.count != null && !(isInt(st.count) && st.count >= 0)) e.push(`${p}: count must be an integer ≥ 0`);
  if (cmd === 'mockApi') {
    if (st.status != null && !(isInt(st.status) && st.status >= 100 && st.status <= 599)) e.push(`${p}: status must be 100..599`);
    if (st.delay != null && !(isInt(st.delay) && st.delay >= 0)) e.push(`${p}: delay must be a number of ms ≥ 0`);
    if (st.times != null && !(isInt(st.times) && st.times >= 1)) e.push(`${p}: times must be ≥ 1`);
    if (st.method != null && !HTTP_METHODS.includes(st.method as string)) e.push(`${p}: method must be ${HTTP_METHODS.join(' | ')}`);
    if (st.body != null && typeof st.body !== 'string') e.push(`${p}: body must be a string (JSON text)`);
  }
  for (const k of ['from', 'to', 'min', 'max', 'minLength', 'maxLength']) if (st[k] != null && !isInt(st[k])) e.push(`${p}: ${k} must be an integer`);
  const mx = st.maxLength, mn = st.minLength;
  if ((isInt(mx) && mx < 0) || (isInt(mn) && (mn < 0 || (isInt(mx) && mn > mx)))) e.push(`${p}: minLength ≤ maxLength, ≥ 0`);
  if (cmd === 'randInt' && isInt(st.min) && isInt(st.max) && st.min > st.max) e.push(`${p}: min ≤ max`);
  if (cmd === 'loopWhile' && isInt(st.max) && st.max < 1) e.push(`${p}: max ≥ 1`);
  if (cmd === 'loop' && isInt(st.from) && isInt(st.to) && Math.abs(st.to - st.from) > 200) e.push(`${p}: loop allows at most 200 iterations`);
  for (const k of ['key', 'path']) {
    if ((cmd === 'getEnv' || cmd === 'getLog') && typeof st[k] === 'string' && SECRET_PATTERN.test(st[k] as string)) e.push(`${p}: secret values are not allowed (${k} "${st[k]}")`);
  }
  if (['randInt', 'randText', 'getText', 'getLog', 'getEnv', 'ask'].includes(cmd)) {
    const n = st.name;
    if (typeof n === 'string' && (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(n) || RESERVED_VARS.includes(n))) {
      e.push(`${p}: variable name "${n}" may only contain letters, digits, _ and must not be ${RESERVED_VARS.join(', ')}`);
    }
  }
  if (cmd === 'pickFile' && typeof st.url === 'string' && !/^(https:\/\/|\{\{)/.test(st.url)) e.push(`${p}: url must start with https://`);
  if (st.type != null && !Object.values(WidgetType).includes(st.type as WidgetType)) e.push(`${p}: type must be ${Object.values(WidgetType).join(' | ')}`);
  if (st.direction != null && !Object.values(SwipeDirection).includes(st.direction as SwipeDirection)) e.push(`${p}: swipe direction must be ${Object.values(SwipeDirection).join(' | ')}`);
  if (st.level != null && !Object.values(LogLevel).includes(st.level as LogLevel)) e.push(`${p}: level must be ${Object.values(LogLevel).join(' | ')}`);
  if (st.timeout != null && !(isInt(st.timeout) && st.timeout > 0)) e.push(`${p}: timeout must be a number of ms > 0`);
  if (cmd === 'wait' && !(isInt(st.ms) && st.ms >= 0)) e.push(`${p}: wait needs a number of ms ≥ 0`);
  if (cmd === 'loop' || cmd === 'loopWhile') {
    const steps = st.steps;
    if (!Array.isArray(steps) || !steps.length) e.push(`${p}: ${cmd} needs steps (at least 1 action)`);
    else steps.forEach((s, j) => validateStep(s, `${p} steps[${j + 1}]`, false, e));
  }
  if (cmd === 'loopWhile') {
    const c = st.condition as Json | undefined;
    if (!c || typeof c !== 'object' || (c.cmd !== 'expect' && c.cmd !== 'notExpect')) e.push(`${p}: loopWhile needs a condition: expect(...) or notExpect(...)`);
    else validateStep(c, `${p} condition`, true, e);
  }
  const list = st.onError;
  if (list != null) {
    if (nested) e.push(`${p}: commands inside onError cannot have their own onError (one level only)`);
    else if (!Array.isArray(list) || !list.length) e.push(`${p}: onError must be a list of commands, e.g. [nav('login')]`);
    else list.forEach((s, j) => validateStep(s, `${p} onError[${j + 1}]`, true, e));
  }
  void isRatioOk;
}

const VERSION = /^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$/;

function validateCase(raw: unknown, p: string, ids: Set<string>, e: string[], root = false): void {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    e.push(`${p}: must be a TestUnit / TestGroup / TestSequence`);
    return;
  }
  const c = raw as Json;
  const where = typeof c.name === 'string' ? `${p} "${c.name}"` : p;
  if (!['unit', 'group', 'sequence'].includes(c.type as string)) e.push(`${where}: type must be unit | group | sequence`);
  if (typeof c.name !== 'string' || !c.name.trim()) e.push(`${where}: name is required`);
  if (c.id != null) {
    if (typeof c.id !== 'string' || !/^[A-Za-z0-9._-]+$/.test(c.id)) e.push(`${where}: id may only contain letters, digits, . _ -`);
    if (ids.has(String(c.id))) e.push(`${where}: id "${c.id}" is duplicated`);
    ids.add(String(c.id));
  } else if (root) e.push(`${where}: the root needs an id (same as the file name)`);
  for (const k of ['minVersion', 'maxVersion']) if (c[k] != null && (typeof c[k] !== 'string' || !VERSION.test(c[k] as string))) e.push(`${where}: ${k} must look like 1.0.0+10`);
  if (c.manual != null && typeof c.manual !== 'string') e.push(`${where}: manual must be a string (the reason)`);
  if (c.writes != null && typeof c.writes !== 'boolean') e.push(`${where}: writes must be true | false`);
  const allowed = ['type', 'id', 'name', 'minVersion', 'maxVersion', 'manual', 'writes', 'pre', 'after', ...(root ? ['schema'] : []), c.type === 'unit' ? 'steps' : 'cases'];
  for (const k of Object.keys(c)) if (!allowed.includes(k)) e.push(`${where}: unknown field "${k}"`);
  const actions = (k: string, required = false) => {
    const list = c[k];
    if (list == null) {
      if (required && c.manual == null) e.push(`${where}: ${k} needs at least 1 action`);
      return;
    }
    if (!Array.isArray(list)) return void e.push(`${where}: ${k} must be a list of actions`);
    if (required && !list.length && c.manual == null) e.push(`${where}: ${k} needs at least 1 action`);
    list.forEach((s, i) => validateStep(s, `${where} ${k}[${i + 1}]`, false, e));
  };
  actions('pre');
  actions('after');
  if (c.type === 'unit') actions('steps', true);
  else if (c.type === 'group' || c.type === 'sequence') {
    const cases = c.cases;
    if (!Array.isArray(cases) || !cases.length) e.push(`${where}: cases needs at least 1 item`);
    else cases.forEach((x, i) => validateCase(x, `${p}.${i + 1}`.replace('Root.', ''), ids, e));
  }
}

/** Validates a script file's JSON (the root has `schema`), returns the list of errors. [fileName]: check the root id matches the file name. */
export function validate(json: Json, fileName?: string): string[] {
  const e: string[] = [];
  if (json.schema !== SCHEMA) e.push(`schema must be ${SCHEMA}`);
  if (json.type !== 'group' && json.type !== 'sequence') e.push('the root must be a TestGroup / TestSequence');
  if (fileName) {
    const base = fileName.replace(/^.*[\\/]/, '').replace(/\.(dart|m?[jt]s|json)$/, '');
    if (base !== json.id) e.push(`root id "${json.id}" differs from the file name "${base}"`);
  }
  validateCase(json, 'Root', new Set(), e, true);
  return e;
}

/** Every id and every `runTest` in the tree */
export function collectIds(root: TestCaseNode): { ids: string[]; runTests: string[] } {
  const ids: string[] = [], runTests: string[] = [];
  const actions = (list?: unknown[]) => {
    for (const a of (list ?? []) as Json[]) {
      if (a.cmd === 'runTest') runTests.push(a.script as string);
      actions(a.onError as unknown[]);
      actions(a.steps as unknown[]);
    }
  };
  const visit = (c: TestCaseNode) => {
    if (c.id) ids.push(c.id);
    actions(c.pre);
    actions(c.after);
    if (c.type === 'unit') actions(c.steps);
    else c.cases.forEach(visit);
  };
  visit(root);
  return { ids, runTests };
}

// ==== Building actions ====

function build(cmd: string, args: Record<string, unknown>): TestAction {
  const json: Json = { cmd };
  for (const [k, v] of Object.entries(args)) {
    if (v === undefined || v === null || (v === false && (k === 'enabled' || k === 'shot'))) continue;
    json[k] = v;
  }
  const e: string[] = [];
  validateStep(json, cmd, false, e);
  if (e.length) throw new Error(e.join('\n'));
  return Object.freeze(json) as TestAction;
}

const find = (f: Find = {}) => ({ text: f.text, id: f.id, type: f.type, icon: f.icon, route: f.route, inside: f.inside, match: f.match === 'exact' ? undefined : f.match });
const opt = (o: Opt = {}) => ({ timeout: o.timeout, note: o.note, shot: o.shot, onError: o.onError });
const state = (s: FieldState = {}) => ({ enabled: s.enabled, value: s.value, focused: s.focused, obscured: s.obscured, maxLength: s.maxLength, count: s.count, checked: s.checked, selected: s.selected });

/** Test data provided by the app (`BistProvider.testData`, e.g. test accounts) – keeps passwords out of scripts */
export const tc = (group: string, field: string) => `{{tc:${group}.${field}}}`;

/** Environment info used directly in text (see getEnv) */
export const env = (key: string) => `{{env:${key}}}`;

// Tap, input
/** Taps the widget matching all given properties */
export const tap = (f: Find & Opt) => build('tap', { ...find(f), ...opt(f) });
/** Long press (700 ms) */
export const tapLong = (f: Find & Opt) => build('tapLong', { ...find(f), ...opt(f) });
/** Double tap */
export const tapDouble = (f: Find & Opt) => build('tapDouble', { ...find(f), ...opt(f) });
/** Enters text (replaces existing text, '' clears it); no finder = the focused field. Dropdown: the text of the item to pick. */
export const input = (value: string, f: Find & Opt = {}) => build('input', { value, ...find(f), ...opt(f) });
/** Picks a date `dd/MM/yyyy` (or `{{date:+1}}`) */
export const inputDate = (value: string, f: Find & Opt = {}) => build('inputDate', { value, ...find(f), ...opt(f) });
/** Picks a date range */
export const inputDateRange = (start: string, end: string, f: Find & Opt = {}) => build('inputDateRange', { start, end, ...find(f), ...opt(f) });
/** Sample file for the next file / image picker: downloads `url` (https, cached) when reached */
export const pickFile = (url: string, o: { name?: string; note?: string } = {}) => build('pickFile', { url, name: o.name, note: o.note });

// Check
/** Waits until a widget matching all properties is visible (scrolls to find it); only `route` = waits for that screen */
export const expect = (f: Find & FieldState & Opt) => build('expect', { ...find(f), ...state(f), ...opt(f) });
/** Waits until the widget is gone; with field conditions: the field must exist but not match them */
export const notExpect = (f: Find & FieldState & Opt) => build('notExpect', { ...find(f), ...state(f), ...opt(f) });

// Navigate, scroll, wait
/** Goes back / closes the dialog */
export const back = (o: Omit<Opt, 'timeout'> = {}) => build('back', opt(o));
/** Swipe: up = see content below, down = pull to refresh; with a finder, swipes inside the scrollable containing that widget */
export const swipe = (direction: SwipeDirection, f: Find & Omit<Opt, 'timeout'> = {}) => build('swipe', { direction, ...find(f), ...opt(f) });
/** Waits exactly ms milliseconds */
export const wait = (ms: number, o: { note?: string; shot?: boolean } = {}) => build('wait', { ms, ...opt(o) });
/** Runs the item with this id (a sub-script), then continues */
export const runTest = (script: string, o: { note?: string; onError?: TestAction[] } = {}) => build('runTest', { script, ...opt(o) });

// Loops, generated data
/** Repeats steps with {{i}} = from..to (at most 200 iterations) */
export const loop = (from: number, to: number, steps: TestAction[], o: { note?: string; onError?: TestAction[] } = {}) =>
  build('loop', { from, to, steps, ...opt(o) });
/** While the condition (expect / notExpect) holds, runs steps; stops when it doesn't; fails after max iterations (default 20) */
export const loopWhile = (condition: TestAction, steps: TestAction[], o: { max?: number; note?: string; onError?: TestAction[] } = {}) =>
  build('loopWhile', { condition, steps, max: o.max, ...opt(o) });
/** Random integer min..max saved to {{name}}; format may contain `{value}` */
export const randInt = (name: string, min: number, max: number, o: { format?: string; note?: string } = {}) =>
  build('randInt', { name, min, max, format: o.format, note: o.note });
/** Random text of length minLength..maxLength saved to {{name}} */
export const randText = (name: string, minLength: number, maxLength: number, o: { chars?: string; format?: string; note?: string } = {}) =>
  build('randText', { name, minLength, maxLength, chars: o.chars, format: o.format, note: o.note });

// Read values
/** Text of a widget / input → {{name}} */
export const getText = (name: string, f: Find & Omit<Opt, 'shot'>) => build('getText', { name, ...find(f), ...opt(f) });
/** Value from the newest app log whose tag contains `tag`, at `path` (e.g. responseBody.data.userId) → {{name}} */
export const getLog = (name: string, tag: string, o: { path?: string; level?: LogLevel; timeout?: number; note?: string; onError?: TestAction[] } = {}) =>
  build('getLog', { name, tag, path: o.path, level: o.level, ...opt(o) });
/** user.id, user.name, user.role, user.logged, app.id, app.name, app.version, env, server.name, server.url, route, setting:<name>, values provided by the app (`Bist.instance.values`, `BistProvider.env`) → {{name}} */
export const getEnv = (name: string, key: string, o: { note?: string; onError?: TestAction[] } = {}) => build('getEnv', { name, key, ...opt(o) });

// Print, notify, ask the tester
/** Writes to the report and the BIST| log */
export const log = (message: string, o: { note?: string } = {}) => build('log', { message, note: o.note });
/** Short message on screen (3 seconds) */
export const toast = (message: string, o: { note?: string } = {}) => build('toast', { message, note: o.note });
/** Confirmation dialog for the tester: Yes passes, No fails (waits up to 5 minutes) */
export const confirm = (message: string, o: { yes?: string; no?: string; timeout?: number; note?: string; onError?: TestAction[] } = {}) =>
  build('confirm', { message, yes: o.yes, no: o.no, ...opt(o) });
/** Dialog asking the tester for input (OTP…) → {{name}} */
export const ask = (name: string, message: string, o: { initial?: string; hint?: string; timeout?: number; note?: string; onError?: TestAction[] } = {}) =>
  build('ask', { name, message, initial: o.initial, hint: o.hint, ...opt(o) });

// For developers
/** Goes straight to a route */
export const nav = (path: string, o: Opt = {}) => build('nav', { path, ...opt(o) });
/** Switches the server, like picking one in the app's server settings */
export const server = (name: string, o: { timeout?: number; note?: string; onError?: TestAction[] } = {}) => build('server', { name, ...opt(o) });
/** Waits for an app log whose tag contains `tag` */
export const expectLog = (tag: string, o: { level?: LogLevel; timeout?: number; note?: string; onError?: TestAction[] } = {}) =>
  build('expectLog', { tag, level: o.level, ...opt(o) });

// Mock server – removed automatically when the run ends
/** Requests whose URL contains `api` (and match `method`, if given) get a fake response: `status` (default 200), `body` (JSON text or object),
 *  after `delay` ms, for `times` requests, then it removes itself. Use it to test error screens, empty data, slow networks. */
export const mockApi = (api: string, o: { status?: number; body?: string | object; delay?: number; times?: number; method?: HttpMethod; note?: string } = {}) =>
  build('mockApi', { api, status: o.status, body: o.body == null || typeof o.body === 'string' ? o.body : JSON.stringify(o.body), delay: o.delay, times: o.times, method: o.method, note: o.note });
/** Simulates going offline (`on` defaults to true) or back online (`on: false`): every request fails with "Disconnected" */
export const offline = (o: { on?: boolean; note?: string } = {}) => build('offline', { on: o.on ?? true, note: o.note });
/** Removes every active mockApi / offline */
export const resetApi = (o: { note?: string } = {}) => build('resetApi', { note: o.note });

// ==== Script tree ====

function node<T extends TestCaseNode>(type: T['type'], p: CaseProps, body: Record<string, unknown>): T {
  return {
    type,
    ...(p.id != null && { id: p.id }),
    name: p.name,
    ...(p.minVersion != null && { minVersion: p.minVersion }),
    ...(p.maxVersion != null && { maxVersion: p.maxVersion }),
    ...(p.manual != null && { manual: p.manual }),
    ...(p.writes && { writes: true }),
    ...(p.pre?.length && { pre: p.pre }),
    ...(p.after?.length && { after: p.after }),
    ...body,
  } as unknown as T;
}

/** One test: the actions in steps */
export const TestUnit = (p: CaseProps & { steps?: TestAction[] }): TestUnitNode => node('unit', p, { steps: p.steps ?? [] });

/** Group: independent children; pre / after run around each child. One script file = one root TestGroup. */
export const TestGroup = (p: CaseProps & { cases: TestCaseNode[] }): TestGroupNode => node('group', p, { cases: p.cases });

/** Group run in order: if a child fails, the remaining children are skipped; pre / after run once */
export const TestSequence = (p: CaseProps & { cases: TestCaseNode[] }): TestGroupNode => node('sequence', p, { cases: p.cases });

/** Script file JSON (root with schema) */
export const toRootJson = (root: TestGroupNode) => ({ schema: SCHEMA, ...root });

/** Prints the script file JSON – at the end of each `<id>.ts` file: `printJson(script)`. Throws on errors instead of printing. */
export function printJson(root: TestGroupNode): void {
  const json = toRootJson(root);
  const e = validate(json as unknown as Json);
  if (e.length) throw new Error(`${root.name}:\n${e.join('\n')}`);
  console.log(JSON.stringify(json, null, 2));
}


// ==== Tools: transpile, type check, bundle (shared by editor.html and the command line) ====

/** Error with a line number */
export interface Diagnostic {
  line: number;
  message: string;
}

// Minimal base types for type checking / completion in the browser (no TypeScript lib.d.ts there) – shared with editor.html
export const MINI_LIB = `
interface Array<T> { length: number; [n: number]: T; map<U>(f: (v: T, i: number) => U): U[]; filter(f: (v: T, i: number) => unknown): T[]; forEach(f: (v: T, i: number) => void): void; some(f: (v: T, i: number) => unknown): boolean; every(f: (v: T, i: number) => unknown): boolean; find(f: (v: T, i: number) => unknown): T | undefined; includes(v: T): boolean; indexOf(v: T): number; slice(a?: number, b?: number): T[]; join(s?: string): string; push(...v: T[]): number; concat(...v: (T | T[])[]): T[]; }
interface ArrayConstructor { from<T>(a: { length: number }, f?: (v: unknown, i: number) => T): T[]; isArray(v: unknown): v is unknown[]; }
declare const Array: ArrayConstructor;
interface ReadonlyArray<T> { length: number; readonly [n: number]: T; }
interface Boolean {} interface Function {} interface CallableFunction {} interface NewableFunction {} interface IArguments {}
interface Number { toString(r?: number): string; } interface Object {} interface RegExp {}
interface String { length: number; replace(a: string | RegExp, b: string): string; padStart(n: number, s?: string): string; toUpperCase(): string; toLowerCase(): string; trim(): string; }
interface TemplateStringsArray extends ReadonlyArray<string> {}
type Record<K extends keyof any, T> = { [P in K]: T };
type Partial<T> = { [P in keyof T]?: T[P] };
type Pick<T, K extends keyof T> = { [P in K]: T[P] };
type Exclude<T, U> = T extends U ? never : T;
type Omit<T, K extends keyof any> = Pick<T, Exclude<keyof T, K>>;
declare const console: { log(...a: unknown[]): void };
declare const Math: { random(): number; floor(n: number): number; ceil(n: number): number; round(n: number): number; min(...n: number[]): number; max(...n: number[]): number };
declare const JSON: { stringify(v: unknown, r?: unknown, s?: number | string): string; parse(s: string): any };
`;

/** Transpiles TS → CommonJS JS (import 'flutter_bist' / '@tlt/bist' becomes require) – [ts] is the `typescript` module */
export function transpile(ts: any, source: string, fileName: string): { code: string; errors: Diagnostic[] } {
  const r = ts.transpileModule(source, { fileName, reportDiagnostics: true, compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } });
  return { code: r.outputText, errors: toDiagnostics(ts, r.diagnostics ?? []) };
}

function toDiagnostics(ts: any, list: any[]): Diagnostic[] {
  return list.map((d) => ({
    line: d.file && d.start != null ? d.file.getLineAndCharacterOfPosition(d.start).line + 1 : 0,
    message: ts.flattenDiagnosticMessageText(d.messageText, '\n'),
  }));
}

/**
 * Type checks a script (command names, parameter names, value types). [bist]: the contents of `bist.d.ts`, or `bist.ts` itself (the browser
 * reads it directly, no build needed). [libFiles]: TypeScript lib files (the command line passes the real libs; the browser leaves it empty – minimal
 * base types are used). Only returns errors of the script file.
 */
export function typecheck(ts: any, source: string, fileName: string, bist: string, libFiles?: Record<string, string>): Diagnostic[] {
  const lib = libFiles ?? { 'lib.mini.d.ts': MINI_LIB };
  const bistFile = /\bexport declare\b/.test(bist) ? 'node_modules/flutter_bist/index.d.ts' : 'node_modules/flutter_bist/index.ts';
  const files: Record<string, string> = { [fileName]: source, [bistFile]: bist, ...lib };
  const options = {
    target: libFiles ? ts.ScriptTarget.ES2022 : ts.ScriptTarget.ES5,
    module: ts.ModuleKind.ESNext,
    moduleResolution: ts.ModuleResolutionKind.Node10,
    noLib: true,
    strict: true,
    noEmit: true,
    types: [],
    skipLibCheck: true,
  };
  const host = {
    getSourceFile: (n: string, v: any) => (n in files ? ts.createSourceFile(n, files[n], v, true) : undefined),
    getDefaultLibFileName: () => Object.keys(lib)[0],
    writeFile: () => {},
    getCurrentDirectory: () => '',
    getDirectories: () => [],
    fileExists: (n: string) => n in files,
    readFile: (n: string) => files[n],
    getCanonicalFileName: (n: string) => n,
    useCaseSensitiveFileNames: () => true,
    getNewLine: () => '\n',
    resolveModuleNames: (names: string[]) =>
      names.map((m) => (m === 'flutter_bist' || m === '@tlt/bist' ? { resolvedFileName: bistFile, extension: bistFile.endsWith('.d.ts') ? '.d.ts' : '.ts' } : undefined)),
  };
  const program = ts.createProgram([fileName, ...Object.keys(lib)], options, host);
  const sf = program.getSourceFile(fileName);
  return toDiagnostics(ts, [...program.getSyntacticDiagnostics(sf), ...program.getSemanticDiagnostics(sf)]);
}

function base64(s: string): string {
  if (typeof btoa === 'function') {
    const bytes = new TextEncoder().encode(s);
    let bin = '';
    for (const b of bytes) bin += String.fromCharCode(b);
    return btoa(bin);
  }
  return (globalThis as any).Buffer.from(s, 'utf8').toString('base64');
}
declare class TextEncoder {
  encode(s: string): Uint8Array;
}
interface Uint8Array {
  [Symbol.iterator](): IterableIterator<number>;
}

/**
 * Standalone `.mjs` file: the library embedded ([bistSource] = contents of `bist.mjs`) + the transpiled script ([code], CommonJS).
 * Run: `node <id>.mjs` (or import it in a module Web Worker) – prints JSON.
 */
export function bundleMjs(id: string, fileName: string, code: string, bistSource: string): string {
  return `// ${id}.mjs – generated from ${fileName} (flutter_bist bin/bist.mjs), run: node ${id}.mjs
const __bist = await import('data:text/javascript;base64,${base64(bistSource)}');
const exports = {};
const module = { exports };
const require = (n) => { if (n === 'flutter_bist' || n === '@tlt/bist') return __bist; throw new Error('Only flutter_bist can be imported: ' + n); };
${code}
`;
}

// ==== Command line: node bin/bist.mjs <scripts dir> <JSON dir> [--mjs <dir>] ====

const imp = (m: string): Promise<any> => import(m);

async function main(argv: string[]): Promise<number> {
  const [fs, path, url, cp, mod] = await Promise.all(['node:fs', 'node:path', 'node:url', 'node:child_process', 'node:module'].map(imp));
  const self = url.fileURLToPath(import.meta.url);
  const here = path.dirname(self);

  // Embed bist.ts into the editor page (so it opens with a double click)
  if (argv[0] === '--embed' && argv[1] && argv[2] && argv[3]) {
    // node bist.mjs --embed <bist.ts> <editor.html source> <output editor.html>
    const src = fs.readFileSync(argv[1], 'utf8');
    if (/<\/script/i.test(src)) throw new Error('bist.ts must not contain a closing script tag');
    const html = fs.readFileSync(argv[2], 'utf8');
    const re = /(<script id="bist-src" type="text\/plain">)[\s\S]*?(<\/script>)/;
    if (!re.test(html)) throw new Error(`${argv[2]} is missing <script id="bist-src" type="text/plain">`);
    fs.writeFileSync(argv[3], html.replace(re, (_: string, a: string, b: string) => a + src + b));
    console.log(`Embedded ${path.basename(argv[1])} into ${argv[3]}`);
    return 0;
  }
  const args = [...argv];
  const mjsFlag = args.indexOf('--mjs');
  const mjsArg = mjsFlag >= 0 ? args.splice(mjsFlag, 2)[1] : null;
  if (args.length !== 2) {
    console.error('Usage: node bist.mjs <scripts dir> <JSON dir> [--mjs <.mjs dir>]');
    return 2;
  }
  const [srcDir, outDir] = args.map((a: string) => path.resolve(a));
  const mjsDir = path.resolve(mjsArg ?? path.join(srcDir, 'build'));

  // typescript: next to this file, in the current directory, or installed globally
  let ts: any;
  for (const from of [self, path.join(here, '..', 'tools', 'editor', 'x.js'), path.join(process.cwd(), 'x.js')]) {
    try {
      ts = mod.createRequire(from)('typescript');
      break;
    } catch {
      // try the next location
    }
  }
  if (!ts) {
    try {
      const root = cp.execSync('npm root -g', { encoding: 'utf8' }).trim();
      ts = mod.createRequire(path.join(root, 'x.js'))('typescript');
    } catch {
      console.error('Missing the typescript package: run `npm install` in flutter_bist/tools/editor (or `npm i -g typescript`)');
      return 2;
    }
  }
  const bistSource = fs.readFileSync(self, 'utf8');
  const dtsPath = path.join(here, 'bist.d.ts');
  if (!fs.existsSync(dtsPath)) {
    console.error(`Missing ${dtsPath}: run \`npm run build\` in flutter_bist/tools/editor`);
    return 2;
  }
  const dts = fs.readFileSync(dtsPath, 'utf8');
  const libDir = path.dirname(ts.getDefaultLibFilePath({ target: ts.ScriptTarget.ES2022 }));
  const libFiles: Record<string, string> = {};
  for (const f of fs.readdirSync(libDir)) if (/^lib\.es(5|20\d\d)(\.[a-z]+)*\.d\.ts$/.test(f) || f === 'lib.decorators.d.ts' || f === 'lib.decorators.legacy.d.ts') libFiles[f] = fs.readFileSync(path.join(libDir, f), 'utf8');
  const libOrdered = { 'lib.es2022.d.ts': libFiles['lib.es2022.d.ts'], ...libFiles };

  // tsconfig.json for VS Code (import 'flutter_bist' / '@tlt/bist' → this library), created if missing
  const tsconfig = path.join(srcDir, 'tsconfig.json');
  if (!fs.existsSync(tsconfig)) {
    const target = path.join(here, 'bist.d.ts');
    const rel = path.relative(srcDir, target).split(path.sep).join('/');
    const cfg = { compilerOptions: { target: 'ES2022', module: 'ESNext', moduleResolution: 'Bundler', strict: true, noEmit: true, skipLibCheck: true, lib: ['ES2022'], types: [], paths: { flutter_bist: [rel], '@tlt/bist': [rel] } }, include: ['*.ts'] };
    fs.writeFileSync(tsconfig, JSON.stringify(cfg, null, 2) + '\n');
    console.log(`Created ${path.relative(process.cwd(), tsconfig)}`);
  }

  const files = fs.readdirSync(srcDir).filter((f: string) => f.endsWith('.ts') && !f.endsWith('.d.ts')).sort();
  if (!files.length) {
    console.error(`No .ts files in ${srcDir}`);
    return 1;
  }
  fs.mkdirSync(mjsDir, { recursive: true });
  const errors: string[] = [];
  const roots = new Map<string, TestGroupNode>();
  for (const f of files) {
    const id = f.replace(/\.ts$/, '');
    const source = fs.readFileSync(path.join(srcDir, f), 'utf8');
    const diag = typecheck(ts, source, f, dts, libOrdered);
    if (diag.length) {
      errors.push(`${f}:\n  ${diag.map((d) => `Line ${d.line}: ${d.message}`).join('\n  ')}`);
      continue;
    }
    const { code } = transpile(ts, source, f);
    const mjs = path.join(mjsDir, `${id}.mjs`);
    fs.writeFileSync(mjs, bundleMjs(id, f, code, bistSource));
    let out: string;
    try {
      out = cp.execFileSync(process.execPath, [mjs], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (e: any) {
      errors.push(`${f}: ${`${e.stderr ?? e.message}`.trim().split('\n').filter((l: string) => !l.startsWith('    at ')).join('\n')}`);
      continue;
    }
    try {
      const json = JSON.parse(out.slice(out.indexOf('{')));
      const e = validate(json, f);
      if (e.length) errors.push(`${f}:\n  ${e.join('\n  ')}`);
      else roots.set(json.id, json);
    } catch (e: any) {
      errors.push(`${f}: couldn't read JSON (${e.message}) – the file must call printJson(root)`);
    }
  }
  const owner = new Map<string, string>();
  for (const [file, root] of roots) {
    for (const id of collectIds(root).ids) {
      if (owner.has(id) && owner.get(id) !== file) errors.push(`id "${id}" is duplicated in ${file} and ${owner.get(id)}`);
      owner.set(id, file);
    }
  }
  for (const [file, root] of roots) for (const id of collectIds(root).runTests) if (!owner.has(id)) errors.push(`${file}: runTest("${id}") – no item has this id`);
  if (errors.length) {
    console.error(errors.join('\n'));
    return 1;
  }
  fs.mkdirSync(outDir, { recursive: true });
  for (const f of fs.readdirSync(outDir)) if (f.endsWith('.json')) fs.rmSync(path.join(outDir, f));
  for (const [id, json] of roots) fs.writeFileSync(path.join(outDir, `${id}.json`), JSON.stringify(toRootJson(json), null, 2) + '\n');
  console.log(`BIST: ${roots.size} script(s) → ${path.relative(process.cwd(), outDir) || '.'} (.mjs in ${path.relative(process.cwd(), mjsDir)})`);
  return 0;
}

// Run the command line when called directly as `node bist.mjs ...` (not when imported by a script / the browser)
// (compares the file name, not the path: when called through a symlink, import.meta.url is the real path)
if (typeof process !== 'undefined' && import.meta.url.startsWith('file:') && /[\\/]bist\.m?js$/.test(process.argv?.[1] ?? '')) {
  main(process.argv.slice(2)).then((code) => process.exit(code));
}
