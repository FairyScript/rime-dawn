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

---@type table<string, boolean>
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
