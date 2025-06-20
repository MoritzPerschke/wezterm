local wezterm = require('wezterm')
local platform = require('utils.platform')()
local colors = require('colors.custom')

-- Seeding random numbers before generating for use
-- Known issue with lua math library
-- see: https://stackoverflow.com/questions/20154991/generating-uniform-random-numbers-in-lua
math.randomseed(os.time())
math.random()
math.random()
math.random()

local PATH_SEP = platform.is_win and '\\' or '/'
local GLOB_PATTERN = '*.{jpg,jpeg,png,gif,bmp,ico,tiff,pnm,dds,tga}'

---@class BackDrops
---@field current_idx number index of current image
---@field files string[] background images
---@field focus_color string background color when in focus mode. Default is `colors.custom.background`
---@field focus_on boolean focus mode on or off
local BackDrops = {}
BackDrops.__index = BackDrops

--- Initialise backdrop controller
---@private
function BackDrops:init()
   local inital = {
      current_idx = 1,
      files = {},
      focus_color = colors.background,
      focus_on = false,
   }
   local backdrops = setmetatable(inital, self)
   wezterm.GLOBAL.background = nil
   return backdrops
end

---MUST BE RUN BEFORE ALL OTHER `BackDrops` functions
---Sets the `files` after instantiating `BackDrops`.
---
--- INFO:
---   During the initial load of the config, this function can only invoked in `wezterm.lua`.
---   WezTerm's fs utility `glob` (used in this function) works by running on a spawned child process.
---   This throws a coroutine error if the function is invoked in outside of `wezterm.lua` in the -
---   initial load of the Terminal config.
function BackDrops:set_files()
  local base_path = wezterm.config_dir .. PATH_SEP .. 'backdrops'
  local all_files = {}

  -- Helper to join and normalize paths
  local function join(...)
    return table.concat({...}, PATH_SEP)
  end

  if pcall(function() wezterm.read_dir(base_path) end) then
   local entries = wezterm.read_dir(base_path)
   for _, entry in ipairs(entries) do
      local ok = pcall(function()
         wezterm.read_dir(entry) -- just to test if it's a directory
      end)

      if ok then
         -- entry is a directory
         local sub_files = wezterm.glob(entry .. PATH_SEP .. GLOB_PATTERN)
         for _, f in ipairs(sub_files) do
         table.insert(all_files, f)
         end
      elseif entry:match('%.%a+$') then
         -- image file directly in `backdrops/`
         if entry:match(GLOB_PATTERN:gsub('[{}]', ''):gsub(',', '|')) then
         table.insert(all_files, entry)
         end
      end
   end
  else
   wezterm.log_info("'backdrops' directory not found")
  end

  self.files = all_files
  wezterm.GLOBAL.background = self.files[1]
  return self
end


---Override the default `focus_color`
---Default `focus_color` is `colors.custom.background`
---@param focus_color string background color when in focus mode
function BackDrops:set_focus(focus_color)
   self.focus_color = focus_color
   return self
end

---Override the current window options for background
---@private
---@param window any WezTerm Window see: https://wezfurlong.org/wezterm/config/lua/window/index.html
function BackDrops:_set_opt(window)
   local opts = {
      background = {
         {
            source = { File = wezterm.GLOBAL.background },
            horizontal_align = 'Center',
         },
         {
            source = { Color = colors.background },
            height = '120%',
            width = '120%',
            vertical_offset = '-10%',
            horizontal_offset = '-10%',
            opacity = 0.96,
         },
      },
   }
   window:set_config_overrides(opts)
end

---Override the current window options for background with focus color
---@private
---@param window any WezTerm Window see: https://wezfurlong.org/wezterm/config/lua/window/index.html
function BackDrops:_set_focus_opt(window)
   local opts = {
      background = {
         {
            source = { Color = self.focus_color },
            height = '120%',
            width = '120%',
            vertical_offset = '-10%',
            horizontal_offset = '-10%',
            opacity = 1,
         },
      },
   }
   window:set_config_overrides(opts)
end

