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
/** JSON format version – same as `kTestScriptSchema` in the Dart model */
export declare const SCHEMA = 4;
export declare const WidgetType: {
    readonly button: "button";
    readonly input: "input";
    readonly text: "text";
    readonly image: "image";
};
export type WidgetType = (typeof WidgetType)[keyof typeof WidgetType];
export declare const LogLevel: {
    readonly debug: "debug";
    readonly info: "info";
    readonly warn: "warn";
    readonly error: "error";
    readonly damage: "damage";
    readonly success: "success";
};
export type LogLevel = (typeof LogLevel)[keyof typeof LogLevel];
export declare const SwipeDirection: {
    readonly up: "up";
    readonly down: "down";
    readonly left: "left";
    readonly right: "right";
};
/** How `text` / `value` is compared: exact (default), contains, regular expression */
export declare const TextMatch: {
    readonly exact: "exact";
    readonly contains: "contains";
    readonly regex: "regex";
};
export type TextMatch = (typeof TextMatch)[keyof typeof TextMatch];
/** HTTP method for mockApi */
export type HttpMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
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
    /** For calling it again (`runTest(id)`) and running it alone (`BIST_RUN_IDS=<id>`); unique across all files */
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
/** Secret-looking keys / paths – getEnv, getLog refuse them */
export declare const SECRET_PATTERN: RegExp;
/** Placeholders replaced at run time: `{{tc:group.field}}`, `{{env:key}}`, `{{date:+1}}`, `{{now}}`, `{{i}}`, `{{variable}}` */
export declare const VALUE_PATTERN: RegExp;
export declare const COMMANDS: string[];
type Json = Record<string, unknown>;
/** Validates a script file's JSON (the root has `schema`), returns the list of errors. [fileName]: check the root id matches the file name. */
export declare function validate(json: Json, fileName?: string): string[];
/** Every id and every `runTest` in the tree */
export declare function collectIds(root: TestCaseNode): {
    ids: string[];
    runTests: string[];
};
/** Test data provided by the app (`BistProvider.testData`, e.g. test accounts) – keeps passwords out of scripts */
export declare const tc: (group: string, field: string) => string;
/** Environment info used directly in text (see getEnv) */
export declare const env: (key: string) => string;
/** Taps the widget matching all given properties */
export declare const tap: (f: Find & Opt) => TestAction;
/** Long press (700 ms) */
export declare const tapLong: (f: Find & Opt) => TestAction;
/** Double tap */
export declare const tapDouble: (f: Find & Opt) => TestAction;
/** Enters text (replaces existing text, '' clears it); no finder = the focused field. Dropdown: the text of the item to pick. */
export declare const input: (value: string, f?: Find & Opt) => TestAction;
/** Picks a date `dd/MM/yyyy` (or `{{date:+1}}`) */
export declare const inputDate: (value: string, f?: Find & Opt) => TestAction;
/** Picks a date range */
export declare const inputDateRange: (start: string, end: string, f?: Find & Opt) => TestAction;
/** Sample file for the next file / image picker: downloads `url` (https, cached) when reached */
export declare const pickFile: (url: string, o?: {
    name?: string;
    note?: string;
}) => TestAction;
/** Waits until a widget matching all properties is visible (scrolls to find it); only `route` = waits for that screen */
export declare const expect: (f: Find & FieldState & Opt) => TestAction;
/** Waits until the widget is gone; with field conditions: the field must exist but not match them */
export declare const notExpect: (f: Find & FieldState & Opt) => TestAction;
/** Goes back / closes the dialog */
export declare const back: (o?: Omit<Opt, "timeout">) => TestAction;
/** Swipe: up = see content below, down = pull to refresh; with a finder, swipes inside the scrollable containing that widget */
export declare const swipe: (direction: SwipeDirection, f?: Find & Omit<Opt, "timeout">) => TestAction;
/** Waits exactly ms milliseconds */
export declare const wait: (ms: number, o?: {
    note?: string;
    shot?: boolean;
}) => TestAction;
/** Runs the item with this id (a sub-script), then continues */
export declare const runTest: (script: string, o?: {
    note?: string;
    onError?: TestAction[];
}) => TestAction;
/** Repeats steps with {{i}} = from..to (at most 200 iterations) */
export declare const loop: (from: number, to: number, steps: TestAction[], o?: {
    note?: string;
    onError?: TestAction[];
}) => TestAction;
/** While the condition (expect / notExpect) holds, runs steps; stops when it doesn't; fails after max iterations (default 20) */
export declare const loopWhile: (condition: TestAction, steps: TestAction[], o?: {
    max?: number;
    note?: string;
    onError?: TestAction[];
}) => TestAction;
/** Random integer min..max saved to {{name}}; format may contain `{value}` */
export declare const randInt: (name: string, min: number, max: number, o?: {
    format?: string;
    note?: string;
}) => TestAction;
/** Random text of length minLength..maxLength saved to {{name}} */
export declare const randText: (name: string, minLength: number, maxLength: number, o?: {
    chars?: string;
    format?: string;
    note?: string;
}) => TestAction;
/** Text of a widget / input → {{name}} */
export declare const getText: (name: string, f: Find & Omit<Opt, "shot">) => TestAction;
/** Value from the newest app log whose tag contains `tag`, at `path` (e.g. responseBody.data.userId) → {{name}} */
export declare const getLog: (name: string, tag: string, o?: {
    path?: string;
    level?: LogLevel;
    timeout?: number;
    note?: string;
    onError?: TestAction[];
}) => TestAction;
/** user.id, user.name, user.role, user.logged, app.id, app.name, app.version, env, server.name, server.url, route, setting:<name>, values provided by the app (`Bist.instance.values`, `BistProvider.env`) → {{name}} */
export declare const getEnv: (name: string, key: string, o?: {
    note?: string;
    onError?: TestAction[];
}) => TestAction;
/** Writes to the report and the BIST| log */
export declare const log: (message: string, o?: {
    note?: string;
}) => TestAction;
/** Short message on screen (3 seconds) */
export declare const toast: (message: string, o?: {
    note?: string;
}) => TestAction;
/** Confirmation dialog for the tester: Yes passes, No fails (waits up to 5 minutes) */
export declare const confirm: (message: string, o?: {
    yes?: string;
    no?: string;
    timeout?: number;
    note?: string;
    onError?: TestAction[];
}) => TestAction;
/** Dialog asking the tester for input (OTP…) → {{name}} */
export declare const ask: (name: string, message: string, o?: {
    initial?: string;
    hint?: string;
    timeout?: number;
    note?: string;
    onError?: TestAction[];
}) => TestAction;
/** Goes straight to a route */
export declare const nav: (path: string, o?: Opt) => TestAction;
/** Switches the server, like picking one in the app's server settings */
export declare const server: (name: string, o?: {
    timeout?: number;
    note?: string;
    onError?: TestAction[];
}) => TestAction;
/** Waits for an app log whose tag contains `tag` */
export declare const expectLog: (tag: string, o?: {
    level?: LogLevel;
    timeout?: number;
    note?: string;
    onError?: TestAction[];
}) => TestAction;
/** Requests whose URL contains `api` (and match `method`, if given) get a fake response: `status` (default 200), `body` (JSON text or object),
 *  after `delay` ms, for `times` requests, then it removes itself. Use it to test error screens, empty data, slow networks. */
