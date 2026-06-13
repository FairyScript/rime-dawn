# Slash Key Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use compose:subagent (recommended) or compose:execute to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `/` key occupation by migrating schema-switch commands to the scheme menu and deleting the double-`/` key binding.

**Architecture:** Add a multi-option Rime switch for pinyin scheme selection. Convert `set_schema.lua` from a `/`-prefix translator to an `option_update_notifier` listener that rewrites `.custom.yaml` files when the user selects a scheme from the menu.

**Tech Stack:** Rime YAML config, Lua (librime-lua API)

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `wanxiang.schema.yaml` | Modify | Add pinyin scheme switch, delete double-`/` key_binder rule |
| `lua/wanxiang/set_schema.lua` | Rewrite | Option-based schema switching via `update_notifier` |
| `wanxiang.custom.yaml` | Modify | Add default pinyin scheme option |
| `custom/wanxiang.custom.yaml` | Modify | Sync template |

---

### Task 1: Add pinyin scheme switch to `wanxiang.schema.yaml`

**Files:**
- Modify: `wanxiang.schema.yaml:22-51` (switches section)

- [ ] **Step 1: Add the multi-option pinyin scheme switch**

Insert a new switch entry after the existing `charset_filter` switch (line 40) and before `char_priority` (line 42). The new switch goes in the `# Character Sets` group:

```yaml
  - options: [pinyin_pinyin, pinyin_zrm, pinyin_znabc, pinyin_flypy, pinyin_mspy, pinyin_sogou, pinyin_ziguang, pinyin_gbpy, pinyin_pyjj, pinyin_lxsq, pinyin_zrlong, pinyin_hxlong]
    states: [全拼, 自然码, 智能ABC, 小鹤双拼, 微软双拼, 搜狗双拼, 紫光双拼, 国标双拼, 拼音加加, 乱序17, 自然龙, 汉心龙]
    abbrev: [拼, 然, 能, 鹤, 微, 搜, 紫, 标, 加, 乱, 龙, 心]
```

The full switches section should read:

```yaml
switches:
  # Input
  - name: ascii_mode
    states: [中, 英]
  - name: ascii_punct
    states: ["。，", "．，"]
  - name: full_shape
    states: [半角, 全角]
  # Character Sets
  - name: emoji
    states: [表情关, 表情开]
    abbrev: [🚫, 😀]
  - options: [zh_cn, zh_hant, zh_hk, zh_tw]
    states: [简, 繁, 港繁, 臺繁]
  - name: abbrev
    states: [简码关, 简码开]
    abbrev: [关, 简]
  - name: charset_filter
    states: [大字集, 小字集]
  - options: [pinyin_pinyin, pinyin_zrm, pinyin_znabc, pinyin_flypy, pinyin_mspy, pinyin_sogou, pinyin_ziguang, pinyin_gbpy, pinyin_pyjj, pinyin_lxsq, pinyin_zrlong, pinyin_hxlong]
    states: [全拼, 自然码, 智能ABC, 小鹤双拼, 微软双拼, 搜狗双拼, 紫光双拼, 国标双拼, 拼音加加, 乱序17, 自然龙, 汉心龙]
    abbrev: [拼, 然, 能, 鹤, 微, 搜, 紫, 标, 加, 乱, 龙, 心]
  # Features
  - name: char_priority
    states: [词组先, 单字先]
    abbrev: [词, 字]
    # Hints
  - options: [comment_off, tone_hint, toneless_hint]
    states: [提示关, 带声调读音, 无声调读音]
    abbrev: [关, 音, 音]
  - options: [raw_code, tone_pinyin_code, toneless_pinyin_code]
    states: [原编码, 带声调全拼, 无声调全拼]
    abbrev: [关, 拼, 拼]
```

- [ ] **Step 2: Delete the double-`/` key_binder rule**

Remove line 434:
```yaml
    # 双击斜杠键上屏 '/'。
    - {match: "^/$", accept: "/", send_sequence: '{space}',}
```

