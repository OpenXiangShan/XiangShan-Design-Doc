local variables = {}

function get_variables (meta)
  if (meta.replace_variables) then
    for var_name, value in pairs(meta.replace_variables) do
      variables["{{" .. var_name .. "}}"] = {table.unpack(value)}
    end
  end
end

function replace_variables (el)
  if variables[el.text] then
    return pandoc.Span(variables[el.text])
  end
  return el
end

return {{Meta = get_variables}, {Str = replace_variables}}