export declare const mockApi: (api: string, o?: {
    status?: number;
    body?: string | object;
    delay?: number;
    times?: number;
    method?: HttpMethod;
    note?: string;
}) => TestAction;
/** Simulates going offline (`on` defaults to true) or back online (`on: false`): every request fails with "Disconnected" */
export declare const offline: (o?: {
    on?: boolean;
    note?: string;
}) => TestAction;
/** Removes every active mockApi / offline */
export declare const resetApi: (o?: {
    note?: string;
}) => TestAction;
/** One test: the actions in steps */
export declare const TestUnit: (p: CaseProps & {
    steps?: TestAction[];
}) => TestUnitNode;
/** Group: independent children; pre / after run around each child. One script file = one root TestGroup. */
export declare const TestGroup: (p: CaseProps & {
    cases: TestCaseNode[];
}) => TestGroupNode;
/** Group run in order: if a child fails, the remaining children are skipped; pre / after run once */
export declare const TestSequence: (p: CaseProps & {
    cases: TestCaseNode[];
}) => TestGroupNode;
/** Script file JSON (root with schema) */
export declare const toRootJson: (root: TestGroupNode) => {
    type: "group" | "sequence";
    cases: TestCaseNode[];
    name: string;
    /** For calling it again (`runTest(id)`) and running it alone (`BIST_RUN_IDS=<id>`); unique across all files */
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
    schema: number;
};
/** Prints the script file JSON – at the end of each `<id>.ts` file: `printJson(script)`. Throws on errors instead of printing. */
export declare function printJson(root: TestGroupNode): void;
/** Error with a line number */
export interface Diagnostic {
    line: number;
    message: string;
}
export declare const MINI_LIB = "\ninterface Array<T> { length: number; [n: number]: T; map<U>(f: (v: T, i: number) => U): U[]; filter(f: (v: T, i: number) => unknown): T[]; forEach(f: (v: T, i: number) => void): void; some(f: (v: T, i: number) => unknown): boolean; every(f: (v: T, i: number) => unknown): boolean; find(f: (v: T, i: number) => unknown): T | undefined; includes(v: T): boolean; indexOf(v: T): number; slice(a?: number, b?: number): T[]; join(s?: string): string; push(...v: T[]): number; concat(...v: (T | T[])[]): T[]; }\ninterface ArrayConstructor { from<T>(a: { length: number }, f?: (v: unknown, i: number) => T): T[]; isArray(v: unknown): v is unknown[]; }\ndeclare const Array: ArrayConstructor;\ninterface ReadonlyArray<T> { length: number; readonly [n: number]: T; }\ninterface Boolean {} interface Function {} interface CallableFunction {} interface NewableFunction {} interface IArguments {}\ninterface Number { toString(r?: number): string; } interface Object {} interface RegExp {}\ninterface String { length: number; replace(a: string | RegExp, b: string): string; padStart(n: number, s?: string): string; toUpperCase(): string; toLowerCase(): string; trim(): string; }\ninterface TemplateStringsArray extends ReadonlyArray<string> {}\ntype Record<K extends keyof any, T> = { [P in K]: T };\ntype Partial<T> = { [P in keyof T]?: T[P] };\ntype Pick<T, K extends keyof T> = { [P in K]: T[P] };\ntype Exclude<T, U> = T extends U ? never : T;\ntype Omit<T, K extends keyof any> = Pick<T, Exclude<keyof T, K>>;\ndeclare const console: { log(...a: unknown[]): void };\ndeclare const Math: { random(): number; floor(n: number): number; ceil(n: number): number; round(n: number): number; min(...n: number[]): number; max(...n: number[]): number };\ndeclare const JSON: { stringify(v: unknown, r?: unknown, s?: number | string): string; parse(s: string): any };\n";
/** Transpiles TS → CommonJS JS (import 'flutter_bist' / '@tlt/bist' becomes require) – [ts] is the `typescript` module */
export declare function transpile(ts: any, source: string, fileName: string): {
    code: string;
    errors: Diagnostic[];
};
/**
 * Type checks a script (command names, parameter names, value types). [bist]: the contents of `bist.d.ts`, or `bist.ts` itself (the browser
 * reads it directly, no build needed). [libFiles]: TypeScript lib files (the command line passes the real libs; the browser leaves it empty – minimal
 * base types are used). Only returns errors of the script file.
 */
export declare function typecheck(ts: any, source: string, fileName: string, bist: string, libFiles?: Record<string, string>): Diagnostic[];
/**
 * Standalone `.mjs` file: the library embedded ([bistSource] = contents of `bist.mjs`) + the transpiled script ([code], CommonJS).
 * Run: `node <id>.mjs` (or import it in a module Web Worker) – prints JSON.
 */
export declare function bundleMjs(id: string, fileName: string, code: string, bistSource: string): string;
export {};