The key_binder section should end with the backtick rule and then the `editor:` section:
```yaml
    # 编码中输入 `` 进入造词模式。
    - {match: "^.*`$", accept: "`", send_sequence: '{BackSpace}{Home}{`}{`}{End}'}

editor:
```

- [ ] **Step 3: Redeploy and verify the switch appears**

Right-click Weasel tray icon → "重新部署". Open the scheme switcher (Ctrl+\` or F4). Verify the pinyin scheme switch appears with 12 options.

---

### Task 2: Rewrite `set_schema.lua` to use option_update_notifier

**Files:**
- Rewrite: `lua/wanxiang/set_schema.lua`

- [ ] **Step 1: Rewrite the module**

Replace the entire file with the following. The module now uses `init`/`fini` lifecycle hooks and `context.update_notifier` instead of a translator function:

```lua
---Provides a utility to dynamically switch the active Pinyin schema by rewriting the configuration file with the
---selected schema rules.
---@author amzxyz
---@author Fidel Yin <fidel.yin@hotmail.com>

local wanxiang = require("wanxiang.wanxiang")

local OPTION_TO_PINYIN = {
    pinyin_pinyin = "全拼",
    pinyin_zrm = "自然码",
    pinyin_znabc = "智能ABC",
    pinyin_flypy = "小鹤双拼",
    pinyin_mspy = "微软双拼",
    pinyin_sogou = "搜狗双拼",
    pinyin_ziguang = "紫光双拼",
    pinyin_gbpy = "国标双拼",
    pinyin_pyjj = "拼音加加",
    pinyin_lxsq = "乱序17",
    pinyin_zrlong = "自然龙",
    pinyin_hxlong = "汉心龙",
}

---@type table<string, string>
local AUX_SCHEMAS = {
    ["直接辅助"] = true,
    ["间接辅助"] = true,
}

---Copies a file from `src` to `dest`, returning whether the copy succeeded.
---@param src string
---@param dest string
---@return boolean
local function copy_file(src, dest)
    local fi = io.open(src, "rb")
    if not fi then
        return false
    end
    local content = fi:read("*a")
    fi:close()

    local fo = io.open(dest, "wb")
    if not fo then
        return false
    end
    fo:write(content)
    fo:close()
    return true
end

---Ensures a custom file exists in the user data directory, copying its template
---from the shared (or user) `custom/` directory when missing.
---@param filename string
---@param user_dir string
---@param shared_dir string
---@return boolean ok true if the destination file exists after this call
local function ensure_custom_file(filename, user_dir, shared_dir)
    local dest = user_dir .. "/" .. filename
    if wanxiang.file_exists(dest) then
        return true
    end

    local src = shared_dir .. "/custom/" .. filename
    if not wanxiang.file_exists(src) then
        src = user_dir .. "/custom/" .. filename
    end

    if not wanxiang.file_exists(src) then
        log.warning("Template custom file not found: " .. src)
        return false
    end

    return copy_file(src, dest)
end

---Reads `custom_file`, applies `transform` to its content, and writes the result
---back. The write is skipped when `transform` returns `nil`.
---@param custom_file string
---@param transform fun(content: string): string?
---@return boolean ok true if the file was successfully updated
local function update_custom_file(custom_file, transform)
    local f = io.open(custom_file, "r")
    if not f then
        return false
    end
    local content = f:read("*a")
    f:close()

    local new_content = transform(content)
    if not new_content then
        return false
    end

    f = io.open(custom_file, "w")
    if not f then
        return false
    end
    f:write(new_content)
    f:close()
    return true
end

---Returns `name` unchanged when it is an auxiliary schema name; otherwise
---returns the target pinyin schema name.
---@param name string
---@param schema_name string
---@return string
local function preserve_aux(name, schema_name)
    if AUX_SCHEMAS[name] then
        return name
    end
    return schema_name
end

---Rewrites the pinyin algebra reference in a custom file to the given schema.
---@param custom_file string
---@param schema_name string
---@return boolean ok true if a substitution was made and written
local function set_pinyin_schema(custom_file, schema_name)
    return update_custom_file(custom_file, function(content)
        local n = 0
        if custom_file:find("wanxiang_reverse") then
            content, n = content:gsub("(%s*__include:%s*wanxiang_algebra:/reverse/)%S+", "%1" .. schema_name)
        elseif custom_file:find("wanxiang_mixedcode") then
            content, n = content:gsub("(%s*__patch:%s*wanxiang_algebra:/mixed/)%S+", "%1" .. schema_name)
        elseif custom_file:find("wanxiang%.custom") then
            content, n = content:gsub("(%s*%-%s*wanxiang_algebra:/base/)(%S+)", function(prefix, suffix)
                return prefix .. preserve_aux(suffix, schema_name)
            end)
        end

        if n == 0 then
            return nil
        end
        return content
    end)
end

---Detects the active pinyin scheme option and returns the corresponding schema name.
---@param ctx Context
---@return string?
local function detect_pinyin_scheme(ctx)
    for option, schema in pairs(OPTION_TO_PINYIN) do
        if ctx:get_option(option) then
            return schema
        end
    end
    return nil
end

---Rewrites all relevant custom files to switch to the given pinyin schema.
---@param schema_name string
---@param env Env
local function apply_pinyin_schema(schema_name, env)
    local user_dir = rime_api.get_user_data_dir()
    local shared_dir = rime_api.get_shared_data_dir()

    local main_custom_file = env.engine.schema.schema_id .. ".custom.yaml"
    local files = {
        main_custom_file,
        "wanxiang_mixedcode.custom.yaml",
        "wanxiang_reverse.custom.yaml",
    }

    for _, filename in ipairs(files) do
        if ensure_custom_file(filename, user_dir, shared_dir) then
            set_pinyin_schema(user_dir .. "/" .. filename, schema_name)
        end
    end
end

---@type TranslatorModule
local M = {}

---@param env Env
function M.init(env)
    local last_scheme = detect_pinyin_scheme(env.engine.context)

    local notifier = env.engine.context.update_notifier:connect(function(ctx)
        local scheme = detect_pinyin_scheme(ctx)
        if scheme and scheme ~= last_scheme then
            last_scheme = scheme
            apply_pinyin_schema(scheme, env)
        end
    end)

    ---@class SetSchemaState
    ---@field update_notifier Connection
    ---@field last_scheme string?
    env.set_schema_state = {
        update_notifier = notifier,
        last_scheme = last_scheme,
    }
end

---@param env Env
function M.fini(env)
    if env.set_schema_state then
        env.set_schema_state.update_notifier:disconnect()
        env.set_schema_state = nil
    end
end

---@param input string
---@param seg Segment
---@param env Env
function M.func(input, seg, env) end

return M
```

- [ ] **Step 2: Redeploy and verify schema switching works**

Right-click Weasel tray icon → "重新部署". Open the scheme switcher (Ctrl+\` or F4), select a different pinyin scheme (e.g., 小鹤双拼). Verify that `wanxiang.custom.yaml` is rewritten with the new scheme. Redeploy again to confirm the new scheme takes effect.

- [ ] **Step 3: Verify `/` key is no longer occupied**

Type `/` in any application. It should pass through as a normal character (or trigger the punctuation mapping for `、` depending on full/half-width mode), not start a command or send a space on double-press.

---

### Task 3: Update custom YAML defaults

**Files:**
- Modify: `wanxiang.custom.yaml`
- Modify: `custom/wanxiang.custom.yaml`

- [ ] **Step 1: Add default pinyin scheme option to `wanxiang.custom.yaml`**

Add the following line after the `menu/page_size: 6` line (line 19):

```yaml
  # 拼音方案。通过方案选单（Ctrl+` 或 F4）切换。
  switches/pinyin_scheme: pinyin_pinyin
```

The file should read:
```yaml
patch:
  speller/algebra:
    __patch:
      # ** 该选项由切换方案命令写入。如不了解原理，请勿手动修改。 **
      # 可选输入方案："全拼", "自然码", "智能ABC", "小鹤双拼", "微软双拼", "搜狗双拼", "紫光双拼", "国标双拼", "拼音加加", "乱序17", "自然龙", "汉心龙"
      - wanxiang_algebra:/base/小鹤双拼

      # 取消注释以开启模糊音。具体规则见 wanxiang_algebra.yaml。
      #- wanxiang_algebra:/模糊音

  # 每页候选词数量。由于 7、8、9、0 数字键被声调辅助筛选占用，该选项最大值为 6。
  menu/page_size: 6

  # 拼音方案。通过方案选单（Ctrl+` 或 F4）切换。
  switches/pinyin_scheme: pinyin_pinyin
```

Note: The `speller/algebra` line still references `小鹤双拼` — this is the user's current active scheme. The `switches/pinyin_scheme` default is `pinyin_pinyin` (全拼). These are independent: the algebra controls the actual pinyin rules, while the switch controls the menu display. The user's next scheme selection via the menu will synchronize both.

- [ ] **Step 2: Sync the template in `custom/wanxiang.custom.yaml`**

Apply the same addition to `custom/wanxiang.custom.yaml`:

```yaml
patch:
  speller/algebra:
    __patch:
      # ** 该选项由切换方案命令写入。如不了解原理，请勿手动修改。 **
      # 可选输入方案："全拼", "自然码", "智能ABC", "小鹤双拼", "微软双拼", "搜狗双拼", "紫光双拼", "国标双拼", "拼音加加", "乱序17", "自然龙", "汉心龙"
      - wanxiang_algebra:/base/全拼

      # 取消注释以开启模糊音。具体规则见 wanxiang_algebra.yaml。
      #- wanxiang_algebra:/模糊音

  # 每页候选词数量。由于 7、8、9、0 数字键被声调辅助筛选占用，该选项最大值为 6。
  menu/page_size: 6

  # 拼音方案。通过方案选单（Ctrl+` 或 F4）切换。
  switches/pinyin_scheme: pinyin_pinyin
```

- [ ] **Step 3: Final redeploy and end-to-end verification**

Redeploy Rime. Verify:
1. Scheme switcher (Ctrl+\` or F4) shows the pinyin scheme switch with 12 options
2. Selecting a scheme rewrites `wanxiang.custom.yaml` (check file contents)
3. Redeploying again applies the selected scheme
4. Typing `/` does not trigger any special behavior
5. Double-typing `/` does not send a space