---Convert the `files` array to a table of `InputSelector` choices
---see: https://wezfurlong.org/wezterm/config/lua/keyassignment/InputSelector.html
function BackDrops:choices()
  local choices = {}
  local base = wezterm.config_dir .. PATH_SEP .. 'backdrops' .. PATH_SEP
  for idx, file in ipairs(self.files) do
    local rel_path = file:sub(#base + 1) -- strip base path
    table.insert(choices, {
      id = tostring(idx),
      label = rel_path,
    })
  end
  return choices
end

---Select a random file and redefine the global `wezterm.GLOBAL.background` variable
---Pass in `Window` object to override the current window options
---@param window any? WezTerm `Window` see: https://wezfurlong.org/wezterm/config/lua/window/index.html
function BackDrops:random(window)
   self.current_idx = math.random(#self.files)
   wezterm.GLOBAL.background = self.files[self.current_idx]

   if window ~= nil then
      self:_set_opt(window)
   end
end

---Cycle the loaded `files` and select the next background
---@param window any WezTerm `Window` see: https://wezfurlong.org/wezterm/config/lua/window/index.html
function BackDrops:cycle_forward(window)
   if self.current_idx == #self.files then
      self.current_idx = 1
   else
      self.current_idx = self.current_idx + 1
   end
   wezterm.GLOBAL.background = self.files[self.current_idx]
   self:_set_opt(window)
end

---Cycle the loaded `files` and select the previous background
---@param window any WezTerm `Window` see: https://wezfurlong.org/wezterm/config/lua/window/index.html
function BackDrops:cycle_back(window)
   if self.current_idx == 1 then
      self.current_idx = #self.files
   else
      self.current_idx = self.current_idx - 1
   end
   wezterm.GLOBAL.background = self.files[self.current_idx]
   self:_set_opt(window)
end

---Set a specific background from the `files` array
---@param window any WezTerm `Window` see: https://wezfurlong.org/wezterm/config/lua/window/index.html
---@param idx number index of the `files` array
function BackDrops:set_img(window, idx)
   if idx > #self.files or idx < 0 then
      wezterm.log_error('Index out of range')
      return
   end

   self.current_idx = idx
   wezterm.GLOBAL.background = self.files[self.current_idx]
   self:_set_opt(window)
end

---Toggle the focus mode
---@param window any WezTerm `Window` see: https://wezfurlong.org/wezterm/config/lua/window/index.html
function BackDrops:toggle_focus(window)
   if self.focus_on then
      self:set_img(window, self.current_idx)
      self.focus_on = false
   else
      self:_set_focus_opt(window)
      self.focus_on = true
   end
end

local instance = BackDrops:init()
function BackDrops:list_directories(window)
  local base_path = wezterm.config_dir .. PATH_SEP .. 'backdrops'
  local dirs = {}

  for _, entry in ipairs(wezterm.read_dir(base_path)) do
    if pcall(wezterm.read_dir, entry) then
      local label = entry:sub(#base_path + 2) -- relative dir name
      table.insert(dirs, {
        id = label,
        label = label,
      })
    end
  end

  window:perform_action(wezterm.action.InputSelector {
    action = wezterm.action_callback(function(win, _pane, selected)
      if selected then
        local full_path = base_path .. PATH_SEP .. selected
        self:list_images_in(win, full_path)
      end
    end),
    title = "Choose a folder",
    choices = dirs,
  }, window:active_pane())
end

function BackDrops:list_images_in(window, dir_path)
  local files = wezterm.glob(dir_path .. PATH_SEP .. GLOB_PATTERN)
  if #files == 0 then
    wezterm.log_info("No images found in: " .. dir_path)
    return
  end

  local choices = {}
  for _, f in ipairs(files) do
    local label = f:match("([^" .. PATH_SEP .. "]+)$")
    table.insert(choices, { id = f, label = label })
  end

  window:perform_action(wezterm.action.InputSelector {
    action = wezterm.action_callback(function(win, _pane, selected)
      if selected then
        self:set_file_path(win, selected)
      end
    end),
    title = "Choose an image",
    choices = choices,
  }, window:active_pane())
end

function BackDrops:set_file_path(window, path)
  wezterm.GLOBAL.background = path
  self:_set_opt(window)
end

return instance
