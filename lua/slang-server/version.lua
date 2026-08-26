local M = {}

M.NAME = "slang-server.nvim"
M.VERSION = "0.2.0"

---@param value string?
---@return integer?, integer?, integer?
function M.parse(value)
   if not value then
      return nil, nil, nil
   end

   value = value:match("^%s*(.-)%s*$")
   if value:sub(1, 1) == "v" then
      value = value:sub(2)
   end

   local major, minor, patch, suffix = value:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
   if not major or (suffix ~= "" and suffix:sub(1, 1) ~= "+" and suffix:sub(1, 1) ~= "-") then
      return nil, nil, nil
   end
   return tonumber(major), tonumber(minor), tonumber(patch)
end

---@param have string?
---@param want string?
---@return boolean?
function M.major_minor_at_least(have, want)
   local hmajor, hminor = M.parse(have)
   local wmajor, wminor = M.parse(want)
   if not hmajor or not wmajor then
      return nil
   end
   return hmajor > wmajor or (hmajor == wmajor and hminor >= wminor)
end

return M
